-- editutor/config.lua
-- Configuration management for ai-editutor
-- v3.0.0: New keymaps for question spawning and processing

local M = {}

---@class EditutorConfig
---@field provider string LLM provider ("claude" | "openai" | "ollama")
---@field api_key string|function API key or function returning key
---@field model string Model identifier
---@field language string Language for explanations
---@field keymaps EditutorKeymaps Keymap configuration
---@field context EditutorContextConfig Context extraction config
---@field providers table<string, EditutorProvider> Provider configurations

---@class EditutorKeymaps
---@field question string Spawn a new question block
---@field ask string Process all pending questions

---@class EditutorContextConfig
---@field token_budget number Max tokens for context (default 25000)
---@field library_info_budget number Max tokens for library API info (default 2000)
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
  provider = "claude",
  model = "claude-sonnet-4-20250514",

  -- Language for responses: "English", "Vietnamese", "vi", "en"
  language = "English",

  -- Context extraction
  context = {
    token_budget = 25000, -- 25k tokens max for total context
    library_info_budget = 2000, -- 2k tokens max for library API info
    library_scan_radius = 50, -- Lines before/after question to scan for library usage
  },

  -- Keymaps
  keymaps = {
    question = "<leader>mq", -- Spawn a new question block
    ask = "<leader>ma",      -- Process all pending questions
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
