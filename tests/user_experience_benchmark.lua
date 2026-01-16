-- user_experience_benchmark.lua
-- Simulates REAL user experience: opens files, places cursor, asks questions
-- Tests what context would actually be sent to LLM
--
-- Usage:
--   nvim --headless -u tests/minimal_init.lua \
--     -c "lua require('tests.user_experience_benchmark').run()" -c "qa"

local M = {}

-- =============================================================================
-- Question Templates (diverse types of questions)
-- =============================================================================

local QUESTION_TYPES = {
  concept = {
    "What is this?",
    "What does this do?",
    "Explain this code",
    "What pattern is used here?",
    "What is the purpose of this?",
  },
  review = {
    "Review this code",
    "What could be improved here?",
    "Are there any issues?",
    "Is this idiomatic?",
    "Rate this code",
  },
  debug = {
    "Why isn't this working?",
    "Debug: what's wrong here?",
    "Why would this fail?",
    "What edge cases might break this?",
    "Potential bugs?",
  },
  howto = {
    "How do I use this?",
    "How to extend this?",
    "How would I test this?",
    "How to add error handling?",
    "Best practices for this?",
  },
  understand = {
    "Walk me through this",
    "Explain step by step",
    "What happens when this runs?",
    "Trace the execution flow",
    "Help me understand this",
  },
}

