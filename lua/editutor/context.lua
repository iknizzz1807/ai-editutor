-- editutor/context.lua
-- Context extraction for ai-editutor v3.0
-- Simplified: no question_line marking, just gather project context

local M = {}

local config = require("editutor.config")
local lsp_context = require("editutor.lsp_context")
local project_scanner = require("editutor.project_scanner")
local import_graph = require("editutor.import_graph")
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
-- Adaptive Context (for large projects)
-- =============================================================================

---Read file content with optional max lines
---@param filepath string
---@param max_lines? number
---@return string|nil content
---@return number line_count
---@return boolean is_truncated
local function read_file_content(filepath, max_lines)
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return nil, 0, false
  end

  local line_count = #lines
  local is_truncated = false

  if max_lines and line_count > max_lines then
    lines = vim.list_slice(lines, 1, max_lines)
    is_truncated = true
  end

  return table.concat(lines, "\n"), line_count, is_truncated
end

---Build adaptive context for large projects (simplified)
---@param current_file string Path to current file
---@param callback function Callback(formatted_context, metadata)
function M.build_adaptive_context(current_file, callback)
  local project_root = project_scanner.get_project_root(current_file)
  local root_name = vim.fn.fnamemodify(project_root, ":t")
  local budget = M.get_token_budget()

  local function get_display_path(filepath)
    if filepath:sub(1, #project_root) == project_root then
      return root_name .. "/" .. filepath:sub(#project_root + 2)
    end
    return root_name .. "/" .. vim.fn.fnamemodify(filepath, ":t")
  end

  local display_current = get_display_path(current_file)

  -- Get project tree (cached)
  local scan_result = cache.get_project(project_root, function()
    return project_scanner.scan_project({ root = project_root })
  end)

  -- Track included files for deduplication
  local included_files = {}
  included_files[current_file] = true

  -- 1. Current file (always include, full content)
  local current_content, current_lines = read_file_content(current_file)
  if not current_content then
    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    current_content = table.concat(buf_lines, "\n")
    current_lines = #buf_lines
  end

  local ext = current_file:match("%.([^.]+)$") or ""
  local language = project_scanner.get_language_for_ext(ext)

  local parts = {}
  local files_metadata = {}

  -- Current file (contains the questions)
  table.insert(parts, "=== CURRENT FILE (contains questions) ===")
  table.insert(parts, string.format("// File: %s", display_current))
  table.insert(parts, "```" .. language)
  table.insert(parts, current_content)
  table.insert(parts, "```")
  table.insert(parts, "")

  table.insert(files_metadata, {
    path = display_current,
    lines = current_lines,
    source = "current",
    tokens = project_scanner.estimate_tokens(current_content),
  })

  -- 2. Import graph files
  local graph = import_graph.get_import_graph(current_file, project_root)

  if #graph.all > 0 then
    table.insert(parts, string.format("=== RELATED FILES (import graph: %d files) ===", #graph.all))
    table.insert(parts, "")

    for _, filepath in ipairs(graph.all) do
      included_files[filepath] = true

      local content, line_count, is_truncated = read_file_content(filepath, 1000)
      if content then
        local file_ext = filepath:match("%.([^.]+)$") or ""
        local file_lang = project_scanner.get_language_for_ext(file_ext)
        local file_display = get_display_path(filepath)

        local relationship = "imported"
        for _, out_path in ipairs(graph.outgoing) do
          if out_path == filepath then
            relationship = "imported by current"
            break
          end
        end
        for _, in_path in ipairs(graph.incoming) do
          if in_path == filepath then
            relationship = "imports current"
            break
          end
        end

        local status = is_truncated and string.format("truncated, %d total", line_count) or "full"
        table.insert(parts, string.format("// File: %s (%s, %s)", file_display, relationship, status))
        table.insert(parts, "```" .. file_lang)
        table.insert(parts, content)
        table.insert(parts, "```")
        table.insert(parts, "")

        table.insert(files_metadata, {
          path = file_display,
          lines = line_count,
          source = "import_graph",
          relationship = relationship,
          tokens = project_scanner.estimate_tokens(content),
        })
      end
    end
  end

  -- 3. LSP definitions (deduped)
  lsp_context.get_context(function(ctx)
    local lsp_files_added = 0

    if ctx.external and #ctx.external > 0 then
      local lsp_parts = {}

      for _, def in ipairs(ctx.external) do
        if not included_files[def.filepath] then
          included_files[def.filepath] = true
          lsp_files_added = lsp_files_added + 1

          local file_ext = def.filepath:match("%.([^.]+)$") or ""
          local file_lang = project_scanner.get_language_for_ext(file_ext)
          local file_display = get_display_path(def.filepath)

          local status = def.is_full_file and "full" or "truncated"
          table.insert(lsp_parts, string.format("// File: %s (LSP definition, %s)", file_display, status))
          table.insert(lsp_parts, "```" .. file_lang)
          table.insert(lsp_parts, def.content)
          table.insert(lsp_parts, "```")
          table.insert(lsp_parts, "")

          table.insert(files_metadata, {
            path = file_display,
            lines = def.line_count,
            source = "lsp",
            tokens = project_scanner.estimate_tokens(def.content),
          })
        end
      end

      if lsp_files_added > 0 then
        table.insert(parts, string.format("=== LSP DEFINITIONS (%d files) ===", lsp_files_added))
        table.insert(parts, "")
        for _, part in ipairs(lsp_parts) do
          table.insert(parts, part)
        end
      end
    end

    -- 4. Project tree
    table.insert(parts, "=== PROJECT STRUCTURE ===")
    table.insert(parts, "```")
    table.insert(parts, scan_result.tree_structure)
    table.insert(parts, "```")

    local formatted = table.concat(parts, "\n")
    local total_tokens = project_scanner.estimate_tokens(formatted)

    -- Check budget
    if total_tokens > budget then
      local error_metadata = {
        mode = "adaptive",
        error = "budget_exceeded",
        total_tokens = total_tokens,
        budget = budget,
        current_file = display_current,
        import_graph_files = #graph.all,
        lsp_files = lsp_files_added,
      }
      callback(nil, error_metadata)
      return
    end

    local metadata = {
      mode = "adaptive",
      current_file = display_current,
      current_lines = current_lines,
      project_root = project_root,
      import_graph = {
        outgoing = #graph.outgoing,
        incoming = #graph.incoming,
        total = #graph.all,
      },
      lsp_files = lsp_files_added,
      files_included = files_metadata,
      tree_structure_lines = #vim.split(scan_result.tree_structure, "\n"),
      total_tokens = total_tokens,
      budget = budget,
      within_budget = true,
      has_lsp = ctx.has_lsp,
    }

    callback(formatted, metadata)
  end, {
    max_external_files = 30,
    max_lines_per_file = 300,
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

return M
