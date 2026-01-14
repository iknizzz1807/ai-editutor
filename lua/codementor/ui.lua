-- codementor/ui.lua
-- Floating window UI for mentor responses

local M = {}

local config = require("codementor.config")

-- Track current popup state
local state = {
  popup_buf = nil,
  popup_win = nil,
  hint_callback = nil,  -- Callback for next hint
  hint_info = nil,      -- Current hint info string
}

---Calculate popup dimensions
---@return number width
---@return number height
---@return number row
---@return number col
local function calculate_dimensions()
  local ui_config = config.options.ui
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines

  -- Calculate width
  local width = ui_config.width
  if type(width) == "string" and width:match("%%$") then
    width = math.floor(editor_width * tonumber(width:sub(1, -2)) / 100)
  end
  width = math.min(width, ui_config.max_width or 120)
  width = math.min(width, editor_width - 4)

  -- Calculate height
  local height = ui_config.height
  if type(height) == "string" and height:match("%%$") then
    height = math.floor(editor_height * tonumber(height:sub(1, -2)) / 100)
  end
  height = math.min(height, editor_height - 6)

  -- Center the popup
  local row = math.floor((editor_height - height) / 2) - 1
  local col = math.floor((editor_width - width) / 2)

  return width, height, row, col
end

---Create floating window
---@param content string|string[] Content to display
---@param title string|nil Window title
---@return number|nil buf Buffer number
---@return number|nil win Window number
local function create_popup(content, title)
  local width, height, row, col = calculate_dimensions()
  local ui_config = config.options.ui

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  -- Set content
  local lines = content
  if type(content) == "string" then
    lines = vim.split(content, "\n")
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Create window
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = ui_config.border or "rounded",
    title = title and (" " .. title .. " ") or nil,
    title_pos = title and "center" or nil,
    zindex = 50,
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set window options
  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("linebreak", true, { win = win })
  vim.api.nvim_set_option_value("cursorline", false, { win = win })

  return buf, win
end

---Close current popup
function M.close()
  if state.popup_win and vim.api.nvim_win_is_valid(state.popup_win) then
    vim.api.nvim_win_close(state.popup_win, true)
  end
  state.popup_win = nil
  state.popup_buf = nil
  state.hint_callback = nil
  state.hint_info = nil
end

---Setup keymaps for popup window
---@param buf number Buffer number
---@param has_hints boolean Whether hints are available
local function setup_keymaps(buf, has_hints)
  local keymaps = config.options.keymaps
  local opts = { buffer = buf, silent = true, noremap = true }

  -- Close popup
  vim.keymap.set("n", keymaps.close or "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)

  -- Copy content
  vim.keymap.set("n", keymaps.copy or "y", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local content = table.concat(lines, "\n")
    vim.fn.setreg("+", content)
    vim.notify("Copied to clipboard", vim.log.levels.INFO)
  end, opts)

  -- Next hint (only if hints available)
  if has_hints then
    vim.keymap.set("n", keymaps.next_hint or "n", function()
      if state.hint_callback then
        state.hint_callback()
      else
        vim.notify("No more hints available", vim.log.levels.INFO)
      end
    end, opts)
  end

  -- Scroll
  vim.keymap.set("n", "j", "gj", opts)
  vim.keymap.set("n", "k", "gk", opts)
  vim.keymap.set("n", "<C-d>", "<C-d>zz", opts)
  vim.keymap.set("n", "<C-u>", "<C-u>zz", opts)
end

---Show mentor response in floating window
---@param content string Response content
---@param mode string|nil Mode name for title
---@param question string|nil Original question for context
---@param opts? table Options {hint_level?: number, has_more_hints?: boolean, hint_callback?: function}
---@return boolean success
function M.show(content, mode, question, opts)
  opts = opts or {}

  -- Close existing popup
  M.close()

  -- Build title
  local title = "Code Mentor"
  if mode then
    title = title .. " [" .. mode:upper() .. "]"
  end
  if opts.hint_level then
    title = title .. " Hint " .. opts.hint_level .. "/4"
  end

  -- Create formatted content
  local formatted = {}

  if question then
    table.insert(formatted, "**Question:** " .. question)
    table.insert(formatted, "")
    table.insert(formatted, "---")
    table.insert(formatted, "")
  end

  -- Add response
  for line in content:gmatch("[^\n]*") do
    table.insert(formatted, line)
  end

  -- Add footer
  table.insert(formatted, "")
  table.insert(formatted, "---")

  local footer_parts = { "`q` close", "`y` copy" }
  if opts.has_more_hints then
    table.insert(footer_parts, "`n` next hint")
  end
  table.insert(formatted, "*" .. table.concat(footer_parts, " | ") .. "*")

  -- Create popup
  local buf, win = create_popup(formatted, title)
  if not buf or not win then
    vim.notify("Failed to create popup window", vim.log.levels.ERROR)
    return false
  end

  state.popup_buf = buf
  state.popup_win = win
  state.hint_callback = opts.hint_callback
  state.hint_info = opts.hint_level and string.format("Hint %d/4", opts.hint_level) or nil

  -- Setup keymaps
  setup_keymaps(buf, opts.has_more_hints)

  -- Auto-close on buffer leave
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(M.close)
    end,
  })

  return true
end

---Show loading indicator
---@param message string|nil Loading message
function M.show_loading(message)
  message = message or "Thinking..."

  local loading_content = {
    "",
    "  " .. message,
    "",
    "  Press <C-c> to cancel",
    "",
  }

  -- Close existing popup
  M.close()

  local buf, win = create_popup(loading_content, "Code Mentor")
  if buf and win then
    state.popup_buf = buf
    state.popup_win = win

    -- Allow canceling
    vim.keymap.set("n", "<C-c>", function()
      M.close()
      vim.notify("Cancelled", vim.log.levels.INFO)
    end, { buffer = buf, silent = true })
  end
end

---Update existing popup with new content
---@param content string New content
---@return boolean success
function M.update(content)
  if not state.popup_buf or not vim.api.nvim_buf_is_valid(state.popup_buf) then
    return false
  end

  local lines = vim.split(content, "\n")

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.popup_buf })
  vim.api.nvim_buf_set_lines(state.popup_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.popup_buf })

  return true
end

---Check if popup is currently open
---@return boolean
function M.is_open()
  return state.popup_win ~= nil and vim.api.nvim_win_is_valid(state.popup_win)
end

return M
