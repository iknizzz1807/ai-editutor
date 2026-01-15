-- tests/generate_snapshots.lua
-- Script to generate snapshot data for documentation
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/generate_snapshots.lua

local helpers = require("tests.helpers")
local context = require("editutor.context")
local prompts = require("editutor.prompts")
local parser = require("editutor.parser")

local function generate_snapshot(opts)
  local content = helpers.read_file(opts.filepath)
  if not content then
    print("ERROR: Could not read " .. opts.filepath)
    return nil
  end

  local bufnr = helpers.create_mock_buffer(content, opts.filetype)
  vim.api.nvim_set_current_buf(bufnr)

  local q_line_content, q_line_num = helpers.find_q_comment(content, opts.comment_prefix)
  if not q_line_content then
    print("ERROR: No Q: comment found in " .. opts.filepath)
    helpers.cleanup_buffer(bufnr)
    return nil
  end

  local mode, question = parser.parse_line(q_line_content)
  mode = mode and mode:lower() or "question"

  vim.api.nvim_win_set_cursor(0, { q_line_num, 0 })
  local ctx = context.extract(bufnr, q_line_num)
  local formatted_context = context.format_for_prompt(ctx)

  local system_prompt = prompts.get_system_prompt(mode)
  local user_prompt = prompts.build_user_prompt(question, formatted_context, mode)

  helpers.cleanup_buffer(bufnr)

  return {
    filepath = opts.filepath,
    filetype = opts.filetype,
    q_line_num = q_line_num,
    q_line_content = q_line_content,
    mode = mode,
    question = question,
    context = ctx,
    formatted_context = formatted_context,
    system_prompt = system_prompt,
    user_prompt = user_prompt,
  }
end

local function print_snapshot(snapshot, name)
  print(string.rep("=", 80))
  print("SNAPSHOT: " .. name)
  print(string.rep("=", 80))
  print("")
  print("File: " .. snapshot.filepath)
  print("Filetype: " .. snapshot.filetype)
  print("Q Line Number: " .. snapshot.q_line_num)
  print("Q Line: " .. snapshot.q_line_content)
  print("Mode: " .. snapshot.mode)
  print("Question: " .. (snapshot.question or "N/A"))
  print("")
  print("--- FORMATTED CONTEXT ---")
  print(snapshot.formatted_context or "N/A")
  print("")
  print("--- SYSTEM PROMPT (first 500 chars) ---")
  print(snapshot.system_prompt:sub(1, 500))
  print("...")
  print("")
  print("--- USER PROMPT ---")
  print(snapshot.user_prompt)
  print("")
end

-- Generate snapshots
local snapshots = {
  {
    name = "typescript-useauth",
    filepath = "tests/fixtures/typescript-fullstack/src/hooks/useAuth.ts",
    filetype = "typescript",
    comment_prefix = "//",
  },
  {
    name = "python-serializer",
    filepath = "tests/fixtures/python-django/myapp/serializers/user.py",
    filetype = "python",
    comment_prefix = "#",
  },
  {
    name = "go-repository",
    filepath = "tests/fixtures/go-gin/repository/user_repository.go",
    filetype = "go",
    comment_prefix = "//",
  },
}

for _, opts in ipairs(snapshots) do
  local snapshot = generate_snapshot(opts)
  if snapshot then
    print_snapshot(snapshot, opts.name)
  end
end

print("\nDone generating snapshots.")
