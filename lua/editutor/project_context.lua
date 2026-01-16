-- editutor/project_context.lua
-- Project-wide context gathering (simplified wrapper for backward compatibility)
-- v1.1.0: Most functionality moved to project_scanner.lua

local M = {}

local project_scanner = require("editutor.project_scanner")

---Get project root
---@return string
function M.get_project_root()
  return project_scanner.get_project_root()
end

---Get project summary (README + package info)
---@return string
function M.get_project_summary()
  local root = M.get_project_root()

  -- Read README
  local readme_content = ""
  local readme_files = { "README.md", "README", "README.txt", "README.rst" }

  for _, filename in ipairs(readme_files) do
    local filepath = root .. "/" .. filename
    local ok, lines = pcall(vim.fn.readfile, filepath)
    if ok and lines and #lines > 0 then
      readme_content = table.concat(lines, "\n")
      -- Truncate if too long
      if #readme_content > 3000 then
        readme_content = readme_content:sub(1, 3000) .. "\n...[truncated]"
      end
      break
    end
  end

  if readme_content == "" then
    return ""
  end

  return "=== Project README ===\n" .. readme_content
end

---Clear cache (for backward compatibility)
function M.clear_cache()
  -- Cache is now managed by cache.lua
  local cache_ok, cache = pcall(require, "editutor.cache")
  if cache_ok then
    cache.invalidate_by_tag("project")
  end
end

return M
