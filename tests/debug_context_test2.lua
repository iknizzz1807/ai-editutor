-- Debug context test 2 - trace inside build_context
print("=== DEBUG CONTEXT TEST 2 ===")

local test_root = "/tmp/editutor_dbg2_" .. os.time()

-- Create files
local files = {
  ["src/main.lua"] = [[
local api = require("src.api")
local M = {}
function M.process(req)
  -- Q: What validation?
  return api.validate(req)
end
return M
]],
  ["src/api.lua"] = [[
local M = {}
function M.validate(request)
  if not request then error("nil") end
  return request
end
return M
]],
}

for path, content in pairs(files) do
  local full = test_root .. "/" .. path
  vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
  local f = io.open(full, "w")
  if f then f:write(content); f:close() end
end

-- Setup
local indexer = require("editutor.indexer")
local db = require("editutor.indexer.db")
local ranker = require("editutor.indexer.ranker")

local orig = indexer._get_project_root
indexer._get_project_root = function() return test_root end

indexer.setup()
indexer.index_project({ progress = function() end })

-- Patch ranker.search_and_rank to add debugging
local original_search_and_rank = ranker.search_and_rank
ranker.search_and_rank = function(query, opts)
  print("  [DEBUG] search_and_rank called with query:", query)
  local results = original_search_and_rank(query, opts)
  print("  [DEBUG] search_and_rank returned:", #results, "results")
  return results
end

print("\n1. Call build_context...")
local ctx, meta = ranker.build_context("What validation should I add?", {
  current_file = test_root .. "/src/main.lua",
  cursor_line = 4,
  project_root = test_root,
  budget = 2000,
})

print("\n2. Results:")
print("   Context length:", #ctx)
print("   Chunks included:", meta.chunks_included)
print("   Sources:")
for _, s in ipairs(meta.sources) do
  print("     -", s.type, s.count or s.file or "")
end

print("\n3. Context preview:")
local lines = vim.split(ctx, "\n")
for i = 1, math.min(30, #lines) do
  print("  ", lines[i])
end

-- Restore and cleanup
ranker.search_and_rank = original_search_and_rank
indexer._get_project_root = orig
vim.fn.delete(test_root, "rf")

print("\n=== DONE ===")
