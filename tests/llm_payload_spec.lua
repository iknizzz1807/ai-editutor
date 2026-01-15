-- tests/llm_payload_spec.lua
-- Tests that verify what gets sent to the LLM
--
-- These tests show:
-- 1. System prompt generation
-- 2. User prompt with context
-- 3. Full payload structure

local helpers = require("tests.helpers")

describe("LLM Payload Generation", function()
  local parser = require("editutor.parser")
  local context = require("editutor.context")
  local prompts = require("editutor.prompts")

  before_each(function()
    -- Reset to default config
    require("editutor.config").setup({
      language = "English",
      default_mode = "question",
    })
  end)

  describe("System Prompt", function()
    it("should generate concise system prompt for inline comments", function()
      local system_prompt = prompts.get_system_prompt("question")

      -- Verify key elements
      assert.matches("TEACH", system_prompt)
      assert.matches("inline comment", system_prompt:lower())
      assert.matches("concise", system_prompt:lower())

      -- Should instruct AI not to use emoji headers
      assert.matches("DO NOT", system_prompt)
      assert.matches("emoji", system_prompt:lower())

      print("\n=== SYSTEM PROMPT (question mode) ===")
      print(system_prompt)
      print("=== END SYSTEM PROMPT ===\n")
    end)

    it("should have different prompts for each mode", function()
      local modes = { "question", "socratic", "review", "debug", "explain" }
      local prompts_map = {}

      for _, mode in ipairs(modes) do
        prompts_map[mode] = prompts.get_system_prompt(mode)
      end

      -- Each mode should be unique
      for i, mode1 in ipairs(modes) do
        for j, mode2 in ipairs(modes) do
          if i ~= j then
            assert.are_not.equal(
              prompts_map[mode1],
              prompts_map[mode2],
              string.format("Prompts for %s and %s should be different", mode1, mode2)
            )
          end
        end
      end
    end)

    it("should support Vietnamese language", function()
      require("editutor.config").options.language = "Vietnamese"

      local system_prompt = prompts.get_system_prompt("question")

      assert.matches("tiếng Việt", system_prompt)
      assert.matches("GIẢI THÍCH", system_prompt)

      print("\n=== SYSTEM PROMPT (Vietnamese) ===")
      print(system_prompt)
      print("=== END SYSTEM PROMPT ===\n")
    end)
  end)

  describe("User Prompt with Context", function()
    it("should build user prompt from mock TypeScript code", function()
      local mock_code = [[
import { useState, useEffect } from 'react';
import { userService } from '../services/userService';
import { User } from '../types/user';

// Q: How does the useEffect cleanup work here?
export function UserProfile({ userId }: { userId: string }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let isMounted = true;

    userService.getUser(userId).then((data) => {
      if (isMounted) {
        setUser(data);
        setLoading(false);
      }
    });

    return () => {
      isMounted = false;
    };
  }, [userId]);

  if (loading) return <div>Loading...</div>;
  return <div>{user?.name}</div>;
}
]]

      -- Create mock buffer
      local bufnr = helpers.create_mock_buffer(mock_code, "typescriptreact")
      vim.api.nvim_set_current_buf(bufnr)

      -- Find Q: line
      local _, q_line = helpers.find_q_comment(mock_code)

      -- Extract context
      local ctx = context.extract(bufnr, q_line)
      local formatted_context = context.format_for_prompt(ctx)

      -- Build user prompt
      local user_prompt = prompts.build_user_prompt(
        "How does the useEffect cleanup work here?",
        formatted_context,
        "question"
      )

      -- Verify structure
      assert.matches("Mode: QUESTION", user_prompt)
      assert.matches("Context:", user_prompt)
      assert.matches("Question:", user_prompt)
      assert.matches("useEffect", user_prompt)
      assert.matches("userService", user_prompt)

      print("\n=== USER PROMPT (TypeScript) ===")
      print(user_prompt)
      print("=== END USER PROMPT ===\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should build user prompt from mock Python code", function()
      local mock_code = [[
from typing import Optional
from fastapi import HTTPException
from app.models.user import User, UserCreate
from app.services.auth_service import verify_token

# Q: What happens if the token is invalid?
async def get_current_user(token: str) -> User:
    payload = verify_token(token)
    if payload is None:
        raise HTTPException(status_code=401, detail="Invalid token")

    user_id = payload.get("sub")
    user = await User.get(user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    return user
]]

      local bufnr = helpers.create_mock_buffer(mock_code, "python")
      vim.api.nvim_set_current_buf(bufnr)

      local _, q_line = helpers.find_q_comment(mock_code, "#")

      local ctx = context.extract(bufnr, q_line)
      local formatted_context = context.format_for_prompt(ctx)

      local user_prompt = prompts.build_user_prompt(
        "What happens if the token is invalid?",
        formatted_context,
        "question"
      )

      assert.matches("python", user_prompt:lower())
      assert.matches("HTTPException", user_prompt)
      assert.matches("verify_token", user_prompt)

      print("\n=== USER PROMPT (Python) ===")
      print(user_prompt)
      print("=== END USER PROMPT ===\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should build user prompt from mock Go code", function()
      local mock_code = [[
package handlers

import (
    "net/http"
    "myapp/internal/services"
    "myapp/internal/models"
    "github.com/gin-gonic/gin"
)

// Q: Why do we use pointer receiver here?
func (h *UserHandler) GetUser(c *gin.Context) {
    userId := c.Param("id")

    user, err := h.userService.FindByID(userId)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
        return
    }

    c.JSON(http.StatusOK, user)
}
]]

      local bufnr = helpers.create_mock_buffer(mock_code, "go")
      vim.api.nvim_set_current_buf(bufnr)

      local _, q_line = helpers.find_q_comment(mock_code)

      local ctx = context.extract(bufnr, q_line)
      local formatted_context = context.format_for_prompt(ctx)

      local user_prompt = prompts.build_user_prompt(
        "Why do we use pointer receiver here?",
        formatted_context,
        "question"
      )

      assert.matches("go", user_prompt:lower())
      assert.matches("UserHandler", user_prompt)
      assert.matches("gin", user_prompt)

      print("\n=== USER PROMPT (Go) ===")
      print(user_prompt)
      print("=== END USER PROMPT ===\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should build user prompt from mock Lua code", function()
      local mock_code = [[
local M = {}

local config = require("myplugin.config")
local utils = require("myplugin.utils")

-- Q: How does the floating window positioning work?
function M.create_window(opts)
  opts = opts or {}

  local width = opts.width or config.defaults.width
  local height = opts.height or config.defaults.height

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  }

  local winnr = vim.api.nvim_open_win(bufnr, true, win_opts)
  return bufnr, winnr
end

return M
]]

      local bufnr = helpers.create_mock_buffer(mock_code, "lua")
      vim.api.nvim_set_current_buf(bufnr)

      local _, q_line = helpers.find_q_comment(mock_code, "--")

      local ctx = context.extract(bufnr, q_line)
      local formatted_context = context.format_for_prompt(ctx)

      local user_prompt = prompts.build_user_prompt(
        "How does the floating window positioning work?",
        formatted_context,
        "question"
      )

      assert.matches("lua", user_prompt:lower())
      assert.matches("nvim_create_buf", user_prompt)
      assert.matches("nvim_open_win", user_prompt)

      print("\n=== USER PROMPT (Lua) ===")
      print(user_prompt)
      print("=== END USER PROMPT ===\n")

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("Full Payload Structure", function()
    it("should generate complete LLM payload for Question mode", function()
      local mock_code = [[
// Q: What is the time complexity of this function?
function findDuplicates(arr) {
  const seen = new Set();
  const duplicates = [];

  for (const item of arr) {
    if (seen.has(item)) {
      duplicates.push(item);
    } else {
      seen.add(item);
    }
  }

  return duplicates;
}
]]

      local bufnr = helpers.create_mock_buffer(mock_code, "javascript")
      vim.api.nvim_set_current_buf(bufnr)

      local q_line_content, q_line = helpers.find_q_comment(mock_code)
      local mode, question = parser.parse_line(q_line_content)

      local ctx = context.extract(bufnr, q_line)
      local formatted_context = context.format_for_prompt(ctx)

      local system_prompt = prompts.get_system_prompt(mode:lower())
      local user_prompt = prompts.build_user_prompt(question, formatted_context, mode:lower())

      print("\n" .. string.rep("=", 60))
      print("FULL LLM PAYLOAD - Question Mode")
      print(string.rep("=", 60))
      print("\n--- SYSTEM PROMPT ---")
      print(system_prompt)
      print("\n--- USER PROMPT ---")
      print(user_prompt)
      print(string.rep("=", 60) .. "\n")

      -- Verify payload structure
      assert.is_not_nil(system_prompt)
      assert.is_not_nil(user_prompt)
      assert.is_true(#system_prompt > 50)
      assert.is_true(#user_prompt > 50)
      assert.matches("findDuplicates", user_prompt)
      assert.matches("Set", user_prompt)

      helpers.cleanup_buffer(bufnr)
    end)

    it("should generate complete LLM payload for Review mode", function()
      local mock_code = [[
// R: Review this function for potential issues
async function fetchUserData(userId) {
  const response = await fetch(`/api/users/${userId}`);
  const data = await response.json();
  return data;
}
]]

      local bufnr = helpers.create_mock_buffer(mock_code, "javascript")
      vim.api.nvim_set_current_buf(bufnr)

      local q_line_content, q_line = helpers.find_q_comment(mock_code)
      -- For R: mode
      q_line_content = mock_code:match("// R:[^\n]+")
      local mode, question = parser.parse_line(q_line_content)

      local ctx = context.extract(bufnr, 2) -- Line with R:
      local formatted_context = context.format_for_prompt(ctx)

      local system_prompt = prompts.get_system_prompt("review")
      local user_prompt = prompts.build_user_prompt(question, formatted_context, "review")

      print("\n" .. string.rep("=", 60))
      print("FULL LLM PAYLOAD - Review Mode")
      print(string.rep("=", 60))
      print("\n--- SYSTEM PROMPT ---")
      print(system_prompt)
      print("\n--- USER PROMPT ---")
      print(user_prompt)
      print(string.rep("=", 60) .. "\n")

      -- Review mode should mention issues/warnings
      assert.matches("CRITICAL", system_prompt:upper())
      assert.matches("WARNING", system_prompt:upper())

      helpers.cleanup_buffer(bufnr)
    end)

    it("should generate complete LLM payload for Socratic mode", function()
      local mock_code = [[
# S: Why might this cause a race condition?
import threading

counter = 0

def increment():
    global counter
    for _ in range(100000):
        counter += 1

threads = [threading.Thread(target=increment) for _ in range(2)]
for t in threads:
    t.start()
for t in threads:
    t.join()
print(counter)
]]

      local bufnr = helpers.create_mock_buffer(mock_code, "python")
      vim.api.nvim_set_current_buf(bufnr)

      local q_line_content, q_line = helpers.find_q_comment(mock_code, "#")
      -- For S: mode
      q_line_content = mock_code:match("# S:[^\n]+")
      local mode, question = parser.parse_line(q_line_content)

      local ctx = context.extract(bufnr, 2)
      local formatted_context = context.format_for_prompt(ctx)

      local system_prompt = prompts.get_system_prompt("socratic")
      local user_prompt = prompts.build_user_prompt(question, formatted_context, "socratic")

      print("\n" .. string.rep("=", 60))
      print("FULL LLM PAYLOAD - Socratic Mode")
      print(string.rep("=", 60))
      print("\n--- SYSTEM PROMPT ---")
      print(system_prompt)
      print("\n--- USER PROMPT ---")
      print(user_prompt)
      print(string.rep("=", 60) .. "\n")

      -- Socratic mode should NOT give direct answers
      assert.matches("NOT", system_prompt:upper())
      assert.matches("question", system_prompt:lower())

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("Hints System Payload", function()
    it("should generate hint prompts at each level", function()
      print("\n" .. string.rep("=", 60))
      print("HINT PROMPTS (all levels)")
      print(string.rep("=", 60))

      for level = 1, 4 do
        local hint_prompt = prompts.get_hint_prompt(level)
        print(string.format("\n--- LEVEL %d ---", level))
        print(hint_prompt)

        assert.is_not_nil(hint_prompt)
        assert.is_true(#hint_prompt > 10)
      end

      print(string.rep("=", 60) .. "\n")
    end)
  end)
end)
