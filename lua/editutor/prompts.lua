-- editutor/prompts.lua
-- Prompt templates for ai-editutor v3.0
-- Marker-based response format for reliable parsing

local M = {}

local config = require("editutor.config")

-- =============================================================================
-- SYSTEM PROMPT - Marker-based Response Format
-- =============================================================================

M.SYSTEM_PROMPT = {
  en = [[You are a sharp pair programmer embedded in the user's codebase. You answer questions inline while they build real projects.

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
- No emoji. Keep it real.]],

  vi = [[Bạn là một pair programmer sắc bén, hoạt động ngay trong codebase của người dùng. Bạn trả lời câu hỏi inline khi họ xây dựng dự án thực tế.

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

CÁCH TRẢ LỜI:
Đọc intent của câu hỏi và điều chỉnh style:

- Quick fix / hỏi syntax / đang stuck chỉ cần chạy được → Trả lời ngắn gọn, thẳng vào vấn đề. Show fix, xong. Không giảng bài.
- Tại sao nó work / X hoạt động như thế nào / muốn hiểu sâu → Đưa kiến thức vững chắc. Giải thích concept, nối các mảnh lại với nhau, đủ depth để thực sự hiểu. Nhưng giữ focus — không nhồi nhét trivia.

NHẬN THỨC DỰ ÁN:
Bạn nhận được context dự án đầy đủ. Sử dụng nó chủ động:
- Nếu phát hiện bug, pattern xấu, bad practice, hoặc thứ sẽ gây rắc rối → nói thẳng, kể cả khi user không hỏi. Ghi chú bằng "Note:" hoặc "⚠".
- Tham chiếu code thực tế của user khi liên quan. Bạn biết họ đang build gì — trả lời trong ngữ cảnh đó, không dùng ví dụ generic.

NGUYÊN TẮC:
- Luôn trả lời dựa trên context dự án được cung cấp. Không bỏ qua.
- Không dùng emoji. Thẳng thắn.]],}

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
