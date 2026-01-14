-- editutor/health.lua
-- Health check for :checkhealth editutor

local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

function M.check()
  start("EduTutor Core")

  -- Check Neovim version
  local nvim_version = vim.version()
  if nvim_version.major >= 0 and nvim_version.minor >= 9 then
    ok(string.format("Neovim version: %d.%d.%d", nvim_version.major, nvim_version.minor, nvim_version.patch))
  else
    warn("Neovim 0.9+ recommended for best experience")
  end

  -- Check plugin version
  local editutor_ok, editutor = pcall(require, "editutor")
  if editutor_ok then
    ok(string.format("EduTutor version: %s", editutor._version or "unknown"))
  end

  -- Check plenary.nvim
  local plenary_ok = pcall(require, "plenary")
  if plenary_ok then
    ok("plenary.nvim is installed")
  else
    error("plenary.nvim is required for HTTP requests", {
      "Install with your package manager: { 'nvim-lua/plenary.nvim' }",
    })
  end

  -- Check nui.nvim (optional, for better UI)
  local nui_ok = pcall(require, "nui.popup")
  if nui_ok then
    ok("nui.nvim is installed (enhanced UI available)")
  else
    info("nui.nvim not installed (optional, for enhanced floating windows)")
  end

  -- Check Tree-sitter
  local ts_ok = pcall(vim.treesitter.get_parser, 0)
  if ts_ok then
    ok("Tree-sitter is available")
  else
    warn("Tree-sitter not available - context extraction may be limited")
  end

  -- Check curl
  if vim.fn.executable("curl") == 1 then
    ok("curl is available")
  else
    error("curl is required for API requests")
  end

  -- Provider checks
  start("EduTutor LLM Provider")

  local config = require("editutor.config")
  local provider = config.get_provider()

  if provider then
    ok(string.format("Active provider: %s", provider.name))
    info(string.format("Model: %s", provider.model or "default"))

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
        error(string.format("%s_API_KEY environment variable not set", provider.name:upper()), {
          string.format("Set the %s_API_KEY environment variable", provider.name:upper()),
          "export " .. provider.name:upper() .. "_API_KEY='your-api-key'",
        })
      end
    else
      -- Check Ollama is running
      local handle = io.popen("curl -s http://localhost:11434/api/version 2>/dev/null")
      if handle then
        local result = handle:read("*a")
        handle:close()
        if result and result ~= "" then
          ok("Ollama is running")
        else
          warn("Ollama may not be running at localhost:11434", {
            "Start Ollama: ollama serve",
          })
        end
      end
    end
  else
    error("No provider configured", {
      "Configure in setup(): require('editutor').setup({ provider = 'claude' })",
    })
  end

  -- LSP Context checks
  start("EduTutor LSP Context")

  local lsp_context_ok, lsp_context = pcall(require, "editutor.lsp_context")
  if not lsp_context_ok then
    warn("LSP context module not loaded")
  else
    -- Check if LSP is available for current buffer
    if lsp_context.is_available() then
      ok("LSP is available for current buffer")

      -- List connected LSP clients
      local clients = vim.lsp.get_clients({ bufnr = 0 })
      for _, client in ipairs(clients) do
        info(string.format("  LSP client: %s", client.name))
      end
    else
      warn("No LSP client attached to current buffer", {
        "Install an LSP server for your language",
        "Lua: lua-language-server",
        "Python: pyright or pylsp",
        "TypeScript: typescript-language-server",
        "Context will fallback to Tree-sitter only",
      })
    end

    -- Check project root detection
    local project_root = lsp_context.get_project_root()
    ok(string.format("Project root: %s", project_root))
  end

  -- Knowledge tracking checks
  start("EduTutor Knowledge Tracking")

  local knowledge_ok, knowledge = pcall(require, "editutor.knowledge")
  if not knowledge_ok then
    warn("Knowledge module not loaded")
  else
    local stats = knowledge.get_stats()
    ok(string.format("Knowledge database: %d entries", stats.total or 0))

    if stats.total and stats.total > 0 then
      local modes = {}
      for mode, count in pairs(stats.by_mode or {}) do
        table.insert(modes, string.format("%s:%d", mode, count))
      end
      if #modes > 0 then
        info("By mode: " .. table.concat(modes, ", "))
      end
    end

    -- Check SQLite (optional)
    local sqlite_ok = pcall(require, "sqlite")
    if sqlite_ok then
      ok("sqlite.lua available (enhanced storage)")
    else
      info("Using JSON fallback for knowledge storage (sqlite.lua not installed)")
    end
  end

  -- Summary
  start("EduTutor Quick Start")
  info("Available modes: Q (Question), S (Socratic), R (Review), D (Debug), E (Explain)")
  info("Example: // Q: What does this function do?")
  info("Keymap: <leader>ma (or run :EduTutorAsk)")
  info("Help: :EduTutorModes or :h editutor")
end

return M
