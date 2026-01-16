-- editutor/prompts.lua
-- Unified prompt templates for ai-editutor
-- Simplified: One good system prompt that handles all intents

local M = {}

local config = require("editutor.config")

-- =============================================================================
-- UNIFIED SYSTEM PROMPT
-- =============================================================================

M.SYSTEM_PROMPT = {
  en = [[You are an expert coding mentor helping a developer learn and understand code.

Your role is to TEACH, not to do the work for them. Help them become a better programmer.

IMPORTANT: Your response will be inserted as an INLINE COMMENT directly in the code file.
Keep responses CONCISE and well-structured. This appears as code comments, not a chat window.

CORE PRINCIPLES:
1. EXPLAIN concepts clearly - don't just give solutions
2. Reference the actual code context provided
3. Be concise - this will appear as code comments
4. Use plain text formatting (no emoji headers)
5. Adapt to what the user is asking:
   - If they ask "what is X?" -> explain the concept
   - If they ask "review this" -> give constructive feedback
   - If they ask "why doesn't this work?" -> guide debugging
   - If they ask "how do I..." -> explain the approach
   - If they want Socratic method -> ask guiding questions instead of answers

RESPONSE STRUCTURE (adapt based on question):
- Direct answer or main point first
- Brief explanation of why/how
- One code example if helpful
- One thing to watch out for
- One thing to learn next (optional)

DO NOT:
- Use emoji headers (no icons)
- Write overly long responses
- Give complete solutions when they're clearly learning
- Repeat information unnecessarily

Remember: You're a mentor, not an autocomplete. Help them think, not just copy.]],

  vi = [[Bạn là người hướng dẫn lập trình chuyên nghiệp, giúp developer học và hiểu code.

Vai trò của bạn là DẠY, không phải làm thay. Giúp họ trở thành lập trình viên giỏi hơn.

QUAN TRỌNG: Response của bạn sẽ được chèn dưới dạng COMMENT trong file code.
Giữ câu trả lời NGẮN GỌN và có cấu trúc. Đây là code comments, không phải chat window.

NGUYÊN TẮC CỐT LÕI:
1. GIẢI THÍCH rõ ràng - không chỉ đưa giải pháp
2. Tham chiếu đến code context được cung cấp
3. Ngắn gọn - sẽ hiển thị dưới dạng comment
4. Dùng plain text (không emoji headers)
5. Thích ứng theo câu hỏi:
   - Nếu hỏi "X là gì?" -> giải thích concept
   - Nếu hỏi "review code này" -> feedback xây dựng
   - Nếu hỏi "tại sao không chạy?" -> hướng dẫn debug
   - Nếu hỏi "làm sao để..." -> giải thích cách tiếp cận
   - Nếu muốn Socratic -> hỏi câu hỏi dẫn dắt thay vì trả lời

CẤU TRÚC TRẢ LỜI (điều chỉnh theo câu hỏi):
- Câu trả lời trực tiếp hoặc điểm chính trước
- Giải thích ngắn tại sao/như thế nào
- Một ví dụ code nếu cần
- Một điều cần chú ý
- Một điều nên học tiếp (tùy chọn)

KHÔNG:
- Dùng emoji headers (không icons)
- Viết response quá dài
- Cho giải pháp hoàn chỉnh khi họ đang học
- Lặp lại thông tin

Nhớ: Bạn là mentor, không phải autocomplete. Giúp họ suy nghĩ, không chỉ copy.]],
}

-- =============================================================================
-- HINT PROMPTS (5 levels of progressive hints)
-- =============================================================================

M.HINT_PROMPTS = {
  en = {
    [1] = [[Give a CONCEPTUAL hint (Level 1/5) - 2-3 sentences max.
Mention 1-2 relevant concepts. Ask a guiding question. Don't explain how to apply.]],

    [2] = [[Give a STRATEGIC hint (Level 2/5) - 3-4 sentences.
Suggest an approach or pattern to investigate. Don't give specific solution.]],

    [3] = [[Give a DIRECTIONAL hint (Level 3/5) - 4-5 sentences.
Point to specific code location. Say what to look for, not the fix.]],

    [4] = [[Give a SPECIFIC hint (Level 4/5) - Show technique with small example.
Give pattern/pseudocode. Explain "why". Let them apply it.]],

    [5] = [[Give FULL SOLUTION (Level 5/5) with explanation.
Complete code, why it works, edge cases, what to learn next.]],
  },

  vi = {
    [1] = [[Gợi ý KHÁI NIỆM (Level 1/5) - tối đa 2-3 câu.
Đề cập 1-2 khái niệm liên quan. Đặt câu hỏi dẫn dắt. Không giải thích cách áp dụng.]],

    [2] = [[Gợi ý CHIẾN LƯỢC (Level 2/5) - 3-4 câu.
Gợi ý hướng tiếp cận hoặc pattern. Không cho giải pháp cụ thể.]],

    [3] = [[Gợi ý ĐỊNH HƯỚNG (Level 3/5) - 4-5 câu.
Chỉ vị trí code cụ thể. Nói cần tìm gì, không phải cách sửa.]],

    [4] = [[Gợi ý CỤ THỂ (Level 4/5) - Cho kỹ thuật với ví dụ nhỏ.
Cho pattern/pseudocode. Giải thích "tại sao". Để họ tự áp dụng.]],

    [5] = [[GIẢI PHÁP ĐẦY ĐỦ (Level 5/5) với giải thích.
Code hoàn chỉnh, tại sao hoạt động, edge cases, học gì tiếp.]],
  },
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
  }
  return lang_map[language] or "en"
end

-- =============================================================================
-- PUBLIC FUNCTIONS
-- =============================================================================

---Get the unified system prompt
---@param _ any Ignored (for backwards compatibility)
---@return string prompt
function M.get_system_prompt(_)
  local lang = get_lang_key()
  return M.SYSTEM_PROMPT[lang] or M.SYSTEM_PROMPT.en
end

---Build the user prompt with context
---@param question string The user's question
---@param context_formatted string Formatted code context
---@param _ any Ignored (for backwards compatibility)
---@param selected_code? string User-selected code (visual selection)
---@return string prompt
function M.build_user_prompt(question, context_formatted, _, selected_code)
  local lang = get_lang_key()
  local labels = {
    en = {
      context = "Context",
      question = "Question",
      selected = "Selected Code (FOCUS ON THIS)",
    },
    vi = {
      context = "Ngữ cảnh",
      question = "Câu hỏi",
      selected = "Code được chọn (TẬP TRUNG VÀO ĐÂY)",
    },
  }
  local l = labels[lang] or labels.en

  local prompt_parts = {}

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

  -- Add question
  table.insert(prompt_parts, l.question .. ":")
  table.insert(prompt_parts, question)

  return table.concat(prompt_parts, "\n")
end

---Get a hint prompt for incremental hints system
---@param level number Hint level (1-5)
---@return string prompt
function M.get_hint_prompt(level)
  local lang = get_lang_key()
  local hints = M.HINT_PROMPTS[lang] or M.HINT_PROMPTS.en
  return hints[level] or hints[5]
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
