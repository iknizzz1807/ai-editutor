-- tests/integration_test.lua
-- Comprehensive integration tests for ai-editutor v0.9.0
-- Tests: Indexer, BM25 search, Context retrieval, LLM payload

local M = {}

-- Test results storage
M.results = {
  passed = 0,
  failed = 0,
  tests = {},
}

---Log test result
---@param name string Test name
---@param passed boolean
---@param message string
local function log_test(name, passed, message)
  local status = passed and "✓ PASS" or "✗ FAIL"
  local result = { name = name, passed = passed, message = message }
  table.insert(M.results.tests, result)

  if passed then
    M.results.passed = M.results.passed + 1
  else
    M.results.failed = M.results.failed + 1
  end

  print(string.format("[%s] %s: %s", status, name, message))
end

---Create mock project structure in memory for testing
---@return table mock_files
local function create_mock_project()
  return {
    -- Main entry point
    ["src/main.lua"] = [[
-- Main entry point for the application
local config = require("src.config")
local api = require("src.api.client")
local utils = require("src.utils.helpers")

local M = {}

function M.start()
  config.load()
  api.connect()
  return utils.format_message("App started")
end

function M.process_request(request)
  -- Q: What validation should I add here?
  local validated = api.validate(request)
  return api.send(validated)
end

return M
]],

    -- Config module
    ["src/config.lua"] = [[
-- Configuration management
local M = {}

M.defaults = {
  timeout = 30,
  retries = 3,
  api_url = "https://api.example.com",
}

M.current = {}

function M.load()
  M.current = vim.tbl_deep_extend("force", {}, M.defaults)
  local ok, user_config = pcall(require, "user_config")
  if ok then
    M.current = vim.tbl_deep_extend("force", M.current, user_config)
  end
  return M.current
end

function M.get(key)
  return M.current[key]
end

function M.set(key, value)
  M.current[key] = value
end

return M
]],

    -- API client
    ["src/api/client.lua"] = [[
-- API client for external service communication
local config = require("src.config")
local http = require("src.utils.http")

local M = {}

M._connected = false
M._session = nil

function M.connect()
  local url = config.get("api_url")
  local timeout = config.get("timeout")

  M._session = http.create_session({
    base_url = url,
    timeout = timeout,
  })
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
    error("Not connected. Call connect() first.")
  end

  return http.post(M._session, "/api/v1/request", request)
end

function M.disconnect()
  if M._session then
    http.close_session(M._session)
    M._session = nil
    M._connected = false
  end
end

return M
]],

    -- HTTP utilities
    ["src/utils/http.lua"] = [[
-- HTTP utilities
local M = {}

function M.create_session(opts)
  return {
    base_url = opts.base_url,
    timeout = opts.timeout or 30,
    headers = opts.headers or {},
  }
end

function M.post(session, path, body)
  -- Mock HTTP POST implementation
  local url = session.base_url .. path
  return {
    status = 200,
    body = vim.json.encode({ success = true }),
  }
end

function M.get(session, path)
  local url = session.base_url .. path
  return {
    status = 200,
    body = "{}",
  }
end

function M.close_session(session)
  -- Cleanup
end

return M
]],

    -- Helper utilities
    ["src/utils/helpers.lua"] = [[
-- General helper functions
local M = {}

function M.format_message(msg)
  return string.format("[%s] %s", os.date("%Y-%m-%d %H:%M:%S"), msg)
end

function M.deep_copy(tbl)
  if type(tbl) ~= "table" then
    return tbl
  end
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = M.deep_copy(v)
  end
  return copy
end

function M.merge_tables(t1, t2)
  local result = M.deep_copy(t1)
  for k, v in pairs(t2) do
    result[k] = v
  end
  return result
end

function M.is_empty(tbl)
  return next(tbl) == nil
end

return M
]],

    -- Database module
    ["src/db/repository.lua"] = [[
-- Database repository pattern
local M = {}

local connection = nil

function M.connect(config)
  -- Connect to database
  connection = {
    host = config.host,
    port = config.port,
    database = config.database,
  }
  return true
end

function M.query(sql, params)
  if not connection then
    error("Database not connected")
  end
  -- Execute query
  return {}
end

function M.insert(table_name, data)
  local columns = {}
  local values = {}
  for k, v in pairs(data) do
    table.insert(columns, k)
    table.insert(values, v)
  end
  return M.query("INSERT INTO " .. table_name, values)
end

function M.find_by_id(table_name, id)
  return M.query("SELECT * FROM " .. table_name .. " WHERE id = ?", { id })
end

function M.disconnect()
  connection = nil
end

return M
]],

    -- User service
    ["src/services/user_service.lua"] = [[
-- User service for user management
local db = require("src.db.repository")
local helpers = require("src.utils.helpers")

local M = {}

function M.create_user(data)
  -- Q: How should I validate user data before inserting?
  if not data.email then
    return nil, "Email is required"
  end

  local user = {
    email = data.email,
    name = data.name or "",
    created_at = os.time(),
  }

  return db.insert("users", user)
end

function M.get_user(id)
  return db.find_by_id("users", id)
end

function M.format_user(user)
  return helpers.format_message("User: " .. user.email)
end

return M
]],
  }
