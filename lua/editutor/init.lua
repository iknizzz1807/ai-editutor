-- editutor/init.lua
-- ai-editutor - A Neovim plugin that teaches you to code better
-- v1.1.0: Enhanced context extraction (full project < 20k tokens or LSP selective)

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
local cache = require("editutor.cache")
local loading = require("editutor.loading")
local debug_log = require("editutor.debug_log")
local project_scanner = require("editutor.project_scanner")

M._name = "EduTutor"
M._version = "1.1.0"
M._setup_called = false

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
    gathering_context = "Gathering context...",
    context_mode_full = "Using full project context (%d tokens)",
    context_mode_lsp = "Using LSP selective context (%d tokens)",
    context_over_budget = "Warning: Context exceeds budget (%d > %d tokens)",
  },
  vi = {
    no_comment = "Khong tim thay cau hoi. Viet: // Q: cau hoi cua ban",
    thinking = "Dang xu ly...",
    error = "Loi: ",
    no_response = "Khong nhan duoc phan hoi",
    response_inserted = "Da chen response",
    history_title = "ai-editutor - Lich Su",
    history_empty = "Khong co lich su",
    search_prompt = "Tim kiem: ",
    search_results = "Ket qua: '%s'",
    search_found = "Tim thay %d muc",
    search_empty = "Khong tim thay: ",
    export_success = "Da xuat ra: ",
    export_failed = "Xuat that bai: ",
    stats_title = "ai-editutor - Thong Ke",
    stats_total = "Tong so Q&A",
    hint_level = "Goi y level %d/%d",
    hint_more = "Chay :EduTutorHint lan nua de co them goi y",
    hint_final = "Da den goi y cuoi cung",
    conversation_continued = "Tiep tuc hoi thoai (%d tin nhan)",
    conversation_new = "Bat dau hoi thoai moi",
    conversation_cleared = "Da xoa hoi thoai",
    gathering_context = "Dang thu thap context...",
    context_mode_full = "Su dung full project context (%d tokens)",
    context_mode_lsp = "Su dung LSP selective context (%d tokens)",
    context_over_budget = "Canh bao: Context vuot budget (%d > %d tokens)",
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

  -- Ensure .editutor.log is in .gitignore
  vim.schedule(function()
    debug_log.ensure_gitignore()
  end)

  -- Setup error logging hook
  debug_log.setup_error_hook()

  -- Check provider on setup
  local ready, err = provider.check_provider()
  if not ready then
    vim.notify("[ai-editutor] Warning: " .. (err or "Provider not ready"), vim.log.levels.WARN)
  end
end

---Create user commands
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

  -- Cache command
  vim.api.nvim_create_user_command("EduTutorClearCache", function()
    M.clear_cache()
  end, { desc = "Clear context cache" })

  -- Debug log command
  vim.api.nvim_create_user_command("EduTutorLog", function()
    debug_log.open()
  end, { desc = "Open debug log file" })

  vim.api.nvim_create_user_command("EduTutorClearLog", function()
    debug_log.clear()
    vim.notify("[ai-editutor] Debug log cleared", vim.log.levels.INFO)
  end, { desc = "Clear debug log file" })

  -- Error log commands
  vim.api.nvim_create_user_command("EduTutorErrors", function()
    debug_log.open_error_log()
  end, { desc = "Open error log file" })

  vim.api.nvim_create_user_command("EduTutorClearErrors", function()
    debug_log.clear_error_log()
    vim.notify("[ai-editutor] Error log cleared", vim.log.levels.INFO)
  end, { desc = "Clear error log file" })
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
  loading.start(M._msg("gathering_context"))

  -- Extract context (auto-selects full project or LSP mode)
  context.extract(function(full_context, metadata)
    -- Log context mode
    if metadata.mode == "full_project" then
      vim.notify(string.format("[ai-editutor] " .. M._msg("context_mode_full"), metadata.total_tokens), vim.log.levels.INFO)
    else
      vim.notify(string.format("[ai-editutor] " .. M._msg("context_mode_lsp"), metadata.total_tokens), vim.log.levels.INFO)
    end

    -- Warn if over budget
    if not metadata.within_budget then
      vim.notify(string.format("[ai-editutor] " .. M._msg("context_over_budget"),
        metadata.total_tokens, metadata.budget), vim.log.levels.WARN)
    end

    loading.update(loading.states.connecting)
    M._process_ask(query, filepath, bufnr, full_context, metadata)
  end, {
    current_file = filepath,
    question_line = cursor_line,
  })
end

---Process ask with context
---@param query table
---@param filepath string
---@param bufnr number
---@param full_context string
---@param metadata table
function M._process_ask(query, filepath, bufnr, full_context, metadata)
  -- Add conversation history
  local conv_history = conversation.get_history_as_context()
  if conv_history ~= "" then
    full_context = conv_history .. "\n" .. full_context
  end

  -- Build prompts
  local system_prompt = prompts.get_system_prompt()
  local user_prompt = prompts.build_user_prompt(query.question, full_context)

  -- Get provider info
  local provider_config = config.get_provider()
  local provider_name = provider_config and provider_config.name or "unknown"
  local model_name = config.options.model or (provider_config and provider_config.model) or "unknown"

  -- Log request to debug file
  debug_log.log_request({
    question = query.question,
    current_file = metadata.current_file or filepath,
    question_line = query.line,
    mode = metadata.mode,
    metadata = metadata,
    system_prompt = system_prompt,
    user_prompt = user_prompt,
    provider = provider_name,
    model = model_name,
  })

  loading.update(loading.states.thinking)
  local start_time = vim.loop.hrtime()

  -- Query LLM
  provider.query_async(system_prompt, user_prompt, function(response, err)
    loading.stop()

    local duration_ms = math.floor((vim.loop.hrtime() - start_time) / 1000000)

    -- Log response
    debug_log.log_response({
      response = response,
      error = err,
      duration_ms = duration_ms,
    })

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
  loading.start(M._msg("gathering_context"))

  -- The selected code becomes the primary context
  local selected_code = selection.text

  -- Extract full context
  context.extract(function(full_context, metadata)
    loading.update(loading.states.connecting)
    M._process_ask_visual(query, filepath, bufnr, full_context, selected_code, metadata)
  end, {
    current_file = filepath,
    question_line = query.line,
  })
end

---Process visual ask with selected code
---@param query table
---@param filepath string
---@param bufnr number
---@param full_context string
---@param selected_code string
---@param metadata table
function M._process_ask_visual(query, filepath, bufnr, full_context, selected_code, metadata)
  -- Add conversation history
  local conv_history = conversation.get_history_as_context()
  if conv_history ~= "" then
    full_context = conv_history .. "\n" .. full_context
  end

  -- Build prompts with selected code
  local system_prompt = prompts.get_system_prompt()
  local user_prompt = prompts.build_user_prompt(query.question, full_context, nil, selected_code)

  -- Get provider info
  local provider_config = config.get_provider()
  local provider_name = provider_config and provider_config.name or "unknown"
  local model_name = config.options.model or (provider_config and provider_config.model) or "unknown"

  -- Log request
  debug_log.log_request({
    question = query.question .. " [with visual selection]",
    current_file = metadata.current_file or filepath,
    question_line = query.line,
    mode = metadata.mode,
    metadata = metadata,
    system_prompt = system_prompt,
    user_prompt = user_prompt,
    provider = provider_name,
    model = model_name,
  })

  loading.update(loading.states.thinking)
  local start_time = vim.loop.hrtime()

  -- Query LLM
  provider.query_async(system_prompt, user_prompt, function(response, err)
    loading.stop()

    local duration_ms = math.floor((vim.loop.hrtime() - start_time) / 1000000)

    -- Log response
    debug_log.log_response({
      response = response,
      error = err,
      duration_ms = duration_ms,
    })

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

  loading.start(M._msg("gathering_context"))

  context.extract(function(context_formatted, metadata)
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
  end, {
    current_file = filepath,
    question_line = cursor_line,
  })
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
  local cache_stats = cache.get_stats()

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
    table.insert(lines, "")
  end

  table.insert(lines, "Cache:")
  table.insert(lines, string.format("  Active entries: %d", cache_stats.active))

  -- Show debug log size
  local log_size = debug_log.get_size()
  if log_size > 0 then
    table.insert(lines, "")
    table.insert(lines, string.format("Debug log size: %.1f KB", log_size / 1024))
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
  local msg = normalized == "English" and "Language set to English" or "Da chuyen sang tieng Viet"
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
  vim.notify("[ai-editutor] " .. M._msg("conversation_cleared"), vim.log.levels.INFO)
end

---Clear cache
function M.clear_cache()
  cache.clear()
  vim.notify("[ai-editutor] Cache cleared", vim.log.levels.INFO)
end

---Get version
function M.version()
  return M._version
end

return M
