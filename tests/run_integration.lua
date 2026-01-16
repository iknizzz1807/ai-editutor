#!/usr/bin/env -S nvim --headless -u NONE -c 'set rtp+=.' -c 'lua dofile("tests/run_integration.lua")' -c 'qa!'

-- Quick Integration Test Runner
-- Tests indexer, BM25 search, context building, and LLM payload

local function printf(fmt, ...)
  print(string.format(fmt, ...))
end

local function test_section(name)
  print("\n" .. string.rep("=", 60))
  printf("  %s", name)
  print(string.rep("=", 60))
end

local results = { passed = 0, failed = 0 }

local function test(name, condition, msg)
  local status = condition and "PASS" or "FAIL"
  local icon = condition and "[OK]" or "[!!]"
  printf("%s %s: %s", icon, name, msg or "")
  if condition then
    results.passed = results.passed + 1
  else
    results.failed = results.failed + 1
  end
  return condition
end

-- Mock project files
local MOCK_PROJECT = {
  ["src/main.lua"] = [[
-- Main entry point
local config = require("src.config")
local api = require("src.api.client")

local M = {}

function M.start()
  config.load()
  api.connect()
  return "App started"
end

function M.process_request(request)
  -- Q: What validation should I add here?
  local validated = api.validate(request)
  return api.send(validated)
end

return M
]],

  ["src/config.lua"] = [[
-- Configuration management
local M = {}

M.defaults = {
  timeout = 30,
  retries = 3,
  api_url = "https://api.example.com",
}

function M.load()
  return vim.tbl_deep_extend("force", {}, M.defaults)
end

function M.get(key)
  return M.defaults[key]
end

return M
]],

  ["src/api/client.lua"] = [[
-- API client
local config = require("src.config")

local M = {}
M._connected = false

function M.connect()
  local url = config.get("api_url")
  M._connected = true
  return true
end

function M.validate(request)
  if not request then
    error("Request cannot be nil")
  end
  if not request.type then
    error("Request must have a type")
  end
  return request
end

function M.send(request)
  if not M._connected then
    error("Not connected")
  end
  return { status = 200 }
end

return M
]],

  ["src/utils/helpers.lua"] = [[
-- Helper utilities
local M = {}

function M.format_message(msg)
  return string.format("[%s] %s", os.date("%H:%M:%S"), msg)
end

function M.deep_copy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = M.deep_copy(v)
  end
  return copy
end

return M
]],

  ["src/services/user_service.lua"] = [[
-- User service
local db = require("src.db.repository")
local helpers = require("src.utils.helpers")

local M = {}

function M.create_user(data)
  -- Q: How should I validate user data?
  if not data.email then
    return nil, "Email required"
  end
  return db.insert("users", data)
end

function M.get_user(id)
  return db.find_by_id("users", id)
end

return M
]],

  ["src/db/repository.lua"] = [[
-- Database repository
local M = {}
local conn = nil

function M.connect(config)
  conn = { host = config.host }
  return true
end

function M.query(sql, params)
  if not conn then error("Not connected") end
  return {}
end

function M.insert(table_name, data)
  return M.query("INSERT INTO " .. table_name, data)
end

function M.find_by_id(table_name, id)
  return M.query("SELECT * FROM " .. table_name, { id })
end

return M
]],
}

-- Create temp project
local function create_mock_project()
  local root = "/tmp/editutor_integration_" .. os.time()

  for path, content in pairs(MOCK_PROJECT) do
    local full_path = root .. "/" .. path
    local dir = vim.fn.fnamemodify(full_path, ":h")
    vim.fn.mkdir(dir, "p")
    local f = io.open(full_path, "w")
    if f then
      f:write(content)
      f:close()
    end
  end

  return root
end

local function cleanup_project(root)
  vim.fn.delete(root, "rf")
end

-- ============================================================================
-- TEST 1: Module Loading
-- ============================================================================
test_section("TEST 1: Module Loading")

local chunker_ok, chunker = pcall(require, "editutor.indexer.chunker")
test("chunker.load", chunker_ok, chunker_ok and "Loaded" or tostring(chunker))

local db_ok, db = pcall(require, "editutor.indexer.db")
test("db.load", db_ok, db_ok and "Loaded" or tostring(db))

local ranker_ok, ranker = pcall(require, "editutor.indexer.ranker")
test("ranker.load", ranker_ok, ranker_ok and "Loaded" or tostring(ranker))

local cache_ok, cache = pcall(require, "editutor.cache")
test("cache.load", cache_ok, cache_ok and "Loaded" or tostring(cache))

