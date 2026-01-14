-- editutor/knowledge.lua
-- Knowledge tracking - save and search Q&A history

local M = {}

local config = require("editutor.config")

-- Database state
local db = nil
local db_path = nil

---Get database path
---@return string
local function get_db_path()
  if db_path then
    return db_path
  end

  local data_dir = vim.fn.stdpath("data")
  db_path = data_dir .. "/editutor/knowledge.db"

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(db_path, ":h")
  vim.fn.mkdir(dir, "p")

  return db_path
end

---Initialize SQLite database
---@return boolean success
---@return string|nil error
local function init_db()
  if db then
    return true, nil
  end

  -- Try to load sqlite.lua
  local ok, sqlite = pcall(require, "sqlite")
  if not ok then
    -- Fallback: use simple JSON file storage
    return M._init_json_storage()
  end

  local path = get_db_path()

  local success, result = pcall(function()
    db = sqlite({
      uri = path,
      entries = {
        id = true,
        timestamp = { "integer", required = true },
        mode = { "text", required = true },
        question = { "text", required = true },
        answer = { "text", required = true },
        language = { "text" },
        filepath = { "text" },
        tags = { "text" }, -- JSON array
      },
    })
  end)

  if not success then
    return M._init_json_storage()
  end

  return true, nil
end

-- JSON file storage fallback
local json_entries = nil
local json_path = nil

---Initialize JSON file storage (fallback when sqlite.lua not available)
---@return boolean success
---@return string|nil error
function M._init_json_storage()
  local data_dir = vim.fn.stdpath("data")
  json_path = data_dir .. "/editutor/knowledge.json"

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(json_path, ":h")
  vim.fn.mkdir(dir, "p")

  -- Load existing entries
  if vim.fn.filereadable(json_path) == 1 then
    local content = vim.fn.readfile(json_path)
    local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
    if ok and data then
      json_entries = data
    else
      json_entries = {}
    end
  else
    json_entries = {}
  end

  return true, nil
end

---Save JSON entries to file
local function save_json()
  if not json_path or not json_entries then
    return
  end

  local ok, encoded = pcall(vim.json.encode, json_entries)
  if ok then
    vim.fn.writefile({ encoded }, json_path)
  end
end

---@class KnowledgeEntry
---@field id number|string Entry ID
---@field timestamp number Unix timestamp
---@field mode string Interaction mode
---@field question string User's question
---@field answer string AI's response
---@field language string|nil Programming language
---@field filepath string|nil File path
---@field tags string[]|nil Tags

---Save a Q&A entry
---@param entry KnowledgeEntry
---@return boolean success
function M.save(entry)
  local ok, err = init_db()
  if not ok then
    vim.notify("[EduTutor] Knowledge tracking disabled: " .. (err or "unknown error"), vim.log.levels.WARN)
    return false
  end

  entry.timestamp = entry.timestamp or os.time()

  -- Convert tags to JSON string if table
  if type(entry.tags) == "table" then
    entry.tags = vim.json.encode(entry.tags)
  end

  if db then
    -- SQLite storage
    local success = pcall(function()
      db:insert(entry)
    end)
    return success
  else
    -- JSON storage
    entry.id = #json_entries + 1
    table.insert(json_entries, entry)
    save_json()
    return true
  end
end

---Search knowledge base
---@param query string Search query
---@param opts? table Options {limit?: number, mode?: string, language?: string}
---@return KnowledgeEntry[] results
function M.search(query, opts)
  opts = opts or {}
  local limit = opts.limit or 50

  local ok, _ = init_db()
  if not ok then
    return {}
  end

  local results = {}
  query = query:lower()

  if db then
    -- SQLite search
    local success, rows = pcall(function()
      return db:select({
        where = {
          question = { "like", "%" .. query .. "%" },
        },
        limit = limit,
      })
    end)

    if success and rows then
      results = rows
    end
  else
    -- JSON search
    for _, entry in ipairs(json_entries or {}) do
      local match = false

      -- Search in question
      if entry.question and entry.question:lower():find(query, 1, true) then
        match = true
      end

      -- Search in answer
      if not match and entry.answer and entry.answer:lower():find(query, 1, true) then
        match = true
      end

      -- Filter by mode
      if match and opts.mode and entry.mode ~= opts.mode then
        match = false
      end

      -- Filter by language
      if match and opts.language and entry.language ~= opts.language then
        match = false
      end

      if match then
        table.insert(results, entry)
        if #results >= limit then
          break
        end
      end
    end
  end

  -- Parse tags back to table
  for _, entry in ipairs(results) do
    if type(entry.tags) == "string" then
      local tag_ok, tags = pcall(vim.json.decode, entry.tags)
      if tag_ok then
        entry.tags = tags
      end
    end
  end

  return results
