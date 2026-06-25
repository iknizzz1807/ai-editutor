-- editutor/lsp_references.lua
-- Symbol reference/call-site context for ai-editutor.

local M = {}

local async = require("editutor.async")
local project_scanner = require("editutor.project_scanner")
local lsp_context = require("editutor.lsp_context")

M.config = {
  lookahead_lines = 25,
  max_symbols = 2,
  max_refs_per_symbol = 8,
  max_total_refs = 12,
  snippet_radius = 4,
  max_tokens = 3000,
  timeout_ms = 5000,
}

local COMMON_NOISE = {
  id = true,
  name = true,
  data = true,
  result = true,
  value = true,
  values = true,
  props = true,
  state = true,
  item = true,
  items = true,
  map = true,
  filter = true,
  reduce = true,
  trim = true,
  length = true,
}

local function get_display_path(filepath, project_root)
  local root_name = vim.fn.fnamemodify(project_root, ":t")
  if filepath:sub(1, #project_root) == project_root then
    local relative = filepath:sub(#project_root + 2):gsub("^/", "")
    return root_name .. "/" .. relative
  end
  return root_name .. "/" .. vim.fn.fnamemodify(filepath, ":t")
end

local function is_noise(name)
  if not name or #name < 3 then
    return true
  end
  return COMMON_NOISE[name] == true
end

local function question_mentions(question_text, name)
  if not question_text or question_text == "" then
    return false
  end
  return question_text:match("%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]") ~= nil
end

local function extract_symbols_below_question(bufnr, question)
  local symbols = {}
  local seen = {}
  local start_line = (question.block_end or question.pending_line or question.block_start or 1) -- 1-indexed
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local scan_start = math.min(total_lines - 1, start_line)
  local scan_end = math.min(total_lines, scan_start + M.config.lookahead_lines)

  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok_parser or not parser then
    return symbols
  end

  local tree = parser:parse()[1]
  if not tree then
    return symbols
  end

  local lang = parser:lang()
  local query_string = "[(identifier) (property_identifier) (type_identifier)] @id"
  if lang == "lua" then
    query_string = "[(identifier) (dot_index_expression)] @id"
  elseif lang == "python" then
    query_string = "[(identifier) (attribute)] @id"
  elseif lang == "go" or lang == "rust" or lang == "c" then
    query_string = "[(identifier) (type_identifier) (field_identifier)] @id"
  elseif lang == "odin" then
    query_string = "(identifier) @id"
  elseif lang == "cpp" then
    query_string = "[(identifier) (type_identifier) (field_identifier) (namespace_identifier) (qualified_identifier)] @id"
  end

  local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if not ok_query or not query then
    return symbols
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, scan_start, scan_end, false)
  local function local_line(row)
    return lines[row - scan_start + 1] or ""
  end

  for _, node in query:iter_captures(tree:root(), bufnr, scan_start, scan_end) do
    local row, col = node:start()
    local name = vim.treesitter.get_node_text(node, bufnr)
    if name and not seen[name] and not is_noise(name) then
      seen[name] = true
      local line_text = local_line(row)
      local score = 0

      if question_mentions(question.question, name) then
        score = score + 100
      end
      if line_text:match("function%s+" .. vim.pesc(name) .. "%f[^%w_]")
        or line_text:match("class%s+" .. vim.pesc(name) .. "%f[^%w_]")
        or line_text:match("interface%s+" .. vim.pesc(name) .. "%f[^%w_]")
        or line_text:match("type%s+" .. vim.pesc(name) .. "%f[^%w_]")
        or line_text:match(vim.pesc(name) .. "%s*::%s*proc%f[^%w_]")
        or line_text:match(vim.pesc(name) .. "%s*::%s*%(%s*proc%f[^%w_]")
      then
        score = score + 50
      end
      if line_text:match(vim.pesc(name) .. "%s*%(") then
        score = score + 25
      end
      score = score + math.max(0, 20 - (row - scan_start))

      table.insert(symbols, {
        name = name,
        line = row,
        col = col,
        score = score,
      })
    end
  end

  table.sort(symbols, function(a, b)
    if a.score == b.score then
      return a.line < b.line
    end
    return a.score > b.score
  end)

  if #symbols > M.config.max_symbols then
    symbols = vim.list_slice(symbols, 1, M.config.max_symbols)
  end

  return symbols
end

local function read_reference_snippet(filepath, line)
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return nil
  end

  local start_line = math.max(1, line - M.config.snippet_radius)
  local end_line = math.min(#lines, line + M.config.snippet_radius)
  return table.concat(vim.list_slice(lines, start_line, end_line), "\n"), start_line, end_line
end

function M.extract_async(bufnr, questions)
  local current_file = vim.api.nvim_buf_get_name(bufnr)
  local project_root = project_scanner.get_project_root(current_file)
  local result = {
    symbols = {},
    tokens = 0,
    refs = 0,
  }

  if #vim.lsp.get_clients({ bufnr = bufnr }) == 0 then
    return result
  end

  local total_refs = 0
  local seen_refs = {}

  for _, question in ipairs(questions or {}) do
    local symbols = extract_symbols_below_question(bufnr, question)
    for _, symbol in ipairs(symbols) do
      if total_refs >= M.config.max_total_refs then
        break
      end

      local locations = async.lsp_references(bufnr, symbol.line, symbol.col, M.config.timeout_ms)
      local symbol_result = { name = symbol.name, references = {} }
      local refs_for_symbol = 0

      for _, loc in ipairs(locations or {}) do
        if refs_for_symbol >= M.config.max_refs_per_symbol or total_refs >= M.config.max_total_refs then
          break
        end
        if loc.uri and loc.range then
          local filepath = vim.uri_to_fname(loc.uri)
          local ref_line = loc.range.start.line + 1
          local key = filepath .. ":" .. ref_line

          if filepath ~= current_file and not seen_refs[key] and lsp_context.is_project_file(filepath) then
            local snippet, start_line, end_line = read_reference_snippet(filepath, ref_line)
            if snippet and snippet ~= "" then
              local tokens = project_scanner.estimate_tokens(snippet)
              if result.tokens + tokens <= M.config.max_tokens then
                seen_refs[key] = true
                refs_for_symbol = refs_for_symbol + 1
                total_refs = total_refs + 1
                result.tokens = result.tokens + tokens
                table.insert(symbol_result.references, {
                  filepath = filepath,
                  display_path = get_display_path(filepath, project_root),
                  line = ref_line,
                  start_line = start_line,
                  end_line = end_line,
                  snippet = snippet,
                  tokens = tokens,
                })
              end
            end
          end
        end
      end

      if #symbol_result.references > 0 then
        table.insert(result.symbols, symbol_result)
        result.refs = result.refs + #symbol_result.references
      end
    end
  end

  return result
end

function M.format_for_prompt(info)
  if not info or not info.symbols or #info.symbols == 0 then
    return "", { symbols = 0, refs = 0, tokens = 0 }
  end

  local parts = {
    "=== LSP REFERENCES / CALL SITES ===",
    "These are precise project locations where symbols near the question's target code are referenced. Use this section to understand callers/usages and real arguments. It complements RELATED FILES, which are broader import-based context.",
    "",
  }

  for _, symbol in ipairs(info.symbols) do
    table.insert(parts, "Symbol: " .. symbol.name)
    table.insert(parts, "")
    for _, ref in ipairs(symbol.references) do
      local ext = ref.filepath:match("%.([^.]+)$") or ""
      local lang = project_scanner.get_language_for_ext(ext)
      table.insert(parts, string.format("// Reference: %s:%d", ref.display_path, ref.line))
      table.insert(parts, "```" .. lang)
      table.insert(parts, ref.snippet)
      table.insert(parts, "```")
      table.insert(parts, "")
    end
  end

  return table.concat(parts, "\n"), {
    symbols = #info.symbols,
    refs = info.refs or 0,
    tokens = info.tokens or 0,
  }
end

return M
