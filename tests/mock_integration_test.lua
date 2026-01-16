-- Mock Integration Test
-- Tests the full context retrieval and LLM payload WITHOUT sqlite.lua
-- Uses in-memory mocks to simulate the indexer behavior

local M = {}

local function printf(fmt, ...)
  print(string.format(fmt, ...))
end

local function section(name)
  print("\n" .. string.rep("=", 70))
  printf("  %s", name)
  print(string.rep("=", 70))
end

-- Mock project files (same as production)
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
-- API client for external service communication
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
    error("Not connected. Call connect() first.")
  end
  return { status = 200, body = "{}" }
end

function M.disconnect()
  M._connected = false
end

return M
]],

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
  if not data.email:match("^[%w.]+@[%w.]+%.[%w]+$") then
    return nil, "Invalid email format"
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

  ["src/utils/helpers.lua"] = [[
-- General helper functions
local M = {}

function M.format_message(msg)
  return string.format("[%s] %s", os.date("%Y-%m-%d %H:%M:%S"), msg)
end

function M.deep_copy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = M.deep_copy(v)
  end
  return copy
end

function M.is_empty(tbl)
  return next(tbl) == nil
end

return M
]],

  ["src/db/repository.lua"] = [[
-- Database repository pattern
local M = {}
local connection = nil

function M.connect(config)
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
  return {}
end

function M.insert(table_name, data)
  local columns = {}
  local values = {}
  for k, v in pairs(data) do
    table.insert(columns, k)
    table.insert(values, v)
  end
  return { id = math.random(1000, 9999), success = true }
end

function M.find_by_id(table_name, id)
  return M.query("SELECT * FROM " .. table_name .. " WHERE id = ?", { id })
end

function M.disconnect()
  connection = nil
end

return M
]],
}

-- Create temp project
local function create_project()
  local root = "/tmp/editutor_mock_" .. os.time()

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

local function cleanup(root)
  vim.fn.delete(root, "rf")
end

-- =============================================================================
-- TEST: Full Context Simulation
-- =============================================================================

