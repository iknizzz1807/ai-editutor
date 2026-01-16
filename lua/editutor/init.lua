-- editutor/init.lua
-- ai-editutor - A Neovim plugin that teaches you to code better

local M = {}

local config = require("editutor.config")
local parser = require("editutor.parser")
local context = require("editutor.context")
local prompts = require("editutor.prompts")
local provider = require("editutor.provider")
local comment_writer = require("editutor.comment_writer")
local hints = require("editutor.hints")
local knowledge = require("editutor.knowledge")
local conversation = require("editutor.conversation")
local project_context = require("editutor.project_context")

-- v0.9.0: New modules
local cache = require("editutor.cache")
local loading = require("editutor.loading")
local indexer_available, indexer = pcall(require, "editutor.indexer")

M._name = "EduTutor"
M._version = "0.9.0"
M._setup_called = false
M._indexer_ready = false

-- UI Messages for internationalization
M._messages = {
  en = {
    no_comment = "No mentor comment found near cursor. Use // Q: your question",
    thinking = "Thinking...",
    error = "Error: ",
    no_response = "No response received",
    response_inserted = "Response inserted as comment",
    modes_title = "ai-editutor - Available Modes",
    modes_instruction = "Write a comment with one of these prefixes, then press ",
    examples = "Examples:",
    hints_title = "Incremental Hints:",
    hints_instruction = "Use :EduTutorHint to get progressive hints (level 1-4)",
    history_title = "ai-editutor - Recent History",
    history_empty = "No history found",
    history_language = "Language",
    search_prompt = "Search knowledge: ",
    search_results = "Search Results: '%s'",
    search_found = "Found %d entries",
    search_empty = "No results found for: ",
    export_success = "Exported to: ",
    export_failed = "Export failed: ",
    stats_title = "ai-editutor - Statistics",
    stats_total = "Total Q&A entries",
    stats_by_mode = "By Mode:",
    stats_by_language = "By Language:",
    getting_hint = "Getting hint level %d...",
    lsp_context = "Gathering context from LSP...",
    lsp_not_available = "LSP not available - using current file context only",
    lsp_found_defs = "Found %d related definitions",
    conversation_continued = "Continuing conversation (%d messages)",
    conversation_new = "Starting new conversation",
    conversation_cleared = "Conversation cleared",
    conversation_info = "Conversation: %d messages, %s",
    -- v0.9.0: Indexer messages
    indexing_started = "Indexing project...",
    indexing_progress = "Indexing: %d/%d files",
    indexing_complete = "Indexing complete: %d files, %d chunks",
    indexing_failed = "Indexing failed: %s",
    indexer_not_available = "Indexer not available (sqlite.lua required)",
    indexer_stats = "Index: %d files, %d chunks",
    gathering_context = "Gathering context...",
  },
  vi = {
    no_comment = "Không tìm thấy comment mentor gần con trỏ. Sử dụng // Q: câu hỏi của bạn",
    thinking = "Đang xử lý...",
    error = "Lỗi: ",
    no_response = "Không nhận được phản hồi",
    response_inserted = "Đã chèn response dưới dạng comment",
    modes_title = "ai-editutor - Các Chế Độ",
    modes_instruction = "Viết comment với một trong các tiền tố sau, rồi nhấn ",
    examples = "Ví dụ:",
    hints_title = "Gợi Ý Từng Bước:",
    hints_instruction = "Dùng :EduTutorHint để nhận gợi ý từng bước (cấp 1-4)",
    history_title = "ai-editutor - Lịch Sử Gần Đây",
    history_empty = "Không có lịch sử",
    history_language = "Ngôn ngữ",
    search_prompt = "Tìm kiếm kiến thức: ",
    search_results = "Kết quả tìm kiếm: '%s'",
    search_found = "Tìm thấy %d mục",
    search_empty = "Không tìm thấy kết quả cho: ",
    export_success = "Đã xuất ra: ",
    export_failed = "Xuất thất bại: ",
    stats_title = "ai-editutor - Thống Kê",
    stats_total = "Tổng số Q&A",
    stats_by_mode = "Theo Chế Độ:",
    stats_by_language = "Theo Ngôn Ngữ:",
    getting_hint = "Đang lấy gợi ý cấp %d...",
    lsp_context = "Đang thu thập context từ LSP...",
    lsp_not_available = "LSP không khả dụng - chỉ sử dụng context file hiện tại",
    lsp_found_defs = "Tìm thấy %d definitions liên quan",
    conversation_continued = "Tiếp tục hội thoại (%d tin nhắn)",
    conversation_new = "Bắt đầu hội thoại mới",
    conversation_cleared = "Đã xóa hội thoại",
    conversation_info = "Hội thoại: %d tin nhắn, %s",
    -- v0.9.0: Indexer messages
    indexing_started = "Đang index dự án...",
    indexing_progress = "Đang index: %d/%d files",
    indexing_complete = "Index hoàn tất: %d files, %d chunks",
    indexing_failed = "Index thất bại: %s",
    indexer_not_available = "Indexer không khả dụng (cần sqlite.lua)",
    indexer_stats = "Index: %d files, %d chunks",
    gathering_context = "Đang thu thập context...",
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

  -- v0.9.0: Initialize cache
  cache.setup()

  -- v0.9.0: Initialize indexer (async, non-blocking)
  if indexer_available then
    vim.schedule(function()
      local ok, err = indexer.setup(opts and opts.indexer)
      if ok then
        M._indexer_ready = true
        -- Start background indexing
        vim.defer_fn(function()
          M._background_index()
        end, 1000) -- Delay 1s after startup
      else
        vim.notify("[ai-editutor] " .. M._msg("indexer_not_available") .. ": " .. (err or ""), vim.log.levels.WARN)
      end
    end)
  end

  -- Check provider on setup
  local ready, err = provider.check_provider()
  if not ready then
    vim.notify("[ai-editutor] Warning: " .. (err or "Provider not ready"), vim.log.levels.WARN)
  end
end

---Background index project (non-blocking)
function M._background_index()
  if not indexer_available or not M._indexer_ready then
    return
  end

  -- Index in background without blocking UI
  indexer.index_project({
    progress = function(current, total, filepath)
      -- Optional: show progress occasionally
      if current % 50 == 0 or current == total then
        vim.schedule(function()
          vim.notify(string.format("[ai-editutor] " .. M._msg("indexing_progress"), current, total), vim.log.levels.INFO)
        end)
      end
    end,
  })
end

---Create user commands
function M._create_commands()
  vim.api.nvim_create_user_command("EduTutorAsk", function()
    M.ask()
  end, { desc = "Ask ai-editutor about the current comment" })

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

  -- Conversation commands
  vim.api.nvim_create_user_command("EduTutorConversation", function()
    M.show_conversation()
  end, { desc = "Show current conversation info" })

  vim.api.nvim_create_user_command("EduTutorClearConversation", function()
    M.clear_conversation()
  end, { desc = "Clear current conversation" })

  -- v0.9.0: Indexer commands
  vim.api.nvim_create_user_command("EduTutorIndex", function(opts)
    M.index_project(opts.bang)
  end, { bang = true, desc = "Index project (! to force re-index)" })

  vim.api.nvim_create_user_command("EduTutorIndexStats", function()
    M.show_index_stats()
  end, { desc = "Show indexer statistics" })

  vim.api.nvim_create_user_command("EduTutorClearCache", function()
    M.clear_cache()
  end, { desc = "Clear context cache" })
end

---Setup keymaps
function M._setup_keymaps()
  local keymaps = config.options.keymaps

  -- Main ask keymap
  if keymaps.ask then
    vim.keymap.set("n", keymaps.ask, M.ask, { desc = "ai-editutor: Ask" })
  end
end

---Main ask function - detect and respond to mentor comments
---Uses multi-signal context (v0.9.0): BM25 + LSP + imports
---Supports conversation memory for follow-up questions
---Includes project documentation for better codebase understanding
---Response is inserted as inline comment below the question
function M.ask()
  -- Find query at or near cursor
  local query = parser.find_query()

  if not query then
    vim.notify("[ai-editutor] " .. M._msg("no_comment"), vim.log.levels.WARN)
    return
  end

  -- Get mode from query
  local mode = query.mode_name or config.options.default_mode
  local filepath = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = query.line

  -- Check if we should continue existing conversation
  local is_continuation = conversation.continue_or_start(filepath, cursor_line, mode)
  if is_continuation then
    local info = conversation.get_session_info()
    vim.notify(string.format("[ai-editutor] " .. M._msg("conversation_continued"), info.message_count), vim.log.levels.INFO)
  end

  -- v0.9.0: Start loading indicator
  loading.start(loading.states.gathering_context)

  -- v0.9.0: Use cache for context extraction
  local cache_key = cache.context_key(filepath, cursor_line)

  -- Try to get cached context first
  local cached_context, cache_hit = cache.get(cache_key)

  if cache_hit then
    -- Use cached context
    loading.update(loading.states.connecting)
    M._process_ask_with_context(query, mode, filepath, bufnr, cached_context, is_continuation)
  else
    -- Extract fresh context
    M._extract_context_async(query.question, filepath, cursor_line, function(full_context)
      -- Cache the context
      cache.set(cache_key, full_context, {
        ttl = cache.config.context_ttl,
        tags = { "file:" .. filepath, "context" },
      })

      loading.update(loading.states.connecting)
      M._process_ask_with_context(query, mode, filepath, bufnr, full_context, is_continuation)
    end)
  end
end

---Extract context using multi-signal approach (v0.9.0)
---@param question string The user's question
---@param filepath string Current file path
---@param cursor_line number Cursor line
---@param callback function Callback with full context
function M._extract_context_async(question, filepath, cursor_line, callback)
  -- v0.9.0: Try indexer first for BM25 + multi-signal context
  if indexer_available and M._indexer_ready and indexer.is_ready() then
    local project_root = indexer._project_root or vim.fn.getcwd()

    -- Build context using indexer (BM25 + LSP + imports)
    local indexer_context, metadata = indexer.get_context({
      question = question,
      current_file = filepath,
      cursor_line = cursor_line,
      budget = config.options.indexer and config.options.indexer.context_budget or 4000,
    })

    if indexer_context and indexer_context ~= "" then
      callback(indexer_context)
      return
    end
  end

  -- Fallback: Use traditional LSP-based context extraction
  context.extract_with_lsp(function(context_formatted, has_lsp)
    if not has_lsp then
      vim.notify("[ai-editutor] " .. M._msg("lsp_not_available"), vim.log.levels.WARN)
    end

    -- Add project documentation
    local project_summary = project_context.get_project_summary()
    if project_summary ~= "" then
      context_formatted = context_formatted .. "\n\n" .. project_summary
    end

    callback(context_formatted)
  end)
end

---Process ask with extracted context
---@param query table Parsed query
---@param mode string Mode name
---@param filepath string Current file path
---@param bufnr number Buffer number
---@param full_context string Formatted context
---@param is_continuation boolean Whether continuing conversation
function M._process_ask_with_context(query, mode, filepath, bufnr, full_context, is_continuation)
  -- Add conversation history if continuing
  local conv_history = conversation.get_history_as_context()
  if conv_history ~= "" then
    full_context = conv_history .. "\n" .. full_context
  end

  -- Build prompts
  local system_prompt = prompts.get_system_prompt(mode)
  local user_prompt = prompts.build_user_prompt(query.question, full_context, mode)

  -- v0.9.0: Update loading state
  loading.update(loading.states.thinking)

  -- Query LLM
  provider.query_async(system_prompt, user_prompt, function(response, err)
    -- Stop loading indicator
    loading.stop()

    if err then
      vim.notify("[ai-editutor] " .. M._msg("error") .. err, vim.log.levels.ERROR)
      return
    end

    if not response then
      vim.notify("[ai-editutor] " .. M._msg("no_response"), vim.log.levels.ERROR)
      return
    end

    -- Add to conversation history
    conversation.add_message("user", query.question)
    conversation.add_message("assistant", response)

    -- Save to knowledge base
    local lang = vim.bo.filetype
    knowledge.save({
      mode = mode,
      question = query.question,
      answer = response,
      language = lang,
      filepath = filepath,
    })

    -- Insert response as inline comment
    comment_writer.insert_or_replace(response, query.line, bufnr)
    vim.notify("[ai-editutor] " .. M._msg("response_inserted"), vim.log.levels.INFO)
  end)
end

---Ask with incremental hints system (5 levels in v0.9.0)
---Uses multi-signal context for better hints
---Response is inserted as inline comment with hint level indicator
function M.ask_with_hints()
  local query = parser.find_query()

  if not query then
    vim.notify("[ai-editutor] " .. M._msg("no_comment"), vim.log.levels.WARN)
    return
  end

  local mode = query.mode_name or config.options.default_mode
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(0)
  local cursor_line = query.line

  -- v0.9.0: Start loading indicator
  loading.start(loading.states.gathering_context)

  -- Extract context using multi-signal approach (v0.9.0)
  M._extract_context_async(query.question, filepath, cursor_line, function(context_formatted)
    -- Get or create hint session
    local session = hints.get_session(query.question, mode, context_formatted)

    -- Get the next hint level
    local level = session.level + 1
    loading.update(string.format("Getting hint level %d...", level))

    hints.request_next_hint(session, function(response, hint_level, has_more, err)
      -- Stop loading indicator
      loading.stop()

      if err then
        vim.notify("[ai-editutor] " .. M._msg("error") .. err, vim.log.levels.ERROR)
        return
      end

      if not response then
        vim.notify("[ai-editutor] " .. M._msg("no_response"), vim.log.levels.ERROR)
        return
      end

      -- Save to knowledge if final hint
      if hint_level == hints.MAX_LEVEL then
        local lang = vim.bo.filetype
        knowledge.save({
          mode = mode,
          question = query.question,
          answer = response,
          language = lang,
          filepath = filepath,
          tags = { "hint", "level-" .. hint_level },
        })
      end

      -- Prepend hint level indicator to response
      local hint_prefix = string.format("[Hint %d/%d - %s]\n", hint_level, hints.MAX_LEVEL, hints.LEVEL_NAMES[hint_level] or "")
      local full_response = hint_prefix .. response

      -- Insert response as inline comment
      comment_writer.insert_or_replace(full_response, query.line, bufnr)

      local msg = has_more
        and string.format("Hint level %d inserted. Run :EduTutorHint again for more hints.", hint_level)
        or string.format("Final hint (level %d) inserted.", hint_level)
      vim.notify("[ai-editutor] " .. msg, vim.log.levels.INFO)
    end)
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
  local bufnr = vim.api.nvim_get_current_buf()

  -- Extract context
  local ctx = context.extract(nil, query.line)

  -- Build prompts
  local system_prompt = prompts.get_system_prompt(mode)
  local context_formatted = context.format_for_prompt(ctx)
  local user_prompt = prompts.build_user_prompt(query.question, context_formatted, mode)

  -- Show thinking notification
  vim.notify("[ai-editutor] " .. M._msg("thinking"), vim.log.levels.INFO)

  -- Query LLM
  provider.query_async(system_prompt, user_prompt, function(response, err)
    if err then
      vim.notify("[ai-editutor] " .. M._msg("error") .. err, vim.log.levels.ERROR)
      return
    end

    if not response then
      vim.notify("[ai-editutor] " .. M._msg("no_response"), vim.log.levels.ERROR)
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

    -- Insert response as inline comment
    comment_writer.insert_or_replace(response, query.line, bufnr)
    vim.notify("[ai-editutor] " .. M._msg("response_inserted"), vim.log.levels.INFO)
  end)
end

---Process a direct question
---@param question string Question text
---@param mode string Mode name
---@param line number Line number for context
function M._process_question(question, mode, line)
  local bufnr = vim.api.nvim_get_current_buf()

  -- Extract context
  local ctx = context.extract(nil, line)

  -- Build prompts
  local system_prompt = prompts.get_system_prompt(mode)
  local context_formatted = context.format_for_prompt(ctx)
  local user_prompt = prompts.build_user_prompt(question, context_formatted, mode)

  -- Show thinking notification
  vim.notify("[ai-editutor] " .. M._msg("thinking"), vim.log.levels.INFO)

  -- Query LLM
  provider.query_async(system_prompt, user_prompt, function(response, err)
    if err then
      vim.notify("[ai-editutor] " .. M._msg("error") .. err, vim.log.levels.ERROR)
      return
    end

    if not response then
      vim.notify("[ai-editutor] " .. M._msg("no_response"), vim.log.levels.ERROR)
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

    -- Insert response as inline comment
    comment_writer.insert_or_replace(response, line, bufnr)
    vim.notify("[ai-editutor] " .. M._msg("response_inserted"), vim.log.levels.INFO)
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

  print(table.concat(help, "\n"))
end

---Show recent Q&A history
function M.show_history()
  local entries = knowledge.get_recent(20)

  if #entries == 0 then
    vim.notify("[ai-editutor] " .. M._msg("history_empty"), vim.log.levels.INFO)
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

  print(table.concat(lines, "\n"))
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
    vim.notify("[ai-editutor] " .. M._msg("search_empty") .. query, vim.log.levels.INFO)
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

  print(table.concat(lines, "\n"))
end

---Export knowledge to markdown
---@param filepath? string Output path
function M.export_knowledge(filepath)
  local success, err = knowledge.export_markdown(filepath)

  if success then
    local path = filepath or (os.getenv("HOME") .. "/editutor_export.md")
    vim.notify("[ai-editutor] " .. M._msg("export_success") .. path, vim.log.levels.INFO)
  else
    vim.notify("[ai-editutor] " .. M._msg("export_failed") .. (err or "unknown error"), vim.log.levels.ERROR)
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

  print(table.concat(lines, "\n"))
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
      "ai-editutor - Language Settings",
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

    print(table.concat(lines, "\n"))
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
      string.format("[ai-editutor] Invalid language: %s. Use 'English' or 'Vietnamese'.", lang),
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

  vim.notify("[ai-editutor] " .. messages[normalized], vim.log.levels.INFO)
end

---Get current language
---@return string Current language setting
function M.get_language()
  return config.options.language
end

-- =============================================================================
-- Conversation Functions
-- =============================================================================

---Show current conversation info
function M.show_conversation()
  local info = conversation.get_session_info()

  if not info then
    vim.notify("[ai-editutor] " .. M._msg("conversation_new"), vim.log.levels.INFO)
    return
  end

  local duration_str
  if info.duration < 60 then
    duration_str = string.format("%ds", info.duration)
  elseif info.duration < 3600 then
    duration_str = string.format("%dm", math.floor(info.duration / 60))
  else
    duration_str = string.format("%dh %dm", math.floor(info.duration / 3600), math.floor((info.duration % 3600) / 60))
  end

  local lines = {
    "ai-editutor - Conversation",
    "==========================",
    "",
    string.format("Messages: %d", info.message_count),
    string.format("Mode: %s", info.mode),
    string.format("Duration: %s", duration_str),
    string.format("File: %s", info.file or "unknown"),
    "",
    "---",
    "",
    "Recent messages:",
  }

  local history = conversation.get_history()
  local start_idx = math.max(1, #history - 3) -- Show last 4 messages
  for i = start_idx, #history do
    local msg = history[i]
    local role_label = msg.role == "user" and "You" or "AI"
    local content = msg.content:sub(1, 100)
    if #msg.content > 100 then
      content = content .. "..."
    end
    content = content:gsub("\n", " ")
    table.insert(lines, string.format("[%s]: %s", role_label, content))
    table.insert(lines, "")
  end

  table.insert(lines, "---")
  table.insert(lines, "Use :EduTutorClearConversation to start fresh")

  print(table.concat(lines, "\n"))
end

---Clear current conversation
function M.clear_conversation()
  conversation.clear_session()
  project_context.clear_cache()
  vim.notify("[ai-editutor] " .. M._msg("conversation_cleared"), vim.log.levels.INFO)
end

-- =============================================================================
-- Indexer Functions (v0.9.0)
-- =============================================================================

---Index the project
---@param force boolean Force re-index even if up-to-date
function M.index_project(force)
  if not indexer_available then
    vim.notify("[ai-editutor] " .. M._msg("indexer_not_available"), vim.log.levels.ERROR)
    return
  end

  if not M._indexer_ready then
    -- Try to setup indexer first
    local ok, err = indexer.setup()
    if not ok then
      vim.notify("[ai-editutor] " .. M._msg("indexing_failed") .. (err or ""), vim.log.levels.ERROR)
      return
    end
    M._indexer_ready = true
  end

  vim.notify("[ai-editutor] " .. M._msg("indexing_started"), vim.log.levels.INFO)

  -- Clear index if force
  if force then
    indexer.rebuild()
  end

  local success, stats = indexer.index_project({
    force = force,
    progress = function(current, total, filepath)
      if current % 20 == 0 or current == total then
        vim.schedule(function()
          vim.notify(string.format("[ai-editutor] " .. M._msg("indexing_progress"), current, total), vim.log.levels.INFO)
        end)
      end
    end,
  })

  if success then
    vim.notify(
      string.format("[ai-editutor] " .. M._msg("indexing_complete"), stats.files_indexed, stats.chunks_created),
      vim.log.levels.INFO
    )
  else
    vim.notify("[ai-editutor] " .. M._msg("indexing_failed") .. (stats.error or ""), vim.log.levels.ERROR)
  end
end

---Show indexer statistics
function M.show_index_stats()
  if not indexer_available then
    vim.notify("[ai-editutor] " .. M._msg("indexer_not_available"), vim.log.levels.WARN)
    return
  end

  local stats = indexer.get_stats()

  if not stats.initialized then
    vim.notify("[ai-editutor] Indexer not initialized. Run :EduTutorIndex first.", vim.log.levels.WARN)
    return
  end

  local lines = {
    "ai-editutor - Index Statistics",
    "==============================",
    "",
    string.format("Database: %s", stats.db_path or "unknown"),
    string.format("Files indexed: %d", stats.file_count or 0),
    string.format("Chunks created: %d", stats.chunk_count or 0),
    string.format("Imports tracked: %d", stats.import_count or 0),
    "",
  }

  if stats.by_type and #stats.by_type > 0 then
    table.insert(lines, "By Chunk Type:")
    for _, item in ipairs(stats.by_type) do
      table.insert(lines, string.format("  %s: %d", item.type, item.count))
    end
    table.insert(lines, "")
  end

  if stats.by_language and #stats.by_language > 0 then
    table.insert(lines, "By Language:")
    for _, item in ipairs(stats.by_language) do
      table.insert(lines, string.format("  %s: %d", item.language or "unknown", item.count))
    end
    table.insert(lines, "")
  end

  -- Cache stats
  local cache_stats = cache.get_stats()
  table.insert(lines, "Cache Statistics:")
  table.insert(lines, string.format("  Active entries: %d/%d", cache_stats.active, cache_stats.max_entries))
  table.insert(lines, string.format("  Expired: %d", cache_stats.expired))

  print(table.concat(lines, "\n"))
end

---Clear context cache
function M.clear_cache()
  cache.clear()
  project_context.clear_cache()
  vim.notify("[ai-editutor] Cache cleared", vim.log.levels.INFO)
end

---Check if indexer is available and ready
---@return boolean available
---@return boolean ready
function M.indexer_status()
  return indexer_available, M._indexer_ready
end

return M
