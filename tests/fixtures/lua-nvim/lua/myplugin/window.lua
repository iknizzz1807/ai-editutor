-- myplugin/window.lua
-- Window management

local M = {}

local config = require("myplugin.config")
local utils = require("myplugin.utils")

---@class WindowState
---@field buf number|nil Buffer number
---@field win number|nil Window number
---@field is_open boolean Whether window is open

local state = {
  buf = nil,
  win = nil,
  is_open = false,
}

---Create a new scratch buffer
---@return number bufnr
local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "myplugin"
  return buf
end

---Calculate window dimensions
---@return table opts
local function get_window_opts()
  local ui_config = config.get("ui")
  local width = ui_config.width
  local height = ui_config.height

  -- Center the window
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  return {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = ui_config.border,
  }
end

-- Q: How does this handle window resize events?
---Open the floating window
---@param content? string[] Initial content
---@return number|nil win Window handle
function M.open(content)
  if state.is_open then
    utils.debug("Window already open")
    return state.win
  end

  -- Create buffer and window
  state.buf = create_buffer()
  local opts = get_window_opts()
  state.win = vim.api.nvim_open_win(state.buf, true, opts)
  state.is_open = true

  -- Set content if provided
  if content then
    M.set_content(content)
  end

  -- Setup keymaps
  M.setup_keymaps()

  utils.debug("Opened window: buf=%d, win=%d", state.buf, state.win)
  return state.win
end

---Close the floating window
function M.close()
  if not state.is_open then
    return
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end

  state.buf = nil
  state.win = nil
  state.is_open = false

  utils.debug("Closed window")
end

---Toggle the floating window
function M.toggle()
  if state.is_open then
    M.close()
  else
    M.open()
  end
end

---Set window content
---@param lines string[]
function M.set_content(lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    utils.warn("No valid buffer")
    return
  end

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
end

---Append content to window
---@param lines string[]
function M.append_content(lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local current = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  for _, line in ipairs(lines) do
    table.insert(current, line)
  end
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, current)
end

---Setup window keymaps
function M.setup_keymaps()
  if not state.buf then
    return
  end

  local keymaps = config.get("keymaps")
  local opts = { buffer = state.buf, noremap = true, silent = true }

  -- Close on q or Escape
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
end

---Check if window is open
---@return boolean
function M.is_open()
  return state.is_open
end

---Get window state
---@return WindowState
function M.get_state()
  return vim.deepcopy(state)
end

return M
