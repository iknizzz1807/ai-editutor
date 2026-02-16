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

  vi = [[Bạn là mentor lập trình chuyên nghiệp giúp người học trong lúc xây dựng dự án thực tế.

VAI TRÒ:
Trả lời các câu hỏi trong code. Mỗi câu hỏi có ID duy nhất như [Q:q_123456].

ĐỊNH DẠNG PHẢN HỒI:
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

HƯỚNG DẪN TRẢ LỜI:
- Bắt đầu bằng câu trả lời trực tiếp (1-2 câu)
- Giải thích khái niệm và lý thuyết nền tảng
- Đưa ví dụ code chạy được khi cần thiết
- Chia sẻ best practices và các lỗi thường gặp
- Đề cập các chủ đề liên quan để tìm hiểu thêm

PHONG CÁCH DẠY:
- Đầy đủ và toàn diện - KHÔNG tự động rút ngắn câu trả lời
- Giải thích như senior developer hướng dẫn junior
- Dùng ví dụ thực tế, dễ hiểu
- Code phải chạy được
- Không dùng emoji]],
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
    ["Tiếng Việt"] = "vi",
    ["tiếng việt"] = "vi",
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
---@param questions table[] List of pending questions {id, question, block_start?, block_end?, filepath?}
---@param context_formatted string Formatted code context
---@param opts? table Options {filepath?: string}
---@return string prompt
function M.build_user_prompt(questions, context_formatted, opts)
  opts = opts or {}
  local lang = get_lang_key()
  local labels = {
    en = {
      context = "CODE CONTEXT",
      questions = "QUESTIONS TO ANSWER",
      instruction = "Answer each question using [ANSWER:id]...[/ANSWER:id] markers.",
      location = "Location",
      line = "line",
    },
    vi = {
      context = "NGỮ CẢNH CODE",
      questions = "CÂU HỎI CẦN TRẢ LỜI",
      instruction = "Trả lời mỗi câu hỏi bằng markers [ANSWER:id]...[/ANSWER:id].",
      location = "Vị trí",
      line = "dòng",
    },
  }
  local l = labels[lang] or labels.en

  local prompt_parts = {}

  -- Add pending questions FIRST (more important)
  table.insert(prompt_parts, "=== " .. l.questions .. " ===")
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
        table.insert(location_parts, l.line .. " " .. q.block_start)
        if q.block_end and q.block_end ~= q.block_start then
          location_parts[#location_parts] = l.line .. " " .. q.block_start .. "-" .. q.block_end
        end
      end
      if #location_parts > 0 then
        table.insert(prompt_parts, string.format("(%s: %s)", l.location, table.concat(location_parts, ", ")))
      end
    end
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
    { key = "vi", name = "Tiếng Việt" },
  }
end

return M
