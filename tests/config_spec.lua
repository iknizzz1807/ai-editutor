-- tests/config_spec.lua
-- Unit tests for configuration module

local config = require("editutor.config")

describe("config", function()
  -- Reset config before each test
  before_each(function()
    config.options = vim.deepcopy(config.defaults)
  end)

  describe("defaults", function()
    it("should have default provider as claude", function()
      assert.equals("claude", config.defaults.provider)
    end)

    it("should have default mode as question", function()
      assert.equals("question", config.defaults.default_mode)
    end)

    it("should have default language as English", function()
      assert.equals("English", config.defaults.language)
    end)

    it("should have context configuration", function()
      assert.is_not_nil(config.defaults.context)
      assert.equals(100, config.defaults.context.lines_around_cursor)
      assert.equals(30, config.defaults.context.external_context_lines)
      assert.equals(20, config.defaults.context.max_external_symbols)
    end)

    it("should have keymaps configuration", function()
      assert.is_not_nil(config.defaults.keymaps)
      assert.equals("<leader>ma", config.defaults.keymaps.ask)
    end)
  end)

  describe("setup", function()
    it("should merge user options with defaults", function()
      config.setup({
        provider = "openai",
        language = "Vietnamese",
      })

      assert.equals("openai", config.options.provider)
      assert.equals("Vietnamese", config.options.language)
      -- Defaults should remain
      assert.equals("question", config.options.default_mode)
    end)

    it("should deep merge nested options", function()
      config.setup({
        context = {
          lines_around_cursor = 200,
        },
      })

      assert.equals(200, config.options.context.lines_around_cursor)
      -- Other context options should remain default
      assert.equals(30, config.options.context.external_context_lines)
      assert.equals(20, config.options.context.max_external_symbols)
    end)

    it("should handle empty options", function()
      config.setup({})
      assert.equals("claude", config.options.provider)
    end)

    it("should handle nil options", function()
      config.setup(nil)
      assert.equals("claude", config.options.provider)
    end)

    it("should handle custom API key", function()
      config.setup({
        provider = "claude",
        api_key = "test-key-123",
      })

      local provider = config.get_provider()
      assert.is_not_nil(provider)
      assert.equals("test-key-123", provider.api_key())
    end)

    it("should handle API key as function", function()
      local key_func = function()
        return "dynamic-key"
      end

      config.setup({
        provider = "claude",
        api_key = key_func,
      })

      local provider = config.get_provider()
      assert.equals("dynamic-key", provider.api_key())
    end)
  end)

  describe("get_provider", function()
    it("should return claude provider by default", function()
      config.setup({})
      local provider = config.get_provider()

      assert.is_not_nil(provider)
      assert.equals("claude", provider.name)
      assert.equals("https://api.anthropic.com/v1/messages", provider.url)
    end)

    it("should return openai provider when configured", function()
      config.setup({ provider = "openai" })
      local provider = config.get_provider()

      assert.is_not_nil(provider)
      assert.equals("openai", provider.name)
      assert.equals("https://api.openai.com/v1/chat/completions", provider.url)
    end)

    it("should return ollama provider when configured", function()
      config.setup({ provider = "ollama" })
      local provider = config.get_provider()

      assert.is_not_nil(provider)
      assert.equals("ollama", provider.name)
      assert.equals("http://localhost:11434/api/chat", provider.url)
    end)

    it("should return nil for unknown provider", function()
      config.setup({ provider = "unknown" })
      local provider = config.get_provider()

      assert.is_nil(provider)
    end)
  end)

  describe("provider format functions", function()
    it("claude should format request correctly", function()
      config.setup({ provider = "claude" })
      local provider = config.get_provider()

      local request = provider.format_request({
        model = "claude-sonnet-4-20250514",
        system = "You are a mentor",
        message = "What is recursion?",
        max_tokens = 2048,
      })

      assert.equals("claude-sonnet-4-20250514", request.model)
      assert.equals(2048, request.max_tokens)
      assert.equals("You are a mentor", request.system)
      assert.equals(1, #request.messages)
      assert.equals("user", request.messages[1].role)
      assert.equals("What is recursion?", request.messages[1].content)
    end)

    it("claude should parse response correctly", function()
      config.setup({ provider = "claude" })
      local provider = config.get_provider()

      local response = provider.format_response({
        content = {
          { text = "Recursion is when a function calls itself." },
        },
      })

      assert.equals("Recursion is when a function calls itself.", response)
    end)

    it("openai should format request correctly", function()
      config.setup({ provider = "openai" })
      local provider = config.get_provider()

      local request = provider.format_request({
        model = "gpt-4o",
        system = "You are a mentor",
        message = "What is recursion?",
      })

      assert.equals("gpt-4o", request.model)
      assert.equals(2, #request.messages)
      assert.equals("system", request.messages[1].role)
      assert.equals("user", request.messages[2].role)
    end)

    it("openai should parse response correctly", function()
      config.setup({ provider = "openai" })
      local provider = config.get_provider()

      local response = provider.format_response({
        choices = {
          { message = { content = "Test response" } },
        },
      })

      assert.equals("Test response", response)
    end)
  end)
end)
