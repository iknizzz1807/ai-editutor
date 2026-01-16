-- Full Context Building Test
-- Shows exactly what gets sent to the LLM
print("=" .. string.rep("=", 60))
print("  FULL CONTEXT BUILDING TEST")
print("=" .. string.rep("=", 60))

-- Create mock project
local test_root = "/tmp/editutor_ctx_" .. os.time()

local MOCK_FILES = {
  ["src/main.lua"] = [[
-- Main entry point
local api = require("src.api.client")
local config = require("src.config")

local M = {}

function M.start()
  config.load()
  api.connect()
end

function M.process_request(request)
  -- Q: What validation should I add here?
  local validated = api.validate(request)
  return api.send(validated)
end

return M
]],

  ["src/api/client.lua"] = [[
-- API client
local config = require("src.config")

local M = {}

function M.connect()
  local url = config.get("api_url")
  M._connected = true
end

function M.validate(request)
  if not request then
    error("Request cannot be nil")
  end
  if not request.type then
    error("Request must have type field")
  end
  if not request.data then
    error("Request must have data field")
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

  ["src/config.lua"] = [[
-- Config module
local M = {}

M.defaults = {
  api_url = "https://api.example.com",
  timeout = 30,
}

function M.load()
  return M.defaults
end

function M.get(key)
  return M.defaults[key]
end

return M
]],

  ["src/services/user.lua"] = [[
-- User service
local db = require("src.db")

local M = {}

function M.create_user(data)
  if not data.email then
    return nil, "Email required"
  end
  return db.insert("users", data)
end

return M
]],
}

-- Create files
for path, content in pairs(MOCK_FILES) do
  local full = test_root .. "/" .. path
  vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
  local f = io.open(full, "w")
  if f then f:write(content); f:close() end
end

print("\nProject created at:", test_root)

-- Initialize indexer
local indexer = require("editutor.indexer")
local ranker = require("editutor.indexer.ranker")

-- Override project root
local orig = indexer._get_project_root
indexer._get_project_root = function() return test_root end

-- Setup and index
print("\n1. Indexing project...")
indexer.setup()
local ok, stats = indexer.index_project({ progress = function() end })
print(string.format("   Files: %d, Chunks: %d", stats.files_indexed or 0, stats.chunks_created or 0))

-- Test search
print("\n2. BM25 Search for 'validate request':")
local results = indexer.search("validate request", { limit = 5 })
for i, r in ipairs(results) do
  local fname = vim.fn.fnamemodify(r.file_path or "", ":t")
  print(string.format("   %d. [%.2f] %s (%s:%d)",
    i, r.combined_score or 0, r.name or "?", fname, r.start_line or 0))
end

-- Build context
print("\n3. Building LLM Context...")
print("   Scenario: Developer at src/main.lua:13 asking about validation")

local context, meta = ranker.build_context("What validation should I add here?", {
  current_file = test_root .. "/src/main.lua",
  cursor_line = 13,
  project_root = test_root,
  budget = 4000,
})

print("\n   CONTEXT METADATA:")
print(string.format("   - Estimated tokens: %d", meta.total_tokens or 0))
print(string.format("   - Chunks included: %d", meta.chunks_included or 0))
print("   - Sources:")
for _, s in ipairs(meta.sources or {}) do
  print(string.format("     * %s: %s", s.type, s.count or s.file or "yes"))
end

-- Show context preview
print("\n4. CONTEXT PREVIEW (what LLM sees):")
print("   " .. string.rep("-", 55))
local lines = vim.split(context, "\n")
for i = 1, math.min(60, #lines) do
  print("   " .. lines[i])
end
if #lines > 60 then
  print(string.format("   ... (%d more lines)", #lines - 60))
end
print("   " .. string.rep("-", 55))

-- Build full prompt
print("\n5. FULL LLM PROMPT:")
local prompts = require("editutor.prompts")
local sys = prompts.get_system_prompt("question")
local usr = prompts.build_user_prompt("What validation should I add here?", context, "question")

print("\n   System prompt: " .. #sys .. " chars (~" .. math.ceil(#sys/4) .. " tokens)")
print("   User prompt: " .. #usr .. " chars (~" .. math.ceil(#usr/4) .. " tokens)")
print("   Total: ~" .. math.ceil((#sys + #usr)/4) .. " tokens")

-- Cleanup
indexer._get_project_root = orig
vim.fn.delete(test_root, "rf")

print("\n" .. string.rep("=", 60))
print("  TEST COMPLETE")
print(string.rep("=", 60))
