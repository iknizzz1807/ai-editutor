-- editutor/cache.lua
-- LRU cache with TTL and autocmd-based invalidation for context data

local M = {}

-- Cache configuration
M.config = {
  max_entries = 100, -- Maximum cache entries
  default_ttl = 300, -- Default TTL in seconds (5 minutes)
  context_ttl = 60, -- Context cache TTL (1 minute)
  lsp_ttl = 120, -- LSP results TTL (2 minutes)
}

-- Cache storage
M._cache = {}
M._access_order = {} -- For LRU tracking
M._autocmd_group = nil

---@class CacheEntry
---@field value any Cached value
---@field expires number Expiration timestamp
---@field key string Cache key
---@field tags string[] Tags for bulk invalidation

---Initialize cache and setup autocmds
function M.setup()
  if M._autocmd_group then
    return -- Already setup
  end

  M._autocmd_group = vim.api.nvim_create_augroup("EduTutorCache", { clear = true })

  -- Invalidate file-specific cache on file save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = M._autocmd_group,
    callback = function(ev)
      M.invalidate_by_tag("file:" .. ev.file)
    end,
  })

  -- Invalidate LSP cache when LSP restarts
  vim.api.nvim_create_autocmd("LspAttach", {
    group = M._autocmd_group,
    callback = function(ev)
      M.invalidate_by_tag("lsp")
    end,
  })

  -- Invalidate on buffer changes (debounced via TextChanged not TextChangedI)
  vim.api.nvim_create_autocmd("TextChanged", {
    group = M._autocmd_group,
    callback = function(ev)
      local filepath = vim.api.nvim_buf_get_name(ev.buf)
      if filepath ~= "" then
        M.invalidate_by_tag("file:" .. filepath)
      end
    end,
  })

  -- Periodic cleanup of expired entries
  vim.fn.timer_start(60000, function()
    vim.schedule(function()
      M.cleanup_expired()
    end)
  end, { ["repeat"] = -1 })
end

---Generate cache key from components
---@param ... any Key components
---@return string key
function M.make_key(...)
  local parts = { ... }
  local key_parts = {}

  for _, part in ipairs(parts) do
    if type(part) == "table" then
      table.insert(key_parts, vim.inspect(part))
    else
      table.insert(key_parts, tostring(part))
    end
  end

  return table.concat(key_parts, ":")
end

---Get value from cache
---@param key string Cache key
---@return any|nil value
---@return boolean hit Whether cache hit
function M.get(key)
  local entry = M._cache[key]

  if not entry then
    return nil, false
  end

  -- Check expiration (use <= to ensure TTL=0 expires immediately)
  if entry.expires <= os.time() then
    M._remove_entry(key)
    return nil, false
  end

  -- Update access order (LRU)
  M._touch(key)

  return entry.value, true
end

---Set value in cache
---@param key string Cache key
---@param value any Value to cache
---@param opts? table {ttl?: number, tags?: string[]}
function M.set(key, value, opts)
  opts = opts or {}
  local ttl = opts.ttl or M.config.default_ttl
  local tags = opts.tags or {}

  -- Evict if at capacity
  if vim.tbl_count(M._cache) >= M.config.max_entries then
    M._evict_lru()
  end

  M._cache[key] = {
    value = value,
    expires = os.time() + ttl,
    key = key,
    tags = tags,
  }

  M._touch(key)
end

---Get or compute value
---@param key string Cache key
---@param compute function Function to compute value if not cached
---@param opts? table {ttl?: number, tags?: string[]}
---@return any value
function M.get_or_compute(key, compute, opts)
  local value, hit = M.get(key)

  if hit then
    return value
  end

  value = compute()
  M.set(key, value, opts)

  return value
end

---Async get or compute
---@param key string Cache key
---@param compute function Async function(callback) to compute value
---@param callback function Callback(value) with result
---@param opts? table {ttl?: number, tags?: string[]}
function M.get_or_compute_async(key, compute, callback, opts)
  local value, hit = M.get(key)

  if hit then
    callback(value)
    return
  end

  compute(function(computed_value)
    M.set(key, computed_value, opts)
    callback(computed_value)
  end)
end

