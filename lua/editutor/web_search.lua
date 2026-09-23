-- editutor/web_search.lua
-- Native AI Web Research & Deep Context Assistant for ai-editutor
-- Powered by Brave Search API + StackExchange REST API + Jina Reader / w3m fallback + Smart Knapsack Chunker + Local Ollama / LLM Provider

local M = {}

local config = require("editutor.config")
local debug_log = require("editutor.debug_log")
local knowledge = require("editutor.knowledge")
local project_scanner = require("editutor.project_scanner")

local state = {
  buf = nil,
  win = nil,
  messages = {},
  is_streaming = false,
  current_job = nil,
  active_code_buf = nil,
  active_filetype = "text",
  active_filepath = "",
}

-- =============================================================================
-- Helpers: Text & URL Processing & Sanitization
-- =============================================================================

---Decode HTML entities and strip XML/HTML tags
---@param text string
---@return string
local function clean_html_entities(text)
  if not text then
    return ""
  end
  local clean = text
    :gsub("<[^>]+>", "")
    :gsub("&quot;", '"')
    :gsub("&apos;", "'")
    :gsub("&#x27;", "'")
    :gsub("&#39;", "'")
    :gsub("&amp;", "&")
    :gsub("&lt;", "<")
    :gsub("&gt;", ">")
    :gsub("&nbsp;", " ")
    :gsub("%s+", " ")
  return clean
end

---Strip web scrapers noise: images, badges, skip-links, cookie notices
---@param text string Raw scraped markdown
---@return string Cleaned markdown
local function clean_scraped_markdown(text)
  if not text or text == "" then
    return ""
  end
  local clean = text
  -- 1. Remove nested markdown image links: [![alt](img_url)](target_url)
  clean = clean:gsub("%[!%b[]%b()%]%b()", "")
  -- 2. Remove standard markdown images: ![alt](url)
  clean = clean:gsub("!%b[]%b()", "")
  -- 3. Remove empty links: [ ](url) or [](url)
  clean = clean:gsub("%[%s*%]%b()", "")
  -- 4. Remove badge links (shields.io, github workflows, etc.)
  clean = clean:gsub("%b[](https?://img%.shields%.io/[^%)]+)%b()", "")
  clean = clean:gsub("%b[](https?://github%.com/[%w_%.-]+/[%w_%.-]+/workflows/[^%)]+)%b()", "")
  -- 5. Remove skip navigation anchors and common UI buttons
  clean = clean:gsub("%[[Ss]kip to [^%]]+%]%b()", "")
  clean = clean:gsub("%[[Jj]ump to [^%]]+%]%b()", "")
  clean = clean:gsub("%[[Nn]avigation%]%b()", "")
  clean = clean:gsub("%[[Ss]ign [Ii]n%]%b()", "")
  clean = clean:gsub("%[[Ll]og [Ii]n%]%b()", "")
  clean = clean:gsub("%[[Cc]lose [Mm]odal%]%b()", "")
  clean = clean:gsub("%[[Mm]enu%]%b()", "")
  -- 6. Strip cookie, license, terms, and social share noise lines
  clean = clean:gsub("\n%s*[Ss]hare on [^\n]+", "")
  clean = clean:gsub("\n%s*[Aa]ll rights reserved[^\n]*", "")
  clean = clean:gsub("\n%s*[Cc]ookie [Pp]olicy[^\n]*", "")
  clean = clean:gsub("\n%s*[Pp]rivacy [Pp]olicy[^\n]*", "")
  clean = clean:gsub("\n%s*[Tt]erms of [Ss]ervice[^\n]*", "")
  -- 7. Collapse 3+ consecutive newlines to 2
  clean = clean:gsub("\n\n\n+", "\n\n")
  return clean
end

---Convert StackOverflow HTML answer body to clean Markdown
---@param html_str string
---@return string
local function stackoverflow_html_to_md(html_str)
  if not html_str or html_str == "" then
    return ""
  end
  local text = html_str
  -- 1. Code blocks: <pre><code>...</code></pre>
  text = text:gsub("<pre><code>(.-)</code></pre>", function(code)
    return "\n```\n" .. clean_html_entities(code) .. "\n```\n"
  end)
  -- 2. Inline code: <code>...</code>
  text = text:gsub("<code>(.-)</code>", function(c)
    return "`" .. clean_html_entities(c) .. "`"
  end)
  -- 3. Blockquotes
  text = text:gsub("<blockquote>(.-)</blockquote>", function(q)
    return "\n> " .. q:gsub("\n", "\n> ") .. "\n"
  end)
  -- 4. Paragraphs and breaks
  text = text:gsub("</p>", "\n\n"):gsub("<br%s*/?>", "\n"):gsub("<hr%s*/?>", "\n---\n")
  -- 5. Links
  text = text:gsub('<a%s+href=[\"\'](.-)[\"\'][^>]*>(.-)</a>', "[%2](%1)")
  -- 6. Formatting
  text = text:gsub("<strong>(.-)</strong>", "**%1**"):gsub("<b>(.-)</b>", "**%1**")
  text = text:gsub("<em>(.-)</em>", "*%1*"):gsub("<i>(.-)</i>", "*%1*")
  -- 7. Clean all remaining HTML tags & decode entities
  text = clean_html_entities(text)
  return vim.trim(text)
end

---Get visual selection from current buffer
---@return string
local function get_visual_selection()
  local orig_reg = vim.fn.getreg("z")
  local orig_regtype = vim.fn.getregtype("z")
  vim.cmd('normal! "zy')
  local sel = vim.fn.getreg("z")
  vim.fn.setreg("z", orig_reg, orig_regtype)
  return vim.trim(sel or "")
end

---Get target query from selection or word under cursor
---@return string
local function get_target_query()
  local mode = vim.api.nvim_get_mode().mode
  if mode:match("^[vV\22]") then
    local sel = get_visual_selection()
    if #sel > 0 then
      return sel
    end
  end
  return vim.fn.expand("<cword>")
end

---Get context surrounding cursor in buffer
---@param buf number
---@return string content
---@return string filetype
---@return string filepath
local function get_buffer_context(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return "", "text", ""
  end
  local filepath = vim.api.nvim_buf_get_name(buf)
  local filetype = vim.bo[buf].filetype
  if not filetype or filetype == "" then
    filetype = "text"
  end

  local total_lines = vim.api.nvim_buf_line_count(buf)
  local cur_win = vim.fn.bufwinid(buf)
  local cur_line = 1
  if cur_win ~= -1 then
    local pos = vim.api.nvim_win_get_cursor(cur_win)
    cur_line = pos[1]
  end

  -- Extract up to 100 lines before and 100 lines after cursor (~200 lines total)
  local start_line = math.max(0, cur_line - 100)
  local end_line = math.min(total_lines, cur_line + 100)
  local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)

  return table.concat(lines, "\n"), filetype, filepath
end

-- =============================================================================
-- Smart Heading-based Knapsack Chunker
-- =============================================================================

