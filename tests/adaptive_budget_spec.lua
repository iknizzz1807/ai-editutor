-- tests/adaptive_budget_spec.lua
-- Tests for adaptive budget allocation and type-based context

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
-- Query Classification Tests
-- =============================================================================

function M.test_query_classification()
  section("Query Classification")

  local ranker = require("editutor.indexer.ranker")

  -- Test specific function query
  local query1 = "What does the validate_user function do?"
  local context1, meta1 = ranker.build_context(query1, { budget = 1000 })
  log(meta1.query_type == "specific_function" and "PASS" or "FAIL", "classify.specific_function",
    string.format("Query '%s' classified as '%s'", query1:sub(1, 30), meta1.query_type))

  -- Test debugging query
  local query2 = "Why is this error happening? The bug crashes the app"
  local context2, meta2 = ranker.build_context(query2, { budget = 1000 })
  log(meta2.query_type == "debugging" and "PASS" or "FAIL", "classify.debugging",
    string.format("Query '%s' classified as '%s'", query2:sub(1, 30), meta2.query_type))

  -- Test architecture query
  local query3 = "How does the authentication system architecture work?"
  local context3, meta3 = ranker.build_context(query3, { budget = 1000 })
  log(meta3.query_type == "architecture" and "PASS" or "FAIL", "classify.architecture",
    string.format("Query '%s' classified as '%s'", query3:sub(1, 30), meta3.query_type))

  -- Test type-related query
  local query4 = "What is the UserConfig type definition?"
  local context4, meta4 = ranker.build_context(query4, { budget = 1000 })
  log(meta4.query_type == "type_related" and "PASS" or "FAIL", "classify.type_related",
    string.format("Query '%s' classified as '%s'", query4:sub(1, 30), meta4.query_type))

  -- Test general query
  local query5 = "Hello world"
  local context5, meta5 = ranker.build_context(query5, { budget = 1000 })
  log(meta5.query_type == "general" and "PASS" or "FAIL", "classify.general",
    string.format("Query '%s' classified as '%s'", query5:sub(1, 30), meta5.query_type))
end

-- =============================================================================
-- Adaptive Budget Allocation Tests
-- =============================================================================

function M.test_adaptive_budget()
  section("Adaptive Budget Allocation")

  local ranker = require("editutor.indexer.ranker")

  -- Test budget allocation exists
  local _, meta1 = ranker.build_context("test query", { budget = 1000 })
  log(meta1.budget_allocation ~= nil and "PASS" or "FAIL", "budget.exists",
    "Budget allocation returned in metadata")

  -- Test budget allocation has expected keys
  local expected_keys = { "current_file", "lsp_definitions", "bm25_results", "call_graph", "type_definitions" }
  local all_keys_exist = true
  for _, key in ipairs(expected_keys) do
    if not meta1.budget_allocation[key] then
      all_keys_exist = false
      break
    end
  end
  log(all_keys_exist and "PASS" or "FAIL", "budget.keys",
    "Budget allocation has all expected keys")

  -- Test budget sums to approximately 1.0
  local total = 0
  for _, v in pairs(meta1.budget_allocation) do
    total = total + v
  end
  log(math.abs(total - 1.0) < 0.01 and "PASS" or "FAIL", "budget.sum",
    string.format("Budget sums to %.4f (should be 1.0)", total))

  -- Test debugging query gets more current_file budget
  local _, meta_debug = ranker.build_context("Why is this error happening?", { budget = 1000 })
  local _, meta_general = ranker.build_context("hello", { budget = 1000 })

  if meta_debug.budget_allocation and meta_general.budget_allocation then
    local debug_current = meta_debug.budget_allocation.current_file or 0
    local general_current = meta_general.budget_allocation.current_file or 0
    log(debug_current > general_current and "PASS" or "FAIL", "budget.debug_boost",
      string.format("Debugging gets more current_file budget (%.2f vs %.2f)", debug_current, general_current))
  else
    log("FAIL", "budget.debug_boost", "Budget allocation missing")
  end

  -- Test type query gets more type_definitions budget
  local _, meta_type = ranker.build_context("What is the User type definition?", { budget = 1000 })
  if meta_type.budget_allocation and meta_general.budget_allocation then
    local type_budget = meta_type.budget_allocation.type_definitions or 0
    local general_type = meta_general.budget_allocation.type_definitions or 0
    log(type_budget > general_type and "PASS" or "FAIL", "budget.type_boost",
      string.format("Type query gets more type_definitions budget (%.2f vs %.2f)", type_budget, general_type))
  else
    log("FAIL", "budget.type_boost", "Budget allocation missing")
  end
