-- editutor/indexer/db.lua
-- SQLite database with FTS5 for BM25 search

local M = {}

local db = nil
local db_path = nil

-- Schema version for migrations
M.SCHEMA_VERSION = 2

---Get database path for project
---@param project_root string
---@return string
local function get_db_path(project_root)
  local data_dir = vim.fn.stdpath("data")
  -- Use hash of project root for unique db per project
  local project_hash = vim.fn.sha256(project_root):sub(1, 16)
  return data_dir .. "/editutor/index_" .. project_hash .. ".db"
end

---Initialize database connection
---@param project_root string
---@return boolean success
---@return string|nil error
function M.init(project_root)
  if db then
    return true, nil
  end

  -- Try to load sqlite.lua
  local ok, sqlite = pcall(require, "sqlite.db")
  if not ok then
    return false, "sqlite.lua is required for indexing. Install kkharji/sqlite.lua"
  end

  db_path = get_db_path(project_root)

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(db_path, ":h")
  vim.fn.mkdir(dir, "p")

  -- Open database
  local success, result = pcall(function()
    return sqlite:open(db_path)
  end)

  if not success then
    return false, "Failed to open database: " .. tostring(result)
  end

  db = result

  -- Run migrations
  local mig_ok, mig_err = M._run_migrations()
  if not mig_ok then
    return false, "Migration failed: " .. (mig_err or "unknown")
  end

  return true, nil
end

---Run database migrations
---@return boolean success
---@return string|nil error
function M._run_migrations()
  if not db then
    return false, "Database not initialized"
  end

  -- Get current version
  local version = 0
  local ok = pcall(function()
    local result = db:eval("SELECT version FROM schema_version LIMIT 1")
    if result and result[1] then
      version = result[1].version
    end
  end)

  if not ok then
    -- Schema version table doesn't exist, create from scratch
    version = 0
  end

  -- Apply migrations
  if version < 1 then
    local schema_ok = M._apply_schema_v1()
    if not schema_ok then
      return false, "Failed to apply schema v1"
    end
  end

  if version < 2 then
    local schema_ok = M._apply_schema_v2()
    if not schema_ok then
      return false, "Failed to apply schema v2"
    end
  end

  return true, nil
end

---Apply schema version 1
---@return boolean success
function M._apply_schema_v1()
  local statements = {
    -- Schema version tracking
    [[
    CREATE TABLE IF NOT EXISTS schema_version (
      version INTEGER PRIMARY KEY
    )
    ]],

    -- Files table
    [[
    CREATE TABLE IF NOT EXISTS files (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      path TEXT UNIQUE NOT NULL,
      hash TEXT,
      mtime INTEGER,
      language TEXT,
      last_indexed INTEGER,
      last_accessed INTEGER,
      line_count INTEGER
    )
    ]],

    -- Chunks table (AST-based)
    [[
    CREATE TABLE IF NOT EXISTS chunks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
      type TEXT NOT NULL,
      name TEXT,
      signature TEXT,
      start_line INTEGER NOT NULL,
      end_line INTEGER NOT NULL,
      content TEXT NOT NULL,
      scope_path TEXT,
      UNIQUE(file_id, start_line, end_line)
    )
    ]],

    -- Imports table for import graph
    [[
    CREATE TABLE IF NOT EXISTS imports (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
      imported_name TEXT NOT NULL,
      imported_from TEXT,
      line_number INTEGER,
      UNIQUE(file_id, imported_name, imported_from)
    )
    ]],

    -- Indexes for fast lookup
    [[CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)]],
    [[CREATE INDEX IF NOT EXISTS idx_files_hash ON files(hash)]],
    [[CREATE INDEX IF NOT EXISTS idx_chunks_file ON chunks(file_id)]],
    [[CREATE INDEX IF NOT EXISTS idx_chunks_name ON chunks(name)]],
    [[CREATE INDEX IF NOT EXISTS idx_chunks_type ON chunks(type)]],
    [[CREATE INDEX IF NOT EXISTS idx_imports_name ON imports(imported_name)]],
    [[CREATE INDEX IF NOT EXISTS idx_imports_file ON imports(file_id)]],

    -- FTS5 virtual table for BM25 search
    [[
    CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
      name,
      signature,
      content,
      content='chunks',
      content_rowid='id',
      tokenize='porter unicode61'
    )
    ]],

    -- Triggers to keep FTS in sync
    [[
    CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
      INSERT INTO chunks_fts(rowid, name, signature, content)
      VALUES (NEW.id, NEW.name, NEW.signature, NEW.content);
    END
    ]],

    [[
    CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
      INSERT INTO chunks_fts(chunks_fts, rowid, name, signature, content)
      VALUES ('delete', OLD.id, OLD.name, OLD.signature, OLD.content);
    END
    ]],

    [[
    CREATE TRIGGER IF NOT EXISTS chunks_au AFTER UPDATE ON chunks BEGIN
      INSERT INTO chunks_fts(chunks_fts, rowid, name, signature, content)
      VALUES ('delete', OLD.id, OLD.name, OLD.signature, OLD.content);
      INSERT INTO chunks_fts(rowid, name, signature, content)
      VALUES (NEW.id, NEW.name, NEW.signature, NEW.content);
    END
    ]],

    -- Set schema version
    [[INSERT OR REPLACE INTO schema_version (version) VALUES (1)]],
  }

  for _, sql in ipairs(statements) do
    local ok = pcall(function()
      db:eval(sql)
    end)
    if not ok then
      -- Some statements may fail (e.g., IF NOT EXISTS already exists)
      -- Continue anyway
    end
  end

  return true
