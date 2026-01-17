-- editutor/init.lua
-- ai-editutor - A Neovim plugin that teaches you to code better
-- v2.0.0: Simplified - no Q:/C: prefix needed, LLM auto-detects intent

local M = {}

local config = require("editutor.config")
local parser = require("editutor.parser")
local context = require("editutor.context")
local prompts = require("editutor.prompts")
local provider = require("editutor.provider")
local comment_writer = require("editutor.comment_writer")
local float_window = require("editutor.float_window")
local knowledge = require("editutor.knowledge")
local cache = require("editutor.cache")
local loading = require("editutor.loading")
local debug_log = require("editutor.debug_log")

M._name = "EduTutor"
M._version = "2.0.0"
M._setup_called = false

-- UI Messages for internationalization
M._messages = {
  en = {
    no_comment = "No comment found near cursor. Write a comment first.",
    thinking = "Thinking...",
    error = "Error: ",
    no_response = "No response received",
    response_inserted = "Response inserted",
    history_title = "ai-editutor - Recent History",
    history_empty = "No history found",
    export_success = "Exported to: ",
    export_failed = "Export failed: ",
    gathering_context = "Gathering context...",
    context_mode_full = "Using full project context (%d tokens)",
    context_mode_adaptive = "Using adaptive context (%d tokens)",
    context_budget_exceeded = "Context exceeds budget (%d > %d tokens). Reduce scope or increase budget.",
  },
  vi = {
    no_comment = "Khong tim thay comment gan cursor. Viet comment truoc.",
    thinking = "Dang xu ly...",
    error = "Loi: ",
    no_response = "Khong nhan duoc phan hoi",
    response_inserted = "Da chen response",
    history_title = "ai-editutor - Lich Su",
    history_empty = "Khong co lich su",
    export_success = "Da xuat ra: ",
    export_failed = "Xuat that bai: ",
    gathering_context = "Dang thu thap context...",
    context_mode_full = "Su dung full project context (%d tokens)",
    context_mode_adaptive = "Su dung adaptive context (%d tokens)",
    context_budget_exceeded = "Context vuot budget (%d > %d tokens). Giam scope hoac tang budget.",
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
  -- Main command - ask about comment near cursor
  vim.api.nvim_create_user_command("EduTutorAsk", function()
    M.ask()
  end, { desc = "Ask ai-editutor about comment near cursor" })

  -- Toggle float window for AI response
  vim.api.nvim_create_user_command("EduTutorToggle", function()
    float_window.toggle()
  end, { desc = "Toggle AI response in float window" })

  -- Knowledge commands
  vim.api.nvim_create_user_command("EduTutorHistory", function()
    M.show_history()
  end, { desc = "Show Q&A history" })

  vim.api.nvim_create_user_command("EduTutorExport", function(opts)
    M.export_knowledge(opts.args)
  end, { nargs = "?", desc = "Export knowledge to markdown" })

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

  -- Browse by date command
  vim.api.nvim_create_user_command("EduTutorBrowse", function(opts)
    M.browse_knowledge(opts.args)
  end, {
    nargs = "?",
    complete = function()
      return knowledge.get_dates()
    end,
    desc = "Browse knowledge by date (YYYY-MM-DD)",
  })
end

---Setup keymaps
function M._setup_keymaps()
  local keymaps = config.options.keymaps

  -- Ask keymap (normal mode + visual mode)
  if keymaps.ask then
    -- Normal mode: ask about comment at cursor
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

  -- Toggle float window keymap
  if keymaps.toggle then
    vim.keymap.set("n", keymaps.toggle, function()
      float_window.toggle()
    end, { desc = "ai-editutor: Toggle AI response" })
  end
end

-- =============================================================================
-- MAIN ASK FUNCTION
-- =============================================================================

---Main ask function - find comment near cursor and respond
function M.ask()
  local comment_info = parser.find_question_near_cursor()

  if not comment_info then
    vim.notify("[ai-editutor] " .. M._msg("no_comment"), vim.log.levels.WARN)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.api.nvim_get_current_buf()
  local comment_line = comment_info.line_num

  -- Start loading - bind to specific buffer and line
  loading.start(M._msg("gathering_context"), bufnr, comment_line - 1)

  -- Extract context (auto-selects full project or adaptive mode)
  context.extract(function(full_context, metadata)
    -- Check if budget exceeded (full_context is nil)
    if not full_context then
      loading.stop()
      vim.notify(
        string.format("[ai-editutor] " .. M._msg("context_budget_exceeded"), metadata.total_tokens, metadata.budget),
        vim.log.levels.ERROR
      )
      return
    end

    -- Log context mode (silent - only in debug)
    debug_log.log("Context mode: " .. metadata.mode .. ", tokens: " .. metadata.total_tokens)

    loading.update(loading.states.connecting)
    M._process_ask(comment_info, filepath, bufnr, full_context, metadata)
  end, {
    current_file = filepath,
    question_line = comment_line,
  })
end

---Process ask with context (streaming)
---@param comment_info table { line_num, content, cursor_line }
---@param filepath string
---@param bufnr number
---@param full_context string
---@param metadata table
function M._process_ask(comment_info, filepath, bufnr, full_context, metadata)
  -- Build prompts (unified - LLM auto-detects intent)
  local system_prompt = prompts.get_system_prompt()
  local user_prompt = prompts.build_user_prompt(comment_info.content, full_context, comment_info.line_num)

  -- Get provider info
  local provider_info = provider.get_info()
  local provider_name = provider_info.name or "unknown"
  local model_name = provider_info.model or "unknown"

  -- Log request to debug file
  debug_log.log_request({
    comment = comment_info.content,
    current_file = metadata.current_file or filepath,
    comment_line = comment_info.line_num,
    metadata = metadata,
    system_prompt = system_prompt,
    user_prompt = user_prompt,
    provider = provider_name,
    model = model_name,
  })

  -- Start streaming
  local stream_state = comment_writer.start_streaming(comment_info.line_num, bufnr)
  loading.update(loading.states.streaming)
  local start_time = vim.loop.hrtime()

  -- Query LLM with streaming
  provider.query_stream(
    system_prompt,
    user_prompt,
    -- on_chunk (not used, we use on_batch instead)
    function() end,
    -- on_done
    function(response, err)
      loading.stop()
      comment_writer.finish_streaming(stream_state)

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

      -- Save to knowledge
      knowledge.save({
        question = comment_info.content,
        answer = response,
        language = vim.bo.filetype,
        filepath = filepath,
      })

      vim.notify("[ai-editutor] " .. M._msg("response_inserted"), vim.log.levels.INFO)
    end,
    -- opts
    {
      debounce_ms = 50,
      on_batch = function(_, full_response_so_far)
        comment_writer.update_streaming(stream_state, full_response_so_far)
      end,
    }
  )
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

  -- Find comment within or near selection
  local comment_info = parser.find_question_near_cursor()

  if not comment_info then
    -- No comment found - prompt user to write one
    vim.notify("[ai-editutor] " .. M._msg("no_comment"), vim.log.levels.WARN)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.api.nvim_get_current_buf()

  -- Start loading - bind to specific buffer and line
  loading.start(M._msg("gathering_context"), bufnr, comment_info.line_num - 1)

  -- The selected code becomes the primary context
  local selected_code = selection.text

  -- Extract full context
  context.extract(function(full_context, metadata)
    -- Check if budget exceeded
    if not full_context then
      loading.stop()
      vim.notify(
        string.format("[ai-editutor] " .. M._msg("context_budget_exceeded"), metadata.total_tokens, metadata.budget),
        vim.log.levels.ERROR
      )
      return
    end

    loading.update(loading.states.connecting)
    M._process_ask_visual(comment_info, filepath, bufnr, full_context, selected_code, metadata)
  end, {
    current_file = filepath,
    question_line = comment_info.line_num,
  })
end

---Process visual ask with selected code (streaming)
---@param comment_info table
---@param filepath string
---@param bufnr number
---@param full_context string
---@param selected_code string
---@param metadata table
function M._process_ask_visual(comment_info, filepath, bufnr, full_context, selected_code, metadata)
  -- Build prompts with selected code
  local system_prompt = prompts.get_system_prompt()
  local user_prompt = prompts.build_user_prompt(comment_info.content, full_context, comment_info.line_num, selected_code)

  -- Get provider info
  local provider_info = provider.get_info()
  local provider_name = provider_info.name or "unknown"
  local model_name = provider_info.model or "unknown"

  -- Log request
  debug_log.log_request({
    comment = comment_info.content .. " [with visual selection]",
    current_file = metadata.current_file or filepath,
    comment_line = comment_info.line_num,
    metadata = metadata,
    system_prompt = system_prompt,
    user_prompt = user_prompt,
    provider = provider_name,
    model = model_name,
  })

  -- Start streaming
  local stream_state = comment_writer.start_streaming(comment_info.line_num, bufnr)
  loading.update(loading.states.streaming)
  local start_time = vim.loop.hrtime()

  -- Query LLM with streaming
  provider.query_stream(
    system_prompt,
    user_prompt,
    -- on_chunk (not used, we use on_batch instead)
    function() end,
    -- on_done
    function(response, err)
      loading.stop()
      comment_writer.finish_streaming(stream_state)

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

      -- Save to knowledge
      knowledge.save({
        question = comment_info.content,
        answer = response,
        language = vim.bo.filetype,
        filepath = filepath,
      })

      vim.notify("[ai-editutor] " .. M._msg("response_inserted"), vim.log.levels.INFO)
    end,
    -- opts
    {
      debounce_ms = 50,
      on_batch = function(_, full_response_so_far)
        comment_writer.update_streaming(stream_state, full_response_so_far)
      end,
    }
  )
end

-- =============================================================================
-- FLOAT WINDOW
-- =============================================================================

---Toggle float window for AI response
function M.toggle_float()
  float_window.toggle()
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

---Browse knowledge by date
function M.browse_knowledge(date)
  if not date or date == "" then
    -- Show available dates
    local dates = knowledge.get_dates()
    if #dates == 0 then
      vim.notify("[ai-editutor] No knowledge entries yet", vim.log.levels.INFO)
      return
    end

    local lines = { "Available dates:", string.rep("=", 40), "" }
    for i, d in ipairs(dates) do
      local entries = knowledge.get_by_date(d)
      table.insert(lines, string.format("%d. %s (%d entries)", i, d, #entries))
    end
    table.insert(lines, "")
    table.insert(lines, "Usage: :EduTutorBrowse YYYY-MM-DD")

    print(table.concat(lines, "\n"))
    return
  end

  -- Show entries for specific date
  local entries = knowledge.get_by_date(date)
  if #entries == 0 then
    vim.notify("[ai-editutor] No entries for " .. date, vim.log.levels.INFO)
    return
  end

  local lines = {
    string.format("Knowledge for %s", date),
    string.format("%d entries", #entries),
    string.rep("=", 40),
    "",
  }

  for i, entry in ipairs(entries) do
    table.insert(lines, string.format("%d. %s", i, entry.question:sub(1, 60)))
    if entry.language then
      table.insert(lines, string.format("   Language: %s", entry.language))
    end
    table.insert(lines, "")
  end

  print(table.concat(lines, "\n"))
end

-- =============================================================================
-- LANGUAGE
-- =============================================================================

---Set language
function M.set_language(lang)
  if not lang then
    local current = config.options.language
    print(string.format("Current language: %s\nUsage: :EduTutorLang English or :EduTutorLang Vietnamese", current))
    return
  end

  local valid = {
    ["English"] = "English",
    ["english"] = "English",
    ["en"] = "English",
    ["Vietnamese"] = "Vietnamese",
    ["vietnamese"] = "Vietnamese",
    ["vi"] = "Vietnamese",
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
