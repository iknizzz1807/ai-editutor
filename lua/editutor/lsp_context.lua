-- editutor/lsp_context.lua
-- LSP-based context extraction for AI EduTutor
-- Extracts definitions and references from project files (not libraries)

local M = {}

-- Patterns to exclude (library/vendor paths)
M.exclude_patterns = {
  "node_modules",
  ".venv",
  "venv",
  "site%-packages",
  "vendor",
  "%.cargo/registry",
  "target/debug",
  "target/release",
  "/usr/",
  "/opt/",
  "%.local/lib/",
  "%.local/share/nvim",
  "%.luarocks/",
  "lib/lua/",
  "share/lua/",
}

-- Cache for LSP results (invalidated on buffer change)
M._cache = {}
M._cache_bufnr = nil

---Check if LSP is available for current buffer
---@return boolean
function M.is_available()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  return #clients > 0
end

---Get project root (git root or cwd)
---@return string
function M.get_project_root()
  -- Try git root first
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
  if git_root and git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    return git_root
  end
  -- Fallback to cwd
  return vim.fn.getcwd()
end

---Check if a file path is within the project (not a library)
---@param filepath string Absolute file path
---@return boolean
function M.is_project_file(filepath)
  if not filepath or filepath == "" then
    return false
  end

  -- Check against exclude patterns
  for _, pattern in ipairs(M.exclude_patterns) do
    if filepath:match(pattern) then
      return false
    end
  end

  -- Check if within project root
  local project_root = M.get_project_root()
  if filepath:sub(1, #project_root) == project_root then
    return true
  end

  return false
end

---Get lines around a position from a file
---@param filepath string File path
---@param line number 0-indexed line number
---@param context_lines number Lines to include above and below
---@return string|nil content, number|nil start_line, number|nil end_line
function M.get_lines_around(filepath, line, context_lines)
  context_lines = context_lines or 15

  -- Read file
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return nil
  end

  local total_lines = #lines
  local start_line = math.max(0, line - context_lines)
  local end_line = math.min(total_lines - 1, line + context_lines)

  local result = {}
  for i = start_line, end_line do
    table.insert(result, lines[i + 1]) -- Lua is 1-indexed
  end

  return table.concat(result, "\n"), start_line, end_line
end

---Get definition location for a symbol at position using LSP
---@param bufnr number Buffer number
---@param line number 0-indexed line
---@param col number 0-indexed column
---@param callback function Callback(locations) where locations is a list of {uri, range}
function M.get_definition(bufnr, line, col, callback)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = { line = line, character = col },
  }

  vim.lsp.buf_request(bufnr, "textDocument/definition", params, function(err, result)
    if err or not result then
      callback({})
      return
    end

    -- Normalize result (can be Location, Location[], or LocationLink[])
    local locations = {}
    if result.uri then
      -- Single Location
      table.insert(locations, result)
    elseif result.targetUri then
      -- Single LocationLink
      table.insert(locations, {
        uri = result.targetUri,
        range = result.targetSelectionRange or result.targetRange,
      })
    elseif type(result) == "table" then
      for _, loc in ipairs(result) do
        if loc.uri then
          table.insert(locations, loc)
        elseif loc.targetUri then
          table.insert(locations, {
            uri = loc.targetUri,
            range = loc.targetSelectionRange or loc.targetRange,
          })
        end
      end
    end

    callback(locations)
  end)
end

