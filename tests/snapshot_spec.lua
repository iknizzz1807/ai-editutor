-- tests/snapshot_spec.lua
-- Validates that LLM payloads match documented snapshots
--
-- Each snapshot in tests/snapshots/*.md documents:
-- 1. Input: file path, Q: comment location
-- 2. Output: extracted context, system prompt, user prompt
--
-- This test ensures the actual extraction matches the documented behavior.

local helpers = require("tests.helpers")
local context = require("editutor.context")
local prompts = require("editutor.prompts")
local parser = require("editutor.parser")

---Generate actual snapshot data for a test case
---@param opts table {filepath, filetype, comment_prefix}
---@return table|nil snapshot
local function generate_snapshot(opts)
  local content = helpers.read_file(opts.filepath)
  if not content then
    return nil
  end

  local bufnr = helpers.create_mock_buffer(content, opts.filetype)
  vim.api.nvim_set_current_buf(bufnr)

  local q_line_content, q_line_num = helpers.find_q_comment(content, opts.comment_prefix)
  if not q_line_content then
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

describe("Snapshot Validation", function()
  describe("TypeScript useAuth Hook", function()
    local snapshot

    before_each(function()
      snapshot = generate_snapshot({
        filepath = "tests/fixtures/typescript-fullstack/src/hooks/useAuth.ts",
        filetype = "typescript",
        comment_prefix = "//",
      })
    end)

    it("should find Q: comment at expected location", function()
      assert.is_not_nil(snapshot, "Should generate snapshot")
      assert.is_not_nil(snapshot.q_line_num, "Should find Q: line")
      assert.matches("logout", snapshot.q_line_content:lower())
      assert.matches("cleanup", snapshot.q_line_content:lower())
    end)

    it("should extract question correctly", function()
      assert.equals("q", snapshot.mode)
      assert.matches("logout", snapshot.question:lower())
      assert.matches("cleanup", snapshot.question:lower())
    end)

    it("should include imports in context", function()
      assert.matches("authService", snapshot.formatted_context)
      assert.matches("useState", snapshot.formatted_context)
      assert.matches("useCallback", snapshot.formatted_context)
    end)

    it("should include surrounding code in context", function()
      assert.matches("const logout", snapshot.formatted_context)
      assert.matches("authService.logout", snapshot.formatted_context)
    end)

    it("should generate system prompt with teaching guidelines", function()
      assert.matches("TEACH", snapshot.system_prompt)
      assert.matches("INLINE COMMENT", snapshot.system_prompt)
      assert.matches("CONCISE", snapshot.system_prompt)
    end)

    it("should generate user prompt with mode and context", function()
      assert.matches("Mode: Q", snapshot.user_prompt)
      assert.matches("Language: typescript", snapshot.user_prompt)
      assert.matches("Question:", snapshot.user_prompt)
    end)

    it("should print full payload for documentation", function()
      print("\n" .. string.rep("=", 70))
      print("TYPESCRIPT USEAUTH - FULL LLM PAYLOAD")
      print(string.rep("=", 70))
      print("\n--- INPUT ---")
      print("File: " .. snapshot.filepath)
      print("Q Line: " .. snapshot.q_line_num)
      print("Question: " .. snapshot.question)
      print("\n--- SYSTEM PROMPT ---")
      print(snapshot.system_prompt:sub(1, 500) .. "...")
      print("\n--- USER PROMPT ---")
      print(snapshot.user_prompt)
      print(string.rep("=", 70) .. "\n")
    end)
  end)

  describe("Python Django Serializer", function()
    local snapshot

    before_each(function()
      snapshot = generate_snapshot({
        filepath = "tests/fixtures/python-django/myapp/serializers/user.py",
        filetype = "python",
        comment_prefix = "#",
      })
    end)

    it("should find Q: comment about race condition", function()
      assert.is_not_nil(snapshot)
      assert.matches("race condition", snapshot.q_line_content:lower())
    end)

    it("should extract question correctly", function()
      assert.equals("q", snapshot.mode)
      assert.matches("email", snapshot.question:lower())
      assert.matches("race condition", snapshot.question:lower())
    end)

    it("should include Django imports in context", function()
      assert.matches("rest_framework", snapshot.formatted_context)
      assert.matches("serializers", snapshot.formatted_context)
    end)

    it("should include serializer class in context", function()
      assert.matches("UserCreateSerializer", snapshot.formatted_context)
      assert.matches("validate", snapshot.formatted_context)
    end)

    it("should generate system prompt for Python", function()
      assert.matches("TEACH", snapshot.system_prompt)
      assert.matches("INLINE COMMENT", snapshot.system_prompt)
    end)

    it("should generate user prompt with Python context", function()
      assert.matches("Mode: Q", snapshot.user_prompt)
      assert.matches("Language: python", snapshot.user_prompt)
    end)

    it("should print full payload for documentation", function()
      print("\n" .. string.rep("=", 70))
      print("PYTHON SERIALIZER - FULL LLM PAYLOAD")
      print(string.rep("=", 70))
      print("\n--- INPUT ---")
      print("File: " .. snapshot.filepath)
      print("Q Line: " .. snapshot.q_line_num)
      print("Question: " .. snapshot.question)
      print("\n--- USER PROMPT (first 1000 chars) ---")
      print(snapshot.user_prompt:sub(1, 1000))
      print(string.rep("=", 70) .. "\n")
    end)
  end)

  describe("Go Gin Repository", function()
    local snapshot

    before_each(function()
      snapshot = generate_snapshot({
        filepath = "tests/fixtures/go-gin/repository/user_repository.go",
        filetype = "go",
        comment_prefix = "//",
      })
    end)

    it("should find Q: comment about pagination", function()
      assert.is_not_nil(snapshot)
      assert.matches("pagination", snapshot.q_line_content:lower())
    end)

    it("should extract question correctly", function()
      assert.equals("q", snapshot.mode)
      assert.matches("cursor", snapshot.question:lower())
      assert.matches("pagination", snapshot.question:lower())
    end)

    it("should include Go imports in context", function()
      assert.matches("gorm", snapshot.formatted_context)
      assert.matches("context", snapshot.formatted_context)
    end)

    it("should include repository methods in context", function()
      assert.matches("UserRepository", snapshot.formatted_context)
      assert.matches("List", snapshot.formatted_context)
    end)

    it("should generate user prompt with Go context", function()
      assert.matches("Mode: Q", snapshot.user_prompt)
      assert.matches("Language: go", snapshot.user_prompt)
    end)

    it("should print full payload for documentation", function()
      print("\n" .. string.rep("=", 70))
      print("GO REPOSITORY - FULL LLM PAYLOAD")
      print(string.rep("=", 70))
      print("\n--- INPUT ---")
      print("File: " .. snapshot.filepath)
      print("Q Line: " .. snapshot.q_line_num)
      print("Question: " .. snapshot.question)
      print("\n--- USER PROMPT (first 1000 chars) ---")
      print(snapshot.user_prompt:sub(1, 1000))
      print(string.rep("=", 70) .. "\n")
    end)
  end)
end)

describe("Snapshot Consistency", function()
  it("should generate consistent payloads across runs", function()
    local opts = {
      filepath = "tests/fixtures/typescript-fullstack/src/hooks/useAuth.ts",
      filetype = "typescript",
      comment_prefix = "//",
    }

    local snapshot1 = generate_snapshot(opts)
    local snapshot2 = generate_snapshot(opts)

    assert.equals(snapshot1.q_line_num, snapshot2.q_line_num)
    assert.equals(snapshot1.question, snapshot2.question)
    assert.equals(snapshot1.system_prompt, snapshot2.system_prompt)
    assert.equals(snapshot1.user_prompt, snapshot2.user_prompt)
  end)

  it("should include all required sections in user prompt", function()
    local snapshot = generate_snapshot({
      filepath = "tests/fixtures/typescript-fullstack/src/hooks/useAuth.ts",
      filetype = "typescript",
      comment_prefix = "//",
    })

    -- Required sections
    assert.matches("Mode:", snapshot.user_prompt)
    assert.matches("Context:", snapshot.user_prompt)
    assert.matches("Language:", snapshot.user_prompt)
    assert.matches("Code context", snapshot.user_prompt)
    assert.matches("Question:", snapshot.user_prompt)
  end)
end)
