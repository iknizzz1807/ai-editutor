-- editutor/comment_writer.lua
-- Spawn question blocks and write AI responses
-- v3.0: New [Q:id] / [PENDING:id] format

local M = {}

local parser = require("editutor.parser")

-- =============================================================================
-- Comment Styles (reuse from parser)
-- =============================================================================

M.comment_styles = parser.COMMENT_STYLES
M.default_style = parser.DEFAULT_STYLE

---Get comment style for current buffer
---@param bufnr? number Buffer number
---@return table style Comment style { line, block }
function M.get_style(bufnr)
  return parser.get_comment_style(bufnr)
end

-- =============================================================================
-- Question Block Spawning
-- =============================================================================

---Spawn a new question block at cursor position
---@param bufnr? number Buffer number
---@param selected_code? string Optional code from visual selection
---@return string id The generated question ID
---@return number cursor_line Line number where cursor should be placed
function M.spawn_question_block(bufnr, selected_code)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]
  local style = M.get_style(bufnr)

  -- Generate unique ID
  local id = parser.generate_id()

  -- Get indentation from current line
  local current_line = vim.api.nvim_buf_get_lines(bufnr, cursor_line - 1, cursor_line, false)[1] or ""
  local indent = current_line:match("^(%s*)") or ""

  local block_lines = {}

  if style.block then
    -- Block comment format
    table.insert(block_lines, "")
    table.insert(block_lines, indent .. style.block[1] .. " [Q:" .. id .. "]")

    -- Add selected code if provided
    if selected_code and selected_code ~= "" then
      table.insert(block_lines, indent .. "Regarding this code:")
      table.insert(block_lines, indent .. "```")
      for line in selected_code:gmatch("[^\n]+") do
        table.insert(block_lines, indent .. line)
      end
      table.insert(block_lines, indent .. "```")
      table.insert(block_lines, indent .. "")
    end

    -- Placeholder for user's question
    table.insert(block_lines, indent .. "")
    local question_line = cursor_line + #block_lines -- Line where user types

    -- PENDING marker and close
    table.insert(block_lines, indent .. "[PENDING:" .. id .. "]")
    table.insert(block_lines, indent .. style.block[2])
  else
    -- Line comment format (for languages without block comments)
    local prefix = style.line .. " "
    table.insert(block_lines, "")
    table.insert(block_lines, indent .. prefix .. "[Q:" .. id .. "]")

    -- Add selected code if provided
    if selected_code and selected_code ~= "" then
      table.insert(block_lines, indent .. prefix .. "Regarding this code:")
      for line in selected_code:gmatch("[^\n]+") do
        table.insert(block_lines, indent .. prefix .. "  " .. line)
      end
      table.insert(block_lines, indent .. prefix .. "")
    end

    -- Placeholder for user's question
    table.insert(block_lines, indent .. prefix .. "")
    local question_line = cursor_line + #block_lines

    -- PENDING marker
    table.insert(block_lines, indent .. prefix .. "[PENDING:" .. id .. "]")
  end

  -- Insert block into buffer
  vim.api.nvim_buf_set_lines(bufnr, cursor_line, cursor_line, false, block_lines)

  -- Calculate line where user should type their question
  -- It's the empty line before [PENDING:id]
  local question_input_line
  if style.block then
    question_input_line = cursor_line + #block_lines - 2 -- Line before [PENDING:id]
  else
    question_input_line = cursor_line + #block_lines - 1
  end

  return id, question_input_line
end

-- =============================================================================
-- Response Writing
-- =============================================================================

---Replace [PENDING:id] marker with AI response
---@param id string Question ID
---@param response string AI response text
---@param bufnr? number Buffer number
---@return boolean success
function M.replace_pending_with_response(id, response, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Find the question block
  local question = parser.find_question_by_id(id, bufnr)
  if not question then
    return false
  end

  local style = M.get_style(bufnr)
  local indent = question.indent

  -- Format the response
  local response_lines = M._format_response(response, indent)

  -- Get current buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Build new block content
  local new_block = {}

  -- Copy lines from block_start to pending_line - 1 (the question part)
  for i = question.block_start, question.pending_line - 1 do
    table.insert(new_block, lines[i])
  end

  -- Add blank line before response
  table.insert(new_block, indent .. "")

  -- Add formatted response
  for _, line in ipairs(response_lines) do
    table.insert(new_block, line)
  end

  -- Add closing (for block comments)
  if style.block then
    table.insert(new_block, indent .. style.block[2])
  end

  -- Replace the block in buffer
  vim.api.nvim_buf_set_lines(bufnr, question.block_start - 1, question.block_end, false, new_block)

  return true
end

---Format response text for insertion
---@param response string Raw response from LLM
---@param indent string Indentation to use
---@return string[] lines Formatted lines
function M._format_response(response, indent)
  local lines = {}
  local max_width = 120 -- Wide enough for most screens

  -- Split by double newlines (paragraphs)
  local paragraphs = vim.split(response, "\n\n", { plain = true })

  for _, para in ipairs(paragraphs) do
    local trimmed = para:gsub("^%s+", ""):gsub("%s+$", "")

    if trimmed == "" then
      -- Empty paragraph = blank line
      table.insert(lines, indent)
    elseif trimmed:match("^%s%s") or trimmed:match("^\t") or trimmed:match("```") then
      -- Code block - preserve line breaks
      for line in para:gmatch("[^\n]+") do
        table.insert(lines, indent .. line)
      end
    else
      -- Regular paragraph - join all lines with space, then wrap
      local joined = trimmed:gsub("\n", " "):gsub("%s+", " ")
      local wrapped = M._wrap_text(joined, max_width - #indent)
      for _, wrapped_line in ipairs(wrapped) do
        table.insert(lines, indent .. wrapped_line)
      end
    end

    -- Add blank line between paragraphs
    table.insert(lines, indent)
  end

  -- Remove trailing blank line
  if #lines > 0 and lines[#lines] == indent then
    table.remove(lines)
  end

  return lines
end

---Wrap text to max width
---@param text string Text to wrap
---@param max_width number Max characters per line
---@return string[] lines Wrapped lines
function M._wrap_text(text, max_width)
  if #text <= max_width then
    return { text }
  end

  local lines = {}
  local words = {}
  for word in text:gmatch("%S+") do
    table.insert(words, word)
  end

  local current_line = ""

  for _, word in ipairs(words) do
    local test_line = current_line == "" and word or (current_line .. " " .. word)

    if #test_line <= max_width then
      current_line = test_line
    else
      if current_line ~= "" then
        table.insert(lines, current_line)
      end
      current_line = word
    end
  end

  if current_line ~= "" then
    table.insert(lines, current_line)
  end

  return lines
end

-- =============================================================================
-- Batch Response Writing
-- =============================================================================

---Replace multiple pending questions with responses from JSON
---@param responses table<string, string> Map of id -> response
---@param bufnr? number Buffer number
---@return number success_count Number of successfully replaced
---@return number fail_count Number of failed replacements
function M.replace_pending_batch(responses, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local success_count = 0
  local fail_count = 0

  -- Sort by block_start descending to replace from bottom to top
  -- This prevents line number shifts from affecting subsequent replacements
  local questions = parser.find_pending_questions(bufnr)
  table.sort(questions, function(a, b)
    return a.block_start > b.block_start
  end)

  for _, question in ipairs(questions) do
    local response = responses[question.id]
    if response then
      local ok = M.replace_pending_with_response(question.id, response, bufnr)
      if ok then
        success_count = success_count + 1
      else
        fail_count = fail_count + 1
      end
    end
  end

  return success_count, fail_count
end

return M