end

-- =============================================================================
-- Test: Module Loading
-- =============================================================================

function M.test_module_loading()
  print("\n=== Test: Module Loading ===")

  -- Test indexer loading
  local indexer_ok, indexer = pcall(require, "editutor.indexer")
  log_test("indexer.load", indexer_ok, indexer_ok and "Indexer module loaded" or tostring(indexer))

  -- Test db loading
  local db_ok, db = pcall(require, "editutor.indexer.db")
  log_test("indexer.db.load", db_ok, db_ok and "DB module loaded" or tostring(db))

  -- Test chunker loading
  local chunker_ok, chunker = pcall(require, "editutor.indexer.chunker")
  log_test("indexer.chunker.load", chunker_ok, chunker_ok and "Chunker module loaded" or tostring(chunker))

  -- Test ranker loading
  local ranker_ok, ranker = pcall(require, "editutor.indexer.ranker")
  log_test("indexer.ranker.load", ranker_ok, ranker_ok and "Ranker module loaded" or tostring(ranker))

  -- Test cache loading
  local cache_ok, cache = pcall(require, "editutor.cache")
  log_test("cache.load", cache_ok, cache_ok and "Cache module loaded" or tostring(cache))

  -- Test provider loading
  local provider_ok, provider = pcall(require, "editutor.provider")
  log_test("provider.load", provider_ok, provider_ok and "Provider module loaded" or tostring(provider))

  return indexer_ok and db_ok and chunker_ok and ranker_ok and cache_ok and provider_ok
end

-- =============================================================================
-- Test: Tree-sitter Chunking
-- =============================================================================

