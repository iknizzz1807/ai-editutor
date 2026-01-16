-- editutor/knowledge.lua
-- Knowledge tracking - save and search Q&A history
-- Storage: One JSON file per day in knowledge/ folder

local M = {}

-- Configuration
M.config = {
  search_days = 30, -- How many days to search by default
  recent_days = 7, -- How many days to show in recent
}

-- Storage state
local storage_dir = nil

---Get storage directory path
---@return string
local function get_storage_dir()
  if storage_dir then
    return storage_dir
  end

  local data_dir = vim.fn.stdpath("data")
  storage_dir = data_dir .. "/editutor/knowledge"

  -- Ensure directory exists
  vim.fn.mkdir(storage_dir, "p")

  return storage_dir
end

---Get file path for a specific date
---@param date? string Date in YYYY-MM-DD format (default: today)
---@return string
local function get_date_file(date)
  date = date or os.date("%Y-%m-%d")
  return get_storage_dir() .. "/" .. date .. ".json"
end

---Load entries from a specific date file
---@param date string Date in YYYY-MM-DD format
---@return table[] entries
local function load_date_entries(date)
  local filepath = get_date_file(date)

  if vim.fn.filereadable(filepath) ~= 1 then
    return {}
  end

  local content = vim.fn.readfile(filepath)
  local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))

  if ok and type(data) == "table" then
    return data
  end

  return {}
end

---Save entries to a specific date file
---@param date string Date in YYYY-MM-DD format
---@param entries table[] Entries to save
local function save_date_entries(date, entries)
  local filepath = get_date_file(date)
  local ok, encoded = pcall(vim.json.encode, entries)

  if ok then
    vim.fn.writefile({ encoded }, filepath)
  end
end

