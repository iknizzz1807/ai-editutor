-- editutor/config.lua
-- Configuration management for ai-editutor
-- v1.1.0: Simplified config (removed indexer, added token budget)

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
---@field ask string Trigger mentor ask
---@field toggle string Toggle AI response in float window

---@class EditutorContextConfig
---@field token_budget number Max tokens for context (default 20000)

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
    token_budget = 20000, -- 20k tokens max for context
  },

  -- Keymaps
  keymaps = {
    ask = "<leader>ma",      -- Ask AI about comment near cursor
    toggle = "<leader>mt",   -- Toggle AI response in float window
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
