-- editutor/context.lua
-- Context extraction for ai-editutor v3.1
-- Smart backtracking strategy for large projects
-- Includes library API info extraction via LSP

local M = {}

local config = require("editutor.config")
local lsp_context = require("editutor.lsp_context")
local project_scanner = require("editutor.project_scanner")
local cache = require("editutor.cache")
local context_strategy = require("editutor.context_strategy")

-- =============================================================================
-- Token Budget
-- =============================================================================

local TOKEN_BUDGET = 25000 -- 25k tokens max
local LIBRARY_INFO_BUDGET = 2000 -- 2k tokens for library API info

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

---Get library scan radius from config or default
---@return number
function M.get_library_scan_radius()
  return config.options.context and config.options.context.library_scan_radius or 50
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

---Build adaptive context for large projects using smart backtracking strategy
---@param current_file string Path to current file
---@param callback function Callback(formatted_context, metadata)
function M.build_adaptive_context(current_file, callback)
  local budget = M.get_token_budget()

  context_strategy.build_context_with_strategy(current_file, function(context, metadata)
    -- Add budget info to metadata
    metadata.budget = budget

    if context then
      callback(context, metadata)
    else
      -- Fallback: should never happen with new strategy, but just in case
      callback(nil, {
        mode = "adaptive",
        error = "strategy_failed",
        budget = budget,
        details = metadata,
      })
    end
  end, {
    budget = budget,
  })
end

-- =============================================================================
-- Library Info Extraction
-- =============================================================================

---Extract library API info for identifiers around question
---@param bufnr number
---@param questions table[] List of pending questions with block_start, block_end
---@param callback function Callback(library_info_text, metadata)
function M.extract_library_info(bufnr, questions, callback)
  -- Lazy load to avoid circular dependency
  local ok, lsp_library = pcall(require, "editutor.lsp_library")
  if not ok then
    callback("", { error = "lsp_library module not found" })
    return
  end

  -- Configure budget
  lsp_library.config.max_tokens = M.get_library_info_budget()
  lsp_library.config.scan_radius = M.get_library_scan_radius()

  -- Find question range (use first and last question to define scan area)
  local min_line = math.huge
  local max_line = 0
  local all_question_text = {}

  for _, q in ipairs(questions) do
    if q.block_start then
      min_line = math.min(min_line, q.block_start - 1) -- Convert to 0-indexed
    end
    if q.block_end then
      max_line = math.max(max_line, q.block_end - 1) -- Convert to 0-indexed
    end
    if q.question then
      table.insert(all_question_text, q.question)
    end
  end

  -- Handle case where no valid lines found
  if min_line == math.huge then
    min_line = 0
  end
  if max_line == 0 then
    max_line = vim.api.nvim_buf_line_count(bufnr) - 1
  end

  local combined_question_text = table.concat(all_question_text, "\n")

  -- Extract library info
  lsp_library.extract_library_info(bufnr, min_line, max_line, combined_question_text, function(result)
    local formatted, metadata = lsp_library.format_for_prompt(result)
    callback(formatted, metadata)
  end)
end

-- =============================================================================
-- Main Entry Point
-- =============================================================================

---Extract context based on project size
---Also extracts library API info if questions are provided
---@param callback function Callback(formatted_context, metadata)
---@param opts? table {current_file?: string, questions?: table[]}
function M.extract(callback, opts)
  opts = opts or {}
  local current_file = opts.current_file or vim.api.nvim_buf_get_name(0)
  local questions = opts.questions or {}
  local bufnr = vim.api.nvim_get_current_buf()

  local project_root = project_scanner.get_project_root(current_file)
  local mode_info = M.detect_mode(project_root)

  -- Track parallel extractions
  local code_context = nil
  local code_metadata = nil
  local library_info = nil
  local library_metadata = nil
  local pending = 2 -- Two parallel tasks

  local function check_complete()
    pending = pending - 1
    if pending > 0 then
      return
    end

    -- Combine code context and library info
    local final_context = code_context or ""
    if library_info and library_info ~= "" then
      final_context = final_context .. "\n\n" .. library_info
    end

    -- Merge metadata
    local final_metadata = code_metadata or {}
    final_metadata.library_info = library_metadata or {}
    if library_metadata and library_metadata.tokens then
      final_metadata.total_tokens = (final_metadata.total_tokens or 0) + library_metadata.tokens
    end

    callback(final_context, final_metadata)
  end

  -- Task 1: Extract code context
  if mode_info.mode == "full_project" then
    local formatted, metadata = M.build_full_project_context(current_file)
    code_context = formatted
    code_metadata = metadata
    check_complete()
  else
    M.build_adaptive_context(current_file, function(formatted, metadata)
      code_context = formatted
      code_metadata = metadata
      check_complete()
    end)
  end

  -- Task 2: Extract library info (parallel)
  if #questions > 0 then
    M.extract_library_info(bufnr, questions, function(info_text, info_metadata)
      library_info = info_text
      library_metadata = info_metadata
      check_complete()
    end)
  else
    -- No questions, skip library info
    library_info = ""
    library_metadata = { skipped = "no_questions" }
    check_complete()
  end
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
