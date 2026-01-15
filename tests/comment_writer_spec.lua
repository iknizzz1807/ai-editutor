-- tests/comment_writer_spec.lua
-- Tests for comment_writer module
--
-- Verifies:
-- 1. Comment style detection per filetype
-- 2. Response formatting as block/line comments
-- 3. Response insertion into buffer
-- 4. Response replacement on re-ask

local helpers = require("tests.helpers")
local comment_writer = require("editutor.comment_writer")

describe("Comment Writer", function()
  describe("Comment Style Detection", function()
    it("should detect JavaScript/TypeScript style", function()
      local bufnr = helpers.create_mock_buffer("const x = 1;", "javascript")
      local style = comment_writer.get_style(bufnr)

      assert.equals("//", style.line)
      assert.is_not_nil(style.block)
      assert.equals("/*", style.block[1])
      assert.equals("*/", style.block[2])

      helpers.cleanup_buffer(bufnr)
    end)

    it("should detect Python style", function()
      local bufnr = helpers.create_mock_buffer("x = 1", "python")
      local style = comment_writer.get_style(bufnr)

      assert.equals("#", style.line)
      assert.is_not_nil(style.block)
      assert.equals('"""', style.block[1])
      assert.equals('"""', style.block[2])

      helpers.cleanup_buffer(bufnr)
    end)

    it("should detect Lua style", function()
      local bufnr = helpers.create_mock_buffer("local x = 1", "lua")
      local style = comment_writer.get_style(bufnr)

      assert.equals("--", style.line)
      assert.is_not_nil(style.block)
      assert.equals("--[[", style.block[1])
      assert.equals("]]", style.block[2])

      helpers.cleanup_buffer(bufnr)
    end)

    it("should detect Go style", function()
      local bufnr = helpers.create_mock_buffer("package main", "go")
      local style = comment_writer.get_style(bufnr)

      assert.equals("//", style.line)
      assert.is_not_nil(style.block)
      assert.equals("/*", style.block[1])
      assert.equals("*/", style.block[2])

      helpers.cleanup_buffer(bufnr)
    end)

    it("should detect HTML style", function()
      local bufnr = helpers.create_mock_buffer("<div></div>", "html")
      local style = comment_writer.get_style(bufnr)

      assert.is_nil(style.line) -- HTML has no line comment
      assert.is_not_nil(style.block)
      assert.equals("<!--", style.block[1])
      assert.equals("-->", style.block[2])

      helpers.cleanup_buffer(bufnr)
    end)

    it("should detect Shell style", function()
      local bufnr = helpers.create_mock_buffer("echo hello", "sh")
      local style = comment_writer.get_style(bufnr)

      assert.equals("#", style.line)
      assert.is_nil(style.block) -- Shell has no block comment

      helpers.cleanup_buffer(bufnr)
    end)

    it("should detect CSS style", function()
      local bufnr = helpers.create_mock_buffer(".class { }", "css")
      local style = comment_writer.get_style(bufnr)

      assert.is_nil(style.line) -- CSS has no line comment
      assert.is_not_nil(style.block)
      assert.equals("/*", style.block[1])
      assert.equals("*/", style.block[2])

      helpers.cleanup_buffer(bufnr)
    end)

    it("should use default style for unknown filetype", function()
      local bufnr = helpers.create_mock_buffer("unknown", "")
      local style = comment_writer.get_style(bufnr)

      -- Default is C-style
      assert.equals("//", style.line)
      assert.is_not_nil(style.block)

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("Response Formatting", function()
    it("should format response as block comment for JavaScript", function()
      local response = [[This is the explanation.

Example:
function example() {
  return true;
}

Key points:
- Point 1
- Point 2]]

      local bufnr = helpers.create_mock_buffer("// Q: question\nconst x = 1;", "javascript")
      local formatted = comment_writer.format_response(response, bufnr, 1)

      -- Should use block comment
      assert.equals("/*", formatted[1])
      assert.equals("A:", formatted[2])
      assert.matches("explanation", formatted[3])
      assert.equals("*/", formatted[#formatted])

      print("\n=== JavaScript Block Comment ===")
      print(table.concat(formatted, "\n"))
      print("=== END ===\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should format response as block comment for Python", function()
      local response = [[This explains the concept.

Example:
def example():
    return True]]

      local bufnr = helpers.create_mock_buffer("# Q: question\nx = 1", "python")
      local formatted = comment_writer.format_response(response, bufnr, 1)

      -- Should use docstring-style block comment
      assert.equals('"""', formatted[1])
      assert.equals("A:", formatted[2])
      assert.equals('"""', formatted[#formatted])

      print("\n=== Python Block Comment ===")
      print(table.concat(formatted, "\n"))
      print("=== END ===\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should format response as block comment for Lua", function()
      local response = [[This is a Lua explanation.

Example:
local function example()
  return true
end]]

      local bufnr = helpers.create_mock_buffer("-- Q: question\nlocal x = 1", "lua")
      local formatted = comment_writer.format_response(response, bufnr, 1)

      -- Should use Lua block comment
      assert.equals("--[[", formatted[1])
      assert.equals("A:", formatted[2])
      assert.equals("]]", formatted[#formatted])

      print("\n=== Lua Block Comment ===")
      print(table.concat(formatted, "\n"))
      print("=== END ===\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should format response as line comments for Shell (no block)", function()
      local response = [[This explains the shell command.

Example: ls -la]]

      local bufnr = helpers.create_mock_buffer("# Q: question\necho hello", "sh")
      local formatted = comment_writer.format_response(response, bufnr, 1)

      -- Should use line comments (shell has no block comment)
      assert.matches("^# A:", formatted[1])
      assert.matches("^#", formatted[2])

      print("\n=== Shell Line Comments ===")
      print(table.concat(formatted, "\n"))
      print("=== END ===\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should preserve indentation from question line", function()
      local code = [[
function outer() {
    // Q: What is this?
    const inner = 1;
}]]

      local bufnr = helpers.create_mock_buffer(code, "javascript")
      local formatted = comment_writer.format_response("This is the answer.", bufnr, 3)

      -- Should have indentation matching the question line
      assert.matches("^    /", formatted[1]) -- 4 spaces indent

      print("\n=== Indented Block Comment ===")
      print(table.concat(formatted, "\n"))
      print("=== END ===\n")

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("Response Insertion", function()
    it("should insert response after question line in JavaScript", function()
      local code = [[// Q: What is closure?
function outer() {
  const x = 1;
  return function inner() {
    return x;
  };
}]]

      local bufnr = helpers.create_mock_buffer(code, "javascript")
      local response = "A closure is a function that captures variables from its outer scope."

      comment_writer.insert_response(response, 1, bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- First line should still be the question
      assert.matches("// Q:", lines[1])

      -- Second line should be blank (for readability)
      assert.equals("", lines[2])

      -- Third line should start the block comment
      assert.equals("/*", lines[3])

      -- Should have A: prefix
      local all_content = table.concat(lines, "\n")
      assert.matches("A:", all_content)
      assert.matches("closure", all_content)
      assert.matches("%*/", all_content)

      print("\n=== Buffer After Insertion (JavaScript) ===")
      print(table.concat(lines, "\n"))
      print("=== END ===\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should insert response after question line in Python", function()
      local code = [[# Q: What is a decorator?
def my_decorator(func):
    def wrapper(*args):
        return func(*args)
    return wrapper]]

      local bufnr = helpers.create_mock_buffer(code, "python")
      local response = "A decorator wraps a function to extend its behavior."

      comment_writer.insert_response(response, 1, bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      assert.matches("# Q:", lines[1])
      local all_content = table.concat(lines, "\n")
      assert.matches('"""', all_content)
      assert.matches("A:", all_content)
      assert.matches("decorator", all_content)

      print("\n=== Buffer After Insertion (Python) ===")
      print(table.concat(lines, "\n"))
      print("=== END ===\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should insert response after question line in Lua", function()
      local code = [[-- Q: What is metatables?
local mt = {}
setmetatable({}, mt)]]

      local bufnr = helpers.create_mock_buffer(code, "lua")
      local response = "Metatables define behavior for tables using metamethods."

      comment_writer.insert_response(response, 1, bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      assert.matches("-- Q:", lines[1])
      local all_content = table.concat(lines, "\n")
      assert.matches("%-%-%[%[", all_content) -- --[[
      assert.matches("A:", all_content)
      assert.matches("Metatables", all_content)

      print("\n=== Buffer After Insertion (Lua) ===")
      print(table.concat(lines, "\n"))
      print("=== END ===\n")

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("Response Replacement", function()
    it("should replace existing block comment response", function()
      local code = [[// Q: What is X?

/*
A: Old answer about X.
This was the previous response.
*/
const x = 1;]]

      local bufnr = helpers.create_mock_buffer(code, "javascript")

      -- Insert new response (should replace old)
      comment_writer.insert_or_replace("New and improved answer about X.", 1, bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_content = table.concat(lines, "\n")

      -- Should NOT have old answer
      assert.is_nil(all_content:match("Old answer"))
      assert.is_nil(all_content:match("previous response"))

      -- Should have new answer
      assert.matches("New and improved", all_content)

      print("\n=== Buffer After Replacement ===")
      print(table.concat(lines, "\n"))
      print("=== END ===\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should replace existing line comment response in Shell", function()
      local code = [[# Q: What is X?
# A: Old answer
# More old answer
echo hello]]

      local bufnr = helpers.create_mock_buffer(code, "sh")

      comment_writer.insert_or_replace("New shell answer.", 1, bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_content = table.concat(lines, "\n")

      -- Should NOT have old answer
      assert.is_nil(all_content:match("Old answer"))
      assert.is_nil(all_content:match("More old"))

      -- Should have new answer
      assert.matches("New shell answer", all_content)

      print("\n=== Shell Buffer After Replacement ===")
      print(table.concat(lines, "\n"))
      print("=== END ===\n")

      helpers.cleanup_buffer(bufnr)
    end)
  end)

  describe("Full Flow Simulation", function()
    it("should simulate complete Q&A flow in JavaScript", function()
      local initial_code = [[import { useState } from 'react';

// Q: How does useState work internally?
function Counter() {
  const [count, setCount] = useState(0);
  return <button onClick={() => setCount(count + 1)}>{count}</button>;
}

export default Counter;]]

      local mock_llm_response = [[useState is a React Hook that lets you add state to functional components.

Internally, React maintains a state array for each component instance. When useState is called:
1. React checks if this is the first render
2. If first render, it initializes the state with the provided value
3. If re-render, it returns the existing state from the array

Example of how it might work internally:
let stateIndex = 0;
const states = [];

function useState(initialValue) {
  const currentIndex = stateIndex;
  states[currentIndex] = states[currentIndex] ?? initialValue;

  const setState = (newValue) => {
    states[currentIndex] = newValue;
    rerender();
  };

  stateIndex++;
  return [states[currentIndex], setState];
}

Key point: Hooks must be called in the same order every render.]]

      local bufnr = helpers.create_mock_buffer(initial_code, "typescriptreact")

      -- Simulate the flow: find question, insert response
      local _, q_line = helpers.find_q_comment(initial_code)
      comment_writer.insert_or_replace(mock_llm_response, q_line, bufnr)

      local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local final_code = table.concat(final_lines, "\n")

      -- Verify structure
      assert.matches("// Q: How does useState", final_code)
      assert.matches("/%*", final_code) -- Block comment start
      assert.matches("A:", final_code)
      assert.matches("React Hook", final_code)
      assert.matches("stateIndex", final_code)
      assert.matches("%*/", final_code) -- Block comment end
      assert.matches("function Counter", final_code) -- Original code still there

      print("\n" .. string.rep("=", 60))
      print("FULL Q&A FLOW SIMULATION (TypeScript React)")
      print(string.rep("=", 60))
      print(final_code)
      print(string.rep("=", 60) .. "\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should simulate complete Q&A flow in Python", function()
      local initial_code = [=[from typing import List, Optional

# Q: What is the difference between List and list in type hints?
def process_items(items: List[str]) -> Optional[str]:
    if not items:
        return None
    return items[0]]=]

      local mock_llm_response = [=[List vs list in Python type hints:

1. `List` (from typing): Required in Python < 3.9 for generic types
2. `list` (built-in): Can be used directly in Python >= 3.9

Example:
# Python 3.8 and earlier
from typing import List
def old_style(items: List[str]) -> List[int]: ...

# Python 3.9+
def new_style(items: list[str]) -> list[int]: ...

Best practice: Use lowercase `list` if targeting Python 3.9+]=]

      local bufnr = helpers.create_mock_buffer(initial_code, "python")

      local _, q_line = helpers.find_q_comment(initial_code, "#")
      comment_writer.insert_or_replace(mock_llm_response, q_line, bufnr)

      local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local final_code = table.concat(final_lines, "\n")

      assert.matches("# Q: What is the difference", final_code)
      assert.matches('"""', final_code) -- Python block comment
      assert.matches("A:", final_code)
      assert.matches("Python 3.9", final_code)
      assert.matches("def process_items", final_code)

      print("\n" .. string.rep("=", 60))
      print("FULL Q&A FLOW SIMULATION (Python)")
      print(string.rep("=", 60))
      print(final_code)
      print(string.rep("=", 60) .. "\n")

      helpers.cleanup_buffer(bufnr)
    end)

    it("should simulate hint levels in Go", function()
      local initial_code = [[package main

// Q: Why does this goroutine leak?
func leaky() {
    ch := make(chan int)
    go func() {
        ch <- 42
    }()
    // Never reads from ch
}]]

      local bufnr = helpers.create_mock_buffer(initial_code, "go")
      local _, q_line = helpers.find_q_comment(initial_code)

      -- Simulate hint level 1
      local hint1 = "[Hint 1/4]\nThink about what happens when a goroutine tries to send to an unbuffered channel..."
      comment_writer.insert_or_replace(hint1, q_line, bufnr)

      local lines1 = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      print("\n=== Hint Level 1 ===")
      print(table.concat(lines1, "\n"))

      -- Simulate hint level 2 (replaces level 1)
      local hint2 = "[Hint 2/4]\nUnbuffered channels block until both sender and receiver are ready. What happens if no one ever receives?"
      comment_writer.insert_or_replace(hint2, q_line, bufnr)

      local lines2 = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      print("\n=== Hint Level 2 (replaced 1) ===")
      print(table.concat(lines2, "\n"))

      -- Verify level 1 is gone
      local content = table.concat(lines2, "\n")
      assert.is_nil(content:match("Hint 1/4"))
      assert.matches("Hint 2/4", content)

      helpers.cleanup_buffer(bufnr)
    end)
  end)
end)
