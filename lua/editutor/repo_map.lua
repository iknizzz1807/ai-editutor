-- editutor/repo_map.lua
-- Compact Aider-inspired repository outline for broad, low-token context.

local M = {}

local project_scanner = require("editutor.project_scanner")
local repo_rank = require("editutor.repo_rank")

M.config = {
  max_tokens = 2000,
  max_files = 30,
  max_symbols = 120,
  max_symbols_per_file = 8,
  max_important_files = 8,
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
  local ranked_files, rank_meta = repo_rank.rank_project(current_file, project_root, scan_result, {
    mentioned_idents = opts.mentioned_idents,
    mentioned_files = opts.mentioned_files,
    top_files = opts.max_files or M.config.max_files,
    top_symbols = opts.max_symbols or M.config.max_symbols,
  })

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

  for _, file in ipairs(collect_important_files(scan_result, current_rel, opts.max_important_files or M.config.max_important_files)) do
    local entry = {
      file.path .. ":",
      string.format("  important project file%s", file.lines and string.format(" (%d lines)", file.lines) or ""),
      "",
    }
    local ok
    lines, ok = append_if_fits(lines, entry, max_tokens)
    if ok then
      files_rendered = files_rendered + 1
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
    important_files = math.min(#collect_important_files(scan_result, current_rel, opts.max_important_files or M.config.max_important_files), files_rendered),
    ranked_symbols = symbol_count,
    rank = rank_meta and {
      tags = rank_meta.tags,
      files_scanned = rank_meta.files_scanned,
      nodes = rank_meta.nodes,
      ranked = rank_meta.ranked,
    } or nil,
  }
end

return M
