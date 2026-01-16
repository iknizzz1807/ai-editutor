-- benchmark.lua
-- Benchmark script to test project_scanner on 50 diverse GitHub repos
-- Usage: nvim --headless -u tests/minimal_init.lua -c "lua require('tests.benchmark').run()" -c "qa"

local M = {}

-- =============================================================================
-- Repository List - 50 Diverse Repos
-- =============================================================================
-- Categories: JavaScript/TypeScript, Python, Rust, Go, Java, C/C++, Ruby, PHP
-- Sizes: Small (<5k tokens), Medium (5k-20k), Large (>20k expected)
-- Frameworks: React, Vue, Angular, Django, FastAPI, Spring, Express, etc.

M.REPOS = {
  -- JavaScript/TypeScript - Small
  { url = "https://github.com/jonschlinkert/is-odd", lang = "JavaScript", size = "small", desc = "Check if number is odd" },
  { url = "https://github.com/minimistjs/minimist", lang = "JavaScript", size = "small", desc = "Argument parser" },
  { url = "https://github.com/ai/nanoid", lang = "JavaScript", size = "medium", desc = "Unique ID generator" },
  { url = "https://github.com/lukeed/clsx", lang = "JavaScript", size = "small", desc = "Classname utility" },
  { url = "https://github.com/jorgebucaran/hyperapp", lang = "JavaScript", size = "medium", desc = "Tiny framework" },

  -- JavaScript/TypeScript - Medium
  { url = "https://github.com/expressjs/express", lang = "JavaScript", size = "medium", desc = "Web framework" },
  { url = "https://github.com/koa-js/koa", lang = "JavaScript", size = "medium", desc = "Web framework" },
  { url = "https://github.com/chalk/chalk", lang = "JavaScript", size = "medium", desc = "Terminal colors" },
  { url = "https://github.com/date-fns/date-fns", lang = "TypeScript", size = "large", desc = "Date utility" },
  { url = "https://github.com/jaredpalmer/formik", lang = "TypeScript", size = "medium", desc = "React forms" },

  -- JavaScript/TypeScript - Large
  { url = "https://github.com/vuejs/core", lang = "TypeScript", size = "large", desc = "Vue.js core" },
  { url = "https://github.com/angular/angular", lang = "TypeScript", size = "large", desc = "Angular framework" },
  { url = "https://github.com/facebook/react", lang = "JavaScript", size = "large", desc = "React framework" },
  { url = "https://github.com/nestjs/nest", lang = "TypeScript", size = "large", desc = "Node.js framework" },
  { url = "https://github.com/prisma/prisma", lang = "TypeScript", size = "large", desc = "ORM" },

  -- Python - Small
  { url = "https://github.com/psf/black", lang = "Python", size = "medium", desc = "Code formatter" },
  { url = "https://github.com/python-poetry/poetry", lang = "Python", size = "medium", desc = "Dependency manager" },
  { url = "https://github.com/pallets/click", lang = "Python", size = "medium", desc = "CLI framework" },
  { url = "https://github.com/httpie/cli", lang = "Python", size = "medium", desc = "HTTP client" },
  { url = "https://github.com/tqdm/tqdm", lang = "Python", size = "small", desc = "Progress bar" },

  -- Python - Large
  { url = "https://github.com/django/django", lang = "Python", size = "large", desc = "Web framework" },
  { url = "https://github.com/tiangolo/fastapi", lang = "Python", size = "medium", desc = "API framework" },
  { url = "https://github.com/pallets/flask", lang = "Python", size = "medium", desc = "Web framework" },
  { url = "https://github.com/scrapy/scrapy", lang = "Python", size = "large", desc = "Web scraping" },
  { url = "https://github.com/pytorch/pytorch", lang = "Python", size = "large", desc = "ML framework" },

  -- Rust
  { url = "https://github.com/BurntSushi/ripgrep", lang = "Rust", size = "medium", desc = "Search tool" },
  { url = "https://github.com/sharkdp/fd", lang = "Rust", size = "medium", desc = "Find alternative" },
  { url = "https://github.com/sharkdp/bat", lang = "Rust", size = "medium", desc = "Cat alternative" },
  { url = "https://github.com/starship/starship", lang = "Rust", size = "medium", desc = "Shell prompt" },
  { url = "https://github.com/alacritty/alacritty", lang = "Rust", size = "medium", desc = "Terminal" },

  -- Go
  { url = "https://github.com/gin-gonic/gin", lang = "Go", size = "medium", desc = "Web framework" },
  { url = "https://github.com/gofiber/fiber", lang = "Go", size = "medium", desc = "Web framework" },
  { url = "https://github.com/junegunn/fzf", lang = "Go", size = "medium", desc = "Fuzzy finder" },
  { url = "https://github.com/jesseduffield/lazygit", lang = "Go", size = "medium", desc = "Git TUI" },
  { url = "https://github.com/charmbracelet/bubbletea", lang = "Go", size = "medium", desc = "TUI framework" },

  -- Java/Kotlin
  { url = "https://github.com/spring-projects/spring-petclinic", lang = "Java", size = "small", desc = "Sample app" },
  { url = "https://github.com/google/guava", lang = "Java", size = "large", desc = "Core libraries" },
  { url = "https://github.com/square/okhttp", lang = "Kotlin", size = "medium", desc = "HTTP client" },
  { url = "https://github.com/square/retrofit", lang = "Java", size = "medium", desc = "HTTP client" },
  { url = "https://github.com/JetBrains/kotlin", lang = "Kotlin", size = "large", desc = "Kotlin compiler" },

  -- C/C++
  { url = "https://github.com/jqlang/jq", lang = "C", size = "medium", desc = "JSON processor" },
  { url = "https://github.com/redis/redis", lang = "C", size = "large", desc = "Database" },
  { url = "https://github.com/curl/curl", lang = "C", size = "large", desc = "HTTP client" },
  { url = "https://github.com/nlohmann/json", lang = "C++", size = "medium", desc = "JSON library" },
  { url = "https://github.com/gabime/spdlog", lang = "C++", size = "medium", desc = "Logging" },

  -- Ruby
  { url = "https://github.com/rails/rails", lang = "Ruby", size = "large", desc = "Web framework" },
  { url = "https://github.com/jekyll/jekyll", lang = "Ruby", size = "medium", desc = "Static site" },
  { url = "https://github.com/Homebrew/brew", lang = "Ruby", size = "medium", desc = "Package manager" },

  -- PHP
  { url = "https://github.com/laravel/laravel", lang = "PHP", size = "small", desc = "Framework skeleton" },
  { url = "https://github.com/laravel/framework", lang = "PHP", size = "large", desc = "Framework core" },

  -- Lua
  { url = "https://github.com/folke/lazy.nvim", lang = "Lua", size = "medium", desc = "Plugin manager" },
  { url = "https://github.com/nvim-lua/plenary.nvim", lang = "Lua", size = "medium", desc = "Lua utilities" },
}

