-- codementor/config.lua
-- Configuration management for AI Code Mentor

local M = {}

---@class CodementorConfig
---@field provider string LLM provider ("claude" | "openai" | "ollama")
---@field api_key string|function API key or function returning key
---@field model string Model identifier
---@field default_mode string Default interaction mode
---@field context_lines number Lines of context around question
---@field include_imports boolean Include file imports in context
---@field language string Language for explanations
---@field ui CodementorUIConfig UI configuration
---@field keymaps CodementorKeymaps Keymap configuration
---@field providers table<string, CodementorProvider> Provider configurations

---@class CodementorUIConfig
---@field width number|string Window width
---@field height number|string Window height
---@field border string Border style
---@field max_width number Maximum window width

---@class CodementorKeymaps
---@field ask string Trigger mentor ask
---@field close string Close popup
---@field copy string Copy answer
---@field next_hint string Get next hint level

---@class CodementorProvider
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

  -- Behavior
  default_mode = "question",
  context_lines = 50,
  include_imports = true,
  language = "English",

  -- UI
  ui = {
    width = 80,
    height = 20,
    border = "rounded",
    max_width = 120,
  },

  -- Keymaps
  keymaps = {
    ask = "<leader>ma",
    close = "q",
    copy = "y",
    next_hint = "n",
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

---@return CodementorProvider|nil
function M.get_provider()
  local provider_id = M.options.provider
  return M.options.providers[provider_id]
end

return M