---Extract identifiers from lines using Tree-sitter
---@param bufnr number Buffer number
---@param start_line number Start line (0-indexed)
---@param end_line number End line (0-indexed)
---@return table List of {name, line, col} for each identifier
function M.extract_identifiers(bufnr, start_line, end_line)
  local identifiers = {}
  local seen = {}

  -- Get parser
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return identifiers
  end

  local tree = parser:parse()[1]
  if not tree then
    return identifiers
  end

  local root = tree:root()

  -- Query for identifiers (works for most languages)
  local lang = parser:lang()
  local query_string = "(identifier) @id"

  -- Some languages use different node types
  if lang == "lua" then
    query_string = "[(identifier) (dot_index_expression)] @id"
  elseif lang == "python" then
    query_string = "[(identifier) (attribute)] @id"
  elseif lang == "javascript" or lang == "typescript" or lang == "tsx" then
    query_string = "[(identifier) (property_identifier) (type_identifier)] @id"
  elseif lang == "go" then
    query_string = "[(identifier) (type_identifier) (field_identifier)] @id"
  elseif lang == "rust" then
    query_string = "[(identifier) (type_identifier) (field_identifier)] @id"
  end

  local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if not ok_query or not query then
    return identifiers
  end

  for id, node in query:iter_captures(root, bufnr, start_line, end_line + 1) do
    local node_start_row, node_start_col = node:start()

    -- Only include nodes in our range
    if node_start_row >= start_line and node_start_row <= end_line then
      local name = vim.treesitter.get_node_text(node, bufnr)

      -- Skip common built-ins and locals
      if name and #name > 1 and not M._is_builtin(name, lang) then
        local key = name .. ":" .. node_start_row .. ":" .. node_start_col
        if not seen[key] then
          seen[key] = true
          table.insert(identifiers, {
            name = name,
            line = node_start_row,
            col = node_start_col,
          })
        end
      end
    end
  end

  return identifiers
end

---Check if a name is a built-in (skip these)
---@param name string
---@param lang string
---@return boolean
function M._is_builtin(name, lang)
  -- Common built-ins across languages
  local common = {
    "true", "false", "nil", "null", "undefined", "None", "True", "False",
    "self", "this", "super", "cls",
    "if", "else", "for", "while", "return", "function", "local", "const", "let", "var",
    "import", "from", "export", "require", "module",
    "class", "struct", "enum", "interface", "type",
    "public", "private", "protected", "static",
    "async", "await", "yield",
    "try", "catch", "finally", "throw",
    "new", "delete", "typeof", "instanceof",
  }

  for _, builtin in ipairs(common) do
    if name == builtin then
      return true
    end
  end

  -- Language-specific built-ins
  if lang == "lua" then
    local lua_builtins = {
      "vim", "print", "pairs", "ipairs", "next", "type", "tostring", "tonumber",
      "string", "table", "math", "os", "io", "debug", "coroutine", "package",
      "error", "assert", "pcall", "xpcall", "select", "unpack", "rawget", "rawset",
      "setmetatable", "getmetatable", "require", "loadfile", "dofile",
      "_G", "_VERSION", "arg",
    }
    for _, builtin in ipairs(lua_builtins) do
      if name == builtin then
        return true
      end
    end
  elseif lang == "python" then
    local py_builtins = {
      "print", "len", "range", "str", "int", "float", "list", "dict", "set", "tuple",
      "bool", "bytes", "type", "object", "super", "property", "classmethod", "staticmethod",
      "open", "input", "map", "filter", "zip", "enumerate", "sorted", "reversed",
      "min", "max", "sum", "abs", "round", "pow", "divmod",
      "all", "any", "isinstance", "issubclass", "hasattr", "getattr", "setattr", "delattr",
      "id", "hash", "repr", "format", "ord", "chr", "hex", "oct", "bin",
      "Exception", "BaseException", "ValueError", "TypeError", "KeyError", "IndexError",
    }
    for _, builtin in ipairs(py_builtins) do
      if name == builtin then
        return true
      end
    end
  elseif lang == "javascript" or lang == "typescript" or lang == "tsx" then
    local js_builtins = {
      "console", "window", "document", "JSON", "Math", "Date", "Array", "Object",
      "String", "Number", "Boolean", "Symbol", "Map", "Set", "WeakMap", "WeakSet",
      "Promise", "Proxy", "Reflect", "Error", "TypeError", "ReferenceError",
      "parseInt", "parseFloat", "isNaN", "isFinite", "encodeURI", "decodeURI",
      "setTimeout", "setInterval", "clearTimeout", "clearInterval",
      "fetch", "Request", "Response", "Headers", "URL", "URLSearchParams",
      "Buffer", "process", "global", "module", "exports", "__dirname", "__filename",
    }
    for _, builtin in ipairs(js_builtins) do
      if name == builtin then
        return true
      end
    end
  end

  return false
end

