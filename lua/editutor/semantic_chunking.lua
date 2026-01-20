-- editutor/semantic_chunking.lua
-- Tree-sitter based semantic extraction for context optimization
-- Extracts meaningful content (exports, types, signatures) instead of truncating by lines

local M = {}

local project_scanner = require("editutor.project_scanner")

-- =============================================================================
-- Configuration
-- =============================================================================

M.DEFAULT_THRESHOLD = 300 -- Lines threshold for chunking
M.DEFAULT_MAX_TOKENS = 2000 -- Max tokens per file when chunking

-- =============================================================================
-- Language-specific Tree-sitter Queries
-- =============================================================================

-- Queries to extract exports, types, and function signatures
-- Priority: exports > types > function signatures > class declarations

M.QUERIES = {
  -- TypeScript/JavaScript/TSX/JSX
  typescript = [[
    ; Export statements (highest priority)
    (export_statement) @export

    ; Type definitions
    (type_alias_declaration) @type

    ; Interface declarations
    (interface_declaration) @interface

    ; Enum declarations
    (enum_declaration) @enum

    ; Function declarations (will extract signature only)
    (function_declaration
      name: (identifier) @func.name) @function

    ; Arrow functions assigned to const (common pattern)
    (lexical_declaration
      (variable_declarator
        name: (identifier) @func.name
        value: (arrow_function))) @arrow_function

    ; Class declarations
    (class_declaration
      name: (type_identifier) @class.name) @class
  ]],

  javascript = [[
    ; Export statements
    (export_statement) @export

    ; Function declarations
    (function_declaration
      name: (identifier) @func.name) @function

    ; Arrow functions assigned to const
    (lexical_declaration
      (variable_declarator
        name: (identifier) @func.name
        value: (arrow_function))) @arrow_function

    ; Class declarations
    (class_declaration
      name: (identifier) @class.name) @class
  ]],

  -- Python
  python = [[
    ; Class definitions
    (class_definition
      name: (identifier) @class.name) @class

    ; Function definitions (top-level)
    (function_definition
      name: (identifier) @func.name) @function

    ; Type alias (Python 3.12+)
    (type_alias_statement) @type

    ; Decorated definitions
    (decorated_definition) @decorated
  ]],

  -- Lua
  lua = [[
    ; Function declarations
    (function_declaration
      name: [(identifier) (dot_index_expression)] @func.name) @function

    ; Local function declarations
    (function_declaration
      name: (identifier) @func.name) @function

    ; Variable assignments (M.xxx = function)
    (assignment_statement
      (variable_list
        (dot_index_expression) @var.name)
      (expression_list
        (function_definition))) @module_function

    ; Return statement (module exports)
    (return_statement) @return
  ]],

  -- Go
  go = [[
    ; Type declarations
    (type_declaration) @type

    ; Function declarations
    (function_declaration
      name: (identifier) @func.name) @function

    ; Method declarations
    (method_declaration
      name: (field_identifier) @method.name) @method

    ; Interface types
    (type_spec
      name: (type_identifier) @interface.name
      type: (interface_type)) @interface

    ; Struct types
    (type_spec
      name: (type_identifier) @struct.name
      type: (struct_type)) @struct
  ]],

  -- Rust
  rust = [[
    ; Public items
    (function_item
      (visibility_modifier)?) @function

    ; Struct definitions
    (struct_item) @struct

    ; Enum definitions
    (enum_item) @enum

    ; Trait definitions
    (trait_item) @trait

    ; Impl blocks
    (impl_item) @impl

    ; Type aliases
    (type_item) @type

    ; Const items
    (const_item) @const

    ; Static items
    (static_item) @static
  ]],

  -- C
  c = [[
    ; Function definitions
    (function_definition
      declarator: (function_declarator
        declarator: (identifier) @func.name)) @function

    ; Function declarations (prototypes)
    (declaration
      declarator: (function_declarator)) @prototype

    ; Struct definitions
    (struct_specifier
      name: (type_identifier) @struct.name
      body: (field_declaration_list)) @struct

    ; Enum definitions
    (enum_specifier
      name: (type_identifier)? @enum.name
      body: (enumerator_list)) @enum

    ; Typedef declarations
    (type_definition) @typedef

    ; Macro definitions
    (preproc_function_def) @macro
    (preproc_def) @macro_const
  ]],

  -- C++
  cpp = [[
    ; Function definitions
    (function_definition
      declarator: [(function_declarator) (qualified_identifier)]) @function

    ; Class definitions
    (class_specifier
      name: (type_identifier) @class.name
      body: (field_declaration_list)) @class

    ; Struct definitions
    (struct_specifier
      name: (type_identifier) @struct.name
      body: (field_declaration_list)) @struct

    ; Enum definitions
    (enum_specifier
      name: (type_identifier)? @enum.name) @enum

    ; Namespace definitions
    (namespace_definition
      name: (identifier) @namespace.name) @namespace

    ; Template declarations
    (template_declaration) @template

    ; Typedef declarations
    (type_definition) @typedef

    ; Using declarations
    (using_declaration) @using
    (alias_declaration) @alias
  ]],

  -- Java
  java = [[
    ; Class declarations
    (class_declaration
      name: (identifier) @class.name) @class

    ; Interface declarations
    (interface_declaration
      name: (identifier) @interface.name) @interface

    ; Enum declarations
    (enum_declaration
      name: (identifier) @enum.name) @enum

    ; Method declarations
    (method_declaration
      name: (identifier) @method.name) @method

    ; Constructor declarations
    (constructor_declaration
      name: (identifier) @constructor.name) @constructor
  ]],
}

