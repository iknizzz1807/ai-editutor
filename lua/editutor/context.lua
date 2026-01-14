-- editutor/context.lua
-- Context extraction for tutor queries using Tree-sitter and LSP

local M = {}

local config = require("editutor.config")
local lsp_context = require("editutor.lsp_context")

---@class CodeContext
---@field language string Programming language
---@field filepath string Full file path
---@field filename string Just the filename
---@field filetype string Vim filetype
---@field surrounding_code string Code around the question
---@field current_function string|nil Current function name
---@field imports string|nil Import statements
---@field question_line number Line number of the question

---Get the current function name using Tree-sitter
---@param bufnr number Buffer number
---@param line number Line number (1-indexed)
---@return string|nil function_name
local function get_current_function(bufnr, line)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local root = tree:root()

  -- Convert to 0-indexed for Tree-sitter
  local row = line - 1

  -- Try to find function at this position
  local node = root:named_descendant_for_range(row, 0, row, 0)

  while node do
    local node_type = node:type()
    -- Check for various function types across languages
    if
      node_type == "function_definition"
      or node_type == "function_declaration"
      or node_type == "method_definition"
      or node_type == "method_declaration"
      or node_type == "function_item" -- Rust
      or node_type == "func_literal" -- Go
      or node_type == "arrow_function"
      or node_type == "function_expression"
    then
      -- Try to get the function name
      for child in node:iter_children() do
        if child:type() == "identifier" or child:type() == "name" or child:type() == "property_identifier" then
          return vim.treesitter.get_node_text(child, bufnr)
        end
      end
      break
    end
    node = node:parent()
  end

  return nil
end

