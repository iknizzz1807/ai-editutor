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
local rag = require("editutor.rag")

M._name = "EduTutor"
M._version = "0.3.0"
M._setup_called = false

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

  -- RAG commands
  vim.api.nvim_create_user_command("EduTutorIndex", function(opts)
    M.index_codebase(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", desc = "Index codebase for RAG" })

  vim.api.nvim_create_user_command("EduTutorRAG", function()
    M.ask_with_rag()
  end, { desc = "Ask with codebase context (RAG)" })

  vim.api.nvim_create_user_command("EduTutorRAGStatus", function()
    M.show_rag_status()
  end, { desc = "Show RAG index status" })
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
function M.ask()
  -- Find query at or near cursor
  local query = parser.find_query()

  if not query then
    vim.notify("[EduTutor] No mentor comment found near cursor.\nUse // Q: your question", vim.log.levels.WARN)
    return
  end

  -- Get mode from query
  local mode = query.mode_name or config.options.default_mode

  -- Extract context
  local ctx = context.extract(nil, query.line)

  -- Build prompts
  local system_prompt = prompts.get_system_prompt(mode)
  local context_formatted = context.format_for_prompt(ctx)
  local user_prompt = prompts.build_user_prompt(query.question, context_formatted, mode)

  -- Show loading
  ui.show_loading("Thinking about: " .. query.question:sub(1, 50) .. "...")

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

---Ask with streaming response
function M.ask_stream()
  local query = parser.find_query()

  if not query then
    vim.notify("[EduTutor] No mentor comment found near cursor.\nUse // Q: your question", vim.log.levels.WARN)
    return
  end

  local mode = query.mode_name or config.options.default_mode
  local ctx = context.extract(nil, query.line)

  -- Build prompts
  local system_prompt = prompts.get_system_prompt(mode)
  local context_formatted = context.format_for_prompt(ctx)
  local user_prompt = prompts.build_user_prompt(query.question, context_formatted, mode)

  -- Start streaming UI
  local job_id
  ui.start_stream(mode, query.question, nil)

  -- Stream response
  job_id = provider.query_stream(
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
      if content and content ~= "" then
        knowledge.save({
          mode = mode,
          question = query.question,
          answer = content,
          language = ctx.language,
          filepath = ctx.filepath,
          tags = { "stream" },
        })
      end
    end
  )

  -- Store job_id for cancellation (update UI state)
  if job_id and ui.is_open() then
    -- The UI already handles cancellation via the job_id passed to start_stream
  end
end

---Ask with incremental hints system
function M.ask_with_hints()
  local query = parser.find_query()

  if not query then
    vim.notify("[EduTutor] No mentor comment found near cursor.\nUse // Q: your question", vim.log.levels.WARN)
    return
  end

  local mode = query.mode_name or config.options.default_mode
  local ctx = context.extract(nil, query.line)
  local context_formatted = context.format_for_prompt(ctx)

  -- Get or create hint session
  local session = hints.get_session(query.question, mode, context_formatted)

  -- Function to request and show next hint
  local function show_next_hint()
    ui.show_loading("Getting next hint...")

    hints.request_next_hint(session, function(response, level, has_more, err)
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

      -- Save to knowledge if final hint
      if level == hints.MAX_LEVEL then
        knowledge.save({
          mode = mode,
          question = query.question,
          answer = response,
          language = ctx.language,
          filepath = ctx.filepath,
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
  local help = {
    "AI EduTutor - Available Modes",
    "================================",
    "",
    "Write a comment with one of these prefixes, then press " .. (config.options.keymaps.ask or "<leader>ma"),
    "",
  }

  for mode_char, mode_info in pairs(parser.modes) do
    table.insert(help, string.format("// %s: %s", mode_char, mode_info.description))
  end

  table.insert(help, "")
  table.insert(help, "Examples:")
  table.insert(help, "  // Q: What is the time complexity of this function?")
  table.insert(help, "  // S: Why might async/await be better here?")
  table.insert(help, "  // R: Review this function for security issues")
  table.insert(help, "  // D: This function returns nil sometimes, why?")
  table.insert(help, "  // E: Explain closures in JavaScript")
  table.insert(help, "")
  table.insert(help, "Incremental Hints:")
  table.insert(help, "  Use :EduTutorHint to get progressive hints (level 1-4)")
  table.insert(help, "  Press 'n' in the popup to get the next hint level")

  ui.show(table.concat(help, "\n"), nil, nil)
end

---Show recent Q&A history
function M.show_history()
  local entries = knowledge.get_recent(20)

  if #entries == 0 then
    vim.notify("[EduTutor] No history found", vim.log.levels.INFO)
    return
  end

  local lines = {
    "EduTutor - Recent History",
    "============================",
    "",
  }

  for i, entry in ipairs(entries) do
    table.insert(lines, string.format("%d. [%s] %s", i, entry.mode:upper(), entry.question:sub(1, 60)))
    if entry.language then
      table.insert(lines, string.format("   Language: %s", entry.language))
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
    vim.ui.input({ prompt = "Search knowledge: " }, function(input)
      if input and input ~= "" then
        M.search_knowledge(input)
      end
    end)
    return
  end

  local results = knowledge.search(query)

  if #results == 0 then
    vim.notify("[EduTutor] No results found for: " .. query, vim.log.levels.INFO)
    return
  end

  local lines = {
    string.format("Search Results: '%s'", query),
    string.format("Found %d entries", #results),
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
    vim.notify("[EduTutor] Exported to: " .. path, vim.log.levels.INFO)
  else
    vim.notify("[EduTutor] Export failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end

---Show knowledge statistics
function M.show_stats()
  local stats = knowledge.get_stats()

  local lines = {
    "EduTutor - Statistics",
    "========================",
    "",
    string.format("Total Q&A entries: %d", stats.total),
    "",
    "By Mode:",
  }

  for mode, count in pairs(stats.by_mode) do
    table.insert(lines, string.format("  %s: %d", mode:upper(), count))
  end

  table.insert(lines, "")
  table.insert(lines, "By Language:")

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
-- RAG Functions
-- =============================================================================

---Index codebase for RAG
---@param path? string Path to index
function M.index_codebase(path)
  path = path or vim.fn.getcwd()

  if not rag.is_available() then
    vim.notify("[EduTutor] RAG CLI not available.\nInstall with: pip install -e python/", vim.log.levels.ERROR)
    return
  end

  vim.notify("[EduTutor] Indexing " .. path .. "...", vim.log.levels.INFO)

  rag.index(path, {}, function(stats, err)
    if err then
      vim.notify("[EduTutor] Indexing error: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.notify(
      string.format("[EduTutor] Indexed %d files, created %d chunks",
        stats.files_processed or 0,
        stats.chunks_created or 0),
      vim.log.levels.INFO
    )
  end)
end

---Ask with RAG context (codebase-aware)
function M.ask_with_rag()
  local query = parser.find_query()

  if not query then
    vim.notify("[EduTutor] No mentor comment found near cursor.\nUse // Q: your question", vim.log.levels.WARN)
    return
  end

  if not rag.is_available() then
    vim.notify("[EduTutor] RAG not available, falling back to normal ask", vim.log.levels.WARN)
    M.ask()
    return
  end

  local mode = query.mode_name or config.options.default_mode
  local ctx = context.extract(nil, query.line)

  ui.show_loading("Searching codebase...")

  -- Get RAG context
  rag.get_context(query.question, function(rag_context, rag_err)
    if rag_err then
      vim.notify("[EduTutor] RAG search failed: " .. rag_err, vim.log.levels.WARN)
    end

    -- Build enhanced prompt with RAG context
    local system_prompt = prompts.get_system_prompt(mode)
    local context_formatted = context.format_for_prompt(ctx)

    -- Add RAG context if available
    local full_context = context_formatted
    if rag_context and rag_context ~= "" then
      full_context = full_context .. "\n\n" .. rag_context
    end

    local user_prompt = prompts.build_user_prompt(query.question, full_context, mode)

    ui.show_loading("Thinking with codebase context...")

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
        tags = { "rag" },
      })

      -- Show response
      ui.show(response, mode .. "+RAG", query.question)
    end)
  end)
end

---Show RAG index status
function M.show_rag_status()
  if not rag.is_available() then
    vim.notify("[EduTutor] RAG CLI not available", vim.log.levels.WARN)
    return
  end

  rag.status(function(stats, err)
    if err then
      vim.notify("[EduTutor] " .. err, vim.log.levels.ERROR)
      return
    end

    local lines = {
      "EduTutor - RAG Status",
      "========================",
      "",
      string.format("Total chunks: %s", stats.total_chunks or "N/A"),
      string.format("Total files: %s", stats.total_files or "N/A"),
      string.format("Database size: %s", stats.db_size or "N/A"),
      string.format("Last updated: %s", stats.last_updated or "N/A"),
      "",
    }

    if stats.by_language then
      table.insert(lines, "By Language:")
      for lang, count in pairs(stats.by_language) do
        table.insert(lines, string.format("  %s: %d", lang, count))
      end
    end

    table.insert(lines, "")
    table.insert(lines, "Commands:")
    table.insert(lines, "  :EduTutorIndex [path] - Index codebase")
    table.insert(lines, "  :EduTutorRAG - Ask with codebase context")

    ui.show(table.concat(lines, "\n"), nil, nil)
  end)
end

return M
