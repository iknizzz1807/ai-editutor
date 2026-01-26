-- editutor/context.lua
-- Context extraction for ai-editutor v3.2
-- Smart backtracking strategy for large projects
-- Includes library API info extraction via LSP
-- v3.2: Uses async abstraction for cleaner parallel execution

local M = {}

local config = require("editutor.config")
local lsp_context = require("editutor.lsp_context")
local project_scanner = require("editutor.project_scanner")
local cache = require("editutor.cache")
local context_strategy = require("editutor.context_strategy")
local async = require("editutor.async")

-- =============================================================================
-- Token Budget
-- =============================================================================

local TOKEN_BUDGET = 25000 -- 25k tokens max
local LIBRARY_INFO_BUDGET = 2000 -- 2k tokens for library API info
local DIAGNOSTICS_BUDGET = 2000 -- 2k tokens for LSP diagnostics

---Get token budget from config or default
---@return number
function M.get_token_budget()
  return config.options.context and config.options.context.token_budget or TOKEN_BUDGET
end

---Get library info budget from config or default
---@return number
function M.get_library_info_budget()
  return config.options.context and config.options.context.library_info_budget or LIBRARY_INFO_BUDGET
end

---Get diagnostics budget from config or default
---@return number
function M.get_diagnostics_budget()
  return config.options.context and config.options.context.diagnostics_budget or DIAGNOSTICS_BUDGET
end

---Get library scan radius from config or default
---@return number
function M.get_library_scan_radius()
  return config.options.context and config.options.context.library_scan_radius or 50
end

-- =============================================================================
-- LSP Diagnostics
-- =============================================================================

local SEVERITY_NAMES = {
  [vim.diagnostic.severity.ERROR] = "ERROR",
  [vim.diagnostic.severity.WARN] = "WARNING",
  [vim.diagnostic.severity.INFO] = "INFO",
  [vim.diagnostic.severity.HINT] = "HINT",
}

