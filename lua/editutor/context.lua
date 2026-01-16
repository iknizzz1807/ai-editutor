-- editutor/context.lua
-- Context extraction for ai-editutor
-- New flow: Full project if < 20k tokens, otherwise LSP definitions

local M = {}

local config = require("editutor.config")
local lsp_context = require("editutor.lsp_context")
local project_scanner = require("editutor.project_scanner")
local cache = require("editutor.cache")

-- =============================================================================
-- Token Budget
-- =============================================================================

local TOKEN_BUDGET = 20000 -- 20k tokens max

---Get token budget from config or default
---@return number
function M.get_token_budget()
  return config.options.context and config.options.context.token_budget or TOKEN_BUDGET
end

-- =============================================================================
-- Context Mode Detection
-- =============================================================================

---@class ContextMode
---@field mode string "full_project"|"lsp_selective"
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
      mode = "lsp_selective",
      project_tokens = project_tokens,
      budget = budget,
    }
  end
end

-- =============================================================================
-- Full Project Context
-- =============================================================================

---@class FullProjectContext
---@field mode string "full_project"
---@field current_file table {path, content, lines}
---@field project_source string All source files content
---@field tree_structure string Project tree
---@field metadata table {files_included, total_tokens, etc}

---Build full project context
---@param current_file string Path to current file
---@param question_line number Line number of question
---@return string formatted_context
---@return table metadata
function M.build_full_project_context(current_file, question_line)
  local project_root = project_scanner.get_project_root()

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
  local relative_current = current_file:gsub(project_root .. "/", "")
  local display_current = root_name .. "/" .. relative_current

  -- Current file first (with question line marked)
  table.insert(parts, "=== CURRENT FILE (question location) ===")
  table.insert(parts, string.format("// File: %s (line %d is where the question was asked)", display_current, question_line))
  table.insert(parts, "```" .. language)
  if current_content then
    -- Add line numbers and mark question line
    local content_lines = vim.split(current_content, "\n")
    local numbered = {}
    for i, line in ipairs(content_lines) do
      local prefix = (i == question_line) and ">>> " or "    "
      table.insert(numbered, string.format("%s%4d: %s", prefix, i, line))
    end
    table.insert(parts, table.concat(numbered, "\n"))
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
    question_line = question_line,
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
-- LSP Selective Context
-- =============================================================================

---Build LSP-based selective context (for large projects)
---@param current_file string Path to current file
---@param question_line number Line number of question
---@param callback function Callback(formatted_context, metadata)
function M.build_lsp_context(current_file, question_line, callback)
  local project_root = project_scanner.get_project_root()
  local root_name = vim.fn.fnamemodify(project_root, ":t")
  local relative_current = current_file:gsub(project_root .. "/", "")
  local display_current = root_name .. "/" .. relative_current

  -- Get project tree (cached)
  local scan_result = cache.get_project(project_root, function()
    return project_scanner.scan_project({ root = project_root })
  end)

  -- Get LSP context (scans entire current file for definitions)
  lsp_context.get_context(function(ctx)
    local lsp_formatted, lsp_metadata = lsp_context.format_for_prompt(ctx)

    -- Build final context
    local parts = {}

    -- LSP context already includes current file with proper // File: format
    table.insert(parts, lsp_formatted)

    -- Project tree structure (always include)
    table.insert(parts, "=== PROJECT STRUCTURE ===")
    table.insert(parts, "```")
    table.insert(parts, scan_result.tree_structure)
    table.insert(parts, "```")

    local formatted = table.concat(parts, "\n")
    local total_tokens = project_scanner.estimate_tokens(formatted)

    local metadata = {
      mode = "lsp_selective",
      current_file = display_current,
      current_lines = lsp_metadata.current_lines,
      question_line = question_line,
      project_root = project_root,
      external_files = lsp_metadata.external_files,
      tree_structure_lines = #vim.split(scan_result.tree_structure, "\n"),
      total_tokens = total_tokens,
      budget = M.get_token_budget(),
      within_budget = total_tokens <= M.get_token_budget(),
      has_lsp = ctx.has_lsp,
    }

    callback(formatted, metadata)
  end, {
    max_external_files = 50,
    max_lines_per_file = 500,
  })
end

-- =============================================================================
-- Main Entry Point
-- =============================================================================

---Extract context based on project size
---Automatically chooses full_project or lsp_selective mode
---@param callback function Callback(formatted_context, metadata)
---@param opts? table {current_file?: string, question_line?: number}
function M.extract(callback, opts)
  opts = opts or {}
  local current_file = opts.current_file or vim.api.nvim_buf_get_name(0)
  local question_line = opts.question_line or vim.api.nvim_win_get_cursor(0)[1]

  local project_root = project_scanner.get_project_root()
  local mode_info = M.detect_mode(project_root)

  if mode_info.mode == "full_project" then
    -- Synchronous: full project context
    local formatted, metadata = M.build_full_project_context(current_file, question_line)
    callback(formatted, metadata)
  else
    -- Async: LSP-based selective context
    M.build_lsp_context(current_file, question_line, callback)
  end
end

-- =============================================================================
-- Utility Functions (backward compatibility)
-- =============================================================================

---Check if LSP is available
---@return boolean
function M.has_lsp()
  return lsp_context.is_available()
end

---Get project root
---@return string
function M.get_project_root()
  return project_scanner.get_project_root()
end

---Estimate tokens for text
---@param text string
---@return number
function M.estimate_tokens(text)
  return project_scanner.estimate_tokens(text)
end

return M
