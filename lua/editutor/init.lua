-- editutor/init.lua
-- ai-editutor - A Neovim plugin that teaches you to code better
-- v3.0: New flow - spawn question blocks, batch process pending questions

local M = {}

local config = require("editutor.config")
local parser = require("editutor.parser")
local context = require("editutor.context")
local prompts = require("editutor.prompts")
local provider = require("editutor.provider")
local comment_writer = require("editutor.comment_writer")
local knowledge = require("editutor.knowledge")
local cache = require("editutor.cache")
local loading = require("editutor.loading")
local debug_log = require("editutor.debug_log")

M._name = "EduTutor"
M._version = "3.0.0"
M._setup_called = false

-- =============================================================================
-- UI Messages
-- =============================================================================

M._messages = {
  en = {
    no_pending = "No pending questions in this file. Use <leader>mq to create one.",
    spawned = "Question block created. Type your question, then use <leader>ma to get answer.",
    processing = "Processing %d question(s)...",
    gathering_context = "Gathering context...",
    success = "Answered %d question(s)",
    partial_success = "Answered %d/%d question(s). %d failed.",
    error = "Error: ",
    no_response = "No response received",
    invalid_json = "Failed to parse LLM response as JSON",
    context_budget_exceeded = "Context exceeds budget (%d > %d tokens)",
  },
  vi = {
    no_pending = "Khong co cau hoi pending. Dung <leader>mq de tao moi.",
    spawned = "Da tao question block. Nhap cau hoi, sau do dung <leader>ma de nhan tra loi.",
    processing = "Dang xu ly %d cau hoi...",
    gathering_context = "Dang thu thap context...",
    success = "Da tra loi %d cau hoi",
    partial_success = "Da tra loi %d/%d cau hoi. %d that bai.",
    error = "Loi: ",
    no_response = "Khong nhan duoc phan hoi",
    invalid_json = "Khong the parse JSON tu LLM response",
    context_budget_exceeded = "Context vuot budget (%d > %d tokens)",
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

-- =============================================================================
-- Setup
-- =============================================================================

---Setup the plugin
---@param opts? table User configuration
function M.setup(opts)
  M._setup_called = true
  config.setup(opts)

  M._create_commands()
  M._setup_keymaps()
  cache.setup()

  vim.schedule(function()
    debug_log.ensure_gitignore()
  end)

  debug_log.setup_error_hook()

  local ready, err = provider.check_provider()
  if not ready then
    vim.notify("[ai-editutor] Warning: " .. (err or "Provider not ready"), vim.log.levels.WARN)
  end
end

-- =============================================================================
-- Commands
-- =============================================================================

function M._create_commands()
  -- Spawn question block
  vim.api.nvim_create_user_command("EduTutorQuestion", function()
    M.spawn_question()
  end, { desc = "Spawn a new question block" })

  -- Process pending questions
  vim.api.nvim_create_user_command("EduTutorAsk", function()
    M.ask()
  end, { desc = "Process all pending questions in current file" })

  -- Show pending count
  vim.api.nvim_create_user_command("EduTutorPending", function()
    M.show_pending()
  end, { desc = "Show pending question count" })

  -- Knowledge commands
  vim.api.nvim_create_user_command("EduTutorHistory", function()
    M.show_history()
  end, { desc = "Show Q&A history" })

  vim.api.nvim_create_user_command("EduTutorExport", function(opts)
    M.export_knowledge(opts.args)
  end, { nargs = "?", desc = "Export knowledge to markdown" })

  vim.api.nvim_create_user_command("EduTutorBrowse", function(opts)
    M.browse_knowledge(opts.args)
  end, {
    nargs = "?",
    complete = function()
      return knowledge.get_dates()
    end,
    desc = "Browse knowledge by date",
  })

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
    cache.clear()
    vim.notify("[ai-editutor] Cache cleared", vim.log.levels.INFO)
  end, { desc = "Clear context cache" })

  -- Debug commands
  vim.api.nvim_create_user_command("EduTutorLog", function()
    debug_log.open()
  end, { desc = "Open debug log" })

  vim.api.nvim_create_user_command("EduTutorClearLog", function()
    debug_log.clear()
    vim.notify("[ai-editutor] Debug log cleared", vim.log.levels.INFO)
  end, { desc = "Clear debug log" })
end

-- =============================================================================
-- Keymaps
-- =============================================================================

function M._setup_keymaps()
  local keymaps = config.options.keymaps

  -- Spawn question block (normal mode)
  if keymaps.question then
    vim.keymap.set("n", keymaps.question, M.spawn_question, {
      desc = "ai-editutor: Spawn question block",
    })

    -- Visual mode: spawn with selected code
    vim.keymap.set("v", keymaps.question, function()
      vim.cmd("normal! ")
      vim.schedule(function()
        M.spawn_question_visual()
      end)
    end, {
      desc = "ai-editutor: Spawn question about selection",
    })
  end

  -- Process pending questions
  if keymaps.ask then
    vim.keymap.set("n", keymaps.ask, M.ask, {
      desc = "ai-editutor: Process pending questions",
    })
  end
end

-- =============================================================================
-- Spawn Question Block
-- =============================================================================

---Spawn a new question block at cursor position
function M.spawn_question()
  local bufnr = vim.api.nvim_get_current_buf()
  local id, cursor_line = comment_writer.spawn_question_block(bufnr)

  -- Move cursor to the question input line
  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })

  -- Enter insert mode
  vim.cmd("startinsert!")

  vim.notify("[ai-editutor] " .. M._msg("spawned"), vim.log.levels.INFO)

  debug_log.log("Spawned question block: " .. id)
