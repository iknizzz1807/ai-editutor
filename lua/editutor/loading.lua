-- editutor/loading.lua
-- Loading indicator for LLM requests
-- Shows animated spinner and status in statusline or virtual text

local M = {}

-- Loading state
M._active = false
M._message = ""
M._spinner_idx = 1
M._timer = nil
M._extmark_id = nil
M._namespace = vim.api.nvim_create_namespace("editutor_loading")
-- Track the specific buffer and line where loading started
M._target_bufnr = nil
M._target_line = nil

-- Spinner frames (braille pattern for smooth animation)
M.SPINNERS = {
  braille = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  dots = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
  line = { "-", "\\", "|", "/" },
  arrow = { "←", "↖", "↑", "↗", "→", "↘", "↓", "↙" },
  simple = { ".", "..", "...", "...." },
}

M.config = {
  spinner = "braille",
  interval_ms = 80,
  show_virtual_text = true,
  virtual_text_position = "eol", -- "eol" or "overlay"
  statusline_component = true,
}

---Setup loading indicator
---@param opts? table Configuration options
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
end

---Get current spinner frame
---@return string frame
local function get_spinner_frame()
  local frames = M.SPINNERS[M.config.spinner] or M.SPINNERS.braille
  return frames[M._spinner_idx]
end

---Advance spinner to next frame
local function advance_spinner()
  local frames = M.SPINNERS[M.config.spinner] or M.SPINNERS.braille
  M._spinner_idx = (M._spinner_idx % #frames) + 1
end

---Update virtual text display
local function update_virtual_text()
  if not M._active then
    return
  end

  -- Use the target buffer and line, not current cursor position
  local bufnr = M._target_bufnr
  local line = M._target_line

  -- Validate buffer is still valid
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Validate line is within buffer range
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line >= line_count then
    line = line_count - 1
  end
  if line < 0 then
    line = 0
  end

  -- Clear previous extmark in target buffer
  if M._extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M._namespace, M._extmark_id)
  end

  -- Create new extmark with virtual text
  local spinner = get_spinner_frame()
  local text = string.format(" %s %s", spinner, M._message)

  M._extmark_id = vim.api.nvim_buf_set_extmark(bufnr, M._namespace, line, 0, {
    virt_text = { { text, "Comment" } },
    virt_text_pos = M.config.virtual_text_position,
    hl_mode = "combine",
  })
end

---Clear virtual text
local function clear_virtual_text()
  -- Clear extmark in target buffer
  if M._extmark_id and M._target_bufnr and vim.api.nvim_buf_is_valid(M._target_bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, M._target_bufnr, M._namespace, M._extmark_id)
  end
  M._extmark_id = nil

  -- Also clear all extmarks in namespace (cleanup any orphaned marks)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_clear_namespace, buf, M._namespace, 0, -1)
    end
  end
end

---Start loading indicator
---@param message? string Loading message
---@param bufnr? number Target buffer (defaults to current)
---@param line? number Target line 0-indexed (defaults to cursor line)
function M.start(message, bufnr, line)
  if M._active then
    M.stop()
  end

  M._active = true
  M._message = message or "Thinking..."
  M._spinner_idx = 1

  -- Capture target buffer and line at start time
  M._target_bufnr = bufnr or vim.api.nvim_get_current_buf()
  if line then
    M._target_line = line
  else
    local cursor = vim.api.nvim_win_get_cursor(0)
    M._target_line = cursor[1] - 1
  end

  -- Start timer for animation
  M._timer = vim.fn.timer_start(M.config.interval_ms, function()
    vim.schedule(function()
      if M._active then
        advance_spinner()
        if M.config.show_virtual_text then
          update_virtual_text()
        end
        -- Trigger statusline refresh
        vim.cmd("redrawstatus")
      end
    end)
  end, { ["repeat"] = -1 })

  -- Initial display
  if M.config.show_virtual_text then
    vim.schedule(function()
      update_virtual_text()
    end)
  end
end

---Update loading message
---@param message string New message
function M.update(message)
  M._message = message
  if M.config.show_virtual_text and M._active then
    vim.schedule(function()
      update_virtual_text()
    end)
  end
end

---Stop loading indicator
function M.stop()
  M._active = false
  M._message = ""

  if M._timer then
    vim.fn.timer_stop(M._timer)
    M._timer = nil
  end

  clear_virtual_text()

  -- Clear target tracking
  M._target_bufnr = nil
  M._target_line = nil

  vim.cmd("redrawstatus")
end

---Check if loading is active
---@return boolean
function M.is_active()
  return M._active
end

---Get current loading status for statusline
---@return string status Empty string if not loading
function M.statusline()
  if not M._active then
    return ""
  end

  local spinner = get_spinner_frame()
  return string.format(" %s %s ", spinner, M._message)
end

---Get statusline component (for lualine, etc.)
---@return table component
function M.lualine_component()
  return {
    function()
      return M.statusline()
    end,
    cond = function()
      return M._active
    end,
    color = { fg = "#f9e2af" }, -- Yellow
  }
end

---Execute function with loading indicator
---@param message string Loading message
---@param fn function Function to execute
---@param callback function Callback with result
function M.with_loading(message, fn, callback)
  M.start(message)

  -- Wrap in pcall for safety
  local ok, result = pcall(fn)

  M.stop()

  if ok then
    callback(result, nil)
  else
    callback(nil, result)
  end
end

---Execute async function with loading indicator
---@param message string Loading message
---@param async_fn function Async function(callback)
---@param on_done function Callback(result, error)
function M.with_loading_async(message, async_fn, on_done)
  M.start(message)

  async_fn(function(result, err)
    M.stop()
    on_done(result, err)
  end)
end

---Show progress with percentage
---@param message string Message
---@param current number Current progress
---@param total number Total
function M.progress(message, current, total)
  local pct = math.floor((current / total) * 100)
  M.update(string.format("%s (%d%%)", message, pct))
end

---Predefined loading states
M.states = {
  thinking = "Thinking...",
  gathering_context = "Gathering context...",
  searching = "Searching codebase...",
  indexing = "Indexing project...",
  connecting = "Connecting to LLM...",
  streaming = "Receiving response...",
  formatting = "Formatting response...",
}

return M
