-- editutor/repo_tags.lua
-- Aider-inspired Tree-sitter definition/reference tags for repo-wide ranking.

local M = {}

local project_scanner = require("editutor.project_scanner")

M.MAX_FILE_SIZE = 100 * 1024

M.EXT_TO_LANG = {
  lua = "lua",
  py = "python",
  pyw = "python",
  pyi = "python",
  js = "javascript",
  jsx = "javascript",
  mjs = "javascript",
  cjs = "javascript",
  ts = "typescript",
  tsx = "typescript",
  go = "go",
  rs = "rust",
  odin = "odin",
}

M.QUERIES = {
  lua = [[
    (function_declaration
      name: [
        (identifier) @name.definition.function
        (dot_index_expression field: (identifier) @name.definition.function)
      ]) @definition.function

    (function_declaration
      name: (method_index_expression method: (identifier) @name.definition.method)) @definition.method

    (assignment_statement
      (variable_list .
        name: [
          (identifier) @name.definition.function
          (dot_index_expression field: (identifier) @name.definition.function)
        ])
      (expression_list . value: (function_definition))) @definition.function

    (table_constructor
      (field
        name: (identifier) @name.definition.function
        value: (function_definition))) @definition.function

    (function_call
      name: [
        (identifier) @name.reference.call
        (dot_index_expression field: (identifier) @name.reference.call)
        (method_index_expression method: (identifier) @name.reference.method)
      ]) @reference.call
  ]],

  python = [[
    (module (expression_statement (assignment left: (identifier) @name.definition.constant) @definition.constant))

    (class_definition
      name: (identifier) @name.definition.class) @definition.class

    (function_definition
      name: (identifier) @name.definition.function) @definition.function

    (call
      function: [
        (identifier) @name.reference.call
        (attribute attribute: (identifier) @name.reference.call)
      ]) @reference.call
  ]],

  javascript = [[
    (function_declaration
      name: (identifier) @name.definition.function) @definition.function

    (method_definition
      name: (property_identifier) @name.definition.method) @definition.method

    (class_declaration
      name: (identifier) @name.definition.class) @definition.class

    (lexical_declaration
      (variable_declarator
        name: (identifier) @name.definition.function
        value: [(arrow_function) (function_expression)])) @definition.function

    (call_expression
      function: [
        (identifier) @name.reference.call
        (member_expression property: (property_identifier) @name.reference.call)
      ]) @reference.call

    (new_expression
      constructor: (identifier) @name.reference.class) @reference.class
  ]],

  typescript = [[
    (function_signature
      name: (identifier) @name.definition.function) @definition.function

    (method_signature
      name: (property_identifier) @name.definition.method) @definition.method

    (interface_declaration
      name: (type_identifier) @name.definition.interface) @definition.interface

    (type_alias_declaration
      name: (type_identifier) @name.definition.type) @definition.type

    (enum_declaration
      name: (identifier) @name.definition.enum) @definition.enum

    (function_declaration
      name: (identifier) @name.definition.function) @definition.function

    (method_definition
      name: (property_identifier) @name.definition.method) @definition.method

    (class_declaration
      name: (type_identifier) @name.definition.class) @definition.class

    (lexical_declaration
      (variable_declarator
        name: (identifier) @name.definition.function
        value: [(arrow_function) (function_expression)])) @definition.function

    (call_expression
      function: [
        (identifier) @name.reference.call
        (member_expression property: (property_identifier) @name.reference.call)
      ]) @reference.call

    (new_expression
      constructor: (identifier) @name.reference.class) @reference.class

    (type_identifier) @name.reference.type @reference.type
  ]],

  go = [[
    (function_declaration
      name: (identifier) @name.definition.function) @definition.function

    (method_declaration
      name: (field_identifier) @name.definition.method) @definition.method

    (type_spec
      name: (type_identifier) @name.definition.type) @definition.type

    (type_declaration (type_spec name: (type_identifier) @name.definition.interface type: (interface_type)))
    (type_declaration (type_spec name: (type_identifier) @name.definition.class type: (struct_type)))
    (var_declaration (var_spec name: (identifier) @name.definition.variable))
    (const_declaration (const_spec name: (identifier) @name.definition.constant))

    (call_expression
      function: [
        (identifier) @name.reference.call
        (selector_expression field: (field_identifier) @name.reference.call)
      ]) @reference.call

    (type_identifier) @name.reference.type @reference.type
  ]],

  rust = [[
    (struct_item name: (type_identifier) @name.definition.class) @definition.class
    (enum_item name: (type_identifier) @name.definition.class) @definition.class
    (type_item name: (type_identifier) @name.definition.class) @definition.class
    (function_item name: (identifier) @name.definition.function) @definition.function
    (trait_item name: (type_identifier) @name.definition.interface) @definition.interface
    (mod_item name: (identifier) @name.definition.module) @definition.module
    (macro_definition name: (identifier) @name.definition.macro) @definition.macro

    (call_expression function: (identifier) @name.reference.call) @reference.call
    (call_expression function: (field_expression field: (field_identifier) @name.reference.call)) @reference.call
    (macro_invocation macro: (identifier) @name.reference.call) @reference.call
    (impl_item trait: (type_identifier) @name.reference.implementation) @reference.implementation
    (impl_item type: (type_identifier) @name.reference.implementation !trait) @reference.implementation
  ]],

  odin = [[
    (procedure_declaration name: (identifier) @name.definition.function) @definition.function
    (type_declaration name: (identifier) @name.definition.type) @definition.type
    (constant_declaration name: (identifier) @name.definition.constant) @definition.constant
    (call_expression function: (identifier) @name.reference.call) @reference.call
  ]],
}

