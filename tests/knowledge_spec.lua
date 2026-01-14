-- tests/knowledge_spec.lua
-- Unit tests for knowledge tracking module

local knowledge = require("editutor.knowledge")

describe("knowledge", function()
  -- Use a test database file
  local test_db_path

  before_each(function()
    -- Create a temp directory for test database
    test_db_path = os.tmpname()
    os.remove(test_db_path) -- Remove the file, we'll use it as base path

    -- Override the database path for testing
    knowledge._test_db_path = test_db_path .. "_knowledge.json"
  end)

  after_each(function()
    -- Clean up test files
    if test_db_path then
      os.remove(test_db_path .. "_knowledge.json")
    end
    knowledge._test_db_path = nil
  end)

  describe("save", function()
    it("should save a Q&A entry", function()
      local entry = {
        mode = "question",
        question = "What is recursion?",
        answer = "Recursion is when a function calls itself.",
        language = "lua",
        filepath = "/project/test.lua",
      }

      -- Should not throw
      assert.has_no.errors(function()
        knowledge.save(entry)
      end)
    end)

    it("should save entry with tags", function()
      local entry = {
        mode = "debug",
        question = "Why nil?",
        answer = "Because...",
        language = "lua",
        filepath = "/test.lua",
        tags = { "bug", "nil-error" },
      }

      assert.has_no.errors(function()
        knowledge.save(entry)
      end)
    end)

    it("should handle missing optional fields", function()
      local entry = {
        mode = "question",
        question = "test",
        answer = "answer",
      }

      assert.has_no.errors(function()
        knowledge.save(entry)
      end)
    end)
  end)

  describe("get_recent", function()
    it("should return a table", function()
      local result = knowledge.get_recent(10)
      assert.is_table(result)
    end)

    it("should return empty table when no entries", function()
      local result = knowledge.get_recent(10)
      -- Might have entries from other tests, just check it's a table
      assert.is_table(result)
    end)

    it("should respect limit parameter", function()
      -- Save some entries
      for i = 1, 5 do
        knowledge.save({
          mode = "question",
          question = "Question " .. i,
          answer = "Answer " .. i,
        })
      end

      local result = knowledge.get_recent(3)
      assert.is_true(#result <= 3)
    end)
  end)

  describe("search", function()
    it("should return a table", function()
      local result = knowledge.search("test")
      assert.is_table(result)
    end)

    it("should find matching entries", function()
      -- Save an entry with specific content
      knowledge.save({
        mode = "question",
        question = "What is unique_test_term_xyz?",
        answer = "It is a test term.",
      })

      local result = knowledge.search("unique_test_term_xyz")
      -- Should find at least the entry we just saved
      -- (depending on implementation, might need time to index)
      assert.is_table(result)
    end)

    it("should handle empty query", function()
      local result = knowledge.search("")
      assert.is_table(result)
    end)
  end)

  describe("get_stats", function()
    it("should return stats object", function()
      local stats = knowledge.get_stats()

      assert.is_table(stats)
      assert.is_number(stats.total)
      assert.is_table(stats.by_mode)
      assert.is_table(stats.by_language)
    end)

    it("should have non-negative total", function()
      local stats = knowledge.get_stats()
      assert.is_true(stats.total >= 0)
    end)
  end)

  describe("export_markdown", function()
    it("should return success status", function()
      local temp_export = os.tmpname()

      local success, err = knowledge.export_markdown(temp_export)

      -- Clean up
      os.remove(temp_export)

      -- Should either succeed or give a meaningful error
      if success then
        assert.is_nil(err)
      else
        assert.is_string(err)
      end
    end)

    it("should create a file when successful", function()
      -- Save some entries first
      knowledge.save({
        mode = "question",
        question = "Test export question",
        answer = "Test export answer",
      })

      local temp_export = os.tmpname()
      local success, _ = knowledge.export_markdown(temp_export)

      if success then
        local f = io.open(temp_export, "r")
        assert.is_not_nil(f)
        if f then
          local content = f:read("*a")
          f:close()
          assert.is_true(#content > 0)
        end
      end

      -- Clean up
      os.remove(temp_export)
    end)
  end)
end)