local function random_question(qtype)
  local questions = QUESTION_TYPES[qtype] or QUESTION_TYPES.concept
  return questions[math.random(#questions)]
end

-- =============================================================================
-- Test Repositories Configuration - 50 diverse repos
-- =============================================================================

M.TEST_REPOS = {
  -- ============ JavaScript/TypeScript ============
  
  -- Small JS
  { url = "https://github.com/lukeed/clsx", lang = "javascript", size = "small", auto_files = true, max_questions = 20 },
  { url = "https://github.com/ai/nanoid", lang = "javascript", size = "small", auto_files = true, max_questions = 20 },
  { url = "https://github.com/jorgebucaran/hyperapp", lang = "javascript", size = "small", auto_files = true, max_questions = 20 },
  
  -- Medium JS  
  { url = "https://github.com/chalk/chalk", lang = "javascript", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/expressjs/express", lang = "javascript", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/lodash/lodash", lang = "javascript", size = "medium", auto_files = true, max_questions = 20 },
  
  -- Large TS
  { url = "https://github.com/vuejs/core", lang = "typescript", size = "large", auto_files = true, max_questions = 20 },
  { url = "https://github.com/jaredpalmer/formik", lang = "typescript", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/nestjs/nest", lang = "typescript", size = "large", auto_files = true, max_questions = 20 },
  
  -- ============ Python ============
  
  -- Small/Medium Python
  { url = "https://github.com/tqdm/tqdm", lang = "python", size = "small", auto_files = true, max_questions = 20 },
  { url = "https://github.com/pallets/click", lang = "python", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/psf/black", lang = "python", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/httpie/cli", lang = "python", size = "medium", auto_files = true, max_questions = 20 },
  
  -- Large Python
  { url = "https://github.com/tiangolo/fastapi", lang = "python", size = "large", auto_files = true, max_questions = 20 },
  { url = "https://github.com/pallets/flask", lang = "python", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/django/django", lang = "python", size = "large", auto_files = true, max_questions = 20 },
  
  -- ============ Rust ============
  
  { url = "https://github.com/sharkdp/fd", lang = "rust", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/BurntSushi/ripgrep", lang = "rust", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/sharkdp/bat", lang = "rust", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/alacritty/alacritty", lang = "rust", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/starship/starship", lang = "rust", size = "medium", auto_files = true, max_questions = 20 },
  
  -- ============ Go ============
  
  { url = "https://github.com/gin-gonic/gin", lang = "go", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/gofiber/fiber", lang = "go", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/charmbracelet/bubbletea", lang = "go", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/junegunn/fzf", lang = "go", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/jesseduffield/lazygit", lang = "go", size = "large", auto_files = true, max_questions = 20 },
  
  -- ============ Lua ============
  
  { url = "https://github.com/folke/lazy.nvim", lang = "lua", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/nvim-lua/plenary.nvim", lang = "lua", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/nvim-telescope/telescope.nvim", lang = "lua", size = "medium", auto_files = true, max_questions = 20 },
  
  -- ============ Ruby ============
  
  { url = "https://github.com/jekyll/jekyll", lang = "ruby", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/Homebrew/brew", lang = "ruby", size = "large", auto_files = true, max_questions = 20 },
  { url = "https://github.com/rails/rails", lang = "ruby", size = "large", auto_files = true, max_questions = 20 },
  
  -- ============ PHP ============
  
  { url = "https://github.com/laravel/laravel", lang = "php", size = "small", auto_files = true, max_questions = 20 },
  { url = "https://github.com/laravel/framework", lang = "php", size = "large", auto_files = true, max_questions = 20 },
  
  -- ============ Java/Kotlin ============
  
  { url = "https://github.com/spring-projects/spring-petclinic", lang = "java", size = "small", auto_files = true, max_questions = 20 },
  { url = "https://github.com/square/okhttp", lang = "kotlin", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/square/retrofit", lang = "java", size = "medium", auto_files = true, max_questions = 20 },
  
  -- ============ C/C++ ============
  
  { url = "https://github.com/jqlang/jq", lang = "c", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/redis/redis", lang = "c", size = "large", auto_files = true, max_questions = 20 },
  { url = "https://github.com/nlohmann/json", lang = "cpp", size = "medium", auto_files = true, max_questions = 20 },
  { url = "https://github.com/gabime/spdlog", lang = "cpp", size = "medium", auto_files = true, max_questions = 20 },
  
  -- ============ Misc ============
  
  { url = "https://github.com/yarnpkg/berry", lang = "typescript", size = "large", auto_files = true, max_questions = 20 },
  { url = "https://github.com/sveltejs/svelte", lang = "javascript", size = "large", auto_files = true, max_questions = 20 },
  { url = "https://github.com/evanw/esbuild", lang = "go", size = "large", auto_files = true, max_questions = 20 },
}

-- =============================================================================
-- Configuration
-- =============================================================================

M.CONFIG = {
  clone_dir = "/tmp/editutor-ux-test",
  output_dir = "tests/benchmark_results",
  token_budget = 20000,
}

-- Language file extensions
local LANG_EXTENSIONS = {
  javascript = { "js", "jsx", "mjs", "cjs" },
  typescript = { "ts", "tsx" },
  python = { "py" },
  rust = { "rs" },
  go = { "go" },
  lua = { "lua" },
  ruby = { "rb" },
  php = { "php" },
  java = { "java" },
  kotlin = { "kt", "kts" },
  c = { "c", "h" },
  cpp = { "cpp", "cc", "cxx", "hpp", "hxx" },
}

-- =============================================================================
-- Utilities
-- =============================================================================

local function log(msg)
  print(string.format("[%s] %s", os.date("%H:%M:%S"), msg))
end

local function ensure_dir(path)
  vim.fn.mkdir(path, "p")
end

local function get_repo_name(url)
  return url:match("([^/]+)$")
end

local function clone_repo(url, target)
  if vim.fn.isdirectory(target) == 1 then
    return true
  end
  local cmd = string.format("git clone --depth 1 %s %s 2>/dev/null", url, target)
  os.execute(cmd)
  return vim.fn.isdirectory(target) == 1
end

local function file_exists(path)
  return vim.fn.filereadable(path) == 1
end

local function format_tokens(n)
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 1000 then return string.format("%.1fK", n / 1000) end
  return tostring(n)
end

---Find source files in a repo directory
---@param repo_path string
---@param extensions string[]
---@param max_files number
---@return string[] List of relative file paths
local function find_source_files(repo_path, extensions, max_files)
  local files = {}
  
  -- Build find command with multiple -name options
  local name_parts = {}
  for _, ext in ipairs(extensions) do
    table.insert(name_parts, string.format("-name '*.%s'", ext))
  end
  local name_expr = "\\( " .. table.concat(name_parts, " -o ") .. " \\)"
  
  local cmd = string.format(
    "find %s -type f %s 2>/dev/null | grep -v node_modules | grep -v vendor | grep -v __pycache__ | grep -v '.min.' | head -100",
    repo_path,
    name_expr
  )
  
  local handle = io.popen(cmd)
  if handle then
    for line in handle:lines() do
      -- Get relative path - use string sub since gsub pattern escaping is tricky
      local prefix_len = #repo_path + 2  -- +2 for trailing / and 1-based index
      local rel = line:sub(prefix_len)
      -- Skip hidden files
      if rel and #rel > 0 and not rel:match("^%.") and not rel:match("/%.") then
        table.insert(files, rel)
        if #files >= max_files then break end
      end
    end
    handle:close()
  end
  
  return files
end

---Generate test questions for a file
---@param filepath string
---@param num_questions number
---@return table[] List of {line, question, qtype}
local function generate_questions_for_file(filepath, num_questions)
  local questions = {}
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then return questions end
  
  local total_lines = #lines
  if total_lines < 5 then return questions end
  
  -- Spread questions across the file
  local step = math.max(1, math.floor(total_lines / (num_questions + 1)))
  local qtypes = { "concept", "review", "debug", "howto", "understand" }
  
  for i = 1, num_questions do
    local line = math.min(i * step, total_lines)
    local qtype = qtypes[(i % #qtypes) + 1]
    table.insert(questions, {
      line = line,
      question = random_question(qtype),
      qtype = qtype,
    })
  end
  
  return questions
end

-- =============================================================================
-- Test Runner
-- =============================================================================

---@class TestResult
---@field repo string Repository name
---@field file string File path
---@field line number Question line
---@field question string The question
---@field qtype string Question type
---@field mode string "full_project" | "lsp_selective"
---@field context_tokens number Tokens in context
---@field has_lsp boolean Whether LSP was available
---@field external_files number Number of external files included
---@field current_file_lines number Lines in current file
---@field tree_lines number Lines in tree structure
---@field within_budget boolean Whether context fits in budget
---@field error string|nil Error message if failed

---Run a single test case (synchronous version for headless mode)
---@param repo_path string
---@param file_rel_path string
---@param line number
---@param question string
---@param qtype string
---@return TestResult
local function run_test_case_sync(repo_path, file_rel_path, line, question, qtype)
  local full_path = repo_path .. "/" .. file_rel_path
  
  -- Check file exists
  if not file_exists(full_path) then
    return {
      file = file_rel_path,
      line = line,
      question = question,
      qtype = qtype,
      error = "File not found",
    }
  end
  
  -- Clear module cache
  for k in pairs(package.loaded) do
    if k:match("^editutor") then
      package.loaded[k] = nil
    end
  end
  
  -- Read file into buffer
  local bufnr = vim.fn.bufadd(full_path)
  vim.fn.bufload(bufnr)
  vim.api.nvim_set_current_buf(bufnr)
  
  -- Get line count and adjust
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local actual_line = math.min(line, line_count)
  vim.api.nvim_win_set_cursor(0, { actual_line, 0 })
  
  -- Load context module
  local ok, context_mod = pcall(require, "editutor.context")
  if not ok then
    return {
      file = file_rel_path,
      line = actual_line,
      question = question,
      qtype = qtype,
      error = "Failed to load context: " .. tostring(context_mod),
    }
  end
  
  -- Extract context synchronously (full_project mode is sync, lsp is async but we handle it)
  local result = nil
  local done = false
  
  context_mod.extract(function(formatted_context, metadata)
    result = {
      file = file_rel_path,
      line = actual_line,
      question = question,
      qtype = qtype,
      mode = metadata.mode,
      context_tokens = metadata.total_tokens or 0,
      has_lsp = metadata.has_lsp or false,
      external_files = metadata.external_files and #metadata.external_files or 0,
      current_file_lines = metadata.current_lines or 0,
      tree_lines = metadata.tree_structure_lines or 0,
      within_budget = metadata.within_budget or false,
      context_preview = formatted_context and formatted_context:sub(1, 1000) or "",
    }
    done = true
  end, {
    current_file = full_path,
    question_line = actual_line,
  })
  
  -- Wait for async callback (with timeout)
  local timeout = 100  -- 100 iterations
  while not done and timeout > 0 do
    vim.wait(10)
    timeout = timeout - 1
  end
  
  if not result then
    return {
      file = file_rel_path,
      line = actual_line,
      question = question,
      qtype = qtype,
      error = "Timeout waiting for context",
    }
  end
  
  return result
end

---Run all tests for a repository
---@param repo table Repository config
---@return TestResult[]
local function run_repo_tests(repo)
  local repo_name = get_repo_name(repo.url)
  local repo_path = M.CONFIG.clone_dir .. "/" .. repo_name
  
  log(string.format("Testing: %s (%s)", repo_name, repo.lang))
  
  -- Clone if needed
  if not clone_repo(repo.url, repo_path) then
    log("  ERROR: Failed to clone")
    return {}
  end
  
  local results = {}
  local extensions = LANG_EXTENSIONS[repo.lang] or { repo.lang }
  
  -- Find source files automatically
  local source_files = find_source_files(repo_path, extensions, 10)  -- Max 10 files per repo
  
  if #source_files == 0 then
    log("  WARNING: No source files found")
    return {}
  end
  
  -- Questions per file
  local questions_per_file = math.ceil((repo.max_questions or 20) / #source_files)
  local total_questions = 0
  
  for _, file_path in ipairs(source_files) do
    local full_path = repo_path .. "/" .. file_path
    local questions = generate_questions_for_file(full_path, questions_per_file)
    
    for _, q in ipairs(questions) do
      if total_questions >= (repo.max_questions or 20) then break end
      
      local result = run_test_case_sync(repo_path, file_path, q.line, q.question, q.qtype)
      result.repo = repo_name
      result.lang = repo.lang
      result.size = repo.size
      table.insert(results, result)
      
      total_questions = total_questions + 1
      
      if result.error then
        log(string.format("  [%d] %s:%d - ERROR: %s",
          total_questions, file_path:sub(1, 30), q.line, result.error))
      else
        log(string.format("  [%d] %s:%d - %s, %s",
          total_questions,
          file_path:sub(1, 30),
          q.line,
          result.mode == "full_project" and "FULL" or "LSP",
          format_tokens(result.context_tokens)))
      end
    end
    
    if total_questions >= (repo.max_questions or 20) then break end
  end
  
  return results
end

-- =============================================================================
-- Report Generation
-- =============================================================================

local function generate_report(all_results)
  local lines = {}
  
  local function add(...)
    for _, line in ipairs({...}) do
      table.insert(lines, line)
    end
  end
  
  add("# ai-editutor User Experience Benchmark")
  add("")
  add("**Generated:** " .. os.date("%Y-%m-%d %H:%M:%S"))
  add("")
  add("This benchmark simulates **REAL user experience**:")
  add("- Opens actual source files in Neovim buffers")
  add("- Places cursor at various lines (spread throughout files)")
  add("- Asks diverse question types (concept, review, debug, howto, understand)")
  add("- Records what context would be sent to LLM")
  add("- Tests across 50 repositories, ~20 questions each")
  add("")
  
  -- Summary stats
  add("## Summary Statistics")
  add("")
  
  local total = #all_results
  local errors = 0
  local full_project = 0
  local lsp_selective = 0
  local within_budget = 0
  local total_tokens = 0
  local has_lsp_count = 0
  local total_external = 0
  
  for _, r in ipairs(all_results) do
    if r.error then
      errors = errors + 1
    else
      if r.mode == "full_project" then
        full_project = full_project + 1
      else
        lsp_selective = lsp_selective + 1
      end
      if r.within_budget then
        within_budget = within_budget + 1
      end
      if r.has_lsp then
        has_lsp_count = has_lsp_count + 1
      end
      total_tokens = total_tokens + (r.context_tokens or 0)
      total_external = total_external + (r.external_files or 0)
    end
  end
  
  local success = total - errors
  
  add("| Metric | Value |")
  add("|--------|-------|")
  add(string.format("| Total Test Cases | %d |", total))
  add(string.format("| Successful | %d (%.0f%%) |", success, 100 * success / math.max(1, total)))
  add(string.format("| Errors | %d |", errors))
  add(string.format("| **Full Project Mode** | %d (%.0f%%) |", full_project, 100 * full_project / math.max(1, success)))
  add(string.format("| **LSP Selective Mode** | %d (%.0f%%) |", lsp_selective, 100 * lsp_selective / math.max(1, success)))
  add(string.format("| Within Budget (20K) | %d (%.0f%%) |", within_budget, 100 * within_budget / math.max(1, success)))
  add(string.format("| Had LSP Available | %d (%.0f%%) |", has_lsp_count, 100 * has_lsp_count / math.max(1, success)))
  add(string.format("| **Avg Tokens per Query** | %s |", format_tokens(total_tokens / math.max(1, success))))
  add(string.format("| Avg External Files (LSP) | %.1f |", total_external / math.max(1, lsp_selective)))
  add("")
  
  -- By project size
  add("## Results by Project Size")
  add("")
  
  local by_size = { small = {}, medium = {}, large = {} }
  for _, r in ipairs(all_results) do
    if not r.error then
      local size = r.size or "unknown"
      if not by_size[size] then by_size[size] = {} end
      table.insert(by_size[size], r)
    end
  end
  
  add("| Size | Tests | Full Project | LSP Selective | Avg Tokens | Within Budget |")
  add("|------|-------|--------------|---------------|------------|---------------|")
  
  for _, size in ipairs({"small", "medium", "large"}) do
    local data = by_size[size] or {}
    local count = #data
    local full = 0
    local lsp = 0
    local tokens = 0
    local budget = 0
    
    for _, r in ipairs(data) do
      if r.mode == "full_project" then full = full + 1 else lsp = lsp + 1 end
      tokens = tokens + (r.context_tokens or 0)
      if r.within_budget then budget = budget + 1 end
    end
    
    add(string.format("| %s | %d | %d (%.0f%%) | %d (%.0f%%) | %s | %d (%.0f%%) |",
      size, count,
      full, count > 0 and 100 * full / count or 0,
      lsp, count > 0 and 100 * lsp / count or 0,
      format_tokens(count > 0 and tokens / count or 0),
      budget, count > 0 and 100 * budget / count or 0))
  end
  add("")
  
  -- By language
  add("## Results by Language")
  add("")
  
  local by_lang = {}
  for _, r in ipairs(all_results) do
    if not r.error then
      local lang = r.lang or "unknown"
      if not by_lang[lang] then
        by_lang[lang] = { count = 0, tokens = 0, full = 0, lsp = 0, budget = 0 }
      end
      by_lang[lang].count = by_lang[lang].count + 1
      by_lang[lang].tokens = by_lang[lang].tokens + (r.context_tokens or 0)
      if r.mode == "full_project" then
        by_lang[lang].full = by_lang[lang].full + 1
      else
        by_lang[lang].lsp = by_lang[lang].lsp + 1
      end
      if r.within_budget then
        by_lang[lang].budget = by_lang[lang].budget + 1
      end
    end
  end
  
  add("| Language | Tests | Full Project | LSP Selective | Avg Tokens | Within Budget |")
  add("|----------|-------|--------------|---------------|------------|---------------|")
  
  local langs = {}
  for lang in pairs(by_lang) do table.insert(langs, lang) end
  table.sort(langs)
  
  for _, lang in ipairs(langs) do
    local data = by_lang[lang]
    add(string.format("| %s | %d | %d | %d | %s | %d (%.0f%%) |",
      lang, data.count, data.full, data.lsp,
      format_tokens(data.tokens / data.count),
      data.budget, 100 * data.budget / data.count))
  end
  add("")
  
  -- By question type
  add("## Results by Question Type")
  add("")
  
  local by_qtype = {}
  for _, r in ipairs(all_results) do
    if not r.error then
      local qtype = r.qtype or "unknown"
      if not by_qtype[qtype] then
        by_qtype[qtype] = { count = 0, tokens = 0 }
      end
      by_qtype[qtype].count = by_qtype[qtype].count + 1
      by_qtype[qtype].tokens = by_qtype[qtype].tokens + (r.context_tokens or 0)
    end
  end
  
  add("| Question Type | Tests | Avg Tokens |")
  add("|---------------|-------|------------|")
  
  for _, qtype in ipairs({"concept", "review", "debug", "howto", "understand"}) do
    local data = by_qtype[qtype]
    if data then
      add(string.format("| %s | %d | %s |",
        qtype, data.count, format_tokens(data.tokens / data.count)))
    end
  end
  add("")
  
  -- Sample context previews
  add("## Sample Context Previews")
  add("")
  add("Examples showing what would be sent to LLM:")
  add("")
  
  local preview_count = 0
  local shown_modes = { full_project = false, lsp_selective = false }
  
  for _, r in ipairs(all_results) do
    if not r.error and r.context_preview and #r.context_preview > 200 then
      if not shown_modes[r.mode] then
        shown_modes[r.mode] = true
        
        add("### " .. (r.mode == "full_project" and "Full Project Mode Example" or "LSP Selective Mode Example"))
        add("")
        add("**Repo:** " .. r.repo .. " | **File:** " .. r.file .. " | **Line:** " .. r.line)
        add("")
        add("**Question:** " .. r.question .. " (" .. r.qtype .. ")")
        add("")
        add("**Tokens:** " .. format_tokens(r.context_tokens) .. " | **External Files:** " .. r.external_files)
        add("")
        add("```")
        add(r.context_preview:sub(1, 2000) .. (r.context_preview:len() > 2000 and "\n..." or ""))
        add("```")
        add("")
        
        preview_count = preview_count + 1
        if preview_count >= 2 then break end
      end
    end
  end
  
  -- Issues summary
  add("## Issues Found")
  add("")
  
  local issue_counts = {
    errors = 0,
    over_budget = 0,
    no_lsp = 0,
  }
  
  for _, r in ipairs(all_results) do
    if r.error then
      issue_counts.errors = issue_counts.errors + 1
    elseif not r.within_budget then
      issue_counts.over_budget = issue_counts.over_budget + 1
    elseif r.mode == "lsp_selective" and (r.external_files or 0) == 0 and not r.has_lsp then
      issue_counts.no_lsp = issue_counts.no_lsp + 1
    end
  end
  
  add("| Issue | Count |")
  add("|-------|-------|")
  add(string.format("| Errors (file not found, etc.) | %d |", issue_counts.errors))
  add(string.format("| Over Token Budget | %d |", issue_counts.over_budget))
  add(string.format("| No LSP (limited context) | %d |", issue_counts.no_lsp))
  add("")
  
  -- Per-repo summary
  add("## Per-Repository Summary")
  add("")
  add("| Repository | Lang | Size | Tests | Mode | Avg Tokens | Budget |")
  add("|------------|------|------|-------|------|------------|--------|")
  
  local by_repo = {}
  for _, r in ipairs(all_results) do
    local key = r.repo or "unknown"
    if not by_repo[key] then
      by_repo[key] = { lang = r.lang, size = r.size, tests = 0, full = 0, tokens = 0, budget = 0, errors = 0 }
    end
    by_repo[key].tests = by_repo[key].tests + 1
    if r.error then
      by_repo[key].errors = by_repo[key].errors + 1
    else
      if r.mode == "full_project" then by_repo[key].full = by_repo[key].full + 1 end
      by_repo[key].tokens = by_repo[key].tokens + (r.context_tokens or 0)
      if r.within_budget then by_repo[key].budget = by_repo[key].budget + 1 end
    end
  end
  
  local repos = {}
  for repo in pairs(by_repo) do table.insert(repos, repo) end
  table.sort(repos)
  
  for _, repo in ipairs(repos) do
    local data = by_repo[repo]
    local success = data.tests - data.errors
    local mode = data.full > success / 2 and "FULL" or "LSP"
    add(string.format("| %s | %s | %s | %d | %s | %s | %d/%d |",
      repo:sub(1, 20),
      data.lang or "?",
      data.size or "?",
      data.tests,
      mode,
      format_tokens(success > 0 and data.tokens / success or 0),
      data.budget, success))
  end
  add("")
  
  return table.concat(lines, "\n")
end

-- =============================================================================
-- Main Entry Point
-- =============================================================================

function M.run()
  math.randomseed(os.time())
  
  log("=== ai-editutor User Experience Benchmark ===")
  log("")
  
  -- Create directories
  ensure_dir(M.CONFIG.clone_dir)
  ensure_dir(M.CONFIG.output_dir)
  
  local all_results = {}
  
  log(string.format("Testing %d repositories with ~20 questions each...", #M.TEST_REPOS))
  log("")
  
  for i, repo in ipairs(M.TEST_REPOS) do
    log(string.format("[%d/%d] %s", i, #M.TEST_REPOS, get_repo_name(repo.url)))
    
    local results = run_repo_tests(repo)
    for _, r in ipairs(results) do
      table.insert(all_results, r)
    end
    
    log("")
  end
  
  log("Generating report...")
  
  local report = generate_report(all_results)
  local report_path = M.CONFIG.output_dir .. "/USER_EXPERIENCE_BENCHMARK.md"
  
  local file = io.open(report_path, "w")
  if file then
    file:write(report)
    file:close()
    log("Report written to: " .. report_path)
  else
    log("ERROR: Could not write report")
  end
  
  log("")
  log(string.format("=== Complete: %d tests across %d repos ===", #all_results, #M.TEST_REPOS))
end

---Quick test with fewer repos
function M.quick_test()
  M.TEST_REPOS = vim.list_slice(M.TEST_REPOS, 1, 5)
  for _, repo in ipairs(M.TEST_REPOS) do
    repo.max_questions = 5
  end
  M.run()
end

return M
