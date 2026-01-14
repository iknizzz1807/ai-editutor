-- editutor/init.lua
-- AI EduTutor - A Neovim plugin that teaches you to code better

local M = {}

local config = require("editutor.config")
local parser = require("editutor.parser")
local context = require("editutor.context")
local prompts = require("editutor.prompts")
local provider = require("editutor.provider")
local ui = require("editutor.ui")
local hints = require("editutor.hints")
local knowledge = require("editutor.knowledge")

M._name = "EduTutor"
M._version = "0.6.0"
M._setup_called = false

-- UI Messages for internationalization
M._messages = {
  en = {
    no_comment = "No mentor comment found near cursor.\nUse // Q: your question",
    thinking = "Thinking about: ",
    error = "Error: ",
    no_response = "No response received",
    modes_title = "AI EduTutor - Available Modes",
    modes_instruction = "Write a comment with one of these prefixes, then press ",
    examples = "Examples:",
    hints_title = "Incremental Hints:",
    hints_instruction = "Use :EduTutorHint to get progressive hints (level 1-4)",
    hints_next = "Press 'n' in the popup to get the next hint level",
    history_title = "EduTutor - Recent History",
    history_empty = "No history found",
    history_language = "Language",
    search_prompt = "Search knowledge: ",
    search_results = "Search Results: '%s'",
    search_found = "Found %d entries",
    search_empty = "No results found for: ",
    export_success = "Exported to: ",
    export_failed = "Export failed: ",
    stats_title = "EduTutor - Statistics",
    stats_total = "Total Q&A entries",
    stats_by_mode = "By Mode:",
    stats_by_language = "By Language:",
    getting_hint = "Getting next hint...",
    lsp_context = "Gathering context from LSP...",
    lsp_not_available = "LSP not available - using current file context only",
    lsp_found_defs = "Found %d related definitions",
  },
  vi = {
    no_comment = "Không tìm thấy comment mentor gần con trỏ.\nSử dụng // Q: câu hỏi của bạn",
    thinking = "Đang suy nghĩ về: ",
    error = "Lỗi: ",
    no_response = "Không nhận được phản hồi",
    modes_title = "AI EduTutor - Các Chế Độ",
    modes_instruction = "Viết comment với một trong các tiền tố sau, rồi nhấn ",
    examples = "Ví dụ:",
    hints_title = "Gợi Ý Từng Bước:",
    hints_instruction = "Dùng :EduTutorHint để nhận gợi ý từng bước (cấp 1-4)",
    hints_next = "Nhấn 'n' trong popup để nhận gợi ý tiếp theo",
    history_title = "EduTutor - Lịch Sử Gần Đây",
    history_empty = "Không có lịch sử",
    history_language = "Ngôn ngữ",
    search_prompt = "Tìm kiếm kiến thức: ",
    search_results = "Kết quả tìm kiếm: '%s'",
    search_found = "Tìm thấy %d mục",
    search_empty = "Không tìm thấy kết quả cho: ",
    export_success = "Đã xuất ra: ",
    export_failed = "Xuất thất bại: ",
    stats_title = "EduTutor - Thống Kê",
    stats_total = "Tổng số Q&A",
    stats_by_mode = "Theo Chế Độ:",
    stats_by_language = "Theo Ngôn Ngữ:",
    getting_hint = "Đang lấy gợi ý tiếp theo...",
    lsp_context = "Đang thu thập context từ LSP...",
    lsp_not_available = "LSP không khả dụng - chỉ sử dụng context file hiện tại",
    lsp_found_defs = "Tìm thấy %d definitions liên quan",
  },
}

---Get a message in the current language
---@param key string Message key
---@return string Message text
function M._msg(key)
  local lang = prompts.get_language()
  local messages = M._messages[lang] or M._messages.en
  return messages[key] or M._messages.en[key] or key
end

---Setup the plugin
---@param opts? table User configuration
function M.setup(opts)
  M._setup_called = true
  config.setup(opts)

  -- Create user commands
  M._create_commands()

  -- Setup keymaps
  M._setup_keymaps()

  -- Check provider on setup
  local ready, err = provider.check_provider()
  if not ready then
    vim.notify("[EduTutor] Warning: " .. (err or "Provider not ready"), vim.log.levels.WARN)
  end
end

