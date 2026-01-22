-- editutor/parser.lua
-- Question block parsing for ai-editutor v3.0
-- Detects [Q:id] blocks and [PENDING:id] markers

local M = {}

-- =============================================================================
-- Comment Styles
-- =============================================================================

M.COMMENT_STYLES = {
  -- C-style: // and /* */
  c = { line = "//", block = { "/*", "*/" } },
  cpp = { line = "//", block = { "/*", "*/" } },
  java = { line = "//", block = { "/*", "*/" } },
  javascript = { line = "//", block = { "/*", "*/" } },
  javascriptreact = { line = "//", block = { "/*", "*/" } },
  typescript = { line = "//", block = { "/*", "*/" } },
  typescriptreact = { line = "//", block = { "/*", "*/" } },
  go = { line = "//", block = { "/*", "*/" } },
  rust = { line = "//", block = { "/*", "*/" } },
  swift = { line = "//", block = { "/*", "*/" } },
  kotlin = { line = "//", block = { "/*", "*/" } },
  scala = { line = "//", block = { "/*", "*/" } },
  dart = { line = "//", block = { "/*", "*/" } },
  php = { line = "//", block = { "/*", "*/" } },
  css = { line = nil, block = { "/*", "*/" } },
  scss = { line = "//", block = { "/*", "*/" } },

  -- Hash-style: #
  python = { line = "#", block = { '"""', '"""' } },
  ruby = { line = "#", block = { "=begin", "=end" } },
  sh = { line = "#", block = nil },
  bash = { line = "#", block = nil },
  zsh = { line = "#", block = nil },
  yaml = { line = "#", block = nil },
  toml = { line = "#", block = nil },
  dockerfile = { line = "#", block = nil },

  -- Dash-style: --
  lua = { line = "--", block = { "--[[", "]]" } },
  sql = { line = "--", block = { "/*", "*/" } },
  haskell = { line = "--", block = { "{-", "-}" } },

  -- HTML/XML: <!-- -->
  html = { line = nil, block = { "<!--", "-->" } },
  xml = { line = nil, block = { "<!--", "-->" } },
  vue = { line = "//", block = { "<!--", "-->" } },
  svelte = { line = "//", block = { "<!--", "-->" } },

  -- Lisp-style: ;
  lisp = { line = ";", block = { "#|", "|#" } },
  clojure = { line = ";", block = nil },

  -- Other
  vim = { line = '"', block = nil },
  tex = { line = "%", block = nil },
  latex = { line = "%", block = nil },
}

M.DEFAULT_STYLE = { line = "//", block = { "/*", "*/" } }

-- =============================================================================
-- Helper Functions
-- =============================================================================

