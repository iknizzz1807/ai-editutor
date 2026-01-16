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
    ask = "<leader>ma",
  },

  -- Provider configurations
  providers = {
    claude = {
      name = "claude",
      url = "https://api.anthropic.com/v1/messages",
      model = "claude-sonnet-4-20250514",
      headers = {
        ["content-type"] = "application/json",
        ["x-api-key"] = "${api_key}",
        ["anthropic-version"] = "2023-06-01",
      },
      api_key = function()
        return os.getenv("ANTHROPIC_API_KEY")
      end,
      format_request = function(data)
        return {
          model = data.model,
          max_tokens = data.max_tokens or 4096,
          system = data.system,
          messages = {
            {
              role = "user",
              content = data.message,
            },
          },
        }
      end,
      format_response = function(response)
        if response.content and response.content[1] then
          return response.content[1].text
        end
        return nil
      end,
      format_error = function(response)
        if response.error then
          return response.error.message
        end
        return "Unknown error"
      end,
    },
    openai = {
      name = "openai",
      url = "https://api.openai.com/v1/chat/completions",
      model = "gpt-4o",
      headers = {
        ["content-type"] = "application/json",
        ["Authorization"] = "Bearer ${api_key}",
      },
      api_key = function()
        return os.getenv("OPENAI_API_KEY")
      end,
      format_request = function(data)
        return {
          model = data.model,
          max_tokens = data.max_tokens or 4096,
          messages = {
            { role = "system", content = data.system },
            { role = "user", content = data.message },
          },
        }
      end,
      format_response = function(response)
        if response.choices and response.choices[1] then
          return response.choices[1].message.content
        end
        return nil
      end,
      format_error = function(response)
        if response.error then
          return response.error.message
        end
        return "Unknown error"
      end,
    },
    ollama = {
      name = "ollama",
      url = "http://localhost:11434/api/chat",
      model = "llama3.2",
      headers = {
        ["content-type"] = "application/json",
      },
      api_key = function()
        return nil
      end,
      format_request = function(data)
        return {
          model = data.model,
          messages = {
            { role = "system", content = data.system },
            { role = "user", content = data.message },
          },
          stream = false,
        }
      end,
      format_response = function(response)
        if response.message then
          return response.message.content
        end
        return nil
      end,
      format_error = function(response)
        return response.error or "Unknown error"
      end,
    },
  },
}

M.options = vim.deepcopy(M.defaults)

---@param opts? table User configuration
function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)

  -- Handle API key passed directly
  if opts.api_key then
    local provider = M.options.provider
    if M.options.providers[provider] then
      local key = opts.api_key
      M.options.providers[provider].api_key = function()
        if type(key) == "function" then
          return key()
        end
        return key
      end
    end
  end
end

---@return EditutorProvider|nil
function M.get_provider()
  local provider_id = M.options.provider
  return M.options.providers[provider_id]
end

return M