---Create user commands
function M._create_commands()
  vim.api.nvim_create_user_command("EduTutorAsk", function()
    M.ask()
  end, { desc = "Ask EduTutor about the current comment" })

  vim.api.nvim_create_user_command("EduTutorHint", function()
    M.ask_with_hints()
  end, { desc = "Ask with incremental hints" })

  vim.api.nvim_create_user_command("EduTutorQuestion", function()
    M.ask_mode("question")
  end, { desc = "Ask in Question mode" })

  vim.api.nvim_create_user_command("EduTutorSocratic", function()
    M.ask_mode("socratic")
  end, { desc = "Ask in Socratic mode" })

  vim.api.nvim_create_user_command("EduTutorReview", function()
    M.ask_mode("review")
  end, { desc = "Review current function" })

  vim.api.nvim_create_user_command("EduTutorDebug", function()
    M.ask_mode("debug")
  end, { desc = "Debug assistance" })

  vim.api.nvim_create_user_command("EduTutorExplain", function()
    M.ask_mode("explain")
  end, { desc = "Explain concept" })

  vim.api.nvim_create_user_command("EduTutorClose", function()
    ui.close()
  end, { desc = "Close tutor popup" })

  vim.api.nvim_create_user_command("EduTutorStream", function()
    M.ask_stream()
  end, { desc = "Ask with streaming response" })

  vim.api.nvim_create_user_command("EduTutorModes", function()
    M.show_modes()
  end, { desc = "Show available modes" })

  -- Knowledge commands
  vim.api.nvim_create_user_command("EduTutorHistory", function()
    M.show_history()
  end, { desc = "Show Q&A history" })

  vim.api.nvim_create_user_command("EduTutorSearch", function(opts)
    M.search_knowledge(opts.args)
  end, { nargs = "?", desc = "Search knowledge base" })

  vim.api.nvim_create_user_command("EduTutorExport", function(opts)
    M.export_knowledge(opts.args)
  end, { nargs = "?", desc = "Export knowledge to markdown" })

  vim.api.nvim_create_user_command("EduTutorStats", function()
    M.show_stats()
  end, { desc = "Show knowledge stats" })

  -- Language command
  vim.api.nvim_create_user_command("EduTutorLang", function(opts)
    M.set_language(opts.args ~= "" and opts.args or nil)
  end, {
    nargs = "?",
    complete = function()
      return { "English", "Vietnamese", "en", "vi" }
    end,
    desc = "Set response language (English/Vietnamese)",
  })
end

---Setup keymaps
function M._setup_keymaps()
  local keymaps = config.options.keymaps

  -- Main ask keymap
  if keymaps.ask then
    vim.keymap.set("n", keymaps.ask, M.ask, { desc = "EduTutor: Ask" })
  end

  -- Streaming keymap
  if keymaps.stream then
    vim.keymap.set("n", keymaps.stream, M.ask_stream, { desc = "EduTutor: Ask (Stream)" })
  end
end

---Main ask function - detect and respond to mentor comments
---Uses LSP to gather context from related project files
function M.ask()
  -- Find query at or near cursor
  local query = parser.find_query()

  if not query then
    vim.notify("[EduTutor] " .. M._msg("no_comment"), vim.log.levels.WARN)
    return
  end

  -- Get mode from query
  local mode = query.mode_name or config.options.default_mode

  -- Show loading while gathering context
  ui.show_loading(M._msg("lsp_context"))

  -- Extract context with LSP (async)
  context.extract_with_lsp(function(context_formatted, has_lsp)
    -- Warn if no LSP
    if not has_lsp then
      vim.notify("[EduTutor] " .. M._msg("lsp_not_available"), vim.log.levels.WARN)
    end

    -- Build prompts
    local system_prompt = prompts.get_system_prompt(mode)
    local user_prompt = prompts.build_user_prompt(query.question, context_formatted, mode)

    -- Update loading message
    ui.show_loading(M._msg("thinking") .. query.question:sub(1, 50) .. "...")

    -- Query LLM
    provider.query_async(system_prompt, user_prompt, function(response, err)
      if err then
        ui.close()
        vim.notify("[EduTutor] " .. M._msg("error") .. err, vim.log.levels.ERROR)
        return
      end

      if not response then
        ui.close()
        vim.notify("[EduTutor] " .. M._msg("no_response"), vim.log.levels.ERROR)
        return
      end

      -- Save to knowledge base
      local filepath = vim.api.nvim_buf_get_name(0)
      local lang = vim.bo.filetype
      knowledge.save({
        mode = mode,
        question = query.question,
        answer = response,
        language = lang,
        filepath = filepath,
      })

      -- Show response
      ui.show(response, mode, query.question)
    end)
  end)
end

