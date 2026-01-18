-- editutor/prompts.lua
-- Prompt templates for ai-editutor v3.0
-- JSON response format for batch questions

local M = {}

local config = require("editutor.config")

-- =============================================================================
-- SYSTEM PROMPT - JSON Response Format
-- =============================================================================

M.SYSTEM_PROMPT = {
  en = [[You are an expert developer mentor helping someone learn while building real projects.

YOUR ROLE:
Answer questions embedded in code. Questions are marked with [Q:id] blocks containing [PENDING:id] markers.

RESPONSE FORMAT:
Respond with ONLY a raw JSON object. NO markdown code fences (no ```). Just the JSON directly:
{"q_1234567890": "Your answer here...", "q_9876543210": "Second answer..."}

CRITICAL JSON RULES:
1. Output ONLY the JSON object - nothing else
2. Keys are question IDs exactly as given (e.g., "q_1234567890")
3. Values are your answers as strings
4. Use \n\n for paragraph breaks within answers
5. Use \n followed by spaces for code indentation
6. Escape quotes with \"

ANSWER STRUCTURE (for each question):
1. DIRECT ANSWER - Answer the question first (1-2 sentences)
2. EXPLANATION - Why/how it works, underlying concepts
3. CODE EXAMPLE - Practical example if relevant (use \n for newlines, spaces for indent)
4. BEST PRACTICES - Tips, common pitfalls to avoid
5. RELATED CONCEPTS - What else to learn (brief)

EXAMPLE ANSWER FORMAT in JSON:
{"q_123": "Direct answer here.\n\nExplanation paragraph with more details about the concept.\n\nCode example:\n  function example() {\n    return value;\n  }\n\nBest practice: Always do X because Y.\n\nRelated: Look into A and B for deeper understanding."}

STYLE:
- No emoji
- Teach deeply but concisely
- Include working code examples
- Professional, mentor tone]],

  vi = [[Ban la mentor lap trinh chuyen nghiep giup nguoi hoc trong luc xay dung du an that.

VAI TRO:
Tra loi cac cau hoi trong code. Cau hoi duoc danh dau bang [Q:id] blocks chua [PENDING:id] markers.

DINH DANG RESPONSE:
Chi tra ve JSON object THUAN (KHONG co markdown code fences, KHONG co ```). Chi JSON truc tiep:
{"q_1234567890": "Cau tra loi...", "q_9876543210": "Cau tra loi thu hai..."}

QUY TAC JSON QUAN TRONG:
1. Chi output JSON object - khong gi khac
2. Keys la question IDs chinh xac (vd: "q_1234567890")
3. Values la cau tra loi dang string
4. Dung \n\n de tach paragraph trong cau tra loi
5. Dung \n va spaces cho code indentation
6. Escape quotes bang \"

CAU TRUC CAU TRA LOI (cho moi cau hoi):
1. TRA LOI TRUC TIEP - Tra loi cau hoi truoc (1-2 cau)
2. GIAI THICH - Tai sao/the nao, khai niem nen tang
3. VI DU CODE - Vi du thuc te neu phu hop (dung \n cho xuong dong, spaces cho indent)
4. BEST PRACTICES - Tips, loi pho bien can tranh
5. KIEN THUC LIEN QUAN - Con gi nen hoc them (ngan gon)

VI DU FORMAT CAU TRA LOI trong JSON:
{"q_123": "Tra loi truc tiep day.\n\nGiai thich chi tiet ve khai niem nay.\n\nVi du code:\n  function example() {\n    return value;\n  }\n\nBest practice: Luon lam X vi Y.\n\nLien quan: Tim hieu them ve A va B."}

STYLE:
- Khong emoji
- Day sau nhung ngan gon
- Co vi du code chay duoc
- Giong chuyen nghiep, mentor]],
}

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

---Get the language key from config language setting
---@return string "en" or "vi"
local function get_lang_key()
  local language = config.options.language or "English"
  local lang_map = {
    ["English"] = "en",
    ["english"] = "en",
    ["en"] = "en",
    ["Vietnamese"] = "vi",
    ["vietnamese"] = "vi",
    ["vi"] = "vi",
    ["Tieng Viet"] = "vi",
    ["tieng viet"] = "vi",
  }
  return lang_map[language] or "en"
end

-- =============================================================================
-- PUBLIC FUNCTIONS
-- =============================================================================

---Get the system prompt
---@return string prompt
function M.get_system_prompt()
  local lang = get_lang_key()
  return M.SYSTEM_PROMPT[lang] or M.SYSTEM_PROMPT.en
end

---Build the user prompt with pending questions
---@param questions table[] List of pending questions {id, question}
---@param context_formatted string Formatted code context
---@return string prompt
function M.build_user_prompt(questions, context_formatted)
  local lang = get_lang_key()
  local labels = {
    en = {
      context = "CODE CONTEXT",
      questions = "QUESTIONS TO ANSWER",
      instruction = "Respond with JSON only: {\"question_id\": \"answer\", ...}",
    },
    vi = {
      context = "NGU CANH CODE",
      questions = "CAU HOI CAN TRA LOI",
      instruction = "Tra loi bang JSON: {\"question_id\": \"answer\", ...}",
    },
  }
  local l = labels[lang] or labels.en

  local prompt_parts = {}

  -- Add pending questions FIRST (more important)
  table.insert(prompt_parts, "=== " .. l.questions .. " ===")
  for i, q in ipairs(questions) do
    table.insert(prompt_parts, string.format("[%s]: %s", q.id, q.question))
  end
  table.insert(prompt_parts, "")

  -- Add code context
  if context_formatted and context_formatted ~= "" then
    table.insert(prompt_parts, "=== " .. l.context .. " ===")
    table.insert(prompt_parts, context_formatted)
    table.insert(prompt_parts, "")
  end

  -- Final instruction
  table.insert(prompt_parts, "---")
  table.insert(prompt_parts, l.instruction)

  return table.concat(prompt_parts, "\n")
end

---Get current language setting
---@return string Language key ("en" or "vi")
function M.get_language()
  return get_lang_key()
end

---Get available languages
---@return table List of available languages
function M.get_available_languages()
  return {
    { key = "en", name = "English" },
    { key = "vi", name = "Tieng Viet" },
  }
end

return M