---Get list of available date files (sorted newest first)
---@param limit? number Max number of files to return
---@return string[] dates List of dates (YYYY-MM-DD format)
local function get_available_dates(limit)
  local dir = get_storage_dir()
  local files = vim.fn.glob(dir .. "/*.json", false, true)
  local dates = {}

  for _, filepath in ipairs(files) do
    local filename = vim.fn.fnamemodify(filepath, ":t:r")
    -- Validate date format (YYYY-MM-DD)
    if filename:match("^%d%d%d%d%-%d%d%-%d%d$") then
      table.insert(dates, filename)
    end
  end

  -- Sort newest first
  table.sort(dates, function(a, b)
    return a > b
  end)

  if limit and limit > 0 then
    local limited = {}
    for i = 1, math.min(limit, #dates) do
      table.insert(limited, dates[i])
    end
    return limited
  end

  return dates
end

---@class KnowledgeEntry
---@field id string Entry ID (date-based: YYYY-MM-DD-NNNN)
---@field timestamp number Unix timestamp
---@field mode string Interaction mode ("question" or "code")
---@field question string User's question
---@field answer string AI's response
---@field language string|nil Programming language
---@field filepath string|nil File path
---@field tags string[]|nil Tags

---Save a Q&A entry
---@param entry KnowledgeEntry
---@return boolean success
function M.save(entry)
  local today = os.date("%Y-%m-%d")
  local entries = load_date_entries(today)

  entry.timestamp = entry.timestamp or os.time()

  -- Generate ID: YYYY-MM-DD-NNNN
  entry.id = string.format("%s-%04d", today, #entries + 1)

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
  save_date_entries(today, entries)

  return true
end

---Search knowledge base across multiple days
---@param query string Search query
---@param opts? table Options {limit?: number, mode?: string, language?: string, days?: number}
---@return KnowledgeEntry[] results
function M.search(query, opts)
  opts = opts or {}
  local limit = opts.limit or 50
  local days = opts.days or M.config.search_days

  local dates = get_available_dates(days)
  local results = {}
  query = query:lower()

  for _, date in ipairs(dates) do
    local entries = load_date_entries(date)

    for _, entry in ipairs(entries) do
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
          return results
        end
      end
    end
  end

  return results
end

---Get recent entries from recent days
---@param limit? number Number of entries (default 20)
---@return KnowledgeEntry[] results
function M.get_recent(limit)
  limit = limit or 20

  local dates = get_available_dates(M.config.recent_days)
  local results = {}

  for _, date in ipairs(dates) do
    local entries = load_date_entries(date)

    -- Add entries in reverse order (newest first)
    for i = #entries, 1, -1 do
      table.insert(results, entries[i])
      if #results >= limit then
        return results
      end
    end
  end

  return results
end

---Get entries for a specific date
---@param date string Date in YYYY-MM-DD format
---@return KnowledgeEntry[] entries
function M.get_by_date(date)
  return load_date_entries(date)
end

---Get entry by ID
---@param id string Entry ID (YYYY-MM-DD-NNNN format)
---@return KnowledgeEntry|nil
function M.get(id)
  -- Extract date from ID
  local date = id:match("^(%d%d%d%d%-%d%d%-%d%d)")
  if not date then
    return nil
  end

  local entries = load_date_entries(date)
  for _, entry in ipairs(entries) do
    if entry.id == id then
      return entry
    end
  end

  return nil
end

---Delete entry by ID
---@param id string Entry ID
---@return boolean success
function M.delete(id)
  -- Extract date from ID
  local date = id:match("^(%d%d%d%d%-%d%d%-%d%d)")
  if not date then
    return false
  end

  local entries = load_date_entries(date)
  for i, entry in ipairs(entries) do
    if entry.id == id then
      table.remove(entries, i)
      save_date_entries(date, entries)
      return true
    end
  end

  return false
end

---Get statistics
---@return table stats
function M.get_stats()
  local dates = get_available_dates()

  local stats = {
    total = 0,
    days = #dates,
    by_mode = {},
    by_language = {},
    by_date = {},
  }

  for _, date in ipairs(dates) do
    local entries = load_date_entries(date)
    stats.by_date[date] = #entries
    stats.total = stats.total + #entries

    for _, entry in ipairs(entries) do
      -- Count by mode
      local mode = entry.mode or "unknown"
      stats.by_mode[mode] = (stats.by_mode[mode] or 0) + 1

      -- Count by language
      local lang = entry.language or "unknown"
      stats.by_language[lang] = (stats.by_language[lang] or 0) + 1
    end
  end

  return stats
end

---Export knowledge base to markdown
---@param filepath? string Output path (default: ~/editutor_export.md)
---@param opts? table Options {days?: number}
---@return boolean success
---@return string|nil error
function M.export_markdown(filepath, opts)
  filepath = filepath or (os.getenv("HOME") .. "/editutor_export.md")
  opts = opts or {}
  local days = opts.days or 30

  local dates = get_available_dates(days)

  if #dates == 0 then
    return false, "No entries to export"
  end

  local lines = {
    "# ai-editutor Knowledge Base",
    "",
    string.format("Exported: %s", os.date("%Y-%m-%d %H:%M:%S")),
    string.format("Days included: %d", #dates),
    "",
    "---",
    "",
  }

  local total_entries = 0

  for _, date in ipairs(dates) do
    local entries = load_date_entries(date)

    if #entries > 0 then
      table.insert(lines, string.format("# %s", date))
      table.insert(lines, "")

      for _, entry in ipairs(entries) do
        total_entries = total_entries + 1

        local mode_label = (entry.mode == "code") and "C" or "Q"
        table.insert(lines, string.format("## %s: %s", mode_label, entry.question:sub(1, 60)))
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
    end
  end

  -- Update total count in header
  lines[4] = string.format("Total entries: %d", total_entries)

  local write_ok = pcall(function()
    vim.fn.writefile(lines, filepath)
  end)

  if write_ok then
    return true, nil
  else
    return false, "Failed to write file"
  end
end

---Clear entries for a specific date
---@param date string Date in YYYY-MM-DD format
function M.clear_date(date)
  local filepath = get_date_file(date)
  if vim.fn.filereadable(filepath) == 1 then
    vim.fn.delete(filepath)
  end
end

---Clear all entries
function M.clear()
  local dates = get_available_dates()
  for _, date in ipairs(dates) do
    M.clear_date(date)
  end
end

---Get available dates (for UI)
---@return string[] dates
function M.get_dates()
  return get_available_dates()
end

return M