end

---Apply schema version 2 (call graph & type refs)
---@return boolean success
function M._apply_schema_v2()
  local statements = {
    -- Call graph table (which function calls which)
    [[
    CREATE TABLE IF NOT EXISTS calls (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      chunk_id INTEGER NOT NULL REFERENCES chunks(id) ON DELETE CASCADE,
      called_name TEXT NOT NULL,
      UNIQUE(chunk_id, called_name)
    )
    ]],

    -- Type references table
    [[
    CREATE TABLE IF NOT EXISTS type_refs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      chunk_id INTEGER NOT NULL REFERENCES chunks(id) ON DELETE CASCADE,
      type_name TEXT NOT NULL,
      UNIQUE(chunk_id, type_name)
    )
    ]],

    -- Add docstring column to chunks (if not exists)
    [[
    ALTER TABLE chunks ADD COLUMN docstring TEXT
    ]],

    -- Indexes for call graph queries
    [[CREATE INDEX IF NOT EXISTS idx_calls_chunk ON calls(chunk_id)]],
    [[CREATE INDEX IF NOT EXISTS idx_calls_name ON calls(called_name)]],
    [[CREATE INDEX IF NOT EXISTS idx_type_refs_chunk ON type_refs(chunk_id)]],
    [[CREATE INDEX IF NOT EXISTS idx_type_refs_name ON type_refs(type_name)]],

    -- Update schema version
    [[INSERT OR REPLACE INTO schema_version (version) VALUES (2)]],
  }

  for _, sql in ipairs(statements) do
    pcall(function()
      db:eval(sql)
    end)
  end

  return true
end

-- =============================================================================
-- File Operations
-- =============================================================================

---Insert or update a file record
---@param file table {path, hash, mtime, language, line_count}
---@return number|nil file_id
function M.upsert_file(file)
  if not db then
    return nil
  end

  local ok = pcall(function()
    db:eval([[
      INSERT INTO files (path, hash, mtime, language, last_indexed, line_count)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(path) DO UPDATE SET
        hash = excluded.hash,
        mtime = excluded.mtime,
        language = excluded.language,
        last_indexed = excluded.last_indexed,
        line_count = excluded.line_count
    ]], {
      file.path,
      file.hash,
      file.mtime,
      file.language,
      os.time(),
      file.line_count,
    })
  end)

  if not ok then
    return nil
  end

  -- Get file ID
  local result = db:eval("SELECT id FROM files WHERE path = ?", { file.path })
  if result and result[1] then
    return result[1].id
  end

  return nil
