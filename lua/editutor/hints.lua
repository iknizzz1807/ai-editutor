-- editutor/hints.lua
-- Incremental hints system - progressive assistance

local M = {}

local config = require("editutor.config")
local prompts = require("editutor.prompts")
local provider = require("editutor.provider")

-- Store hint sessions (question -> hint state)
-- Each session tracks hint level and previous responses
local sessions = {}

---@class HintSession
---@field question string Original question
---@field mode string Mode used
---@field context string Formatted context
---@field level number Current hint level (1-4)
---@field responses string[] Responses at each level
---@field created number Timestamp

-- Maximum hint levels
M.MAX_LEVEL = 4

-- Hint level descriptions
M.LEVEL_DESCRIPTIONS = {
  [1] = "Subtle hint - points in the right direction",
  [2] = "Clearer hint - narrows down the problem",
  [3] = "Strong hint - almost reveals the answer",
  [4] = "Full solution - complete explanation",
}

-- Hint level prompts
M.LEVEL_PROMPTS = {
  [1] = [[
Give a SUBTLE hint that points in the right direction without revealing the answer.
- Use analogies or ask leading questions
- Point to relevant concepts without explaining them fully
- Encourage the developer to think about specific aspects]],

  [2] = [[
Give a CLEARER hint that narrows down the problem area.
- Identify the specific area where the issue/answer lies
- Explain related concepts that are necessary to understand
- Still require the developer to make the final connection]],

  [3] = [[
Give a STRONG hint that makes the answer almost obvious.
- Provide a partial solution or pseudocode
- Explain most of the reasoning
- Leave only the final step for the developer]],

  [4] = [[
Provide the FULL solution with a detailed explanation.
- Give the complete answer
- Explain why this is the correct approach
- Cover edge cases and best practices
- Suggest follow-up learning topics]],
}

---Generate session key from question and context
---@param question string
---@param mode string
---@return string
local function get_session_key(question, mode)
  -- Simple hash based on question and mode
  return mode .. ":" .. question:sub(1, 100)
end

---Get or create hint session
---@param question string
---@param mode string
---@param context string Formatted context
---@return HintSession
function M.get_session(question, mode, context)
  local key = get_session_key(question, mode)

  if not sessions[key] then
    sessions[key] = {
      question = question,
      mode = mode,
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
---@param mode string
---@param level number
---@param previous_responses string[]
---@return string system_prompt
---@return string user_prompt
function M.build_hint_prompt(question, context, mode, level, previous_responses)
  -- Base system prompt
  local system_parts = {
    prompts.get_system_prompt(mode),
    "",
    "HINT LEVEL: " .. level .. "/" .. M.MAX_LEVEL,
    M.LEVEL_PROMPTS[level],
  }

  -- Add previous hint context if available
  if #previous_responses > 0 then
    table.insert(system_parts, "")
    table.insert(system_parts, "Previous hints given (do not repeat, build upon them):")
    for i, resp in ipairs(previous_responses) do
      table.insert(system_parts, string.format("Level %d hint: %s", i, resp:sub(1, 200) .. "..."))
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
    session.mode,
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
---@param mode string
function M.clear_session(question, mode)
  local key = get_session_key(question, mode)
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