---Get external definitions for identifiers in a range
---@param bufnr number Buffer number
---@param start_line number Start line (0-indexed)
---@param end_line number End line (0-indexed)
---@param callback function Callback(definitions) where definitions is a list of {name, filepath, content, start_line, end_line}
---@param opts? table Options {max_symbols?: number, context_lines?: number}
function M.get_external_definitions(bufnr, start_line, end_line, callback, opts)
  opts = opts or {}
  local max_symbols = opts.max_symbols or 20
  local context_lines = opts.context_lines or 15

  local current_file = vim.api.nvim_buf_get_name(bufnr)
  local identifiers = M.extract_identifiers(bufnr, start_line, end_line)

  -- Limit identifiers
  if #identifiers > max_symbols then
    identifiers = vim.list_slice(identifiers, 1, max_symbols)
  end

  local definitions = {}
  local seen_files = {}
  local pending = #identifiers
  local completed = 0

  if pending == 0 then
    callback({})
    return
  end

  for _, ident in ipairs(identifiers) do
    M.get_definition(bufnr, ident.line, ident.col, function(locations)
      completed = completed + 1

      for _, loc in ipairs(locations) do
        local filepath = vim.uri_to_fname(loc.uri)

        -- Skip if same file or already seen or not project file
        if filepath ~= current_file and not seen_files[filepath] and M.is_project_file(filepath) then
          seen_files[filepath] = true

          local def_line = loc.range and loc.range.start and loc.range.start.line or 0
          local content, content_start, content_end = M.get_lines_around(filepath, def_line, context_lines)

          if content then
            table.insert(definitions, {
              name = ident.name,
              filepath = filepath,
              content = content,
              start_line = content_start,
              end_line = content_end,
              definition_line = def_line,
            })
          end
        end
      end

      -- All done
      if completed >= pending then
        callback(definitions)
      end
    end)
  end
end

---Get full LSP context for current cursor position
---@param callback function Callback(context) where context is {current, external, has_lsp}
---@param opts? table Options from config
function M.get_context(callback, opts)
  opts = opts or {}
  local lines_around = opts.lines_around_cursor or 100
  local external_lines = opts.external_context_lines or 30
  local max_symbols = opts.max_external_symbols or 20

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1] - 1 -- 0-indexed
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  -- Calculate range around cursor
  local half = math.floor(lines_around / 2)
  local start_line = math.max(0, cursor_line - half)
  local end_line = math.min(total_lines - 1, cursor_line + half)

  -- Get current context
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
  local current_content = table.concat(current_lines, "\n")
  local current_file = vim.api.nvim_buf_get_name(bufnr)

  local context = {
    current = {
      filepath = current_file,
      content = current_content,
      start_line = start_line,
      end_line = end_line,
      cursor_line = cursor_line,
    },
    external = {},
    has_lsp = M.is_available(),
  }

  -- If no LSP, return just current context
  if not context.has_lsp then
    callback(context)
    return
  end

  -- Get external definitions
  M.get_external_definitions(bufnr, start_line, end_line, function(definitions)
    context.external = definitions
    callback(context)
  end, {
    max_symbols = max_symbols,
    context_lines = math.floor(external_lines / 2),
  })
end

---Format context for LLM prompt
---@param ctx table Context from get_context
---@return string Formatted context
function M.format_for_prompt(ctx)
  local parts = {}

  -- Current file context
  local relative_path = ctx.current.filepath:gsub(M.get_project_root() .. "/", "")
  table.insert(parts, string.format("=== Current File: %s (lines %d-%d) ===",
    relative_path,
    ctx.current.start_line + 1,
    ctx.current.end_line + 1
  ))
  table.insert(parts, "```")
  table.insert(parts, ctx.current.content)
  table.insert(parts, "```")
  table.insert(parts, "")

  -- External definitions
  if ctx.external and #ctx.external > 0 then
    table.insert(parts, "=== Related Definitions from Project ===")
    table.insert(parts, "")

    for _, def in ipairs(ctx.external) do
      local def_relative = def.filepath:gsub(M.get_project_root() .. "/", "")
      table.insert(parts, string.format("--- %s (lines %d-%d) ---",
        def_relative,
        def.start_line + 1,
        def.end_line + 1
      ))
      table.insert(parts, "```")
      table.insert(parts, def.content)
      table.insert(parts, "```")
      table.insert(parts, "")
    end
  end

  -- LSP status note
  if not ctx.has_lsp then
    table.insert(parts, "[Note: LSP not available - showing only current file context]")
    table.insert(parts, "")
  end

  return table.concat(parts, "\n")
end

---Clear cache (call on buffer change)
function M.clear_cache()
  M._cache = {}
  M._cache_bufnr = nil
end

return M