-- =============================================================================
-- Configuration
-- =============================================================================

M.CONFIG = {
  clone_dir = "/tmp/editutor-benchmark-repos",
  output_file = "tests/BENCHMARK_RESULTS.md",
  token_budget = 20000,
  shallow_clone = true,  -- --depth 1 for faster cloning
  max_repos = nil,       -- nil = all, or set number for testing
}

-- =============================================================================
-- Utilities
-- =============================================================================

local function log(msg)
  print(string.format("[%s] %s", os.date("%H:%M:%S"), msg))
end

local function shell(cmd)
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then return nil, "Failed to execute command" end
  local result = handle:read("*a")
  local ok = handle:close()
  return result, ok
end

local function format_number(n)
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 1000 then
    return string.format("%.1fK", n / 1000)
  else
    return tostring(n)
  end
end

local function get_repo_name(url)
  return url:match("([^/]+)$")
end

-- =============================================================================
-- Clone Repository
-- =============================================================================

local function clone_repo(repo)
  local name = get_repo_name(repo.url)
  local target = M.CONFIG.clone_dir .. "/" .. name

  -- Skip if already exists
  if vim.fn.isdirectory(target) == 1 then
    log("  Skipping clone (exists): " .. name)
    return target, true
  end

  local depth_flag = M.CONFIG.shallow_clone and "--depth 1" or ""
  local cmd = string.format("git clone %s %s %s", depth_flag, repo.url, target)

  log("  Cloning: " .. name)
  local _, ok = shell(cmd)

  if vim.fn.isdirectory(target) == 1 then
    return target, true
  else
    return nil, false
  end
