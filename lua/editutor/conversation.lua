-- editutor/conversation.lua
-- Session-based conversation memory for follow-up questions

local M = {}

-- Current conversation session
M._session = {
  id = nil,
  messages = {},
  context_file = nil,
  context_line = nil,
  started_at = nil,
  mode = nil,
}

-- Configuration
M.config = {
  max_messages = 10,        -- Max messages to keep in context
  max_context_tokens = 4000, -- Approximate token limit for history
  auto_clear_minutes = 30,  -- Auto-clear after inactivity
}

---Generate a unique session ID
---@return string
local function generate_session_id()
  return string.format("%s_%d", os.date("%Y%m%d%H%M%S"), math.random(1000, 9999))
end

---Estimate token count (rough: 1 token ≈ 4 chars)
---@param text string
---@return number
local function estimate_tokens(text)
  return math.ceil(#text / 4)
end

---Start a new conversation session
---@param opts? table {mode?: string, filepath?: string, line?: number}
---@return string session_id
function M.start_session(opts)
  opts = opts or {}

  M._session = {
    id = generate_session_id(),
    messages = {},
    context_file = opts.filepath or vim.api.nvim_buf_get_name(0),
    context_line = opts.line,
    started_at = os.time(),
    mode = opts.mode or "question",
  }

  return M._session.id
end

---Check if we should continue existing session or start new
---@param filepath string Current file path
---@param line number Current line
---@return boolean should_continue
function M.should_continue_session(filepath, line)
  -- No existing session
  if not M._session.id then
    return false
  end

  -- Session expired (30 min inactivity)
  local elapsed = os.time() - (M._session.started_at or 0)
  if elapsed > M.config.auto_clear_minutes * 60 then
    return false
  end

  -- Different file = new session
  if M._session.context_file ~= filepath then
    return false
  end

  -- Same file, within reasonable range (±50 lines) = continue
  if M._session.context_line then
    local distance = math.abs(line - M._session.context_line)
    if distance > 50 then
      return false
    end
  end

  return true
end

---Add a message to the conversation
---@param role "user"|"assistant" Message role
---@param content string Message content
function M.add_message(role, content)
  if not M._session.id then
    M.start_session()
  end

  table.insert(M._session.messages, {
    role = role,
    content = content,
    timestamp = os.time(),
  })

  -- Update activity timestamp
  M._session.started_at = os.time()

  -- Trim if too many messages
  M._trim_messages()
end

---Trim messages to stay within limits
function M._trim_messages()
  -- Keep max N messages
  while #M._session.messages > M.config.max_messages do
    table.remove(M._session.messages, 1)
  end

  -- Check token limit and summarize if needed
  local total_tokens = 0
  for _, msg in ipairs(M._session.messages) do
    total_tokens = total_tokens + estimate_tokens(msg.content)
  end

  -- If over limit, remove oldest messages
  while total_tokens > M.config.max_context_tokens and #M._session.messages > 2 do
    local removed = table.remove(M._session.messages, 1)
    total_tokens = total_tokens - estimate_tokens(removed.content)
  end
end

---Get conversation history formatted for LLM
---@return table messages List of {role, content}
function M.get_history()
  local history = {}

  for _, msg in ipairs(M._session.messages) do
    table.insert(history, {
      role = msg.role,
      content = msg.content,
    })
  end

  return history
end

---Get conversation history as a single context string
---@return string Formatted history
function M.get_history_as_context()
  if #M._session.messages == 0 then
    return ""
  end

  local parts = {"=== Previous conversation ===", ""}

  for i, msg in ipairs(M._session.messages) do
    local role_label = msg.role == "user" and "User" or "Assistant"
    -- Truncate long messages in history
    local content = msg.content
    if #content > 500 then
      content = content:sub(1, 500) .. "...[truncated]"
    end
    table.insert(parts, string.format("[%s]: %s", role_label, content))
    table.insert(parts, "")
  end

  table.insert(parts, "=== Current question ===")
  table.insert(parts, "")

  return table.concat(parts, "\n")
end

---Check if there's an active conversation
---@return boolean
function M.has_active_session()
  return M._session.id ~= nil and #M._session.messages > 0
end

---Get session info
---@return table|nil
function M.get_session_info()
  if not M._session.id then
    return nil
  end

  return {
    id = M._session.id,
    message_count = #M._session.messages,
    file = M._session.context_file,
    mode = M._session.mode,
    duration = os.time() - M._session.started_at,
  }
end

---Clear current session
function M.clear_session()
  M._session = {
    id = nil,
    messages = {},
    context_file = nil,
    context_line = nil,
    started_at = nil,
    mode = nil,
  }
end

---Continue or start session based on context
---@param filepath string
---@param line number
---@param mode string
---@return boolean is_continuation
function M.continue_or_start(filepath, line, mode)
  if M.should_continue_session(filepath, line) then
    -- Update context line for continued session
    M._session.context_line = line
    return true
  else
    M.start_session({
      filepath = filepath,
      line = line,
      mode = mode,
    })
    return false
  end
end

return M