function M.test_full_context_simulation()
  section("FULL CONTEXT SIMULATION (No sqlite.lua required)")

  local project_root = create_project()
  printf("  Project root: %s", project_root)

  -- Load modules
  local chunker = require("editutor.indexer.chunker")
  local ranker = require("editutor.indexer.ranker")
  local prompts = require("editutor.prompts")

  -- Step 1: Extract chunks from all files (what indexer would do)
  print("\n  STEP 1: Extracting chunks from project files...")
  print("  " .. string.rep("-", 50))

  local all_chunks = {}
  local file_count = 0

  for path, content in pairs(MOCK_PROJECT) do
    local full_path = project_root .. "/" .. path
    local chunks = chunker.extract_chunks(full_path, content, { language = "lua" })

    printf("\n  File: %s", path)
    printf("    Chunks extracted: %d", #chunks)

    for _, chunk in ipairs(chunks) do
      chunk.file_path = full_path
      table.insert(all_chunks, chunk)

      if chunk.type == "function_declaration" then
        printf("      - [%s] %s (lines %d-%d)",
          chunk.type, chunk.name or "anonymous", chunk.start_line or 0, chunk.end_line or 0)
      end
    end

    file_count = file_count + 1
  end

  printf("\n  Total: %d files, %d chunks", file_count, #all_chunks)

  -- Step 2: Simulate BM25 search
  print("\n  STEP 2: Simulating BM25 Search...")
  print("  " .. string.rep("-", 50))

  local function mock_search(query, chunks)
    local results = {}
    local query_words = {}
    for word in query:lower():gmatch("%w+") do
      query_words[word] = true
    end

    for _, chunk in ipairs(chunks) do
      local score = 0
      local content_lower = (chunk.content or ""):lower()
      local name_lower = (chunk.name or ""):lower()

      -- Simple scoring: count query word matches
      for word, _ in pairs(query_words) do
        if name_lower:find(word, 1, true) then
          score = score + 2  -- Name match is stronger
        end
        if content_lower:find(word, 1, true) then
          score = score + 1
        end
      end

      if score > 0 then
        chunk.mock_score = score
        table.insert(results, chunk)
      end
    end

    -- Sort by score
    table.sort(results, function(a, b)
      return (a.mock_score or 0) > (b.mock_score or 0)
    end)

    return results
  end

  local test_queries = {
    { q = "validate request", desc = "Find validation code" },
    { q = "create user", desc = "Find user creation" },
    { q = "connect database", desc = "Find DB connection" },
    { q = "format message", desc = "Find formatting" },
  }

  for _, tq in ipairs(test_queries) do
    local results = mock_search(tq.q, all_chunks)
    printf("\n  Query: '%s' (%s)", tq.q, tq.desc)
    printf("  Results: %d chunks", #results)

    for i = 1, math.min(3, #results) do
      local r = results[i]
      local fname = vim.fn.fnamemodify(r.file_path or "", ":t")
      printf("    %d. [score:%d] %s %s (%s:%d)",
        i, r.mock_score or 0, r.type or "?", r.name or "?", fname, r.start_line or 0)
    end
  end

  -- Step 3: Build context for developer scenario
  print("\n  STEP 3: Building Context for Developer Scenario...")
  print("  " .. string.rep("-", 50))

  local current_file = project_root .. "/src/services/user_service.lua"
  local cursor_line = 8
  local question = "How should I validate user data before inserting?"

  printf("\n  SCENARIO:")
  printf("    Developer is editing: src/services/user_service.lua")
  printf("    Cursor at line: %d (inside create_user function)", cursor_line)
  printf("    Question: '%s'", question)

  -- Read current file for context
  local ok, current_content = pcall(vim.fn.readfile, current_file)
  if not ok then
    print("  ERROR: Could not read current file")
    cleanup(project_root)
    return
  end

  -- Build context parts
  local context_parts = {}

  -- Part 1: Current file context (30% budget)
  local start_line = math.max(1, cursor_line - 20)
  local end_line = math.min(#current_content, cursor_line + 20)
  local current_context = {}
  for i = start_line, end_line do
    table.insert(current_context, string.format("%d: %s", i, current_content[i]))
  end
  table.insert(context_parts, string.format(
    "=== Current File: user_service.lua (lines %d-%d) ===\n%s",
    start_line, end_line, table.concat(current_context, "\n")
  ))

  -- Part 2: Related chunks from search (20% budget)
  local search_results = mock_search(question, all_chunks)
  if #search_results > 0 then
    local search_parts = {}
    for i = 1, math.min(5, #search_results) do
      local r = search_results[i]
      local fname = vim.fn.fnamemodify(r.file_path or "", ":t")
      table.insert(search_parts, string.format(
        "-- %s %s (%s:%d-%d)\n%s",
        r.type or "chunk", r.name or "anonymous", fname,
        r.start_line or 0, r.end_line or 0, r.content or ""
      ))
    end
    table.insert(context_parts, "=== Related Code (BM25 Search) ===\n" .. table.concat(search_parts, "\n\n"))
  end

  -- Part 3: Import graph (10% budget)
  local imports = chunker.extract_imports(current_file, MOCK_PROJECT["src/services/user_service.lua"], "lua")
  if #imports > 0 then
    local import_parts = {}
    for _, imp in ipairs(imports) do
      table.insert(import_parts, string.format("- %s (line %d)", imp.imported_name, imp.line_number or 0))
    end
    table.insert(context_parts, "=== Imports ===\n" .. table.concat(import_parts, "\n"))
  end

  local full_context = table.concat(context_parts, "\n\n")

  -- Step 4: Build full LLM payload
  print("\n  STEP 4: Building Full LLM Payload...")
  print("  " .. string.rep("-", 50))

  local system_prompt = prompts.get_system_prompt("question")
  local user_prompt = prompts.build_user_prompt(question, full_context, "question")

  -- Display everything
  print("\n  === SYSTEM PROMPT ===")
  print("  " .. string.rep("-", 40))
  local sys_lines = vim.split(system_prompt, "\n")
  for i = 1, math.min(20, #sys_lines) do
    print("  " .. sys_lines[i])
  end
  if #sys_lines > 20 then
    printf("  ... (%d more lines)", #sys_lines - 20)
  end

  print("\n  === USER PROMPT (what gets sent with context) ===")
  print("  " .. string.rep("-", 40))
  local user_lines = vim.split(user_prompt, "\n")
  for i = 1, math.min(80, #user_lines) do
    print("  " .. user_lines[i])
  end
  if #user_lines > 80 then
    printf("  ... (%d more lines)", #user_lines - 80)
  end

  -- Token estimates
  print("\n  === TOKEN ESTIMATES ===")
  local sys_tokens = math.ceil(#system_prompt / 4)
  local user_tokens = math.ceil(#user_prompt / 4)
  printf("  System prompt: ~%d tokens (%d chars)", sys_tokens, #system_prompt)
  printf("  User prompt: ~%d tokens (%d chars)", user_tokens, #user_prompt)
  printf("  Total input: ~%d tokens", sys_tokens + user_tokens)

  -- Context analysis
  print("\n  === CONTEXT ANALYSIS ===")
  print("  What information is available to the LLM:")

  local analysis = {
    { pattern = "create_user", desc = "Target function (create_user)" },
    { pattern = "validate", desc = "Validation-related code" },
    { pattern = "email", desc = "Email field reference" },
    { pattern = "db%.insert", desc = "Database operations" },
    { pattern = "error", desc = "Error handling patterns" },
    { pattern = "helpers", desc = "Helper function references" },
    { pattern = "api%.validate", desc = "API validation example" },
    { pattern = "request%.type", desc = "Type checking patterns" },
  }

  local ctx_text = user_prompt:lower()
  for _, a in ipairs(analysis) do
    local found = ctx_text:find(a.pattern:lower(), 1, true) ~= nil
    local icon = found and "[YES]" or "[NO]"
    printf("    %s %s", icon, a.desc)
  end

  -- Cleanup
  cleanup(project_root)

  print("\n  TEST COMPLETE")
  return true
end

-- =============================================================================
-- TEST: Multi-Signal Ranking Demonstration
-- =============================================================================

function M.test_ranking_signals()
  section("MULTI-SIGNAL RANKING DEMONSTRATION")

  local ranker = require("editutor.indexer.ranker")

  print("\n  DEFAULT RANKING WEIGHTS:")
  print("  " .. string.rep("-", 40))

  for signal, weight in pairs(ranker.DEFAULT_WEIGHTS) do
    local bar = string.rep("*", math.floor(weight * 20))
    printf("  %-20s: %.2f %s", signal, weight, bar)
  end

  print("\n  CONTEXT BUDGET ALLOCATION:")
  print("  " .. string.rep("-", 40))

  for category, pct in pairs(ranker.BUDGET_ALLOCATION) do
    local bar = string.rep("#", math.floor(pct * 50))
    printf("  %-20s: %d%% %s", category, math.floor(pct * 100), bar)
  end

  return true
end

-- =============================================================================
-- TEST: Cache System
-- =============================================================================

function M.test_cache_system()
  section("CACHE SYSTEM TEST")

  local cache = require("editutor.cache")
  cache.setup()
  cache.clear()

  print("\n  Testing cache operations...")

  -- Test 1: Basic set/get
  cache.set("context:file1:10", "cached_context_data", { ttl = 300 })
  local val, hit = cache.get("context:file1:10")
  printf("  1. Set/Get: %s (hit=%s)", hit and "OK" or "FAIL", tostring(hit))

  -- Test 2: Cache miss
  local _, hit2 = cache.get("nonexistent_key")
  printf("  2. Cache miss: %s (hit=%s)", not hit2 and "OK" or "FAIL", tostring(hit2))

  -- Test 3: Tag-based invalidation
  cache.set("ctx:a", "value_a", { ttl = 300, tags = { "file:/src/main.lua" } })
  cache.set("ctx:b", "value_b", { ttl = 300, tags = { "file:/src/main.lua" } })
  cache.set("ctx:c", "value_c", { ttl = 300, tags = { "file:/src/other.lua" } })

  cache.invalidate_by_tag("file:/src/main.lua")

  local _, hit_a = cache.get("ctx:a")
  local _, hit_b = cache.get("ctx:b")
  local _, hit_c = cache.get("ctx:c")

  printf("  3. Tag invalidation: a=%s, b=%s, c=%s (expect: miss, miss, hit)",
    tostring(hit_a), tostring(hit_b), tostring(hit_c))

  -- Test 4: Stats
  local stats = cache.get_stats()
  printf("  4. Cache stats: active=%d, max=%d, expired=%d",
    stats.active or 0, stats.max_entries or 0, stats.expired or 0)

  return true
end

-- =============================================================================
-- RUN ALL
-- =============================================================================

function M.run_all()
  print(string.rep("=", 70))
  print("  ai-editutor v0.9.0 Mock Integration Tests")
  print("  (No sqlite.lua required)")
  print(string.rep("=", 70))

  M.test_ranking_signals()
  M.test_cache_system()
  M.test_full_context_simulation()

  print("\n" .. string.rep("=", 70))
  print("  ALL TESTS COMPLETE")
  print(string.rep("=", 70))
end

return M