M.QUERIES.tsx = M.QUERIES.typescript
M.QUERIES.jsx = M.QUERIES.javascript

local function get_display_path(filepath, project_root)
  if filepath:sub(1, #project_root) == project_root then
    return filepath:sub(#project_root + 2):gsub("^/", "")
  end
  return vim.fn.fnamemodify(filepath, ":t")
end

function M.get_language(filepath)
  local ext = filepath:match("%.([^.]+)$")
  if not ext then
    return nil
  end
  return M.EXT_TO_LANG[ext:lower()]
end

local function read_file(filepath)
  local stat = vim.loop.fs_stat(filepath)
  if not stat or stat.size > M.MAX_FILE_SIZE then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return nil
  end
  return table.concat(lines, "\n")
end

local function extract_odin_tags_from_content(content, filepath, project_root)
  local rel_fname = get_display_path(filepath, project_root)
  local tags = {}
  local seen = {}
  local noise = {
    proc = true,
    struct = true,
    enum = true,
    union = true,
    bit_set = true,
    distinct = true,
    import = true,
    package = true,
    ["return"] = true,
    ["if"] = true,
    ["for"] = true,
    ["switch"] = true,
    ["when"] = true,
  }

  local function add(kind, tag_type, name, line)
    if not name or name == "" or noise[name] then
      return
    end
    local key = kind .. ":" .. name .. ":" .. line
    if seen[key] then
      return
    end
    seen[key] = true
    table.insert(tags, {
      rel_fname = rel_fname,
      fname = filepath,
      line = line,
      name = name,
      kind = kind,
      type = tag_type,
    })
  end

  local line_no = 0
  for line in content:gmatch("[^\n]+") do
    local name, rhs = line:match("^%s*([%a_][%w_]*)%s*::%s*(.*)$")
    if name and rhs then
      local rhs_unwrapped = rhs:gsub("^%(%s*", "")
      if rhs_unwrapped:match("^proc%f[%W]") then
        add("def", "function", name, line_no)
      elseif rhs_unwrapped:match("^struct%f[%W]") or rhs_unwrapped:match("^enum%f[%W]") or rhs_unwrapped:match("^union%f[%W]") or rhs_unwrapped:match("^bit_set%f[%W]") or rhs_unwrapped:match("^distinct%f[%W]") then
        add("def", "type", name, line_no)
      else
        add("def", "constant", name, line_no)
      end
    end

    for call_name in line:gmatch("([%a_][%w_]*)%s*%(") do
      add("ref", "call", call_name, line_no)
    end

    line_no = line_no + 1
  end

  return tags
end

local function tag_kind(capture_name)
  if capture_name:match("^name%.definition%.") then
    return "def", capture_name:gsub("^name%.definition%.", "")
  end
  if capture_name:match("^name%.reference%.") then
    return "ref", capture_name:gsub("^name%.reference%.", "")
  end
  return nil, nil
end

function M.extract_file_tags(filepath, project_root)
  local lang = M.get_language(filepath)
  if not lang then
    return {}
  end

  local query_string = M.QUERIES[lang]
  if not query_string then
    return {}
  end

  local content = read_file(filepath)
  if not content or content == "" then
    return {}
  end

  if lang == "odin" then
    local tags = extract_odin_tags_from_content(content, filepath, project_root)
    if #tags > 0 then
      return tags
    end
  end

  local ok_parser, parser = pcall(vim.treesitter.get_string_parser, content, lang)
  if not ok_parser or not parser then
    return {}
  end

  local tree = parser:parse()[1]
  if not tree then
    return {}
  end

  local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if not ok_query or not query then
    return {}
  end

  local rel_fname = get_display_path(filepath, project_root)
  local tags = {}
  local seen = {}

  for id, node in query:iter_captures(tree:root(), content, 0, -1) do
    local capture_name = query.captures[id]
    local kind, tag_type = tag_kind(capture_name)
    if kind then
      local name = vim.treesitter.get_node_text(node, content)
      local line = node:start()
      if name and name ~= "" then
        local key = kind .. ":" .. name .. ":" .. line
        if not seen[key] then
          seen[key] = true
          table.insert(tags, {
            rel_fname = rel_fname,
            fname = filepath,
            line = line,
            name = name,
            kind = kind,
            type = tag_type,
          })
        end
      end
    end
  end

  return tags
end

function M.extract_project_tags(project_root, scan_result, opts)
  opts = opts or {}
  scan_result = scan_result or project_scanner.scan_project({ root = project_root })
  local max_files = opts.max_files or 800

  local tags = {}
  local files_seen = 0

  for _, file in ipairs(scan_result.files or {}) do
    if file.type == "source" then
      local filepath = vim.fn.simplify(project_root .. "/" .. file.path)
      if M.get_language(filepath) then
        files_seen = files_seen + 1
        if files_seen > max_files then
          break
        end
        vim.list_extend(tags, M.extract_file_tags(filepath, project_root))
      end
    end
  end

  return tags, { files_scanned = files_seen, tags = #tags, max_files = max_files }
end

return M
