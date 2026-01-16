-- editutor/lsp_context.lua
-- LSP-based context extraction for ai-editutor
-- Enhanced: scans ENTIRE current file for symbols, not just cursor position
-- Deduplicates definitions to avoid sending same content multiple times

local M = {}

local project_scanner = require("editutor.project_scanner")

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
---@return string
function M.get_project_root()
  return project_scanner.get_project_root()
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
  end

  return false
end

---@class ExternalDefinition
---@field name string Symbol name
---@field filepath string Full file path
---@field content string File content (full or partial)
---@field start_line number Start line (0-indexed)
---@field end_line number End line (0-indexed)
---@field is_full_file boolean Whether content is full file

---Get external definitions for ALL identifiers in current file
---Deduplicates by file path (each external file included only once)
---@param bufnr number Buffer number
---@param callback function Callback(definitions) where definitions is ExternalDefinition[]
---@param opts? table Options {max_files?: number, max_lines_per_file?: number}
function M.get_all_external_definitions(bufnr, callback, opts)
  opts = opts or {}
  local max_files = opts.max_files or 50
  local max_lines_per_file = opts.max_lines_per_file or 500

  local current_file = vim.api.nvim_buf_get_name(bufnr)
  local identifiers = M.extract_all_identifiers(bufnr)

  local definitions = {}
  local seen_files = {} -- Dedup by filepath
  local pending = #identifiers
  local completed = 0

  if pending == 0 then
    callback({})
    return
  end

  -- Process identifiers but limit total external files
  for _, ident in ipairs(identifiers) do
    -- Stop if we have enough files
    if vim.tbl_count(seen_files) >= max_files then
      completed = completed + 1
      if completed >= pending then
        callback(definitions)
      end
      goto continue
    end

    M.get_definition(bufnr, ident.line, ident.col, function(locations)
      completed = completed + 1

      for _, loc in ipairs(locations) do
        local filepath = vim.uri_to_fname(loc.uri)

        -- Skip if same file, already seen, or not project file
        if filepath ~= current_file
          and not seen_files[filepath]
          and M.is_project_file(filepath)
          and vim.tbl_count(seen_files) < max_files then

          seen_files[filepath] = true

          -- Read full file content
          local content, line_count = M.read_file(filepath)

          if content and line_count then
            local is_full = line_count <= max_lines_per_file

            -- Truncate if too long
            if not is_full then
              local lines = vim.split(content, "\n")
              lines = vim.list_slice(lines, 1, max_lines_per_file)
              content = table.concat(lines, "\n") .. "\n... (truncated, " .. line_count .. " total lines)"
            end

            table.insert(definitions, {
              name = ident.name,
              filepath = filepath,
              content = content,
              start_line = 0,
              end_line = is_full and (line_count - 1) or (max_lines_per_file - 1),
              is_full_file = is_full,
              line_count = line_count,
            })
          end
        end
      end

      -- All done
      if completed >= pending then
        callback(definitions)
      end
    end)

    ::continue::
  end
end

---Get full LSP context for current buffer
---@param callback function Callback(context) where context is {current, external, has_lsp}
---@param opts? table Options {max_external_files?: number, max_lines_per_file?: number}
function M.get_context(callback, opts)
  opts = opts or {}
  local max_external_files = opts.max_external_files or 50
  local max_lines_per_file = opts.max_lines_per_file or 500

  local bufnr = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(bufnr)

  -- Read full current file
  local current_content, current_lines = M.read_file(current_file)
  if not current_content then
    -- Fallback: read from buffer
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    current_content = table.concat(lines, "\n")
    current_lines = #lines
  end

  local context = {
    current = {
      filepath = current_file,
      content = current_content,
      line_count = current_lines,
    },
    external = {},
    has_lsp = M.is_available(),
  }

  -- If no LSP, return just current context
  if not context.has_lsp then
    callback(context)
    return
  end

  -- Get external definitions (scans entire file, deduped)
  M.get_all_external_definitions(bufnr, function(definitions)
    context.external = definitions
    callback(context)
  end, {
    max_files = max_external_files,
    max_lines_per_file = max_lines_per_file,
  })
end

---Format context for LLM prompt
---@param ctx table Context from get_context
---@return string Formatted context
---@return table metadata
function M.format_for_prompt(ctx)
  local parts = {}
  local project_root = M.get_project_root()
  local root_name = vim.fn.fnamemodify(project_root, ":t")

  local metadata = {
    current_file = ctx.current.filepath,
    current_lines = ctx.current.line_count,
    external_files = {},
    total_tokens = 0,
  }

  -- Get language from extension
  local ext = ctx.current.filepath:match("%.(%w+)$") or ""
  local language = project_scanner.get_language_for_ext(ext)

  -- Current file context (full file)
  local relative_path = ctx.current.filepath:gsub(project_root .. "/", "")
  local display_path = root_name .. "/" .. relative_path

  table.insert(parts, "=== Current File ===")
  table.insert(parts, string.format("// File: %s (%d lines)", display_path, ctx.current.line_count))
  table.insert(parts, "```" .. language)
  table.insert(parts, ctx.current.content)
  table.insert(parts, "```")
  table.insert(parts, "")

  metadata.total_tokens = project_scanner.estimate_tokens(ctx.current.content)

  -- External definitions (deduped, full files when possible)
  if ctx.external and #ctx.external > 0 then
    table.insert(parts, string.format("=== Related Files from Project (%d files) ===", #ctx.external))
    table.insert(parts, "")

    for _, def in ipairs(ctx.external) do
      local def_relative = def.filepath:gsub(project_root .. "/", "")
      local def_display = root_name .. "/" .. def_relative
      local def_ext = def.filepath:match("%.(%w+)$") or ""
      local def_lang = project_scanner.get_language_for_ext(def_ext)

      local status = def.is_full_file and "full" or "truncated"
      table.insert(parts, string.format("// File: %s (%d lines, %s)", def_display, def.line_count, status))
      table.insert(parts, "```" .. def_lang)
      table.insert(parts, def.content)
      table.insert(parts, "```")
      table.insert(parts, "")

      table.insert(metadata.external_files, {
        path = def_display,
        lines = def.line_count,
        is_full = def.is_full_file,
        tokens = project_scanner.estimate_tokens(def.content),
      })

      metadata.total_tokens = metadata.total_tokens + project_scanner.estimate_tokens(def.content)
    end
  end

  -- LSP status note
  if not ctx.has_lsp then
    table.insert(parts, "[Note: LSP not available - showing only current file context]")
    table.insert(parts, "")
  end

  return table.concat(parts, "\n"), metadata
end

return M