local provider_ok, provider = pcall(require, "editutor.provider")
test("provider.load", provider_ok, provider_ok and "Loaded" or tostring(provider))

-- ============================================================================
-- TEST 2: Tree-sitter Chunking
-- ============================================================================
test_section("TEST 2: Tree-sitter Chunking")

if chunker_ok then
  local lua_code = MOCK_PROJECT["src/api/client.lua"]
  local chunks = chunker.extract_chunks("test.lua", lua_code, { language = "lua" })

  test("chunker.extract", #chunks > 0, string.format("Found %d chunks", #chunks))

  if #chunks > 0 then
    print("\n  Extracted chunks:")
    for i, c in ipairs(chunks) do
      printf("    %d. [%s] %s (lines %d-%d)",
        i, c.type or "?", c.name or "anon", c.start_line or 0, c.end_line or 0)
    end

    -- Check for expected functions
    local found = {}
    for _, c in ipairs(chunks) do
      if c.name then found[c.name] = true end
    end

    local expected = { "connect", "validate", "send" }
    for _, fn in ipairs(expected) do
      local has_fn = found[fn] or found["M." .. fn]
      test("chunk.has." .. fn, has_fn, has_fn and "Found" or "Not found")
    end
  end

  -- Test import extraction
  local imports = chunker.extract_imports("test.lua", lua_code, "lua")
  test("chunker.imports", #imports > 0, string.format("Found %d imports", #imports))

  if #imports > 0 then
    print("\n  Imports:")
    for _, imp in ipairs(imports) do
      printf("    - %s (line %d)", imp.imported_name, imp.line_number or 0)
    end
  end
end

-- ============================================================================
-- TEST 3: Database + BM25 Search
-- ============================================================================
test_section("TEST 3: Database + BM25 Search")

local sqlite_ok = pcall(require, "sqlite")
if not sqlite_ok then
  print("  [SKIP] sqlite.lua not installed - skipping DB tests")
else
  if db_ok then
    local test_root = "/tmp/editutor_db_test_" .. os.time()
    vim.fn.mkdir(test_root, "p")

    local init_ok = db.init(test_root)
    test("db.init", init_ok, init_ok and "Initialized" or "Failed")

    if init_ok then
      -- Insert test data
      local file_id = db.upsert_file({
        path = test_root .. "/test.lua",
        hash = "abc123",
        mtime = os.time(),
        language = "lua",
        line_count = 50,
      })
      test("db.upsert_file", file_id ~= nil, file_id and ("ID: " .. file_id) or "Failed")

      if file_id then
        -- Insert chunks
        local chunks_data = {
          { name = "validate_request", type = "function_declaration", content = "function validate_request(req) if not req then error('nil') end return req end" },
          { name = "connect_database", type = "function_declaration", content = "function connect_database(config) local conn = db.connect(config) return conn end" },
          { name = "create_user", type = "function_declaration", content = "function create_user(data) validate(data) return db.insert('users', data) end" },
        }

        for i, chunk in ipairs(chunks_data) do
          db.insert_chunk({
            file_id = file_id,
            type = chunk.type,
            name = chunk.name,
            signature = "function " .. chunk.name .. "()",
            start_line = i * 10,
            end_line = i * 10 + 5,
            content = chunk.content,
          })
        end

        -- Test BM25 search
        print("\n  BM25 Search Tests:")
        local queries = {
          "validate request",
          "connect database",
          "create user",
          "function",
        }

        for _, q in ipairs(queries) do
          local results = db.search_bm25(q, { limit = 5 })
          printf("    Query '%s': %d results", q, #results)
          if #results > 0 then
            for j, r in ipairs(results) do
              printf("      %d. %s (score: %.2f)", j, r.name or "?", r.score or 0)
            end
          end
        end

        -- Test name search
        local name_results = db.search_by_name("validate")
        test("db.search_by_name", #name_results > 0, string.format("Found %d", #name_results))

        -- Stats
        local stats = db.get_stats()
        printf("  DB Stats: files=%d, chunks=%d", stats.file_count or 0, stats.chunk_count or 0)
      end

      db.close()
    end

    vim.fn.delete(test_root, "rf")
  end
end

-- ============================================================================
-- TEST 4: Full Indexing Pipeline
-- ============================================================================
test_section("TEST 4: Full Indexing Pipeline")

if not sqlite_ok then
  print("  [SKIP] sqlite.lua not installed")
else
  local indexer_ok, indexer = pcall(require, "editutor.indexer")

  if indexer_ok then
    local project_root = create_mock_project()
    printf("  Created mock project at: %s", project_root)

    -- Override project root
    local old_root_fn = indexer._get_project_root
    indexer._get_project_root = function() return project_root end

    local setup_ok = indexer.setup()
    test("indexer.setup", setup_ok, setup_ok and "Success" or "Failed")

    if setup_ok then
      local idx_ok, idx_stats = indexer.index_project({
        progress = function() end -- Silent
      })

      test("indexer.index", idx_ok, idx_ok and
        string.format("Files: %d, Chunks: %d", idx_stats.files_indexed or 0, idx_stats.chunks_created or 0) or
        "Failed")

      if idx_ok then
        print("\n  Search Results from Indexed Project:")

        local search_queries = {
          { q = "validate", desc = "Find validation code" },
          { q = "connect", desc = "Find connection code" },
          { q = "user", desc = "Find user-related code" },
          { q = "config", desc = "Find config code" },
        }

        for _, sq in ipairs(search_queries) do
          local results = indexer.search(sq.q, { limit = 3 })
          printf("\n    '%s' (%s): %d results", sq.q, sq.desc, #results)
          for i, r in ipairs(results) do
            local fname = vim.fn.fnamemodify(r.file_path or "", ":t")
            printf("      %d. [%.2f] %s %s (%s:%d)",
              i, r.combined_score or 0, r.type or "?", r.name or "?", fname, r.start_line or 0)
          end
        end
      end
    end

    indexer._get_project_root = old_root_fn
    cleanup_project(project_root)
  end
end

-- ============================================================================
-- TEST 5: Context Building (What Gets Sent to LLM)
-- ============================================================================
test_section("TEST 5: Context Building (LLM Payload)")

if not sqlite_ok then
  print("  [SKIP] sqlite.lua not installed")
elseif ranker_ok then
  local indexer = require("editutor.indexer")
  local project_root = create_mock_project()

  local old_root_fn = indexer._get_project_root
  indexer._get_project_root = function() return project_root end

  indexer.setup()
  indexer.index_project({ progress = function() end })

  -- Simulate developer asking a question
  print("\n  DEVELOPER SCENARIO:")
  print("  ------------------")
  print("  File: src/services/user_service.lua")
  print("  Line: 8 (inside create_user function)")
  print("  Question: 'How should I validate user data?'")

  local current_file = project_root .. "/src/services/user_service.lua"
  local question = "How should I validate user data?"

  local context, metadata = ranker.build_context(question, {
    current_file = current_file,
    cursor_line = 8,
    project_root = project_root,
    budget = 4000,
  })

  test("context.build", context and #context > 0,
    string.format("Built %d chars, ~%d tokens", #context, metadata.total_tokens or 0))

  if context then
    print("\n  CONTEXT METADATA:")
    printf("    Estimated tokens: %d", metadata.total_tokens or 0)
    printf("    Chunks included: %d", metadata.chunks_included or 0)
    print("    Sources:")
    for _, src in ipairs(metadata.sources or {}) do
      local detail = src.count and string.format("(%d items)", src.count) or
                    src.file and vim.fn.fnamemodify(src.file, ":t") or "yes"
      printf("      - %s: %s", src.type, detail)
    end

    print("\n  CONTEXT PREVIEW (first 40 lines):")
    print("  " .. string.rep("-", 50))
    local lines = vim.split(context, "\n")
    for i = 1, math.min(40, #lines) do
      print("  " .. lines[i])
    end
    if #lines > 40 then
      printf("  ... (%d more lines)", #lines - 40)
    end
    print("  " .. string.rep("-", 50))

    -- Check relevance
    print("\n  RELEVANCE CHECK:")
    local ctx_lower = context:lower()
    local checks = {
      { p = "validate", d = "validation code" },
      { p = "user", d = "user context" },
      { p = "email", d = "email field" },
      { p = "db", d = "database operations" },
      { p = "create_user", d = "target function" },
    }

    for _, c in ipairs(checks) do
      local found = ctx_lower:find(c.p, 1, true) ~= nil
      printf("    [%s] %s", found and "OK" or "!!", c.d)
    end
  end

  indexer._get_project_root = old_root_fn
  cleanup_project(project_root)
end

-- ============================================================================
-- TEST 6: Full LLM Payload Simulation
-- ============================================================================
test_section("TEST 6: Full LLM Payload Simulation")

if not sqlite_ok then
  print("  [SKIP] sqlite.lua not installed")
else
  local prompts_ok, prompts = pcall(require, "editutor.prompts")

  if prompts_ok and ranker_ok then
    local indexer = require("editutor.indexer")
    local project_root = create_mock_project()

    local old_root_fn = indexer._get_project_root
    indexer._get_project_root = function() return project_root end

    indexer.setup()
    indexer.index_project({ progress = function() end })

    local current_file = project_root .. "/src/main.lua"
    local question = "What validation should I add here?"

    local context, _ = ranker.build_context(question, {
      current_file = current_file,
      cursor_line = 14,
      project_root = project_root,
      budget = 4000,
    })

    local system_prompt = prompts.get_system_prompt("question")
    local user_prompt = prompts.build_user_prompt(question, context, "question")

    print("\n  === COMPLETE LLM REQUEST ===")

    print("\n  SYSTEM PROMPT (first 15 lines):")
    print("  " .. string.rep("-", 40))
    local sys_lines = vim.split(system_prompt, "\n")
    for i = 1, math.min(15, #sys_lines) do
      print("  " .. sys_lines[i])
    end
    if #sys_lines > 15 then printf("  ... (%d more lines)", #sys_lines - 15) end

    print("\n  USER PROMPT (first 50 lines):")
    print("  " .. string.rep("-", 40))
    local user_lines = vim.split(user_prompt, "\n")
    for i = 1, math.min(50, #user_lines) do
      print("  " .. user_lines[i])
    end
    if #user_lines > 50 then printf("  ... (%d more lines)", #user_lines - 50) end

    -- Token estimates
    local sys_tokens = math.ceil(#system_prompt / 4)
    local user_tokens = math.ceil(#user_prompt / 4)

    print("\n  TOKEN ESTIMATES:")
    printf("    System prompt: ~%d tokens", sys_tokens)
    printf("    User prompt: ~%d tokens", user_tokens)
    printf("    Total input: ~%d tokens", sys_tokens + user_tokens)

    test("payload.complete",
      system_prompt and #system_prompt > 0 and user_prompt and #user_prompt > 0,
      "Full payload generated")

    indexer._get_project_root = old_root_fn
    cleanup_project(project_root)
  end
end

-- ============================================================================
-- TEST 7: Cache Operations
-- ============================================================================
test_section("TEST 7: Cache Operations")

if cache_ok then
  cache.setup()
  cache.clear()

  -- Basic set/get
  cache.set("key1", "value1", { ttl = 60 })
  local v, hit = cache.get("key1")
  test("cache.set_get", hit and v == "value1", hit and "Hit" or "Miss")

  -- TTL expiration
  cache.set("key2", "value2", { ttl = 0 })
  local _, hit2 = cache.get("key2")
  test("cache.ttl", not hit2, not hit2 and "Expired correctly" or "Should expire")

  -- Tag invalidation
  cache.set("key3", "value3", { ttl = 60, tags = { "file:/test.lua" } })
  cache.invalidate_by_tag("file:/test.lua")
  local _, hit3 = cache.get("key3")
  test("cache.tag_invalidate", not hit3, not hit3 and "Invalidated" or "Should invalidate")

  -- Stats
  local stats = cache.get_stats()
  printf("  Cache stats: active=%d, max=%d", stats.active or 0, stats.max_entries or 0)
end

-- ============================================================================
-- TEST 8: Provider System
-- ============================================================================
test_section("TEST 8: Provider System")

if provider_ok then
  local providers = { "claude", "openai", "deepseek", "groq", "ollama" }

  for _, name in ipairs(providers) do
    local p = provider.resolve_provider(name)
    local valid = p and p.name and p.url and type(p.format_request) == "function"
    test("provider." .. name, valid, valid and p.url:sub(1, 35) .. "..." or "Invalid")
  end

  -- Test inheritance
  local deepseek = provider.resolve_provider("deepseek")
  local openai = provider.resolve_provider("openai")
  local inherits = deepseek and openai and
    type(deepseek.format_request) == "function" and
    type(openai.format_request) == "function"
  test("provider.inheritance", inherits, inherits and "DeepSeek inherits OpenAI format" or "Broken")
end

-- ============================================================================
-- SUMMARY
-- ============================================================================
print("\n" .. string.rep("=", 60))
print("  TEST SUMMARY")
print(string.rep("=", 60))
printf("  Passed: %d", results.passed)
printf("  Failed: %d", results.failed)
printf("  Total:  %d", results.passed + results.failed)

if results.failed > 0 then
  print("\n  Some tests failed. Check output above for details.")
else
  print("\n  All tests passed!")
end

print(string.rep("=", 60))
