-- editutor/lsp_context.lua
-- LSP-based context extraction for ai-editutor
-- Enhanced: scans ENTIRE current file for symbols, not just cursor position
-- Deduplicates definitions to avoid sending same content multiple times
-- v3.1: Uses semantic_chunking to extract only definitions, not full files
-- v3.2: Uses async abstraction for cleaner parallel execution

local M = {}

local project_scanner = require("editutor.project_scanner")
local semantic_chunking = require("editutor.semantic_chunking")
local async = require("editutor.async")

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

---Check if LSP is available for current buffer
---@return boolean
function M.is_available()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  return #clients > 0
end

---Get project root (git root or cwd)
---@param filepath? string File path to find project root for
---@return string
function M.get_project_root(filepath)
  return project_scanner.get_project_root(filepath)
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

  -- Check if within project root (use the filepath to detect project root)
  local project_root = M.get_project_root(filepath)
  if filepath:sub(1, #project_root) == project_root then
    return true
  end

  return false
end

---Read entire file content
---@param filepath string
---@return string|nil content
---@return number|nil line_count
function M.read_file(filepath)
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return nil, nil
  end
  return table.concat(lines, "\n"), #lines
end

---Get definition location for a symbol at position using LSP (async version)
---Must be called from within an async context (async.run)
---@param bufnr number Buffer number
---@param line number 0-indexed line
---@param col number 0-indexed column
---@param timeout_ms? number Optional timeout (default: 5000ms)
---@return table[] locations List of {uri, range}
function M.get_definition_async(bufnr, line, col, timeout_ms)
  return async.lsp_definition(bufnr, line, col, timeout_ms)
end

---Get definition location for a symbol at position using LSP (callback version)
---Extract ALL identifiers from entire file using Tree-sitter
---@param bufnr number Buffer number
---@return table List of {name, line, col} for each unique identifier
function M.extract_all_identifiers(bufnr)
  local identifiers = {}
  local seen_names = {} -- Dedup by name (we only need one occurrence per symbol)

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
  local lang = parser:lang()

  -- Query for identifiers (works for most languages)
  local query_string = "(identifier) @id"

  -- Language-specific queries for better coverage
  if lang == "lua" then
    query_string = "[(identifier) (dot_index_expression)] @id"
  elseif lang == "python" then
    query_string = "[(identifier) (attribute)] @id"
  elseif lang == "javascript" then
    query_string = "[(identifier) (property_identifier)] @id"
  elseif lang == "typescript" or lang == "tsx" then
    query_string = "[(identifier) (property_identifier) (type_identifier)] @id"
  elseif lang == "go" then
    query_string = "[(identifier) (type_identifier) (field_identifier)] @id"
  elseif lang == "rust" then
    query_string = "[(identifier) (type_identifier) (field_identifier)] @id"
  elseif lang == "c" then
    query_string = "[(identifier) (type_identifier) (field_identifier)] @id"
  elseif lang == "cpp" then
    query_string = "[(identifier) (type_identifier) (field_identifier) (namespace_identifier) (qualified_identifier)] @id"
  end

  local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if not ok_query or not query then
    return identifiers
  end

  -- Get total lines
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  for _, node in query:iter_captures(root, bufnr, 0, total_lines) do
    local node_start_row, node_start_col = node:start()
    local name = vim.treesitter.get_node_text(node, bufnr)

    -- Skip built-ins and already seen names
    if name and #name > 1 and not M._is_builtin(name, lang) and not seen_names[name] then
      seen_names[name] = true
      table.insert(identifiers, {
        name = name,
        line = node_start_row,
        col = node_start_col,
      })
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
    "and", "or", "not", "in", "is",
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
      "_G", "_VERSION", "arg", "M",
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
      "React", "useState", "useEffect", "useCallback", "useMemo", "useRef",
    }
    for _, builtin in ipairs(js_builtins) do
      if name == builtin then
        return true
      end
    end
  elseif lang == "c" or lang == "cpp" then
    local c_builtins = {
      -- C standard library
      "printf", "scanf", "malloc", "free", "calloc", "realloc",
      "strlen", "strcpy", "strcat", "strcmp", "strncpy", "strncat",
      "memcpy", "memset", "memmove", "memcmp",
      "fopen", "fclose", "fread", "fwrite", "fprintf", "fscanf",
      "exit", "abort", "atexit", "system", "getenv",
      "sizeof", "NULL", "EOF", "stdin", "stdout", "stderr",
      -- C++ standard library
      "std", "cout", "cin", "endl", "cerr", "clog",
      "string", "vector", "map", "set", "list", "deque", "queue", "stack",
      "unique_ptr", "shared_ptr", "weak_ptr", "make_unique", "make_shared",
      "move", "forward", "swap",
      "begin", "end", "size", "empty", "push_back", "pop_back",
      "iterator", "const_iterator",
      "pair", "tuple", "optional", "variant", "any",
      "thread", "mutex", "lock_guard", "unique_lock",
      "async", "future", "promise",
      "exception", "runtime_error", "logic_error",
      "true", "false", "nullptr",
    }
    for _, builtin in ipairs(c_builtins) do
      if name == builtin then
        return true
      end
    end
  elseif lang == "go" then
    local go_builtins = {
      "append", "cap", "close", "complex", "copy", "delete",
      "imag", "len", "make", "new", "panic", "print", "println",
      "real", "recover",
      "bool", "byte", "complex64", "complex128", "error",
      "float32", "float64", "int", "int8", "int16", "int32", "int64",
      "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr",
      "nil", "iota",
      "fmt", "os", "io", "bufio", "strings", "strconv",
      "context", "sync", "time", "net", "http",
    }
    for _, builtin in ipairs(go_builtins) do
      if name == builtin then
        return true
      end
    end
  elseif lang == "rust" then
    local rust_builtins = {
      "println", "print", "eprintln", "eprint", "format", "panic",
      "vec", "Vec", "String", "str", "Box", "Rc", "Arc", "Cell", "RefCell",
      "Option", "Some", "None", "Result", "Ok", "Err",
      "assert", "assert_eq", "assert_ne", "debug_assert",
      "todo", "unimplemented", "unreachable",
      "Clone", "Copy", "Debug", "Default", "Eq", "Hash", "Ord", "PartialEq", "PartialOrd",
      "Drop", "Fn", "FnMut", "FnOnce", "From", "Into", "Iterator",
      "Send", "Sync", "Sized", "Unpin",
      "std", "self", "crate", "super",
      "i8", "i16", "i32", "i64", "i128", "isize",
      "u8", "u16", "u32", "u64", "u128", "usize",
      "f32", "f64", "bool", "char",
    }
    for _, builtin in ipairs(rust_builtins) do
      if name == builtin then
        return true
      end
    end
  end

  return false
end

return M
