-- tests/e2e_flow_spec.lua
-- End-to-end tests showing complete flow from Q: comment to LLM payload
--
-- This test file demonstrates:
-- 1. What context gets extracted from real fixture projects
-- 2. What system prompt is generated for each mode
-- 3. What user prompt is sent to the LLM
-- 4. How the response is formatted as inline comments

local helpers = require("tests.helpers")

describe("End-to-End Flow", function()
  local fixtures_path = vim.fn.fnamemodify("tests/fixtures", ":p")

  before_each(function()
    -- Reset config
    require("editutor.config").setup({
      language = "English",
      default_mode = "question",
    })
    vim.cmd("bufdo bwipeout!")
  end)

  describe("TypeScript Fullstack Project", function()
    local project_path = fixtures_path .. "typescript-fullstack/"

    it("should generate complete LLM payload for useAuth hook", function()
      local filepath = project_path .. "src/hooks/useAuth.ts"
      local content = helpers.read_file(filepath)

      if not content then
        pending("Fixture file not found: " .. filepath)
        return
      end

      local payload = helpers.simulate_ask_flow(content, "typescript")

      if payload then
        print("\n" .. string.rep("=", 70))
        print("TypeScript useAuth.ts - LLM PAYLOAD")
        print(string.rep("=", 70))
        print(string.format("Mode: %s", payload.mode))
        print(string.format("Question: %s", payload.question or "N/A"))
        print(string.rep("-", 70))
        print("CONTEXT EXTRACTED:")
        print(string.rep("-", 70))
        print(payload.formatted_context or "No context")
        print(string.rep("-", 70))
        print("SYSTEM PROMPT:")
        print(string.rep("-", 70))
        print(payload.system_prompt)
        print(string.rep("-", 70))
        print("USER PROMPT:")
        print(string.rep("-", 70))
        print(payload.user_prompt)
        print(string.rep("=", 70) .. "\n")

        assert.is_not_nil(payload.system_prompt)
        assert.is_not_nil(payload.user_prompt)
      end
    end)

    it("should format response correctly for TypeScript", function()
      local code = [[import { authService } from '../services/authService';

// Q: How does the login function handle errors?
export function useAuth() {
  const login = async (email: string, password: string) => {
    const result = await authService.login(email, password);
    return result;
  };
  return { login };
}]]

      local mock_response = [[The login function doesn't explicitly handle errors - it lets them propagate.

When authService.login() throws:
1. The error bubbles up to the caller
2. The caller is responsible for try/catch

Better approach:
try {
  const result = await authService.login(email, password);
  return { success: true, data: result };
} catch (error) {
  return { success: false, error: error.message };
}

Consider: Add error state to the hook for UI feedback.]]

      local final_code = helpers.simulate_response_insertion(code, mock_response, "typescript")

      print("\n" .. string.rep("=", 70))
      print("TypeScript - FINAL CODE WITH RESPONSE")
      print(string.rep("=", 70))
      print(final_code)
      print(string.rep("=", 70) .. "\n")

      -- Verify structure
      assert.matches("// Q:", final_code)
      assert.matches("/%*", final_code)
      assert.matches("A:", final_code)
      assert.matches("authService", final_code)
      assert.matches("%*/", final_code)
    end)
  end)

  describe("Python Django Project", function()
    local project_path = fixtures_path .. "python-django/"

    it("should generate complete LLM payload for user service", function()
      local filepath = project_path .. "myapp/services/user_service.py"
      local content = helpers.read_file(filepath)

      if not content then
        pending("Fixture file not found: " .. filepath)
        return
      end

      local payload = helpers.simulate_ask_flow(content, "python", "#")

      if payload then
        print("\n" .. string.rep("=", 70))
        print("Python user_service.py - LLM PAYLOAD")
        print(string.rep("=", 70))
        print(string.format("Mode: %s", payload.mode))
        print(string.format("Question: %s", payload.question or "N/A"))
        print(string.rep("-", 70))
        print("CONTEXT EXTRACTED:")
        print(string.rep("-", 70))
        print(payload.formatted_context or "No context")
        print(string.rep("-", 70))
        print("USER PROMPT (truncated):")
        print(string.rep("-", 70))
        print(payload.user_prompt:sub(1, 2000))
        if #payload.user_prompt > 2000 then
          print("... (truncated)")
        end
        print(string.rep("=", 70) .. "\n")

        assert.is_not_nil(payload.system_prompt)
        assert.is_not_nil(payload.user_prompt)
      end
    end)

    it("should format response correctly for Python", function()
      local code = [[from app.models.user import User

# Q: What is the N+1 query problem here?
def get_users_with_posts():
    users = User.objects.all()
    for user in users:
        print(user.posts.all())  # N+1 problem!
    return users]]

      local mock_response = [[The N+1 query problem occurs when you:
1. Query N users (1 query)
2. For each user, query their posts (N queries)
Total: N+1 queries!

Solution - use prefetch_related:
users = User.objects.prefetch_related('posts').all()

This fetches all posts in 2 queries total instead of N+1.

Alternative with select_related for ForeignKey:
users = User.objects.select_related('profile').all()]]

      local final_code = helpers.simulate_response_insertion(code, mock_response, "python", "#")

      print("\n" .. string.rep("=", 70))
      print("Python - FINAL CODE WITH RESPONSE")
      print(string.rep("=", 70))
      print(final_code)
      print(string.rep("=", 70) .. "\n")

      -- Verify Python uses docstring-style block comment
      assert.matches("# Q:", final_code)
      assert.matches('"""', final_code)
      assert.matches("A:", final_code)
      assert.matches("prefetch_related", final_code)
    end)
  end)

  describe("Go Gin Project", function()
    local project_path = fixtures_path .. "go-gin/"

    it("should generate complete LLM payload for handler", function()
      local filepath = project_path .. "internal/handlers/user_handler.go"
      local content = helpers.read_file(filepath)

      if not content then
        -- Create mock if file doesn't exist
        content = [[package handlers

import (
    "net/http"
    "myapp/internal/services"
    "github.com/gin-gonic/gin"
)

// Q: Why use a struct for the handler instead of package-level functions?
type UserHandler struct {
    userService *services.UserService
}

func NewUserHandler(us *services.UserService) *UserHandler {
    return &UserHandler{userService: us}
}

func (h *UserHandler) GetUser(c *gin.Context) {
    id := c.Param("id")
    user, err := h.userService.FindByID(id)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
        return
    }
    c.JSON(http.StatusOK, user)
}]]
      end

      local payload = helpers.simulate_ask_flow(content, "go")

      if payload then
        print("\n" .. string.rep("=", 70))
        print("Go user_handler.go - LLM PAYLOAD")
        print(string.rep("=", 70))
        print(string.format("Mode: %s", payload.mode))
        print(string.format("Question: %s", payload.question or "N/A"))
        print(string.rep("-", 70))
        print("USER PROMPT:")
        print(string.rep("-", 70))
        print(payload.user_prompt)
        print(string.rep("=", 70) .. "\n")

        assert.is_not_nil(payload.system_prompt)
        assert.is_not_nil(payload.user_prompt)
        assert.matches("go", payload.user_prompt:lower())
      end
    end)

    it("should format response correctly for Go", function()
      local code = [[package main

// Q: What is a goroutine?
func main() {
    go func() {
        println("Hello from goroutine")
    }()
}]]

      local mock_response = [[A goroutine is a lightweight thread managed by the Go runtime.

Key characteristics:
- Starts with ~2KB stack (grows as needed)
- Managed by Go scheduler, not OS
- Cheaper than OS threads (can run millions)

The "go" keyword spawns a new goroutine:
go myFunction()  // Runs concurrently

Common pattern with channels:
ch := make(chan int)
go func() { ch <- 42 }()
result := <-ch  // Wait for result

Warning: main() doesn't wait for goroutines by default!]]

      local final_code = helpers.simulate_response_insertion(code, mock_response, "go")

      print("\n" .. string.rep("=", 70))
      print("Go - FINAL CODE WITH RESPONSE")
      print(string.rep("=", 70))
      print(final_code)
      print(string.rep("=", 70) .. "\n")

      -- Verify Go uses C-style block comment
      assert.matches("// Q:", final_code)
      assert.matches("/%*", final_code)
      assert.matches("A:", final_code)
      assert.matches("%*/", final_code)
    end)
  end)

  describe("Different Modes", function()
    it("should generate different payloads for each mode", function()
      local modes = {
        { prefix = "Q", mode = "question", desc = "Direct answer" },
        { prefix = "S", mode = "socratic", desc = "Guiding questions" },
        { prefix = "R", mode = "review", desc = "Code review" },
        { prefix = "D", mode = "debug", desc = "Debug guidance" },
        { prefix = "E", mode = "explain", desc = "Explanation" },
      }

      print("\n" .. string.rep("=", 70))
      print("MODE COMPARISON - System Prompts")
      print(string.rep("=", 70))

      local prompts_mod = require("editutor.prompts")
      local payloads = {}

      for _, m in ipairs(modes) do
        local code = string.format([[// %s: What is this code doing?
function example() {
  return 42;
}]], m.prefix)

        local payload = helpers.simulate_ask_flow(code, "javascript")
        payloads[m.mode] = payload

        print(string.format("\n--- %s MODE (%s) ---", m.mode:upper(), m.desc))
        print(prompts_mod.get_system_prompt(m.mode):sub(1, 500))
        if #prompts_mod.get_system_prompt(m.mode) > 500 then
          print("...")
        end
      end

      print(string.rep("=", 70) .. "\n")

      -- Verify each mode produces different prompt
      for i, m1 in ipairs(modes) do
        for j, m2 in ipairs(modes) do
          if i < j then
            local p1 = prompts_mod.get_system_prompt(m1.mode)
            local p2 = prompts_mod.get_system_prompt(m2.mode)
            assert.are_not.equal(p1, p2, string.format("%s and %s should have different prompts", m1.mode, m2.mode))
          end
        end
      end
    end)
  end)

  describe("Response Insertion Across Languages", function()
    local test_cases = {
      {
        name = "JavaScript",
        filetype = "javascript",
        prefix = "//",
        code = "// Q: What is hoisting?\nvar x = 1;",
        response = "Hoisting moves declarations to top of scope.",
        expect_block = "/*",
      },
      {
        name = "Python",
        filetype = "python",
        prefix = "#",
        code = "# Q: What is a list comprehension?\nx = [i for i in range(10)]",
        response = "List comprehension creates lists concisely.",
        expect_block = '"""',
      },
      {
        name = "Lua",
        filetype = "lua",
        prefix = "--",
        code = "-- Q: What is a metatable?\nlocal t = {}",
        response = "Metatables define table behavior.",
        expect_block = "--[[",
      },
      {
        name = "Go",
        filetype = "go",
        prefix = "//",
        code = "// Q: What is a channel?\nch := make(chan int)",
        response = "Channels enable goroutine communication.",
        expect_block = "/*",
      },
      {
        name = "Shell",
        filetype = "sh",
        prefix = "#",
        code = "# Q: What does $@ mean?\necho $@",
        response = "\\$@ expands to all script arguments.",
        expect_line = "# A:", -- Shell has no block comment
      },
      {
        name = "HTML",
        filetype = "html",
        prefix = nil, -- No line comment
        code = "<!-- Q: What is semantic HTML? -->\n<main></main>",
        response = "Semantic HTML uses meaningful tags.",
        expect_block = "<!--",
      },
    }

    for _, tc in ipairs(test_cases) do
      it(string.format("should insert response correctly in %s", tc.name), function()
        local final_code

        if tc.prefix then
          final_code = helpers.simulate_response_insertion(tc.code, tc.response, tc.filetype, tc.prefix)
        else
          -- HTML special case - use the helpers directly
          local comment_writer = require("editutor.comment_writer")
          local bufnr = helpers.create_mock_buffer(tc.code, tc.filetype)
          comment_writer.insert_or_replace(tc.response, 1, bufnr)
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          final_code = table.concat(lines, "\n")
          helpers.cleanup_buffer(bufnr)
        end

        print(string.format("\n--- %s ---", tc.name))
        print(final_code)

        -- Verify expected comment style
        if tc.expect_block then
          assert.matches(tc.expect_block:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1"), final_code)
        end
        if tc.expect_line then
          assert.matches(tc.expect_line:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1"), final_code)
        end

        -- Verify response content is present
        assert.matches("A:", final_code)
      end)
    end
  end)

  describe("Hint Levels Flow", function()
    it("should replace hints at each level", function()
      local code = [[// Q: Why does this leak memory?
function createClosures() {
  var funcs = [];
  for (var i = 0; i < 10; i++) {
    funcs.push(function() { return i; });
  }
  return funcs;
}]]

      local comment_writer = require("editutor.comment_writer")
      local bufnr = helpers.create_mock_buffer(code, "javascript")
      local _, q_line = helpers.find_q_comment(code)

      local hints = {
        "[Hint 1/4]\nThink about variable scope in JavaScript loops...",
        "[Hint 2/4]\nThe 'var' keyword doesn't create block scope. What does 'i' reference when the functions are called?",
        "[Hint 3/4]\nAll closures share the same 'i' variable. By the time they're called, the loop has finished and i=10.",
        "[Hint 4/4]\nFull solution:\nfor (let i = 0; i < 10; i++) { ... }\n\nOr use IIFE:\nfuncs.push((function(j) { return function() { return j; }; })(i));",
      }

      print("\n" .. string.rep("=", 70))
      print("HINT PROGRESSION")
      print(string.rep("=", 70))

      for level, hint in ipairs(hints) do
        comment_writer.insert_or_replace(hint, q_line, bufnr)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local content = table.concat(lines, "\n")

        print(string.format("\n--- After Hint Level %d ---", level))
        print(content:sub(1, 500))

        -- Verify only current hint is present
        assert.matches(string.format("Hint %d/4", level), content)
        if level > 1 then
          assert.is_nil(content:match(string.format("Hint %d/4", level - 1)))
        end
      end

      print(string.rep("=", 70) .. "\n")

      helpers.cleanup_buffer(bufnr)
    end)
  end)
end)
