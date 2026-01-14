-- myplugin/init.lua
-- Main entry point

local M = {}

local config = require("myplugin.config")
local utils = require("myplugin.utils")
local window = require("myplugin.window")

M._name = "MyPlugin"
M._version = "1.0.0"

---Setup the plugin
---@param opts? table User configuration
function M.setup(opts)
  config.setup(opts)
  M._setup_commands()
  M._setup_keymaps()

  utils.info("Plugin loaded (v%s)", M._version)
end

---Setup user commands
function M._setup_commands()
  vim.api.nvim_create_user_command("MyPluginToggle", function()
    M.toggle()
  end, { desc = "Toggle MyPlugin window" })

  vim.api.nvim_create_user_command("MyPluginOpen", function()
    M.open()
  end, { desc = "Open MyPlugin window" })

  vim.api.nvim_create_user_command("MyPluginClose", function()
    M.close()
  end, { desc = "Close MyPlugin window" })
end

---Setup keymaps
function M._setup_keymaps()
  local keymaps = config.get("keymaps")

  if keymaps.toggle then
    vim.keymap.set("n", keymaps.toggle, M.toggle, {
      desc = "Toggle MyPlugin",
    })
  end
end

---Open the plugin window
---@param content? string[] Initial content
function M.open(content)
  if not config.get("enabled") then
    utils.warn("Plugin is disabled")
    return
  end

  window.open(content)
end

---Close the plugin window
function M.close()
  window.close()
end

---Toggle the plugin window
function M.toggle()
  window.toggle()
end

---Check if window is open
---@return boolean
function M.is_open()
  return window.is_open()
end

---Get plugin version
---@return string
function M.version()
  return M._version
end

return M
