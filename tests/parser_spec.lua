-- tests/parser_spec.lua
-- Unit tests for comment parser

local parser = require("editutor.parser")

describe("parser", function()
  describe("parse_line", function()
    it("should parse Q: prefix", function()
      local mode, question = parser.parse_line("// Q: What is recursion?")
      assert.equals("Q", mode)
      assert.equals("What is recursion?", question)
    end)

    it("should parse S: prefix (Socratic)", function()
      local mode, question = parser.parse_line("// S: Why might this be slow?")
      assert.equals("S", mode)
      assert.equals("Why might this be slow?", question)
    end)

    it("should parse R: prefix (Review)", function()
      local mode, question = parser.parse_line("// R: Review this function")
      assert.equals("R", mode)
      assert.equals("Review this function", question)
    end)

    it("should parse D: prefix (Debug)", function()
      local mode, question = parser.parse_line("// D: Why does this return nil?")
      assert.equals("D", mode)
      assert.equals("Why does this return nil?", question)
    end)

    it("should parse E: prefix (Explain)", function()
      local mode, question = parser.parse_line("// E: Explain closures")
      assert.equals("E", mode)
      assert.equals("Explain closures", question)
    end)

    it("should handle # comment style", function()
      local mode, question = parser.parse_line("# Q: What does this do?")
      assert.equals("Q", mode)
      assert.equals("What does this do?", question)
    end)

    it("should handle -- comment style (Lua)", function()
      local mode, question = parser.parse_line("-- Q: Explain metatables")
      assert.equals("Q", mode)
      assert.equals("Explain metatables", question)
    end)

    it("should handle ; comment style (Lisp/ASM)", function()
      local mode, question = parser.parse_line("; Q: What is this macro?")
      assert.equals("Q", mode)
      assert.equals("What is this macro?", question)
    end)

    it("should handle /* block comment style", function()
      local mode, question = parser.parse_line("/* Q: What is this? */")
      assert.equals("Q", mode)
      assert.is_not_nil(question)
    end)

    it("should return nil for non-mentor comments", function()
      local mode, question = parser.parse_line("// This is a regular comment")
      assert.is_nil(mode)
      assert.is_nil(question)
    end)

    it("should return nil for empty strings", function()
      local mode, question = parser.parse_line("")
      assert.is_nil(mode)
      assert.is_nil(question)
    end)

    it("should handle TODO comments (not mentor)", function()
      local mode, question = parser.parse_line("// TODO: fix this later")
      assert.is_nil(mode)
    end)

    it("should handle leading whitespace", function()
      local mode, question = parser.parse_line("    // Q: indented question")
      assert.equals("Q", mode)
      assert.equals("indented question", question)
    end)
  end)

  describe("modes", function()
    it("should have all 5 modes defined", function()
      assert.is_not_nil(parser.modes.Q)
      assert.is_not_nil(parser.modes.S)
      assert.is_not_nil(parser.modes.R)
      assert.is_not_nil(parser.modes.D)
      assert.is_not_nil(parser.modes.E)
    end)

    it("should have correct mode names", function()
      assert.equals("question", parser.modes.Q.name)
      assert.equals("socratic", parser.modes.S.name)
      assert.equals("review", parser.modes.R.name)
      assert.equals("debug", parser.modes.D.name)
      assert.equals("explain", parser.modes.E.name)
    end)

    it("should have descriptions for all modes", function()
      for mode_char, mode_info in pairs(parser.modes) do
        assert.is_string(mode_info.description)
        assert.is_true(#mode_info.description > 0)
      end
    end)
  end)

  describe("get_mode_description", function()
    it("should return description for valid mode", function()
      local desc = parser.get_mode_description("Q")
      assert.is_string(desc)
      assert.is_true(desc:find("question") ~= nil or desc:find("answer") ~= nil)
    end)

    it("should return 'Unknown mode' for invalid mode", function()
      local desc = parser.get_mode_description("X")
      assert.equals("Unknown mode", desc)
    end)
  end)

  describe("get_modes_help", function()
    it("should return a string", function()
      local help = parser.get_modes_help()
      assert.is_string(help)
      assert.is_true(#help > 0)
    end)

    it("should include all mode characters", function()
      local help = parser.get_modes_help()
      assert.is_true(help:find("// Q:") ~= nil)
      assert.is_true(help:find("// S:") ~= nil)
      assert.is_true(help:find("// R:") ~= nil)
      assert.is_true(help:find("// D:") ~= nil)
      assert.is_true(help:find("// E:") ~= nil)
    end)
  end)

  describe("find_query (integration)", function()
    -- These tests need a buffer context, skip if not available
    local test_buf

    before_each(function()
      -- Create a scratch buffer for testing
      test_buf = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if test_buf and vim.api.nvim_buf_is_valid(test_buf) then
        vim.api.nvim_buf_delete(test_buf, { force = true })
      end
    end)

    it("should find query at specified line", function()
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "local x = 1",
        "// Q: What is this variable for?",
        "local y = 2",
      })

      local query = parser.find_query(test_buf, 2)

      assert.is_not_nil(query)
      assert.equals("Q", query.mode)
      assert.equals("question", query.mode_name)
      assert.equals("What is this variable for?", query.question)
      assert.equals(2, query.line)
    end)

    it("should search nearby lines", function()
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "// Q: Found me!",
        "local x = 1",
        "local y = 2",
      })

      -- Start from line 2, should find query at line 1
      local query = parser.find_query(test_buf, 2)

      assert.is_not_nil(query)
      assert.equals("Found me!", query.question)
    end)

    it("should return nil when no query found", function()
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "local x = 1",
        "local y = 2",
        "-- regular comment",
      })

      local query = parser.find_query(test_buf, 2)
      assert.is_nil(query)
    end)
  end)

  describe("find_all_queries", function()
    local test_buf

    before_each(function()
      test_buf = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if test_buf and vim.api.nvim_buf_is_valid(test_buf) then
        vim.api.nvim_buf_delete(test_buf, { force = true })
      end
    end)

    it("should find all queries in buffer", function()
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "// Q: First question",
        "local x = 1",
        "// S: Second query",
        "local y = 2",
        "// R: Third review",
      })

      local queries = parser.find_all_queries(test_buf)

      assert.equals(3, #queries)
      assert.equals("Q", queries[1].mode)
      assert.equals("S", queries[2].mode)
      assert.equals("R", queries[3].mode)
    end)

    it("should return empty table for no queries", function()
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "local x = 1",
        "-- regular comment",
      })

      local queries = parser.find_all_queries(test_buf)
      assert.equals(0, #queries)
    end)
  end)
end)
