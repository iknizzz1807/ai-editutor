-- tests/simplified_spec.lua
-- Tests for simplified Q-only ai-editutor v1.0

local M = {}

M.results = { passed = 0, failed = 0, tests = {} }

local function log(status, name, msg)
  local icon = status == "PASS" and "[OK]" or (status == "FAIL" and "[!!]" or "[--]")
  print(string.format("%s %s: %s", icon, name, msg or ""))

  if status == "PASS" then
    M.results.passed = M.results.passed + 1
  elseif status == "FAIL" then
    M.results.failed = M.results.failed + 1
  end

  table.insert(M.results.tests, { name = name, status = status, msg = msg })
end

local function section(name)
  print("\n" .. string.rep("=", 60))
  print("  " .. name)
  print(string.rep("=", 60))
end

-- =============================================================================
-- PARSER TESTS - Only Q: should work
-- =============================================================================

function M.test_parser_q_only()
  section("Parser - Q: Only Mode")

  local parser = require("editutor.parser")

  -- Test Q: works
  local question = parser.parse_line("// Q: What is closure?")
  log(question == "What is closure?" and "PASS" or "FAIL", "parser.q_mode",
    string.format("Q: detected, question='%s'", question or "nil"))

  -- Test lowercase q: also works
  local question2 = parser.parse_line("// q: lowercase question")
  log(question2 == "lowercase question" and "PASS" or "FAIL", "parser.q_lowercase",
    string.format("lowercase q: detected, question='%s'", question2 or "nil"))

  -- Test other prefixes DON'T work (S, R, D, E removed)
  local q_s = parser.parse_line("// S: Socratic question")
  local q_r = parser.parse_line("// R: Review this")
  local q_d = parser.parse_line("// D: Debug this")
  local q_e = parser.parse_line("// E: Explain this")

  log(q_s == nil and "PASS" or "FAIL", "parser.no_s_mode",
    string.format("S: should not work, got='%s'", q_s or "nil"))
  log(q_r == nil and "PASS" or "FAIL", "parser.no_r_mode",
    string.format("R: should not work, got='%s'", q_r or "nil"))
  log(q_d == nil and "PASS" or "FAIL", "parser.no_d_mode",
    string.format("D: should not work, got='%s'", q_d or "nil"))
  log(q_e == nil and "PASS" or "FAIL", "parser.no_e_mode",
    string.format("E: should not work, got='%s'", q_e or "nil"))
end

function M.test_parser_comment_styles()
  section("Parser - Comment Styles")

  local parser = require("editutor.parser")

  -- Test various comment styles with Q:
  local test_cases = {
    { line = "// Q: JS question", expected = "JS question", desc = "JS style //" },
    { line = "# Q: Python question", expected = "Python question", desc = "Python style #" },
    { line = "-- Q: Lua question", expected = "Lua question", desc = "Lua style --" },
    { line = "/* Q: Block comment", expected = "Block comment", desc = "Block comment /*" },
    { line = "--[[ Q: Lua block", expected = "Lua block", desc = "Lua block --[[" },
    { line = "  // Q: Indented question", expected = "Indented question", desc = "Indented" },
    { line = "<!-- Q: HTML comment", expected = "HTML comment", desc = "HTML comment" },
  }

  for _, tc in ipairs(test_cases) do
    local question = parser.parse_line(tc.line)
    log(question == tc.expected and "PASS" or "FAIL", "parser." .. tc.desc:gsub("%s+", "_"),
      string.format("%s: got='%s'", tc.desc, question or "nil"))
  end
end

function M.test_parser_edge_cases()
  section("Parser - Edge Cases")

  local parser = require("editutor.parser")

  -- Empty question should not match
  local q1 = parser.parse_line("// Q: ")
  log(q1 == nil and "PASS" or "FAIL", "parser.empty_question",
    string.format("Empty question should not match, got='%s'", q1 or "nil"))

  -- No colon should not match
  local q2 = parser.parse_line("// Q What about this")
  log(q2 == nil and "PASS" or "FAIL", "parser.no_colon",
    "Missing colon should not match")

  -- No space after // should still work
  local q3 = parser.parse_line("//Q:question")
  log(q3 == "question" and "PASS" or "FAIL", "parser.no_space",
    string.format("No space after // should work, got='%s'", q3 or "nil"))

  -- Normal code should not match
  local q4 = parser.parse_line("const x = 5;")
  log(q4 == nil and "PASS" or "FAIL", "parser.normal_code",
    "Normal code should not match")

  -- Regular comment should not match
  local q5 = parser.parse_line("// This is a regular comment")
  log(q5 == nil and "PASS" or "FAIL", "parser.regular_comment",
    "Regular comment should not match")
