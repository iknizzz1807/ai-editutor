-- tests/minimal_init.lua
-- Minimal Neovim configuration for running tests

-- Add project to runtime path
local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(project_root)

-- Add plenary to runtime path (assuming it's installed)
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:prepend(plenary_path)
end

-- Also check for plenary in packer location
local packer_plenary = vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim"
if vim.fn.isdirectory(packer_plenary) == 1 then
  vim.opt.rtp:prepend(packer_plenary)
end

-- Check ~/.local/share/nvim/site/pack
local site_pack_plenary = vim.fn.stdpath("data") .. "/site/pack/*/start/plenary.nvim"
local found_plenarys = vim.fn.glob(site_pack_plenary, false, true)
for _, path in ipairs(found_plenarys) do
  vim.opt.rtp:prepend(path)
end

-- Basic vim settings
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
vim.o.undofile = false

-- Disable shada
vim.o.shadafile = "NONE"

-- Set up package path for our plugin
package.loaded["editutor"] = nil
package.loaded["editutor.config"] = nil
package.loaded["editutor.parser"] = nil
package.loaded["editutor.context"] = nil
package.loaded["editutor.project_scanner"] = nil
package.loaded["editutor.lsp_context"] = nil

-- Add tests to package path
package.path = package.path .. ";" .. project_root .. "/tests/?.lua"

print("Minimal init loaded from: " .. project_root)
