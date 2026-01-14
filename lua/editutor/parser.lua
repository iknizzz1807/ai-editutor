-- editutor/parser.lua
-- Comment parsing for tutor triggers

local M = {}

---@class MentorQuery
---@field mode string The mode (Q|S|R|D|E)
---@field mode_name string Full mode name
---@field question string The question/request text
---@field line number Line number of the comment
---@field col number Column position

-- Mode definitions
M.modes = {
  Q = { name = "question", description = "Direct question - get educational answer" },
  S = { name = "socratic", description = "Socratic mode - guided discovery through questions" },
  R = { name = "review", description = "Code review - get feedback on code quality" },
  D = { name = "debug", description = "Debug mode - guided debugging assistance" },
  E = { name = "explain", description = "Explain mode - deep concept explanation" },
}

-- Pattern to match mentor comments: // Q: question text
-- Supports various comment styles: //, #, --, /* */
local PATTERNS = {
  -- Single line comments
  "^%s*//[%s]*([QSRDE]):[%s]*(.+)$",      -- // Q: question
  "^%s*#[%s]*([QSRDE]):[%s]*(.+)$",        -- # Q: question
  "^%s*%-%-[%s]*([QSRDE]):[%s]*(.+)$",     -- -- Q: question
  "^%s*;[%s]*([QSRDE]):[%s]*(.+)$",        -- ; Q: question (lisp, asm)
  -- Block comment start (just the opening line)
  "^%s*/%*[%s]*([QSRDE]):[%s]*(.+)",       -- /* Q: question
  "^%s*%-%-%[[%s]*([QSRDE]):[%s]*(.+)",    -- --[[ Q: question (lua)
}

---Parse a single line for mentor trigger
---@param line string The line content
---@return string|nil mode The mode character (Q, S, R, D, E)
---@return string|nil question The question text
function M.parse_line(line)
  for _, pattern in ipairs(PATTERNS) do
    local mode, question = line:match(pattern)
    if mode and question then
      -- Clean up question (remove trailing comment closers)
      question = question:gsub("%s*%*/[%s]*$", "")
      question = question:gsub("%s*%]%][%s]*$", "")
      question = question:gsub("%s*$", "")
      return mode, question
    end
  end
  return nil, nil
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
      local mode, question = M.parse_line(line)
      if mode and question then
        local mode_info = M.modes[mode]
        return {
          mode = mode,
          mode_name = mode_info and mode_info.name or "question",
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
    local mode, question = M.parse_line(line)
    if mode and question then
      local mode_info = M.modes[mode]
      table.insert(queries, {
        mode = mode,
        mode_name = mode_info and mode_info.name or "question",
        question = question,
        line = line_num,
        col = 1,
      })
    end
  end

  return queries
end

---Get mode description
---@param mode string Mode character
---@return string description
function M.get_mode_description(mode)
  local info = M.modes[mode]
  if info then
    return info.description
  end
  return "Unknown mode"
end

---Get all available modes as formatted string
---@return string
function M.get_modes_help()
  local help = {}
  for mode, info in pairs(M.modes) do
    table.insert(help, string.format("// %s: %s", mode, info.description))
  end
  table.sort(help)
  return table.concat(help, "\n")
end

return M