---Ask with streaming response
---Uses LSP to gather context from related project files
function M.ask_stream()
  local query = parser.find_query()

  if not query then
    vim.notify("[EduTutor] " .. M._msg("no_comment"), vim.log.levels.WARN)
    return
  end

  local mode = query.mode_name or config.options.default_mode

  -- Show loading while gathering context
  ui.show_loading(M._msg("lsp_context"))

  -- Extract context with LSP (async)
  context.extract_with_lsp(function(context_formatted, has_lsp)
    -- Warn if no LSP
    if not has_lsp then
      vim.notify("[EduTutor] " .. M._msg("lsp_not_available"), vim.log.levels.WARN)
    end

    -- Build prompts
    local system_prompt = prompts.get_system_prompt(mode)
    local user_prompt = prompts.build_user_prompt(query.question, context_formatted, mode)

    -- Start streaming UI
    ui.start_stream(mode, query.question, nil)

    -- Stream response
    local job_id = provider.query_stream(
      system_prompt,
      user_prompt,
      -- On each chunk
      function(chunk)
        ui.append_stream(chunk)
      end,
      -- On done
      function(full_response, err)
        if err then
          ui.finish_stream(false, err)
          return
        end

        ui.finish_stream(true, nil)

        -- Save to knowledge base
        local content = ui.get_stream_content()
        local filepath = vim.api.nvim_buf_get_name(0)
        local lang = vim.bo.filetype
        if content and content ~= "" then
          knowledge.save({
            mode = mode,
            question = query.question,
            answer = content,
            language = lang,
            filepath = filepath,
            tags = { "stream" },
          })
        end
      end
    )

    -- Store job_id for cancellation (update UI state)
    if job_id and ui.is_open() then
      -- The UI already handles cancellation via the job_id passed to start_stream
    end
  end)
end

---Ask with incremental hints system
---Uses LSP to gather context from related project files
function M.ask_with_hints()
  local query = parser.find_query()

  if not query then
    vim.notify("[EduTutor] " .. M._msg("no_comment"), vim.log.levels.WARN)
    return
  end

  local mode = query.mode_name or config.options.default_mode

  -- Show loading while gathering context
  ui.show_loading(M._msg("lsp_context"))

  -- Extract context with LSP (async)
  context.extract_with_lsp(function(context_formatted, has_lsp)
    -- Warn if no LSP
    if not has_lsp then
      vim.notify("[EduTutor] " .. M._msg("lsp_not_available"), vim.log.levels.WARN)
    end

    -- Get or create hint session
    local session = hints.get_session(query.question, mode, context_formatted)

    -- Function to request and show next hint
    local function show_next_hint()
      ui.show_loading(M._msg("getting_hint"))

      hints.request_next_hint(session, function(response, level, has_more, err)
        if err then
          ui.close()
          vim.notify("[EduTutor] " .. M._msg("error") .. err, vim.log.levels.ERROR)
          return
        end

        if not response then
          ui.close()
          vim.notify("[EduTutor] " .. M._msg("no_response"), vim.log.levels.ERROR)
          return
        end

        -- Save to knowledge if final hint
        if level == hints.MAX_LEVEL then
          local filepath = vim.api.nvim_buf_get_name(0)
          local lang = vim.bo.filetype
          knowledge.save({
            mode = mode,
            question = query.question,
            answer = response,
            language = lang,
            filepath = filepath,
            tags = { "hint", "level-" .. level },
          })
        end

        -- Show response with hint info
        ui.show(response, mode, query.question, {
          hint_level = level,
          has_more_hints = has_more,
          hint_callback = has_more and show_next_hint or nil,
        })
      end)
    end

    -- Start with first hint
    show_next_hint()
  end)
end

---Ask with a specific mode override
---@param mode string Mode name
function M.ask_mode(mode)
  -- Prompt user for question if no comment found
  local query = parser.find_query()

  if query then
    -- Override mode
    query.mode_name = mode
  else
    -- Prompt for question
    vim.ui.input({ prompt = string.format("[%s] Enter question: ", mode:upper()) }, function(input)
      if not input or input == "" then
        return
      end

      -- Create synthetic query
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      M._process_question(input, mode, cursor_line)
    end)
    return
  end

  -- Process found query with mode override
  M._process_query(query, mode)
end

---Process a query
---@param query table Parsed query
---@param mode_override? string Mode override
function M._process_query(query, mode_override)
  local mode = mode_override or query.mode_name or config.options.default_mode

  -- Extract context
  local ctx = context.extract(nil, query.line)

  -- Build prompts
  local system_prompt = prompts.get_system_prompt(mode)
  local context_formatted = context.format_for_prompt(ctx)
  local user_prompt = prompts.build_user_prompt(query.question, context_formatted, mode)

  -- Show loading
  ui.show_loading("Thinking...")

  -- Query LLM
  provider.query_async(system_prompt, user_prompt, function(response, err)
    if err then
      ui.close()
      vim.notify("[EduTutor] Error: " .. err, vim.log.levels.ERROR)
      return
    end

    if not response then
      ui.close()
      vim.notify("[EduTutor] No response received", vim.log.levels.ERROR)
      return
    end

    -- Save to knowledge base
    knowledge.save({
      mode = mode,
      question = query.question,
      answer = response,
      language = ctx.language,
      filepath = ctx.filepath,
    })

    -- Show response
    ui.show(response, mode, query.question)
  end)
