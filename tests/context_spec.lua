-- tests/context_spec.lua
-- Unit tests for context extraction module

local context = require("editutor.context")

describe("context", function()
  describe("format_for_prompt", function()
    it("should format basic context", function()
      local ctx = {
        language = "lua",
        filename = "test.lua",
        filepath = "/project/test.lua",
        surrounding_code = "local x = 1",
        question_line = 10,
      }

      local result = context.format_for_prompt(ctx)

      assert.is_not_nil(result)
      assert.is_true(result:find("Language: lua") ~= nil)
      assert.is_true(result:find("File: test.lua") ~= nil)
      assert.is_true(result:find("local x = 1") ~= nil)
    end)

    it("should include current function if present", function()
      local ctx = {
        language = "python",
        filename = "test.py",
        filepath = "/project/test.py",
        surrounding_code = "def foo(): pass",
        current_function = "calculate_sum",
        question_line = 5,
      }

      local result = context.format_for_prompt(ctx)

      assert.is_true(result:find("Current function: calculate_sum") ~= nil)
    end)

    it("should include imports if present", function()
      local ctx = {
        language = "python",
        filename = "test.py",
        filepath = "/project/test.py",
        surrounding_code = "x = 1",
        imports = "import os\nimport sys",
        question_line = 10,
      }

      local result = context.format_for_prompt(ctx)

      assert.is_true(result:find("Imports:") ~= nil)
      assert.is_true(result:find("import os") ~= nil)
    end)

    it("should wrap code in markdown code blocks", function()
      local ctx = {
        language = "javascript",
        filename = "test.js",
        filepath = "/project/test.js",
        surrounding_code = "const x = 1;",
        question_line = 1,
      }

      local result = context.format_for_prompt(ctx)

      assert.is_true(result:find("```javascript") ~= nil)
      assert.is_true(result:find("```", 1, true) ~= nil)
    end)
  end)

  describe("format_lsp_context", function()
    it("should format current file context", function()
      local ctx = {
        current = {
          filepath = "/project/src/main.lua",
          content = "local M = {}\nreturn M",
          start_line = 0,
          end_line = 10,
          cursor_line = 5,
        },
        external = {},
        has_lsp = true,
      }

      local result = context.format_lsp_context(ctx)

      assert.is_not_nil(result)
      assert.is_true(result:find("Language: lua") ~= nil)
      assert.is_true(result:find("Current Code") ~= nil)
      assert.is_true(result:find("local M = {}") ~= nil)
    end)

    it("should include external definitions", function()
      local ctx = {
        current = {
          filepath = "/project/src/main.lua",
          content = "local config = require('config')",
          start_line = 0,
          end_line = 5,
          cursor_line = 0,
        },
        external = {
          {
            name = "config",
            filepath = "/project/src/config.lua",
            content = "local M = {}\nM.debug = true\nreturn M",
            start_line = 0,
            end_line = 10,
          },
        },
        has_lsp = true,
      }

      local result = context.format_lsp_context(ctx)

      assert.is_true(result:find("Related Definitions") ~= nil)
      assert.is_true(result:find("config.lua") ~= nil)
      assert.is_true(result:find("M.debug = true") ~= nil)
    end)

    it("should show LSP not available note", function()
      local ctx = {
        current = {
          filepath = "/project/test.py",
          content = "x = 1",
          start_line = 0,
          end_line = 1,
          cursor_line = 0,
        },
        external = {},
        has_lsp = false,
      }

      local result = context.format_lsp_context(ctx)

      assert.is_true(result:find("LSP not available") ~= nil)
    end)

    it("should detect language from file extension", function()
      local test_cases = {
        { filepath = "/test.py", expected = "python" },
        { filepath = "/test.js", expected = "javascript" },
        { filepath = "/test.ts", expected = "typescript" },
        { filepath = "/test.go", expected = "go" },
        { filepath = "/test.rs", expected = "rust" },
        { filepath = "/test.lua", expected = "lua" },
      }

      for _, tc in ipairs(test_cases) do
        local ctx = {
          current = {
            filepath = tc.filepath,
            content = "code",
            start_line = 0,
            end_line = 1,
            cursor_line = 0,
          },
          external = {},
          has_lsp = true,
        }

        local result = context.format_lsp_context(ctx)
        assert.is_true(result:find("Language: " .. tc.expected) ~= nil,
          "Failed for " .. tc.filepath .. ", expected " .. tc.expected)
      end
    end)
  end)

  describe("has_lsp", function()
    it("should return a boolean", function()
      local result = context.has_lsp()
      assert.is_boolean(result)
    end)
  end)
end)
