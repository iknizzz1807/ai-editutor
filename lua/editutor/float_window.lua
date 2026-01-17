-- editutor/float_window.lua
-- Floating window to view/edit AI responses
-- Toggle open/close, editable, syntax highlighting, sync back to source

local M = {}

local comment_writer = require("editutor.comment_writer")
local parser = require("editutor.parser")

-- Track open float windows by source buffer
-- { [source_bufnr] = { win = win_id, buf = buf_id, response_start = line, response_end = line } }
M._windows = {}

---Get dimensions for float window
---@return table { width, height, row, col }
local function get_float_dimensions()
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines

  -- Float window: 80% width, 60% height, centered
  local width = math.floor(editor_width * 0.8)
  local height = math.floor(editor_height * 0.6)
  local row = math.floor((editor_height - height) / 2)
  local col = math.floor((editor_width - width) / 2)

  return {
    width = width,
    height = height,
    row = row,
    col = col,
  }
end

---Strip comment syntax from content for display
---@param content string Raw content with comment markers
---@param style table Comment style
---@return string Cleaned content
local function strip_comment_syntax(content, style)
  local lines = {}

  for line in content:gmatch("[^\n]*") do
    local cleaned = line

    -- Remove block comment markers
    if style.block then
      local block_start = style.block[1]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
      local block_end = style.block[2]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
      cleaned = cleaned:gsub("^%s*" .. block_start .. "%s*", "")
      cleaned = cleaned:gsub("%s*" .. block_end .. "%s*$", "")
    end

    -- Remove line comment prefix
    if style.line then
      local line_prefix = style.line:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
      cleaned = cleaned:gsub("^%s*" .. line_prefix .. "%s*", "")
    end

    -- Remove [AI] marker
    cleaned = cleaned:gsub("^%[AI%]%s*", "")

    table.insert(lines, cleaned)
  end

  return table.concat(lines, "\n")
end

---Wrap content back into comment syntax for saving
---@param content string Plain content
---@param style table Comment style
---@param indent string Indentation
---@return string[] lines Comment-wrapped lines
local function wrap_in_comment_syntax(content, style, indent)
  local lines = {}

  if style.block then
    -- Block comment with [AI] marker
    table.insert(lines, indent .. style.block[1] .. " " .. comment_writer.AI_MARKER)

    for line in content:gmatch("[^\n]*") do
      table.insert(lines, indent .. line)
    end

    table.insert(lines, indent .. style.block[2])
  elseif style.line then
    -- Line comments with [AI] marker
    local prefix = style.line .. " "
    table.insert(lines, indent .. prefix .. comment_writer.AI_MARKER)

    for line in content:gmatch("[^\n]*") do
      table.insert(lines, indent .. prefix .. line)
    end
  end

  return lines
end

---Close float window for a source buffer
---@param source_bufnr number
---@param save boolean Whether to save changes back
function M.close(source_bufnr, save)
  local state = M._windows[source_bufnr]
  if not state then
    return
  end

  if save and vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_buf_is_valid(source_bufnr) then
    -- Get content from float buffer
    local float_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
    local content = table.concat(float_lines, "\n")

    -- Get style and indent from source
    local style = comment_writer.get_style(source_bufnr)
    local source_lines = vim.api.nvim_buf_get_lines(source_bufnr, state.response_start - 1, state.response_start, false)
    local indent = ""
    if source_lines[1] then
      indent = source_lines[1]:match("^(%s*)") or ""
    end

    -- Wrap content back in comment syntax
    local new_lines = wrap_in_comment_syntax(content, style, indent)

    -- Replace in source buffer
    vim.api.nvim_buf_set_lines(source_bufnr, state.response_start - 1, state.response_end, false, new_lines)
  end

  -- Close window if valid
  if vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end

  -- Delete buffer if valid
  if vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end

  M._windows[source_bufnr] = nil
end

