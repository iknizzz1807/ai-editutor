-- editutor/init.lua
-- ai-editutor - A Neovim plugin that teaches you to code better
-- Simplified v1.0: Just Q: prefix, one unified experience

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
M._version = "1.0.0"
M._setup_called = false
M._indexer_ready = false

-- UI Messages for internationalization
M._messages = {
  en = {
    no_comment = "No question found. Write: // Q: your question",
    thinking = "Thinking...",
    error = "Error: ",
    no_response = "No response received",
    response_inserted = "Response inserted",
    history_title = "ai-editutor - Recent History",
    history_empty = "No history found",
    search_prompt = "Search knowledge: ",
    search_results = "Search Results: '%s'",
    search_found = "Found %d entries",
    search_empty = "No results found for: ",
    export_success = "Exported to: ",
    export_failed = "Export failed: ",
    stats_title = "ai-editutor - Statistics",
    stats_total = "Total Q&A entries",
    hint_level = "Hint level %d/%d",
    hint_more = "Run :EduTutorHint again for more hints",
    hint_final = "Final hint reached",
    conversation_continued = "Continuing conversation (%d messages)",
    conversation_new = "Starting new conversation",
    conversation_cleared = "Conversation cleared",
    -- Indexer messages
    indexing_started = "Indexing project...",
    indexing_progress = "Indexing: %d/%d files",
    indexing_complete = "Indexing complete: %d files, %d chunks",
    indexing_failed = "Indexing failed: %s",
    indexer_not_available = "Indexer not available (sqlite.lua required)",
    gathering_context = "Gathering context...",
  },
  vi = {
    no_comment = "Không tìm thấy câu hỏi. Viết: // Q: câu hỏi của bạn",
    thinking = "Đang xử lý...",
    error = "Lỗi: ",
    no_response = "Không nhận được phản hồi",
    response_inserted = "Đã chèn response",
    history_title = "ai-editutor - Lịch Sử",
    history_empty = "Không có lịch sử",
    search_prompt = "Tìm kiếm: ",
    search_results = "Kết quả: '%s'",
    search_found = "Tìm thấy %d mục",
    search_empty = "Không tìm thấy: ",
    export_success = "Đã xuất ra: ",
    export_failed = "Xuất thất bại: ",
    stats_title = "ai-editutor - Thống Kê",
    stats_total = "Tổng số Q&A",
    hint_level = "Gợi ý level %d/%d",
    hint_more = "Chạy :EduTutorHint lần nữa để có thêm gợi ý",
    hint_final = "Đã đến gợi ý cuối cùng",
    conversation_continued = "Tiếp tục hội thoại (%d tin nhắn)",
    conversation_new = "Bắt đầu hội thoại mới",
    conversation_cleared = "Đã xóa hội thoại",
    -- Indexer messages
    indexing_started = "Đang index dự án...",
    indexing_progress = "Đang index: %d/%d files",
    indexing_complete = "Index hoàn tất: %d files, %d chunks",
    indexing_failed = "Index thất bại: %s",
    indexer_not_available = "Indexer không khả dụng (cần sqlite.lua)",
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

  -- Initialize cache
  cache.setup()

  -- Initialize indexer (async, non-blocking)
  if indexer_available then
    vim.schedule(function()
      local ok, err = indexer.setup(opts and opts.indexer)
      if ok then
        M._indexer_ready = true
        -- Start background indexing after 1s
        vim.defer_fn(function()
          M._background_index()
        end, 1000)
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

  indexer.index_project({
    progress = function(current, total, _)
      if current % 50 == 0 or current == total then
        vim.schedule(function()
          vim.notify(string.format("[ai-editutor] " .. M._msg("indexing_progress"), current, total), vim.log.levels.INFO)
        end)
      end
    end,
  })
end

---Create user commands (simplified - no mode commands)
function M._create_commands()
  -- Main command
  vim.api.nvim_create_user_command("EduTutorAsk", function()
    M.ask()
  end, { desc = "Ask ai-editutor (write // Q: your question first)" })

  -- Hint command (progressive hints)
  vim.api.nvim_create_user_command("EduTutorHint", function()
    M.ask_with_hints()
  end, { desc = "Get progressive hints (run multiple times for more detail)" })

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
  end, { desc = "Show statistics" })

  -- Language command
  vim.api.nvim_create_user_command("EduTutorLang", function(opts)
    M.set_language(opts.args ~= "" and opts.args or nil)
  end, {
    nargs = "?",
    complete = function()
      return { "English", "Vietnamese", "en", "vi" }
    end,
    desc = "Set response language",
  })

  -- Conversation commands
  vim.api.nvim_create_user_command("EduTutorConversation", function()
    M.show_conversation()
  end, { desc = "Show conversation info" })

  vim.api.nvim_create_user_command("EduTutorClearConversation", function()
    M.clear_conversation()
  end, { desc = "Clear conversation" })

  -- Indexer commands
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

  if keymaps.ask then
    -- Normal mode: ask about code at cursor
    vim.keymap.set("n", keymaps.ask, M.ask, { desc = "ai-editutor: Ask" })
    -- Visual mode: ask about selected code
    vim.keymap.set("v", keymaps.ask, function()
      -- Exit visual mode first to set '< and '> marks
      vim.cmd("normal! ")
      -- Small delay to let marks be set
      vim.schedule(function()
        M.ask_visual()
      end)
    end, { desc = "ai-editutor: Ask about selection" })
  end
end

-- =============================================================================
-- MAIN ASK FUNCTION
-- =============================================================================

---Main ask function - find Q: comment and respond
function M.ask()
  local query = parser.find_query()

  if not query then
    vim.notify("[ai-editutor] " .. M._msg("no_comment"), vim.log.levels.WARN)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = query.line

  -- Check conversation continuation
  local is_continuation = conversation.continue_or_start(filepath, cursor_line, "question")
  if is_continuation then
    local info = conversation.get_session_info()
    vim.notify(string.format("[ai-editutor] " .. M._msg("conversation_continued"), info.message_count), vim.log.levels.INFO)
  end

  -- Start loading
  loading.start(loading.states.gathering_context)

  -- Check cache
  local cache_key = cache.context_key(filepath, cursor_line)
  local cached_context, cache_hit = cache.get(cache_key)

  if cache_hit then
    loading.update(loading.states.connecting)
    M._process_ask(query, filepath, bufnr, cached_context)
  else
    M._extract_context_async(query.question, filepath, cursor_line, function(full_context)
      cache.set(cache_key, full_context, {
        ttl = cache.config.context_ttl,
        tags = { "file:" .. filepath, "context" },
      })

      loading.update(loading.states.connecting)
      M._process_ask(query, filepath, bufnr, full_context)
    end)
  end
end

---Extract context using multi-signal approach
---@param question string
---@param filepath string
---@param cursor_line number
---@param callback function
function M._extract_context_async(question, filepath, cursor_line, callback)
  -- Try indexer first
  if indexer_available and M._indexer_ready and indexer.is_ready() then
    local indexer_context, _ = indexer.get_context({
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

  -- Fallback: LSP-based context
  context.extract_with_lsp(function(context_formatted, has_lsp)
    if not has_lsp then
      vim.notify("[ai-editutor] LSP not available - using file context only", vim.log.levels.WARN)
    end

    local project_summary = project_context.get_project_summary()
    if project_summary ~= "" then
      context_formatted = context_formatted .. "\n\n" .. project_summary
    end

    callback(context_formatted)
  end)
end

---Process ask with context
---@param query table
---@param filepath string
---@param bufnr number
---@param full_context string
function M._process_ask(query, filepath, bufnr, full_context)
  -- Add conversation history
  local conv_history = conversation.get_history_as_context()
  if conv_history ~= "" then
    full_context = conv_history .. "\n" .. full_context
  end

  -- Build prompts
  local system_prompt = prompts.get_system_prompt()
  local user_prompt = prompts.build_user_prompt(query.question, full_context)

  loading.update(loading.states.thinking)

  -- Query LLM
  provider.query_async(system_prompt, user_prompt, function(response, err)
    loading.stop()

    if err then
      vim.notify("[ai-editutor] " .. M._msg("error") .. err, vim.log.levels.ERROR)
      return
    end

    if not response then
      vim.notify("[ai-editutor] " .. M._msg("no_response"), vim.log.levels.ERROR)
      return
    end

    -- Add to conversation
    conversation.add_message("user", query.question)
    conversation.add_message("assistant", response)

    -- Save to knowledge
    knowledge.save({
      mode = "question",
      question = query.question,
      answer = response,
      language = vim.bo.filetype,
      filepath = filepath,
    })

    -- Insert response
    comment_writer.insert_or_replace(response, query.line, bufnr)
    vim.notify("[ai-editutor] " .. M._msg("response_inserted"), vim.log.levels.INFO)
  end)
end

-- =============================================================================
-- VISUAL SELECTION ASK
-- =============================================================================

---Ask about visually selected code
function M.ask_visual()
  local selection = parser.get_visual_selection()

  if not selection then
    vim.notify("[ai-editutor] No visual selection found", vim.log.levels.WARN)
    return
  end

  -- Find Q: comment within selection range
  local query = parser.find_query_in_range(nil, selection.start_line, selection.end_line)

  if not query then
    -- No Q: found in selection - prompt user to write one
    vim.notify("[ai-editutor] " .. M._msg("no_comment"), vim.log.levels.WARN)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.api.nvim_get_current_buf()

  -- Check conversation continuation
  local is_continuation = conversation.continue_or_start(filepath, query.line, "question")
  if is_continuation then
    local info = conversation.get_session_info()
    vim.notify(string.format("[ai-editutor] " .. M._msg("conversation_continued"), info.message_count), vim.log.levels.INFO)
  end

  -- Start loading
  loading.start(loading.states.gathering_context)

  -- The selected code becomes the primary context
  local selected_code = selection.text

  -- Also get surrounding context
  M._extract_context_async(query.question, filepath, query.line, function(full_context)
    loading.update(loading.states.connecting)
    M._process_ask_visual(query, filepath, bufnr, full_context, selected_code)
  end)
end

---Process visual ask with selected code
---@param query table
---@param filepath string
---@param bufnr number
---@param full_context string
---@param selected_code string
function M._process_ask_visual(query, filepath, bufnr, full_context, selected_code)
  -- Add conversation history
  local conv_history = conversation.get_history_as_context()
  if conv_history ~= "" then
    full_context = conv_history .. "\n" .. full_context
  end

  -- Build prompts with selected code
  local system_prompt = prompts.get_system_prompt()
  local user_prompt = prompts.build_user_prompt(query.question, full_context, nil, selected_code)

  loading.update(loading.states.thinking)

  -- Query LLM
  provider.query_async(system_prompt, user_prompt, function(response, err)
    loading.stop()

    if err then
      vim.notify("[ai-editutor] " .. M._msg("error") .. err, vim.log.levels.ERROR)
      return
    end

    if not response then
      vim.notify("[ai-editutor] " .. M._msg("no_response"), vim.log.levels.ERROR)
      return
    end

    -- Add to conversation
    conversation.add_message("user", query.question .. "\n[Selected code]\n" .. selected_code:sub(1, 200))
    conversation.add_message("assistant", response)

    -- Save to knowledge
    knowledge.save({
      mode = "question",
      question = query.question,
      answer = response,
      language = vim.bo.filetype,
      filepath = filepath,
      tags = { "visual-selection" },
    })

    -- Insert response
    comment_writer.insert_or_replace(response, query.line, bufnr)
    vim.notify("[ai-editutor] " .. M._msg("response_inserted"), vim.log.levels.INFO)
  end)
end

-- =============================================================================
-- HINTS FUNCTION
-- =============================================================================

---Ask with incremental hints (5 levels)
function M.ask_with_hints()
  local query = parser.find_query()

  if not query then
    vim.notify("[ai-editutor] " .. M._msg("no_comment"), vim.log.levels.WARN)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(0)
  local cursor_line = query.line

  loading.start(loading.states.gathering_context)

  M._extract_context_async(query.question, filepath, cursor_line, function(context_formatted)
    local session = hints.get_session(query.question, nil, context_formatted)
    local level = session.level + 1

    loading.update(string.format("Getting hint level %d...", level))

    hints.request_next_hint(session, function(response, hint_level, has_more, err)
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
        knowledge.save({
          mode = "question",
          question = query.question,
          answer = response,
          language = vim.bo.filetype,
          filepath = filepath,
          tags = { "hint", "level-" .. hint_level },
        })
      end

      -- Add hint level indicator
      local hint_prefix = string.format("[Hint %d/%d - %s]\n",
        hint_level, hints.MAX_LEVEL, hints.LEVEL_NAMES[hint_level] or "")
      local full_response = hint_prefix .. response

      comment_writer.insert_or_replace(full_response, query.line, bufnr)

      local msg = has_more and M._msg("hint_more") or M._msg("hint_final")
      vim.notify(string.format("[ai-editutor] " .. M._msg("hint_level") .. " - %s",
        hint_level, hints.MAX_LEVEL, msg), vim.log.levels.INFO)
    end)
  end)
end

-- =============================================================================
-- KNOWLEDGE FUNCTIONS
-- =============================================================================

---Show recent history
function M.show_history()
  local entries = knowledge.get_recent(20)

  if #entries == 0 then
    vim.notify("[ai-editutor] " .. M._msg("history_empty"), vim.log.levels.INFO)
    return
  end

  local lines = { M._msg("history_title"), string.rep("=", 40), "" }

  for i, entry in ipairs(entries) do
    table.insert(lines, string.format("%d. %s", i, entry.question:sub(1, 60)))
    if entry.language then
      table.insert(lines, string.format("   [%s]", entry.language))
    end
    table.insert(lines, "")
  end

  print(table.concat(lines, "\n"))
end

---Search knowledge
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
    string.rep("=", 40), "",
  }

  for i, entry in ipairs(results) do
    table.insert(lines, string.format("## %d. %s", i, entry.question))
    table.insert(lines, entry.answer:sub(1, 200):gsub("\n", " ") .. "...")
    table.insert(lines, "")
  end

  print(table.concat(lines, "\n"))
end

---Export knowledge
function M.export_knowledge(filepath)
  local success, err = knowledge.export_markdown(filepath)

  if success then
    local path = filepath or (os.getenv("HOME") .. "/editutor_export.md")
    vim.notify("[ai-editutor] " .. M._msg("export_success") .. path, vim.log.levels.INFO)
  else
    vim.notify("[ai-editutor] " .. M._msg("export_failed") .. (err or ""), vim.log.levels.ERROR)
  end
end

---Show stats
function M.show_stats()
  local stats = knowledge.get_stats()

  local lines = {
    M._msg("stats_title"),
    string.rep("=", 40), "",
    string.format("%s: %d", M._msg("stats_total"), stats.total), "",
  }

  if next(stats.by_language) then
    table.insert(lines, "By Language:")
    for lang, count in pairs(stats.by_language) do
      table.insert(lines, string.format("  %s: %d", lang, count))
    end
  end

  print(table.concat(lines, "\n"))
end

-- =============================================================================
-- LANGUAGE & CONVERSATION
-- =============================================================================

---Set language
function M.set_language(lang)
  if not lang then
    local current = config.options.language
    print(string.format("Current language: %s\nUsage: :EduTutorLang English or :EduTutorLang Vietnamese", current))
    return
  end

  local valid = {
    ["English"] = "English", ["english"] = "English", ["en"] = "English",
    ["Vietnamese"] = "Vietnamese", ["vietnamese"] = "Vietnamese", ["vi"] = "Vietnamese",
  }

  local normalized = valid[lang]
  if not normalized then
    vim.notify("[ai-editutor] Invalid language. Use 'English' or 'Vietnamese'.", vim.log.levels.ERROR)
    return
  end

  config.options.language = normalized
  local msg = normalized == "English" and "Language set to English" or "Đã chuyển sang tiếng Việt"
  vim.notify("[ai-editutor] " .. msg, vim.log.levels.INFO)
end

---Show conversation
function M.show_conversation()
  local info = conversation.get_session_info()

  if not info then
    vim.notify("[ai-editutor] " .. M._msg("conversation_new"), vim.log.levels.INFO)
    return
  end

  local lines = {
    "ai-editutor - Conversation",
    string.rep("=", 40), "",
    string.format("Messages: %d", info.message_count),
    string.format("File: %s", info.file or "unknown"), "",
  }

  print(table.concat(lines, "\n"))
end

---Clear conversation
function M.clear_conversation()
  conversation.clear_session()
  project_context.clear_cache()
  vim.notify("[ai-editutor] " .. M._msg("conversation_cleared"), vim.log.levels.INFO)
end

-- =============================================================================
-- INDEXER FUNCTIONS
-- =============================================================================

---Index project
function M.index_project(force)
  if not indexer_available then
    vim.notify("[ai-editutor] " .. M._msg("indexer_not_available"), vim.log.levels.ERROR)
    return
  end

  if not M._indexer_ready then
    local ok, err = indexer.setup()
    if not ok then
      vim.notify("[ai-editutor] " .. M._msg("indexing_failed") .. (err or ""), vim.log.levels.ERROR)
      return
    end
    M._indexer_ready = true
  end

  vim.notify("[ai-editutor] " .. M._msg("indexing_started"), vim.log.levels.INFO)

  if force then
    indexer.rebuild()
  end

  local success, stats = indexer.index_project({
    force = force,
    progress = function(current, total, _)
      if current % 20 == 0 or current == total then
        vim.schedule(function()
          vim.notify(string.format("[ai-editutor] " .. M._msg("indexing_progress"), current, total), vim.log.levels.INFO)
        end)
      end
    end,
  })

  if success then
    vim.notify(string.format("[ai-editutor] " .. M._msg("indexing_complete"),
      stats.files_indexed, stats.chunks_created), vim.log.levels.INFO)
  else
    vim.notify("[ai-editutor] " .. M._msg("indexing_failed") .. (stats.error or ""), vim.log.levels.ERROR)
  end
end

---Show index stats
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
    string.rep("=", 40), "",
    string.format("Files indexed: %d", stats.file_count or 0),
    string.format("Chunks created: %d", stats.chunk_count or 0), "",
  }

  print(table.concat(lines, "\n"))
end

---Clear cache
function M.clear_cache()
  cache.clear()
  project_context.clear_cache()
  vim.notify("[ai-editutor] Cache cleared", vim.log.levels.INFO)
end

---Get version
function M.version()
  return M._version
end

return M