---Get import statements from the buffer
---@param bufnr number Buffer number
---@return string|nil imports
local function get_imports(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end

  local lang = parser:lang()
  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local root = tree:root()

  -- Query patterns for different languages
  local import_patterns = {
    python = "(import_statement) @import (import_from_statement) @import",
    javascript = "(import_statement) @import",
    typescript = "(import_statement) @import",
    go = "(import_declaration) @import",
    rust = "(use_declaration) @import",
    lua = "(function_call name: (identifier) @fn (#eq? @fn \"require\")) @import",
  }

  local pattern = import_patterns[lang]
  if not pattern then
    return nil
  end

  local query_ok, query = pcall(vim.treesitter.query.parse, lang, pattern)
  if not query_ok or not query then
    return nil
  end

  local imports = {}
  for _, node in query:iter_captures(root, bufnr) do
    local text = vim.treesitter.get_node_text(node, bufnr)
    table.insert(imports, text)
  end

  if #imports > 0 then
    return table.concat(imports, "\n")
  end

  return nil
end

---Get surrounding code context
---@param bufnr number Buffer number
---@param center_line number Center line (1-indexed)
---@param context_lines number Number of lines before and after
---@return string code
---@return number start_line
---@return number end_line
local function get_surrounding_code(bufnr, center_line, context_lines)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  local start_line = math.max(1, center_line - context_lines)
  local end_line = math.min(total_lines, center_line + context_lines)

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  -- Add line numbers for context
  local numbered_lines = {}
  for i, line in ipairs(lines) do
    local actual_line = start_line + i - 1
    local prefix = actual_line == center_line and ">>> " or "    "
    table.insert(numbered_lines, string.format("%s%3d: %s", prefix, actual_line, line))
  end

  return table.concat(numbered_lines, "\n"), start_line, end_line
end

---Extract full context for a mentor query
---@param bufnr? number Buffer number
---@param query_line? number Line number of the query
---@return CodeContext context
function M.extract(bufnr, query_line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  query_line = query_line or vim.api.nvim_win_get_cursor(0)[1]

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filename = vim.fn.fnamemodify(filepath, ":t")
  local filetype = vim.bo[bufnr].filetype

  -- Get language from Tree-sitter or fallback to filetype
  local language = filetype
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if ok and parser then
    language = parser:lang()
  end

  local context_lines = config.options.context_lines
  local surrounding_code, _, _ = get_surrounding_code(bufnr, query_line, context_lines)

  local imports = nil
  if config.options.include_imports then
    imports = get_imports(bufnr)
  end

  local current_function = get_current_function(bufnr, query_line)

  return {
    language = language,
    filepath = filepath,
    filename = filename,
    filetype = filetype,
    surrounding_code = surrounding_code,
    current_function = current_function,
    imports = imports,
    question_line = query_line,
  }
end

---Format context for LLM prompt (basic, without LSP)
---@param context CodeContext
---@return string formatted
function M.format_for_prompt(context)
  local parts = {}

  table.insert(parts, string.format("Language: %s", context.language))
  table.insert(parts, string.format("File: %s", context.filename))

  if context.current_function then
    table.insert(parts, string.format("Current function: %s", context.current_function))
  end

  if context.imports then
    table.insert(parts, "\nImports:")
    table.insert(parts, "```" .. context.language)
    table.insert(parts, context.imports)
    table.insert(parts, "```")
  end

  table.insert(parts, "\nCode context (>>> marks the question line):")
  table.insert(parts, "```" .. context.language)
  table.insert(parts, context.surrounding_code)
  table.insert(parts, "```")

  return table.concat(parts, "\n")
end

-- =============================================================================
-- LSP-Enhanced Context Functions
-- =============================================================================

---Check if LSP is available
---@return boolean
function M.has_lsp()
  return lsp_context.is_available()
end

---Extract context with LSP support (async)
---Includes external definitions from project files
---@param callback function Callback(formatted_context, has_lsp)
---@param opts? table Options override
function M.extract_with_lsp(callback, opts)
  opts = opts or {}

  local context_opts = {
    lines_around_cursor = opts.lines_around_cursor or config.options.context.lines_around_cursor or 100,
    external_context_lines = opts.external_context_lines or config.options.context.external_context_lines or 30,
    max_external_symbols = opts.max_external_symbols or config.options.context.max_external_symbols or 20,
  }

  lsp_context.get_context(function(ctx)
    local formatted = M.format_lsp_context(ctx)
    callback(formatted, ctx.has_lsp)
  end, context_opts)
end

---Format LSP context for LLM prompt
---@param ctx table LSP context from lsp_context.get_context
---@return string formatted
function M.format_lsp_context(ctx)
  local parts = {}

  -- Detect language from filepath
  local ext = ctx.current.filepath:match("%.(%w+)$") or "unknown"
  local lang_map = {
    lua = "lua", py = "python", js = "javascript", ts = "typescript",
    tsx = "tsx", jsx = "jsx", go = "go", rs = "rust", rb = "ruby",
    java = "java", c = "c", cpp = "cpp", h = "c", hpp = "cpp",
  }
  local language = lang_map[ext] or ext

  -- Project root for relative paths
  local project_root = lsp_context.get_project_root()

  -- Header
  local relative_path = ctx.current.filepath:gsub(project_root .. "/", "")
  table.insert(parts, string.format("Language: %s", language))
  table.insert(parts, string.format("File: %s", relative_path))
  table.insert(parts, "")

  -- Current file context
  table.insert(parts, string.format("=== Current Code (lines %d-%d, cursor at line %d) ===",
    ctx.current.start_line + 1,
    ctx.current.end_line + 1,
    ctx.current.cursor_line + 1
  ))
  table.insert(parts, "```" .. language)
  table.insert(parts, ctx.current.content)
  table.insert(parts, "```")
  table.insert(parts, "")

  -- External definitions
  if ctx.external and #ctx.external > 0 then
    table.insert(parts, string.format("=== Related Definitions from Project (%d files) ===", #ctx.external))
    table.insert(parts, "")

    for _, def in ipairs(ctx.external) do
      local def_relative = def.filepath:gsub(project_root .. "/", "")
      local def_ext = def.filepath:match("%.(%w+)$") or ext
      local def_lang = lang_map[def_ext] or def_ext

      table.insert(parts, string.format("--- %s (lines %d-%d, defines: %s) ---",
        def_relative,
        def.start_line + 1,
        def.end_line + 1,
        def.name
      ))
      table.insert(parts, "```" .. def_lang)
      table.insert(parts, def.content)
      table.insert(parts, "```")
      table.insert(parts, "")
    end
  end

  -- LSP status note
  if not ctx.has_lsp then
    table.insert(parts, "[Note: LSP not available - showing only current file context]")
    table.insert(parts, "[Tip: Setup LSP for your language to get better context from related files]")
    table.insert(parts, "")
  end

  return table.concat(parts, "\n")
end

return M