-- Aliases
M.QUERIES.tsx = M.QUERIES.typescript
M.QUERIES.jsx = M.QUERIES.javascript

-- =============================================================================
-- Language Detection
-- =============================================================================

M.EXT_TO_LANG = {
  ts = "typescript",
  tsx = "typescript",
  js = "javascript",
  jsx = "javascript",
  mjs = "javascript",
  cjs = "javascript",
  py = "python",
  pyw = "python",
  lua = "lua",
  go = "go",
  rs = "rust",
  c = "c",
  h = "c",
  cpp = "cpp",
  cc = "cpp",
  cxx = "cpp",
  hpp = "cpp",
  hh = "cpp",
  hxx = "cpp",
  java = "java",
}

---Get tree-sitter language from file extension
---@param filepath string
---@return string|nil
function M.get_language(filepath)
  local ext = filepath:match("%.([^.]+)$")
  if not ext then
    return nil
  end
  return M.EXT_TO_LANG[ext:lower()]
end

---Get tree-sitter parser language name (may differ from our lang key)
---@param lang string
---@return string
function M.get_parser_lang(lang)
  -- Tree-sitter parser names
  local parser_names = {
    typescript = "typescript",
    javascript = "javascript",
    python = "python",
    lua = "lua",
    go = "go",
    rust = "rust",
    c = "c",
    cpp = "cpp",
    java = "java",
  }
  return parser_names[lang] or lang
end

-- =============================================================================
-- Core Extraction Functions
-- =============================================================================

---Read file content
---@param filepath string
---@return string|nil content
---@return number line_count
local function read_file(filepath)
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return nil, 0
  end
  return table.concat(lines, "\n"), #lines
end

