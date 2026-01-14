-- codementor/health.lua
-- Health check for :checkhealth codementor

local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error

function M.check()
  start("CodeMentor")

  -- Check Neovim version
  local nvim_version = vim.version()
  if nvim_version.major >= 0 and nvim_version.minor >= 9 then
    ok(string.format("Neovim version: %d.%d.%d", nvim_version.major, nvim_version.minor, nvim_version.patch))
  else
    warn("Neovim 0.9+ recommended for best experience")
  end

  -- Check plenary.nvim
  local plenary_ok = pcall(require, "plenary")
  if plenary_ok then
    ok("plenary.nvim is installed")
  else
    error("plenary.nvim is required for HTTP requests")
  end

  -- Check Tree-sitter
  local ts_ok = pcall(vim.treesitter.get_parser, 0)
  if ts_ok then
    ok("Tree-sitter is available")
  else
    warn("Tree-sitter not available - context extraction may be limited")
  end

  -- Check provider configuration
  local config = require("codementor.config")
  local provider = config.get_provider()

  if provider then
    ok(string.format("Provider configured: %s", provider.name))

    -- Check API key
    if provider.name ~= "ollama" then
      local api_key = nil
      if provider.api_key then
        local key_ok, key = pcall(provider.api_key)
        if key_ok then
          api_key = key
        end
      end

      if api_key and api_key ~= "" then
        ok(string.format("%s API key is set", provider.name:upper()))
      else
        error(string.format("%s_API_KEY environment variable not set", provider.name:upper()))
      end
    else
      ok("Ollama provider configured (no API key required)")
    end
  else
    error("No provider configured")
  end

  -- Check curl
  if vim.fn.executable("curl") == 1 then
    ok("curl is available")
  else
    error("curl is required for API requests")
  end
end

return M
