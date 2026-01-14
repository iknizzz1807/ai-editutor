-- editutor/rag.lua
-- RAG integration - interface to Python CLI for codebase search

local M = {}

local config = require("editutor.config")

---@class RAGResult
---@field filepath string File path
---@field chunk string Code chunk content
---@field language string Programming language
---@field start_line number|nil Start line
---@field end_line number|nil End line
---@field score number Relevance score

-- Cache for CLI availability check
local cli_available = nil

---Check if editutor-cli is available
---@return boolean
function M.is_available()
  if cli_available ~= nil then
    return cli_available
  end

  local handle = io.popen("which editutor-cli 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    cli_available = result and result ~= ""
  else
    cli_available = false
  end

  return cli_available
end

---Run CLI command and get JSON output
---@param args string[] Command arguments
---@param callback function Callback(result, error)
local function run_cli_async(args, callback)
  local cmd = "editutor-cli " .. table.concat(args, " ")

  local Job = require("plenary.job")

  Job:new({
    command = "editutor-cli",
    args = args,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          callback(nil, "CLI error: " .. stderr)
          return
        end

        local stdout = table.concat(j:result(), "\n")
        local ok, result = pcall(vim.json.decode, stdout)

        if not ok then
          callback(nil, "Failed to parse CLI output")
          return
        end

        callback(result, nil)
      end)
    end,
  }):start()
end

---Query the RAG system
---@param query string Natural language query
---@param opts? table Options {top_k?: number, hybrid?: boolean}
---@param callback function Callback(results, error)
function M.query(query, opts, callback)
  opts = opts or {}

  if not M.is_available() then
    callback(nil, "editutor-cli not installed. Run: pip install -e python/")
    return
  end

  local args = { "query", vim.fn.shellescape(query), "--json" }

  if opts.top_k then
    table.insert(args, "--top-k")
    table.insert(args, tostring(opts.top_k))
  end

  if opts.hybrid then
    table.insert(args, "--hybrid")
  end

  run_cli_async(args, function(result, err)
    if err then
      callback(nil, err)
      return
    end

    local results = {}
    for _, r in ipairs(result.results or {}) do
      table.insert(results, {
        filepath = r.filepath,
        chunk = r.chunk,
        language = r.language or "",
        start_line = r.start_line,
        end_line = r.end_line,
        score = r.score or 0,
      })
    end

    callback(results, nil)
  end)
end

---Index the current project
---@param path? string Path to index (default: current working directory)
---@param opts? table Options {force?: boolean}
---@param callback function Callback(stats, error)
function M.index(path, opts, callback)
  path = path or vim.fn.getcwd()
  opts = opts or {}

  if not M.is_available() then
    callback(nil, "editutor-cli not installed")
    return
  end

  local args = { "index", vim.fn.shellescape(path) }

  if opts.force then
    table.insert(args, "--force")
  end

  vim.notify("[EduTutor] Indexing " .. path .. "...", vim.log.levels.INFO)

  run_cli_async(args, function(result, err)
    if err then
      callback(nil, err)
      return
    end

    callback(result, nil)
  end)
end

---Get index status
---@param callback function Callback(stats, error)
function M.status(callback)
  if not M.is_available() then
    callback(nil, "editutor-cli not installed")
    return
  end

  run_cli_async({ "status" }, callback)
end

---Index a single file (for auto-reindex on save)
---@param filepath string Absolute path to file
---@param callback? function Callback(success, error)
function M.index_file(filepath, callback)
  callback = callback or function() end

  if not M.is_available() then
    callback(false, "editutor-cli not installed")
    return
  end

  local args = { "index-file", vim.fn.shellescape(filepath) }

  run_cli_async(args, function(result, err)
    if err then
      callback(false, err)
      return
    end
    callback(true, nil)
  end)
end

---Check if a file is in an indexed project
---@param filepath string File path to check
---@param callback function Callback(is_indexed, project_root)
function M.is_file_indexed(filepath, callback)
  if not M.is_available() then
    callback(false, nil)
    return
  end

  run_cli_async({ "check-file", vim.fn.shellescape(filepath) }, function(result, err)
    if err then
      callback(false, nil)
      return
    end
    callback(result.indexed or false, result.project_root)
  end)
end

---Format RAG results for prompt context
---@param results RAGResult[]
---@return string
function M.format_for_prompt(results)
  if not results or #results == 0 then
    return ""
  end

  local parts = {
    "Relevant code from the codebase:",
    "",
  }

  for i, result in ipairs(results) do
    table.insert(parts, string.format("--- %d. %s (score: %.3f) ---", i, result.filepath, result.score))

    if result.start_line then
      table.insert(parts, string.format("Lines %d-%d:", result.start_line, result.end_line or result.start_line))
    end

    table.insert(parts, "```" .. result.language)
    table.insert(parts, result.chunk)
    table.insert(parts, "```")
    table.insert(parts, "")
  end

  return table.concat(parts, "\n")
end

---Query and format for prompt
---@param query string
---@param callback function Callback(context_string, error)
function M.get_context(query, callback)
  M.query(query, { top_k = 5, hybrid = true }, function(results, err)
    if err then
      callback("", err)
      return
    end

    local context = M.format_for_prompt(results)
    callback(context, nil)
  end)
end

return M
