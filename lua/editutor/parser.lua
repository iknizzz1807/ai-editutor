-- editutor/parser.lua
-- Comment parsing for mentor triggers
-- Supports Q: (question/explain) and C: (code generation) prefixes

local M = {}

---@class MentorQuery
---@field question string The question/request text
---@field line number Line number of the comment
---@field col number Column position
---@field mode string "question" or "code"

-- Modes
M.MODE_QUESTION = "question"  -- Q: - explain, teach, answer
M.MODE_CODE = "code"          -- C: - generate code with notes

-- Pattern to match mentor comments: // Q: or // C:
-- Supports various comment styles: //, #, --, /* */
local PATTERNS = {
  -- Q: patterns (question/explain mode)
  { pattern = "^%s*//[%s]*[Qq]:[%s]*(.+)$", mode = "question" },
  { pattern = "^%s*#[%s]*[Qq]:[%s]*(.+)$", mode = "question" },
  { pattern = "^%s*%-%-[%s]*[Qq]:[%s]*(.+)$", mode = "question" },
  { pattern = "^%s*;[%s]*[Qq]:[%s]*(.+)$", mode = "question" },
  { pattern = "^%s*/%*[%s]*[Qq]:[%s]*(.+)", mode = "question" },
  { pattern = "^%s*%-%-%[%[[%s]*[Qq]:[%s]*(.+)", mode = "question" },
  { pattern = "^%s*<!%-%-%s*[Qq]:[%s]*(.+)", mode = "question" },

  -- C: patterns (code generation mode)
  { pattern = "^%s*//[%s]*[Cc]:[%s]*(.+)$", mode = "code" },
  { pattern = "^%s*#[%s]*[Cc]:[%s]*(.+)$", mode = "code" },
  { pattern = "^%s*%-%-[%s]*[Cc]:[%s]*(.+)$", mode = "code" },
  { pattern = "^%s*;[%s]*[Cc]:[%s]*(.+)$", mode = "code" },
  { pattern = "^%s*/%*[%s]*[Cc]:[%s]*(.+)", mode = "code" },
  { pattern = "^%s*%-%-%[%[[%s]*[Cc]:[%s]*(.+)", mode = "code" },
  { pattern = "^%s*<!%-%-%s*[Cc]:[%s]*(.+)", mode = "code" },
}

-- Patterns to detect A: response below a question
local ANSWER_PATTERNS = {
  "^%s*/%*",                     -- /* (block comment start)
  "^%s*%-%-%[%[",                -- --[[ (lua block)
  "^%s*<!%-%-",                  -- <!-- (html block)
  "^%s*//[%s]*A:",               -- // A: (line comment)
  "^%s*#[%s]*A:",                -- # A: (python/ruby)
  "^%s*%-%-[%s]*A:",             -- -- A: (lua)
  "^%s*;[%s]*A:",                -- ; A: (lisp)
  "^%s*A:",                      -- A: inside block comment
}

---Parse a single line for mentor trigger
---@param line string The line content
---@return string|nil question The question text (nil if no match)
---@return string|nil mode The mode ("question" or "code")
function M.parse_line(line)
  for _, p in ipairs(PATTERNS) do
    local question = line:match(p.pattern)
    if question then
      -- Clean up question (remove trailing comment closers)
      question = question:gsub("%s*%*/[%s]*$", "")
      question = question:gsub("%s*%]%][%s]*$", "")
      question = question:gsub("%s*%-%->[%s]*$", "")
      question = question:gsub("%s*$", "")

      -- Don't match empty questions
      if question ~= "" then
        return question, p.mode
      end
    end
  end
  return nil, nil
end

---Check if a Q: line has an A: response below it
---@param lines string[] All lines in buffer
---@param question_line number Line number of the question (1-indexed)
---@return boolean has_answer True if there's an A: response below
function M.has_answer_below(lines, question_line)
  local total_lines = #lines

  -- Check the next few lines for A: response
  -- Typically: Q: line, then blank line, then /* or A:
  for offset = 1, 5 do
    local check_idx = question_line + offset
    if check_idx > total_lines then
      break
    end

    local line = lines[check_idx]
    if not line then
      break
    end

    -- Skip empty lines (continue checking next line)
    if not line:match("^%s*$") then
      -- Non-empty line: check if it matches any answer pattern
      for _, pattern in ipairs(ANSWER_PATTERNS) do
        if line:match(pattern) then
          return true
        end
      end

      -- If we hit a non-empty, non-answer line, stop looking
      -- (the answer should be immediately after the question)
      break
    end
  end

  return false
end

---Find mentor query at cursor position or nearby
---Skips Q: lines that already have A: responses below them
---@param bufnr? number Buffer number (default: current)
---@param start_line? number Start line to search from (1-indexed)
---@param include_answered? boolean Include answered questions (default: false)
---@return MentorQuery|nil query The parsed query or nil
function M.find_query(bufnr, start_line, include_answered)
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
      local question, mode = M.parse_line(line)
      if question then
        -- Skip if already answered (unless include_answered is true)
        local should_skip = not include_answered and M.has_answer_below(lines, line_num)

        if not should_skip then
          return {
            question = question,
            line = line_num,
            col = 1,
            mode = mode or M.MODE_QUESTION,
          }
        end
        -- If should_skip, loop continues to next line_num
      end
    end
  end

  return nil
end

---Find all mentor queries in buffer
---@param bufnr? number Buffer number
---@param include_answered? boolean Include answered questions (default: true for find_all)
---@return MentorQuery[] queries List of all queries found
function M.find_all_queries(bufnr, include_answered)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local queries = {}

  -- Default to including answered for find_all (show all questions)
  if include_answered == nil then
    include_answered = true
  end

  for line_num, line in ipairs(lines) do
    local question, mode = M.parse_line(line)
    if question then
      local has_answer = M.has_answer_below(lines, line_num)

      if include_answered or not has_answer then
        table.insert(queries, {
          question = question,
          line = line_num,
          col = 1,
          mode = mode or M.MODE_QUESTION,
          answered = has_answer,
        })
      end
    end
  end

  return queries
end

---Get visual selection range and content
---@return table|nil selection { start_line, end_line, lines, text } or nil if not in visual mode
function M.get_visual_selection()
  -- Get visual selection marks
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = start_pos[2]
  local end_line = end_pos[2]

  -- Check if we have a valid selection
  if start_line == 0 or end_line == 0 or start_line > end_line then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  return {
    start_line = start_line,
    end_line = end_line,
    lines = lines,
    text = table.concat(lines, "\n"),
  }
end

---Find query within a specific line range (for visual selection)
---@param bufnr? number Buffer number
---@param start_line number Start line (1-indexed)
---@param end_line number End line (1-indexed)
---@return MentorQuery|nil query The parsed query or nil
function M.find_query_in_range(bufnr, start_line, end_line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Search within the range
  for line_num = start_line, end_line do
    local line = lines[line_num]
    if line then
      local question, mode = M.parse_line(line)
      if question then
        -- Skip if already answered
        if not M.has_answer_below(lines, line_num) then
          return {
            question = question,
            line = line_num,
            col = 1,
            mode = mode or M.MODE_QUESTION,
          }
        end
      end
    end
  end

  return nil
end

return M
