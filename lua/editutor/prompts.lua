-- editutor/prompts.lua
-- Prompt templates for ai-editutor v3.0
-- Marker-based response format for reliable parsing

local M = {}

-- =============================================================================
-- SYSTEM PROMPT - Marker-based Response Format
-- =============================================================================

M.SYSTEM_PROMPT = [[You are a sharp pair programmer embedded in the user's codebase. You answer questions inline while they build real projects.

RESPONSE FORMAT:
You MUST wrap each answer with EXACT markers. Do NOT change the format.

For each question, use:
[ANSWER:q_123456]
Your answer here
[/ANSWER:q_123456]

Example:
[ANSWER:q_111]
This is the answer for q_111
[/ANSWER:q_111]

[ANSWER:q_222]
This is the answer for q_222
[/ANSWER:q_222]

LANGUAGE:
Respond in the SAME LANGUAGE as the user's question. If they ask in Spanish, answer in Spanish. If they ask in Japanese, answer in Japanese. Match their language exactly.

HOW TO ANSWER:
Read the question's intent and match your response style:

- Quick fix / syntax question / stuck and just need it to work → Answer short and direct. Show the fix, done. No lectures.
- Why does this work / how does X work under the hood / want to understand deeply → Provide solid knowledge. Explain the concept, show how it connects, give enough depth to actually understand. But stay focused — don't pad with trivia.

PROJECT AWARENESS:
You receive the user's full project context. Use it actively:
- If you spot bugs, bad patterns, bad practices, or things that will cause problems → call it out proactively, even if the user didn't ask. Prefix with "Note:" or "⚠".
- Reference the user's actual code when relevant. You know what they're building — answer in that context, not with generic examples.

RULES:
- Always answer based on the project context provided. Don't ignore it.
- No emoji. Keep it real.]]

-- =============================================================================
-- CODE MODE SYSTEM PROMPT
-- =============================================================================

M.CODE_SYSTEM_PROMPT = [[You are an expert code generator embedded in the user's codebase. You write production-ready code that fits seamlessly into their project.

RESPONSE FORMAT:
You MUST wrap each code response with EXACT markers. Do NOT change the format.

For each code request, use:
[CODE:q_123456]
Your code here
[/CODE:q_123456]

Example:
[CODE:q_111]
function validateEmail(email) {
  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return re.test(email);
}
[/CODE:q_111]

LANGUAGE:
Write code comments and variable names in the SAME LANGUAGE as the user's request. If they ask in Spanish, write Spanish comments. Match their language in code comments.

HOW TO WRITE CODE:
- Output primarily code. Keep explanations minimal — use inline code comments instead of separate commentary.
- Match the project's existing code style (naming, formatting, patterns).
- Include necessary imports if they are not already present in the file.
- If the request asks to modify existing code, output the complete modified version.
- If the request is ambiguous, write the most reasonable implementation.
- Do not wrap code in markdown code fences inside the markers.

INLINE COMMENTS (ENCOURAGED):
Use code comments to explain non-obvious logic, tricky parts, or design decisions:
- Keep comments concise and directly above the relevant code
- Explain WHY, not WHAT (the code shows what)
- Example: "// Cache result to avoid recomputing on each call"
- Example: "// Handle edge case: empty input returns default"

PROJECT AWARENESS:
You receive the user's full project context. Use it actively:
- Follow existing patterns and conventions in the codebase.
- Use the same libraries and frameworks already in the project.
- If you spot bugs or issues in the surrounding code, add brief inline comments prefixed with "NOTE:".

RULES:
- Output code with helpful inline comments, no external explanations.
- No emoji.
- No markdown outside the markers.]]

-- =============================================================================
-- PUBLIC FUNCTIONS
-- =============================================================================

---Get the system prompt
---@return string prompt
function M.get_system_prompt()
  return M.SYSTEM_PROMPT
end

