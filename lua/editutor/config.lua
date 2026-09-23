-- editutor/config.lua
-- Configuration management for ai-editutor
-- v3.0.0: New keymaps for question spawning and processing

local M = {}

---@class EditutorConfig
---@field provider string LLM provider ("gemini" | "deepseek")
---@field api_key string|function API key or function returning key
---@field model string Model identifier
---@field keymaps EditutorKeymaps Keymap configuration
---@field context EditutorContextConfig Context extraction config
---@field providers table<string, EditutorProvider> Provider configurations

---@class EditutorKeymaps
---@field question string Spawn a new question block
---@field ask string Process all pending questions
---@field code string Spawn a new code request block
---@field execute string Execute all pending code requests

---@class EditutorContextConfig
---@field token_budget number Max tokens for context (default 52000)
---@field library_info_budget number Max tokens for library API info (default 3500)
---@field diagnostics_budget number Max tokens for LSP diagnostics (default 2500)
---@field references_budget number Max tokens for LSP references (default 4000)
---@field library_scan_radius number Lines before/after question to scan (default 60)

---@class EditutorProvider
---@field name string Provider name
---@field url string API endpoint URL
---@field model string Default model
---@field headers table HTTP headers
---@field api_key function Function to get API key
---@field format_request function Format request payload
---@field format_response function Parse response
---@field format_error function Parse error

M.defaults = {
  -- LLM Provider
  provider = "deepseek",
  model = "deepseek-flash",
  max_output_tokens = 8192, -- DeepSeek-Flash 8k output tokens (52k in + 8k out = 60k max ping)

  -- Context extraction
  context = {
    token_budget = 52000, -- 52k tokens max for total context input (~50k-60k max total ping)
    library_info_budget = 3500, -- 3.5k tokens max for library API info / hover docs
    diagnostics_budget = 2500, -- 2.5k tokens max for LSP diagnostics
    references_budget = 4000, -- 4k tokens max for LSP references / call sites
    library_scan_radius = 60, -- Lines before/after question to scan for library usage
  },

  -- Web Search & Smart Fix
  web_search = {
    brave_api_key = nil, -- string|nil: Brave Search API key (or set BRAVE_API_KEY environment variable)
    provider = "deepseek", -- "deepseek" | "ollama"
    model = "deepseek-flash", -- "deepseek-flash" | "qwen2.5-coder:3b"
    ollama_url = "http://localhost:11434",
    num_ctx = 32768,
    knapsack_max_chars = 36000, -- Sweet spot: 36k chars (~9k tokens)
    section1_cap_pct = 0.35,
    panel_width_pct = 0.40,
    max_search_results = 5, -- Sweet spot: 5 search results
    max_deep_docs = 3, -- Sweet spot: 3 deep docs
    max_code_lines = 120, -- Up from 35 lines
    max_code_chars = 16000, -- Up from 4000 chars (~4k tokens)
    max_diag_count = 8,
  },

  -- Keymaps
  keymaps = {
    question = "<leader>mq", -- Spawn a new question block
    ask = "<leader>ma", -- Process all pending questions
    code = "<leader>mc", -- Spawn a new code request block
    execute = "<leader>mx", -- Execute all pending code requests
    search_instant = "<leader>si", -- Instant search & explain word / visual selection
    search_prompt = "<leader>ss", -- Search with prompt pre-filled
    search_blank = "<leader>sw", -- Blank web search query
    smart_fix = "<leader>se", -- Smart auto-diagnose & fix LSP error
  },

  -- Custom provider overrides (built-in providers are in provider.lua)
  -- Users can add custom providers here or override built-in ones
  providers = {},
}

M.options = vim.deepcopy(M.defaults)

---@param opts? table User configuration
function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)
  -- api_key is stored in M.options.api_key if provided
  -- provider.lua will check this before using provider's default api_key function
end

---@return EditutorProvider|nil
function M.get_provider()
  local provider_id = M.options.provider
  return M.options.providers[provider_id]
end

return M