end

-- =============================================================================
-- Run Scanner
-- =============================================================================

local function run_scanner(repo_path)
  local scanner = require("editutor.project_scanner")

  local start_time = vim.loop.hrtime()
  local result = scanner.scan_project({ root = repo_path })
  local scan_time = (vim.loop.hrtime() - start_time) / 1000000 -- ms

  -- Get content stats
  start_time = vim.loop.hrtime()
  local content, metadata = scanner.read_all_sources(result)
  local read_time = (vim.loop.hrtime() - start_time) / 1000000 -- ms

  -- Determine mode
  local mode = metadata.total_tokens <= M.CONFIG.token_budget and "full_project" or "lsp_selective"

  return {
    scan_time_ms = scan_time,
    read_time_ms = read_time,
    total_files = #result.files,
    total_folders = #result.folders,
    total_lines = metadata.total_lines,
    total_tokens = metadata.total_tokens,
    tree_structure = result.tree_structure,
    mode = mode,
    files_by_type = {
      source = 0,
      config = 0,
    },
    extensions = {},
  }
end

-- =============================================================================
-- Analyze Results
-- =============================================================================

local function count_stats(result, files)
  for _, file in ipairs(files) do
    if file.type == "source" then
      result.files_by_type.source = result.files_by_type.source + 1
    elseif file.type == "config" then
      result.files_by_type.config = result.files_by_type.config + 1
    end

    local ext = file.name:match("%.([^.]+)$") or "no_ext"
    result.extensions[ext] = (result.extensions[ext] or 0) + 1
  end
end

-- =============================================================================
-- Generate Report
-- =============================================================================

