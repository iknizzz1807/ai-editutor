-- tests/helpers.lua
-- Helper functions for behavior tests

local M = {}

---Read a file and return its contents
---@param filepath string Absolute or relative path to file
---@return string|nil content File contents or nil if not found
function M.read_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

---Find the first Q: comment in content
---@param content string File content
---@param comment_prefix? string Comment prefix (default "//")
---@return string|nil line The Q: comment line
---@return number|nil line_num Line number (1-indexed)
function M.find_q_comment(content, comment_prefix)
  comment_prefix = comment_prefix or "//"
  local line_num = 0

  for line in content:gmatch("[^\n]+") do
    line_num = line_num + 1

    -- Escape the prefix for pattern matching
    local escaped_prefix = comment_prefix:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")

    -- Match Q: comment
    local pattern = escaped_prefix .. "%s*Q:"
    if line:match(pattern) then
      return line, line_num
    end
  end

  return nil, nil
end

---Find all Q/S/R/D/E comments in content
---@param content string File content
---@param comment_prefix? string Comment prefix (default "//")
---@return table[] comments List of {line, line_num, mode, query}
function M.find_all_comments(content, comment_prefix)
  comment_prefix = comment_prefix or "//"
  local comments = {}
  local line_num = 0

  local escaped_prefix = comment_prefix:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")

  for line in content:gmatch("[^\n]+") do
    line_num = line_num + 1

    for _, mode in ipairs({ "Q", "S", "R", "D", "E" }) do
      local pattern = escaped_prefix .. "%s*" .. mode .. ":%s*(.+)"
      local query = line:match(pattern)
      if query then
        table.insert(comments, {
          line = line,
          line_num = line_num,
          mode = mode,
          query = query,
        })
        break
      end
    end
  end

  return comments
end

---Extract import statements from TypeScript/JavaScript content
---@param content string File content
---@return table[] imports List of {line, symbols, source}
function M.extract_ts_imports(content)
  local imports = {}

  for line in content:gmatch("[^\n]+") do
    if line:match("^import") then
      local symbols_str = line:match("{([^}]+)}")
      local source = line:match("from%s+['\"]([^'\"]+)['\"]")

      local symbols = {}
      if symbols_str then
        for symbol in symbols_str:gmatch("([%w_]+)") do
          table.insert(symbols, symbol)
        end
      end

      table.insert(imports, {
        line = line,
        symbols = symbols,
        source = source,
      })
    end
  end

  return imports
end

---Extract import statements from Python content
---@param content string File content
---@return table[] imports List of {line, module, symbols}
function M.extract_python_imports(content)
  local imports = {}

  for line in content:gmatch("[^\n]+") do
    -- from module import symbol1, symbol2
    local module, symbols_str = line:match("^from%s+([%w_.]+)%s+import%s+(.+)")
    if module then
      local symbols = {}
      for symbol in symbols_str:gmatch("([%w_]+)") do
        table.insert(symbols, symbol)
      end
      table.insert(imports, {
        line = line,
        module = module,
        symbols = symbols,
      })
    else
      -- import module
      local mod = line:match("^import%s+([%w_.]+)")
      if mod then
        table.insert(imports, {
          line = line,
          module = mod,
          symbols = {},
        })
      end
    end
  end

  return imports
end

---Extract import statements from Go content
---@param content string File content
---@return string[] imports List of import paths
function M.extract_go_imports(content)
  local imports = {}

  -- Find import block
  local import_block = content:match("import %b()")
  if import_block then
    for path in import_block:gmatch('"([^"]+)"') do
      table.insert(imports, path)
    end
  end

  -- Also check single imports
  for path in content:gmatch('import "([^"]+)"') do
    table.insert(imports, path)
  end

  return imports
end

---Extract require statements from Lua content
---@param content string File content
---@return string[] requires List of required module names
function M.extract_lua_requires(content)
  local requires = {}

  for line in content:gmatch("[^\n]+") do
    local mod = line:match('require%("([^"]+)"%)')
    if mod then
      table.insert(requires, mod)
    end
    -- Also match single quotes
    mod = line:match("require%('([^']+)'%)")
    if mod then
      table.insert(requires, mod)
    end
  end

  return requires
end

---Create a mock buffer with content
---@param content string|string[] Content as string or lines
---@param filetype string Filetype to set
---@return number bufnr Buffer number
function M.create_mock_buffer(content, filetype)
  local bufnr = vim.api.nvim_create_buf(false, true)

  local lines
  if type(content) == "string" then
    lines = vim.split(content, "\n")
  else
    lines = content
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, "filetype", filetype)

  return bufnr