---Extract function/method signature only (without body)
---@param node userdata Tree-sitter node
---@param content string Full file content
---@param lang string Language
---@return string signature
local function extract_signature_only(node, content, lang)
  local node_text = vim.treesitter.get_node_text(node, content)

  if lang == "typescript" or lang == "javascript" then
    -- Remove function body { ... }
    local signature = node_text:gsub("%s*%b{}%s*$", "")
    -- Clean up arrow function bodies
    signature = signature:gsub("%s*=>%s*%b{}%s*$", " => { ... }")
    signature = signature:gsub("%s*=>%s*[^{].*$", " => ...")
    return signature
  elseif lang == "python" then
    -- Keep only the def line and docstring if present
    local lines = vim.split(node_text, "\n")
    local signature_lines = {}
    local in_docstring = false
    local docstring_char = nil

    for i, line in ipairs(lines) do
      if i == 1 then
        -- Always keep def line
        table.insert(signature_lines, line)
      elseif line:match('^%s*"""') or line:match("^%s*'''") then
        -- Docstring handling
        if not in_docstring then
          in_docstring = true
          docstring_char = line:match('"""') and '"""' or "'''"
          table.insert(signature_lines, line)
          -- Check if single-line docstring
          if line:match(docstring_char .. ".*" .. docstring_char .. "%s*$") then
            in_docstring = false
            break
          end
        else
          table.insert(signature_lines, line)
          if line:match(docstring_char .. "%s*$") then
            break
          end
        end
      elseif in_docstring then
        table.insert(signature_lines, line)
      else
        -- Stop at first non-docstring line after def
        table.insert(signature_lines, "    ...")
        break
      end
    end
    return table.concat(signature_lines, "\n")
  elseif lang == "lua" then
    -- Remove function body
    local signature = node_text:gsub("\n.-\nend%s*$", "\n  -- ...\nend")
    return signature
  elseif lang == "go" then
    -- Keep signature, replace body
    local signature = node_text:gsub("%s*%b{}%s*$", " { ... }")
    return signature
  elseif lang == "rust" then
    -- Keep signature, replace body
    local signature = node_text:gsub("%s*%b{}%s*$", " { ... }")
    return signature
  elseif lang == "c" or lang == "cpp" then
    -- Keep signature, replace body
    local signature = node_text:gsub("%s*%b{}%s*$", ";")
    return signature
  elseif lang == "java" then
    -- Keep signature, replace body
    local signature = node_text:gsub("%s*%b{}%s*$", " { ... }")
    return signature
  end

  return node_text
end

---Check if node is a function/method that should have body stripped
---@param node_type string
---@param lang string
---@return boolean
local function is_function_node(node_type, lang)
  local function_types = {
    typescript = { "function", "arrow_function", "method_definition" },
    javascript = { "function", "arrow_function", "method_definition" },
    python = { "function", "function_definition" },
    lua = { "function", "module_function", "function_declaration" },
    go = { "function", "method" },
    rust = { "function" },
    c = { "function" },
    cpp = { "function" },
    java = { "method", "constructor" },
  }

  local types = function_types[lang] or {}
  for _, t in ipairs(types) do
    if node_type == t then
      return true
    end
  end
  return false
end

