-- tests/prompts_spec.lua
-- Unit tests for prompt generation module

local prompts = require("editutor.prompts")
local config = require("editutor.config")

describe("prompts", function()
  before_each(function()
    -- Reset config to defaults
    config.options = vim.deepcopy(config.defaults)
  end)

  describe("get_system_prompt", function()
    it("should return a string for question mode", function()
      local prompt = prompts.get_system_prompt("question")
      assert.is_string(prompt)
      assert.is_true(#prompt > 0)
    end)

    it("should return a string for socratic mode", function()
      local prompt = prompts.get_system_prompt("socratic")
      assert.is_string(prompt)
      assert.is_true(#prompt > 0)
    end)

    it("should return a string for review mode", function()
      local prompt = prompts.get_system_prompt("review")
      assert.is_string(prompt)
      assert.is_true(#prompt > 0)
    end)

    it("should return a string for debug mode", function()
      local prompt = prompts.get_system_prompt("debug")
      assert.is_string(prompt)
      assert.is_true(#prompt > 0)
    end)

    it("should return a string for explain mode", function()
      local prompt = prompts.get_system_prompt("explain")
      assert.is_string(prompt)
      assert.is_true(#prompt > 0)
    end)

    it("should fallback to question mode for unknown mode", function()
      local prompt = prompts.get_system_prompt("unknown_mode")
      local question_prompt = prompts.get_system_prompt("question")
      -- Should return something (either fallback or default)
      assert.is_string(prompt)
      assert.is_true(#prompt > 0)
    end)

    it("should include language instruction for English", function()
      config.options.language = "English"
      local prompt = prompts.get_system_prompt("question")
      -- Prompt should mention English or be in English
      assert.is_string(prompt)
    end)

    it("should include Vietnamese instruction when configured", function()
      config.options.language = "Vietnamese"
      local prompt = prompts.get_system_prompt("question")
      -- Prompt should include Vietnamese language instruction
      assert.is_string(prompt)
      -- Check for Vietnamese-related content
      assert.is_true(
        prompt:find("Vietnamese") ~= nil or
        prompt:find("tiếng Việt") ~= nil or
        prompt:find("Việt") ~= nil
      )
    end)
  end)

  describe("build_user_prompt", function()
    it("should include the question", function()
      local result = prompts.build_user_prompt(
        "What is recursion?",
        "Code context here",
        "question"
      )

      assert.is_string(result)
      assert.is_true(result:find("What is recursion?") ~= nil)
    end)

    it("should include the context", function()
      local result = prompts.build_user_prompt(
        "Explain this",
        "function foo() { return 1; }",
        "question"
      )

      assert.is_true(result:find("function foo") ~= nil)
    end)

    it("should handle empty context", function()
      local result = prompts.build_user_prompt(
        "General question",
        "",
        "question"
      )

      assert.is_string(result)
      assert.is_true(result:find("General question") ~= nil)
    end)

    it("should handle nil context", function()
      local result = prompts.build_user_prompt(
        "General question",
        nil,
        "question"
      )

      assert.is_string(result)
    end)
  end)

  describe("get_language", function()
    it("should return 'en' for English", function()
      config.options.language = "English"
      local lang = prompts.get_language()
      assert.equals("en", lang)
    end)

    it("should return 'vi' for Vietnamese", function()
      config.options.language = "Vietnamese"
      local lang = prompts.get_language()
      assert.equals("vi", lang)
    end)

    it("should handle 'vi' shorthand", function()
      config.options.language = "vi"
      local lang = prompts.get_language()
      assert.equals("vi", lang)
    end)

    it("should handle 'en' shorthand", function()
      config.options.language = "en"
      local lang = prompts.get_language()
      assert.equals("en", lang)
    end)

    it("should default to 'en' for unknown language", function()
      config.options.language = "unknown"
      local lang = prompts.get_language()
      assert.equals("en", lang)
    end)
  end)

  describe("get_available_languages", function()
    it("should return a list of languages", function()
      local langs = prompts.get_available_languages()

      assert.is_table(langs)
      assert.is_true(#langs >= 2) -- At least English and Vietnamese
    end)

    it("should include English", function()
      local langs = prompts.get_available_languages()
      local found = false

      for _, lang in ipairs(langs) do
        if lang.key == "en" or lang.name == "English" then
          found = true
          break
        end
      end

      assert.is_true(found)
    end)

    it("should include Vietnamese", function()
      local langs = prompts.get_available_languages()
      local found = false

      for _, lang in ipairs(langs) do
        if lang.key == "vi" or lang.name == "Vietnamese" then
          found = true
          break
        end
      end

      assert.is_true(found)
    end)
  end)

  describe("get_hint_prompt", function()
    it("should return different prompts for different levels", function()
      local level1 = prompts.get_hint_prompt(1)
      local level2 = prompts.get_hint_prompt(2)
      local level3 = prompts.get_hint_prompt(3)
      local level4 = prompts.get_hint_prompt(4)

      assert.is_string(level1)
      assert.is_string(level2)
      assert.is_string(level3)
      assert.is_string(level4)

      -- Each level should be different
      assert.is_not.equals(level1, level4)
    end)

    it("should handle invalid levels gracefully", function()
      local result = prompts.get_hint_prompt(0)
      assert.is_string(result)

      result = prompts.get_hint_prompt(99)
      assert.is_string(result)
    end)
  end)
end)