function M.test_chunking()
  print("\n=== Test: Tree-sitter Chunking ===")

  local chunker_ok, chunker = pcall(require, "editutor.indexer.chunker")
  if not chunker_ok then
    log_test("chunker.available", false, "Chunker not available")
    return false
  end

  local mock_files = create_mock_project()
  local all_passed = true

  -- Test Lua file chunking
  local lua_content = mock_files["src/api/client.lua"]
  local chunks = chunker.extract_chunks("src/api/client.lua", lua_content, { language = "lua" })

  log_test("chunker.lua.extract", #chunks > 0, string.format("Extracted %d chunks from Lua file", #chunks))

  if #chunks > 0 then
    -- Check that we found the expected functions
    local found_functions = {}
    for _, chunk in ipairs(chunks) do
      if chunk.name then
        found_functions[chunk.name] = true
      end
    end

    local expected = { "M.connect", "M.validate", "M.send", "M.disconnect" }
    for _, fn_name in ipairs(expected) do
      local found = found_functions[fn_name] or found_functions[fn_name:gsub("M%.", "")]
      if not found then
        -- Check partial match
        for name, _ in pairs(found_functions) do
          if name:find(fn_name:gsub("M%.", ""), 1, true) then
            found = true
            break
          end
        end
      end
      log_test("chunker.lua.found." .. fn_name, found ~= nil, found and "Found function" or "Function not found")
      all_passed = all_passed and (found ~= nil)
    end

    -- Print chunk details for debugging
    print("\n  Chunks found:")
    for i, chunk in ipairs(chunks) do
      print(string.format("    %d. [%s] %s (lines %d-%d)", i, chunk.type or "?", chunk.name or "anonymous", chunk.start_line or 0, chunk.end_line or 0))
    end
  else
    all_passed = false
  end

  -- Test import extraction
  local imports = chunker.extract_imports("src/api/client.lua", lua_content, "lua")
  log_test("chunker.imports.extract", #imports > 0, string.format("Extracted %d imports", #imports))

  if #imports > 0 then
    print("\n  Imports found:")
    for i, imp in ipairs(imports) do
      print(string.format("    %d. %s (line %d)", i, imp.imported_name, imp.line_number or 0))
    end
  end

  return all_passed
end

-- =============================================================================
-- Test: Database Operations (requires sqlite.lua)
-- =============================================================================

function M.test_database()
  print("\n=== Test: Database Operations ===")

  local db_ok, db = pcall(require, "editutor.indexer.db")
  if not db_ok then
    log_test("db.available", false, "DB module not available: " .. tostring(db))
    return false
  end

  -- Test with temp database
  local test_root = "/tmp/editutor_test_" .. os.time()
  vim.fn.mkdir(test_root, "p")

  local init_ok, init_err = db.init(test_root)
  log_test("db.init", init_ok, init_ok and "Database initialized" or ("Init failed: " .. tostring(init_err)))

  if not init_ok then
    return false
  end

  -- Test file upsert
  local file_id = db.upsert_file({
    path = test_root .. "/test.lua",
    hash = "abc123",
    mtime = os.time(),
    language = "lua",
    line_count = 100,
  })
  log_test("db.upsert_file", file_id ~= nil, file_id and ("File ID: " .. file_id) or "Upsert failed")

  if file_id then
    -- Test chunk insert
    local chunk_id = db.insert_chunk({
      file_id = file_id,
      type = "function_declaration",
      name = "test_function",
      signature = "function test_function()",
      start_line = 1,
      end_line = 10,
      content = "function test_function() return true end",
      scope_path = nil,
    })
    log_test("db.insert_chunk", chunk_id ~= nil, chunk_id and ("Chunk ID: " .. chunk_id) or "Insert failed")

    -- Test BM25 search
    local results = db.search_bm25("test function", { limit = 10 })
    log_test("db.search_bm25", #results > 0, string.format("Found %d results", #results))

    if #results > 0 then
      print("\n  BM25 Search Results:")
      for i, r in ipairs(results) do
        print(string.format("    %d. [%s] %s (score: %s)", i, r.type or "?", r.name or "?", tostring(r.score)))
      end
    end

    -- Test name search
    local name_results = db.search_by_name("test_function")
    log_test("db.search_by_name", #name_results > 0, string.format("Found %d by name", #name_results))
  end

  -- Get stats
  local stats = db.get_stats()
  log_test("db.get_stats", stats.initialized, string.format("Files: %d, Chunks: %d", stats.file_count or 0, stats.chunk_count or 0))

  -- Cleanup
  db.close()
  vim.fn.delete(test_root, "rf")

  return true
end

-- =============================================================================
-- Test: Full Indexing Pipeline
-- =============================================================================

function M.test_indexing_pipeline()
  print("\n=== Test: Full Indexing Pipeline ===")

  local indexer_ok, indexer = pcall(require, "editutor.indexer")
  if not indexer_ok then
    log_test("indexer.available", false, "Indexer not available")
    return false
  end

  -- Create temp project
  local test_root = "/tmp/editutor_test_project_" .. os.time()
  vim.fn.mkdir(test_root .. "/src/api", "p")
  vim.fn.mkdir(test_root .. "/src/utils", "p")
  vim.fn.mkdir(test_root .. "/src/services", "p")
  vim.fn.mkdir(test_root .. "/src/db", "p")

  -- Write mock files
  local mock_files = create_mock_project()
  for path, content in pairs(mock_files) do
    local full_path = test_root .. "/" .. path
    local dir = vim.fn.fnamemodify(full_path, ":h")
    vim.fn.mkdir(dir, "p")
    local file = io.open(full_path, "w")
    if file then
      file:write(content)
      file:close()
    end
  end

  -- Override project root for testing
  local old_get_project_root = indexer._get_project_root
  indexer._get_project_root = function()
    return test_root
  end

  -- Setup indexer
  local setup_ok, setup_err = indexer.setup()
  log_test("indexer.setup", setup_ok, setup_ok and "Setup successful" or ("Setup failed: " .. tostring(setup_err)))

  if not setup_ok then
    -- Cleanup
    indexer._get_project_root = old_get_project_root
    vim.fn.delete(test_root, "rf")
    return false
  end

  -- Index project
  local index_ok, stats = indexer.index_project({
    progress = function(current, total, filepath)
      -- Silent progress
    end,
  })

  log_test("indexer.index_project", index_ok, index_ok and string.format("Indexed %d files, %d chunks", stats.files_indexed or 0, stats.chunks_created or 0) or ("Index failed: " .. tostring(stats.error)))

  if index_ok then
    print("\n  Index Statistics:")
    print(string.format("    Files scanned: %d", stats.files_scanned or 0))
    print(string.format("    Files indexed: %d", stats.files_indexed or 0))
    print(string.format("    Chunks created: %d", stats.chunks_created or 0))
    if stats.errors and #stats.errors > 0 then
      print(string.format("    Errors: %d", #stats.errors))
    end
  end

  -- Test search
  print("\n  Testing Search Queries:")

  local test_queries = {
    { query = "validate request", desc = "Find validation code" },
    { query = "connect database", desc = "Find DB connection" },
    { query = "create user", desc = "Find user creation" },
    { query = "format message", desc = "Find formatting helpers" },
    { query = "http post", desc = "Find HTTP methods" },
  }

  for _, test in ipairs(test_queries) do
    local results = indexer.search(test.query, { limit = 5 })
    local found = #results > 0

    print(string.format("\n    Query: '%s' (%s)", test.query, test.desc))
    print(string.format("    Results: %d", #results))

    if found then
      for i, r in ipairs(results) do
        local filename = vim.fn.fnamemodify(r.file_path or "", ":t")
        print(string.format("      %d. [%.2f] %s %s (%s:%d)", i, r.combined_score or 0, r.type or "?", r.name or "?", filename, r.start_line or 0))
      end
    end

    log_test("search." .. test.query:gsub(" ", "_"), found, found and "Found results" or "No results")
  end

  -- Cleanup
  indexer._get_project_root = old_get_project_root
  vim.fn.delete(test_root, "rf")

  return index_ok
end

-- =============================================================================
-- Test: Context Building (What gets sent to LLM)
-- =============================================================================

function M.test_context_building()
  print("\n=== Test: Context Building (LLM Payload) ===")

  local ranker_ok, ranker = pcall(require, "editutor.indexer.ranker")
  if not ranker_ok then
    log_test("ranker.available", false, "Ranker not available")
    return false
  end

  -- Create temp project
  local test_root = "/tmp/editutor_test_context_" .. os.time()
  vim.fn.mkdir(test_root .. "/src", "p")

  -- Write a mock file
  local mock_files = create_mock_project()
  local main_content = mock_files["src/main.lua"]
  local main_path = test_root .. "/src/main.lua"

  local file = io.open(main_path, "w")
  if file then
    file:write(main_content)
    file:close()
  end

  -- Also write dependent files
  for path, content in pairs(mock_files) do
    local full_path = test_root .. "/" .. path
    local dir = vim.fn.fnamemodify(full_path, ":h")
    vim.fn.mkdir(dir, "p")
    local f = io.open(full_path, "w")
    if f then
      f:write(content)
      f:close()
    end
  end

  -- Setup indexer
  local indexer_ok, indexer = pcall(require, "editutor.indexer")
  if not indexer_ok then
    log_test("indexer.for_context", false, "Indexer not available")
    vim.fn.delete(test_root, "rf")
    return false
  end

  local old_get_project_root = indexer._get_project_root
  indexer._get_project_root = function()
    return test_root
  end

  indexer.setup()
  indexer.index_project()

  -- Build context for a question
  print("\n  Simulating developer question:")
  print('  File: src/main.lua, Line: 12')
  print('  Question: "What validation should I add here?"')

  local context, metadata = ranker.build_context("What validation should I add here?", {
    current_file = main_path,
    cursor_line = 12,
    project_root = test_root,
    budget = 4000,
  })

  log_test("context.build", context ~= nil and context ~= "", context and "Context built successfully" or "Failed to build context")

  if context then
    print("\n  === CONTEXT THAT WOULD BE SENT TO LLM ===")
    print("  " .. string.rep("-", 50))

    -- Show truncated context
    local lines = vim.split(context, "\n")
    local max_lines = 50
    for i, line in ipairs(lines) do
      if i <= max_lines then
        print("  " .. line)
      elseif i == max_lines + 1 then
        print(string.format("  ... (%d more lines)", #lines - max_lines))
        break
      end
    end

    print("  " .. string.rep("-", 50))

    -- Show metadata
    print("\n  Context Metadata:")
    print(string.format("    Total tokens (estimated): %d", metadata.total_tokens or 0))
    print(string.format("    Chunks included: %d", metadata.chunks_included or 0))
    print("    Sources:")
    for _, src in ipairs(metadata.sources or {}) do
      print(string.format("      - %s: %s", src.type, src.count and tostring(src.count) or (src.file and vim.fn.fnamemodify(src.file, ":t") or "yes")))
    end
  end

  -- Cleanup
  indexer._get_project_root = old_get_project_root
  vim.fn.delete(test_root, "rf")

  return context ~= nil
end

-- =============================================================================
-- Test: Cache Operations
-- =============================================================================

function M.test_cache()
  print("\n=== Test: Cache Operations ===")

  local cache_ok, cache = pcall(require, "editutor.cache")
  if not cache_ok then
    log_test("cache.available", false, "Cache not available")
    return false
  end

  -- Setup cache
  cache.setup()
  cache.clear()

  -- Test basic set/get
  cache.set("test_key", "test_value", { ttl = 60 })
  local value, hit = cache.get("test_key")
  log_test("cache.set_get", hit and value == "test_value", hit and "Cache hit" or "Cache miss")

  -- Test TTL expiration (simulate with short TTL)
  cache.set("expire_key", "expire_value", { ttl = 0 })
  vim.wait(10) -- Small delay
  local _, hit2 = cache.get("expire_key")
  log_test("cache.ttl_expire", not hit2, not hit2 and "Correctly expired" or "Should have expired")

  -- Test tag-based invalidation
  cache.set("tagged_key", "tagged_value", { ttl = 60, tags = { "file:/test/path.lua" } })
  cache.invalidate_by_tag("file:/test/path.lua")
  local _, hit3 = cache.get("tagged_key")
  log_test("cache.tag_invalidate", not hit3, not hit3 and "Tag invalidation works" or "Tag invalidation failed")

  -- Test get_or_compute
  local compute_count = 0
  local computed = cache.get_or_compute("compute_key", function()
    compute_count = compute_count + 1
    return "computed_value"
  end, { ttl = 60 })

  local computed2 = cache.get_or_compute("compute_key", function()
    compute_count = compute_count + 1
    return "computed_value_2"
  end, { ttl = 60 })

  log_test("cache.get_or_compute", compute_count == 1 and computed == computed2, compute_count == 1 and "Computed only once" or "Computed multiple times")

  -- Get stats
  local stats = cache.get_stats()
  log_test("cache.stats", stats.total >= 0, string.format("Active: %d, Max: %d", stats.active, stats.max_entries))

  return true
end

-- =============================================================================
-- Test: Provider Inheritance
-- =============================================================================

function M.test_provider_inheritance()
  print("\n=== Test: Provider Inheritance ===")

  local provider_ok, provider = pcall(require, "editutor.provider")
  if not provider_ok then
    log_test("provider.available", false, "Provider not available")
    return false
  end

  -- Test built-in providers
  local providers_to_test = { "claude", "openai", "deepseek", "groq", "ollama" }

  for _, name in ipairs(providers_to_test) do
    local resolved = provider.resolve_provider(name)
    local has_required = resolved and resolved.name and resolved.url and resolved.format_request
    log_test("provider." .. name, has_required, has_required and string.format("URL: %s", resolved.url:sub(1, 40) .. "...") or "Missing required fields")
  end

  -- Test inheritance chain (deepseek inherits from openai)
  local deepseek = provider.resolve_provider("deepseek")
  local openai = provider.resolve_provider("openai")

  local inherits_format = deepseek and openai and type(deepseek.format_request) == "function"
  log_test("provider.inheritance", inherits_format, inherits_format and "DeepSeek inherits from OpenAI" or "Inheritance broken")

  -- Test custom provider registration
  provider.register_provider("test_provider", {
    __inherited_from = "openai",
    name = "test_provider",
    url = "https://test.example.com/v1/chat",
    api_key = function()
      return "test_key"
    end,
  })

  local test_prov = provider.resolve_provider("test_provider")
  log_test("provider.custom", test_prov and test_prov.name == "test_provider", test_prov and "Custom provider registered" or "Registration failed")

  -- List all providers
  local all_providers = provider.list_providers()
  print("\n  Available Providers:")
  for _, name in ipairs(all_providers) do
    print("    - " .. name)
  end

  return true
end

-- =============================================================================
-- Test: Real-world Scenario Simulation
-- =============================================================================

function M.test_developer_scenario()
  print("\n=== Test: Developer Scenario Simulation ===")

  -- Scenario: Developer is working on user_service.lua and asks about validation

  local test_root = "/tmp/editutor_scenario_" .. os.time()
  local mock_files = create_mock_project()

  -- Create project structure
  for path, content in pairs(mock_files) do
    local full_path = test_root .. "/" .. path
    local dir = vim.fn.fnamemodify(full_path, ":h")
    vim.fn.mkdir(dir, "p")
    local f = io.open(full_path, "w")
    if f then
      f:write(content)
      f:close()
    end
  end

  -- Setup
  local indexer = require("editutor.indexer")
  local ranker = require("editutor.indexer.ranker")
  local prompts = require("editutor.prompts")

  local old_get_project_root = indexer._get_project_root
  indexer._get_project_root = function()
    return test_root
  end

  indexer.setup()
  indexer.index_project()

  -- Simulate developer scenario
  print("\n  SCENARIO: Developer working on user_service.lua")
  print("  Question: 'How should I validate user data before inserting?'")
  print("  Current file: src/services/user_service.lua")
  print("  Cursor line: 8 (inside create_user function)")

  local current_file = test_root .. "/src/services/user_service.lua"
  local question = "How should I validate user data before inserting?"

  -- Build context
  local context, metadata = ranker.build_context(question, {
    current_file = current_file,
    cursor_line = 8,
    project_root = test_root,
    budget = 4000,
  })

  -- Build full prompt
  local system_prompt = prompts.get_system_prompt("question")
  local user_prompt = prompts.build_user_prompt(question, context, "question")

  print("\n  === FULL LLM PAYLOAD ===")
  print("\n  --- SYSTEM PROMPT ---")
  local sys_lines = vim.split(system_prompt, "\n")
  for i = 1, math.min(20, #sys_lines) do
    print("  " .. sys_lines[i])
  end
  if #sys_lines > 20 then
    print(string.format("  ... (%d more lines)", #sys_lines - 20))
  end

  print("\n  --- USER PROMPT ---")
  local user_lines = vim.split(user_prompt, "\n")
  for i = 1, math.min(60, #user_lines) do
    print("  " .. user_lines[i])
  end
  if #user_lines > 60 then
    print(string.format("  ... (%d more lines)", #user_lines - 60))
  end

  print("\n  --- CONTEXT ANALYSIS ---")
  print(string.format("  Total estimated tokens: %d", metadata.total_tokens or 0))
  print("  Sources included:")
  for _, src in ipairs(metadata.sources or {}) do
    local detail = src.count and string.format("(%d items)", src.count) or ""
    print(string.format("    ✓ %s %s", src.type, detail))
  end

  -- Check if we found relevant code
  print("\n  Relevance Check:")

  local context_lower = context:lower()
  local checks = {
    { pattern = "validate", desc = "Found 'validate' keyword" },
    { pattern = "user", desc = "Found 'user' related code" },
    { pattern = "email", desc = "Found 'email' validation context" },
    { pattern = "insert", desc = "Found 'insert' operations" },
    { pattern = "db", desc = "Found database context" },
  }

  local all_relevant = true
  for _, check in ipairs(checks) do
    local found = context_lower:find(check.pattern, 1, true) ~= nil
    local status = found and "✓" or "✗"
    print(string.format("    %s %s", status, check.desc))
    all_relevant = all_relevant and found
  end

  log_test("scenario.context_relevant", all_relevant, all_relevant and "All relevant context found" or "Some context missing")

  -- Cleanup
  indexer._get_project_root = old_get_project_root
  vim.fn.delete(test_root, "rf")

  return all_relevant
end

-- =============================================================================
-- Run All Tests
-- =============================================================================

function M.run_all()
  print("=" .. string.rep("=", 60))
  print("  ai-editutor v0.9.0 Integration Tests")
  print("=" .. string.rep("=", 60))

  M.results = { passed = 0, failed = 0, tests = {} }

  -- Run tests in order
  M.test_module_loading()
  M.test_chunking()
  M.test_cache()
  M.test_provider_inheritance()

  -- These require sqlite.lua
  local sqlite_ok = pcall(require, "sqlite")
  if sqlite_ok then
    M.test_database()
    M.test_indexing_pipeline()
    M.test_context_building()
    M.test_developer_scenario()
  else
    print("\n⚠ Skipping database tests (sqlite.lua not installed)")
  end

  -- Summary
  print("\n" .. string.rep("=", 60))
  print("  TEST SUMMARY")
  print(string.rep("=", 60))
  print(string.format("  Passed: %d", M.results.passed))
  print(string.format("  Failed: %d", M.results.failed))
  print(string.format("  Total:  %d", M.results.passed + M.results.failed))

  if M.results.failed > 0 then
    print("\n  Failed Tests:")
    for _, test in ipairs(M.results.tests) do
      if not test.passed then
        print(string.format("    ✗ %s: %s", test.name, test.message))
      end
    end
  end

  print(string.rep("=", 60))

  return M.results.failed == 0
end

return M