local function generate_report(results)
  local lines = {}

  local function add(...)
    for _, line in ipairs({...}) do
      table.insert(lines, line)
    end
  end

  add("# ai-editutor Benchmark Results")
  add("")
  add("Generated: " .. os.date("%Y-%m-%d %H:%M:%S"))
  add("")
  add("Token Budget: " .. format_number(M.CONFIG.token_budget))
  add("")

  -- Summary statistics
  add("## Summary Statistics")
  add("")

  local total_repos = #results
  local full_project_count = 0
  local lsp_selective_count = 0
  local failed_count = 0

  local total_files = 0
  local total_lines = 0
  local total_tokens = 0

  local by_lang = {}
  local by_size = { small = {}, medium = {}, large = {} }

  for _, r in ipairs(results) do
    if r.error then
      failed_count = failed_count + 1
    else
      if r.stats.mode == "full_project" then
        full_project_count = full_project_count + 1
      else
        lsp_selective_count = lsp_selective_count + 1
      end

      total_files = total_files + r.stats.total_files
      total_lines = total_lines + r.stats.total_lines
      total_tokens = total_tokens + r.stats.total_tokens

      -- By language
      local lang = r.repo.lang
      if not by_lang[lang] then
        by_lang[lang] = { count = 0, tokens = 0, full = 0, lsp = 0 }
      end
      by_lang[lang].count = by_lang[lang].count + 1
      by_lang[lang].tokens = by_lang[lang].tokens + r.stats.total_tokens
      if r.stats.mode == "full_project" then
        by_lang[lang].full = by_lang[lang].full + 1
      else
        by_lang[lang].lsp = by_lang[lang].lsp + 1
      end

      -- By expected size
      table.insert(by_size[r.repo.size], r)
    end
  end

  add("| Metric | Value |")
  add("|--------|-------|")
  add(string.format("| Total Repos | %d |", total_repos))
  add(string.format("| Successful | %d |", total_repos - failed_count))
  add(string.format("| Failed | %d |", failed_count))
  add(string.format("| Full Project Mode | %d (%.0f%%) |", full_project_count, 100 * full_project_count / (total_repos - failed_count)))
  add(string.format("| LSP Selective Mode | %d (%.0f%%) |", lsp_selective_count, 100 * lsp_selective_count / (total_repos - failed_count)))
  add("")

  -- Mode distribution by expected size
  add("### Mode Distribution by Expected Size")
  add("")
  add("| Expected Size | Repos | Full Project | LSP Selective |")
  add("|---------------|-------|--------------|---------------|")

  for _, size in ipairs({"small", "medium", "large"}) do
    local repos = by_size[size]
    local full = 0
    local lsp = 0
    for _, r in ipairs(repos) do
      if not r.error then
        if r.stats.mode == "full_project" then
          full = full + 1
        else
          lsp = lsp + 1
        end
      end
    end
    add(string.format("| %s | %d | %d | %d |", size, #repos, full, lsp))
  end
  add("")

  -- By language
  add("### By Language")
  add("")
  add("| Language | Repos | Avg Tokens | Full Project | LSP Selective |")
  add("|----------|-------|------------|--------------|---------------|")

  local langs_sorted = {}
  for lang, _ in pairs(by_lang) do
    table.insert(langs_sorted, lang)
  end
  table.sort(langs_sorted)

  for _, lang in ipairs(langs_sorted) do
    local data = by_lang[lang]
    local avg_tokens = data.tokens / data.count
    add(string.format("| %s | %d | %s | %d | %d |",
      lang, data.count, format_number(avg_tokens), data.full, data.lsp))
  end
  add("")

  -- Detailed results
  add("## Detailed Results")
  add("")
  add("| # | Repository | Lang | Expected | Mode | Files | Lines | Tokens | Time |")
  add("|---|------------|------|----------|------|-------|-------|--------|------|")

  for i, r in ipairs(results) do
    if r.error then
      add(string.format("| %d | %s | %s | %s | ERROR | - | - | - | - |",
        i, r.repo_name, r.repo.lang, r.repo.size))
    else
      local time_str = string.format("%.0fms", r.stats.scan_time_ms + r.stats.read_time_ms)
      add(string.format("| %d | %s | %s | %s | %s | %d | %s | %s | %s |",
        i,
        r.repo_name,
        r.repo.lang,
        r.repo.size,
        r.stats.mode == "full_project" and "FULL" or "LSP",
        r.stats.total_files,
        format_number(r.stats.total_lines),
        format_number(r.stats.total_tokens),
        time_str))
    end
  end
  add("")

  -- Sample tree structures
  add("## Sample Tree Structures")
  add("")

  -- Show 3 examples: one small (full), one medium, one large (lsp)
  local examples = {
    { title = "Small Project (Full Project Mode)", size = "small", mode = "full_project" },
    { title = "Medium Project", size = "medium", mode = nil },
    { title = "Large Project (LSP Selective Mode)", size = "large", mode = "lsp_selective" },
  }

  for _, ex in ipairs(examples) do
    local found = nil
    for _, r in ipairs(results) do
      if not r.error and r.repo.size == ex.size then
        if ex.mode == nil or r.stats.mode == ex.mode then
          found = r
          break
        end
      end
    end

    if found then
      add("### " .. ex.title .. ": " .. found.repo_name)
      add("")
      add("- **Files:** " .. found.stats.total_files)
      add("- **Lines:** " .. format_number(found.stats.total_lines))
      add("- **Tokens:** " .. format_number(found.stats.total_tokens))
      add("- **Mode:** " .. found.stats.mode)
      add("")
      add("```")
      -- Truncate tree if too long
      local tree_lines = vim.split(found.stats.tree_structure, "\n")
      if #tree_lines > 50 then
        for i = 1, 50 do
          add(tree_lines[i])
        end
        add("... (" .. (#tree_lines - 50) .. " more lines)")
      else
        add(found.stats.tree_structure)
      end
      add("```")
      add("")
    end
  end

  -- Top tokens consumers
  add("## Top 10 by Token Count")
  add("")

  local sorted_by_tokens = {}
  for _, r in ipairs(results) do
    if not r.error then
      table.insert(sorted_by_tokens, r)
    end
  end
  table.sort(sorted_by_tokens, function(a, b)
    return a.stats.total_tokens > b.stats.total_tokens
  end)

  add("| # | Repository | Tokens | Files | Mode |")
  add("|---|------------|--------|-------|------|")
  for i = 1, math.min(10, #sorted_by_tokens) do
    local r = sorted_by_tokens[i]
    add(string.format("| %d | %s | %s | %d | %s |",
      i, r.repo_name, format_number(r.stats.total_tokens), r.stats.total_files, r.stats.mode))
  end
  add("")

  -- Smallest tokens (full project candidates)
  add("## Top 10 Smallest (Best Full Project Candidates)")
  add("")

  table.sort(sorted_by_tokens, function(a, b)
    return a.stats.total_tokens < b.stats.total_tokens
  end)

  add("| # | Repository | Tokens | Files | Mode |")
  add("|---|------------|--------|-------|------|")
  for i = 1, math.min(10, #sorted_by_tokens) do
    local r = sorted_by_tokens[i]
    add(string.format("| %d | %s | %s | %d | %s |",
      i, r.repo_name, format_number(r.stats.total_tokens), r.stats.total_files, r.stats.mode))
  end
  add("")

  -- File extension distribution
  add("## File Extension Distribution")
  add("")

  local all_extensions = {}
  for _, r in ipairs(results) do
    if not r.error and r.stats.extensions then
      for ext, count in pairs(r.stats.extensions) do
        all_extensions[ext] = (all_extensions[ext] or 0) + count
      end
    end
  end

  local ext_list = {}
  for ext, count in pairs(all_extensions) do
    table.insert(ext_list, { ext = ext, count = count })
  end
  table.sort(ext_list, function(a, b) return a.count > b.count end)

  add("| Extension | Count |")
  add("|-----------|-------|")
  for i = 1, math.min(20, #ext_list) do
    add(string.format("| .%s | %d |", ext_list[i].ext, ext_list[i].count))
  end
  add("")

  return table.concat(lines, "\n")
end

-- =============================================================================
-- Main Run Function
-- =============================================================================

function M.run()
  log("=== ai-editutor Benchmark ===")
  log("")

  -- Create clone directory
  shell("mkdir -p " .. M.CONFIG.clone_dir)

  local repos = M.REPOS
  if M.CONFIG.max_repos then
    repos = vim.list_slice(repos, 1, M.CONFIG.max_repos)
  end

  log(string.format("Testing %d repositories...", #repos))
  log("")

  local results = {}

  for i, repo in ipairs(repos) do
    local repo_name = get_repo_name(repo.url)
    log(string.format("[%d/%d] Processing: %s (%s)", i, #repos, repo_name, repo.lang))

    local result = {
      repo = repo,
      repo_name = repo_name,
      error = nil,
      stats = nil,
    }

    -- Clone
    local repo_path, clone_ok = clone_repo(repo)
    if not clone_ok then
      result.error = "Clone failed"
      log("  ERROR: Clone failed")
    else
      -- Scan
      local ok, stats = pcall(function()
        local scanner = require("editutor.project_scanner")
        local scan_result = scanner.scan_project({ root = repo_path })
        local content, metadata = scanner.read_all_sources(scan_result)

        local mode = metadata.total_tokens <= M.CONFIG.token_budget and "full_project" or "lsp_selective"

        return {
          scan_time_ms = 0,
          read_time_ms = 0,
          total_files = #scan_result.files,
          total_folders = #scan_result.folders,
          total_lines = metadata.total_lines,
          total_tokens = metadata.total_tokens,
          tree_structure = scan_result.tree_structure,
          mode = mode,
          files_by_type = { source = 0, config = 0 },
          extensions = {},
        }
      end)

      if ok then
        result.stats = stats
        log(string.format("  Files: %d, Tokens: %s, Mode: %s",
          stats.total_files, format_number(stats.total_tokens), stats.mode))
      else
        result.error = tostring(stats)
        log("  ERROR: " .. result.error)
      end
    end

    table.insert(results, result)
  end

  log("")
  log("Generating report...")

  local report = generate_report(results)

  -- Write report
  local output_path = vim.fn.getcwd() .. "/" .. M.CONFIG.output_file
  local file = io.open(output_path, "w")
  if file then
    file:write(report)
    file:close()
    log("Report written to: " .. M.CONFIG.output_file)
  else
    log("ERROR: Could not write report to " .. output_path)
    print(report)
  end

  log("")
  log("=== Benchmark Complete ===")
end

-- =============================================================================
-- Quick Test (5 repos)
-- =============================================================================

function M.quick_test()
  M.CONFIG.max_repos = 5
  M.run()
end

return M