---Get comment style for filetype
---@param bufnr? number
---@return table style
function M.get_comment_style(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  return M.COMMENT_STYLES[ft] or M.DEFAULT_STYLE
end

---Generate unique ID based on timestamp (milliseconds)
---@return string id Format: "q_<timestamp_ms>"
function M.generate_id()
  -- Get current time in milliseconds
  local time_ms = vim.loop.hrtime() / 1000000
  return string.format("q_%d", math.floor(time_ms))
end

---Escape pattern special characters
---@param str string
---@return string
local function escape_pattern(str)
  return str:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

-- =============================================================================
-- Question Block Detection
-- =============================================================================

---@class PendingQuestion
---@field id string Question ID (e.g., "q_1737200000000")
---@field question string The question text
---@field block_start number Start line of the block (1-indexed)
---@field block_end number End line of the block (1-indexed)
---@field pending_line number Line number of [PENDING:id] marker
---@field indent string Indentation of the block

---Find all pending questions in current buffer
---Simple approach: find [PENDING:id], then find matching [Q:id]
---Supports both block comments (/* */) and line comments (# // --)
---@param bufnr? number Buffer number
---@return PendingQuestion[] questions List of pending questions
function M.find_pending_questions(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local style = M.get_comment_style(bufnr)

  -- For languages without block comments (Python, Shell, etc.), use line comment parser
  if not style.block and style.line then
    return M._find_pending_line_comments(lines, style)
  end

  local questions = {}

  -- First pass: find all [PENDING:id] markers
  local pending_markers = {} -- id -> line_number
  for i, line in ipairs(lines) do
    local id = line:match("%[PENDING:(q_%d+)%]")
    if id then
      pending_markers[id] = i
    end
  end

  -- If no pending markers, return empty
  if vim.tbl_isempty(pending_markers) then
    return questions
  end

  -- Second pass: find [Q:id] and match with pending
  for i, line in ipairs(lines) do
    local id = line:match("%[Q:(q_%d+)%]")
    if id and pending_markers[id] then
      local pending_line = pending_markers[id]
      local block_start = i
      local block_end = pending_line
      local indent = line:match("^(%s*)") or ""

      -- Look backwards for block comment start (/* or similar)
      if style.block then
        for j = i, math.max(1, i - 10), -1 do
          if lines[j]:match(escape_pattern(style.block[1])) then
            block_start = j
            indent = lines[j]:match("^(%s*)") or ""
            break
          end
        end

        -- Look forwards for block comment end (*/ or similar)
        for j = pending_line, math.min(#lines, pending_line + 10) do
          if lines[j]:match(escape_pattern(style.block[2])) then
            block_end = j
            break
          end
        end
      end

      -- Extract question text (between [Q:id] line and [PENDING:id] line)
      local question_lines = {}
      for j = i + 1, pending_line - 1 do
        local content = lines[j]:gsub("^%s*", ""):gsub("%s*$", "")
        if content ~= "" then
          table.insert(question_lines, content)
        end
      end

      table.insert(questions, {
        id = id,
        question = table.concat(question_lines, "\n"),
        block_start = block_start,
        block_end = block_end,
        pending_line = pending_line,
        indent = indent,
      })
    end
  end

  return questions
end

---Find pending questions in line-comment style (for languages without block comments)
---@param lines string[]
---@param style table
---@return PendingQuestion[]
function M._find_pending_line_comments(lines, style)
  local questions = {}
  local prefix_pattern = escape_pattern(style.line)

  local i = 1
  while i <= #lines do
    local line = lines[i]

    -- Check for line comment with [Q:id]
    local id = line:match("%[Q:(q_%d+)%]")
    if id and line:match("^%s*" .. prefix_pattern) then
      local indent = line:match("^(%s*)") or ""
      local block_start = i
      local block_end = i
      local pending_line = nil
      local question_lines = {}

      -- Search consecutive comment lines for content and [PENDING:id]
      for j = i + 1, #lines do
        local check_line = lines[j]

        -- Check if still a comment line
        if not check_line:match("^%s*" .. prefix_pattern) then
          block_end = j - 1
          break
        end

        block_end = j

        -- Check for [PENDING:id]
        if check_line:match("%[PENDING:" .. escape_pattern(id) .. "%]") then
          pending_line = j
        elseif not pending_line then
          -- Collect question text
          local content = check_line:gsub("^%s*" .. prefix_pattern .. "%s*", "")
          if content ~= "" then
            table.insert(question_lines, content)
          end
        end
      end

      if pending_line then
        table.insert(questions, {
          id = id,
          question = table.concat(question_lines, "\n"),
          block_start = block_start,
          block_end = block_end,
          pending_line = pending_line,
          indent = indent,
        })
      end

      i = block_end + 1
    else
      i = i + 1
    end
  end

  return questions
end

---Find a specific question block by ID
---@param id string Question ID
---@param bufnr? number Buffer number
---@return PendingQuestion|nil
function M.find_question_by_id(id, bufnr)
  local questions = M.find_pending_questions(bufnr)
  for _, q in ipairs(questions) do
    if q.id == id then
      return q
    end
  end
  return nil
end

---Check if buffer has any pending questions
---@param bufnr? number Buffer number
---@return boolean
function M.has_pending_questions(bufnr)
  local questions = M.find_pending_questions(bufnr)
  return #questions > 0
end

---Get count of pending questions
---@param bufnr? number Buffer number
---@return number
function M.count_pending_questions(bufnr)
  local questions = M.find_pending_questions(bufnr)
  return #questions
end

return M