end

---Get recent entries
---@param limit? number Number of entries (default 20)
---@return KnowledgeEntry[] results
function M.get_recent(limit)
  limit = limit or 20

  local ok, _ = init_db()
  if not ok then
    return {}
  end

  local results = {}

  if db then
    local success, rows = pcall(function()
      return db:select({
        order_by = { desc = "timestamp" },
        limit = limit,
      })
    end)

    if success and rows then
      results = rows
    end
  else
    -- JSON: get last N entries
    local start = math.max(1, #(json_entries or {}) - limit + 1)
    for i = #(json_entries or {}), start, -1 do
      table.insert(results, json_entries[i])
    end
  end

  return results
end

---Get entry by ID
---@param id number|string Entry ID
---@return KnowledgeEntry|nil
function M.get(id)
  local ok, _ = init_db()
  if not ok then
    return nil
  end

  if db then
    local success, rows = pcall(function()
      return db:select({ where = { id = id }, limit = 1 })
    end)

    if success and rows and #rows > 0 then
      return rows[1]
    end
  else
    for _, entry in ipairs(json_entries or {}) do
      if entry.id == id then
        return entry
      end
    end
  end

  return nil
end

---Delete entry by ID
---@param id number|string Entry ID
---@return boolean success
function M.delete(id)
  local ok, _ = init_db()
  if not ok then
    return false
  end

  if db then
    local success = pcall(function()
      db:delete({ where = { id = id } })
    end)
    return success
  else
    for i, entry in ipairs(json_entries or {}) do
      if entry.id == id then
        table.remove(json_entries, i)
        save_json()
        return true
      end
    end
  end

  return false
end

---Get statistics
---@return table stats
function M.get_stats()
  local ok, _ = init_db()
  if not ok then
    return { total = 0, by_mode = {}, by_language = {} }
  end

  local stats = {
    total = 0,
    by_mode = {},
    by_language = {},
  }

  local entries = json_entries or {}

  if db then
    local success, rows = pcall(function()
      return db:select({})
    end)
    if success and rows then
      entries = rows
    end
  end

  stats.total = #entries

  for _, entry in ipairs(entries) do
    -- Count by mode
    local mode = entry.mode or "unknown"
    stats.by_mode[mode] = (stats.by_mode[mode] or 0) + 1

    -- Count by language
    local lang = entry.language or "unknown"
    stats.by_language[lang] = (stats.by_language[lang] or 0) + 1
  end

  return stats
end

---Export knowledge base to markdown
---@param filepath? string Output path (default: ~/editutor_export.md)
---@return boolean success
---@return string|nil error
function M.export_markdown(filepath)
  filepath = filepath or (os.getenv("HOME") .. "/editutor_export.md")

  local ok, _ = init_db()
  if not ok then
    return false, "Knowledge base not initialized"
  end

  local entries = M.get_recent(1000) -- Get up to 1000 entries

  if #entries == 0 then
    return false, "No entries to export"
  end

  local lines = {
    "# EduTutor Knowledge Base",
    "",
    string.format("Exported: %s", os.date("%Y-%m-%d %H:%M:%S")),
    string.format("Total entries: %d", #entries),
    "",
    "---",
    "",
  }

  for _, entry in ipairs(entries) do
    table.insert(lines, string.format("## %s [%s]", entry.mode:upper(), os.date("%Y-%m-%d", entry.timestamp)))
    table.insert(lines, "")

    if entry.language then
      table.insert(lines, string.format("**Language:** %s", entry.language))
    end

    if entry.filepath then
      table.insert(lines, string.format("**File:** `%s`", entry.filepath))
    end

    table.insert(lines, "")
    table.insert(lines, "**Question:**")
    table.insert(lines, entry.question)
    table.insert(lines, "")
    table.insert(lines, "**Answer:**")
    table.insert(lines, entry.answer)
    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "")
  end

  local write_ok = pcall(function()
    vim.fn.writefile(lines, filepath)
  end)

  if write_ok then
    return true, nil
  else
    return false, "Failed to write file"
  end
end

return M
