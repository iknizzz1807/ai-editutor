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
---@field token_budget number Max tokens for context (default 100000)
---@field library_info_budget number Max tokens for library API info (default 2000)
---@field diagnostics_budget number Max tokens for LSP diagnostics (default 2000)
---@field library_scan_radius number Lines before/after question to scan (default 50)

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
  provider = "gemini",
  model = "gemini-3-flash-preview",

  -- Context extraction
  context = {
    token_budget = 100000, -- 100k tokens max for total context
    library_info_budget = 2000, -- 2k tokens max for library API info
    diagnostics_budget = 2000, -- 2k tokens max for LSP diagnostics
    library_scan_radius = 50, -- Lines before/after question to scan for library usage
  },

  -- Web Search & Smart Fix
  web_search = {
    brave_api_key = nil, -- string|nil: Brave Search API key (or set BRAVE_API_KEY environment variable)
    provider = "deepseek", -- "deepseek" | "ollama"
    model = "deepseek-flash", -- "deepseek-flash" | "qwen2.5-coder:3b"
    ollama_url = "http://localhost:11434",
    num_ctx = 32768,
    knapsack_max_chars = 30000, -- Sweet spot: 30k chars (~7.5k tokens)
    section1_cap_pct = 0.35,
    panel_width_pct = 0.40,
    max_search_results = 5, -- Sweet spot: 5 search results
    max_deep_docs = 3, -- Sweet spot: 3 deep docs
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
