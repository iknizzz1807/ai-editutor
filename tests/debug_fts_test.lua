-- Debug FTS5 query
print("=== DEBUG FTS5 QUERY ===")

local test_root = "/tmp/editutor_fts_" .. os.time()
vim.fn.mkdir(test_root, "p")

local db = require("editutor.indexer.db")
db.init(test_root)

-- Insert test data
local file_id = db.upsert_file({
  path = test_root .. "/test.lua",
  hash = "abc",
  mtime = os.time(),
  language = "lua",
  line_count = 10,
})

db.insert_chunk({
  file_id = file_id,
  type = "function",
  name = "validate",
  signature = "function validate()",
  start_line = 1,
  end_line = 5,
  content = "function validate(request) if not request then error('nil') end return request end",
})

-- Test different queries
local queries = {
  "validate",
  "validation",
  "request",
  "What validation",
  "What validation should I add?",
  "validation request",
}

for _, q in ipairs(queries) do
  -- Build FTS5 query manually (same logic as db.search_bm25)
  local escaped = q:gsub('[%-%+%*%"%(%)]', " ")
  local terms = {}
  for word in escaped:gmatch("%S+") do
    if #word > 1 then
      table.insert(terms, word .. "*")
    end
  end
  local fts_query = table.concat(terms, " OR ")

  local results = db.search_bm25(q, { limit = 5 })

  print(string.format("\nQuery: '%s'", q))
  print(string.format("  FTS5 query: '%s'", fts_query))
  print(string.format("  Results: %d", #results))
  for i, r in ipairs(results) do
    print(string.format("    %d. %s (score: %.6f)", i, r.name, r.score or 0))
  end
end

db.close()
vim.fn.delete(test_root, "rf")

print("\n=== DONE ===")
