-- editutor/async.lua
-- Async abstraction layer using plenary.async
-- Provides consistent patterns for parallel/sequential async operations

local M = {}

-- Check if plenary.async is available
local ok, a = pcall(require, "plenary.async.async")
if not ok then
  vim.notify("[ai-editutor] plenary.nvim required for async operations", vim.log.levels.ERROR)
  return M
end

local util = require("plenary.async.util")
local lsp_async = require("plenary.async.lsp")

-- =============================================================================
-- Core Wrappers
-- =============================================================================

---Wrap a callback-style function for use in async context
---@param fn function The callback-style function (callback must be last param)
---@param argc number Number of arguments including callback
---@return function Wrapped async function
M.wrap = a.wrap

---Run an async function from non-async context
---@param async_fn function The async function to run
---@param callback? function Optional callback(result) when done
M.run = function(async_fn, callback)
  a.run(async_fn, callback or function() end)
end

---Create a "void" async function (fire and forget from non-async context)
---@param fn function The async function
---@return function A function that runs async without blocking
M.void = a.void

-- =============================================================================
-- Parallel Execution (Promise.all equivalent)
-- =============================================================================

---Run multiple async functions in parallel, wait for all to complete
---Like Promise.all - returns results in same order as input
---@param async_fns function[] List of async functions
---@return table[] Results in same order as input (each result is {return_values...})
M.all = function(async_fns)
  if #async_fns == 0 then
    return {}
  end
  return util.join(async_fns)
end

---Run multiple async functions in parallel, return first to complete
---Like Promise.race
---@param async_fns function[] List of async functions
---@return any Result from first completed function
M.race = function(async_fns)
  return util.race(async_fns)
end

-- =============================================================================
-- Timeout Handling
-- =============================================================================

---Run an async function with timeout
---@param async_fn function The async function
---@param timeout_ms number Timeout in milliseconds
---@param fallback? any Value to return on timeout (default: nil)
---@return any result Result or fallback on timeout
---@return boolean timed_out Whether timeout occurred
M.with_timeout = function(async_fn, timeout_ms, fallback)
  local result = nil
  local completed = false
  local timed_out = false

  -- Race between the async function and a sleep timer
  local winner = util.race({
    function()
      result = async_fn()
      completed = true
      return "completed"
    end,
    function()
      util.sleep(timeout_ms)
      return "timeout"
    end,
  })

  if winner == "timeout" then
    timed_out = true
    return fallback, true
  end

  return result, false
end

-- =============================================================================
-- Protected Async Call
-- =============================================================================

---Run an async function with error protection (like pcall)
---@param async_fn function The async function
---@return boolean ok Whether function succeeded
---@return any result Result or error message
M.pcall = function(async_fn)
  return util.apcall(async_fn)
end

-- =============================================================================
-- LSP Wrappers
-- =============================================================================

---Async LSP definition request
---Returns normalized locations from all clients
---@param bufnr number Buffer number
---@param line number 0-indexed line
---@param col number 0-indexed column
---@param timeout_ms? number Optional timeout (default: 5000ms)
---@return table[] locations List of {uri, range} locations
M.lsp_definition = function(bufnr, line, col, timeout_ms)
  timeout_ms = timeout_ms or 5000

  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = { line = line, character = col },
  }

  -- Use with_timeout to prevent hanging
  local results, timed_out = M.with_timeout(function()
    return lsp_async.buf_request_all(bufnr, "textDocument/definition", params)
  end, timeout_ms, {})

  if timed_out or not results then
    return {}
  end

  -- Normalize results from all clients
  local locations = {}
  for _, client_result in pairs(results) do
    if client_result.result then
      local res = client_result.result
      -- Handle single Location
      if res.uri then
        table.insert(locations, { uri = res.uri, range = res.range })
      -- Handle LocationLink
      elseif res.targetUri then
        table.insert(locations, { uri = res.targetUri, range = res.targetRange or res.targetSelectionRange })
      -- Handle array of Location/LocationLink
      elseif type(res) == "table" and #res > 0 then
        for _, loc in ipairs(res) do
          if loc.uri then
            table.insert(locations, { uri = loc.uri, range = loc.range })
          elseif loc.targetUri then
            table.insert(locations, { uri = loc.targetUri, range = loc.targetRange or loc.targetSelectionRange })
          end
        end
      end
    end
  end

  return locations
