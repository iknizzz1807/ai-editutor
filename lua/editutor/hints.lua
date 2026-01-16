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
---@field level number Current hint level (1-5)
---@field responses string[] Responses at each level
---@field created number Timestamp

-- Maximum hint levels (5-level progressive system)
M.MAX_LEVEL = 5

-- Hint level names and descriptions
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

-- Hint level prompts (5 levels of progressively more revealing hints)
M.LEVEL_PROMPTS = {
  -- Level 1: Conceptual - Point to relevant concepts without explaining how to apply them
  [1] = [[
Give a CONCEPTUAL hint (Level 1/5) - What concepts are relevant?
- Mention 1-2 programming concepts that relate to this problem
- Use a question to guide thinking: "Have you considered...?"
- DO NOT explain how to apply these concepts
- DO NOT point to specific code locations
- Keep it to 2-3 sentences maximum
- Example: "This seems related to closure scope. What happens to variables when a function returns?"]],

  -- Level 2: Strategic - Suggest an approach or strategy
  [2] = [[
Give a STRATEGIC hint (Level 2/5) - What approach to consider?
- Build on the conceptual hint (don't repeat it)
- Suggest a general strategy or pattern to investigate
- Mention what type of solution might work (but not the specific solution)
- Keep it to 3-4 sentences
- Example: "You might want to look into how async/await handles errors differently from callbacks. Consider what happens if a promise rejects..."]],

  -- Level 3: Directional - Point to specific code locations or patterns
  [3] = [[
Give a DIRECTIONAL hint (Level 3/5) - Where in the code to look?
- Point to specific areas in the provided code context
- Identify which function, line, or pattern to focus on
- Explain what to look for (but not the fix)
- You can reference line numbers from the context
- Keep it to 4-5 sentences
- Example: "Look at line 42 where the callback is registered. Notice how the variable 'count' is accessed. What value does 'count' have when the callback actually runs?"]],

  -- Level 4: Specific - Give specific techniques but not the full answer
  [4] = [[
Give a SPECIFIC hint (Level 4/5) - What techniques to try?
- Provide a specific technique or pattern to apply
- Show a small code example or pseudocode (not the complete solution)
- Explain the "why" behind this technique
- Let the developer apply it to their specific case
- Keep it to 5-7 sentences with a short code snippet
- Example: "To capture the current value, you can use an IIFE or pass it as a parameter. Like this:
  for (let i = 0; i < 5; i++) { ((current) => { setTimeout(() => console.log(current), 100); })(i); }
  Now apply this pattern to your situation..."]],

  -- Level 5: Solution - Complete answer with explanation
  [5] = [[
Give the FULL SOLUTION (Level 5/5) - Complete answer with explanation.
- Provide the complete, working solution
- Explain each part of the solution and why it works
- Show before/after code if applicable
- Mention edge cases and potential pitfalls
- Suggest one related concept to learn next
- Be thorough but concise (aim for clear, not long)]],
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
