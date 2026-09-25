-- editutor/debug_log.lua
-- Debug logging for ai-editutor
-- Logs all LLM requests to {project_root}/.editutor/editutor.log
-- Also logs all errors to ~/.local/share/nvim/editutor_errors.log

local M = {}

local project_scanner = require("editutor.project_scanner")
local config = require("editutor.config")

-- Error log (global, not per-project)
M.ERROR_LOG = vim.fn.stdpath("data") .. "/editutor_errors.log"

-- Log rotation settings
M.MAX_LOG_SIZE = 1024 * 1024 -- 1MB max log size
M.MAX_ERROR_LOG_SIZE = 512 * 1024 -- 512KB max error log size
M.MAX_BACKUP_COUNT = 2 -- Keep up to 2 backup files

---Normalize an allowed-root entry: expand ~, absolutize, strip trailing slash
---@param p string
---@return string
local function normalize_root(p)
  local expanded = vim.fn.expand(p)
  local abs = vim.fn.fnamemodify(expanded, ":p")
  if #abs > 1 then
    abs = abs:gsub("/+$", "")
  end
  return abs
end

---Check whether per-project logging is allowed for the current buffer.
---Opt-in via `log = { enabled, only_in }`: disabled by default, and when
---enabled the project root must sit inside one of only_in roots (subtree
---match, so subfolders of /work match too). Always silent (no notify).
---@return string|nil project_root nil when logging is not allowed
local function allowed_project_root()
  local log_cfg = config.options.log or {}
  if not log_cfg.enabled then
    return nil
  end
  -- Never touch special buffers (Tutor: buftype=nowrite/filetype=tutor)
  if vim.bo.buftype ~= "" then
    return nil
  end
  if vim.bo.filetype == "tutor" or vim.bo.filetype == "help" then
    return nil
  end
  local project_root = project_scanner.get_project_root()
  if not project_root or project_root == "" then
    return nil
  end
  local only_in = log_cfg.only_in or {}
  if #only_in == 0 then
    return project_root -- enabled with no roots = legacy allow-all
  end
  local root_abs = vim.fn.fnamemodify(project_root, ":p"):gsub("/+$", "")
  for _, entry in ipairs(only_in) do
    local allowed = normalize_root(entry)
    if root_abs == allowed or root_abs:sub(1, #allowed + 1) == allowed .. "/" then
      return project_root
    end
  end
  return nil
end

---Get log file path
---@return string|nil nil when per-project logging is not allowed here
function M.get_log_path()
  local project_root = allowed_project_root()
  if project_root == nil then
    return nil
  end
  return project_root .. "/.editutor/editutor.log"
end

---Ensure the per-project editutor directory exists
---@return string|nil dir_path nil when per-project logging is not allowed here
local function ensure_project_dir()
  local project_root = allowed_project_root()
  if project_root == nil then
    return nil
  end
  local dir_path = project_root .. "/.editutor"

  if vim.fn.isdirectory(dir_path) ~= 1 then
    local ok = pcall(vim.fn.mkdir, dir_path, "p")
    if not ok then
      return nil
    end
  end

  return dir_path
end

---Rotate log file if it exceeds max size
---@param log_path string Path to log file
---@param max_size number Maximum size in bytes
local function rotate_log_if_needed(log_path, max_size)
  local stat = vim.loop.fs_stat(log_path)
  if not stat or stat.size < max_size then
    return -- No rotation needed
  end

  -- Rotate existing backups: .log.2 -> delete, .log.1 -> .log.2, .log -> .log.1
  for i = M.MAX_BACKUP_COUNT, 1, -1 do
    local old_backup = log_path .. "." .. i
    if i == M.MAX_BACKUP_COUNT then
      -- Delete oldest backup
      if vim.fn.filereadable(old_backup) == 1 then
        vim.fn.delete(old_backup)
      end
    else
      -- Rename to next number
      local new_backup = log_path .. "." .. (i + 1)
      if vim.fn.filereadable(old_backup) == 1 then
        vim.fn.rename(old_backup, new_backup)
      end
    end
  end

  -- Move current log to .log.1
  vim.fn.rename(log_path, log_path .. ".1")
end

---Ensure editutor log files are in .gitignore
---Silent no-op when per-project logging is not allowed here.
---@return boolean ok
function M.ensure_gitignore()
  local ok, result = pcall(function()
    if ensure_project_dir() == nil then
      return false
    end
    local project_root = project_scanner.get_project_root()
    project_scanner.ensure_gitignore_entry(project_root)
    return true
  end)
  if not ok then
    return false
  end
  return result
end

---Format timestamp
---@return string
local function timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

---Create separator line
---@param char? string Character to use (default "=")
---@param length? number Length (default 80)
---@return string
local function separator(char, length)
  char = char or "="
  length = length or 80
  return string.rep(char, length)
end

---Format a section header
---@param title string
---@return string
local function section_header(title)
  local line = string.rep("-", 80 - 4 - #title)
  return "-- " .. title .. " " .. line
end

---@class LogRequest
---@field question string User's question
---@field current_file string Current file path
---@field question_line number Line number
---@field mode string "full_project"|"adaptive"
---@field metadata table Context metadata
---@field system_prompt string System prompt sent to LLM
---@field user_prompt string Full user prompt sent to LLM
---@field provider string LLM provider name
---@field model string Model name

---Log a request to the debug file
---@param request LogRequest
function M.log_request(request)
  -- Ensure gitignore entry exists
  M.ensure_gitignore()

  local log_path = M.get_log_path()
  if log_path == nil then
    return false -- per-project logging not allowed here
  end

  -- Rotate log if needed
  rotate_log_if_needed(log_path, M.MAX_LOG_SIZE)

  local lines = {}

  -- Header
  table.insert(lines, separator())
  table.insert(lines, string.format("[%s] Editutor Request", timestamp()))
  table.insert(lines, separator())
  table.insert(lines, "")

  -- Summary section
  table.insert(lines, section_header("Summary"))
  table.insert(lines, string.format("Mode:           %s", request.mode or "unknown"))
  table.insert(lines, string.format("Token count:    %s / %s",
    request.metadata and request.metadata.total_tokens or "?",
    request.metadata and request.metadata.budget or "20000"))
  table.insert(lines, string.format("Within budget:  %s",
    request.metadata and request.metadata.within_budget and "YES" or "NO"))
  table.insert(lines, string.format("Question:       %s", request.question or ""))
  table.insert(lines, string.format("File:           %s:%d",
    request.current_file or "?",
    request.question_line or 0))
  table.insert(lines, string.format("Provider:       %s", request.provider or "unknown"))
  table.insert(lines, string.format("Model:          %s", request.model or "unknown"))
  table.insert(lines, string.format("Has LSP:        %s",
    request.metadata and request.metadata.has_lsp ~= nil
      and (request.metadata.has_lsp and "YES" or "NO")
      or "N/A"))
  table.insert(lines, "")

  -- Included sources section
  table.insert(lines, section_header("Included Sources"))

  if request.metadata then
    -- Current file
    table.insert(lines, string.format("[CURRENT]  %s (%d lines)",
      request.metadata.current_file or request.current_file or "?",
      request.metadata.current_lines or 0))

    -- Mode-specific details
    if request.mode == "full_project" then
      -- Full project mode: list all files
      if request.metadata.files_included then
        for _, file in ipairs(request.metadata.files_included) do
          table.insert(lines, string.format("[PROJECT]  %s (%d lines, ~%d tokens)",
            file.path, file.lines or 0, file.tokens or 0))
        end
      end
      table.insert(lines, string.format("[TREE]     Project structure (%d lines)",
        request.metadata.tree_structure_lines or 0))

    elseif request.mode == "adaptive" then
      -- Adaptive mode: import graph + LSP definitions
      if request.metadata.import_graph_files then
        for _, file in ipairs(request.metadata.import_graph_files) do
          table.insert(lines, string.format("[IMPORT]   %s (%d lines, ~%d tokens)",
            file.path, file.lines or 0, file.tokens or 0))
        end
      end
      if request.metadata.external_files then
        for _, file in ipairs(request.metadata.external_files) do
          local status = file.is_full and "full" or "truncated"
          table.insert(lines, string.format("[LSP DEF]  %s (%d lines, %s, ~%d tokens)",
            file.path, file.lines or 0, status, file.tokens or 0))
        end
      end
      table.insert(lines, string.format("[TREE]     Project structure (%d lines)",
        request.metadata.tree_structure_lines or 0))
    end
  end

  table.insert(lines, "")

  -- System prompt section
  table.insert(lines, section_header("System Prompt"))
  if request.system_prompt then
    -- Truncate if very long
    local sys_prompt = request.system_prompt
    if #sys_prompt > 2000 then
      sys_prompt = sys_prompt:sub(1, 2000) .. "\n... (truncated, " .. #request.system_prompt .. " chars total)"
    end
    table.insert(lines, sys_prompt)
  else
    table.insert(lines, "(no system prompt)")
  end
  table.insert(lines, "")

  -- User prompt section (FULL content)
  table.insert(lines, section_header("User Prompt (Full Content)"))
  if request.user_prompt then
    table.insert(lines, request.user_prompt)
  else
    table.insert(lines, "(no user prompt)")
  end
  table.insert(lines, "")

  -- Footer
  table.insert(lines, separator())
  table.insert(lines, "")
  table.insert(lines, "")

  -- Append to log file
  local content = table.concat(lines, "\n")

  -- Read existing content
  local existing = ""
  if vim.fn.filereadable(log_path) == 1 then
    local existing_lines = vim.fn.readfile(log_path)
    existing = table.concat(existing_lines, "\n")
  end

  -- Write combined content
  vim.fn.writefile(vim.split(existing .. content, "\n"), log_path)
end

---@class LogResponse
---@field response string LLM response
---@field error string|nil Error message if failed
---@field duration_ms number|nil Time taken

---Log a response (appends to last request)
---@param response LogResponse
function M.log_response(response)
  local log_path = M.get_log_path()
  if log_path == nil then
    return -- per-project logging not allowed here
  end

  if vim.fn.filereadable(log_path) ~= 1 then
    return -- No log file yet
  end

  local lines = {}

  table.insert(lines, "")
  table.insert(lines, section_header("Response"))
  table.insert(lines, string.format("Time:     %s", timestamp()))

  if response.duration_ms then
    table.insert(lines, string.format("Duration: %d ms", response.duration_ms))
  end

  if response.error then
    table.insert(lines, string.format("Status:   ERROR"))
    table.insert(lines, string.format("Error:    %s", response.error))
  else
    table.insert(lines, string.format("Status:   SUCCESS"))
    table.insert(lines, "")
    table.insert(lines, "Response content:")
    table.insert(lines, response.response or "(empty)")
  end

  table.insert(lines, "")
  table.insert(lines, separator())
  table.insert(lines, "")

  -- Append to log file
  local content = table.concat(lines, "\n")
  local existing_lines = vim.fn.readfile(log_path)
  local existing = table.concat(existing_lines, "\n")
  vim.fn.writefile(vim.split(existing .. content, "\n"), log_path)
end

---Clear log file
function M.clear()
  local log_path = M.get_log_path()
  if log_path == nil then
    return
  end
  if vim.fn.filereadable(log_path) == 1 then
    vim.fn.delete(log_path)
  end
end

-- =============================================================================
-- ERROR LOGGING (Global)
-- =============================================================================

---Log an error to the global error log
---@param source string Where the error occurred
---@param error_msg string Error message
---@param context? table Additional context
function M.log_error(source, error_msg, context)
  -- Rotate error log if needed
  rotate_log_if_needed(M.ERROR_LOG, M.MAX_ERROR_LOG_SIZE)

  local lines = {}

  table.insert(lines, separator())
  table.insert(lines, string.format("[%s] ERROR in %s", timestamp(), source))
  table.insert(lines, separator("-"))
  table.insert(lines, "")
  table.insert(lines, "Error: " .. tostring(error_msg))
  table.insert(lines, "")
  
  if context then
    table.insert(lines, "Context:")
    for k, v in pairs(context) do
      local val = type(v) == "table" and vim.inspect(v) or tostring(v)
      -- Truncate long values
      if #val > 500 then
        val = val:sub(1, 500) .. "... (truncated)"
      end
      table.insert(lines, string.format("  %s: %s", k, val))
    end
    table.insert(lines, "")
  end
  
  -- Stack trace
  table.insert(lines, "Stack trace:")
  table.insert(lines, debug.traceback("", 2))
  table.insert(lines, "")
  table.insert(lines, separator())
  table.insert(lines, "")
  
  -- Append to error log
  local content = table.concat(lines, "\n")
  local f = io.open(M.ERROR_LOG, "a")
  if f then
    f:write(content)
    f:close()
  end
end

-- Track recently logged errors to prevent duplicates
local recent_errors = {}
local DEDUP_WINDOW_SEC = 60 -- Don't log same error within 60 seconds

---Setup vim.notify hook to catch errors (not warnings)
function M.setup_error_hook()
  local original_notify = vim.notify
  
  vim.notify = function(msg, level, opts)
    -- Only log ERROR level (not WARN) to prevent log spam
    if level == vim.log.levels.ERROR then
      -- Only log messages FROM our plugin (starts with [ai-editutor])
      -- This excludes errors from other plugins that happen to mention "editutor"
      if msg and msg:match("^%[ai%-editutor%]") then
        -- Dedup: skip if same error logged recently
        local now = os.time()
        local last_logged = recent_errors[msg]
        if not last_logged or (now - last_logged) > DEDUP_WINDOW_SEC then
          recent_errors[msg] = now
          M.log_error("vim.notify", msg, { level = level, opts = opts })
        end
      end
    end
    
    -- Call original
    return original_notify(msg, level, opts)
  end
end

---Open error log
function M.open_error_log()
  if vim.fn.filereadable(M.ERROR_LOG) == 1 then
    vim.cmd("edit " .. M.ERROR_LOG)
  else
    vim.notify("[ai-editutor] No error log found", vim.log.levels.INFO)
  end
end

---Clear error log
function M.clear_error_log()
  if vim.fn.filereadable(M.ERROR_LOG) == 1 then
    vim.fn.delete(M.ERROR_LOG)
  end
end

---Get log file size
---@return number bytes
function M.get_size()
  local log_path = M.get_log_path()
  if log_path == nil then
    return 0
  end
  local stat = vim.loop.fs_stat(log_path)
  return stat and stat.size or 0
end

---Open log file in a new buffer
function M.open()
  local log_path = M.get_log_path()
  if log_path == nil then
    vim.notify("[ai-editutor] Per-project logging is not enabled for this location", vim.log.levels.INFO)
    return
  end
  if vim.fn.filereadable(log_path) == 1 then
    vim.cmd("edit " .. log_path)
  else
    vim.notify("[ai-editutor] No debug log found at " .. log_path, vim.log.levels.INFO)
  end
end

-- =============================================================================
-- SIMPLE LOGGING
-- =============================================================================

---Simple log message (appends to project log)
---@param message string Message to log
function M.log(message)
  M.ensure_gitignore()

  local log_path = M.get_log_path()
  if log_path == nil then
    return false -- per-project logging not allowed here
  end
  local line = string.format("[%s] %s", timestamp(), message)
  
  -- Read existing content
  local existing = ""
  if vim.fn.filereadable(log_path) == 1 then
    local existing_lines = vim.fn.readfile(log_path)
    existing = table.concat(existing_lines, "\n")
    if existing ~= "" then
      existing = existing .. "\n"
    end
  end
  
  -- Append new line
  vim.fn.writefile(vim.split(existing .. line, "\n"), log_path)
end

return M