end

---Clean up a mock buffer
---@param bufnr number Buffer number
function M.cleanup_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

---Get the fixture path for a project
---@param project_name string Name of the fixture project
---@return string path Absolute path to fixture
function M.get_fixture_path(project_name)
  local base = vim.fn.fnamemodify("tests/fixtures", ":p")
  return base .. project_name .. "/"
end

---Assert that content contains all expected strings
---@param content string Content to check
---@param expected string[] List of expected strings
---@return boolean success Whether all strings were found
---@return string|nil missing First missing string, if any
function M.assert_contains_all(content, expected)
  for _, exp in ipairs(expected) do
    if not content:match(exp:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")) then
      return false, exp
    end
  end
  return true, nil
end

---Build mock LSP context from fixture files
---@param definitions table[] List of {symbol, filepath, kind}
---@return table lsp_context Mock LSP context structure
function M.build_mock_lsp_context(definitions)
  local result = {
    definitions = {},
    references = {},
  }

  for _, def in ipairs(definitions) do
    local content = M.read_file(def.filepath)
    if content then
      table.insert(result.definitions, {
        symbol = def.symbol,
        filepath = def.filepath,
        content = content,
        kind = def.kind or "unknown",
      })
    end
  end

  return result
end

---Simulate the full editutor flow and capture LLM payload
---@param code string Code content with Q: comment
---@param filetype string Filetype
---@param comment_prefix? string Comment prefix (default "//")
---@return table payload {system_prompt, user_prompt, mode, question, context}
function M.simulate_ask_flow(code, filetype, comment_prefix)
  comment_prefix = comment_prefix or "//"

  local parser = require("editutor.parser")
  local context = require("editutor.context")
  local prompts = require("editutor.prompts")

  -- Create buffer
  local bufnr = M.create_mock_buffer(code, filetype)
  vim.api.nvim_set_current_buf(bufnr)

  -- Find question
  local q_line_content, q_line_num = M.find_q_comment(code, comment_prefix)
  if not q_line_content then
    M.cleanup_buffer(bufnr)
    return nil
  end

  -- Parse question
  local mode, question = parser.parse_line(q_line_content)
  mode = mode and mode:lower() or "question"

  -- Set cursor
  vim.api.nvim_win_set_cursor(0, { q_line_num, 0 })

  -- Extract context
  local ctx = context.extract(bufnr, q_line_num)
  local formatted_context = context.format_for_prompt(ctx)

  -- Build prompts
  local system_prompt = prompts.get_system_prompt(mode)
  local user_prompt = prompts.build_user_prompt(question, formatted_context, mode)

  M.cleanup_buffer(bufnr)

  return {
    system_prompt = system_prompt,
    user_prompt = user_prompt,
    mode = mode,
    question = question,
    context = ctx,
    formatted_context = formatted_context,
  }
end

---Simulate inserting a response and return final buffer content
---@param code string Original code
---@param response string LLM response
---@param filetype string Filetype
---@param comment_prefix? string Comment prefix
---@return string final_code Final code with response inserted
function M.simulate_response_insertion(code, response, filetype, comment_prefix)
  comment_prefix = comment_prefix or "//"

  local comment_writer = require("editutor.comment_writer")

  -- Create buffer
  local bufnr = M.create_mock_buffer(code, filetype)
  vim.api.nvim_set_current_buf(bufnr)

  -- Find question line
  local _, q_line_num = M.find_q_comment(code, comment_prefix)
  if not q_line_num then
    M.cleanup_buffer(bufnr)
    return code
  end

  -- Insert response
  comment_writer.insert_or_replace(response, q_line_num, bufnr)

  -- Get final content
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local final_code = table.concat(lines, "\n")

  M.cleanup_buffer(bufnr)

  return final_code
end

---Print the full LLM payload for debugging
---@param payload table From simulate_ask_flow
function M.print_llm_payload(payload)
  if not payload then
    print("No payload generated")
    return
  end

  print("\n" .. string.rep("=", 70))
  print("LLM PAYLOAD DEBUG")
  print(string.rep("=", 70))
  print(string.format("Mode: %s", payload.mode))
  print(string.format("Question: %s", payload.question))
  print(string.rep("-", 70))
  print("SYSTEM PROMPT:")
  print(string.rep("-", 70))
  print(payload.system_prompt)
  print(string.rep("-", 70))
  print("USER PROMPT:")
  print(string.rep("-", 70))
  print(payload.user_prompt)
  print(string.rep("=", 70) .. "\n")
end

return M
