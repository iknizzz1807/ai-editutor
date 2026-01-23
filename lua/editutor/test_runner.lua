-- editutor/test_runner.lua
-- Automated testing for ai-editutor with curated test cases
-- Run inside Neovim: :lua require('editutor.test_runner').run()

local M = {}

local test_cases = require("editutor.test_cases")

-- =============================================================================
-- Configuration
-- =============================================================================

M.config = {
  repos_dir = vim.fn.expand("~/.cache/editutor-tests/repos"),
  results_dir = vim.fn.expand("~/.cache/editutor-tests/results"),
  lsp_timeout = 15000,  -- 15 seconds for LSP
  dry_run = true,       -- Don't actually call LLM
  save_contexts = true, -- Save full context to files
  cleanup_interval = 20, -- Cleanup all buffers every N tests
  start_from = 1,       -- Start from this test case index
}

-- =============================================================================
-- Results Structure
-- =============================================================================

local results = {
  started_at = nil,
  completed_at = nil,
  config = nil,
  test_cases = {},
  summary = {
    total = 0,
    passed = 0,
    failed = 0,
    skipped = 0,
    by_language = {},
    by_pattern = {},
    lsp_stats = {
      available = 0,
      unavailable = 0,
      timeout = 0,
    },
    context_stats = {
      full_project = 0,
      adaptive = 0,
      avg_tokens = 0,
      avg_extraction_ms = 0,
    },
    library_info_stats = {
      with_info = 0,
      without_info = 0,
      avg_items = 0,
    },
  },
  errors = {},
}

-- =============================================================================
-- Logging
-- =============================================================================

local log_file = nil

local function init_log()
  local timestamp = os.date("%Y%m%d_%H%M%S")
  local log_path = M.config.results_dir .. "/test_run_" .. timestamp .. ".log"
  vim.fn.mkdir(M.config.results_dir, "p")
  log_file = io.open(log_path, "w")
  return log_path
end

local function log(msg, level)
  level = level or "INFO"
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local line = string.format("[%s] [%-5s] %s", timestamp, level, msg)
  print(line)
  if log_file then
    log_file:write(line .. "\n")
    log_file:flush()
  end
end

local function close_log()
  if log_file then
    log_file:close()
    log_file = nil
  end
end

-- =============================================================================
-- Buffer & LSP Cleanup
-- =============================================================================

