-- editutor/debug_log.lua
-- Debug logging for ai-editutor
-- Logs all LLM requests to {project_root}/.editutor.log
-- Also logs all errors to ~/.local/share/nvim/editutor_errors.log

local M = {}

local project_scanner = require("editutor.project_scanner")

-- Error log (global, not per-project)
M.ERROR_LOG = vim.fn.stdpath("data") .. "/editutor_errors.log"

---Get log file path
---@return string
function M.get_log_path()
  local project_root = project_scanner.get_project_root()
  return project_root .. "/.editutor.log"
end

---Ensure .editutor.log is in .gitignore
function M.ensure_gitignore()
  local project_root = project_scanner.get_project_root()
  project_scanner.ensure_gitignore_entry(project_root)
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
  local lines = {}

  -- Header
  table.insert(lines, separator())
  table.insert(lines, string.format("[%s] EduTutor Request", timestamp()))
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
  local stat = vim.loop.fs_stat(log_path)
  return stat and stat.size or 0
end

---Open log file in a new buffer
function M.open()
  local log_path = M.get_log_path()
  if vim.fn.filereadable(log_path) == 1 then
    vim.cmd("edit " .. log_path)
  else
    vim.notify("[ai-editutor] No debug log found at " .. log_path, vim.log.levels.INFO)
  end
end

return M