end

---Process a direct question
---@param question string Question text
---@param mode string Mode name
---@param line number Line number for context
function M._process_question(question, mode, line)
  -- Extract context
  local ctx = context.extract(nil, line)

  -- Build prompts
  local system_prompt = prompts.get_system_prompt(mode)
  local context_formatted = context.format_for_prompt(ctx)
  local user_prompt = prompts.build_user_prompt(question, context_formatted, mode)

  -- Show loading
  ui.show_loading("Thinking...")

  -- Query LLM
  provider.query_async(system_prompt, user_prompt, function(response, err)
    if err then
      ui.close()
      vim.notify("[EduTutor] Error: " .. err, vim.log.levels.ERROR)
      return
    end

    if not response then
      ui.close()
      vim.notify("[EduTutor] No response received", vim.log.levels.ERROR)
      return
    end

    -- Save to knowledge base
    knowledge.save({
      mode = mode,
      question = question,
      answer = response,
      language = ctx.language,
      filepath = ctx.filepath,
    })

    -- Show response
    ui.show(response, mode, question)
  end)
end

---Show available modes
function M.show_modes()
  local lang = prompts.get_language()
  local is_vi = lang == "vi"

  local help = {
    M._msg("modes_title"),
    "================================",
    "",
    M._msg("modes_instruction") .. (config.options.keymaps.ask or "<leader>ma"),
    "",
  }

  -- Mode descriptions based on language
  local mode_descriptions = {
    en = {
      Q = "Question - Direct answers with explanations",
      S = "Socratic - Guided discovery through questions",
      R = "Review - Code review and best practices",
      D = "Debug - Guided debugging assistance",
      E = "Explain - Deep concept explanations",
    },
    vi = {
      Q = "Hỏi Đáp - Trả lời trực tiếp với giải thích",
      S = "Socratic - Khám phá qua câu hỏi dẫn dắt",
      R = "Review - Đánh giá code và best practices",
      D = "Debug - Hỗ trợ debug có hướng dẫn",
      E = "Giải Thích - Giải thích khái niệm sâu",
    },
  }

  local descs = mode_descriptions[lang] or mode_descriptions.en
  for mode_char, desc in pairs(descs) do
    table.insert(help, string.format("// %s: %s", mode_char, desc))
  end

  table.insert(help, "")
  table.insert(help, M._msg("examples"))

  if is_vi then
    table.insert(help, "  // Q: Độ phức tạp thời gian của function này là gì?")
    table.insert(help, "  // S: Tại sao async/await có thể tốt hơn ở đây?")
    table.insert(help, "  // R: Review function này về vấn đề bảo mật")
    table.insert(help, "  // D: Function này đôi khi trả về nil, tại sao?")
    table.insert(help, "  // E: Giải thích closures trong JavaScript")
  else
    table.insert(help, "  // Q: What is the time complexity of this function?")
    table.insert(help, "  // S: Why might async/await be better here?")
    table.insert(help, "  // R: Review this function for security issues")
    table.insert(help, "  // D: This function returns nil sometimes, why?")
    table.insert(help, "  // E: Explain closures in JavaScript")
  end

  table.insert(help, "")
  table.insert(help, M._msg("hints_title"))
  table.insert(help, "  " .. M._msg("hints_instruction"))
  table.insert(help, "  " .. M._msg("hints_next"))

  ui.show(table.concat(help, "\n"), nil, nil)
end

---Show recent Q&A history
function M.show_history()
  local entries = knowledge.get_recent(20)

  if #entries == 0 then
    vim.notify("[EduTutor] " .. M._msg("history_empty"), vim.log.levels.INFO)
    return
  end

  local lines = {
    M._msg("history_title"),
    "============================",
    "",
  }

  for i, entry in ipairs(entries) do
    table.insert(lines, string.format("%d. [%s] %s", i, entry.mode:upper(), entry.question:sub(1, 60)))
    if entry.language then
      table.insert(lines, string.format("   %s: %s", M._msg("history_language"), entry.language))
    end
    table.insert(lines, "")
  end

  table.insert(lines, "---")
  table.insert(lines, "Use :EduTutorSearch <query> to search")
  table.insert(lines, "Use :EduTutorExport to export to markdown")

  ui.show(table.concat(lines, "\n"), nil, nil)