local function cleanup_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Stop all LSP clients attached to this buffer
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    pcall(function()
      vim.lsp.buf_detach_client(bufnr, client.id)
    end)
  end

  -- Force delete buffer
  pcall(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end

local function cleanup_all_buffers()
  log("  [CLEANUP] Starting periodic buffer cleanup...", "DEBUG")
  local cleaned = 0

  -- Get all buffers
  local buffers = vim.api.nvim_list_bufs()
  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      -- Only cleanup repo test buffers, not our working files
      if name:match("%.cache/editutor%-tests/repos/") then
        cleanup_buffer(bufnr)
        cleaned = cleaned + 1
      end
    end
  end

  -- Force garbage collection
  collectgarbage("collect")

  log(string.format("  [CLEANUP] Cleaned %d buffers, GC done", cleaned), "DEBUG")
  return cleaned
end

local function stop_all_lsp_clients()
  log("  [CLEANUP] Stopping all LSP clients...", "DEBUG")
  local clients = vim.lsp.get_clients()
  local stopped = 0
  for _, client in ipairs(clients) do
    pcall(function()
      client.stop()
      stopped = stopped + 1
    end)
  end
  -- Give LSP time to shutdown
  vim.wait(500, function() return false end)
  collectgarbage("collect")
  log(string.format("  [CLEANUP] Stopped %d LSP clients, GC done", stopped), "DEBUG")
  return stopped
end

-- Track current repo for cleanup on repo change
local current_test_repo = nil

-- =============================================================================
-- Project Structure Capture
-- =============================================================================

local function capture_project_structure(repo_path, max_depth)
  max_depth = max_depth or 3
  local structure = {}

  local function scan_dir(path, depth, prefix)
    if depth > max_depth then return end

    local handle = vim.loop.fs_scandir(path)
    if not handle then return end

    local entries = {}
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end

      -- Skip hidden and common non-source dirs
      if not name:match("^%.") and
         name ~= "node_modules" and
         name ~= "vendor" and
         name ~= "target" and
         name ~= "build" and
         name ~= "dist" and
         name ~= "__pycache__" then
        table.insert(entries, {name = name, type = type})
      end
    end

    table.sort(entries, function(a, b) return a.name < b.name end)

    for i, entry in ipairs(entries) do
      local is_last = (i == #entries)
      local connector = is_last and "└── " or "├── "
      local child_prefix = is_last and "    " or "│   "

      table.insert(structure, prefix .. connector .. entry.name)

      if entry.type == "directory" then
        scan_dir(path .. "/" .. entry.name, depth + 1, prefix .. child_prefix)
      end
    end
  end

  local repo_name = vim.fn.fnamemodify(repo_path, ":t")
  table.insert(structure, repo_name .. "/")
  scan_dir(repo_path, 1, "")

  return table.concat(structure, "\n")
end

-- =============================================================================
-- LSP Waiting
-- =============================================================================

local function wait_for_lsp(bufnr, timeout, callback)
  local start_time = vim.loop.now()

  local function check()
    local clients = vim.lsp.get_clients({ bufnr = bufnr })

    for _, client in ipairs(clients) do
      if client.initialized then
        -- Give LSP a moment to process the file
        vim.defer_fn(function()
          callback(true, clients)
        end, 500)
        return
      end
    end

    if vim.loop.now() - start_time > timeout then
      callback(false, nil, "timeout")
      return
    end

    vim.defer_fn(check, 200)
  end

  check()
end

-- =============================================================================
-- Test Case Execution
-- =============================================================================

local function run_test_case(tc, callback)
  local result = {
    test_case = tc,
    status = "pending",
    file_path = test_cases.get_file_path(tc),
    file_exists = false,
    file_lines = 0,
    lsp = {
      available = false,
      clients = {},
      timeout = false,
    },
    context = {
      mode = nil,
      total_tokens = 0,
      files_included = 0,
      extraction_time_ms = 0,
      strategy_level = nil,
    },
    library_info = {
      items = 0,
      tokens = 0,
      identifiers_scanned = 0,
    },
    errors = {},
    context_preview = nil,  -- First 500 chars of context
  }

  -- Check file exists
  if vim.fn.filereadable(result.file_path) ~= 1 then
    result.status = "skipped"
    result.errors[#result.errors + 1] = "File not found: " .. result.file_path
    callback(result)
    return
  end
  result.file_exists = true

  -- Open file
  local ok, err = pcall(function()
    vim.cmd("edit " .. vim.fn.fnameescape(result.file_path))
  end)

  if not ok then
    result.status = "failed"
    result.errors[#result.errors + 1] = "Failed to open file: " .. tostring(err)
    callback(result)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  result.file_lines = vim.api.nvim_buf_line_count(bufnr)

  -- Wait for LSP
  wait_for_lsp(bufnr, M.config.lsp_timeout, function(lsp_ready, clients, lsp_err)
    result.lsp.available = lsp_ready
    result.lsp.timeout = (lsp_err == "timeout")

    if lsp_err == "timeout" then
      result.errors[#result.errors + 1] = "LSP timeout after " .. M.config.lsp_timeout .. "ms"
    elseif not lsp_ready then
      result.errors[#result.errors + 1] = "LSP not available for this file type"
    end

    if clients then
      for _, client in ipairs(clients) do
        table.insert(result.lsp.clients, client.name)
      end
    end

    -- Create mock question for context extraction
    local parser = require("editutor.parser")
    local mock_question = {
      id = parser.generate_id(),
      question = tc.question,
      block_start = tc.lines[1],
      block_end = tc.lines[2],
      filepath = result.file_path,
    }

    -- Extract context with error handling and timeout
    local context_module = require("editutor.context")
    local start_time = vim.loop.now()
    local extraction_done = false
    local extraction_timeout = 30000  -- 30 seconds timeout

    -- Timeout handler
    vim.defer_fn(function()
      if not extraction_done then
        extraction_done = true
        result.status = "failed"
        result.errors[#result.errors + 1] = "Context extraction timeout after " .. extraction_timeout .. "ms"
        log("    [TIMEOUT] Context extraction timed out", "ERROR")

        -- Close buffer with proper cleanup
        cleanup_buffer(bufnr)

        callback(result)
      end
    end, extraction_timeout)

    log("    Starting context extraction...", "DEBUG")
    log(string.format("    File path: %s", result.file_path), "DEBUG")
    log(string.format("    Question ID: %s", mock_question.id), "DEBUG")

    local extract_ok, extract_err = pcall(function()
      log("    Calling context_module.extract()...", "DEBUG")
      context_module.extract(function(context_text, metadata)
        log("    Context extraction callback received", "DEBUG")
        if extraction_done then
          return  -- Already timed out
        end
        extraction_done = true
      local elapsed = vim.loop.now() - start_time
      result.context.extraction_time_ms = elapsed

      log(string.format("    Context text length: %d", context_text and #context_text or 0), "DEBUG")
      log(string.format("    Metadata mode: %s", metadata and metadata.mode or "nil"), "DEBUG")

      if metadata then
        log("    Processing metadata...", "DEBUG")
        result.context.mode = metadata.mode
        result.context.total_tokens = metadata.total_tokens
          or (metadata.token_usage and metadata.token_usage.total)
          or 0
        -- files_included can be a table or number depending on context mode
        local files = metadata.files_included or metadata.files or 0
        if type(files) == "table" then
          result.context.files_included = #files
        else
          result.context.files_included = files
        end
        result.context.strategy_level = metadata.strategy_level or (metadata.strategy and metadata.strategy.level_used)

        -- Log metadata errors
        if metadata.error then
          result.errors[#result.errors + 1] = "Context error: " .. tostring(metadata.error)
        end
        if metadata.details and metadata.details.error then
          result.errors[#result.errors + 1] = "Strategy error: " .. tostring(metadata.details.error)
        end

        if metadata.library_info then
          result.library_info.items = metadata.library_info.items or 0
          result.library_info.tokens = metadata.library_info.tokens or 0

          -- Log library info errors
          if metadata.library_info.errors then
            local lib_errors = metadata.library_info.errors
            if type(lib_errors) == "table" then
              for _, lib_err in ipairs(lib_errors) do
                result.errors[#result.errors + 1] = "Library info: " .. tostring(lib_err)
              end
            elseif type(lib_errors) == "number" and lib_errors > 0 then
              result.errors[#result.errors + 1] = "Library info: " .. lib_errors .. " errors occurred"
            end
          end
          if metadata.library_info.error then
            result.errors[#result.errors + 1] = "Library info: " .. tostring(metadata.library_info.error)
          end
        end
        log("    Metadata processed", "DEBUG")
      else
        result.errors[#result.errors + 1] = "Context extraction returned nil metadata"
        log("    No metadata received", "DEBUG")
      end

      if not context_text or #context_text == 0 then
        result.errors[#result.errors + 1] = "Context extraction returned empty context"
        log("    Empty context", "DEBUG")
      end

      log("    Saving context...", "DEBUG")

      -- Save context preview
      if context_text and #context_text > 0 then
        result.context_preview = context_text:sub(1, 1000) .. (
          #context_text > 1000 and "\n... [truncated]" or ""
        )

        -- Save full context if enabled
        if M.config.save_contexts then
          log("    Writing context file...", "DEBUG")
          local context_dir = M.config.results_dir .. "/contexts/" .. tc.repo
          vim.fn.mkdir(context_dir, "p")

          local safe_file = tc.file:gsub("/", "_"):gsub("%.", "_")
          local context_path = string.format("%s/%s_L%d-%d.txt",
            context_dir, safe_file, tc.lines[1], tc.lines[2])

          local write_ok, write_err = pcall(function()
            local f = io.open(context_path, "w")
            if f then
              log(string.format("    Context file opened: %s", context_path), "DEBUG")
              f:write("=== TEST CASE ===\n")
              f:write(string.format("Repo: %s\n", tc.repo))
              f:write(string.format("File: %s\n", tc.file))
              f:write(string.format("Lines: %d-%d\n", tc.lines[1], tc.lines[2]))
              f:write(string.format("Language: %s\n", tc.lang))
              f:write(string.format("Pattern: %s\n", tc.pattern))
              f:write(string.format("Question: %s\n", tc.question))
              f:write("\n=== METADATA ===\n")
              f:write(string.format("Mode: %s\n", result.context.mode or "unknown"))
              f:write(string.format("Tokens: %d\n", result.context.total_tokens))
              f:write(string.format("Files: %d\n", result.context.files_included))
              f:write(string.format("LSP: %s\n", result.lsp.available and "yes" or "no"))
              f:write(string.format("LSP Clients: %s\n", table.concat(result.lsp.clients, ", ")))
              f:write(string.format("Library Info Items: %d\n", result.library_info.items))
              f:write(string.format("Extraction Time: %dms\n", result.context.extraction_time_ms))
              if #result.errors > 0 then
                f:write("\n=== ERRORS ===\n")
                for _, err in ipairs(result.errors) do
                  f:write("- " .. err .. "\n")
                end
              end
              f:write("\n=== CONTEXT ===\n")
              f:write(context_text or "(empty)")
              f:close()
              log("    Context file written and closed", "DEBUG")
            else
              log("    Failed to open context file", "ERROR")
            end
          end)
          if not write_ok then
            log(string.format("    Context file write error: %s", tostring(write_err)), "ERROR")
          end
        end
      else
        log("    Skipping context save (empty context)", "DEBUG")
      end

      log("    Determining final status...", "DEBUG")

      -- Determine final status based on errors
      local critical_errors = 0
      for _, err in ipairs(result.errors) do
        -- Count critical errors (not warnings like "LSP not available")
        if err:match("Context error") or
           err:match("Strategy error") or
           err:match("nil metadata") or
           err:match("empty context") then
          critical_errors = critical_errors + 1
        end
      end

      if critical_errors > 0 then
        result.status = "failed"
      elseif #result.errors > 0 then
        result.status = "passed"  -- Passed with warnings
      else
        result.status = "passed"
      end

      log(string.format("    Test case complete, status: %s", result.status), "DEBUG")

      -- Close buffer with proper cleanup
      cleanup_buffer(bufnr)

      log("    Calling test callback...", "DEBUG")
        callback(result)
      end, {
        current_file = result.file_path,
        questions = {mock_question},
      })
    end)

    if not extract_ok then
      if not extraction_done then
        extraction_done = true
        result.status = "failed"
        result.errors[#result.errors + 1] = "Context extraction error: " .. tostring(extract_err)
        log("    [ERROR] " .. tostring(extract_err), "ERROR")

        -- Close buffer with proper cleanup
        cleanup_buffer(bufnr)

        callback(result)
      end
    end
  end)
end

-- =============================================================================
-- Main Runner
-- =============================================================================

function M.run(opts)
  opts = opts or {}

  -- Merge config
  if opts.config then
    M.config = vim.tbl_deep_extend("force", M.config, opts.config)
  end

  -- Filter test cases
  local cases_to_run = test_cases.TEST_CASES
  if opts.lang then
    cases_to_run = test_cases.get_by_language(opts.lang)
  elseif opts.repo then
    cases_to_run = test_cases.get_by_repo(opts.repo)
  elseif opts.pattern then
    cases_to_run = test_cases.get_by_pattern(opts.pattern)
  elseif opts.limit then
    cases_to_run = {}
    for i = 1, math.min(opts.limit, #test_cases.TEST_CASES) do
      table.insert(cases_to_run, test_cases.TEST_CASES[i])
    end
  end

  -- Initialize
  local log_path = init_log()
  results = {
    started_at = os.date("%Y-%m-%d %H:%M:%S"),
    completed_at = nil,
    config = vim.deepcopy(M.config),
    test_cases = {},
    summary = {
      total = #cases_to_run,
      passed = 0,
      failed = 0,
      skipped = 0,
      by_language = {},
      by_pattern = {},
      lsp_stats = { available = 0, unavailable = 0, timeout = 0 },
      context_stats = { full_project = 0, adaptive = 0, total_tokens = 0, total_extraction_ms = 0 },
      library_info_stats = { with_info = 0, without_info = 0, total_items = 0 },
    },
    errors = {},
  }

  log("========================================")
  log("ai-editutor Automated Test Runner")
  log("========================================")
  log(string.format("Log file: %s", log_path))
  log(string.format("Test cases: %d", #cases_to_run))
  log(string.format("Results dir: %s", M.config.results_dir))
  log("")

  -- Support starting from a specific index
  local start_index = opts.start_from or M.config.start_from or 1
  local case_index = start_index - 1  -- Will be incremented to start_index
  local total_tokens = 0
  local total_extraction_ms = 0

  if start_index > 1 then
    log(string.format("Starting from test case #%d", start_index))
  end

  -- Reset repo tracker
  current_test_repo = nil

  local function run_next()
    case_index = case_index + 1

    if case_index > #cases_to_run then
      M.finish()
      return
    end

    local tc = cases_to_run[case_index]

    -- Stop LSP clients when switching to a different repo (prevents memory buildup)
    if current_test_repo and current_test_repo ~= tc.repo then
      log(string.format("  [REPO CHANGE] %s -> %s", current_test_repo, tc.repo), "DEBUG")
      cleanup_all_buffers()
      stop_all_lsp_clients()
    end
    current_test_repo = tc.repo

    -- Periodic cleanup to prevent memory buildup
    if M.config.cleanup_interval > 0 and case_index > start_index and
       (case_index - start_index) % M.config.cleanup_interval == 0 then
      cleanup_all_buffers()
    end

    log(string.format("[%d/%d] %s/%s (L%d-%d)",
      case_index, #cases_to_run, tc.repo, tc.file, tc.lines[1], tc.lines[2]))

    run_test_case(tc, function(result)
      table.insert(results.test_cases, result)

      -- Update summary
      if result.status == "passed" then
        results.summary.passed = results.summary.passed + 1
      elseif result.status == "failed" then
        results.summary.failed = results.summary.failed + 1
      else
        results.summary.skipped = results.summary.skipped + 1
      end

      -- Language stats
      local lang = tc.lang
      results.summary.by_language[lang] = results.summary.by_language[lang] or {passed = 0, failed = 0, skipped = 0}
      results.summary.by_language[lang][result.status] = (results.summary.by_language[lang][result.status] or 0) + 1

      -- Pattern stats
      local pattern = tc.pattern
      results.summary.by_pattern[pattern] = results.summary.by_pattern[pattern] or {passed = 0, failed = 0, skipped = 0}
      results.summary.by_pattern[pattern][result.status] = (results.summary.by_pattern[pattern][result.status] or 0) + 1

      -- LSP stats
      if result.lsp.available then
        results.summary.lsp_stats.available = results.summary.lsp_stats.available + 1
      elseif result.lsp.timeout then
        results.summary.lsp_stats.timeout = results.summary.lsp_stats.timeout + 1
      else
        results.summary.lsp_stats.unavailable = results.summary.lsp_stats.unavailable + 1
      end

      -- Context stats
      if result.context.mode == "full_project" then
        results.summary.context_stats.full_project = results.summary.context_stats.full_project + 1
      elseif result.context.mode == "adaptive" then
        results.summary.context_stats.adaptive = results.summary.context_stats.adaptive + 1
      end
      total_tokens = total_tokens + (result.context.total_tokens or 0)
      total_extraction_ms = total_extraction_ms + (result.context.extraction_time_ms or 0)

      -- Library info stats
      if result.library_info.items > 0 then
        results.summary.library_info_stats.with_info = results.summary.library_info_stats.with_info + 1
        results.summary.library_info_stats.total_items = results.summary.library_info_stats.total_items + result.library_info.items
      else
        results.summary.library_info_stats.without_info = results.summary.library_info_stats.without_info + 1
      end

      -- Log result
      local status_icon = result.status == "passed" and "OK" or (result.status == "skipped" and "SKIP" or "FAIL")
      log(string.format("  [%s] mode=%s tokens=%d lsp=%s lib_items=%d time=%dms",
        status_icon,
        result.context.mode or "?",
        result.context.total_tokens,
        result.lsp.available and table.concat(result.lsp.clients, ",") or "none",
        result.library_info.items,
        result.context.extraction_time_ms
      ))

      if #result.errors > 0 then
        for _, err in ipairs(result.errors) do
          log("    ERROR: " .. err, "ERROR")
        end
      end

      -- Small delay between tests
      vim.defer_fn(run_next, 200)
    end)
  end

  run_next()
end

-- =============================================================================
-- Finish & Report
-- =============================================================================

function M.finish()
  results.completed_at = os.date("%Y-%m-%d %H:%M:%S")

  -- Calculate averages
  local passed_count = math.max(1, results.summary.passed)
  results.summary.context_stats.avg_tokens = math.floor(
    results.summary.context_stats.total_tokens or 0 / passed_count
  )
  results.summary.context_stats.avg_extraction_ms = math.floor(
    results.summary.context_stats.total_extraction_ms or 0 / passed_count
  )

  log("")
  log("========================================")
  log("TEST COMPLETE")
  log("========================================")
  log("")
  log(string.format("Total: %d | Passed: %d | Failed: %d | Skipped: %d",
    results.summary.total,
    results.summary.passed,
    results.summary.failed,
    results.summary.skipped
  ))
  log("")
  log("LSP Stats:")
  log(string.format("  Available: %d | Unavailable: %d | Timeout: %d",
    results.summary.lsp_stats.available,
    results.summary.lsp_stats.unavailable,
    results.summary.lsp_stats.timeout
  ))
  log("")
  log("Context Stats:")
  log(string.format("  Full Project: %d | Adaptive: %d",
    results.summary.context_stats.full_project,
    results.summary.context_stats.adaptive
  ))
  log("")
  log("Library Info Stats:")
  log(string.format("  With Info: %d | Without: %d | Total Items: %d",
    results.summary.library_info_stats.with_info,
    results.summary.library_info_stats.without_info,
    results.summary.library_info_stats.total_items
  ))

  -- Save JSON results
  local json_path = M.config.results_dir .. "/results.json"
  local f = io.open(json_path, "w")
  if f then
    f:write(vim.fn.json_encode(results))
    f:close()
    log("")
    log("Results saved to: " .. json_path)
  end

  -- Generate markdown report
  local report_path = M.config.results_dir .. "/report.md"
  M.generate_report(report_path)
  log("Report saved to: " .. report_path)

  close_log()

  vim.notify(string.format(
    "Test complete: %d/%d passed. See %s",
    results.summary.passed,
    results.summary.total,
    M.config.results_dir
  ), vim.log.levels.INFO)
end

function M.generate_report(filepath)
  local lines = {
    "# ai-editutor Test Report",
    "",
    string.format("**Started:** %s", results.started_at),
    string.format("**Completed:** %s", results.completed_at),
    "",
    "## Summary",
    "",
    "| Metric | Value |",
    "|--------|-------|",
    string.format("| Total Test Cases | %d |", results.summary.total),
    string.format("| Passed | %d (%.1f%%) |", results.summary.passed, results.summary.passed / math.max(1, results.summary.total) * 100),
    string.format("| Failed | %d |", results.summary.failed),
    string.format("| Skipped | %d |", results.summary.skipped),
    "",
    "## LSP Statistics",
    "",
    "| Status | Count |",
    "|--------|-------|",
    string.format("| Available | %d |", results.summary.lsp_stats.available),
    string.format("| Unavailable | %d |", results.summary.lsp_stats.unavailable),
    string.format("| Timeout | %d |", results.summary.lsp_stats.timeout),
    "",
    "## Context Mode Distribution",
    "",
    "| Mode | Count |",
    "|------|-------|",
    string.format("| Full Project | %d |", results.summary.context_stats.full_project),
    string.format("| Adaptive | %d |", results.summary.context_stats.adaptive),
    "",
    "## Library Info Extraction",
    "",
    "| Metric | Value |",
    "|--------|-------|",
    string.format("| Cases with library info | %d |", results.summary.library_info_stats.with_info),
    string.format("| Cases without | %d |", results.summary.library_info_stats.without_info),
    string.format("| Total items extracted | %d |", results.summary.library_info_stats.total_items),
    "",
    "## Results by Language",
    "",
    "| Language | Passed | Failed | Skipped |",
    "|----------|--------|--------|---------|",
  }

  for lang, stats in pairs(results.summary.by_language) do
    table.insert(lines, string.format("| %s | %d | %d | %d |",
      lang, stats.passed or 0, stats.failed or 0, stats.skipped or 0))
  end

  table.insert(lines, "")
  table.insert(lines, "## Results by Pattern")
  table.insert(lines, "")
  table.insert(lines, "| Pattern | Passed | Failed | Skipped |")
  table.insert(lines, "|---------|--------|--------|---------|")

  for pattern, stats in pairs(results.summary.by_pattern) do
    table.insert(lines, string.format("| %s | %d | %d | %d |",
      pattern, stats.passed or 0, stats.failed or 0, stats.skipped or 0))
  end

  table.insert(lines, "")
  table.insert(lines, "## Test Case Details")
  table.insert(lines, "")

  for i, tc_result in ipairs(results.test_cases) do
    local tc = tc_result.test_case
    local status_emoji = tc_result.status == "passed" and "PASS" or (tc_result.status == "skipped" and "SKIP" or "FAIL")

    table.insert(lines, string.format("### %d. [%s] %s/%s", i, status_emoji, tc.repo, tc.file))
    table.insert(lines, "")
    table.insert(lines, string.format("- **Lines:** %d-%d", tc.lines[1], tc.lines[2]))
    table.insert(lines, string.format("- **Language:** %s", tc.lang))
    table.insert(lines, string.format("- **Pattern:** %s", tc.pattern))
    table.insert(lines, string.format("- **Question:** %s", tc.question))
    table.insert(lines, "")
    table.insert(lines, "**Results:**")
    table.insert(lines, string.format("- Context Mode: %s", tc_result.context.mode or "N/A"))
    table.insert(lines, string.format("- Tokens: %d", tc_result.context.total_tokens))
    table.insert(lines, string.format("- Files Included: %d", tc_result.context.files_included))
    table.insert(lines, string.format("- LSP: %s", tc_result.lsp.available and table.concat(tc_result.lsp.clients, ", ") or "unavailable"))
    table.insert(lines, string.format("- Library Info Items: %d", tc_result.library_info.items))
    table.insert(lines, string.format("- Extraction Time: %dms", tc_result.context.extraction_time_ms))

    if #tc_result.errors > 0 then
      table.insert(lines, "")
      table.insert(lines, "**Errors:**")
      for _, err in ipairs(tc_result.errors) do
        table.insert(lines, "- " .. err)
      end
    end

    table.insert(lines, "")
  end

  local f = io.open(filepath, "w")
  if f then
    f:write(table.concat(lines, "\n"))
    f:close()
  end
end

-- =============================================================================
-- Quick Commands
-- =============================================================================

function M.quick_test()
  M.run({ limit = 5 })
end

function M.test_lang(lang)
  M.run({ lang = lang })
end

function M.test_repo(repo)
  M.run({ repo = repo })
end

function M.test_pattern(pattern)
  M.run({ pattern = pattern })
end

function M.view_results()
  local report = M.config.results_dir .. "/report.md"
  if vim.fn.filereadable(report) == 1 then
    vim.cmd("edit " .. report)
  else
    vim.notify("No results found. Run tests first.", vim.log.levels.WARN)
  end
end

function M.show_stats()
  local stats = test_cases.get_stats()
  print("=== Test Cases Statistics ===")
  print(string.format("Total: %d", stats.total))
  print("")
  print("By Language:")
  for lang, count in pairs(stats.by_language) do
    print(string.format("  %s: %d", lang, count))
  end
  print("")
  print("By Pattern:")
  for pattern, count in pairs(stats.by_pattern) do
    print(string.format("  %s: %d", pattern, count))
  end
end

function M.validate_cases()
  local validation = test_cases.validate()
  print(string.format("Valid: %d | Invalid: %d", #validation.valid, #validation.invalid))
  if #validation.invalid > 0 then
    print("")
    print("Invalid cases:")
    for _, inv in ipairs(validation.invalid) do
      print(string.format("  - %s/%s: %s", inv.test_case.repo, inv.test_case.file, inv.error))
    end
  end
end

-- Resume test from a specific index
function M.resume(start_index)
  M.run({ start_from = start_index })
end

-- Force cleanup all test buffers
function M.cleanup()
  local cleaned = cleanup_all_buffers()
  vim.notify(string.format("Cleaned %d test buffers", cleaned), vim.log.levels.INFO)
end

-- Get test case info by index
function M.get_case(index)
  local tc = test_cases.TEST_CASES[index]
  if tc then
    print(string.format("Test case #%d:", index))
    print(string.format("  repo: %s", tc.repo))
    print(string.format("  file: %s", tc.file))
    print(string.format("  lang: %s", tc.lang))
    print(string.format("  lines: %d-%d", tc.lines[1], tc.lines[2]))
    print(string.format("  pattern: %s", tc.pattern))
    print(string.format("  question: %s", tc.question))
    return tc
  else
    print("Test case not found: " .. index)
    return nil
  end
end

return M