---Build the user prompt with pending questions
---@param questions table[] List of pending questions {id, question, block_start?, block_end?, filepath?}
---@param context_formatted string Formatted code context
---@param opts? table Options {filepath?: string}
---@return string prompt
function M.build_user_prompt(questions, context_formatted, opts)
  opts = opts or {}

  local prompt_parts = {}

  -- Add pending questions FIRST (more important)
  table.insert(prompt_parts, "=== QUESTIONS TO ANSWER ===")
  table.insert(prompt_parts, "")
  for _, q in ipairs(questions) do
    -- Include question ID and text
    table.insert(prompt_parts, string.format("[%s]: %s", q.id, q.question))

    -- Include location info if available
    if q.block_start or q.filepath then
      local location_parts = {}
      if q.filepath or opts.filepath then
        local filepath = q.filepath or opts.filepath
        -- Get relative filename for cleaner display
        local filename = vim.fn.fnamemodify(filepath, ":t")
        table.insert(location_parts, filename)
      end
      if q.block_start then
        table.insert(location_parts, "line " .. q.block_start)
        if q.block_end and q.block_end ~= q.block_start then
          location_parts[#location_parts] = "line " .. q.block_start .. "-" .. q.block_end
        end
      end
      if #location_parts > 0 then
        table.insert(prompt_parts, string.format("(Location: %s)", table.concat(location_parts, ", ")))
      end
    end
    table.insert(prompt_parts, "")
  end

  -- Add code context
  if context_formatted and context_formatted ~= "" then
    table.insert(prompt_parts, "=== CODE CONTEXT ===")
    table.insert(prompt_parts, context_formatted)
    table.insert(prompt_parts, "")
  end

  -- Final instruction
  table.insert(prompt_parts, "---")
  table.insert(prompt_parts, "Answer each question using [ANSWER:id]...[/ANSWER:id] markers.")

  return table.concat(prompt_parts, "\n")
end

---Get the code mode system prompt
---@return string prompt
function M.get_code_system_prompt()
  return M.CODE_SYSTEM_PROMPT
end

---Build the user prompt for code requests
---@param code_requests table[] List of pending code requests {id, question, block_start?, block_end?, filepath?}
---@param context_formatted string Formatted code context
---@param opts? table Options {filepath?: string}
---@return string prompt
function M.build_code_user_prompt(code_requests, context_formatted, opts)
  opts = opts or {}

  local prompt_parts = {}

  -- Add code requests FIRST
  table.insert(prompt_parts, "=== CODE REQUESTS ===")
  table.insert(prompt_parts, "")
  for _, req in ipairs(code_requests) do
    table.insert(prompt_parts, string.format("[%s]: %s", req.id, req.question))

    if req.block_start or req.filepath then
      local location_parts = {}
      if req.filepath or opts.filepath then
        local filepath = req.filepath or opts.filepath
        local filename = vim.fn.fnamemodify(filepath, ":t")
        table.insert(location_parts, filename)
      end
      if req.block_start then
        table.insert(location_parts, "line " .. req.block_start)
        if req.block_end and req.block_end ~= req.block_start then
          location_parts[#location_parts] = "line " .. req.block_start .. "-" .. req.block_end
        end
      end
      if #location_parts > 0 then
        table.insert(prompt_parts, string.format("(Location: %s)", table.concat(location_parts, ", ")))
      end
    end
    table.insert(prompt_parts, "")
  end

  -- Add code context
  if context_formatted and context_formatted ~= "" then
    table.insert(prompt_parts, "=== CODE CONTEXT ===")
    table.insert(prompt_parts, context_formatted)
    table.insert(prompt_parts, "")
  end

  -- Final instruction
  table.insert(prompt_parts, "---")
  table.insert(prompt_parts, "Generate code for each request using [CODE:id]...[/CODE:id] markers. Output only code, no explanations.")

  return table.concat(prompt_parts, "\n")
end

return M