---Pack scraped markdown into token budget using heading scoring and Section 1 capping
---@param markdown_text string
---@param query string
---@param max_chars? number
---@return string
local function smart_knapsack_pack(markdown_text, query, max_chars)
  local ws_config = (config.options and config.options.web_search) or {}
  max_chars = max_chars or ws_config.knapsack_max_chars or 36000
  local section1_cap_pct = ws_config.section1_cap_pct or 0.35

  if not markdown_text then
    return ""
  end
  markdown_text = clean_scraped_markdown(markdown_text)
  if #markdown_text <= max_chars then
    return markdown_text
  end

  -- Tokenize query terms for scoring
  local query_terms = {}
  for w in query:lower():gmatch("%w+") do
    if #w > 2 then
      table.insert(query_terms, w)
    end
  end

  -- Split by markdown headings (#, ##, ###) while not inside code blocks
  local lines = vim.split(markdown_text, "\n", { plain = true })
  local sections = {}
  local current_sec = { heading = "", lines = {}, line_idx = 0 }
  local in_code_block = false

  for idx, line in ipairs(lines) do
    if line:match("^%s*```") then
      in_code_block = not in_code_block
    end

    local is_heading = not in_code_block and line:match("^#{1,4}%s+")
    if is_heading and (#current_sec.lines > 0 or current_sec.heading ~= "") then
      table.insert(sections, current_sec)
      current_sec = { heading = line, lines = {}, line_idx = idx }
    else
      if current_sec.heading == "" and is_heading then
        current_sec.heading = line
        current_sec.line_idx = idx
      else
        table.insert(current_sec.lines, line)
      end
    end
  end

  if #current_sec.lines > 0 or current_sec.heading ~= "" then
    table.insert(sections, current_sec)
  end

  -- Fallback if no headings found: split by double newline
  if #sections <= 1 then
    local blocks = vim.split(markdown_text, "\n\n", { plain = true })
    sections = {}
    for i, b in ipairs(blocks) do
      table.insert(sections, { heading = "Block " .. i, lines = { b }, line_idx = i })
    end
  end

  local high_value_keywords = {
    "example", "usage", "how to", "solution", "fix", "syntax",
    "parameters", "overview", "code", "implementation", "benchmarks", "api"
  }

  -- Score each section
  for _, sec in ipairs(sections) do
    local content = sec.heading .. "\n" .. table.concat(sec.lines, "\n")
    sec.content = content
    sec.char_count = #content
    local lower_content = content:lower()

    local score = 1.0

    -- 1. Query keyword matches (+8 pts per match)
    for _, term in ipairs(query_terms) do
      local _, count = lower_content:gsub(vim.pesc(term), "")
      score = score + (count * 8.0)
    end

    -- 2. Code blocks presence (+15 pts per code block)
    local _, fence_count = content:gsub("```", "")
    local code_blocks = math.floor(fence_count / 2)
    score = score + (code_blocks * 15.0)

    -- 3. High-value heading (+12 pts)
    local lower_heading = sec.heading:lower()
    for _, hvk in ipairs(high_value_keywords) do
      if lower_heading:match(vim.pesc(hvk)) then
        score = score + 12.0
      end
    end

    -- 4. Spam penalty
    if lower_content:match("share on twitter") or lower_content:match("cookie policy") or lower_content:match("all rights reserved") then
      score = score - 20.0
    end

    sec.score = score
  end

  -- Pre-cap individual sections so neither section 1 nor huge fallback blocks exceed budget
  for idx, sec in ipairs(sections) do
    local cap = max_chars
    if #sections > 1 and idx == 1 then
      cap = math.min(max_chars, math.floor(max_chars * section1_cap_pct))
    end
    if sec.char_count > cap then
      sec.content = sec.content:sub(1, cap) .. "\n\n[... content truncated for brevity ...]\n"
      sec.char_count = #sec.content
    end
  end

  -- Knapsack Selection: Always keep Section 1 (Title / Overview)
  local selected_indices = {}
  local used_chars = 0

  if #sections > 0 then
    selected_indices[1] = true
    used_chars = used_chars + sections[1].char_count
  end

  -- Sort remaining sections by score descending
  local remaining = {}
  for i = 2, #sections do
    table.insert(remaining, { idx = i, sec = sections[i] })
  end
  table.sort(remaining, function(a, b)
    return a.sec.score > b.sec.score
  end)

  for _, item in ipairs(remaining) do
    if used_chars + item.sec.char_count <= max_chars then
      selected_indices[item.idx] = true
      used_chars = used_chars + item.sec.char_count
    end
  end

  -- Reconstruct document preserving original chronological document order
  local packed_sections = {}
  local prev_idx = -1

  for idx = 1, #sections do
    if selected_indices[idx] then
      if prev_idx ~= -1 and idx > prev_idx + 1 then
        table.insert(packed_sections, "\n\n[... sections omitted for brevity ...]\n\n")
      end
      table.insert(packed_sections, sections[idx].content)
      prev_idx = idx
    end
  end

  local packed_text = table.concat(packed_sections, "\n\n")

  -- Guarantee code fence integrity (all ``` must be paired)
  local _, total_fences = packed_text:gsub("```", "")
  if total_fences % 2 ~= 0 then
    packed_text = packed_text .. "\n```\n"
  end

  return packed_text
end

---Strip prompt-bleed line numbers ("  1 | ", " 12 > ", "123: ") from code blocks inside buffer
---@param buf number
local function clean_panel_code_blocks(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local in_code_block = false
  local modified = false
  for idx, line in ipairs(lines) do
    if line:match("^%s*```") then
      in_code_block = not in_code_block
    elseif in_code_block then
      local cleaned = line:gsub("^%s*%d+%s*[|>:]%s*", "")
      if cleaned ~= line then
        lines[idx] = cleaned
        modified = true
      end
    end
  end
  if modified then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
end

-- =============================================================================
-- UI Management: Vertical Split on Right (Non-intrusive, never covers code)
-- =============================================================================

---Append text chunk to side panel
---@param text string
local function append_to_panel(text)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local lines = vim.split(text, "\n", { plain = true })
  local last_idx = math.max(0, vim.api.nvim_buf_line_count(state.buf) - 1)
  local last_line = (vim.api.nvim_buf_get_lines(state.buf, last_idx, last_idx + 1, false)[1]) or ""
  lines[1] = last_line .. lines[1]
  vim.api.nvim_buf_set_lines(state.buf, last_idx, last_idx + 1, false, lines)

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local new_count = vim.api.nvim_buf_line_count(state.buf)
    pcall(vim.api.nvim_win_set_cursor, state.win, { new_count, 0 })
  end
end

---Set full lines in side panel
---@param lines string[]
local function set_panel_content(lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
  end
end

-- Forward declaration for follow-up prompt
local prompt_followup

---Create or focus right vertical split research panel
---@return number bufnr
---@return number winid
local function get_or_create_panel()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return state.buf, state.win
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"

  local ws_config = (config.options and config.options.web_search) or {}
  local width_pct = ws_config.panel_width_pct or 0.40
  local target_width = math.max(50, math.floor(vim.o.columns * width_pct))
  local win = vim.api.nvim_open_win(buf, true, {
    split = "right",
    width = target_width,
  })

  vim.wo[win].winfixwidth = true
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  state.buf = buf
  state.win = win

  -- Clean up state on window close
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if state.current_job then
        pcall(state.current_job.kill, state.current_job)
        state.current_job = nil
      end
      state.is_streaming = false
      state.win = nil
      state.buf = nil
    end,
  })

  -- Keymaps inside the right panel
  local map_opts = { buffer = buf, silent = true }

  -- q or <Esc> to close panel
  vim.keymap.set("n", "q", function()
    pcall(vim.api.nvim_win_close, win, true)
  end, vim.tbl_extend("force", map_opts, { desc = "Close AI Research Panel" }))

  vim.keymap.set("n", "<Esc>", function()
    pcall(vim.api.nvim_win_close, win, true)
  end, vim.tbl_extend("force", map_opts, { desc = "Close AI Research Panel" }))

  -- i or a to prompt for follow-up question
  vim.keymap.set("n", "i", function()
    prompt_followup()
  end, vim.tbl_extend("force", map_opts, { desc = "Ask Follow-up Question" }))

  vim.keymap.set("n", "a", function()
    prompt_followup()
  end, vim.tbl_extend("force", map_opts, { desc = "Ask Follow-up Question" }))

  -- gx to open link under cursor
  vim.keymap.set("n", "gx", function()
    local line = vim.api.nvim_get_current_line()
    local url = nil
    for raw_url in line:gmatch("https?://[%w%-_%.%?%+%:=%%&/#@]+") do
      url = raw_url
    end
    for _, md_url in line:gmatch("%b[]%((https?://[^)]+)%)") do
      url = md_url
    end
    if url then
      if vim.ui.open then
        vim.ui.open(url)
      else
        vim.fn.jobstart({ "xdg-open", url }, { detach = true })
      end
      vim.notify("[ai-editutor] Opening: " .. url, vim.log.levels.INFO)
    else
      vim.notify("[ai-editutor] No URL found on current line", vim.log.levels.WARN)
    end
  end, vim.tbl_extend("force", map_opts, { desc = "Open Link in Browser" }))

  return buf, win
end

-- =============================================================================
-- Retrieval: Brave Search API & Deep Scraper
-- =============================================================================

---Query Brave Search API
---@param query string
---@param on_complete function Callback(results)
local function search_brave(query, on_complete)
  local ws_config = (config.options and config.options.web_search) or {}
  local api_key = ws_config.brave_api_key or os.getenv("BRAVE_API_KEY")
  if not api_key or api_key == "" then
    debug_log.log("[web_search] Brave search API key not found. Please configure web_search.brave_api_key or set BRAVE_API_KEY environment variable.")
    on_complete({})
    return
  end
  local max_results = ws_config.max_search_results or 3

  local params = "q=" .. vim.uri_encode(query) .. "&count=5&extra_snippets=true"
  local url = "https://api.search.brave.com/res/v1/web/search?" .. params

  local cmd = {
    "curl",
    "-s",
    "--max-time",
    "6",
    url,
    "-H",
    "Accept: application/json",
    "-H",
    "X-Subscription-Token: " .. api_key,
    "-H",
    "User-Agent: ai-editutor-researcher/3.1",
  }

  debug_log.log("[web_search] Brave search query: " .. query)

  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 or not res.stdout or #res.stdout == 0 then
        debug_log.log("[web_search] Brave search returned empty or error code: " .. tostring(res.code))
        on_complete({})
        return
      end

      local ok, data = pcall(vim.json.decode, res.stdout)
      if not ok or not data or not data.web or not data.web.results then
        debug_log.log("[web_search] Failed to parse Brave JSON response")
        on_complete({})
        return
      end

      local results = {}
      for _, item in ipairs(data.web.results) do
        local target_url = item.url or ""
        if target_url:match("^https?://")
          and not target_url:match("youtube%.com")
          and not target_url:match("facebook%.com")
          and not target_url:match("instagram%.com")
        then
          local title = clean_html_entities(item.title)
          local desc = clean_html_entities(item.description)
          local extra_str = ""
          if item.extra_snippets and #item.extra_snippets > 0 then
            local extra_clean = {}
            for idx, s in ipairs(item.extra_snippets) do
              if idx <= 2 then
                table.insert(extra_clean, clean_html_entities(s))
              end
            end
            extra_str = " " .. table.concat(extra_clean, " ")
          end
          table.insert(results, {
            title = title,
            url = target_url,
            snippet = desc .. extra_str,
          })
          if #results >= max_results then
            break
          end
        end
      end

      debug_log.log(string.format("[web_search] Retrieved %d Brave search results", #results))
      on_complete(results)
    end)
  end)
end

---Scrape deep content via StackExchange API or Jina Reader with w3m fallback
---@param urls string[]
---@param query string
---@param on_complete function Callback(full_deep_docs_markdown)
local function scrape_deep_docs(urls, query, on_complete)
  if not urls or #urls == 0 then
    on_complete("")
    return
  end

  local ws_config = (config.options and config.options.web_search) or {}
  local max_deep = ws_config.max_deep_docs or 2
  local total_budget = ws_config.knapsack_max_chars or 36000

  local valid_urls = {}
  for _, u in ipairs(urls) do
    if not u:match("reddit%.com") and not u:match("twitter%.com") then
      table.insert(valid_urls, u)
      if #valid_urls >= max_deep then
        break
      end
    end
  end

  if #valid_urls == 0 then
    on_complete("")
    return
  end

  local completed = 0
  local deep_docs_parts = {}
  local per_doc_budget = math.max(4000, math.floor(total_budget / math.max(1, #valid_urls)))

  for i, target_url in ipairs(valid_urls) do
    local so_qid = target_url:match("stackoverflow%.com/questions/(%d+)")
    if so_qid then
      -- StackOverflow Path: Official StackExchange API (Zero Cloudflare issues)
      local so_api_url = "https://api.stackexchange.com/2.3/questions/" .. so_qid .. "/answers?order=desc&sort=votes&site=stackoverflow&filter=withbody"
      local cmd = {
        "curl",
        "-s",
        "--compressed",
        "--max-time",
        "6",
        so_api_url,
        "-H",
        "User-Agent: Mozilla/5.0 (compatible; ai-editutor/3.1)",
      }
      vim.system(cmd, { text = true }, function(res)
        local content = ""
        if res.code == 0 and res.stdout and #res.stdout > 50 then
          local ok, data = pcall(vim.json.decode, res.stdout)
          if ok and data and data.items and #data.items > 0 then
            local so_answers = {}
            for idx, ans in ipairs(data.items) do
              if idx <= 2 then
                local score = ans.score or 0
                local is_acc = ans.is_accepted and " (Accepted ✅)" or ""
                local body_md = stackoverflow_html_to_md(ans.body)
                table.insert(so_answers, string.format("#### 💬 Câu trả lời StackOverflow #%d [Votes: %d%s]:\n\n%s", idx, score, is_acc, body_md))
              end
            end
            content = table.concat(so_answers, "\n\n---\n\n")
          end
        end

        vim.schedule(function()
          completed = completed + 1
          if #content > 0 then
            local packed = smart_knapsack_pack(content, query, per_doc_budget)
            table.insert(deep_docs_parts, string.format("### 📄 Nguồn cào sâu [%d]: %s (StackOverflow Official API)\n\n%s", i, target_url, packed))
          end

          if completed >= #valid_urls then
            local full_deep_docs = table.concat(deep_docs_parts, "\n\n---\n\n")
            on_complete(full_deep_docs)
          end
        end)
      end)
    else
      -- Primary: Jina Reader API (r.jina.ai)
      local jina_url = "https://r.jina.ai/" .. target_url
      local cmd = {
        "curl",
        "-s",
        "-L",
        "--max-time",
        "8",
        jina_url,
        "-H",
        "X-Return-Format: markdown",
        "-H",
        "User-Agent: ai-editutor-researcher/3.1",
      }

      vim.system(cmd, { text = true }, function(res)
        local content = ""
        local is_blocked = false
        if res.code == 0 and res.stdout then
          local lower = res.stdout:lower()
          if lower:match("error 403: forbidden")
            or lower:match("just a moment%.%.%.")
            or lower:match("blocked by network security")
            or lower:match("attention required! | cloudflare")
            or lower:match("cf%-browser%-verification")
            or lower:match("please enable cookies")
            or lower:match("checking your browser")
            or lower:match("security check to access")
            or lower:match("cloudflare ray id")
          then
            is_blocked = true
          end
        end

        if res.code == 0 and res.stdout and #res.stdout > 150 and not is_blocked then
          content = res.stdout
        else
          -- Fallback: Local w3m dump
          local fallback_res = vim.system({
            "bash",
            "-c",
            string.format("curl -s -L --max-time 6 %q | w3m -dump -T text/html", target_url),
          }, { text = true }):wait()
          if fallback_res.code == 0 and fallback_res.stdout and #fallback_res.stdout > 100 then
            local fb_lower = fallback_res.stdout:lower()
            if not fb_lower:match("403 forbidden") and not fb_lower:match("just a moment") then
              content = fallback_res.stdout
            end
          end
        end

        vim.schedule(function()
          completed = completed + 1
          if #content > 0 then
            local packed = smart_knapsack_pack(content, query, per_doc_budget)
            table.insert(deep_docs_parts, string.format("### 📄 Nguồn cào sâu [%d]: %s\n\n%s", i, target_url, packed))
          end

          if completed >= #valid_urls then
            local full_deep_docs = table.concat(deep_docs_parts, "\n\n---\n\n")
            on_complete(full_deep_docs)
          end
        end)
      end)
    end
  end
end

-- =============================================================================
-- Ollama Streaming & Chat Execution
-- =============================================================================

---Stream multi-turn chat messages to LLM (DeepSeek or Ollama)
---@param messages table[]
---@param on_token function Callback(token)
---@param on_finish function Callback(completed_process)
local function stream_llm_chat(messages, on_token, on_finish)
  local ws_config = (config.options and config.options.web_search) or {}
  local deepseek_key = os.getenv("DEEPSEEK_API_KEY")
  local provider = ws_config.provider or (deepseek_key and "deepseek" or "ollama")

  if provider == "deepseek" and deepseek_key and #deepseek_key > 0 then
    local model = ws_config.model or "deepseek-flash"
    local max_tokens = ws_config.max_output_tokens or (config.options and config.options.max_output_tokens) or 8192
    local payload = vim.json.encode({
      model = model,
      messages = messages,
      stream = true,
      max_tokens = max_tokens,
      temperature = 0.2,
      thinking = { type = "disabled" },
    })

    local stdout_buffer = ""
    state.is_streaming = true

    local job = vim.system({
      "curl",
      "-s",
      "-N",
      "https://api.deepseek.com/chat/completions",
      "-H",
      "Content-Type: application/json",
      "-H",
      "Authorization: Bearer " .. deepseek_key,
      "-d",
      payload,
    }, {
      stdout = function(_, data)
        if data then
          stdout_buffer = stdout_buffer .. data
          while true do
            local line, rest = stdout_buffer:match("^(.-)\n(.*)$")
            if not line then
              break
            end
            stdout_buffer = rest
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line:sub(1, 6) == "data: " then
              local json_str = line:sub(7)
              if json_str ~= "[DONE]" then
                local ok, json = pcall(vim.json.decode, json_str)
                if ok and json and json.choices and json.choices[1] and json.choices[1].delta then
                  local token = json.choices[1].delta.content
                  if token and token ~= "" then
                    vim.schedule(function()
                      on_token(token)
                    end)
                  end
                end
              end
            end
          end
        end
      end,
    }, function(completed)
      vim.schedule(function()
        state.is_streaming = false
        state.current_job = nil
        if on_finish then
          on_finish(completed)
        end
      end)
    end)

    state.current_job = job
  else
    local ollama_url = ws_config.ollama_url or "http://localhost:11434"
    local model = ws_config.model or "qwen2.5-coder:3b"
    local num_ctx = ws_config.num_ctx or 32768

    local payload = vim.json.encode({
      model = model,
      messages = messages,
      stream = true,
      options = {
        num_ctx = num_ctx,
        temperature = 0.2,
        num_predict = 1800,
        repeat_penalty = 1.15,
        frequency_penalty = 0.1,
        presence_penalty = 0.1,
      },
    })

    local stdout_buffer = ""
    state.is_streaming = true

    local job = vim.system({
      "curl",
      "-s",
      "-N",
      ollama_url .. "/api/chat",
      "-H",
      "Content-Type: application/json",
      "-d",
      payload,
    }, {
      stdout = function(_, data)
        if data then
          stdout_buffer = stdout_buffer .. data
          while true do
            local line, rest = stdout_buffer:match("^(.-)\n(.*)$")
            if not line then
              break
            end
            stdout_buffer = rest
            if line ~= "" then
              local ok, json = pcall(vim.json.decode, line)
              if ok and json and json.message and json.message.content then
                local token = json.message.content
                vim.schedule(function()
                  on_token(token)
                end)
              end
            end
          end
        end
      end,
    }, function(completed)
      vim.schedule(function()
        state.is_streaming = false
        state.current_job = nil
        if on_finish then
          on_finish(completed)
        end
      end)
    end)

    state.current_job = job
  end
end

-- Backward compatibility alias
local stream_ollama_chat = stream_llm_chat

-- =============================================================================
-- Smart Diagnostics & Context Extraction (LSP + Annotated Code)
-- =============================================================================

---Gather LSP diagnostics and format annotated code lines around cursor
---@param buf number
---@param opts? table
---@return string code_context
---@return table[] top_diags
---@return string filetype
---@return string filepath
---@return number cur_line
local function get_smart_diagnostics_and_context(buf, opts)
  opts = opts or {}
  local ws_config = (config.options and config.options.web_search) or {}
  local max_code_lines = opts.max_code_lines or ws_config.max_code_lines or 120
  local max_code_chars = opts.max_code_chars or ws_config.max_code_chars or 16000
  local max_diag_count = opts.max_diag_count or ws_config.max_diag_count or 8

  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return "", {}, "text", "", 1
  end

  local filepath = vim.api.nvim_buf_get_name(buf)
  local filetype = vim.bo[buf].filetype or "text"
  if filetype == "" then
    filetype = "text"
  end

  local total_lines = vim.api.nvim_buf_line_count(buf)
  local cur_win = vim.fn.bufwinid(buf)
  local cur_line = 1
  if cur_win ~= -1 then
    local pos = vim.api.nvim_win_get_cursor(cur_win)
    cur_line = pos[1]
  end

  local mode = vim.api.nvim_get_mode().mode
  local is_visual = mode:match("^[vV\22]")
  local start_line, end_line

  if is_visual then
    local v_start = vim.fn.getpos("v")[2]
    local v_end = vim.fn.getpos(".")[2]
    if v_start > v_end then
      v_start, v_end = v_end, v_start
    end
    start_line = math.max(1, v_start - 5)
    end_line = math.min(total_lines, v_end + 5)
    cur_line = v_start
  else
    start_line = math.max(1, cur_line - max_code_lines)
    end_line = math.min(total_lines, cur_line + max_code_lines)
  end

  -- Collect and score diagnostics
  local all_diags = vim.diagnostic.get(buf)
  local scored_diags = {}

  for _, d in ipairs(all_diags) do
    local d_line = d.lnum + 1
    local dist = math.abs(d_line - cur_line)
    local sev_weight = (5 - (d.severity or 4)) * 250
    local in_window = (d_line >= start_line and d_line <= end_line) and 400 or 0
    local dist_penalty = math.min(dist * 10, 500)
    local score = sev_weight + in_window - dist_penalty

    table.insert(scored_diags, {
      score = score,
      line = d_line,
      col = (d.col or 0) + 1,
      severity = d.severity or 4,
      message = vim.trim(d.message or ""),
      source = d.source or filetype,
      code = d.code and tostring(d.code) or "",
    })
  end

  table.sort(scored_diags, function(a, b)
    return a.score > b.score
  end)

  local top_diags = {}
  local diag_by_line = {}
  for i = 1, math.min(#scored_diags, max_diag_count) do
    local item = scored_diags[i]
    table.insert(top_diags, item)
    if not diag_by_line[item.line] then
      diag_by_line[item.line] = {}
    end
    table.insert(diag_by_line[item.line], item)
  end

  local annotated_lines = {}
  local total_chars = 0

  -- Pin file header & imports if error occurs beyond the start of the file (start_line > 1)
  if start_line > 1 then
    local max_header_line = math.min(25, start_line - 1)
    local raw_header = vim.api.nvim_buf_get_lines(buf, 0, max_header_line, false)
    local has_imports = false
    for _, h_line in ipairs(raw_header) do
      local lower_h = h_line:lower():gsub("^%s+", "")
      if lower_h:match("^import%s")
        or lower_h:match("^from%s")
        or lower_h:match("^package%s")
        or lower_h:match("^use%s")
        or lower_h:match("^#include")
        or lower_h:match("^const%s+.*=%s*require")
        or lower_h:match("^local%s+.*=%s*require")
        or lower_h:match("^#pragma")
      then
        has_imports = true
        break
      end
    end

    if has_imports then
      for h_idx, h_line in ipairs(raw_header) do
        local h_line_num = h_idx
        local h_marker = (h_line_num == cur_line) and ">" or "|"
        local h_str = string.format("%4d %s %s", h_line_num, h_marker, h_line)
        table.insert(annotated_lines, h_str)
        total_chars = total_chars + #h_str + 1
      end
      if max_header_line < start_line - 1 then
        local omit_str = string.format("     ... [Lines %d-%d omitted for brevity] ...", max_header_line + 1, start_line - 1)
        table.insert(annotated_lines, omit_str)
        total_chars = total_chars + #omit_str + 1
      end
    end
  end

  local raw_lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
  local emitted_diags = {}

  for idx, line in ipairs(raw_lines) do
    local actual_line_num = start_line + idx - 1
    local is_cursor = (actual_line_num == cur_line)
    local marker = is_cursor and ">" or "|"
    local line_str = string.format("%4d %s %s", actual_line_num, marker, line)

    table.insert(annotated_lines, line_str)
    total_chars = total_chars + #line_str + 1

    if diag_by_line[actual_line_num] then
      for _, d in ipairs(diag_by_line[actual_line_num]) do
        emitted_diags[d] = true
        local sev_str = d.severity == 1 and "ERROR" or (d.severity == 2 and "WARN" or "INFO")
        local code_info = d.code ~= "" and (" " .. d.code) or ""
        local annot = string.format("     ^ [%s%s] (%s): %s", sev_str, code_info, d.source, d.message:gsub("\n", " "))
        table.insert(annotated_lines, annot)
        total_chars = total_chars + #annot + 1
      end
    end

    if total_chars > max_code_chars then
      table.insert(annotated_lines, string.format("     ... [Code truncated to fit budget: %d chars] ...", max_code_chars))
      break
    end
  end

  -- Catch any diagnostics placed at EOF or outside the visible window
  for _, d in ipairs(top_diags) do
    if not emitted_diags[d] then
      local sev_str = d.severity == 1 and "ERROR" or (d.severity == 2 and "WARN" or "INFO")
      local code_info = d.code ~= "" and (" " .. d.code) or ""
      local annot = string.format("     ^ [%s%s] (Line %d, %s): %s", sev_str, code_info, d.line, d.source, d.message:gsub("\n", " "))
      table.insert(annotated_lines, annot)
      total_chars = total_chars + #annot + 1
    end
  end

  local code_str = table.concat(annotated_lines, "\n")
  return code_str, top_diags, filetype, filepath, cur_line
end

---Formulate a 3 to 6 word search query using 1-shot LLM with deterministic fallback
---@param code_context string
---@param top_diags table[]
---@param filetype string
---@param user_intent? string
---@param callback function Callback(search_query, is_ai_formulated)
local function formulate_search_query(code_context, top_diags, filetype, user_intent, callback)
  local fallback_query = ""
  if #top_diags > 0 then
    local d = top_diags[1]
    local clean_msg = d.message:gsub("\n", " "):gsub("[%p%c]", " "):gsub("%s+", " ")
    local code_part = d.code ~= "" and (tostring(d.code) .. " ") or ""
    fallback_query = string.format("%s %s%s", filetype, code_part, clean_msg)
    fallback_query = vim.trim(fallback_query):sub(1, 100)
  elseif user_intent and #user_intent > 0 then
    fallback_query = user_intent
  else
    fallback_query = filetype .. " error documentation"
  end

  local diag_texts = {}
  for _, d in ipairs(top_diags) do
    local sev_str = d.severity == 1 and "ERROR" or (d.severity == 2 and "WARN" or "INFO")
    local code_info = d.code ~= "" and (" " .. d.code) or ""
    table.insert(diag_texts, string.format("[%s%s] (Line %d) %s: %s", sev_str, code_info, d.line, d.source, d.message))
  end
  local diag_summary = table.concat(diag_texts, "\n")

  local formulator_prompt = table.concat({
    "You are an expert search query generator for technical programming problems.",
    "Given the programming language, code context, and compiler/LSP diagnostics, generate a precise 3 to 6 word search query for Brave/Google Search.",
    "CRITICAL RULES:",
    "1. Strip project-specific identifiers, variable names, struct field names, and local paths (e.g. generalize 'my_cache.lock()' to 'mutex lock').",
    "2. Include the programming language or framework name and the core technical concept or error message.",
    "3. Output ONLY the 3 to 6 word search query on a single line. Do NOT output quotes, punctuation, markdown formatting, or explanations.",
    "",
    "Language: " .. filetype,
    "LSP Diagnostics:\n" .. (diag_summary ~= "" and diag_summary or "None"),
    (user_intent and user_intent ~= "") and ("User Note: " .. user_intent) or "",
    "Code Snippet:\n" .. code_context:sub(1, 1400),
    "",
    "Search Query:",
  }, "\n")

  local ws_config = (config.options and config.options.web_search) or {}
  local deepseek_key = os.getenv("DEEPSEEK_API_KEY")
  local provider = ws_config.provider or (deepseek_key and "deepseek" or "ollama")
  local model = ws_config.model or (provider == "deepseek" and "deepseek-flash" or "qwen2.5-coder:3b")

  local cmd
  if provider == "deepseek" and deepseek_key and #deepseek_key > 0 then
    local payload = vim.json.encode({
      model = model,
      messages = {
        { role = "user", content = formulator_prompt },
      },
      stream = false,
      max_tokens = 35,
      temperature = 0.1,
      thinking = { type = "disabled" },
    })
    cmd = {
      "curl",
      "-s",
      "--max-time",
      "8",
      "https://api.deepseek.com/chat/completions",
      "-H",
      "Content-Type: application/json",
      "-H",
      "Authorization: Bearer " .. deepseek_key,
      "-d",
      payload,
    }
  else
    local ollama_url = ws_config.ollama_url or "http://localhost:11434"
    local payload = vim.json.encode({
      model = model,
      messages = {
        { role = "user", content = formulator_prompt },
      },
      stream = false,
      options = {
        num_ctx = 4096,
        temperature = 0.1,
        num_predict = 35,
      },
    })
    cmd = {
      "curl",
      "-s",
      "--max-time",
      "8",
      ollama_url .. "/api/chat",
      "-H",
      "Content-Type: application/json",
      "-d",
      payload,
    }
  end

  vim.system(cmd, { text = true }, function(res)
    local generated_query = nil
    if res.code == 0 and res.stdout and #res.stdout > 0 then
      local ok, data = pcall(vim.json.decode, res.stdout)
      local content = nil
      if ok and data then
        if data.choices and data.choices[1] and data.choices[1].message then
          content = data.choices[1].message.content
        elseif data.message and data.message.content then
          content = data.message.content
        end
      end
      if content then
        local raw = vim.trim(content)
        raw = raw:gsub("`", ""):gsub('^["\']', ""):gsub('["\']$', ""):gsub("^[Qq]uery:%s*", "")
        raw = raw:gsub("\n.*$", "")
        raw = vim.trim(raw)
        local words = vim.split(raw, "%s+")
        local dedup_words = {}
        for _, w in ipairs(words) do
          if #dedup_words == 0 or dedup_words[#dedup_words]:lower() ~= w:lower() then
            table.insert(dedup_words, w)
          end
          if #dedup_words >= 6 then
            break
          end
        end
        if #dedup_words >= 2 then
          raw = table.concat(dedup_words, " ")
        end
        if #raw >= 5 and not raw:lower():match("here is") then
          generated_query = raw
        end
      end
    end

    local final_query = generated_query or fallback_query
    vim.schedule(function()
      callback(final_query, generated_query ~= nil)
    end)
  end)
end

-- =============================================================================
-- Core Entry Workflows
-- =============================================================================

---Run AI Web Search with deep context
---@param raw_query string
---@param opts? table
function M.search(raw_query, opts)
  opts = opts or {}
  local query = vim.trim(raw_query or "")
  if #query == 0 then
    vim.notify("[ai-editutor] Vui lòng nhập từ khóa tìm kiếm", vim.log.levels.WARN)
    return
  end

  local origin_buf = vim.api.nvim_get_current_buf()
  local code_context, filetype, filepath = get_buffer_context(origin_buf)

  state.active_code_buf = origin_buf
  state.active_filetype = filetype
  state.active_filepath = filepath

  local buf, _ = get_or_create_panel()

  if state.current_job then
    pcall(state.current_job.kill, state.current_job)
    state.current_job = nil
    state.is_streaming = false
  end

  state.messages = {}

  local display_q = #query > 40 and (query:sub(1, 37) .. "...") or query
  set_panel_content({
    "# 🔍 AI Web Research: " .. display_q,
    string.format("> **File:** `%s` | **Ngôn ngữ:** `%s` | **Model:** %s", vim.fs.basename(filepath), filetype, (config.options.web_search and config.options.web_search.model) or "qwen2.5-coder:3b"),
    "---",
    "",
    "⏳ *Bước 1/2: Đang tìm kiếm qua Brave Search API...*",
    "",
  })

  local search_engine_query = query
  local lower_q = query:lower()
  if not lower_q:match(filetype:lower()) and filetype ~= "text" and #query < 50 then
    search_engine_query = query .. " " .. filetype .. " documentation example"
  end

  search_brave(search_engine_query, function(results)
    if #results == 0 then
      append_to_panel("\n⚠️ *Không tìm thấy kết quả từ Brave Search. Đang hỏi trực tiếp LLM...*\n\n")
    else
      append_to_panel(string.format("\n✅ *Tìm thấy %d nguồn uy tín.* Đang cào sâu tài liệu (Jina Reader + Knapsack)...\n\n", #results))
    end

    local candidate_urls = {}
    for _, r in ipairs(results) do
      table.insert(candidate_urls, r.url)
    end

    scrape_deep_docs(candidate_urls, query, function(deep_docs)
      append_to_panel("🤖 *AI đang tổng hợp và phân tích...*\n\n---\n\n")

      local system_prompt = table.concat({
        "Bạn là chuyên gia lập trình và trợ lý nghiên cứu kỹ thuật bên trong Neovim.",
        "Nhiệm vụ: Dựa vào tài liệu web vừa tìm kiếm và mã nguồn hiện tại của lập trình viên, hãy phân tích và đưa ra câu trả lời xuất sắc nhất.",
        "",
        "Quy tắc trả lời:",
        "1. Trả lời hoàn toàn bằng tiếng Việt tự nhiên, rõ ràng, gãy gọn. Giữ nguyên thuật ngữ kỹ thuật tiếng Anh (interface, goroutine, hook, decorator, struct, closure...).",
        "2. Cấu trúc câu trả lời bắt buộc đầy đủ 5 mục sau:",
        "   - 📌 Khái niệm & Mục đích (Ngắn gọn 1-2 câu)",
        "   - 🎯 Khi nào nên dùng (Tình huống thực tế)",
        "   - 📥 Tham số & Giá trị trả về (Nếu là hàm/cú pháp/API) HOẶC Nguyên nhân gốc rễ (Nếu là lỗi runtime/compiler)",
        "   - 💻 Code mẫu chuẩn (Tối giản, dễ hiểu, có comment giải thích rõ ràng)",
        "   - ⚠️ Lưu ý & Cạm bẫy hay gặp (Gotchas, edge cases, hiệu năng)",
        "3. Tuyệt đối không lặp lại từ ngữ hoặc tạo vòng lặp vô tận. Luôn hoàn thành trọn vẹn cả 5 mục.",
        "4. Với các câu hỏi nâng cấp phiên bản hoặc breaking changes (như Pydantic v2, Tailwind v4, React 19...), BẮT BUỘC dùng cú pháp mới nhất từ tài liệu web, TUYỆT ĐỐI KHÔNG dùng cú pháp cũ deprecated.",
        "5. Nếu câu hỏi liên quan đến đoạn code trong file hiện tại của lập trình viên, hãy chỉ rõ cách áp dụng hoặc sửa trực tiếp vào file đó.",
        "6. Liệt kê các đường link nguồn ở cuối câu trả lời.",
      }, "\n")

      local web_section_parts = {}
      if deep_docs and #deep_docs > 0 then
        table.insert(web_section_parts, deep_docs)
      end
      if #results > 0 then
        local snippets_summary = { "### Tóm tắt các nguồn tìm kiếm:" }
        for _, r in ipairs(results) do
          table.insert(snippets_summary, string.format("- [%s](%s): %s", r.title, r.url, r.snippet))
        end
        table.insert(web_section_parts, table.concat(snippets_summary, "\n"))
      end
      local web_context_str = table.concat(web_section_parts, "\n\n")

      local user_prompt_parts = {}
      if #code_context > 0 then
        table.insert(user_prompt_parts, string.format("[MÃ NGUỒN HIỆN TẠI TRONG FILE: %s (%s)]\n```%s\n%s\n```", filepath, filetype, filetype, code_context))
      end
      if #web_context_str > 0 then
        table.insert(user_prompt_parts, string.format("[TÀI LIỆU WEB TÌM KIẾM ĐƯỢC]\n%s", web_context_str))
      end
      table.insert(user_prompt_parts, string.format("[CÂU HỎI CỦA LẬP TRÌNH VIÊN]\n%s", query))

      local user_prompt = table.concat(user_prompt_parts, "\n\n")

      state.messages = {
        { role = "system", content = system_prompt },
        { role = "user", content = user_prompt },
      }

      local assistant_response_accum = ""

      stream_ollama_chat(state.messages, function(token)
        assistant_response_accum = assistant_response_accum .. token
        append_to_panel(token)
      end, function()
        table.insert(state.messages, { role = "assistant", content = assistant_response_accum })
        pcall(clean_panel_code_blocks, state.buf)
        append_to_panel("\n\n---\n💡 **Phím tắt**: `i` / `a`: Hỏi tiếp (Follow-up) | `q`: Đóng panel | `gx`: Mở link nguồn | `<C-w>h`: Quay lại code\n")

        -- Save to knowledge base
        pcall(knowledge.save, {
          question = "[Web Search] " .. query,
          answer = assistant_response_accum,
          language = filetype,
          filepath = filepath,
        })
      end)
    end)
  end)
end

---Run Smart Auto-Diagnose & Fix (LSP Error + Context + Web Search + Code Fix)
---@param user_notes? string
---@param opts? table
function M.smart_fix(user_notes, opts)
  opts = opts or {}
  local origin_buf = vim.api.nvim_get_current_buf()
  local code_context, top_diags, filetype, filepath, cur_line = get_smart_diagnostics_and_context(origin_buf)

  if #top_diags == 0 and (not user_notes or #vim.trim(user_notes) == 0) then
    vim.ui.input({ prompt = "🛠️ [ai-editutor] Không có lỗi LSP. Nhập yêu cầu phân tích code: " }, function(input)
      if input and #vim.trim(input) > 0 then
        M.smart_fix(input, opts)
      end
    end)
    return
  end

  state.active_code_buf = origin_buf
  state.active_filetype = filetype
  state.active_filepath = filepath

  local buf, _ = get_or_create_panel()

  if state.current_job then
    pcall(state.current_job.kill, state.current_job)
    state.current_job = nil
    state.is_streaming = false
  end

  state.messages = {}

  local filename = vim.fs.basename(filepath)
  local diag_count_label = #top_diags > 0 and string.format("%d LSP diagnostics", #top_diags) or "Code Context"

  set_panel_content({
    "# 🛠️ AI Smart Auto-Diagnose & Fix: " .. filename,
    string.format("> **File:** `%s` (dòng %d) | **Ngôn ngữ:** `%s` | **Phát hiện:** %s", filename, cur_line, filetype, diag_count_label),
    "---",
    "",
    "⏳ *Bước 1/3: Đang đọc ngữ cảnh mã nguồn và phân tích lỗi LSP...*",
    "",
  })

  formulate_search_query(code_context, top_diags, filetype, user_notes, function(search_query, is_ai_formulated)
    append_to_panel(string.format("🔍 *Bước 2/3: LLM tự động trích xuất từ khóa tra cứu:* `%s`%s\n", search_query, is_ai_formulated and " *(AI Autonomous)*" or " *(LSP Fallback)*"))
    append_to_panel("⏳ *Đang tìm kiếm tài liệu chuẩn & giải pháp (Brave Search + StackExchange API)...*\n\n")

    search_brave(search_query, function(results)
      if #results == 0 then
        append_to_panel("⚠️ *Không tìm thấy kết quả từ web. Đang phân tích trực tiếp từ kiến thức mô hình...*\n\n")
      else
        append_to_panel(string.format("✅ *Tìm thấy %d nguồn uy tín.* Đang cào sâu chi tiết (StackExchange API / Jina + Knapsack)...\n\n", #results))
      end

      local candidate_urls = {}
      for _, r in ipairs(results) do
        table.insert(candidate_urls, r.url)
      end

      scrape_deep_docs(candidate_urls, search_query, function(deep_docs)
        append_to_panel("🤖 *Bước 3/3: AI đang tổng hợp nguyên nhân gốc rễ và viết code sửa đổi...*\n\n---\n\n")

        local system_prompt = table.concat({
          "Bạn là kỹ sư phần mềm cao cấp và chuyên gia gỡ lỗi (Debugging Specialist) trong Neovim.",
          "Nhiệm vụ: Phân tích mã nguồn được đánh số dòng, thông tin cảnh báo/lỗi LSP, và tài liệu kỹ thuật/StackOverflow vừa tra cứu để đưa ra nguyên nhân gốc rễ và code sửa đổi chính xác nhất.",
          "",
          "Quy tắc trả lời:",
          "1. Trả lời hoàn toàn bằng tiếng Việt tự nhiên, rõ ràng, kỹ thuật và gãy gọn. Giữ nguyên thuật ngữ kỹ thuật tiếng Anh (goroutine, channel, mutex, borrow checker, lifetime, async/await, hook...).",
          "2. Cấu trúc câu trả lời bắt buộc gồm 5 phần rõ ràng:",
          "   - 🔍 **1. Chẩn đoán nguyên nhân gốc rễ (Root Cause)**: Giải thích chính xác tại sao dòng mã đó bị cảnh báo/lỗi LSP dựa trên đặc tính ngôn ngữ/compiler.",
          "   - 💡 **2. Giải pháp kỹ thuật**: Cách xử lý chuẩn theo idiomatic coding style và best practices của ngôn ngữ/thư viện.",
          "   - 🛠️ **3. Code sửa đổi chi tiết**: Chỉ rõ dòng cần thay thế (trích số dòng), cung cấp code sửa hoàn chỉnh với comment giải thích rõ ràng.",
          "   - ⚠️ **4. Lưu ý & Cạm bẫy (Gotchas)**: Vấn đề hiệu năng, cạnh tranh tài nguyên (race condition), memory leak hoặc edge cases.",
          "   - 🔗 **5. Nguồn tham khảo**: Các tài liệu chính thức hoặc câu trả lời StackOverflow đã tra cứu.",
          "3. Code đề xuất phải tương thích hoàn toàn với ngữ cảnh xung quanh trong file mã nguồn của người dùng.",
          "4. TUYỆT ĐỐI KHÔNG ghi số dòng (ví dụ: '1 |', '2 >', '10 |') vào bên trong các khối mã code block ```. Code block phải là mã nguồn sạch nguyên bản để người dùng có thể copy và chạy được ngay.",
          "5. Tuyệt đối không lặp lại từ ngữ hoặc tạo vòng lặp vô tận. Hoàn thành đầy đủ cả 5 phần.",
        }, "\n")

        local web_section_parts = {}
        if deep_docs and #deep_docs > 0 then
          table.insert(web_section_parts, deep_docs)
        end
        if #results > 0 then
          local snippets_summary = { "### Tóm tắt các nguồn tìm kiếm:" }
          for _, r in ipairs(results) do
            table.insert(snippets_summary, string.format("- [%s](%s): %s", r.title, r.url, r.snippet))
          end
          table.insert(web_section_parts, table.concat(snippets_summary, "\n"))
        end
        local web_context_str = table.concat(web_section_parts, "\n\n")

        local diag_section_parts = {}
        if #top_diags > 0 then
          table.insert(diag_section_parts, "[DANH SÁCH CẢNH BÁO / LỖI LSP]")
          for _, d in ipairs(top_diags) do
            local sev_str = d.severity == 1 and "ERROR" or (d.severity == 2 and "WARN" or "INFO")
            local code_info = d.code ~= "" and (" [" .. d.code .. "]") or ""
            table.insert(diag_section_parts, string.format("- Dòng %d (Cột %d) [%s%s] từ %s: %s", d.line, d.col, sev_str, code_info, d.source, d.message))
          end
        end
        local diag_context_str = table.concat(diag_section_parts, "\n")

        local user_prompt_parts = {}
        if #code_context > 0 then
          table.insert(user_prompt_parts, string.format("[MÃ NGUỒN HIỆN TẠI VỚI SỐ DÒNG: %s (%s)]\n```%s\n%s\n```", filepath, filetype, filetype, code_context))
        end
        if #diag_context_str > 0 then
          table.insert(user_prompt_parts, diag_context_str)
        end
        if #web_context_str > 0 then
          table.insert(user_prompt_parts, string.format("[TÀI LIỆU WEB & STACKOVERFLOW TRA CỨU ĐƯỢC]\n%s", web_context_str))
        end

        local final_query_instruction = string.format("[YÊU CẦU CỦA LẬP TRÌNH VIÊN]\nHãy phân tích lỗi LSP trên mã nguồn trên (từ khóa tra cứu: '%s').%s Hãy đưa ra nguyên nhân gốc rễ và code sửa đổi chi tiết nhất.",
          search_query,
          (user_notes and #vim.trim(user_notes) > 0) and (" Ghi chú thêm: " .. user_notes) or "")
        table.insert(user_prompt_parts, final_query_instruction)

        local user_prompt = table.concat(user_prompt_parts, "\n\n")

        state.messages = {
          { role = "system", content = system_prompt },
          { role = "user", content = user_prompt },
        }

        local assistant_response_accum = ""

        stream_ollama_chat(state.messages, function(token)
          assistant_response_accum = assistant_response_accum .. token
          append_to_panel(token)
        end, function()
          table.insert(state.messages, { role = "assistant", content = assistant_response_accum })
          pcall(clean_panel_code_blocks, state.buf)
          append_to_panel("\n\n---\n💡 **Phím tắt**: `i` / `a`: Hỏi tiếp (Follow-up) | `q`: Đóng panel | `gx`: Mở link nguồn | `<C-w>h`: Quay lại code\n")

          -- Save to knowledge base
          pcall(knowledge.save, {
            question = string.format("[Smart Fix: %s] %s", filename, search_query),
            answer = assistant_response_accum,
            language = filetype,
            filepath = filepath,
          })
        end)
      end)
    end)
  end)
end

-- =============================================================================
-- Multi-turn Follow-up Flow
-- =============================================================================

prompt_followup = function()
  if state.is_streaming then
    vim.notify("[ai-editutor] AI đang trả lời, vui lòng đợi xong...", vim.log.levels.WARN)
    return
  end

  if #state.messages == 0 then
    vim.notify("[ai-editutor] Chưa có phiên tìm kiếm nào để hỏi tiếp", vim.log.levels.WARN)
    return
  end

  if #state.messages >= 22 then
    vim.notify("[ai-editutor] Đã đạt giới hạn 10 câu hỏi tiếp nối. Hãy khởi động phiên search mới.", vim.log.levels.INFO)
  end

  vim.ui.input({ prompt = "💬 [ai-editutor] Hỏi tiếp (Follow-up): " }, function(input)
    if not input or #vim.trim(input) == 0 then
      return
    end

    local q = vim.trim(input)
    append_to_panel(string.format("\n\n### 💬 Bạn: %s\n\n---\n🤖 **AI:**\n\n", q))

    table.insert(state.messages, { role = "user", content = q })

    local follow_up_accum = ""
    stream_ollama_chat(state.messages, function(token)
      follow_up_accum = follow_up_accum .. token
      append_to_panel(token)
    end, function()
      table.insert(state.messages, { role = "assistant", content = follow_up_accum })
      pcall(clean_panel_code_blocks, state.buf)
      append_to_panel("\n\n---\n💡 **Phím tắt**: `i` / `a`: Hỏi tiếp (Follow-up) | `q`: Đóng panel | `gx`: Mở link nguồn\n")
    end)
  end)
end

M.followup = prompt_followup

-- =============================================================================
-- Convenience Entry Points
-- =============================================================================

---Instant explain word under cursor or visual selection
function M.search_instant()
  local target = get_target_query()
  if target and #target > 0 then
    M.search(target)
  else
    vim.ui.input({ prompt = "🔍 [ai-editutor] Search Web: " }, function(input)
      if input and #vim.trim(input) > 0 then
        M.search(input)
      end
    end)
  end
end

---Prompt with visual selection or word pre-filled
function M.search_prompt()
  local target = get_target_query()
  vim.ui.input({
    prompt = "🔍 [ai-editutor] Search (chỉnh sửa câu hỏi): ",
    default = target or "",
  }, function(input)
    if input and #vim.trim(input) > 0 then
      M.search(input)
    end
  end)
end

---Blank search prompt
function M.search_blank()
  vim.ui.input({ prompt = "🔍 [ai-editutor] Search Web: " }, function(input)
    if input and #vim.trim(input) > 0 then
      M.search(input)
    end
  end)
end

return M