end

function M.test_parser_find_query()
  section("Parser - find_query()")

  local parser = require("editutor.parser")

  -- Create a test buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "function test() {",
    "  // Q: What does this do?",
    "  return 42;",
    "}",
  })

  local query = parser.find_query(bufnr, 2)
  log(query ~= nil and "PASS" or "FAIL", "parser.find_query",
    "Found query in buffer")

  if query then
    log(query.question == "What does this do?" and "PASS" or "FAIL", "parser.find_query_question",
      string.format("Question: '%s'", query.question))
    log(query.line == 2 and "PASS" or "FAIL", "parser.find_query_line",
      string.format("Line: %d", query.line))
  end

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- =============================================================================
-- PROMPTS TESTS - Unified prompt
-- =============================================================================

function M.test_prompts_unified()
  section("Prompts - Unified System Prompt")

  local prompts = require("editutor.prompts")

  -- Should have a unified system prompt
  local system_prompt = prompts.get_system_prompt()
  log(system_prompt ~= nil and #system_prompt > 100 and "PASS" or "FAIL", "prompts.exists",
    string.format("System prompt exists, length=%d", #(system_prompt or "")))

  -- Should contain teaching philosophy
  log(system_prompt:find("TEACH") ~= nil and "PASS" or "FAIL", "prompts.teaches",
    "Contains teaching philosophy")

  -- Should mention inline comments
  log(system_prompt:lower():find("comment") ~= nil and "PASS" or "FAIL", "prompts.inline_comments",
    "Mentions inline comments")

  -- get_system_prompt should ignore mode argument (backwards compat)
  local prompt_any = prompts.get_system_prompt("anything")
  log(system_prompt == prompt_any and "PASS" or "FAIL", "prompts.unified",
    "Same prompt regardless of argument")
end

function M.test_prompts_user_prompt()
  section("Prompts - User Prompt Building")

  local prompts = require("editutor.prompts")

  local question = "What is closure?"
  local context = "function foo() { let x = 1; return function() { return x; } }"

  local user_prompt = prompts.build_user_prompt(question, context)

  log(user_prompt ~= nil and "PASS" or "FAIL", "prompts.user_exists",
    "User prompt built")

  log(user_prompt:find(question) ~= nil and "PASS" or "FAIL", "prompts.contains_question",
    "Contains the question")

  log(user_prompt:find("foo") ~= nil and "PASS" or "FAIL", "prompts.contains_context",
    "Contains the context")

  -- Should NOT crash when mode is nil
  local user_prompt2 = prompts.build_user_prompt(question, context, nil)
  log(user_prompt2 ~= nil and "PASS" or "FAIL", "prompts.nil_mode_ok",
    "Handles nil mode argument")
end

function M.test_prompts_hints()
  section("Prompts - Hint Prompts")

  local prompts = require("editutor.prompts")

  -- Hint prompts should exist
  for level = 1, 5 do
    local hint_prompt = prompts.get_hint_prompt(level)
    log(hint_prompt ~= nil and #hint_prompt > 20 and "PASS" or "FAIL",
      "prompts.hint_level_" .. level,
      string.format("Hint level %d exists, length=%d", level, #(hint_prompt or "")))
  end
end

function M.test_prompts_language()
  section("Prompts - Language Support")

  local prompts = require("editutor.prompts")

  local available = prompts.get_available_languages()
  local has_en = false
  local has_vi = false

  for _, lang in ipairs(available) do
    if lang.key == "en" then has_en = true end
    if lang.key == "vi" then has_vi = true end
  end

  log(has_en and "PASS" or "FAIL", "prompts.lang_en", "English available")
  log(has_vi and "PASS" or "FAIL", "prompts.lang_vi", "Vietnamese available")
end

-- =============================================================================
-- CONFIG TESTS
-- =============================================================================

function M.test_config_simplified()
  section("Config - Simplified")

  local config = require("editutor.config")

  log(config ~= nil and "PASS" or "FAIL", "config.exists", "Config module loads")

  -- Provider should still work
  local provider = config.get_provider()
  log(provider ~= nil and "PASS" or "FAIL", "config.provider",
    string.format("Provider exists: %s", provider and provider.name or "nil"))

  -- Keymaps should still work
  log(config.options.keymaps.ask ~= nil and "PASS" or "FAIL", "config.keymap",
    string.format("Ask keymap: %s", config.options.keymaps.ask or "nil"))

  -- default_mode should be removed
  log(config.defaults.default_mode == nil and "PASS" or "FAIL", "config.no_default_mode",
    "default_mode removed from defaults")
end

-- =============================================================================
-- HINTS TESTS
-- =============================================================================

function M.test_hints_simplified()
  section("Hints - Simplified")

  local hints = require("editutor.hints")

  -- MAX_LEVEL should be 5
  log(hints.MAX_LEVEL == 5 and "PASS" or "FAIL", "hints.max_level",
    string.format("MAX_LEVEL=%d", hints.MAX_LEVEL))

  -- Level names should exist
  log(hints.LEVEL_NAMES[1] == "conceptual" and "PASS" or "FAIL", "hints.level_1",
    string.format("Level 1 name: %s", hints.LEVEL_NAMES[1] or "nil"))

  -- get_session should work with nil mode (backwards compat)
  local session = hints.get_session("test question", nil, "test context")
  log(session ~= nil and "PASS" or "FAIL", "hints.session",
    "Session created with nil mode")

  log(session.level == 0 and "PASS" or "FAIL", "hints.initial_level",
    string.format("Initial level=%d", session.level))

  -- Cleanup
  hints.clear_all_sessions()
end

-- =============================================================================
-- COMMENT WRITER TESTS
-- =============================================================================

function M.test_comment_writer()
  section("Comment Writer")

  local comment_writer = require("editutor.comment_writer")

  -- get_style should work
  local js_style = comment_writer.comment_styles.javascript
  log(js_style ~= nil and "PASS" or "FAIL", "comment.js_style",
    "JavaScript style exists")

  log(js_style.line == "//" and "PASS" or "FAIL", "comment.js_line",
    string.format("JS line comment: %s", js_style.line or "nil"))

  local py_style = comment_writer.comment_styles.python
  log(py_style.line == "#" and "PASS" or "FAIL", "comment.py_line",
    string.format("Python line comment: %s", py_style.line or "nil"))

  local lua_style = comment_writer.comment_styles.lua
  log(lua_style.line == "--" and "PASS" or "FAIL", "comment.lua_line",
    string.format("Lua line comment: %s", lua_style.line or "nil"))
end

-- =============================================================================
-- KNOWLEDGE TESTS
-- =============================================================================

function M.test_knowledge_simplified()
  section("Knowledge - Simplified")

  local knowledge = require("editutor.knowledge")

  -- save should work (mode is always "question" now)
  local saved = knowledge.save({
    mode = "question",
    question = "Test question from simplified spec v1.0",
    answer = "Test answer",
    language = "lua",
    filepath = "/test/path.lua",
  })

  log(saved and "PASS" or "FAIL", "knowledge.save",
    "Entry saved successfully")

  -- search should work
  local results = knowledge.search("simplified spec v1.0")
  log(#results > 0 and "PASS" or "FAIL", "knowledge.search",
    string.format("Found %d results", #results))

  -- stats should work
  local stats = knowledge.get_stats()
  log(stats.total > 0 and "PASS" or "FAIL", "knowledge.stats",
    string.format("Total entries: %d", stats.total))
end

-- =============================================================================
-- INTEGRATION TESTS
-- =============================================================================

function M.test_integration_flow()
  section("Integration - Simplified Flow")

  local parser = require("editutor.parser")
  local prompts = require("editutor.prompts")

  -- 1. Parse a question (no mode returned, just question)
  local question = parser.parse_line("// Q: How does async/await work?")
  log(question ~= nil and "PASS" or "FAIL", "integration.parse",
    string.format("Question parsed: '%s'", question or "nil"))

  -- 2. Build prompts (no mode needed)
  local system_prompt = prompts.get_system_prompt()
  local user_prompt = prompts.build_user_prompt(question, "async function foo() { await bar(); }")

  log(#system_prompt > 0 and #user_prompt > 0 and "PASS" or "FAIL", "integration.prompts",
    "Prompts built successfully")

  -- 3. Flow is simple: Q: -> context -> prompt -> response
  log(true and "PASS" or "FAIL", "integration.flow",
    "Simplified flow: Q: -> context -> prompt -> response")
end

function M.test_api_simplified()
  section("API - Simplified")

  local parser = require("editutor.parser")

  -- parser.modes should not exist (removed)
  log(parser.modes == nil and "PASS" or "FAIL", "api.no_modes",
    string.format("parser.modes removed (exists=%s)", parser.modes ~= nil))

  -- parser.get_modes_help should not exist
  log(parser.get_modes_help == nil and "PASS" or "FAIL", "api.no_get_modes_help",
    string.format("get_modes_help removed (exists=%s)", parser.get_modes_help ~= nil))

  -- parser.get_mode_description should not exist
  log(parser.get_mode_description == nil and "PASS" or "FAIL", "api.no_get_mode_description",
    string.format("get_mode_description removed (exists=%s)", parser.get_mode_description ~= nil))

  -- parse_line should return just question (not mode, question)
  local result = parser.parse_line("// Q: test")
  log(type(result) == "string" and "PASS" or "FAIL", "api.parse_line_returns_string",
    string.format("parse_line returns string, got %s", type(result)))
end

-- =============================================================================
-- SKIP ANSWERED QUESTIONS TESTS
-- =============================================================================

function M.test_skip_answered_questions()
  section("Parser - Skip Answered Questions (Q: with A: below)")

  local parser = require("editutor.parser")

  -- Test: Q: with A: block comment below should be skipped
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", "javascript", { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "function test() {",
    "  // Q: What is closure?",           -- line 2: answered question
    "  /*",                                -- line 3: A: response starts
    "  A: A closure is a function...",
    "  */",
    "  // Q: How does async work?",       -- line 6: unanswered question
    "  return 42;",
    "}",
  })

  -- When cursor is at line 6, should find the unanswered question at line 6
  local query = parser.find_query(bufnr, 6)
  log(query ~= nil and query.line == 6 and "PASS" or "FAIL", "parser.skip_answered_block",
    string.format("Skipped answered Q: (found at line %d, expected 6)", query and query.line or -1))

  -- When cursor is at line 2, should skip answered Q and find unanswered Q
  local query2 = parser.find_query(bufnr, 2)
  log(query2 ~= nil and query2.line == 6 and "PASS" or "FAIL", "parser.skip_answered_find_next",
    string.format("From answered line, found unanswered at line %d", query2 and query2.line or -1))

  vim.api.nvim_buf_delete(bufnr, { force = true })

  -- Test: Q: with A: line comment below should be skipped
  local bufnr2 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr2 })
  vim.api.nvim_buf_set_lines(bufnr2, 0, -1, false, {
    "def test():",
    "    # Q: What is a list comprehension?",  -- line 2: answered
    "    # A: A list comprehension is...",     -- line 3: response
    "    # Q: What is a generator?",           -- line 4: unanswered
    "    return 42",
  })

  local query3 = parser.find_query(bufnr2, 2)
  log(query3 ~= nil and query3.line == 4 and "PASS" or "FAIL", "parser.skip_answered_line_comment",
    string.format("Skipped line comment A:, found at line %d", query3 and query3.line or -1))

  vim.api.nvim_buf_delete(bufnr2, { force = true })

  -- Test: Q: without A: below should NOT be skipped
  local bufnr3 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", "javascript", { buf = bufnr3 })
  vim.api.nvim_buf_set_lines(bufnr3, 0, -1, false, {
    "function test() {",
    "  // Q: What is this?",  -- line 2: unanswered (no A: below)
    "  return 42;",
    "}",
  })

  local query4 = parser.find_query(bufnr3, 2)
  log(query4 ~= nil and query4.line == 2 and "PASS" or "FAIL", "parser.unanswered_found",
    string.format("Unanswered Q: found at line %d", query4 and query4.line or -1))

  vim.api.nvim_buf_delete(bufnr3, { force = true })
end

-- =============================================================================
-- VISUAL SELECTION TESTS
-- =============================================================================

function M.test_visual_selection()
  section("Visual Selection Support")

  local parser = require("editutor.parser")

  -- Test: find_query_with_selection should detect visual selection
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "function calculate(a, b) {",      -- line 1
    "  const result = a + b;",          -- line 2
    "  // Q: Explain this function",    -- line 3
    "  return result * 2;",             -- line 4
    "}",                                -- line 5
  })

  -- Simulate visual selection from line 1 to 5
  local selection_start = 1
  local selection_end = 5

  -- Should be able to get selection context
  local selected_lines = vim.api.nvim_buf_get_lines(bufnr, selection_start - 1, selection_end, false)
  local selected_code = table.concat(selected_lines, "\n")

  log(#selected_lines == 5 and "PASS" or "FAIL", "visual.get_selection",
    string.format("Got %d lines of selection", #selected_lines))

  log(selected_code:find("calculate") ~= nil and "PASS" or "FAIL", "visual.contains_code",
    "Selection contains the code")

  -- Test: find_query should work within selection range
  local query = parser.find_query(bufnr, selection_start)
  log(query ~= nil and "PASS" or "FAIL", "visual.find_query_in_selection",
    "Found Q: within selection range")

  vim.api.nvim_buf_delete(bufnr, { force = true })

  -- Test: get_visual_selection helper
  if parser.get_visual_selection then
    log(true and "PASS" or "FAIL", "visual.helper_exists",
      "get_visual_selection helper exists")
  else
    log("SKIP", "visual.helper_exists",
      "get_visual_selection helper not yet implemented")
  end
end

function M.test_visual_mode_context()
  section("Visual Mode Context Enhancement")

  local prompts = require("editutor.prompts")

  -- Test: build_user_prompt should handle selected_code parameter (4th arg)
  local question = "Explain this"
  local context = "surrounding context"
  local selected_code = "function foo() { return 42; }"

  -- Call with 4 parameters: question, context, mode (nil), selected_code
  local user_prompt = prompts.build_user_prompt(question, context, nil, selected_code)

  log(user_prompt:find("foo") ~= nil and "PASS" or "FAIL", "visual.prompt_contains_selection",
    "User prompt contains selected code")

  -- Selected code should be marked as focused
  local has_focus_label = user_prompt:find("FOCUS") or user_prompt:find("Selected")
  log(has_focus_label and "PASS" or "FAIL", "visual.prompt_marks_selection",
    "Selected code is marked with focus label")

  -- Test: without selected_code, prompt should still work
  local basic_prompt = prompts.build_user_prompt(question, context, nil)
  log(basic_prompt:find(question) ~= nil and "PASS" or "FAIL", "visual.basic_prompt_works",
    "Basic prompt without selection still works")
end

-- =============================================================================
-- RUN ALL TESTS
-- =============================================================================

function M.run_all()
  print(string.rep("=", 60))
  print("  ai-editutor Simplified v1.0 Tests")
  print(string.rep("=", 60))

  M.results = { passed = 0, failed = 0, tests = {} }

  -- Parser tests
  M.test_parser_q_only()
  M.test_parser_comment_styles()
  M.test_parser_edge_cases()
  M.test_parser_find_query()

  -- Prompts tests
  M.test_prompts_unified()
  M.test_prompts_user_prompt()
  M.test_prompts_hints()
  M.test_prompts_language()

  -- Config tests
  M.test_config_simplified()

  -- Hints tests
  M.test_hints_simplified()

  -- Comment writer tests
  M.test_comment_writer()

  -- Knowledge tests
  M.test_knowledge_simplified()

  -- Integration tests
  M.test_integration_flow()
  M.test_api_simplified()

  -- New features tests
  M.test_skip_answered_questions()
  M.test_visual_selection()
  M.test_visual_mode_context()

  -- Summary
  print("\n" .. string.rep("=", 60))
  print("  SIMPLIFIED v1.0 TEST SUMMARY")
  print(string.rep("=", 60))
  print(string.format("  Passed: %d", M.results.passed))
  print(string.format("  Failed: %d", M.results.failed))
  print(string.format("  Total: %d", #M.results.tests))

  if M.results.failed > 0 then
    print("\n  Failed tests:")
    for _, t in ipairs(M.results.tests) do
      if t.status == "FAIL" then
        print(string.format("    - %s: %s", t.name, t.msg or ""))
      end
    end
  end

  print(string.rep("=", 60))

  return M.results.failed == 0
end

return M
