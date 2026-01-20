-- editutor/context.lua
-- Context extraction for ai-editutor v3.1
-- Smart backtracking strategy for large projects
-- Simplified: no question_line marking, just gather project context

local M = {}

local config = require("editutor.config")
local lsp_context = require("editutor.lsp_context")
local project_scanner = require("editutor.project_scanner")
local cache = require("editutor.cache")
local context_strategy = require("editutor.context_strategy")

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
-- Main Entry Point
-- =============================================================================

---Extract context based on project size
---@param callback function Callback(formatted_context, metadata)
---@param opts? table {current_file?: string}
function M.extract(callback, opts)
  opts = opts or {}
  local current_file = opts.current_file or vim.api.nvim_buf_get_name(0)

  local project_root = project_scanner.get_project_root(current_file)
  local mode_info = M.detect_mode(project_root)

  if mode_info.mode == "full_project" then
    local formatted, metadata = M.build_full_project_context(current_file)
    callback(formatted, metadata)
  else
    M.build_adaptive_context(current_file, callback)
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
