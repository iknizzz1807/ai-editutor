-- myplugin/config.lua
-- Configuration management

local M = {}

---@class PluginConfig
---@field enabled boolean Enable the plugin
---@field debug boolean Debug mode
---@field keymaps PluginKeymaps Keymap configuration
---@field ui PluginUI UI configuration

---@class PluginKeymaps
---@field toggle string Toggle keymap
---@field next string Next item keymap
---@field prev string Previous item keymap

---@class PluginUI
---@field width number Window width
---@field height number Window height
---@field border string Border style

M.defaults = {
  enabled = true,
  debug = false,
  keymaps = {
    toggle = "<leader>t",
    next = "]t",
    prev = "[t",
  },
  ui = {
    width = 60,
    height = 15,
    border = "rounded",
  },
}

M.options = vim.deepcopy(M.defaults)

---Setup the plugin configuration
---@param opts? table User configuration
function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)
end

---Get a config value by path
---@param path string Dot-separated path
---@return any
function M.get(path)
  local keys = vim.split(path, ".", { plain = true })
  local value = M.options

  for _, key in ipairs(keys) do
    if type(value) ~= "table" then
      return nil
    end
    value = value[key]
  end

  return value
end

return M