end

---Search knowledge base
---@param query? string Search query
function M.search_knowledge(query)
  if not query or query == "" then
    vim.ui.input({ prompt = M._msg("search_prompt") }, function(input)
      if input and input ~= "" then
        M.search_knowledge(input)
      end
    end)
    return
  end

  local results = knowledge.search(query)

  if #results == 0 then
    vim.notify("[EduTutor] " .. M._msg("search_empty") .. query, vim.log.levels.INFO)
    return
  end

  local lines = {
    string.format(M._msg("search_results"), query),
    string.format(M._msg("search_found"), #results),
    "========================",
    "",
  }

  for i, entry in ipairs(results) do
    table.insert(lines, string.format("## %d. [%s] %s", i, entry.mode:upper(), entry.question))
    table.insert(lines, "")
    -- Truncate answer
    local answer_preview = entry.answer:sub(1, 200):gsub("\n", " ")
    if #entry.answer > 200 then
      answer_preview = answer_preview .. "..."
    end
    table.insert(lines, answer_preview)
    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "")
  end

  ui.show(table.concat(lines, "\n"), nil, nil)
end

---Export knowledge to markdown
---@param filepath? string Output path
function M.export_knowledge(filepath)
  local success, err = knowledge.export_markdown(filepath)

  if success then
    local path = filepath or (os.getenv("HOME") .. "/editutor_export.md")
    vim.notify("[EduTutor] " .. M._msg("export_success") .. path, vim.log.levels.INFO)
  else
    vim.notify("[EduTutor] " .. M._msg("export_failed") .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end

---Show knowledge statistics
function M.show_stats()
  local stats = knowledge.get_stats()

  local lines = {
    M._msg("stats_title"),
    "========================",
    "",
    string.format("%s: %d", M._msg("stats_total"), stats.total),
    "",
    M._msg("stats_by_mode"),
  }

  for mode, count in pairs(stats.by_mode) do
    table.insert(lines, string.format("  %s: %d", mode:upper(), count))
  end

  table.insert(lines, "")
  table.insert(lines, M._msg("stats_by_language"))

  for lang, count in pairs(stats.by_language) do
    table.insert(lines, string.format("  %s: %d", lang, count))
  end

  ui.show(table.concat(lines, "\n"), nil, nil)
end

---Get plugin version
---@return string
function M.version()
  return M._version
end

-- =============================================================================
-- Language Functions
-- =============================================================================

---Set the response language
---@param lang? string Language to set (English, Vietnamese, en, vi)
function M.set_language(lang)
  if not lang then
    -- Show current language and options
    local current = config.options.language
    local available = prompts.get_available_languages()

    local lines = {
      "EduTutor - Language Settings",
      "============================",
      "",
      string.format("Current language: %s", current),
      "",
      "Available languages:",
    }

    for _, l in ipairs(available) do
      local marker = (l.name == current or l.key == current) and " (current)" or ""
      table.insert(lines, string.format("  - %s (%s)%s", l.name, l.key, marker))
    end

    table.insert(lines, "")
    table.insert(lines, "Usage:")
    table.insert(lines, "  :EduTutorLang Vietnamese  - Switch to Vietnamese")
    table.insert(lines, "  :EduTutorLang English     - Switch to English")
    table.insert(lines, "  :EduTutorLang vi          - Switch to Vietnamese")
    table.insert(lines, "  :EduTutorLang en          - Switch to English")

    ui.show(table.concat(lines, "\n"), nil, nil)
    return
  end

  -- Validate and set language
  local valid_langs = {
    ["English"] = "English",
    ["english"] = "English",
    ["en"] = "English",
    ["Vietnamese"] = "Vietnamese",
    ["vietnamese"] = "Vietnamese",
    ["vi"] = "Vietnamese",
    ["Tiếng Việt"] = "Vietnamese",
  }

  local normalized = valid_langs[lang]
  if not normalized then
    vim.notify(
      string.format("[EduTutor] Invalid language: %s. Use 'English' or 'Vietnamese'.", lang),
      vim.log.levels.ERROR
    )
    return
  end

  config.options.language = normalized

  -- Notify in the appropriate language
  local messages = {
    ["English"] = "Language set to English",
    ["Vietnamese"] = "Đã chuyển sang tiếng Việt",
  }

  vim.notify("[EduTutor] " .. messages[normalized], vim.log.levels.INFO)
end

---Get current language
---@return string Current language setting
function M.get_language()
  return config.options.language
end

return M