end

---Spawn question block with visual selection
function M.spawn_question_visual()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get visual selection
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  if start_line == 0 or end_line == 0 or start_line > end_line then
    vim.notify("[ai-editutor] No visual selection found", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local selected_code = table.concat(lines, "\n")

  local id, cursor_line = comment_writer.spawn_question_block(bufnr, selected_code)

  -- Move cursor to the question input line
  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })

  -- Enter insert mode
  vim.cmd("startinsert!")

  vim.notify("[ai-editutor] " .. M._msg("spawned"), vim.log.levels.INFO)

  debug_log.log("Spawned question block with selection: " .. id)
end

-- =============================================================================
-- Process Pending Questions
-- =============================================================================

---Process all pending questions in current file
function M.ask()
  local bufnr = vim.api.nvim_get_current_buf()
  local questions = parser.find_pending_questions(bufnr)

  if #questions == 0 then
    vim.notify("[ai-editutor] " .. M._msg("no_pending"), vim.log.levels.INFO)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- Start loading
  loading.start(string.format(M._msg("processing"), #questions), bufnr, 0)

  -- Extract context
  context.extract(function(full_context, metadata)
    if not full_context then
      loading.stop()
      vim.notify(
        string.format("[ai-editutor] " .. M._msg("context_budget_exceeded"), metadata.total_tokens, metadata.budget),
        vim.log.levels.ERROR
      )
      return
    end

    debug_log.log("Context mode: " .. metadata.mode .. ", tokens: " .. metadata.total_tokens)

    loading.update(loading.states.connecting)
    M._process_questions(questions, filepath, bufnr, full_context, metadata)
  end, {
    current_file = filepath,
  })
end

---Process questions with context
---@param questions table[] Pending questions
---@param filepath string
---@param bufnr number
---@param full_context string
---@param metadata table
function M._process_questions(questions, filepath, bufnr, full_context, metadata)
  -- Build prompts
  local system_prompt = prompts.get_system_prompt()
  local user_prompt = prompts.build_user_prompt(questions, full_context)

  -- Get provider info
  local provider_info = provider.get_info()

  -- Log request
  debug_log.log_request({
    questions = vim.tbl_map(function(q)
      return { id = q.id, question = q.question }
    end, questions),
    current_file = metadata.current_file or filepath,
    metadata = metadata,
    system_prompt = system_prompt,
    user_prompt = user_prompt,
    provider = provider_info.name or "unknown",
    model = provider_info.model or "unknown",
  })

  local start_time = vim.loop.hrtime()

  -- Query LLM (no streaming - wait for full response)
  provider.query(system_prompt, user_prompt, function(response, err)
    loading.stop()

    local duration_ms = math.floor((vim.loop.hrtime() - start_time) / 1000000)

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

    -- Parse JSON response
    local responses = M._parse_json_response(response)
    if not responses then
      vim.notify("[ai-editutor] " .. M._msg("invalid_json"), vim.log.levels.ERROR)
      debug_log.log("Failed to parse JSON: " .. response)
      return
    end

    -- Replace pending markers with responses
    local success_count, fail_count = comment_writer.replace_pending_batch(responses, bufnr)

    -- Save to knowledge
    for _, q in ipairs(questions) do
      if responses[q.id] then
        knowledge.save({
          question = q.question,
          answer = responses[q.id],
          language = vim.bo.filetype,
          filepath = filepath,
        })
      end
    end

    -- Notify result
    if fail_count == 0 then
      vim.notify("[ai-editutor] " .. string.format(M._msg("success"), success_count), vim.log.levels.INFO)
    else
      vim.notify(
        "[ai-editutor] " .. string.format(M._msg("partial_success"), success_count, #questions, fail_count),
        vim.log.levels.WARN
      )
    end
  end)
end

---Parse JSON response from LLM
---@param response string Raw response
---@return table<string, string>|nil Map of id -> answer
function M._parse_json_response(response)
  -- Try to extract JSON from response (in case LLM adds extra text)
  local json_str = response:match("```json%s*(.-)%s*```")
    or response:match("```%s*(.-)%s*```")
    or response:match("(%b{})")
    or response

  -- Clean up potential issues
  json_str = json_str:gsub("^%s*", ""):gsub("%s*$", "")

  local ok, result = pcall(vim.json.decode, json_str)
  if ok and type(result) == "table" then
    return result
  end

  return nil
end

-- =============================================================================
-- Utility Functions
-- =============================================================================

---Show pending question count
function M.show_pending()
  local count = parser.count_pending_questions()
  vim.notify(string.format("[ai-editutor] %d pending question(s) in current file", count), vim.log.levels.INFO)
end

---Show recent history
function M.show_history()
  local entries = knowledge.get_recent(20)

  if #entries == 0 then
    vim.notify("[ai-editutor] No history found", vim.log.levels.INFO)
    return
  end

  local lines = { "ai-editutor - Recent History", string.rep("=", 40), "" }

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
    vim.notify("[ai-editutor] Exported to: " .. path, vim.log.levels.INFO)
  else
    vim.notify("[ai-editutor] Export failed: " .. (err or ""), vim.log.levels.ERROR)
  end
end

---Browse knowledge by date
function M.browse_knowledge(date)
  if not date or date == "" then
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

---Get version
function M.version()
  return M._version
end

return M
