-- editutor/parser.lua
-- Comment parsing for mentor triggers
-- Simplified: Only Q: prefix (ask any question naturally)

local M = {}

---@class MentorQuery
---@field question string The question/request text
---@field line number Line number of the comment
---@field col number Column position

-- Pattern to match mentor comments: // Q: question text
-- Supports various comment styles: //, #, --, /* */
-- Only Q: (or q:) is supported - users can naturally express intent in the question
local PATTERNS = {
  -- Single line comments (Q or q, case insensitive)
  "^%s*//[%s]*[Qq]:[%s]*(.+)$",       -- // Q: question  or // q: question
  "^%s*#[%s]*[Qq]:[%s]*(.+)$",         -- # Q: question
  "^%s*%-%-[%s]*[Qq]:[%s]*(.+)$",      -- -- Q: question
  "^%s*;[%s]*[Qq]:[%s]*(.+)$",         -- ; Q: question (lisp, asm)
  -- Block comment start
  "^%s*/%*[%s]*[Qq]:[%s]*(.+)",        -- /* Q: question
  "^%s*%-%-%[%[[%s]*[Qq]:[%s]*(.+)",   -- --[[ Q: question (lua)
  "^%s*<!%-%-%s*[Qq]:[%s]*(.+)",       -- <!-- Q: question (html)
}

---Parse a single line for mentor trigger
---@param line string The line content
---@return string|nil question The question text (nil if no match)
function M.parse_line(line)
  for _, pattern in ipairs(PATTERNS) do
    local question = line:match(pattern)
    if question then
      -- Clean up question (remove trailing comment closers)
      question = question:gsub("%s*%*/[%s]*$", "")
      question = question:gsub("%s*%]%][%s]*$", "")
      question = question:gsub("%s*%-%->[%s]*$", "")
      question = question:gsub("%s*$", "")

      -- Don't match empty questions
      if question ~= "" then
        return question
      end
    end
  end
  return nil
end

---Find mentor query at cursor position or nearby
---@param bufnr? number Buffer number (default: current)
---@param start_line? number Start line to search from (1-indexed)
---@return MentorQuery|nil query The parsed query or nil
function M.find_query(bufnr, start_line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  start_line = start_line or vim.api.nvim_win_get_cursor(0)[1]

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local total_lines = #lines

  -- Search from current line, then up, then down
  local search_order = { start_line }
  for i = 1, 10 do
    if start_line - i >= 1 then
      table.insert(search_order, start_line - i)
    end
    if start_line + i <= total_lines then
      table.insert(search_order, start_line + i)
    end
  end

  for _, line_num in ipairs(search_order) do
    local line = lines[line_num]
    if line then
      local question = M.parse_line(line)
      if question then
        return {
          question = question,
          line = line_num,
          col = 1,
        }
      end
    end
  end

  return nil
end

---Find all mentor queries in buffer
---@param bufnr? number Buffer number
---@return MentorQuery[] queries List of all queries found
function M.find_all_queries(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local queries = {}

  for line_num, line in ipairs(lines) do
    local question = M.parse_line(line)
    if question then
      table.insert(queries, {
        question = question,
        line = line_num,
        col = 1,
      })
    end
  end

  return queries
end

return M