---Invalidate specific key
---@param key string Cache key
function M.invalidate(key)
  M._remove_entry(key)
end

---Invalidate all entries with a specific tag
---@param tag string Tag to match
function M.invalidate_by_tag(tag)
  local to_remove = {}

  for key, entry in pairs(M._cache) do
    if entry.tags then
      for _, t in ipairs(entry.tags) do
        if t == tag then
          table.insert(to_remove, key)
          break
        end
      end
    end
  end

  for _, key in ipairs(to_remove) do
    M._remove_entry(key)
  end
end

---Invalidate entries matching a pattern
---@param pattern string Lua pattern
function M.invalidate_by_pattern(pattern)
  local to_remove = {}

  for key, _ in pairs(M._cache) do
    if key:match(pattern) then
      table.insert(to_remove, key)
    end
  end

  for _, key in ipairs(to_remove) do
    M._remove_entry(key)
  end
end

---Clear all cache entries
function M.clear()
  M._cache = {}
  M._access_order = {}
end

---Remove expired entries
function M.cleanup_expired()
  local now = os.time()
  local to_remove = {}

  for key, entry in pairs(M._cache) do
    if entry.expires < now then
      table.insert(to_remove, key)
    end
  end

  for _, key in ipairs(to_remove) do
    M._remove_entry(key)
  end
end

---Get cache statistics
---@return table stats
function M.get_stats()
  local now = os.time()
  local active = 0
  local expired = 0

  for _, entry in pairs(M._cache) do
    if entry.expires >= now then
      active = active + 1
    else
      expired = expired + 1
    end
  end

  return {
    total = vim.tbl_count(M._cache),
    active = active,
    expired = expired,
    max_entries = M.config.max_entries,
  }
end

-- =============================================================================
-- Internal Functions
-- =============================================================================

---Update access order for LRU
---@param key string
function M._touch(key)
  -- Remove from current position
  for i, k in ipairs(M._access_order) do
    if k == key then
      table.remove(M._access_order, i)
      break
    end
  end

  -- Add to end (most recently used)
  table.insert(M._access_order, key)
end

---Remove entry from cache
---@param key string
function M._remove_entry(key)
  M._cache[key] = nil

  for i, k in ipairs(M._access_order) do
    if k == key then
      table.remove(M._access_order, i)
      break
    end
  end
end

---Evict least recently used entry
function M._evict_lru()
  if #M._access_order > 0 then
    local oldest_key = M._access_order[1]
    M._remove_entry(oldest_key)
  end
end

-- =============================================================================
-- Context-Specific Cache Helpers
-- =============================================================================

---Cache key for file context
---@param filepath string
---@param cursor_line number
---@return string key
function M.context_key(filepath, cursor_line)
  return M.make_key("context", filepath, cursor_line)
end

---Cache key for LSP definitions
---@param filepath string
---@param symbol_name string
---@return string key
function M.lsp_key(filepath, symbol_name)
  return M.make_key("lsp", filepath, symbol_name)
end

---Cache key for search results
---@param query string
---@return string key
function M.search_key(query)
  return M.make_key("search", query)
end

---Get cached context or compute
---@param filepath string
---@param cursor_line number
---@param compute function
---@return any context
function M.get_context(filepath, cursor_line, compute)
  local key = M.context_key(filepath, cursor_line)
  return M.get_or_compute(key, compute, {
    ttl = M.config.context_ttl,
    tags = { "file:" .. filepath, "context" },
  })
end

---Get cached LSP result or compute async
---@param filepath string
---@param symbol_name string
---@param compute function Async compute(callback)
---@param callback function Result callback
function M.get_lsp_async(filepath, symbol_name, compute, callback)
  local key = M.lsp_key(filepath, symbol_name)
  M.get_or_compute_async(key, compute, callback, {
    ttl = M.config.lsp_ttl,
    tags = { "file:" .. filepath, "lsp" },
  })
end

---Get cached search results
---@param query string
---@param compute function
---@return any results
function M.get_search(query, compute)
  local key = M.search_key(query)
  return M.get_or_compute(key, compute, {
    ttl = M.config.context_ttl,
    tags = { "search" },
  })
end

return M
