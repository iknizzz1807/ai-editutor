-- editutor/health.lua
-- Health check for :checkhealth editutor
-- v1.1.0: Updated for simplified architecture (no SQLite/indexer)

local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

function M.check()
  start("ai-editutor Core")

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
    ok(string.format("ai-editutor version: %s", editutor._version or "unknown"))
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
  start("ai-editutor LLM Provider")

  local config = require("editutor.config")
  local provider = config.get_provider()

  if provider then
    ok(string.format("Active provider: %s", provider.name))
    info(string.format("Model: %s", config.options.model or provider.model or "default"))

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

  -- Context extraction checks
  start("ai-editutor Context Extraction")

  local context_ok, context_mod = pcall(require, "editutor.context")
  if context_ok then
    ok("Context module loaded")

    -- Check token budget
    local budget = context_mod.get_token_budget()
    info(string.format("Token budget: %d tokens", budget))

    -- Detect mode for current project
    local mode_info = context_mod.detect_mode()
    if mode_info.mode == "full_project" then
      ok(string.format("Mode: FULL_PROJECT (%d tokens, within budget)", mode_info.project_tokens))
    else
      info(string.format("Mode: LSP_SELECTIVE (project %d tokens > budget %d)",
        mode_info.project_tokens, mode_info.budget))
    end
  else
    warn("Context module not loaded")
  end

  -- LSP checks
  start("ai-editutor LSP")

  local lsp_context_ok, lsp_context = pcall(require, "editutor.lsp_context")
  if lsp_context_ok then
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
        "For large projects, LSP provides better context",
      })
    end

    -- Check project root detection
    local project_root = lsp_context.get_project_root()
    ok(string.format("Project root: %s", project_root))
  else
    warn("LSP context module not loaded")
  end

  -- Project scanner checks
  start("ai-editutor Project Scanner")

  local scanner_ok, scanner = pcall(require, "editutor.project_scanner")
  if scanner_ok then
    ok("Project scanner loaded")

    -- Scan project
    local scan_result = scanner.scan_project()
    info(string.format("Project files: %d source files", #scan_result.files))
    info(string.format("Project folders: %d folders", #scan_result.folders))
    info(string.format("Estimated tokens: %d", scan_result.total_tokens))
  else
    warn("Project scanner not loaded")
  end

  -- Knowledge tracking checks
  start("ai-editutor Knowledge Tracking")

  local knowledge_ok, knowledge = pcall(require, "editutor.knowledge")
  if knowledge_ok then
    local stats = knowledge.get_stats()
    ok(string.format("Knowledge database: %d entries (JSON storage)", stats.total or 0))

    if stats.total and stats.total > 0 then
      local modes = {}
      for mode, count in pairs(stats.by_mode or {}) do
        table.insert(modes, string.format("%s:%d", mode, count))
      end
      if #modes > 0 then
        info("By mode: " .. table.concat(modes, ", "))
      end
    end
  else
    warn("Knowledge module not loaded")
  end

  -- Cache checks
  start("ai-editutor Cache")

  local cache_ok, cache_mod = pcall(require, "editutor.cache")
  if cache_ok then
    ok("Cache module loaded")

    local cache_stats = cache_mod.get_stats()
    info(string.format("Cache entries: %d active", cache_stats.active or 0))
  else
    warn("Cache module not loaded")
  end

  -- Debug log checks
  start("ai-editutor Debug Log")

  local debug_ok, debug_log = pcall(require, "editutor.debug_log")
  if debug_ok then
    ok("Debug log module loaded")

    local log_size = debug_log.get_size()
    if log_size > 0 then
      info(string.format("Log file size: %.1f KB", log_size / 1024))
      info(string.format("Log path: %s", debug_log.get_log_path()))
    else
      info("No debug log yet (created on first request)")
    end
  else
    warn("Debug log module not loaded")
  end

  -- Summary
  start("ai-editutor Quick Start")
  info("Write: // Q: your question")
  info("Keymap: <leader>ma (or run :EduTutorAsk)")
  info("")
  info("Context modes:")
  info("  - FULL_PROJECT: Sends entire project if < 20k tokens")
  info("  - LSP_SELECTIVE: Uses LSP definitions for large projects")
  info("")
  info("Commands:")
  info("  :EduTutorAsk      - Ask question")
  info("  :EduTutorHint     - Get progressive hints")
  info("  :EduTutorLog      - Open debug log")
  info("  :EduTutorHistory  - View Q&A history")
  info("  :EduTutorStats    - View statistics")
  info("")
  info("Help: :h editutor")
end

return M