---Extract semantic summary from file using tree-sitter
---@param filepath string
---@param max_tokens? number Maximum tokens (default 2000)
---@return string|nil content Extracted content
---@return table metadata
function M.extract_semantic_summary(filepath, max_tokens)
  max_tokens = max_tokens or M.DEFAULT_MAX_TOKENS

  local content, line_count = read_file(filepath)
  if not content then
    return nil, { error = "cannot_read_file" }
  end

  local lang = M.get_language(filepath)
  if not lang then
    -- Unsupported language, return truncated content
    local lines = vim.split(content, "\n")
    if #lines > M.DEFAULT_THRESHOLD then
      lines = vim.list_slice(lines, 1, M.DEFAULT_THRESHOLD)
      content = table.concat(lines, "\n") .. "\n-- ... (truncated)"
    end
    return content, { mode = "truncated", reason = "unsupported_language" }
  end

  local query_string = M.QUERIES[lang]
  if not query_string then
    -- No query for this language, return truncated
    local lines = vim.split(content, "\n")
    if #lines > M.DEFAULT_THRESHOLD then
      lines = vim.list_slice(lines, 1, M.DEFAULT_THRESHOLD)
      content = table.concat(lines, "\n") .. "\n-- ... (truncated)"
    end
    return content, { mode = "truncated", reason = "no_query" }
  end

  -- Parse with tree-sitter
  local parser_lang = M.get_parser_lang(lang)
  local ok_parser, parser = pcall(vim.treesitter.get_string_parser, content, parser_lang)
  if not ok_parser or not parser then
    -- Parser not available, return truncated
    local lines = vim.split(content, "\n")
    if #lines > M.DEFAULT_THRESHOLD then
      lines = vim.list_slice(lines, 1, M.DEFAULT_THRESHOLD)
      content = table.concat(lines, "\n") .. "\n-- ... (truncated)"
    end
    return content, { mode = "truncated", reason = "parser_unavailable" }
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil, { error = "parse_failed" }
  end

  local root = tree:root()

  -- Parse query
  local ok_query, query = pcall(vim.treesitter.query.parse, parser_lang, query_string)
  if not ok_query or not query then
    -- Query failed, return truncated
    local lines = vim.split(content, "\n")
    if #lines > M.DEFAULT_THRESHOLD then
      lines = vim.list_slice(lines, 1, M.DEFAULT_THRESHOLD)
      content = table.concat(lines, "\n") .. "\n-- ... (truncated)"
    end
    return content, { mode = "truncated", reason = "query_failed" }
  end

  -- Collect captures
  local captures = {}
  local seen_ranges = {} -- Deduplicate overlapping captures

  for id, node, _ in query:iter_captures(root, content) do
    local name = query.captures[id]
    local start_row, start_col, end_row, end_col = node:range()
    local range_key = string.format("%d:%d-%d:%d", start_row, start_col, end_row, end_col)

    -- Skip if we've seen this exact range (parent/child overlap)
    if not seen_ranges[range_key] then
      -- Skip inner captures (like func.name), only take outer captures
      if not name:match("%.name$") then
        seen_ranges[range_key] = true

        local node_type = name:gsub("%..*", "") -- Remove .name suffix
        local node_text

        if is_function_node(node_type, lang) then
          -- Extract signature only for functions
          node_text = extract_signature_only(node, content, lang)
        else
          node_text = vim.treesitter.get_node_text(node, content)
        end

        table.insert(captures, {
          type = node_type,
          text = node_text,
          start_row = start_row,
          end_row = end_row,
          tokens = project_scanner.estimate_tokens(node_text),
        })
      end
    end
  end

  -- Sort by position in file
  table.sort(captures, function(a, b)
    return a.start_row < b.start_row
  end)

  -- Build result within token budget
  local parts = {}
  local total_tokens = 0
  local included_count = 0

  for _, capture in ipairs(captures) do
    if total_tokens + capture.tokens <= max_tokens then
      table.insert(parts, capture.text)
      total_tokens = total_tokens + capture.tokens
      included_count = included_count + 1
    else
      -- Budget exceeded
      break
    end
  end

  -- Add note if truncated
  local result = table.concat(parts, "\n\n")
  if included_count < #captures then
    result = result .. "\n\n// ... (" .. (#captures - included_count) .. " more items truncated)"
  end

  return result,
    {
      mode = "semantic",
      language = lang,
      total_captures = #captures,
      included_captures = included_count,
      total_tokens = total_tokens,
      original_lines = line_count,
    }
end

---Extract only type definitions from file
---@param filepath string
---@param max_tokens? number
---@return string|nil content
---@return table metadata
function M.extract_types_only(filepath, max_tokens)
  max_tokens = max_tokens or M.DEFAULT_MAX_TOKENS

  local content, line_count = read_file(filepath)
  if not content then
    return nil, { error = "cannot_read_file" }
  end

  local lang = M.get_language(filepath)
  if not lang then
    return nil, { error = "unsupported_language" }
  end

  -- Type-specific queries
  local type_queries = {
    typescript = [[
      (type_alias_declaration) @type
      (interface_declaration) @interface
      (enum_declaration) @enum
    ]],
    javascript = [[
      ; JavaScript doesn't have built-in types, extract JSDoc comments
      (comment) @jsdoc
    ]],
    python = [[
      (class_definition
        name: (identifier) @class.name
        body: (block
          (expression_statement
            (assignment
              left: (identifier)
              right: (_))))) @dataclass
      (type_alias_statement) @type
    ]],
    go = [[
      (type_declaration) @type
    ]],
    rust = [[
      (struct_item) @struct
      (enum_item) @enum
      (type_item) @type
    ]],
    c = [[
      (struct_specifier
        name: (type_identifier)
        body: (field_declaration_list)) @struct
      (enum_specifier) @enum
      (type_definition) @typedef
    ]],
    cpp = [[
      (class_specifier) @class
      (struct_specifier
        name: (type_identifier)
        body: (field_declaration_list)) @struct
      (enum_specifier) @enum
      (type_definition) @typedef
      (alias_declaration) @alias
    ]],
    java = [[
      (class_declaration) @class
      (interface_declaration) @interface
      (enum_declaration) @enum
    ]],
  }

  type_queries.tsx = type_queries.typescript
  type_queries.jsx = type_queries.javascript

  local query_string = type_queries[lang]
  if not query_string then
    return nil, { error = "no_type_query", language = lang }
  end

  local parser_lang = M.get_parser_lang(lang)
  local ok_parser, parser = pcall(vim.treesitter.get_string_parser, content, parser_lang)
  if not ok_parser or not parser then
    return nil, { error = "parser_unavailable" }
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil, { error = "parse_failed" }
  end

  local root = tree:root()

  local ok_query, query = pcall(vim.treesitter.query.parse, parser_lang, query_string)
  if not ok_query or not query then
    return nil, { error = "query_failed" }
  end

  local parts = {}
  local total_tokens = 0
  local seen_ranges = {}

  for id, node in query:iter_captures(root, content) do
    local name = query.captures[id]
    if not name:match("%.name$") then
      local start_row, start_col, end_row, end_col = node:range()
      local range_key = string.format("%d:%d-%d:%d", start_row, start_col, end_row, end_col)

      if not seen_ranges[range_key] then
        seen_ranges[range_key] = true
        local text = vim.treesitter.get_node_text(node, content)
        local tokens = project_scanner.estimate_tokens(text)

        if total_tokens + tokens <= max_tokens then
          table.insert(parts, text)
          total_tokens = total_tokens + tokens
        end
      end
    end
  end

  return table.concat(parts, "\n\n"),
    {
      mode = "types_only",
      language = lang,
      total_tokens = total_tokens,
      original_lines = line_count,
    }
end

---Extract definition at specific location (for LSP results)
---@param filepath string
---@param line number 0-indexed line
---@param col number 0-indexed column
---@param context_lines? number Extra lines of context (default 5)
---@return string|nil content
---@return table metadata
function M.extract_definition_at(filepath, line, col, context_lines)
  context_lines = context_lines or 5

  local content, line_count = read_file(filepath)
  if not content then
    return nil, { error = "cannot_read_file" }
  end

  local lang = M.get_language(filepath)
  if not lang then
    -- Fallback: extract lines around position
    local lines = vim.split(content, "\n")
    local start_line = math.max(1, line - context_lines)
    local end_line = math.min(#lines, line + context_lines + 10)
    local result = table.concat(vim.list_slice(lines, start_line, end_line), "\n")
    return result, { mode = "context_lines", language = nil }
  end

  -- Parse with tree-sitter
  local parser_lang = M.get_parser_lang(lang)
  local ok_parser, parser = pcall(vim.treesitter.get_string_parser, content, parser_lang)
  if not ok_parser or not parser then
    -- Fallback
    local lines = vim.split(content, "\n")
    local start_line = math.max(1, line - context_lines)
    local end_line = math.min(#lines, line + context_lines + 10)
    local result = table.concat(vim.list_slice(lines, start_line, end_line), "\n")
    return result, { mode = "context_lines", reason = "parser_unavailable" }
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil, { error = "parse_failed" }
  end

  local root = tree:root()

  -- Find node at position
  local node = root:named_descendant_for_range(line, col, line, col)
  if not node then
    -- Fallback
    local lines = vim.split(content, "\n")
    local start_line = math.max(1, line - context_lines)
    local end_line = math.min(#lines, line + context_lines + 10)
    local result = table.concat(vim.list_slice(lines, start_line, end_line), "\n")
    return result, { mode = "context_lines", reason = "no_node_at_position" }
  end

  -- Walk up to find enclosing declaration
  local declaration_types = {
    -- TypeScript/JavaScript
    "function_declaration",
    "class_declaration",
    "interface_declaration",
    "type_alias_declaration",
    "enum_declaration",
    "lexical_declaration",
    "variable_declaration",
    "export_statement",
    "method_definition",
    -- Python
    "function_definition",
    "class_definition",
    "decorated_definition",
    -- Lua
    "function_declaration",
    "assignment_statement",
    -- Go
    "function_declaration",
    "method_declaration",
    "type_declaration",
    "type_spec",
    -- Rust
    "function_item",
    "struct_item",
    "enum_item",
    "impl_item",
    "trait_item",
    "type_item",
    -- C/C++
    "function_definition",
    "declaration",
    "struct_specifier",
    "class_specifier",
    "enum_specifier",
    "type_definition",
    "namespace_definition",
    "template_declaration",
    -- Java
    "class_declaration",
    "interface_declaration",
    "method_declaration",
    "enum_declaration",
  }

  local declaration_set = {}
  for _, t in ipairs(declaration_types) do
    declaration_set[t] = true
  end

  local current = node
  while current do
    if declaration_set[current:type()] then
      local text = vim.treesitter.get_node_text(current, content)
      local start_row, _, end_row, _ = current:range()
      return text,
        {
          mode = "definition",
          language = lang,
          node_type = current:type(),
          start_line = start_row,
          end_line = end_row,
          tokens = project_scanner.estimate_tokens(text),
        }
    end
    current = current:parent()
  end

  -- No declaration found, return context around position
  local lines = vim.split(content, "\n")
  local start_line = math.max(1, line - context_lines)
  local end_line = math.min(#lines, line + context_lines + 10)
  local result = table.concat(vim.list_slice(lines, start_line, end_line), "\n")
  return result, { mode = "context_lines", reason = "no_declaration_found" }
end

-- =============================================================================
-- Smart Content Extraction
-- =============================================================================

---Get file content with smart chunking based on size
---@param filepath string
---@param opts? table {threshold?: number, max_tokens?: number, mode?: string}
---@return string|nil content
---@return table metadata
function M.get_file_content(filepath, opts)
  opts = opts or {}
  local threshold = opts.threshold or M.DEFAULT_THRESHOLD
  local max_tokens = opts.max_tokens or M.DEFAULT_MAX_TOKENS
  local mode = opts.mode or "semantic" -- "semantic", "types_only", "full", "truncate"

  local content, line_count = read_file(filepath)
  if not content then
    return nil, { error = "cannot_read_file" }
  end

  -- Small file: return full content
  if line_count <= threshold then
    return content,
      {
        mode = "full",
        lines = line_count,
        tokens = project_scanner.estimate_tokens(content),
      }
  end

  -- Large file: apply chunking strategy
  if mode == "full" then
    return content,
      {
        mode = "full",
        lines = line_count,
        tokens = project_scanner.estimate_tokens(content),
      }
  elseif mode == "truncate" then
    local lines = vim.split(content, "\n")
    lines = vim.list_slice(lines, 1, threshold)
    local truncated = table.concat(lines, "\n") .. "\n// ... (truncated, " .. line_count .. " total lines)"
    return truncated,
      {
        mode = "truncated",
        lines = threshold,
        original_lines = line_count,
        tokens = project_scanner.estimate_tokens(truncated),
      }
  elseif mode == "types_only" then
    return M.extract_types_only(filepath, max_tokens)
  else
    -- Default: semantic
    return M.extract_semantic_summary(filepath, max_tokens)
  end
end

-- =============================================================================
-- Utility Functions
-- =============================================================================

---Check if file needs chunking based on line count
---@param filepath string
---@param threshold? number
---@return boolean
function M.needs_chunking(filepath, threshold)
  threshold = threshold or M.DEFAULT_THRESHOLD
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return false
  end
  return #lines > threshold
end

---Check if tree-sitter is available for language
---@param lang string
---@return boolean
function M.has_parser(lang)
  local parser_lang = M.get_parser_lang(lang)
  local ok = pcall(vim.treesitter.language.inspect, parser_lang)
  return ok
end

---List supported languages
---@return string[]
function M.supported_languages()
  local langs = {}
  for lang, _ in pairs(M.QUERIES) do
    table.insert(langs, lang)
  end
  table.sort(langs)
  return langs
end

return M
