-- Quick BM25 test
print("=== BM25 Search Test ===")

-- Setup paths
local test_root = "/tmp/editutor_bm25_" .. os.time()
vim.fn.mkdir(test_root, "p")

-- Load db module
local db = require("editutor.indexer.db")

-- Initialize
print("\n1. Initializing database...")
local ok, err = db.init(test_root)
print("   Result:", ok and "SUCCESS" or ("FAILED: " .. tostring(err)))

if not ok then
  print("ABORT: Database init failed")
  return
end

-- Insert test files and chunks
print("\n2. Inserting test data...")

local file_id = db.upsert_file({
  path = test_root .. "/api/client.lua",
  hash = "abc123",
  mtime = os.time(),
  language = "lua",
  line_count = 50,
})
print("   File ID:", file_id)

-- Insert chunks
local chunks = {
  { name = "validate_request", type = "function", content = "function validate_request(req) if not req then error('nil') end return req end" },
  { name = "connect_api", type = "function", content = "function connect_api(url) local conn = http.connect(url) return conn end" },
  { name = "send_message", type = "function", content = "function send_message(msg) validate(msg) return api.send(msg) end" },
  { name = "create_user", type = "function", content = "function create_user(data) if not data.email then return nil end return db.insert('users', data) end" },
  { name = "handle_error", type = "function", content = "function handle_error(err) log.error(err) notify_admin(err) end" },
}

for i, c in ipairs(chunks) do
  db.insert_chunk({
    file_id = file_id,
    type = c.type,
    name = c.name,
    signature = "function " .. c.name .. "()",
    start_line = i * 10,
    end_line = i * 10 + 5,
    content = c.content,
  })
end
print("   Inserted", #chunks, "chunks")

-- Test BM25 search
print("\n3. BM25 Search Results:")
print("   " .. string.rep("-", 50))

local queries = {
  "validate request",
  "connect api",
  "create user email",
  "handle error",
  "send message",
}

for _, q in ipairs(queries) do
  local results = db.search_bm25(q, { limit = 3 })
  print(string.format("\n   Query: '%s'", q))
  print(string.format("   Found: %d results", #results))

  for i, r in ipairs(results) do
    print(string.format("     %d. [score:%.2f] %s", i, r.score or 0, r.name or "?"))
  end
end

-- Stats
print("\n4. Database Statistics:")
local stats = db.get_stats()
print(string.format("   Files: %d", stats.file_count or 0))
print(string.format("   Chunks: %d", stats.chunk_count or 0))
print(string.format("   Imports: %d", stats.import_count or 0))

-- Cleanup
db.close()
vim.fn.delete(test_root, "rf")

print("\n=== TEST COMPLETE ===")