end

---Async LSP hover request
---@param bufnr number Buffer number
---@param line number 0-indexed line
---@param col number 0-indexed column
---@param timeout_ms? number Optional timeout (default: 3000ms)
---@return string|nil hover_text Hover content or nil
M.lsp_hover = function(bufnr, line, col, timeout_ms)
  timeout_ms = timeout_ms or 3000

  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = { line = line, character = col },
  }

  local results, timed_out = M.with_timeout(function()
    return lsp_async.buf_request_all(bufnr, "textDocument/hover", params)
  end, timeout_ms, {})

  if timed_out or not results then
    return nil
  end

  -- Extract hover text from first successful result
  for _, client_result in pairs(results) do
    local result = client_result.result
    if result and result.contents then
      -- String content
      if type(result.contents) == "string" then
        return result.contents
      -- MarkupContent
      elseif result.contents.value then
        return result.contents.value
      -- Array of MarkedString
      elseif type(result.contents) == "table" and #result.contents > 0 then
        local parts = {}
        for _, content in ipairs(result.contents) do
          if type(content) == "string" then
            table.insert(parts, content)
          elseif content.value then
            table.insert(parts, content.value)
          end
        end
        if #parts > 0 then
          return table.concat(parts, "\n")
        end
      end
    end
  end

  return nil
end

-- =============================================================================
-- Scheduler
-- =============================================================================

---Yield to Neovim scheduler (required before calling vim.api from async)
M.scheduler = util.scheduler

---Sleep for specified milliseconds
---@param ms number Milliseconds to sleep
M.sleep = util.sleep

-- =============================================================================
-- Task Tracking (for parallel with limited concurrency)
-- =============================================================================

---Run multiple tasks with limited concurrency
---@param tasks function[] List of async functions
---@param opts? {max_concurrent?: number, timeout_ms?: number}
---@return table[] results Results (nil for failed/timed-out tasks)
---@return table metadata {completed: number, failed: number, timed_out: boolean}
M.parallel_limited = function(tasks, opts)
  opts = opts or {}
  local max_concurrent = opts.max_concurrent or 10
  local timeout_ms = opts.timeout_ms

  if #tasks == 0 then
    return {}, { completed = 0, failed = 0, timed_out = false }
  end

  local results = {}
  local failed = 0
  local global_timed_out = false

  -- Wrap the entire parallel execution with timeout if specified
  local function execute_all()
    local i = 1
    while i <= #tasks do
      -- Build batch
      local batch = {}
      local batch_indices = {}

      for j = i, math.min(i + max_concurrent - 1, #tasks) do
        local task_index = j
        table.insert(batch, function()
          local ok, result = M.pcall(tasks[task_index])
          if ok then
            return { ok = true, result = result }
          else
            return { ok = false, error = result }
          end
        end)
        table.insert(batch_indices, j)
      end

      -- Execute batch in parallel
      local batch_results = util.join(batch)

      -- Map results back to original indices
      for k, idx in ipairs(batch_indices) do
        local br = batch_results[k]
        if br and br[1] then -- join returns {{result}, ...}
          local wrapped = br[1]
          if wrapped.ok then
            results[idx] = wrapped.result
          else
            results[idx] = nil
            failed = failed + 1
          end
        else
          results[idx] = nil
          failed = failed + 1
        end
      end

      i = i + max_concurrent
    end
  end

  if timeout_ms then
    local _, timed_out = M.with_timeout(execute_all, timeout_ms, nil)
    global_timed_out = timed_out
  else
    execute_all()
  end

  local completed = 0
  for i = 1, #tasks do
    if results[i] ~= nil then
      completed = completed + 1
    end
  end

  return results, {
    completed = completed,
    failed = failed,
    timed_out = global_timed_out,
  }
end

-- =============================================================================
-- Utility: Convert callback function to async
-- =============================================================================

---Helper to convert a callback-style function call to awaitable
---Usage: local result = M.await(function(cb) some_callback_fn(arg1, arg2, cb) end)
---@param fn function Function that takes a callback as its only argument
---@return any The result passed to the callback
M.await = a.wrap(function(fn, callback)
  fn(callback)
end, 2)

return M
