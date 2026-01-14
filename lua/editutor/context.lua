-- editutor/context.lua
-- Context extraction for tutor queries using Tree-sitter

local M = {}

local config = require("editutor.config")

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

---Format context for LLM prompt
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

return M