---Open float window for AI response near cursor
---@param source_bufnr? number Source buffer (default: current)
---@return boolean success
function M.open(source_bufnr)
  source_bufnr = source_bufnr or vim.api.nvim_get_current_buf()

  -- Close existing float for this buffer
  if M._windows[source_bufnr] then
    M.close(source_bufnr, false)
  end

  -- Find comment near cursor
  local comment_info = parser.find_question_near_cursor(source_bufnr)
  if not comment_info then
    vim.notify("[ai-editutor] No comment found near cursor", vim.log.levels.WARN)
    return false
  end

  -- Find AI response block
  local response = comment_writer.find_ai_response_block(source_bufnr, comment_info.line_num + 1)
  if not response then
    vim.notify("[ai-editutor] No AI response found for this comment", vim.log.levels.WARN)
    return false
  end

  -- Get comment style
  local style = comment_writer.get_style(source_bufnr)

  -- Strip comment syntax for display
  local clean_content = strip_comment_syntax(response.content, style)

  -- Create float buffer
  local float_buf = vim.api.nvim_create_buf(false, true)

  -- Set content
  local content_lines = {}
  for line in clean_content:gmatch("[^\n]*") do
    table.insert(content_lines, line)
  end
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, content_lines)

  -- Get dimensions
  local dims = get_float_dimensions()

  -- Create float window
  local float_win = vim.api.nvim_open_win(float_buf, true, {
    relative = "editor",
    width = dims.width,
    height = dims.height,
    row = dims.row,
    col = dims.col,
    style = "minimal",
    border = "rounded",
    title = " AI Response (q to close, :w to save) ",
    title_pos = "center",
  })

  -- Set buffer options
  vim.bo[float_buf].modifiable = true
  vim.bo[float_buf].buftype = "nofile"
  vim.bo[float_buf].swapfile = false

  -- Try to inherit filetype for syntax highlighting
  local source_ft = vim.bo[source_bufnr].filetype
  -- For responses, markdown is usually best
  vim.bo[float_buf].filetype = "markdown"

  -- Set window options
  vim.wo[float_win].wrap = true
  vim.wo[float_win].linebreak = true
  vim.wo[float_win].cursorline = true
  vim.wo[float_win].number = false
  vim.wo[float_win].relativenumber = false

  -- Store state
  M._windows[source_bufnr] = {
    win = float_win,
    buf = float_buf,
    response_start = response.start_line,
    response_end = response.end_line,
    source_ft = source_ft,
  }

  -- Keymaps for float window
  local opts = { buffer = float_buf, silent = true }

  -- Close without saving
  vim.keymap.set("n", "q", function()
    M.close(source_bufnr, false)
  end, opts)

  vim.keymap.set("n", "<Esc>", function()
    M.close(source_bufnr, false)
  end, opts)

  -- Save and close
  vim.keymap.set("n", "<C-s>", function()
    M.close(source_bufnr, true)
    vim.notify("[ai-editutor] Changes saved", vim.log.levels.INFO)
  end, opts)

  -- :w to save
  vim.api.nvim_buf_create_user_command(float_buf, "w", function()
    M.close(source_bufnr, true)
    vim.notify("[ai-editutor] Changes saved", vim.log.levels.INFO)
  end, {})

  -- :wq to save and close
  vim.api.nvim_buf_create_user_command(float_buf, "wq", function()
    M.close(source_bufnr, true)
    vim.notify("[ai-editutor] Changes saved", vim.log.levels.INFO)
  end, {})

  -- :q to close without saving
  vim.api.nvim_buf_create_user_command(float_buf, "q", function()
    M.close(source_bufnr, false)
  end, {})

  -- Auto close on leaving buffer
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = float_buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if M._windows[source_bufnr] then
          M.close(source_bufnr, false)
        end
      end)
    end,
  })

  return true
end

---Toggle float window for AI response near cursor
---@param source_bufnr? number Source buffer (default: current)
function M.toggle(source_bufnr)
  source_bufnr = source_bufnr or vim.api.nvim_get_current_buf()

  if M._windows[source_bufnr] and vim.api.nvim_win_is_valid(M._windows[source_bufnr].win) then
    -- Window is open, close it (without saving by default)
    M.close(source_bufnr, false)
  else
    -- Window is closed, open it
    M.open(source_bufnr)
  end
end

---Check if float window is open for a buffer
---@param source_bufnr? number
---@return boolean
function M.is_open(source_bufnr)
  source_bufnr = source_bufnr or vim.api.nvim_get_current_buf()
  local state = M._windows[source_bufnr]
  return state ~= nil and vim.api.nvim_win_is_valid(state.win)
end

---Close all float windows
function M.close_all()
  for bufnr, _ in pairs(M._windows) do
    M.close(bufnr, false)
  end
end

return M
