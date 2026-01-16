-- editutor/indexer/chunker.lua
-- Tree-sitter AST-based code chunking for semantic search

local M = {}

-- Tree-sitter node types that define chunk boundaries by language
local CHUNK_TYPES = {
  lua = {
    "function_declaration",
    "function_definition",
    "local_function",
    "method_definition",
    "assignment_statement", -- For M.foo = function() patterns
  },
  python = {
    "function_definition",
    "class_definition",
    "decorated_definition",
  },
  javascript = {
    "function_declaration",
    "function_expression",
    "arrow_function",
    "method_definition",
    "class_declaration",
    "variable_declarator", -- For const foo = () => {} patterns
  },
  typescript = {
    "function_declaration",
    "function_expression",
    "arrow_function",
    "method_definition",
    "class_declaration",
    "interface_declaration",
    "type_alias_declaration",
    "variable_declarator",
  },
  tsx = {
    "function_declaration",
    "function_expression",
    "arrow_function",
    "method_definition",
    "class_declaration",
    "interface_declaration",
    "type_alias_declaration",
    "variable_declarator",
  },
  go = {
    "function_declaration",
    "method_declaration",
    "type_declaration",
    "const_declaration",
    "var_declaration",
  },
  rust = {
    "function_item",
    "impl_item",
    "struct_item",
    "enum_item",
    "trait_item",
    "mod_item",
  },
  c = {
    "function_definition",
    "struct_specifier",
    "enum_specifier",
    "declaration",
  },
  cpp = {
    "function_definition",
    "class_specifier",
    "struct_specifier",
    "enum_specifier",
    "namespace_definition",
    "template_declaration",
  },
  java = {
    "method_declaration",
    "class_declaration",
    "interface_declaration",
    "constructor_declaration",
    "enum_declaration",
  },
  ruby = {
    "method",
    "singleton_method",
    "class",
    "module",
  },
  php = {
    "function_definition",
    "method_declaration",
    "class_declaration",
    "interface_declaration",
    "trait_declaration",
  },
}

-- Import patterns by language
local IMPORT_PATTERNS = {
  lua = {
    patterns = { "require%s*%(?['\"]([^'\"]+)['\"]%)?", "local%s+%w+%s*=%s*require%s*%(?['\"]([^'\"]+)['\"]%)?" },
    type = "require",
  },
  python = {
    patterns = { "^import%s+([%w_.]+)", "^from%s+([%w_.]+)%s+import" },
    type = "import",
  },
  javascript = {
    patterns = { "import%s+.+%s+from%s+['\"]([^'\"]+)['\"]", "require%s*%(['\"]([^'\"]+)['\"]%)" },
    type = "import",
  },
  typescript = {
    patterns = { "import%s+.+%s+from%s+['\"]([^'\"]+)['\"]", "require%s*%(['\"]([^'\"]+)['\"]%)" },
    type = "import",
  },
  go = {
    patterns = { 'import%s+["\']([^"\']+)["\']', 'import%s*%(%s*["\']([^"\']+)["\']' },
    type = "import",
  },
  rust = {
    patterns = { "use%s+([%w_:]+)", "extern%s+crate%s+([%w_]+)" },
    type = "use",
  },
}

---Count non-whitespace characters (NWS) for chunk size estimation
---@param text string
---@return number
local function count_nws(text)
  return #text:gsub("%s", "")
end

---Get the name of a chunk from its node
---@param node userdata Tree-sitter node
---@param content string Full file content
---@param language string
---@return string|nil
local function get_chunk_name(node, content, language)
  local type = node:type()

  -- Language-specific name extraction
  if language == "lua" then
    if type == "function_declaration" or type == "local_function" then
      for child in node:iter_children() do
        if child:type() == "identifier" or child:type() == "dot_index_expression" then
          local start_row, start_col, end_row, end_col = child:range()
          local lines = vim.split(content, "\n")
          if lines[start_row + 1] then
            return lines[start_row + 1]:sub(start_col + 1, end_col)
          end
        end
      end
    elseif type == "assignment_statement" then
      -- Handle M.foo = function() patterns
      for child in node:iter_children() do
        if child:type() == "variable_list" then
          local var = child:child(0)
          if var then
            local start_row, start_col, end_row, end_col = var:range()
            local lines = vim.split(content, "\n")
            if lines[start_row + 1] then
              return lines[start_row + 1]:sub(start_col + 1, end_col)
            end
          end
        end
      end
    end
  elseif language == "python" then
    for child in node:iter_children() do
      if child:type() == "identifier" then
        local start_row, start_col, end_row, end_col = child:range()
        local lines = vim.split(content, "\n")
        if lines[start_row + 1] then
          return lines[start_row + 1]:sub(start_col + 1, end_col)
        end
      end
    end
  else
    -- Generic: look for identifier or name child
    for child in node:iter_children() do
      local child_type = child:type()
      if child_type == "identifier" or child_type == "name" or child_type == "property_identifier" then
        local start_row, start_col, end_row, end_col = child:range()
        local lines = vim.split(content, "\n")
        if lines[start_row + 1] then
          return lines[start_row + 1]:sub(start_col + 1, end_col)
        end
      end
    end
  end

  return nil
