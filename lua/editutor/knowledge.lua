-- editutor/knowledge.lua
-- Knowledge tracking - save and search Q&A history
-- Simplified version: JSON file storage only (no SQLite)

local M = {}

-- Storage state
local entries = nil
local storage_path = nil

---Get storage path
---@return string
local function get_storage_path()
  if storage_path then
    return storage_path
  end

  local data_dir = vim.fn.stdpath("data")
  storage_path = data_dir .. "/editutor/knowledge.json"

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(storage_path, ":h")
  vim.fn.mkdir(dir, "p")

  return storage_path
end

---Initialize JSON storage
---@return boolean success
local function init_storage()
  if entries then
    return true
  end

  local path = get_storage_path()

  -- Load existing entries
  if vim.fn.filereadable(path) == 1 then
    local content = vim.fn.readfile(path)
    local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
    if ok and data then
      entries = data
    else
      entries = {}
    end
  else
    entries = {}
  end

  return true
end

---Save entries to file
local function save_storage()
  if not storage_path or not entries then
    return
  end

  local ok, encoded = pcall(vim.json.encode, entries)
  if ok then
    vim.fn.writefile({ encoded }, storage_path)
  end
end

---@class KnowledgeEntry
---@field id number Entry ID
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
  init_storage()

  entry.timestamp = entry.timestamp or os.time()
  entry.id = #entries + 1

  -- Ensure tags is a table
  if type(entry.tags) == "string" then
    local ok, tags = pcall(vim.json.decode, entry.tags)
    if ok then
      entry.tags = tags
    else
      entry.tags = {}
    end
  end

  table.insert(entries, entry)
  save_storage()
  return true
end

---Search knowledge base
---@param query string Search query
---@param opts? table Options {limit?: number, mode?: string, language?: string}
---@return KnowledgeEntry[] results
function M.search(query, opts)
  opts = opts or {}
  local limit = opts.limit or 50

  init_storage()

  local results = {}
  query = query:lower()

  for _, entry in ipairs(entries or {}) do
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

  return results
end

---Get recent entries
---@param limit? number Number of entries (default 20)
---@return KnowledgeEntry[] results
function M.get_recent(limit)
  limit = limit or 20

  init_storage()

  local results = {}
  local start = math.max(1, #(entries or {}) - limit + 1)

  for i = #(entries or {}), start, -1 do
    table.insert(results, entries[i])
  end

  return results
end

---Get entry by ID
---@param id number Entry ID
---@return KnowledgeEntry|nil
function M.get(id)
  init_storage()

  for _, entry in ipairs(entries or {}) do
    if entry.id == id then
      return entry
    end
  end

  return nil
end

---Delete entry by ID
---@param id number Entry ID
---@return boolean success
function M.delete(id)
  init_storage()

  for i, entry in ipairs(entries or {}) do
    if entry.id == id then
      table.remove(entries, i)
      save_storage()
      return true
    end
  end

  return false
end

---Get statistics
---@return table stats
function M.get_stats()
  init_storage()

  local stats = {
    total = #(entries or {}),
    by_mode = {},
    by_language = {},
  }

  for _, entry in ipairs(entries or {}) do
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

  init_storage()

  local all_entries = M.get_recent(1000)

  if #all_entries == 0 then
    return false, "No entries to export"
  end

  local lines = {
    "# ai-editutor Knowledge Base",
    "",
    string.format("Exported: %s", os.date("%Y-%m-%d %H:%M:%S")),
    string.format("Total entries: %d", #all_entries),
    "",
    "---",
    "",
  }

  for _, entry in ipairs(all_entries) do
    table.insert(lines, string.format("## %s [%s]", (entry.mode or "Q"):upper(), os.date("%Y-%m-%d", entry.timestamp)))
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

---Clear all entries
function M.clear()
  entries = {}
  save_storage()
end

return M
