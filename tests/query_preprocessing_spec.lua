-- tests/query_preprocessing_spec.lua
-- Tests for query preprocessing, synonym expansion, and context relevance

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
-- Query Preprocessing Tests
-- =============================================================================

function M.test_query_preprocessing()
  section("Query Preprocessing")

  local ranker = require("editutor.indexer.ranker")

  -- Test basic preprocessing
  local query1 = "How do I validate user input?"
  local processed1, terms1 = ranker.preprocess_query(query1)

  log(#terms1 > 0 and "PASS" or "FAIL", "preprocess.basic",
    string.format("'%s' -> %d terms", query1:sub(1, 30), #terms1))

  -- Test stop word removal
  local has_stop_word = false
  for _, term in ipairs(terms1) do
    if term == "do" or term == "i" or term == "how" then
      has_stop_word = true
    end
  end
  log(not has_stop_word and "PASS" or "FAIL", "preprocess.stop_words",
    "Stop words removed")

  -- Test key term extraction
  local has_validate = false
  local has_user = false
  local has_input = false
  for _, term in ipairs(terms1) do
    if term == "validate" then
      has_validate = true
    end
    if term == "user" then
      has_user = true
    end
    if term == "input" then
      has_input = true
    end
  end
  log(has_validate and has_user and has_input and "PASS" or "FAIL", "preprocess.key_terms",
    "Key terms extracted: validate, user, input")

  -- Test camelCase splitting
  -- Note: "by" is a stop word, so it won't be in results
  local query2 = "getUserById function"
  local _, terms2 = ranker.preprocess_query(query2)

  local found_get = false
  local found_user = false
  local found_id = false
  local found_function = false
  for _, term in ipairs(terms2) do
    if term == "get" then
      found_get = true
    end
    if term == "user" then
      found_user = true
    end
    if term == "id" then
      found_id = true
    end
    if term == "function" then
      found_function = true
    end
  end
  log(found_get and found_user and found_id and found_function and "PASS" or "FAIL",
    "preprocess.camel_case",
    "camelCase split: getUserById -> get, user, id, function")

  -- Test snake_case splitting
  local query3 = "hash_password_with_salt"
  local _, terms3 = ranker.preprocess_query(query3)

  local found_hash = false
  local found_password = false
  local found_salt = false
  for _, term in ipairs(terms3) do
    if term == "hash" then
      found_hash = true
    end
    if term == "password" then
      found_password = true
    end
    if term == "salt" then
      found_salt = true
    end
  end
  log(found_hash and found_password and found_salt and "PASS" or "FAIL", "preprocess.snake_case",
    "snake_case split: hash_password_with_salt")
end

function M.test_synonym_expansion()
  section("Synonym Expansion")

  local ranker = require("editutor.indexer.ranker")

  -- Test auth -> authentication, login, etc.
  local query1 = "auth"
  local processed1, terms1 = ranker.preprocess_query(query1)

  local found_auth = false
  local found_authentication = false
  local found_login = false
  for _, term in ipairs(terms1) do
    if term == "auth" then
      found_auth = true
    end
    if term == "authentication" then
      found_authentication = true
    end
    if term == "login" then
      found_login = true
    end
  end
  log(found_auth and found_authentication and found_login and "PASS" or "FAIL",
    "synonym.auth",
    string.format("'auth' expanded to %d terms including authentication, login", #terms1))

  -- Test validate -> check, verify, etc.
  local query2 = "validate"
  local _, terms2 = ranker.preprocess_query(query2)

  local found_validate = false
  local found_check = false
  local found_verify = false
  for _, term in ipairs(terms2) do
    if term == "validate" then
      found_validate = true
    end
    if term == "check" then
      found_check = true
    end
    if term == "verify" then
      found_verify = true
    end
  end
  log(found_validate and found_check and found_verify and "PASS" or "FAIL",
    "synonym.validate",
    "validate -> check, verify")

  -- Test password -> pass, pwd, credential
  local query3 = "password"
  local _, terms3 = ranker.preprocess_query(query3)

  local found_password = false
  local found_pass = false
  local found_credential = false
  for _, term in ipairs(terms3) do
    if term == "password" then
      found_password = true
    end
    if term == "pass" then
      found_pass = true
    end
    if term == "credential" then
      found_credential = true
    end
  end
  log(found_password and found_pass and found_credential and "PASS" or "FAIL",
    "synonym.password",
    "password -> pass, credential")

  -- Test fetch -> get, retrieve, load
  local query4 = "fetch"
  local _, terms4 = ranker.preprocess_query(query4)

  local found_fetch = false
  local found_get = false
  local found_retrieve = false
  for _, term in ipairs(terms4) do
    if term == "fetch" then
      found_fetch = true
    end
    if term == "get" then
      found_get = true
    end
    if term == "retrieve" then
      found_retrieve = true
    end
  end
  log(found_fetch and found_get and found_retrieve and "PASS" or "FAIL",
    "synonym.fetch",
    "fetch -> get, retrieve")
end

function M.test_natural_language_queries()
  section("Natural Language Query Handling")

  local ranker = require("editutor.indexer.ranker")

  -- Common programming questions
  local test_cases = {
    {
      query = "How do I prevent timing attacks in password comparison?",
      expected = { "prevent", "timing", "attacks", "password", "comparison" },
    },
    {
      query = "What is the best way to handle authentication errors?",
      expected = { "best", "way", "handle", "auth", "errors" },
    },
    {
      query = "Why is my async function not returning a value?",
      expected = { "async", "function", "returning", "value" },
    },
    {
      query = "Can you explain how closures work in JavaScript?",
      expected = { "explain", "closures", "work", "javascript" },
    },
  }

  for i, tc in ipairs(test_cases) do
    local _, terms = ranker.preprocess_query(tc.query)

    local found_count = 0
    for _, expected in ipairs(tc.expected) do
      for _, term in ipairs(terms) do
        if term:find(expected, 1, true) then
          found_count = found_count + 1
          break
        end
      end
    end

    local pct = math.floor((found_count / #tc.expected) * 100)
    log(pct >= 60 and "PASS" or "FAIL",
      "nlp.case" .. i,
      string.format("'%s...' -> %d%% key terms found", tc.query:sub(1, 25), pct))
  end
end

function M.test_edge_cases()
  section("Edge Cases")

  local ranker = require("editutor.indexer.ranker")

  -- Empty query
  local empty_processed, empty_terms = ranker.preprocess_query("")
  log(#empty_terms == 0 and "PASS" or "FAIL", "edge.empty_query",
    string.format("Empty query -> %d terms", #empty_terms))

  -- Only stop words
  local stopwords_query = "the a an is are was were be"
  local _, stopwords_terms = ranker.preprocess_query(stopwords_query)
  log(#stopwords_terms == 0 and "PASS" or "FAIL", "edge.only_stopwords",
    string.format("Only stop words -> %d terms", #stopwords_terms))

  -- Special characters
  local special_query = "!@#$% what?"
  local _, special_terms = ranker.preprocess_query(special_query)
  log(type(special_terms) == "table" and "PASS" or "FAIL", "edge.special_chars",
    "Special characters handled")

  -- Very long query
  local long_query = string.rep("authentication validation ", 50)
  local _, long_terms = ranker.preprocess_query(long_query)
  log(#long_terms > 0 and #long_terms < 200 and "PASS" or "FAIL", "edge.long_query",
    string.format("Long query -> %d terms (no explosion)", #long_terms))

  -- Unicode/non-ASCII
  local unicode_query = "日本語 authentication"
  local _, unicode_terms = ranker.preprocess_query(unicode_query)
  log(type(unicode_terms) == "table" and "PASS" or "FAIL", "edge.unicode",
    "Unicode handled")
end

function M.test_weights()
  section("Ranking Weights")

  local ranker = require("editutor.indexer.ranker")

  -- Check default weights exist
  local weights = ranker.DEFAULT_WEIGHTS
  log(weights.bm25_score ~= nil and "PASS" or "FAIL", "weights.bm25", "bm25_score defined")
  log(weights.name_match ~= nil and "PASS" or "FAIL", "weights.name_match", "name_match defined")
  log(weights.lsp_definition ~= nil and "PASS" or "FAIL", "weights.lsp", "lsp_definition defined")
  log(weights.directory_proximity ~= nil and "PASS" or "FAIL", "weights.proximity", "directory_proximity defined")
  log(weights.import_distance ~= nil and "PASS" or "FAIL", "weights.import", "import_distance defined")
  log(weights.type_priority ~= nil and "PASS" or "FAIL", "weights.type", "type_priority defined")

  -- Check synonyms exist
  log(ranker.SYNONYMS ~= nil and type(ranker.SYNONYMS) == "table" and "PASS" or "FAIL",
    "weights.synonyms", "Synonyms table defined")

  -- Check stop words exist
  log(ranker.STOP_WORDS ~= nil and type(ranker.STOP_WORDS) == "table" and "PASS" or "FAIL",
    "weights.stopwords", "Stop words table defined")
end

-- =============================================================================
-- RUN ALL TESTS
-- =============================================================================

function M.run_all()
  print(string.rep("=", 60))
  print("  Query Preprocessing Tests")
  print(string.rep("=", 60))

  M.results = { passed = 0, failed = 0, tests = {} }

  M.test_query_preprocessing()
  M.test_synonym_expansion()
  M.test_natural_language_queries()
  M.test_edge_cases()
  M.test_weights()

  -- Summary
  print("\n" .. string.rep("=", 60))
  print("  QUERY PREPROCESSING TEST SUMMARY")
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