---Extract LSP diagnostics for current buffer
---Prioritizes diagnostics near the question area
---@param bufnr number Buffer number
---@param question_lines? {min: number, max: number} Question line range (1-indexed)
---@param max_tokens? number Maximum tokens for diagnostics (default: 2000)
---@return string|nil formatted_diagnostics
---@return table metadata
function M.get_buffer_diagnostics(bufnr, question_lines, max_tokens)
  max_tokens = max_tokens or M.get_diagnostics_budget()
  local diagnostics = vim.diagnostic.get(bufnr)

  if #diagnostics == 0 then
    return nil, { count = 0 }
  end

  -- Filter to ERROR and WARNING only
  local filtered = vim.tbl_filter(function(d)
    return d.severity <= vim.diagnostic.severity.WARN
  end, diagnostics)

  if #filtered == 0 then
    return nil, { count = 0, total = #diagnostics, filtered_out = #diagnostics }
  end

  -- Calculate proximity to question for each diagnostic
  local q_center = nil
  if question_lines then
    q_center = (question_lines.min + question_lines.max) / 2
  end

  -- Sort by: proximity to question (if available), then severity, then line
  table.sort(filtered, function(a, b)
    if q_center then
      local dist_a = math.abs(a.lnum + 1 - q_center)
      local dist_b = math.abs(b.lnum + 1 - q_center)
      -- Prioritize diagnostics within ±50 lines of question
      local near_a = dist_a <= 50
      local near_b = dist_b <= 50
      if near_a ~= near_b then
        return near_a -- near ones first
      end
      if near_a and near_b and dist_a ~= dist_b then
        return dist_a < dist_b -- closer ones first among near
      end
    end
    -- Then by severity (errors first)
    if a.severity ~= b.severity then
      return a.severity < b.severity
    end
    return a.lnum < b.lnum
  end)

  -- Add diagnostics one by one until budget exhausted
  local parts = {}
  local included_count = 0

  for _, d in ipairs(filtered) do
    local sev = SEVERITY_NAMES[d.severity] or "UNKNOWN"
    local line = d.lnum + 1 -- 0-indexed to 1-indexed
    local msg = d.message:gsub("\n", " "):gsub("%s+", " ") -- Normalize whitespace
    local source = d.source and (" (" .. d.source .. ")") or ""
    local diag_line = string.format("[%s] Line %d%s: %s", sev, line, source, msg)

    -- Check budget before adding
    local test_parts = vim.list_slice(parts, 1)
    table.insert(test_parts, diag_line)
    local header = string.format("=== LSP DIAGNOSTICS (%d issues) ===\n\n", #test_parts)
    local test_tokens = project_scanner.estimate_tokens(header .. table.concat(test_parts, "\n"))

    if test_tokens > max_tokens then
      break -- Budget exhausted
    end

    table.insert(parts, diag_line)
    included_count = included_count + 1
  end

  if #parts == 0 then
    return nil, { count = 0, total = #diagnostics, filtered_out = #diagnostics }
  end

  -- Build final output
  local header
  if included_count < #filtered then
    header = string.format("=== LSP DIAGNOSTICS (%d of %d issues) ===", included_count, #filtered)
  else
    header = string.format("=== LSP DIAGNOSTICS (%d issues) ===", included_count)
  end

  local formatted = header .. "\n\n" .. table.concat(parts, "\n")
  local tokens = project_scanner.estimate_tokens(formatted)

  return formatted, {
    count = included_count,
    total = #diagnostics,
    tokens = tokens,
    original_filtered = #filtered,
  }
end

-- =============================================================================
-- Context Mode Detection
-- =============================================================================

---@class ContextMode
---@field mode string "full_project"|"adaptive"
---@field project_tokens number Estimated project tokens
---@field budget number Token budget

---Determine which context mode to use
---@param project_root? string
---@return ContextMode
function M.detect_mode(project_root)
  project_root = project_root or project_scanner.get_project_root()
  local budget = M.get_token_budget()

  -- Use cache for project scan
  local scan_result = cache.get_project(project_root, function()
    return project_scanner.scan_project({ root = project_root })
  end)

  local project_tokens = scan_result.total_tokens

  if project_tokens <= budget then
    return {
      mode = "full_project",
      project_tokens = project_tokens,
      budget = budget,
    }
  else
    return {
      mode = "adaptive",
      project_tokens = project_tokens,
      budget = budget,
    }
  end
end

-- =============================================================================
-- Full Project Context
-- =============================================================================

---Build full project context (simplified - no question line marking)
---@param current_file string Path to current file
---@return string formatted_context
---@return table metadata
function M.build_full_project_context(current_file)
  local project_root = project_scanner.get_project_root(current_file)

  -- Scan project (cached)
  local scan_result = cache.get_project(project_root, function()
    return project_scanner.scan_project({ root = project_root })
  end)

  -- Read all source files
  local project_source, source_metadata = project_scanner.read_all_sources(scan_result)

  -- Read current file
  local current_content = nil
  local current_lines = 0
  local ok, lines = pcall(vim.fn.readfile, current_file)
  if ok and lines then
    current_content = table.concat(lines, "\n")
    current_lines = #lines
  end

  -- Detect language
  local ext = current_file:match("%.(%w+)$") or ""
  local language = project_scanner.get_language_for_ext(ext)

  -- Build formatted context
  local parts = {}
  local root_name = vim.fn.fnamemodify(project_root, ":t")
  local relative_current
  if current_file:sub(1, #project_root) == project_root then
    relative_current = current_file:sub(#project_root + 2)
  else
    relative_current = vim.fn.fnamemodify(current_file, ":t")
  end
  local display_current = root_name .. "/" .. relative_current

  -- Current file first (contains the questions)
  table.insert(parts, "=== CURRENT FILE (contains questions) ===")
  table.insert(parts, string.format("// File: %s", display_current))
  table.insert(parts, "```" .. language)
  if current_content then
    table.insert(parts, current_content)
  end
  table.insert(parts, "```")
  table.insert(parts, "")

  -- Project tree structure
  table.insert(parts, "=== PROJECT STRUCTURE ===")
  table.insert(parts, "```")
  table.insert(parts, scan_result.tree_structure)
  table.insert(parts, "```")
  table.insert(parts, "")

  -- All other project source files
  table.insert(parts, "=== OTHER PROJECT FILES ===")
  table.insert(parts, project_source)

  local formatted = table.concat(parts, "\n")
  local total_tokens = project_scanner.estimate_tokens(formatted)

  local metadata = {
    mode = "full_project",
    current_file = display_current,
    current_lines = current_lines,
    project_root = project_root,
    files_included = source_metadata.files_included,
    tree_structure_lines = #vim.split(scan_result.tree_structure, "\n"),
    total_tokens = total_tokens,
    budget = M.get_token_budget(),
    within_budget = total_tokens <= M.get_token_budget(),
  }

  return formatted, metadata
end

-- =============================================================================
-- Adaptive Context (for large projects) - v3.1 with smart backtracking
-- =============================================================================

---Build adaptive context for large projects (async version)
---Must be called from within an async context
---@param current_file string Path to current file
---@param opts? table {question_lines?: {min: number, max: number}}
---@return string|nil context, table metadata
function M.build_adaptive_context_async(current_file, opts)
  opts = opts or {}
  -- Reserve space for library info and diagnostics (added after strategy returns)
  local code_budget = M.get_token_budget() - M.get_library_info_budget() - M.get_diagnostics_budget()

  -- Call async version directly (no nested async.run)
  local context, metadata = context_strategy.build_context_with_strategy_async(current_file, {
    budget = code_budget,
    question_lines = opts.question_lines,
  })

  -- Add budget info to metadata (report total budget, not just code budget)
  metadata = metadata or {}
  metadata.budget = M.get_token_budget()
  metadata.code_budget = code_budget

  if context then
    return context, metadata
  else
    return nil, {
      mode = "adaptive",
      error = "strategy_failed",
      budget = M.get_token_budget(),
      details = metadata,
    }
  end
end

-- =============================================================================
-- Library Info Extraction
-- =============================================================================

---Extract library API info for identifiers (async version)
---Must be called from within an async context
---@param bufnr number
---@param questions table[] List of pending questions with block_start, block_end
---@return string formatted_text, table metadata
function M.extract_library_info_async(bufnr, questions)
  local ok, lsp_library = pcall(require, "editutor.lsp_library")
  if not ok then
    return "", { error = "lsp_library module not found" }
  end

  -- Configure budget
  lsp_library.config.max_tokens = M.get_library_info_budget()
  lsp_library.config.scan_radius = M.get_library_scan_radius()

  -- Find question range
  local min_line = math.huge
  local max_line = 0
  local all_question_text = {}

  for _, q in ipairs(questions) do
    if q.block_start then
      min_line = math.min(min_line, q.block_start - 1)
    end
    if q.block_end then
      max_line = math.max(max_line, q.block_end - 1)
    end
    if q.question then
      table.insert(all_question_text, q.question)
    end
  end

  if min_line == math.huge then min_line = 0 end
  if max_line == 0 then max_line = vim.api.nvim_buf_line_count(bufnr) - 1 end

  local combined_question_text = table.concat(all_question_text, "\n")

  -- Use async version directly
  local result = lsp_library.extract_library_info_async(bufnr, min_line, max_line, combined_question_text)
  return lsp_library.format_for_prompt(result)
end

-- =============================================================================
-- Main Entry Point
-- =============================================================================

---Extract context based on project size (async version)
---Must be called from within an async context
---@param opts? table {current_file?: string, questions?: table[], timeout?: number}
---@return string formatted_context, table metadata
function M.extract_async(opts)
  opts = opts or {}
  local current_file = opts.current_file or vim.api.nvim_buf_get_name(0)
  local questions = opts.questions or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local overall_timeout = opts.timeout or 45000

  local project_root = project_scanner.get_project_root(current_file)
  local mode_info = M.detect_mode(project_root)

  -- Compute question line range for truncation if needed
  local question_lines = nil
  if questions and #questions > 0 then
    local min_line = math.huge
    local max_line = 0
    for _, q in ipairs(questions) do
      if q.block_start then min_line = math.min(min_line, q.block_start) end
      if q.block_end then max_line = math.max(max_line, q.block_end) end
    end
    if min_line < math.huge and max_line > 0 then
      question_lines = { min = min_line, max = max_line }
    end
  end

  -- Build parallel tasks
  local tasks = {}

  -- Task 1: Extract code context
  table.insert(tasks, function()
    if mode_info.mode == "full_project" then
      return { M.build_full_project_context(current_file) }
    else
      local ctx, meta = M.build_adaptive_context_async(current_file, { question_lines = question_lines })
      return { ctx, meta }
    end
  end)

  -- Task 2: Extract library info
  table.insert(tasks, function()
    if #questions > 0 then
      local info, meta = M.extract_library_info_async(bufnr, questions)
      return { info, meta }
    else
      return { "", { skipped = "no_questions" } }
    end
  end)

  -- Execute in parallel with timeout
  local results, timed_out, async_err = async.with_timeout(function()
    return async.all(tasks)
  end, overall_timeout, {})

  -- Extract results
  local code_context, code_metadata
  local library_info, library_metadata

  if timed_out then
    code_context = ""
    code_metadata = { mode = mode_info.mode, timeout = true, warning = "Context extraction timeout" }
    library_info = ""
    library_metadata = {}
  elseif async_err then
    code_context = ""
    code_metadata = { mode = mode_info.mode, error = async_err, warning = "Context extraction error" }
    library_info = ""
    library_metadata = {}
  else
    -- Results from async.all are wrapped: {{result1, result2}, {result1, result2}}
    -- Validate structure before accessing
    local code_result = {}
    local lib_result = {}

    if type(results) == "table" and results[1] and type(results[1][1]) == "table" then
      code_result = results[1][1]
    end
    if type(results) == "table" and results[2] and type(results[2][1]) == "table" then
      lib_result = results[2][1]
    end

    code_context = code_result[1] or ""
    code_metadata = code_result[2] or { mode = mode_info.mode }
    library_info = lib_result[1] or ""
    library_metadata = lib_result[2] or {}
  end

  -- Combine code context and library info
  local final_context = code_context or ""
  if library_info and library_info ~= "" then
    final_context = final_context .. "\n\n" .. library_info
  end

  -- Add LSP diagnostics (prioritize near question, cap at 2k tokens)
  local diagnostics_text, diagnostics_metadata = M.get_buffer_diagnostics(bufnr, question_lines)
  if diagnostics_text then
    final_context = final_context .. "\n\n" .. diagnostics_text
  end

  -- Merge metadata
  local final_metadata = code_metadata or {}
  final_metadata.library_info = library_metadata or {}
  final_metadata.diagnostics = diagnostics_metadata or {}

  -- Fix: Get total_tokens from token_usage if not set directly
  local code_tokens = final_metadata.total_tokens
    or (final_metadata.token_usage and final_metadata.token_usage.total)
    or 0
  final_metadata.total_tokens = code_tokens

  if library_metadata and library_metadata.tokens then
    final_metadata.total_tokens = final_metadata.total_tokens + library_metadata.tokens
  end

  if diagnostics_metadata and diagnostics_metadata.tokens then
    final_metadata.total_tokens = final_metadata.total_tokens + diagnostics_metadata.tokens
  end

  return final_context, final_metadata
end

---Extract context based on project size
---Also extracts library API info if questions are provided
---@param callback function Callback(formatted_context, metadata)
---@param opts? table {current_file?: string, questions?: table[], timeout?: number}
function M.extract(callback, opts)
  async.run(function()
    local context, metadata = M.extract_async(opts)
    async.scheduler()
    callback(context, metadata)
  end)
end

-- =============================================================================
-- Utility Functions
-- =============================================================================

function M.has_lsp()
  return lsp_context.is_available()
end

function M.get_project_root()
  return project_scanner.get_project_root()
end

function M.estimate_tokens(text)
  return project_scanner.estimate_tokens(text)
end

---Get available strategy levels (for debugging/display)
---@return table[]
function M.get_strategy_levels()
  return context_strategy.get_levels()
end

---Estimate which strategy level would be used
---@param current_file? string
---@return string level_name
---@return table estimation
function M.estimate_strategy_level(current_file)
  current_file = current_file or vim.api.nvim_buf_get_name(0)
  return context_strategy.estimate_level(current_file, M.get_token_budget())
end

return M
