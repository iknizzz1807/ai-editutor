-- editutor/hints.lua
-- Incremental hints system - progressive assistance (5 levels)
-- Simplified: No mode dependency

local M = {}

local prompts = require("editutor.prompts")
local provider = require("editutor.provider")

-- Store hint sessions (question -> hint state)
local sessions = {}

---@class HintSession
---@field question string Original question
---@field context string Formatted context
---@field level number Current hint level (1-5)
---@field responses string[] Responses at each level
---@field created number Timestamp

-- Maximum hint levels (5-level progressive system)
M.MAX_LEVEL = 5

-- Hint level names
M.LEVEL_NAMES = {
  [1] = "conceptual",
  [2] = "strategic",
  [3] = "directional",
  [4] = "specific",
  [5] = "solution",
}

M.LEVEL_DESCRIPTIONS = {
  [1] = "Conceptual - What concepts are relevant?",
  [2] = "Strategic - What approach to consider?",
  [3] = "Directional - Where in the code to look?",
  [4] = "Specific - What techniques to try?",
  [5] = "Solution - Complete answer with explanation",
}

---Generate session key from question
---@param question string
---@return string
local function get_session_key(question)
  return "hint:" .. question:sub(1, 100)
end

---Get or create hint session
---@param question string
---@param context string Formatted context
---@return HintSession
function M.get_session(question, context)
  local key = get_session_key(question)

  if not sessions[key] then
    sessions[key] = {
      question = question,
      context = context,
      level = 0,
      responses = {},
      created = os.time(),
    }
  end

  return sessions[key]
end

---Get next hint level for a session
---@param session HintSession
---@return number level
function M.get_next_level(session)
  local next_level = session.level + 1
  return math.min(next_level, M.MAX_LEVEL)
end

---Check if session has more hints available
---@param session HintSession
---@return boolean
function M.has_more_hints(session)
  return session.level < M.MAX_LEVEL
end

---Build hint prompt for specific level
---@param question string
---@param context string
---@param level number
---@param previous_responses string[]
---@return string system_prompt
---@return string user_prompt
function M.build_hint_prompt(question, context, level, previous_responses)
  -- Base system prompt + hint level instruction
  local system_parts = {
    prompts.get_system_prompt(),
    "",
    "HINT LEVEL: " .. level .. "/" .. M.MAX_LEVEL,
    prompts.get_hint_prompt(level),
  }

  -- Add previous hint context if available
  if #previous_responses > 0 then
    table.insert(system_parts, "")
    table.insert(system_parts, "Previous hints given (do not repeat, build upon them):")
    for i, resp in ipairs(previous_responses) do
      table.insert(system_parts, string.format("Level %d: %s", i, resp:sub(1, 150) .. "..."))
    end
  end

  local system_prompt = table.concat(system_parts, "\n")

  -- User prompt
  local user_parts = {
    "Context:",
    context,
    "",
    "Question:",
    question,
    "",
    string.format("Provide a level %d hint (%s)", level, M.LEVEL_DESCRIPTIONS[level]),
  }

  local user_prompt = table.concat(user_parts, "\n")

  return system_prompt, user_prompt
end

---Request next hint for a session
---@param session HintSession
---@param callback function(response, level, has_more, error)
function M.request_next_hint(session, callback)
  local next_level = M.get_next_level(session)

  -- Check if we already have this level
  if session.responses[next_level] then
    callback(session.responses[next_level], next_level, M.has_more_hints(session), nil)
    return
  end

  -- Build prompt for this level
  local system_prompt, user_prompt = M.build_hint_prompt(
    session.question,
    session.context,
    next_level,
    session.responses
  )

  -- Query LLM
  provider.query_async(system_prompt, user_prompt, function(response, err)
    if err then
      callback(nil, next_level, false, err)
      return
    end

    -- Store response and update level
    session.level = next_level
    session.responses[next_level] = response

    callback(response, next_level, next_level < M.MAX_LEVEL, nil)
  end)
end

---Clear a specific session
---@param question string
function M.clear_session(question)
  local key = get_session_key(question)
  sessions[key] = nil
end

---Clear all sessions
function M.clear_all_sessions()
  sessions = {}
end

---Clean old sessions (older than 1 hour)
function M.cleanup_old_sessions()
  local now = os.time()
  local max_age = 3600 -- 1 hour

  for key, session in pairs(sessions) do
    if now - session.created > max_age then
      sessions[key] = nil
    end
  end
end

---Get session info for display
---@param session HintSession
---@return string
function M.get_session_info(session)
  local info = {
    string.format("Hint Level: %d/%d", session.level, M.MAX_LEVEL),
  }

  if session.level < M.MAX_LEVEL then
    table.insert(info, string.format("Next: %s", M.LEVEL_DESCRIPTIONS[session.level + 1]))
  else
    table.insert(info, "Maximum hint level reached")
  end

  return table.concat(info, " | ")
end

return M
