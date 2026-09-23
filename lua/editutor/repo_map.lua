-- editutor/repo_map.lua
-- Compact Aider-inspired repository outline for broad, low-token context.

local M = {}

local project_scanner = require("editutor.project_scanner")
local repo_rank = require("editutor.repo_rank")

M.config = {
  max_tokens = 4000,
  max_files = 80,
  max_symbols = 300,
  max_symbols_per_file = 12,
  max_important_files = 12,
}

local IMPORTANT_PRIORITY = {
  ["package.json"] = 100,
  ["pyproject.toml"] = 100,
  ["Cargo.toml"] = 100,
  ["go.mod"] = 100,
  ["tsconfig.json"] = 90,
  ["vite.config.js"] = 80,
  ["vite.config.ts"] = 80,
  ["next.config.js"] = 80,
  ["next.config.ts"] = 80,
  ["svelte.config.js"] = 80,
  ["README.md"] = 70,
  ["README"] = 70,
}

local function rel_path(filepath, project_root)
  if filepath and filepath:sub(1, #project_root) == project_root then
    return filepath:sub(#project_root + 2):gsub("^/", "")
  end
  return filepath or ""
end

local function symbol_label(symbol)
  local typ = symbol.type or "symbol"
  if typ == "class" then
    return "class " .. symbol.name
  elseif typ == "interface" then
    return "interface " .. symbol.name
  elseif typ == "type" then
    return "type " .. symbol.name
  elseif typ == "enum" then
    return "enum " .. symbol.name
  elseif typ == "method" then
    return "method " .. symbol.name
  elseif typ == "function" then
    return "function " .. symbol.name
  elseif typ == "constant" then
    return "const " .. symbol.name
  elseif typ == "module" then
    return "module " .. symbol.name
  elseif typ == "macro" then
    return "macro " .. symbol.name
  end
  return typ .. " " .. symbol.name
end

---Clean a raw source code line to extract a concise signature
---@param raw_line string
---@param symbol table {name: string, type: string}
---@return string signature
local function clean_signature_line(raw_line, symbol)
  if not raw_line or raw_line == "" then
    return symbol_label(symbol)
  end
  local clean = vim.trim(raw_line)
  -- Remove comments
  clean = clean:gsub("%s*%-%-.*$", ""):gsub("%s*//.*$", ""):gsub("%s*#.*$", "")
  -- Remove trailing block openers, colons, semicolons, dos, thens
  clean = clean:gsub("%s*[{};:]%s*$", ""):gsub("%s+do%s*$", ""):gsub("%s+then%s*$", "")
  -- Remove module/self qualifiers before symbol name: M.foo -> foo, self.foo -> foo
  clean = clean:gsub("[%w_]+%.(" .. vim.pesc(symbol.name) .. ")", "%1")
  -- Remove visibility / storage modifiers
  clean = clean:gsub("^export%s+", ""):gsub("^pub%s+", ""):gsub("^async%s+", ""):gsub("^static%s+", ""):gsub("^local%s+", "")
  -- Remove function keyword for cleaner compact display
  clean = clean:gsub("^function%s+", ""):gsub("^def%s+", ""):gsub("^fn%s+", ""):gsub("^func%s+", "")
  clean = vim.trim(clean)

  -- Truncate overly long parameter lists
  if #clean > 60 then
    clean = clean:sub(1, 57) .. "..."
  end

  if #clean == 0 or not clean:find(symbol.name, 1, true) then
    return symbol_label(symbol)
  end
  return clean
end

---Extract signature for a symbol from file on disk
---@param filepath string Absolute file path
---@param line number 0-indexed line number
---@param symbol table
---@param file_cache table<string, string[]>
---@return string
local function get_symbol_signature(filepath, line, symbol, file_cache)
  if not file_cache[filepath] then
    if vim.fn.filereadable(filepath) == 1 then
      file_cache[filepath] = vim.fn.readfile(filepath)
    else
      file_cache[filepath] = {}
    end
  end
  local lines = file_cache[filepath]
  local raw_line = lines and lines[line + 1] or ""
  return clean_signature_line(raw_line, symbol)
end

local function important_score(file)
  local name = file.name or vim.fn.fnamemodify(file.path or "", ":t")
  local score = IMPORTANT_PRIORITY[name] or 50
  if not (file.path or ""):find("/", 1, true) then
    score = score + 10
  end
  if file.lines and file.lines > 250 then
    score = score - 20
  end
  return score
end

local function collect_important_files(scan_result, current_rel, limit)
  local important = {}
  for _, file in ipairs(scan_result.files or {}) do
    if file.type == "config" and file.path ~= current_rel and project_scanner.is_important_file(file.path) then
      table.insert(important, file)
    end
  end

  table.sort(important, function(a, b)
    local sa = important_score(a)
    local sb = important_score(b)
    if sa == sb then
      return a.path < b.path
    end
    return sa > sb
  end)

  if #important > limit then
    important = vim.list_slice(important, 1, limit)
  end

  return important
end

local function append_if_fits(lines, new_lines, max_tokens)
  local candidate = vim.list_extend(vim.deepcopy(lines), new_lines)
  local text = table.concat(candidate, "\n")
  if project_scanner.estimate_tokens(text) <= max_tokens then
    return candidate, true
  end
  return lines, false
end

function M.render(current_file, project_root, scan_result, opts)
  opts = opts or {}
  project_root = project_root or project_scanner.get_project_root(current_file)
  scan_result = scan_result or project_scanner.scan_project({ root = project_root })

  local max_tokens = opts.max_tokens or M.config.max_tokens
  if max_tokens <= 0 then
    return "", { tokens = 0, files = 0, symbols = 0, important_files = 0 }
  end

  local current_rel = rel_path(current_file, project_root)
  local ranked_files = opts.ranked_files
  local rank_meta = opts.rank_meta
  if not ranked_files or not rank_meta then
    ranked_files, rank_meta = repo_rank.rank_project(current_file, project_root, scan_result, {
      mentioned_idents = opts.mentioned_idents,
      mentioned_files = opts.mentioned_files,
      top_files = opts.max_files or M.config.max_files,
      top_symbols = opts.max_symbols or M.config.max_symbols,
    })
  end

  local symbols_by_file = {}
  local file_order = {}
  local seen_file = {}
  local symbol_count = 0

  for _, symbol in ipairs((rank_meta and rank_meta.ranked_symbols) or {}) do
    if symbol.rel_path ~= current_rel then
      local bucket = symbols_by_file[symbol.rel_path]
      if not bucket then
        bucket = {}
        symbols_by_file[symbol.rel_path] = bucket
        if not seen_file[symbol.rel_path] then
          seen_file[symbol.rel_path] = true
          table.insert(file_order, symbol.rel_path)
        end
      end
      if #bucket < (opts.max_symbols_per_file or M.config.max_symbols_per_file) then
        table.insert(bucket, symbol)
        symbol_count = symbol_count + 1
      end
    end
  end

  for _, ranked in ipairs(ranked_files or {}) do
    if ranked.rel_path ~= current_rel and not seen_file[ranked.rel_path] then
      seen_file[ranked.rel_path] = true
      table.insert(file_order, ranked.rel_path)
    end
  end

  local lines = {
    "=== REPO MAP (compact symbol outline) ===",
    "These are ranked project symbols and important project files for broad context. Use RELATED FILES for implementation details.",
    "",
  }

  local files_rendered = 0
  local symbols_rendered = 0
  local important_files_rendered = 0

  local important_files = collect_important_files(scan_result, current_rel, opts.max_important_files or M.config.max_important_files)
  for _, file in ipairs(important_files) do
    local entry = {
      file.path .. ":",
      string.format("  important project file%s", file.lines and string.format(" (%d lines)", file.lines) or ""),
      "",
    }
    local ok
    lines, ok = append_if_fits(lines, entry, max_tokens)
    if ok then
      files_rendered = files_rendered + 1
      important_files_rendered = important_files_rendered + 1
    end
  end

  for _, file in ipairs(file_order) do
    local symbols = symbols_by_file[file]
    local entry = { file .. ":" }
    if symbols and #symbols > 0 then
      for _, symbol in ipairs(symbols) do
        table.insert(entry, string.format("  %s", symbol_label(symbol)))
      end
    else
      table.insert(entry, "  ranked project file")
    end
    table.insert(entry, "")

    local ok
    lines, ok = append_if_fits(lines, entry, max_tokens)
    if ok then
      files_rendered = files_rendered + 1
      symbols_rendered = symbols_rendered + (symbols and #symbols or 0)
    end
  end

  if files_rendered == 0 then
    return "", { tokens = 0, files = 0, symbols = 0, important_files = 0 }
  end

  local text = table.concat(lines, "\n")
  return text, {
    tokens = project_scanner.estimate_tokens(text),
    files = files_rendered,
    symbols = symbols_rendered,
    important_files = important_files_rendered,
    ranked_symbols = symbol_count,
    rank = rank_meta and {
      tags = rank_meta.tags,
      files_scanned = rank_meta.files_scanned,
      nodes = rank_meta.nodes,
      ranked = rank_meta.ranked,
    } or nil,
  }
end

---Render an Aider-style Unified Context Map combining the project tree with inline/indented symbol signatures
---@param current_file string
---@param project_root string
---@param scan_result table
---@param opts? table {max_tokens?: number, max_symbols_per_file?: number, style?: "inline"|"indent", mentioned_idents?: table}
---@return string tree_text
---@return table metadata
function M.render_unified_map(current_file, project_root, scan_result, opts)
  opts = opts or {}
  project_root = project_root or project_scanner.get_project_root(current_file)
  scan_result = scan_result or project_scanner.scan_project({ root = project_root })

  local max_tokens = opts.max_tokens or M.config.max_tokens
  if max_tokens <= 0 then
    return "", { tokens = 0, files = 0, symbols = 0, important_files = 0 }
  end

  local current_rel = rel_path(current_file, project_root)
  local ranked_files = opts.ranked_files
  local rank_meta = opts.rank_meta
  if not ranked_files or not rank_meta then
    ranked_files, rank_meta = repo_rank.rank_project(current_file, project_root, scan_result, {
      mentioned_idents = opts.mentioned_idents,
      mentioned_files = opts.mentioned_files,
      top_files = opts.max_files or M.config.max_files,
      top_symbols = opts.max_symbols or M.config.max_symbols,
    })
  end

  local file_cache = {}
  local symbols_by_file = {}
  local symbol_count = 0
  local max_per_file = opts.max_symbols_per_file or M.config.max_symbols_per_file

  for _, symbol in ipairs((rank_meta and rank_meta.ranked_symbols) or {}) do
    if symbol.rel_path ~= current_rel then
      local bucket = symbols_by_file[symbol.rel_path]
      if not bucket then
        bucket = {}
        symbols_by_file[symbol.rel_path] = bucket
      end
      if #bucket < max_per_file then
        local abs_filepath = project_root .. "/" .. symbol.rel_path
        local signature = get_symbol_signature(abs_filepath, symbol.line, symbol, file_cache)
        table.insert(bucket, signature)
        symbol_count = symbol_count + 1
      end
    end
  end

  local important_files_list = collect_important_files(scan_result, current_rel, opts.max_important_files or M.config.max_important_files)
  local important_files_map = {}
  for _, f in ipairs(important_files_list) do
    important_files_map[f.path] = true
  end

  local tree_text = project_scanner.build_tree_structure(project_root, scan_result.files, scan_result.folders, {
    symbols_by_file = symbols_by_file,
    important_files = important_files_map,
    max_symbols_per_file = max_per_file,
    style = opts.style or "inline",
  })

  -- Truncate tree if it exceeds max_tokens budget
  local est_tokens = project_scanner.estimate_tokens(tree_text)
  if est_tokens > max_tokens then
    local tree_lines = vim.split(tree_text, "\n")
    local max_lines = math.floor(#tree_lines * (max_tokens / est_tokens))
    if max_lines < #tree_lines then
      tree_lines = vim.list_slice(tree_lines, 1, math.max(5, max_lines))
      tree_text = table.concat(tree_lines, "\n") .. "\n... (remaining tree truncated to fit budget)"
      est_tokens = project_scanner.estimate_tokens(tree_text)
    end
  end

  return tree_text, {
    tokens = est_tokens,
    symbols = symbol_count,
    files_with_symbols = vim.tbl_count(symbols_by_file),
    important_files = #important_files_list,
    rank = rank_meta and {
      tags = rank_meta.tags,
      files_scanned = rank_meta.files_scanned,
      nodes = rank_meta.nodes,
      ranked = rank_meta.ranked,
    } or nil,
  }
end

return M
