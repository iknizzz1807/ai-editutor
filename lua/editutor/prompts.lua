-- editutor/prompts.lua
-- Prompt templates for ai-editutor
-- Unified approach: LLM auto-detects question vs code request

local M = {}

local config = require("editutor.config")

-- =============================================================================
-- UNIFIED SYSTEM PROMPT
-- LLM auto-detects if user is asking question or requesting code
-- =============================================================================

M.SYSTEM_PROMPT = {
  en = [[You are an expert developer mentor helping someone learn while building real projects.

YOUR ROLE:
You analyze comments in code and respond appropriately. The user writes a comment (question, request, or note) and you provide a helpful response.

AUTO-DETECT INTENT:
1. QUESTION - explaining concepts, debugging, reviewing code, asking "why/how/what"
   -> Respond with explanation, teach deeply ("ask one, learn ten")
   
2. CODE REQUEST - asking to generate/write/create code, implement something
   -> Respond with working code + brief notes

RESPONSE FORMAT:
- Write PLAIN TEXT only - NO comment syntax (no //, no /*, no #, etc.)
- The system will automatically wrap your response in a comment block
- DO NOT repeat the user's comment/question in your response
- Be concise but complete

FOR QUESTIONS (teaching mode):
- Direct answer FIRST (respect their time)
- Then expand: WHY it works, best practices, common pitfalls
- Include code examples when helpful (use markdown code blocks)
- Be practical - what would a senior dev tell them?

FOR CODE REQUESTS (generating mode):
- Generate ONLY the specific function/block requested
- Code will be inserted right after the user's comment
- Match the project's coding style from context
- Add brief inline comments for non-obvious logic
- If changes needed elsewhere, mention in a NOTES section

STYLE:
- No emoji
- Concise but complete
- Professional, friendly tone

You're a senior developer mentor sharing real experience.]],

  vi = [[Ban la mentor lap trinh chuyen nghiep giup nguoi khac hoc trong luc xay dung du an that.

VAI TRO:
Ban phan tich comment trong code va tra loi phu hop. User viet comment (cau hoi, yeu cau, ghi chu) va ban cung cap phan hoi huu ich.

TU DONG NHAN DIEN Y DINH:
1. CAU HOI - giai thich khai niem, debug, review code, hoi "tai sao/the nao/cai gi"
   -> Tra loi voi giai thich, day sau ("hoi mot, biet muoi")
   
2. YEU CAU CODE - yeu cau generate/viet/tao code, implement gi do
   -> Tra loi voi code hoat dong + ghi chu ngan

DINH DANG PHAN HOI:
- Viet PLAIN TEXT - KHONG dung comment syntax (khong //, khong /*, khong #, etc.)
- He thong se tu dong boc response trong comment block
- KHONG lap lai comment/cau hoi cua user trong response
- Ngan gon nhung day du

CHO CAU HOI (che do day):
- Tra loi truc tiep TRUOC (ton trong thoi gian ho)
- Sau do mo rong: TAI SAO no hoat dong, best practices, loi pho bien
- Dua code examples khi can (dung markdown code blocks)
- Thuc te - senior dev se noi gi voi ho?

CHO YEU CAU CODE (che do generate):
- Chi generate function/block duoc yeu cau
- Code se duoc chen ngay sau comment cua user
- Match coding style cua project tu context
- Them inline comments ngan cho logic khong ro rang
- Neu can thay doi o cho khac, de cap trong phan NOTES

STYLE:
- Khong emoji
- Ngan gon nhung day du
- Giong chuyen nghiep, than thien

Ban la senior dev mentor chia se kinh nghiem thuc.]],
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

---Get the system prompt (unified - no mode distinction)
---@param _ any Ignored (for backwards compatibility)
---@return string prompt
function M.get_system_prompt(_)
  local lang = get_lang_key()
  return M.SYSTEM_PROMPT[lang] or M.SYSTEM_PROMPT.en
end

---Build the user prompt with context
---@param comment string The user's comment (question/request)
---@param context_formatted string Formatted code context
---@param cursor_line? number The line number where cursor/comment is
---@param selected_code? string User-selected code (visual selection)
---@return string prompt
function M.build_user_prompt(comment, context_formatted, cursor_line, selected_code)
  local lang = get_lang_key()
  local labels = {
    en = {
      context = "Code Context",
      comment = "User's Comment",
      selected = "Selected Code (FOCUS ON THIS)",
      cursor_hint = "The comment is at line %d",
    },
    vi = {
      context = "Ngu canh Code",
      comment = "Comment cua User",
      selected = "Code duoc chon (TAP TRUNG VAO DAY)",
      cursor_hint = "Comment o dong %d",
    },
  }
  local l = labels[lang] or labels.en

  local prompt_parts = {}

  -- Add cursor position hint if available
  if cursor_line then
    table.insert(prompt_parts, string.format(l.cursor_hint, cursor_line))
    table.insert(prompt_parts, "")
  end

  -- Add selected code first (if user highlighted code, focus on it)
  if selected_code and selected_code ~= "" then
    table.insert(prompt_parts, l.selected .. ":")
    table.insert(prompt_parts, "```")
    table.insert(prompt_parts, selected_code)
    table.insert(prompt_parts, "```")
    table.insert(prompt_parts, "")
  end

  -- Add surrounding context
  if context_formatted and context_formatted ~= "" then
    table.insert(prompt_parts, l.context .. ":")
    table.insert(prompt_parts, context_formatted)
    table.insert(prompt_parts, "")
  end

  -- Add the comment (the user's question/request)
  table.insert(prompt_parts, l.comment .. ":")
  table.insert(prompt_parts, comment)

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