end

---Check if file is up to date
---@param filepath string
---@param hash string
---@return boolean
function M.is_up_to_date(filepath, hash)
  if not db then
    return false
  end

  local ok, result = pcall(function()
    return db:eval("SELECT hash FROM files WHERE path = ?", { filepath })
  end)

  if ok and type(result) == "table" and result[1] then
    return result[1].hash == hash
  end

  return false
end

---Remove a file and its chunks/imports
---@param filepath string
function M.remove_file(filepath)
  if not db then
    return
  end

  db:eval("DELETE FROM files WHERE path = ?", { filepath })
end

---Mark file as recently accessed
---@param filepath string
function M.mark_accessed(filepath)
  if not db then
    return
  end

  db:eval("UPDATE files SET last_accessed = ? WHERE path = ?", { os.time(), filepath })
end

---Get file by path
---@param filepath string
---@return table|nil
function M.get_file(filepath)
  if not db then
    return nil
  end

  local ok, result = pcall(function()
    return db:eval("SELECT * FROM files WHERE path = ?", { filepath })
  end)

  if ok and type(result) == "table" and result[1] then
    return result[1]
  end

  return nil
end

-- =============================================================================
-- Chunk Operations
-- =============================================================================

---Insert a chunk
---@param chunk table {file_id, type, name, signature, start_line, end_line, content, scope_path}
---@return number|nil chunk_id
function M.insert_chunk(chunk)
  if not db then
    return nil
  end

  local ok = pcall(function()
    db:eval([[
      INSERT OR REPLACE INTO chunks
        (file_id, type, name, signature, start_line, end_line, content, scope_path)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
      chunk.file_id,
      chunk.type,
      chunk.name,
      chunk.signature,
      chunk.start_line,
      chunk.end_line,
      chunk.content,
      chunk.scope_path,
    })
  end)

  return ok and db:eval("SELECT last_insert_rowid()")[1]["last_insert_rowid()"] or nil
end

---Remove all chunks for a file
---@param file_id number
function M.remove_chunks(file_id)
  if not db then
    return
  end

  db:eval("DELETE FROM chunks WHERE file_id = ?", { file_id })
end

---Get chunks for a file
---@param file_id number
---@return table[]
function M.get_file_chunks(file_id)
  if not db then
    return {}
  end

  return db:eval("SELECT * FROM chunks WHERE file_id = ? ORDER BY start_line", { file_id }) or {}
end

---Get chunk count
---@return number
function M.get_chunk_count()
  if not db then
    return 0
  end

  local result = db:eval("SELECT COUNT(*) as count FROM chunks")
  return result and result[1] and result[1].count or 0
end

-- =============================================================================
-- Import Operations
-- =============================================================================

---Insert an import
---@param import table {file_id, imported_name, imported_from, line_number}
function M.insert_import(import)
  if not db then
    return
  end

  pcall(function()
    db:eval([[
      INSERT OR IGNORE INTO imports (file_id, imported_name, imported_from, line_number)
      VALUES (?, ?, ?, ?)
    ]], {
      import.file_id,
      import.imported_name,
      import.imported_from,
      import.line_number,
    })
  end)
end

---Remove all imports for a file
---@param file_id number
function M.remove_imports(file_id)
  if not db then
    return
  end

  db:eval("DELETE FROM imports WHERE file_id = ?", { file_id })
end

---Get files that import a name
---@param imported_name string
---@return table[]
function M.get_importers(imported_name)
  if not db then
    return {}
  end

  local ok, result = pcall(function()
    return db:eval([[
      SELECT f.path, i.line_number
      FROM imports i
      JOIN files f ON f.id = i.file_id
      WHERE i.imported_name = ?
    ]], { imported_name })
  end)

  if ok and type(result) == "table" then
    return result
  end
  return {}
end

-- =============================================================================
-- BM25 Search
-- =============================================================================

---Search chunks using BM25 (FTS5)
---@param query string Search query
---@param opts? table {limit?: number}
---@return table[] results with {chunk_id, file_path, name, type, score, ...}
function M.search_bm25(query, opts)
  if not db then
    return {}
  end

  opts = opts or {}
  local limit = opts.limit or 20

  -- Escape special FTS5 characters (including ? which is special in FTS5)
  local escaped_query = query:gsub('[%-%+%*%"%(%)?:^~]', function(c)
    return " "
  end)

  -- Build query terms for OR matching
  local terms = {}
  for word in escaped_query:gmatch("%S+") do
    if #word > 1 then
      table.insert(terms, word .. "*") -- Prefix matching
    end
  end

  if #terms == 0 then
    return {}
  end

  local fts_query = table.concat(terms, " OR ")

  local ok, result = pcall(function()
    return db:eval([[
      SELECT
        c.id,
        c.file_id,
        c.type,
        c.name,
        c.signature,
        c.start_line,
        c.end_line,
        c.content,
        c.scope_path,
        f.path as file_path,
        f.language,
        bm25(chunks_fts, 10.0, 5.0, 1.0) as score
      FROM chunks_fts
      JOIN chunks c ON c.id = chunks_fts.rowid
      JOIN files f ON f.id = c.file_id
      WHERE chunks_fts MATCH ?
      ORDER BY score
      LIMIT ?
    ]], { fts_query, limit })
  end)

  if ok and type(result) == "table" then
    return result
  end
  return {}
end

---Search by exact name
---@param name string
---@return table[]
function M.search_by_name(name)
  if not db then
    return {}
  end

  local ok, result = pcall(function()
    return db:eval([[
      SELECT c.*, f.path as file_path, f.language
      FROM chunks c
      JOIN files f ON f.id = c.file_id
      WHERE c.name = ?
    ]], { name })
  end)

  if ok and type(result) == "table" then
    return result
  end
  return {}
end

-- =============================================================================
-- Call Graph Operations
-- =============================================================================

---Insert a function call relationship
---@param chunk_id number
---@param called_name string
function M.insert_call(chunk_id, called_name)
  if not db then
    return
  end

  pcall(function()
    db:eval([[
      INSERT OR IGNORE INTO calls (chunk_id, called_name)
      VALUES (?, ?)
    ]], { chunk_id, called_name })
  end)
end

---Remove all calls for a chunk
---@param chunk_id number
function M.remove_calls(chunk_id)
  if not db then
    return
  end

  pcall(function()
    db:eval("DELETE FROM calls WHERE chunk_id = ?", { chunk_id })
  end)
end

---Get chunks that call a specific function
---@param function_name string
---@return table[] callers
function M.get_callers(function_name)
  if not db then
    return {}
  end

  local ok, result = pcall(function()
    return db:eval([[
      SELECT c.*, f.path as file_path, f.language
      FROM calls cl
      JOIN chunks c ON c.id = cl.chunk_id
      JOIN files f ON f.id = c.file_id
      WHERE cl.called_name = ? OR cl.called_name LIKE ?
    ]], { function_name, "%." .. function_name })
  end)

  if ok and type(result) == "table" then
    return result
  end
  return {}
end

---Get functions called by a chunk
---@param chunk_id number
---@return table[] callees
function M.get_callees(chunk_id)
  if not db then
    return {}
  end

  local ok, result = pcall(function()
    return db:eval([[
      SELECT c.*, f.path as file_path, f.language
      FROM calls cl
      JOIN chunks c ON c.name = cl.called_name OR c.name LIKE '%.' || cl.called_name
      JOIN files f ON f.id = c.file_id
      WHERE cl.chunk_id = ?
    ]], { chunk_id })
  end)

  if ok and type(result) == "table" then
    return result
  end
  return {}
end

---Get call names for a chunk
---@param chunk_id number
---@return string[] called_names
function M.get_call_names(chunk_id)
  if not db then
    return {}
  end

  local ok, result = pcall(function()
    return db:eval("SELECT called_name FROM calls WHERE chunk_id = ?", { chunk_id })
  end)

  if ok and type(result) == "table" then
    local names = {}
    for _, r in ipairs(result) do
      table.insert(names, r.called_name)
    end
    return names
  end
  return {}
end

-- =============================================================================
-- Type Reference Operations
-- =============================================================================

---Insert a type reference
---@param chunk_id number
---@param type_name string
function M.insert_type_ref(chunk_id, type_name)
  if not db then
    return
  end

  pcall(function()
    db:eval([[
      INSERT OR IGNORE INTO type_refs (chunk_id, type_name)
      VALUES (?, ?)
    ]], { chunk_id, type_name })
  end)
end

---Remove all type refs for a chunk
---@param chunk_id number
function M.remove_type_refs(chunk_id)
  if not db then
    return
  end

  pcall(function()
    db:eval("DELETE FROM type_refs WHERE chunk_id = ?", { chunk_id })
  end)
end

---Get chunks that reference a type
---@param type_name string
---@return table[]
function M.get_type_users(type_name)
  if not db then
    return {}
  end

  local ok, result = pcall(function()
    return db:eval([[
      SELECT c.*, f.path as file_path, f.language
      FROM type_refs tr
      JOIN chunks c ON c.id = tr.chunk_id
      JOIN files f ON f.id = c.file_id
      WHERE tr.type_name = ?
    ]], { type_name })
  end)

  if ok and type(result) == "table" then
    return result
  end
  return {}
end

---Get type definitions (chunks that define a type)
---@param type_name string
---@return table[]
function M.get_type_definition(type_name)
  if not db then
    return {}
  end

  local ok, result = pcall(function()
    return db:eval([[
      SELECT c.*, f.path as file_path, f.language
      FROM chunks c
      JOIN files f ON f.id = c.file_id
      WHERE c.name = ?
      AND c.type IN ('type_alias_declaration', 'interface_declaration',
                     'class_declaration', 'struct_item', 'enum_item',
                     'type_declaration', 'enum_declaration')
    ]], { type_name })
  end)

  if ok and type(result) == "table" then
    return result
  end
  return {}
end

-- =============================================================================
-- Statistics & Utilities
-- =============================================================================

---Get database statistics
---@return table
function M.get_stats()
  if not db then
    return { initialized = false }
  end

  local file_count = db:eval("SELECT COUNT(*) as count FROM files")
  local chunk_count = db:eval("SELECT COUNT(*) as count FROM chunks")
  local import_count = db:eval("SELECT COUNT(*) as count FROM imports")

  local type_counts = db:eval([[
    SELECT type, COUNT(*) as count
    FROM chunks
    GROUP BY type
    ORDER BY count DESC
  ]]) or {}

  local lang_counts = db:eval([[
    SELECT language, COUNT(*) as count
    FROM files
    GROUP BY language
    ORDER BY count DESC
  ]]) or {}

  return {
    initialized = true,
    db_path = db_path,
    file_count = file_count and file_count[1] and file_count[1].count or 0,
    chunk_count = chunk_count and chunk_count[1] and chunk_count[1].count or 0,
    import_count = import_count and import_count[1] and import_count[1].count or 0,
    by_type = type_counts,
    by_language = lang_counts,
  }
end

---Clear all data
function M.clear_all()
  if not db then
    return
  end

  db:eval("DELETE FROM imports")
  db:eval("DELETE FROM chunks")
  db:eval("DELETE FROM files")
  db:eval("DELETE FROM chunks_fts")
end

---Get recently accessed files
---@param limit? number
---@return table[]
function M.get_recent_files(limit)
  if not db then
    return {}
  end

  return db:eval([[
    SELECT * FROM files
    WHERE last_accessed IS NOT NULL
    ORDER BY last_accessed DESC
    LIMIT ?
  ]], { limit or 10 }) or {}
end

---Get recently modified files (by mtime)
---@param limit? number
---@return table[]
function M.get_recently_modified(limit)
  if not db then
    return {}
  end

  return db:eval([[
    SELECT * FROM files
    ORDER BY mtime DESC
    LIMIT ?
  ]], { limit or 10 }) or {}
end

---Close database connection
function M.close()
  if db then
    db:close()
    db = nil
  end
end

return M