end

-- =============================================================================
-- Type Context Extraction Tests
-- =============================================================================

function M.test_type_context_patterns()
  section("Type Context Pattern Extraction")

  -- Test type patterns directly
  local test_content = [[
function processUser(user: UserConfig): Promise<UserResult> {
  const settings: AppSettings = getSettings();
  const data = new DataService();
  return data.process<UserResult>(user);
}

impl UserService for MyService {
  fn get_user(&self, id: i32) -> Option<User> {
    self.db.query::<User>(id)
  }
}
]]

  -- Check that common type patterns are recognized
  local type_patterns = {
    ":%s*([A-Z][%w_]+)",      -- : TypeName
    "<%s*([A-Z][%w_]+)",      -- <TypeName>
    "impl%s+([A-Z][%w_]+)",   -- impl TypeName
  }

  local found_types = {}
  for _, pattern in ipairs(type_patterns) do
    for type_name in test_content:gmatch(pattern) do
      found_types[type_name] = true
    end
  end

  log(found_types["UserConfig"] and "PASS" or "FAIL", "type.pattern_colon",
    "Detected UserConfig from : TypeName pattern")
  log(found_types["UserResult"] and "PASS" or "FAIL", "type.pattern_generic",
    "Detected UserResult from <TypeName> pattern")
  log(found_types["UserService"] and "PASS" or "FAIL", "type.pattern_impl",
    "Detected UserService from impl TypeName pattern")
end

-- =============================================================================
-- Integration Test
-- =============================================================================

function M.test_build_context_integration()
  section("Build Context Integration")

  local ranker = require("editutor.indexer.ranker")

  -- Test that build_context returns expected structure
  local context, meta = ranker.build_context("How does authentication work?", {
    budget = 2000,
    project_root = vim.fn.getcwd(),
  })

  log(type(context) == "string" and "PASS" or "FAIL", "integration.context_type",
    "build_context returns string context")

  log(type(meta) == "table" and "PASS" or "FAIL", "integration.meta_type",
    "build_context returns table metadata")

  log(meta.query_type ~= nil and "PASS" or "FAIL", "integration.has_query_type",
    "Metadata has query_type field")

  log(meta.budget_allocation ~= nil and "PASS" or "FAIL", "integration.has_budget",
    "Metadata has budget_allocation field")

  log(meta.sources ~= nil and "PASS" or "FAIL", "integration.has_sources",
    "Metadata has sources field")

  log(meta.deduplicated ~= nil and "PASS" or "FAIL", "integration.has_dedup",
    "Metadata has deduplicated count")
end

-- =============================================================================
-- RUN ALL TESTS
-- =============================================================================

function M.run_all()
  print(string.rep("=", 60))
  print("  Adaptive Budget & Type Context Tests")
  print(string.rep("=", 60))

  M.results = { passed = 0, failed = 0, tests = {} }

  M.test_query_classification()
  M.test_adaptive_budget()
  M.test_type_context_patterns()
  M.test_build_context_integration()

  -- Summary
  print("\n" .. string.rep("=", 60))
  print("  ADAPTIVE BUDGET TEST SUMMARY")
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
