-- tests/behavior_spec.lua
-- Behavior tests for context extraction and parsing
--
-- Tests with mock data that don't require fixtures

local helpers = require("tests.helpers")

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

describe("Full Integration Flow with Mock Data", function()
  describe("TypeScript React component", function()
    it("should parse and extract context", function()
      local content = [[
import { useState, useEffect } from 'react';
import { userService } from '../services/userService';

// Q: How does this component handle authentication state?
export function UserProfile({ userId }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    userService.getUser(userId).then(setUser).finally(() => setLoading(false));
  }, [userId]);

  if (loading) return <div>Loading...</div>;
  return <div>{user?.name}</div>;
}
]]

      local _, q_line_num = helpers.find_q_comment(content)
      assert.is_not_nil(q_line_num)

      local bufnr = helpers.create_mock_buffer(content, "typescriptreact")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { q_line_num, 0 })

      local context = require("editutor.context")
      local ctx = context.extract(bufnr, q_line_num)

      assert.is_not_nil(ctx)
      assert.is_not_nil(ctx.surrounding_code)
      assert.matches("UserProfile", ctx.surrounding_code)
      assert.matches("useState", ctx.surrounding_code)

      local formatted = context.format_for_prompt(ctx)
      assert.is_not_nil(formatted)
      assert.is_true(#formatted > 100)

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("Python code", function()
    it("should parse and extract context", function()
      local content = [[
from typing import List, Optional
from app.models import User

# Q: What is the time complexity of this function?
def find_user_by_email(users: List[User], email: str) -> Optional[User]:
    for user in users:
        if user.email == email:
            return user
    return None
]]

      local _, q_line_num = helpers.find_q_comment(content, "#")
      assert.is_not_nil(q_line_num)

      local bufnr = helpers.create_mock_buffer(content, "python")
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

  describe("Go code", function()
    it("should parse and extract context", function()
      local content = [[
package handlers

import (
    "net/http"
    "github.com/gin-gonic/gin"
)

// Q: What happens if validation fails?
func (h *UserHandler) CreateUser(c *gin.Context) {
    var input CreateUserInput
    if err := c.ShouldBindJSON(&input); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    // Create user...
}
]]

      local _, q_line_num = helpers.find_q_comment(content)
      assert.is_not_nil(q_line_num)

      local bufnr = helpers.create_mock_buffer(content, "go")
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

  describe("Lua code", function()
    it("should parse and extract context", function()
      local content = [[
local M = {}

local config = require("myplugin.config")

-- Q: How does the window resize work?
function M.create_window(opts)
  opts = opts or {}
  local width = opts.width or config.defaults.width
  local height = opts.height or config.defaults.height

  local bufnr = vim.api.nvim_create_buf(false, true)
  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = 5,
    col = 5,
  })

  return bufnr, winnr
end

return M
]]

      local _, q_line_num = helpers.find_q_comment(content, "--")
      assert.is_not_nil(q_line_num)

      local bufnr = helpers.create_mock_buffer(content, "lua")
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

describe("Import Detection", function()
  describe("TypeScript imports", function()
    it("should detect import statements", function()
      local content = [[
import { useState, useEffect } from 'react';
import { User } from '../types/user';
import userService from '../services/userService';

export function MyComponent() {}
]]

      local imports = helpers.extract_ts_imports(content)

      assert.is_true(#imports >= 3)

      local symbols = {}
      for _, imp in ipairs(imports) do
        for _, sym in ipairs(imp.symbols) do
          table.insert(symbols, sym)
        end
      end

      assert.is_true(vim.tbl_contains(symbols, "useState"))
      assert.is_true(vim.tbl_contains(symbols, "User"))
    end)
  end)

  describe("Python imports", function()
    it("should detect from...import statements", function()
      local content = [[
from typing import List, Optional
from app.models.user import User
from app.services import user_service

def my_function():
    pass
]]

      local imports = helpers.extract_python_imports(content)

      assert.is_true(#imports >= 3)

      local has_typing = false
      local has_models = false
      for _, imp in ipairs(imports) do
        if imp.module and imp.module:match("typing") then
          has_typing = true
        end
        if imp.module and imp.module:match("app.models") then
          has_models = true
        end
      end

      assert.is_true(has_typing)
      assert.is_true(has_models)
    end)
  end)

  describe("Go imports", function()
    it("should detect package imports", function()
      local content = [[
package main

import (
    "fmt"
    "net/http"
    "myapp/internal/services"
)

func main() {}
]]

      local imports = helpers.extract_go_imports(content)

      assert.is_true(#imports >= 3)
      assert.is_true(vim.tbl_contains(imports, "fmt"))
      assert.is_true(vim.tbl_contains(imports, "net/http"))
      assert.is_true(vim.tbl_contains(imports, "myapp/internal/services"))
    end)
  end)

  describe("Lua requires", function()
    it("should detect require statements", function()
      local content = [[
local M = {}

local config = require("myplugin.config")
local utils = require("myplugin.utils")
local window = require("myplugin.window")

return M
]]

      local requires = helpers.extract_lua_requires(content)

      assert.is_true(#requires >= 3)
      assert.is_true(vim.tbl_contains(requires, "myplugin.config"))
      assert.is_true(vim.tbl_contains(requires, "myplugin.utils"))
      assert.is_true(vim.tbl_contains(requires, "myplugin.window"))
    end)
  end)
end)
