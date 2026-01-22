-- editutor/cache.lua
-- Simple in-memory cache with TTL and autocmd-based invalidation
-- Simplified version: only caches project info and LSP results

local M = {}

-- Cache configuration
M.config = {
  default_ttl = 300, -- Default TTL in seconds (5 minutes)
  project_ttl = 600, -- Project scan cache TTL (10 minutes)
  lsp_ttl = 120, -- LSP results TTL (2 minutes)
}

-- Cache storage
M._cache = {}
M._autocmd_group = nil

---@class CacheEntry
---@field value any Cached value
---@field expires number Expiration timestamp
---@field tags string[] Tags for bulk invalidation

-- Source file extensions that should trigger cache invalidation
M.SOURCE_EXTENSIONS = {
  "js", "jsx", "ts", "tsx", "mjs", "cjs",
  "py", "pyw",
  "lua",
  "go",
  "rs",
  "c", "h", "cpp", "cc", "hpp",
  "java", "kt",
  "rb",
  "php",
  "swift",
  "ex", "exs",
}

---Check if file is a source file that should invalidate cache
---@param filepath string
---@return boolean
local function is_source_file(filepath)
  local ext = filepath:match("%.([^.]+)$")
  if not ext then return false end
  ext = ext:lower()
  for _, source_ext in ipairs(M.SOURCE_EXTENSIONS) do
    if ext == source_ext then
      return true
    end
  end
  return false
end

---Initialize cache and setup autocmds
function M.setup()
  if M._autocmd_group then
    return -- Already setup
  end

  M._autocmd_group = vim.api.nvim_create_augroup("EditutorCache", { clear = true })

  -- Invalidate file-specific cache on file save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = M._autocmd_group,
    callback = function(ev)
      M.invalidate_by_tag("file:" .. ev.file)

      -- Only invalidate project cache when a SOURCE file changes
      -- This prevents unnecessary re-scans when editing non-code files
      if is_source_file(ev.file) then
        M.invalidate_by_tag("project")

        -- Also invalidate import index
        local ok, import_graph = pcall(require, "editutor.import_graph")
        if ok and import_graph.invalidate_index then
          import_graph.invalidate_index()
        end
      end
    end,
  })

  -- Invalidate LSP cache when LSP restarts
  vim.api.nvim_create_autocmd("LspAttach", {
    group = M._autocmd_group,
    callback = function()
      M.invalidate_by_tag("lsp")
    end,
  })
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

  -- Check expiration
  if entry.expires <= os.time() then
    M._cache[key] = nil
    return nil, false
  end

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

  M._cache[key] = {
    value = value,
    expires = os.time() + ttl,
    tags = tags,
  }
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
    M._cache[key] = nil
  end
end

---Clear all cache entries
function M.clear()
  M._cache = {}
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
  }
end

-- =============================================================================
-- Specialized Cache Helpers
-- =============================================================================

---Cache key for project scan results
---@param project_root string
---@return string key
function M.project_key(project_root)
  return "project:" .. project_root
end

---Cache key for LSP definitions
---@param filepath string
---@return string key
function M.lsp_key(filepath)
  return "lsp:" .. filepath
end

---Get or compute project scan
---@param project_root string
---@param compute function
---@return any result
function M.get_project(project_root, compute)
  local key = M.project_key(project_root)
  local value, hit = M.get(key)

  if hit then
    return value
  end

  value = compute()
  M.set(key, value, {
    ttl = M.config.project_ttl,
    tags = { "project" },
  })

  return value
end

---Get or compute LSP definitions (async)
---@param filepath string
---@param compute function Async compute(callback)
---@param callback function Result callback
function M.get_lsp_async(filepath, compute, callback)
  local key = M.lsp_key(filepath)
  local value, hit = M.get(key)

  if hit then
    callback(value)
    return
  end

  compute(function(computed_value)
    M.set(key, computed_value, {
      ttl = M.config.lsp_ttl,
      tags = { "lsp", "file:" .. filepath },
    })
    callback(computed_value)
  end)
end

return M
