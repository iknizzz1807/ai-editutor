-- tests/behavior_spec.lua
-- Behavior tests for context extraction with real project fixtures
--
-- These tests verify that when a user positions their cursor at a Q: comment
-- in a real project structure, the context extraction produces correct results.

local helpers = require("tests.helpers")

describe("Behavior Tests", function()
  local fixtures_path = vim.fn.fnamemodify("tests/fixtures", ":p")

  before_each(function()
    -- Clear all buffers
    vim.cmd("bufdo bwipeout!")
  end)

  describe("TypeScript React Project", function()
    local project_path = fixtures_path .. "typescript-react/"

    describe("UserProfile.tsx context extraction", function()
      it("should identify the Q: comment about authentication state", function()
        local filepath = project_path .. "src/components/UserProfile.tsx"
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        -- Find the Q: comment line
        local q_line, q_line_num = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("How does this component handle authentication state", q_line)

        -- Parse the comment using actual parser API
        local parser = require("editutor.parser")
        local mode, question = parser.parse_line(q_line)

        assert.is_not_nil(mode)
        assert.equals("Q", mode)
        assert.is_not_nil(question)
        assert.matches("authentication state", question)
      end)

      it("should extract correct code context around the question", function()
        local filepath = project_path .. "src/components/UserProfile.tsx"
        local content = helpers.read_file(filepath)
        local lines = vim.split(content, "\n")

        -- Find line number of Q: comment
        local _, q_line_num = helpers.find_q_comment(content)
        assert.is_not_nil(q_line_num)

        -- Extract surrounding code (simulating what context.lua does)
        local start_line = math.max(1, q_line_num - 30)
        local end_line = math.min(#lines, q_line_num + 30)
        local surrounding = {}
        for i = start_line, end_line do
          table.insert(surrounding, lines[i])
        end
        local surrounding_code = table.concat(surrounding, "\n")

        -- Verify key code elements are present
        assert.matches("useAuth", surrounding_code)
        assert.matches("useState", surrounding_code)
        assert.matches("UserProfile", surrounding_code)
      end)

      it("should recognize imports that need LSP resolution", function()
        local filepath = project_path .. "src/components/UserProfile.tsx"
        local content = helpers.read_file(filepath)

        -- Verify cross-file imports exist
        assert.matches("import.*useAuth.*from.*hooks/useAuth", content)
        assert.matches("import.*User.*from.*types/user", content)
        assert.matches("import.*userService.*from.*services/userService", content)
      end)
    end)

    describe("useAuth hook context", function()
      it("should have references to authService", function()
        local filepath = project_path .. "src/hooks/useAuth.ts"
        local content = helpers.read_file(filepath)

        assert.matches("import.*authService.*from.*services/authService", content)
        assert.matches("authService%.login", content)
        assert.matches("authService%.logout", content)
      end)
    end)

    describe("authService context", function()
      it("should have references to apiClient and User type", function()
        local filepath = project_path .. "src/services/authService.ts"
        local content = helpers.read_file(filepath)

        assert.matches("import.*apiClient.*from.*apiClient", content)
        assert.matches("import.*User.*from.*types/user", content)
      end)
    end)
  end)

  describe("Python FastAPI Project", function()
    local project_path = fixtures_path .. "python-fastapi/"

    describe("auth_service.py context extraction", function()
      it("should identify Q: comment about token validation", function()
        local filepath = project_path .. "app/services/auth_service.py"
        local content = helpers.read_file(filepath)

        local q_line, _ = helpers.find_q_comment(content, "#")
        assert.is_not_nil(q_line)
        assert.matches("token validation", q_line)

        local parser = require("editutor.parser")
        local mode, question = parser.parse_line(q_line)

        assert.is_not_nil(mode)
        assert.equals("Q", mode)
      end)

      it("should have cross-module imports", function()
        local filepath = project_path .. "app/services/auth_service.py"
        local content = helpers.read_file(filepath)

        assert.matches("from app.models.user import User", content)
        assert.matches("from app.config import settings", content)
      end)
    end)

    describe("users router context extraction", function()
      it("should identify Q: comment about user validation", function()
        local filepath = project_path .. "app/routers/users.py"
        local content = helpers.read_file(filepath)

        local q_line, _ = helpers.find_q_comment(content, "#")
        assert.is_not_nil(q_line)
        assert.matches("validation", q_line)
      end)

      it("should have cross-module dependencies", function()
        local filepath = project_path .. "app/routers/users.py"
        local content = helpers.read_file(filepath)

        assert.matches("from app.services.user_service import", content)
        assert.matches("from app.services.auth_service import", content)
        assert.matches("from app.models.user import", content)
      end)
    end)

    describe("models relationships", function()
      it("should define User model with proper schema", function()
        local filepath = project_path .. "app/models/user.py"
        local content = helpers.read_file(filepath)

        assert.matches("class User", content)
        assert.matches("class UserCreate", content)
        assert.matches("class UserResponse", content)
      end)
    end)
  end)

  describe("Go API Project", function()
    local project_path = fixtures_path .. "go-api/"

    describe("auth_service.go context extraction", function()
      it("should identify Q: comment about token expiration", function()
        local filepath = project_path .. "internal/services/auth_service.go"
        local content = helpers.read_file(filepath)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("token expiration", q_line)

        local parser = require("editutor.parser")
        local mode, question = parser.parse_line(q_line)

        assert.is_not_nil(mode)
        assert.equals("Q", mode)
      end)

      it("should import models package", function()
        local filepath = project_path .. "internal/services/auth_service.go"
        local content = helpers.read_file(filepath)

        assert.matches('myapp/internal/models', content)
        assert.matches('myapp/internal/config', content)
      end)
    end)

    describe("user_handler.go context extraction", function()
      it("should identify Q: comment about validation", function()
        local filepath = project_path .. "internal/handlers/user_handler.go"
        local content = helpers.read_file(filepath)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("validation fails", q_line)
      end)

      it("should import services package", function()
        local filepath = project_path .. "internal/handlers/user_handler.go"
        local content = helpers.read_file(filepath)

        assert.matches('myapp/internal/services', content)
        assert.matches('myapp/internal/models', content)
      end)
    end)

    describe("models package", function()
      it("should define User struct with DTOs", function()
        local filepath = project_path .. "internal/models/user.go"
        local content = helpers.read_file(filepath)

        assert.matches("type User struct", content)
        assert.matches("type CreateUserInput struct", content)
        assert.matches("type UserResponse struct", content)
      end)
    end)
  end)

  describe("Lua Neovim Plugin Project", function()
    local project_path = fixtures_path .. "lua-nvim/"

    describe("window.lua context extraction", function()
      it("should identify Q: comment about window resize", function()
        local filepath = project_path .. "lua/myplugin/window.lua"
        local content = helpers.read_file(filepath)

        -- Lua uses -- for comments
        local q_line, _ = helpers.find_q_comment(content, "--")
        assert.is_not_nil(q_line, "Should find Q: comment in window.lua")
        assert.matches("window resize", q_line)

        local parser = require("editutor.parser")
        local mode, question = parser.parse_line(q_line)

        assert.is_not_nil(mode, "Parser should recognize -- Q: comment")
        assert.equals("Q", mode)
      end)

      it("should require config and utils modules", function()
        local filepath = project_path .. "lua/myplugin/window.lua"
        local content = helpers.read_file(filepath)

        assert.matches('require%("myplugin.config"%)', content)
        assert.matches('require%("myplugin.utils"%)', content)
      end)
    end)

    describe("init.lua module structure", function()
      it("should require all plugin modules", function()
        local filepath = project_path .. "lua/myplugin/init.lua"
        local content = helpers.read_file(filepath)

        assert.matches('require%("myplugin.config"%)', content)
        assert.matches('require%("myplugin.utils"%)', content)
        assert.matches('require%("myplugin.window"%)', content)
      end)

      it("should expose setup function", function()
        local filepath = project_path .. "lua/myplugin/init.lua"
        local content = helpers.read_file(filepath)

        assert.matches("function M.setup", content)
      end)
    end)

    describe("utils.lua dependencies", function()
      it("should require config module", function()
        local filepath = project_path .. "lua/myplugin/utils.lua"
        local content = helpers.read_file(filepath)

        assert.matches('require%("myplugin.config"%)', content)
      end)
    end)
  end)
end)

describe("Context Module", function()
  describe("extract function", function()
    it("should extract context from a buffer", function()
      local content = [[
import { useState } from 'react';

// Q: How does useState work?
function Counter() {
  const [count, setCount] = useState(0);
  return <button onClick={() => setCount(count + 1)}>{count}</button>;
}
]]
      local bufnr = helpers.create_mock_buffer(content, "typescriptreact")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 4, 0 }) -- Line with Q:

      local context = require("editutor.context")
      local ctx = context.extract(bufnr, 4)

      assert.is_not_nil(ctx)
      assert.is_not_nil(ctx.language)
      assert.is_not_nil(ctx.surrounding_code)
      assert.matches("useState", ctx.surrounding_code)

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("format_for_prompt function", function()
    it("should format context correctly", function()
      local context = require("editutor.context")

      local ctx = {
        language = "typescript",
        filepath = "/test/project/src/main.ts",
        filename = "main.ts",
        filetype = "typescript",
        surrounding_code = "function test() { return 1; }",
        current_function = "test",
        imports = "import { x } from 'y';",
        question_line = 5,
      }

      local formatted = context.format_for_prompt(ctx)

      assert.is_not_nil(formatted)
      assert.matches("Language: typescript", formatted)
      assert.matches("File: main.ts", formatted)
      assert.matches("Current function: test", formatted)
      assert.matches("Imports:", formatted)
      assert.matches("Code context", formatted)
    end)

    it("should handle context without optional fields", function()
      local context = require("editutor.context")

      local ctx = {
        language = "python",
        filepath = "/test/main.py",
        filename = "main.py",
        filetype = "python",
        surrounding_code = "print('hello')",
        question_line = 1,
      }

      local formatted = context.format_for_prompt(ctx)

      assert.is_not_nil(formatted)
      assert.matches("Language: python", formatted)
      assert.matches("File: main.py", formatted)
    end)
  end)
end)

describe("Cross-file Reference Detection", function()
  local fixtures_path = vim.fn.fnamemodify("tests/fixtures", ":p")

  describe("TypeScript imports", function()
    it("should detect import statements for LSP resolution", function()
      local filepath = fixtures_path .. "typescript-react/src/components/UserProfile.tsx"
      local content = helpers.read_file(filepath)

      -- Extract import lines
      local imports = {}
      for line in content:gmatch("[^\n]+") do
        if line:match("^import") then
          table.insert(imports, line)
        end
      end

      -- Should have multiple imports
      assert.is_true(#imports >= 3)

      -- Each import represents a symbol that LSP should resolve
      local symbols_to_resolve = {}
      for _, imp in ipairs(imports) do
        -- Extract imported names
        local names = imp:match("{([^}]+)}")
        if names then
          for name in names:gmatch("([%w_]+)") do
            table.insert(symbols_to_resolve, name)
          end
        end
      end

      assert.is_true(vim.tbl_contains(symbols_to_resolve, "useAuth"))
      assert.is_true(vim.tbl_contains(symbols_to_resolve, "User"))
      assert.is_true(vim.tbl_contains(symbols_to_resolve, "userService"))
    end)
  end)

  describe("Python imports", function()
    it("should detect from...import statements", function()
      local filepath = fixtures_path .. "python-fastapi/app/routers/users.py"
      local content = helpers.read_file(filepath)

      local imports = {}
      for line in content:gmatch("[^\n]+") do
        if line:match("^from") or line:match("^import") then
          table.insert(imports, line)
        end
      end

      assert.is_true(#imports >= 3)

      -- Should import from local modules
      local has_service_import = false
      local has_model_import = false
      for _, imp in ipairs(imports) do
        if imp:match("app%.services") then
          has_service_import = true
        end
        if imp:match("app%.models") then
          has_model_import = true
        end
      end

      assert.is_true(has_service_import)
      assert.is_true(has_model_import)
    end)
  end)

  describe("Go imports", function()
    it("should detect package imports", function()
      local filepath = fixtures_path .. "go-api/internal/handlers/user_handler.go"
      local content = helpers.read_file(filepath)

      -- Go uses import block
      local import_block = content:match("import %b()")
      assert.is_not_nil(import_block)

      -- Should import internal packages
      assert.matches("myapp/internal/services", import_block)
      assert.matches("myapp/internal/models", import_block)
    end)
  end)

  describe("Lua requires", function()
    it("should detect require statements", function()
      local filepath = fixtures_path .. "lua-nvim/lua/myplugin/init.lua"
      local content = helpers.read_file(filepath)

      local requires = {}
      for line in content:gmatch("[^\n]+") do
        local req = line:match('require%("([^"]+)"%)')
        if req then
          table.insert(requires, req)
        end
      end

      assert.is_true(#requires >= 3)
      assert.is_true(vim.tbl_contains(requires, "myplugin.config"))
      assert.is_true(vim.tbl_contains(requires, "myplugin.utils"))
      assert.is_true(vim.tbl_contains(requires, "myplugin.window"))
    end)
  end)
end)

describe("Parser Multi-Language Support", function()
  local parser = require("editutor.parser")

  describe("Comment syntax variations", function()
    it("should parse // style comments (C, JS, Go, etc.)", function()
      local mode, question = parser.parse_line("// Q: What is this function doing?")
      assert.equals("Q", mode)
      assert.matches("What is this function doing", question)
    end)

    it("should parse # style comments (Python, Ruby, Shell)", function()
      local mode, question = parser.parse_line("# Q: How does this work?")
      assert.equals("Q", mode)
      assert.matches("How does this work", question)
    end)

    it("should parse -- style comments (Lua, SQL, Haskell)", function()
      local mode, question = parser.parse_line("-- Q: Why is this needed?")
      assert.equals("Q", mode)
      assert.matches("Why is this needed", question)
    end)

    it("should parse ; style comments (Lisp, Assembly)", function()
      local mode, question = parser.parse_line("; Q: What does this do?")
      assert.equals("Q", mode)
      assert.matches("What does this do", question)
    end)

    it("should handle leading whitespace", function()
      local mode, question = parser.parse_line("    // Q: Indented question?")
      assert.equals("Q", mode)
      assert.matches("Indented question", question)
    end)

    it("should recognize all modes", function()
      local modes_to_test = {
        { "// Q: Question mode", "Q" },
        { "// S: Socratic mode", "S" },
        { "// R: Review mode", "R" },
        { "// D: Debug mode", "D" },
        { "// E: Explain mode", "E" },
      }

      for _, test in ipairs(modes_to_test) do
        local mode, _ = parser.parse_line(test[1])
        assert.equals(test[2], mode, "Mode should match for: " .. test[1])
      end
    end)
  end)
end)

describe("Full Integration Flow", function()
  local fixtures_path = vim.fn.fnamemodify("tests/fixtures", ":p")

  describe("TypeScript React component", function()
    it("should parse and extract context for a real file", function()
      local filepath = fixtures_path .. "typescript-react/src/components/UserProfile.tsx"
      local content = helpers.read_file(filepath)
      local lines = vim.split(content, "\n")

      -- Find Q: comment line
      local _, q_line_num = helpers.find_q_comment(content)
      assert.is_not_nil(q_line_num)

      -- Create buffer
      local bufnr = helpers.create_mock_buffer(lines, "typescriptreact")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { q_line_num, 0 })

      -- Extract context
      local context = require("editutor.context")
      local ctx = context.extract(bufnr, q_line_num)

      -- Verify context structure
      assert.is_not_nil(ctx)
      assert.is_not_nil(ctx.surrounding_code)
      assert.matches("UserProfile", ctx.surrounding_code)

      -- Format for prompt
      local formatted = context.format_for_prompt(ctx)
      assert.is_not_nil(formatted)
      assert.is_true(#formatted > 100, "Formatted context should be substantial")

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("Python FastAPI router", function()
    it("should parse and extract context for a real file", function()
      local filepath = fixtures_path .. "python-fastapi/app/routers/users.py"
      local content = helpers.read_file(filepath)
      local lines = vim.split(content, "\n")

      local _, q_line_num = helpers.find_q_comment(content, "#")
      assert.is_not_nil(q_line_num)

      local bufnr = helpers.create_mock_buffer(lines, "python")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { q_line_num, 0 })

      local context = require("editutor.context")
      local ctx = context.extract(bufnr, q_line_num)

      assert.is_not_nil(ctx)
      assert.is_not_nil(ctx.surrounding_code)

      local formatted = context.format_for_prompt(ctx)
      assert.is_not_nil(formatted)
      assert.is_true(#formatted > 100)

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("Go handler", function()
    it("should parse and extract context for a real file", function()
      local filepath = fixtures_path .. "go-api/internal/handlers/user_handler.go"
      local content = helpers.read_file(filepath)
      local lines = vim.split(content, "\n")

      local _, q_line_num = helpers.find_q_comment(content)
      assert.is_not_nil(q_line_num)

      local bufnr = helpers.create_mock_buffer(lines, "go")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { q_line_num, 0 })

      local context = require("editutor.context")
      local ctx = context.extract(bufnr, q_line_num)

      assert.is_not_nil(ctx)
      assert.is_not_nil(ctx.surrounding_code)

      local formatted = context.format_for_prompt(ctx)
      assert.is_not_nil(formatted)
      assert.is_true(#formatted > 100)

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("Lua Neovim plugin", function()
    it("should parse and extract context for a real file", function()
      local filepath = fixtures_path .. "lua-nvim/lua/myplugin/window.lua"
      local content = helpers.read_file(filepath)
      local lines = vim.split(content, "\n")

      local _, q_line_num = helpers.find_q_comment(content, "--")
      assert.is_not_nil(q_line_num, "Should find Q: comment in Lua file")

      local bufnr = helpers.create_mock_buffer(lines, "lua")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { q_line_num, 0 })

      local context = require("editutor.context")
      local ctx = context.extract(bufnr, q_line_num)

      assert.is_not_nil(ctx)
      assert.is_not_nil(ctx.surrounding_code)

      local formatted = context.format_for_prompt(ctx)
      assert.is_not_nil(formatted)
      assert.is_true(#formatted > 100)

      helpers.cleanup_buffer(bufnr)
    end)
  end)
end)
