-- Minimal init for running tests
-- Usage: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

-- Add plugin to runtimepath
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(plugin_root)

-- Add plenary to runtimepath (adjust path as needed)
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:prepend(plenary_path)
end

-- Alternative: try site packages
local site_plenary = vim.fn.expand("~/.local/share/nvim/site/pack/*/start/plenary.nvim")
local site_dirs = vim.fn.glob(site_plenary, false, true)
if #site_dirs > 0 then
  vim.opt.runtimepath:prepend(site_dirs[1])
end

-- Load plenary
local ok, _ = pcall(require, "plenary")
if not ok then
  print("ERROR: plenary.nvim not found. Please install it first.")
  print("Searched paths:")
  print("  - " .. plenary_path)
  print("  - " .. site_plenary)
  vim.cmd("qa!")
end

-- Disable swap files for tests
vim.opt.swapfile = false

-- Load the plugin
require("editutor")
