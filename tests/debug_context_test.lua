-- Debug context test
print("=== DEBUG CONTEXT TEST ===")

local test_root = "/tmp/editutor_dbg_" .. os.time()

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

-- Test indexer search
local indexer = require("editutor.indexer")
local db = require("editutor.indexer.db")
local ranker = require("editutor.indexer.ranker")

local orig = indexer._get_project_root
indexer._get_project_root = function() return test_root end

print("\n1. Setup indexer...")
local ok, err = indexer.setup()
print("   Setup:", ok, err)

print("\n2. Index project...")
local ok2, stats = indexer.index_project({ progress = function() end })
print("   Index:", ok2, stats and stats.files_indexed, stats and stats.chunks_created)

print("\n3. Direct DB search...")
local db_results = db.search_bm25("validate", { limit = 5 })
print("   DB search results:", type(db_results), #db_results)
for i, r in ipairs(db_results) do
  print("     ", i, r.name, r.score)
end

print("\n4. Ranker search_and_rank...")
local ranked = ranker.search_and_rank("validate", {
  limit = 5,
  current_file = test_root .. "/src/main.lua",
  project_root = test_root,
})
print("   Ranked results:", type(ranked), #ranked)
for i, r in ipairs(ranked) do
  print("     ", i, r.name, r.combined_score)
end

print("\n5. Build context...")
local ctx, meta = ranker.build_context("What validation?", {
  current_file = test_root .. "/src/main.lua",
  cursor_line = 4,
  project_root = test_root,
  budget = 2000,
})
print("   Context length:", #ctx)
print("   Chunks included:", meta.chunks_included)
print("   Sources:", vim.inspect(meta.sources))

-- Cleanup
indexer._get_project_root = orig
vim.fn.delete(test_root, "rf")

print("\n=== DONE ===")
