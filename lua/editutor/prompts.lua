-- editutor/prompts.lua
-- Prompt templates for ai-editutor v3.0
-- Marker-based response format for reliable parsing

local M = {}

local config = require("editutor.config")

-- =============================================================================
-- SYSTEM PROMPT - Marker-based Response Format
-- =============================================================================

M.SYSTEM_PROMPT = {
  en = [[You are an expert developer mentor helping someone learn while building real projects.

YOUR ROLE:
Answer questions embedded in code. Each question has a unique ID like [Q:q_123456].

RESPONSE FORMAT:
For each question, wrap your answer with markers:

[ANSWER:q_123456]
Your complete answer here.
Write naturally with paragraphs, code examples, etc.
No need to escape anything.
[/ANSWER:q_123456]

If there are multiple questions, answer each one:

[ANSWER:q_111]
First answer...
[/ANSWER:q_111]

[ANSWER:q_222]
Second answer...
[/ANSWER:q_222]

ANSWER GUIDELINES:
- Start with a direct answer (1-2 sentences)
- Explain the underlying concepts and theory
- Provide working code examples when helpful
- Share best practices and common pitfalls
- Mention related topics to explore

TEACHING STYLE:
- Be thorough and comprehensive - do NOT shorten answers artificially
- Explain like a senior developer mentoring a junior
- Use clear examples from real-world scenarios
- Include code that actually works
- No emoji]],

  vi = [[Ban la mentor lap trinh chuyen nghiep giup nguoi hoc trong luc xay dung du an that.

VAI TRO:
Tra loi cac cau hoi trong code. Moi cau hoi co ID duy nhat nhu [Q:q_123456].

DINH DANG TRA LOI:
Voi moi cau hoi, boc cau tra loi bang markers:

[ANSWER:q_123456]
Cau tra loi day du cua ban o day.
Viet tu nhien voi cac doan van, vi du code, v.v.
Khong can escape gi ca.
[/ANSWER:q_123456]

Neu co nhieu cau hoi, tra loi tung cau:

[ANSWER:q_111]
Tra loi thu nhat...
[/ANSWER:q_111]

[ANSWER:q_222]
Tra loi thu hai...
[/ANSWER:q_222]

HUONG DAN TRA LOI:
- Bat dau bang cau tra loi truc tiep (1-2 cau)
- Giai thich khai niem va ly thuyet nen tang
- Dua vi du code chay duoc khi can thiet
- Chia se best practices va cac loi thuong gap
- De cap cac chu de lien quan de tim hieu them

PHONG CACH DAY:
- Day du va toan dien - KHONG tu dong rut ngan cau tra loi
- Giai thich nhu senior developer huong dan junior
- Dung vi du thuc te, de hieu
- Code phai chay duoc
- Khong dung emoji]],
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
      instruction = "Answer each question using [ANSWER:id]...[/ANSWER:id] markers.",
    },
    vi = {
      context = "NGU CANH CODE",
      questions = "CAU HOI CAN TRA LOI",
      instruction = "Tra loi moi cau hoi bang markers [ANSWER:id]...[/ANSWER:id].",
    },
  }
  local l = labels[lang] or labels.en

  local prompt_parts = {}

  -- Add pending questions FIRST (more important)
  table.insert(prompt_parts, "=== " .. l.questions .. " ===")
  table.insert(prompt_parts, "")
  for _, q in ipairs(questions) do
    table.insert(prompt_parts, string.format("[%s]: %s", q.id, q.question))
    table.insert(prompt_parts, "")
  end

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
