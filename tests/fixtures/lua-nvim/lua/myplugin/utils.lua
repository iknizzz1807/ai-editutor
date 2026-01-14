-- myplugin/utils.lua
-- Utility functions

local M = {}

local config = require("myplugin.config")

---Check if a value is nil or empty
---@param value any
---@return boolean
function M.is_empty(value)
  if value == nil then
    return true
  end
  if type(value) == "string" and value == "" then
    return true
  end
  if type(value) == "table" and next(value) == nil then
    return true
  end
  return false
end

---Safely call a function
---@param fn function
---@param ... any
---@return boolean success
---@return any result_or_error
function M.pcall(fn, ...)
  return pcall(fn, ...)
end

---Log a debug message
---@param msg string
---@param ... any
function M.debug(msg, ...)
  if config.get("debug") then
    local formatted = string.format(msg, ...)
    vim.notify("[MyPlugin Debug] " .. formatted, vim.log.levels.DEBUG)
  end
end

---Log an info message
---@param msg string
---@param ... any
function M.info(msg, ...)
  local formatted = string.format(msg, ...)
  vim.notify("[MyPlugin] " .. formatted, vim.log.levels.INFO)
end

---Log a warning
---@param msg string
---@param ... any
function M.warn(msg, ...)
  local formatted = string.format(msg, ...)
  vim.notify("[MyPlugin] " .. formatted, vim.log.levels.WARN)
end

---Log an error
---@param msg string
---@param ... any
function M.error(msg, ...)
  local formatted = string.format(msg, ...)
  vim.notify("[MyPlugin] " .. formatted, vim.log.levels.ERROR)
end

---Debounce a function
---@param fn function
---@param ms number
---@return function
function M.debounce(fn, ms)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
    end
    timer = vim.loop.new_timer()
    timer:start(ms, 0, vim.schedule_wrap(function()
      fn(unpack(args))
    end))
  end
end

---Get visual selection text
---@return string|nil
function M.get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.fn.getline(start_pos[2], end_pos[2])

  if #lines == 0 then
    return nil
  end

  -- Adjust for partial line selection
  lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
  lines[1] = string.sub(lines[1], start_pos[3])

  return table.concat(lines, "\n")
end

return M