end

---Get function signature from node
---@param node userdata Tree-sitter node
---@param content string
---@return string|nil
local function get_signature(node, content)
  local start_row, start_col, _, _ = node:range()
  local lines = vim.split(content, "\n")
  local first_line = lines[start_row + 1]

  if not first_line then
    return nil
  end

  -- Take up to first { or : or end of line
  local sig = first_line:match("^[^{:]+") or first_line
  return vim.trim(sig)
end

---Get content of a node
---@param node userdata Tree-sitter node
---@param content string
---@return string
local function get_node_content(node, content)
  local start_row, start_col, end_row, end_col = node:range()
  local lines = vim.split(content, "\n")

  local result = {}
  for i = start_row + 1, end_row + 1 do
    if lines[i] then
      if i == start_row + 1 and i == end_row + 1 then
        table.insert(result, lines[i]:sub(start_col + 1, end_col))
      elseif i == start_row + 1 then
        table.insert(result, lines[i]:sub(start_col + 1))
      elseif i == end_row + 1 then
        table.insert(result, lines[i]:sub(1, end_col))
      else
        table.insert(result, lines[i])
      end
    end
  end

  return table.concat(result, "\n")
end

---Get scope path (nested context) for a node
---@param node userdata Tree-sitter node
---@param content string
---@param language string
---@return string
local function get_scope_path(node, content, language)
  local parts = {}
  local current = node:parent()

  while current do
    local type = current:type()
    local chunk_types = CHUNK_TYPES[language] or {}

    for _, ct in ipairs(chunk_types) do
      if type == ct then
        local name = get_chunk_name(current, content, language)
        if name then
          table.insert(parts, 1, name)
        end
        break
      end
    end

    current = current:parent()
  end

  return table.concat(parts, ".")
end

---Check if node is a valid chunk (contains meaningful code)
---@param node userdata Tree-sitter node
---@param content string
---@param opts table
---@return boolean
local function is_valid_chunk(node, content, opts)
  local node_content = get_node_content(node, content)
  local nws = count_nws(node_content)

  -- Skip if too small (likely just a declaration)
  if nws < 20 then
    return false
  end

  -- Skip if too large (will be split)
  if nws > (opts.max_chunk_size or 2000) then
    -- For now, still include but could implement splitting
    return true
  end

  return true
end

---Extract chunks from file using Tree-sitter
---@param filepath string
---@param content string
---@param opts? table {language?: string, max_chunks?: number, max_chunk_size?: number}
---@return table[] chunks
function M.extract_chunks(filepath, content, opts)
  opts = opts or {}
  local language = opts.language

  if not language then
    return {}
  end

  -- Map language names to tree-sitter parsers
  local parser_map = {
    javascript = "javascript",
    typescript = "typescript",
    tsx = "tsx",
    jsx = "javascript",
    python = "python",
    lua = "lua",
    go = "go",
    rust = "rust",
    c = "c",
    cpp = "cpp",
    c_sharp = "c_sharp",
    java = "java",
    ruby = "ruby",
    php = "php",
    vue = "vue",
    svelte = "svelte",
    kotlin = "kotlin",
    scala = "scala",
    swift = "swift",
    elixir = "elixir",
  }

  local ts_lang = parser_map[language]
  if not ts_lang then
    -- Fallback: create a single chunk for the whole file
    return M._fallback_chunks(filepath, content, opts)
  end

  -- Try to get tree-sitter parser
  local ok, parser = pcall(vim.treesitter.get_string_parser, content, ts_lang)
  if not ok or not parser then
    return M._fallback_chunks(filepath, content, opts)
  end

  local tree = parser:parse()[1]
  if not tree then
    return M._fallback_chunks(filepath, content, opts)
  end

  local root = tree:root()
  local chunks = {}
  local chunk_types = CHUNK_TYPES[language] or CHUNK_TYPES[ts_lang] or {}
  local max_chunks = opts.max_chunks or 100

  ---Recursively extract chunks from AST
  ---@param node userdata
  local function extract_from_node(node)
    if #chunks >= max_chunks then
      return
    end

    local type = node:type()

    -- Check if this node type is a chunk boundary
    local is_chunk = false
    for _, ct in ipairs(chunk_types) do
      if type == ct then
        is_chunk = true
        break
      end
    end

    if is_chunk and is_valid_chunk(node, content, opts) then
      local start_row, _, end_row, _ = node:range()
      local name = get_chunk_name(node, content, language)
      local signature = get_signature(node, content)
      local node_content = get_node_content(node, content)
      local scope_path = get_scope_path(node, content, language)

      table.insert(chunks, {
        type = type,
        name = name,
        signature = signature,
        start_line = start_row + 1,
        end_line = end_row + 1,
        content = node_content,
        scope_path = scope_path ~= "" and scope_path or nil,
      })
    end

    -- Recurse into children
    for child in node:iter_children() do
      extract_from_node(child)
    end
  end

  extract_from_node(root)

  return chunks
end

---Fallback chunking when Tree-sitter is not available
---@param filepath string
---@param content string
---@param opts table
---@return table[]
function M._fallback_chunks(filepath, content, opts)
  local max_chunk_size = opts.max_chunk_size or 2000
  local lines = vim.split(content, "\n")
  local chunks = {}

  -- Simple line-based chunking
  local chunk_lines = {}
  local chunk_start = 1
  local current_nws = 0

  for i, line in ipairs(lines) do
    local line_nws = count_nws(line)
    current_nws = current_nws + line_nws
    table.insert(chunk_lines, line)

    -- Start new chunk if we hit size limit or end of file
    if current_nws >= max_chunk_size or i == #lines then
      if #chunk_lines > 0 then
        table.insert(chunks, {
          type = "block",
          name = nil,
          signature = nil,
          start_line = chunk_start,
          end_line = i,
          content = table.concat(chunk_lines, "\n"),
          scope_path = nil,
        })
      end

      chunk_lines = {}
      chunk_start = i + 1
      current_nws = 0
    end
  end

  return chunks
end

---Extract imports from file
---@param filepath string
---@param content string
---@param language string
---@return table[] imports {imported_name, imported_from, line_number}
function M.extract_imports(filepath, content, language)
  local import_config = IMPORT_PATTERNS[language]
  if not import_config then
    return {}
  end

  local imports = {}
  local lines = vim.split(content, "\n")

  for line_num, line in ipairs(lines) do
    for _, pattern in ipairs(import_config.patterns) do
      local match = line:match(pattern)
      if match then
        table.insert(imports, {
          imported_name = match,
          imported_from = nil, -- Could be enhanced to extract full path
          line_number = line_num,
        })
      end
    end
  end

  return imports
end

-- =============================================================================
-- Call Graph Analysis
-- =============================================================================

-- Node types that represent function calls by language
local CALL_TYPES = {
  lua = { "function_call" },
  python = { "call" },
  javascript = { "call_expression" },
  typescript = { "call_expression" },
  tsx = { "call_expression" },
  go = { "call_expression" },
  rust = { "call_expression", "macro_invocation" },
  java = { "method_invocation" },
  c = { "call_expression" },
  cpp = { "call_expression" },
}

---Extract function calls from a chunk
---@param node userdata Tree-sitter node
---@param content string
---@param language string
---@return string[] called_functions
local function extract_calls_from_node(node, content, language)
  local calls = {}
  local call_types = CALL_TYPES[language] or {}

  local function traverse(n)
    local type = n:type()

    -- Check if this is a call expression
    for _, ct in ipairs(call_types) do
      if type == ct then
        -- Try to extract the function name
        local name = nil

        -- Look for identifier or member expression
        for child in n:iter_children() do
          local child_type = child:type()
          if child_type == "identifier" or child_type == "name" then
            local start_row, start_col, end_row, end_col = child:range()
            local lines = vim.split(content, "\n")
            if lines[start_row + 1] then
              name = lines[start_row + 1]:sub(start_col + 1, end_col)
            end
            break
          elseif child_type == "member_expression" or child_type == "dot_index_expression"
              or child_type == "attribute" then
            -- Get the full member expression (e.g., obj.method)
            local start_row, start_col, end_row, end_col = child:range()
            local lines = vim.split(content, "\n")
            if lines[start_row + 1] then
              name = lines[start_row + 1]:sub(start_col + 1, end_col)
            end
            break
          end
        end

        if name and name ~= "" then
          table.insert(calls, name)
        end
      end
    end

    -- Recurse
    for child in n:iter_children() do
      traverse(child)
    end
  end

  traverse(node)

  -- Dedupe
  local seen = {}
  local unique = {}
  for _, c in ipairs(calls) do
    if not seen[c] then
      seen[c] = true
      table.insert(unique, c)
    end
  end

  return unique
end

---Extract function calls from content
---@param content string
---@param language string
---@return table[] calls {caller_name, called_names[], line_start, line_end}
function M.extract_call_graph(content, language)
  local parser_map = {
    javascript = "javascript",
    typescript = "typescript",
    tsx = "tsx",
    jsx = "javascript",
    python = "python",
    lua = "lua",
    go = "go",
    rust = "rust",
    c = "c",
    cpp = "cpp",
    java = "java",
  }

  local ts_lang = parser_map[language]
  if not ts_lang then
    return {}
  end

  local ok, parser = pcall(vim.treesitter.get_string_parser, content, ts_lang)
  if not ok or not parser then
    return {}
  end

  local tree = parser:parse()[1]
  if not tree then
    return {}
  end

  local root = tree:root()
  local graph = {}
  local chunk_types = CHUNK_TYPES[language] or CHUNK_TYPES[ts_lang] or {}

  local function extract_from_node(node)
    local type = node:type()

    -- Check if this is a function definition
    local is_func = false
    for _, ct in ipairs(chunk_types) do
      if type == ct and (ct:find("function") or ct:find("method")) then
        is_func = true
        break
      end
    end

    if is_func then
      local start_row, _, end_row, _ = node:range()
      local name = get_chunk_name(node, content, language)
      local calls = extract_calls_from_node(node, content, language)

      if name or #calls > 0 then
        table.insert(graph, {
          name = name or "anonymous",
          calls = calls,
          start_line = start_row + 1,
          end_line = end_row + 1,
        })
      end
    end

    -- Recurse
    for child in node:iter_children() do
      extract_from_node(child)
    end
  end

  extract_from_node(root)
  return graph
end

-- =============================================================================
-- Docstring/Comment Extraction
-- =============================================================================

---Extract docstring or leading comment for a function
---@param node userdata Tree-sitter node
---@param content string
---@param language string
---@return string|nil docstring
local function extract_docstring(node, content, language)
  local lines = vim.split(content, "\n")
  local start_row, _, _, _ = node:range()

  -- Look for comments/docstrings before the function
  local doc_lines = {}

  -- Check previous sibling for comment
  local prev = node:prev_sibling()
  if prev then
    local prev_type = prev:type()
    if prev_type:find("comment") or prev_type == "string" then
      local ps, _, pe, _ = prev:range()
      for i = ps + 1, pe + 1 do
        if lines[i] then
          table.insert(doc_lines, lines[i])
        end
      end
    end
  end

  -- Also check lines immediately before (for languages without tree-sitter comment nodes)
  if #doc_lines == 0 and start_row > 0 then
    local comment_patterns = {
      lua = "^%s*%-%-",
      python = "^%s*#",
      javascript = "^%s*//",
      typescript = "^%s*//",
      go = "^%s*//",
      rust = "^%s*//",
      java = "^%s*//",
      c = "^%s*//",
      cpp = "^%s*//",
    }

    local pattern = comment_patterns[language] or "^%s*[/#%-]"
    local i = start_row -- 0-indexed, so this is line before

    while i > 0 and i > start_row - 10 do
      local line = lines[i]
      if line and line:match(pattern) then
        table.insert(doc_lines, 1, line)
        i = i - 1
      else
        break
      end
    end
  end

  if #doc_lines > 0 then
    return table.concat(doc_lines, "\n")
  end

  return nil
end

-- =============================================================================
-- Type Reference Extraction
-- =============================================================================

-- Type annotation node types by language
local TYPE_REF_TYPES = {
  typescript = { "type_identifier", "predefined_type", "generic_type" },
  tsx = { "type_identifier", "predefined_type", "generic_type" },
  rust = { "type_identifier", "generic_type" },
  java = { "type_identifier", "generic_type" },
  go = { "type_identifier" },
  python = { "identifier" }, -- Python type hints are just identifiers
}

---Extract type references from a chunk
---@param node userdata Tree-sitter node
---@param content string
---@param language string
---@return string[] type_names
local function extract_type_refs(node, content, language)
  local type_refs = {}
  local ref_types = TYPE_REF_TYPES[language] or {}

  if #ref_types == 0 then
    return {}
  end

  local function traverse(n)
    local type = n:type()

    for _, rt in ipairs(ref_types) do
      if type == rt then
        local start_row, start_col, end_row, end_col = n:range()
        local lines = vim.split(content, "\n")
        if lines[start_row + 1] then
          local name = lines[start_row + 1]:sub(start_col + 1, end_col)
          -- Filter out primitive types
          local primitives = {
            string = true, number = true, boolean = true, void = true,
            int = true, float = true, double = true, char = true,
            bool = true, i32 = true, i64 = true, u32 = true, u64 = true,
            str = true, any = true, null = true, undefined = true,
          }
          if name and not primitives[name:lower()] then
            table.insert(type_refs, name)
          end
        end
      end
    end

    for child in n:iter_children() do
      traverse(child)
    end
  end

  traverse(node)

  -- Dedupe
  local seen = {}
  local unique = {}
  for _, t in ipairs(type_refs) do
    if not seen[t] then
      seen[t] = true
      table.insert(unique, t)
    end
  end

  return unique
end

-- =============================================================================
-- Enhanced Chunk Extraction
-- =============================================================================

---Extract chunks with enhanced metadata (calls, docstring, types)
---@param filepath string
---@param content string
---@param opts? table
---@return table[] chunks
function M.extract_chunks_enhanced(filepath, content, opts)
  opts = opts or {}
  local language = opts.language

  if not language then
    return {}
  end

  local parser_map = {
    javascript = "javascript",
    typescript = "typescript",
    tsx = "tsx",
    jsx = "javascript",
    python = "python",
    lua = "lua",
    go = "go",
    rust = "rust",
    c = "c",
    cpp = "cpp",
    java = "java",
    ruby = "ruby",
    php = "php",
  }

  local ts_lang = parser_map[language]
  if not ts_lang then
    return M._fallback_chunks(filepath, content, opts)
  end

  local ok, parser = pcall(vim.treesitter.get_string_parser, content, ts_lang)
  if not ok or not parser then
    return M._fallback_chunks(filepath, content, opts)
  end

  local tree = parser:parse()[1]
  if not tree then
    return M._fallback_chunks(filepath, content, opts)
  end

  local root = tree:root()
  local chunks = {}
  local chunk_types = CHUNK_TYPES[language] or CHUNK_TYPES[ts_lang] or {}
  local max_chunks = opts.max_chunks or 100

  local function extract_from_node(node)
    if #chunks >= max_chunks then
      return
    end

    local type = node:type()

    local is_chunk = false
    for _, ct in ipairs(chunk_types) do
      if type == ct then
        is_chunk = true
        break
      end
    end

    if is_chunk and is_valid_chunk(node, content, opts) then
      local start_row, _, end_row, _ = node:range()
      local name = get_chunk_name(node, content, language)
      local signature = get_signature(node, content)
      local node_content = get_node_content(node, content)
      local scope_path = get_scope_path(node, content, language)

      -- Enhanced metadata
      local docstring = extract_docstring(node, content, language)
      local calls = extract_calls_from_node(node, content, language)
      local type_refs = extract_type_refs(node, content, language)

      table.insert(chunks, {
        type = type,
        name = name,
        signature = signature,
        start_line = start_row + 1,
        end_line = end_row + 1,
        content = node_content,
        scope_path = scope_path ~= "" and scope_path or nil,
        -- Enhanced fields
        docstring = docstring,
        calls = calls,
        type_refs = type_refs,
      })
    end

    for child in node:iter_children() do
      extract_from_node(child)
    end
  end

  extract_from_node(root)
  return chunks
end

-- =============================================================================
-- Ranking Helpers
-- =============================================================================

---Get chunk type priority for ranking
---@param chunk_type string
---@return number Higher is more important
function M.get_type_priority(chunk_type)
  local priorities = {
    -- Functions are most important
    function_declaration = 10,
    function_definition = 10,
    local_function = 9,
    function_item = 10,
    method_declaration = 9,
    method_definition = 9,
    arrow_function = 8,
    function_expression = 8,

    -- Classes/structs
    class_declaration = 8,
    class_definition = 8,
    struct_item = 7,
    struct_specifier = 7,
    interface_declaration = 7,
    trait_item = 7,
    impl_item = 8,

    -- Type definitions
    type_alias_declaration = 6,
    type_declaration = 6,
    enum_item = 6,
    enum_declaration = 6,

    -- Variables/constants
    variable_declarator = 5,
    const_declaration = 5,
    var_declaration = 4,
    assignment_statement = 5,

    -- Modules
    mod_item = 4,
    module = 4,
    namespace_definition = 4,

    -- Fallback
    block = 2,
  }

  return priorities[chunk_type] or 3
end

return M
