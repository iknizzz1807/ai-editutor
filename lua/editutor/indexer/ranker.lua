-- editutor/indexer/ranker.lua
-- Multi-signal context ranking for precise LLM context selection
-- Combines: BM25, LSP definitions, file recency, directory proximity, import graph, recent access

local M = {}

local db = require("editutor.indexer.db")
local chunker = require("editutor.indexer.chunker")

-- Default weights for ranking signals
M.DEFAULT_WEIGHTS = {
  lsp_definition = 1.0, -- Direct LSP go-to-definition match
  lsp_reference = 0.3, -- LSP references
  bm25_score = 0.5, -- FTS5 BM25 relevance score
  file_recency = 0.2, -- Recently modified files (mtime from filesystem)
  directory_proximity = 0.3, -- Same/nearby directory
  import_distance = 0.2, -- Import graph distance
  recent_access = 0.15, -- Recently opened in editor
  type_priority = 0.15, -- Chunk type (function > class > variable)
  name_match = 0.4, -- Exact/partial name match
}

-- Context budget allocation (percentage of total budget)
M.BUDGET_ALLOCATION = {
  current_file = 0.30, -- 30% for current file context
  lsp_definitions = 0.25, -- 25% for LSP definitions
  bm25_results = 0.20, -- 20% for BM25 search results
  imports = 0.10, -- 10% for import graph
  project_docs = 0.10, -- 10% for README, package.json, etc.
  diagnostics = 0.05, -- 5% for LSP diagnostics/errors
}

---Calculate directory proximity score
---@param file1 string
---@param file2 string
---@param project_root string
---@return number 0-1 score (1 = same directory)
local function calc_directory_proximity(file1, file2, project_root)
  if not file1 or not file2 then
    return 0
  end

  -- Get relative paths
  local rel1 = file1:gsub("^" .. vim.pesc(project_root) .. "/?", "")
  local rel2 = file2:gsub("^" .. vim.pesc(project_root) .. "/?", "")

  -- Split into path components
  local parts1 = vim.split(rel1, "/")
  local parts2 = vim.split(rel2, "/")

  -- Remove filename
  table.remove(parts1)
  table.remove(parts2)

  -- Count common prefix
  local common = 0
  for i = 1, math.min(#parts1, #parts2) do
    if parts1[i] == parts2[i] then
      common = common + 1
    else
      break
    end
  end

  -- Calculate score based on common path depth
  local max_depth = math.max(#parts1, #parts2)
  if max_depth == 0 then
    return 1 -- Same directory (root)
  end

  return common / max_depth
end

---Calculate file recency score using mtime from database
---@param filepath string
---@return number 0-1 score (1 = modified recently)
local function calc_file_recency(filepath)
  local file_info = db.get_file(filepath)
  if not file_info or not file_info.mtime then
    return 0
  end

  -- Score based on age (decay over 7 days)
  local age_seconds = os.time() - file_info.mtime
  local age_days = age_seconds / (24 * 60 * 60)
  local decay_days = 7 -- Files modified within a week get higher scores

  return math.max(0, 1 - (age_days / decay_days))
end

---Calculate import graph distance
---@param from_file string
---@param to_file string
---@return number 0-1 score (1 = directly imported)
local function calc_import_distance(from_file, to_file)
  -- Check if to_file is directly imported by from_file
  local from_info = db.get_file(from_file)
  if not from_info then
    return 0
  end

  -- Get the filename/module name of to_file
  local to_name = vim.fn.fnamemodify(to_file, ":t:r")

  -- Check imports
  local importers = db.get_importers(to_name)
  for _, imp in ipairs(importers) do
    if imp.path == from_file then
      return 1 -- Directly imported
    end
  end

  -- TODO: Could implement multi-hop distance calculation
  return 0
end

---Calculate name match score
---@param query string
---@param chunk_name string|nil
---@return number 0-1 score
local function calc_name_match(query, chunk_name)
  if not chunk_name or chunk_name == "" then
    return 0
  end

  local query_lower = query:lower()
  local name_lower = chunk_name:lower()

  -- Exact match
  if query_lower == name_lower then
    return 1
  end

  -- Contains match
  if name_lower:find(query_lower, 1, true) then
    return 0.7
  end

  -- Word match (query words appear in name)
  local words_matched = 0
  local total_words = 0
  for word in query_lower:gmatch("%w+") do
    total_words = total_words + 1
    if name_lower:find(word, 1, true) then
      words_matched = words_matched + 1
    end
  end

  if total_words > 0 then
    return 0.5 * (words_matched / total_words)
  end

  return 0
end

---Calculate recent access score
---@param filepath string
---@return number 0-1 score
local function calc_recent_access(filepath)
  local file_info = db.get_file(filepath)
  if not file_info or not file_info.last_accessed then
    return 0
  end

  -- Score based on how recently accessed (decay over 1 hour)
  local age_seconds = os.time() - file_info.last_accessed
  local decay_seconds = 60 * 60 -- 1 hour

  return math.max(0, 1 - (age_seconds / decay_seconds))
end

---Calculate combined score for a chunk
---@param chunk table
---@param opts table {query, current_file, weights, project_root}
---@return number score
local function calc_chunk_score(chunk, opts)
  -- Merge custom weights with defaults to ensure all keys exist
  local weights = vim.tbl_deep_extend("force", M.DEFAULT_WEIGHTS, opts.weights or {})
  local score = 0

  -- BM25 score (already from FTS5, normalize to 0-1)
  -- FTS5 bm25() returns negative scores, lower is better
  if chunk.score then
    local normalized_bm25 = math.max(0, 1 + chunk.score / 10)
    score = score + weights.bm25_score * normalized_bm25
  end

  -- Name match
  local name_score = calc_name_match(opts.query or "", chunk.name)
  score = score + weights.name_match * name_score

  -- Type priority
  local type_priority = chunker.get_type_priority(chunk.type) / 10
  score = score + weights.type_priority * type_priority

  -- Directory proximity
  if opts.current_file and chunk.file_path then
    local proximity = calc_directory_proximity(opts.current_file, chunk.file_path, opts.project_root or "")
    score = score + weights.directory_proximity * proximity
  end

  -- File recency (using mtime from database - fast!)
  if chunk.file_path then
    local recency_score = calc_file_recency(chunk.file_path)
    score = score + weights.file_recency * recency_score
  end

  -- Import distance
  if opts.current_file and chunk.file_path then
    local import_score = calc_import_distance(opts.current_file, chunk.file_path)
    score = score + weights.import_distance * import_score
  end

  -- Recent access
  if chunk.file_path then
    local access_score = calc_recent_access(chunk.file_path)
    score = score + weights.recent_access * access_score
  end

  return score
end

---Search and rank chunks
---@param query string Search query
---@param opts table {limit, current_file, cursor_line, project_root, weights}
---@return table[] Ranked chunks with scores
function M.search_and_rank(query, opts)
  opts = opts or {}
  local limit = opts.limit or 20

  -- Get BM25 results from FTS5
  local bm25_results = db.search_bm25(query, { limit = limit * 2 })

  -- Also search by exact name
  local name_results = db.search_by_name(query)

  -- Merge results (avoid duplicates)
  local seen = {}
  local all_results = {}

  for _, chunk in ipairs(bm25_results) do
    if not seen[chunk.id] then
      seen[chunk.id] = true
      table.insert(all_results, chunk)
    end
  end

  for _, chunk in ipairs(name_results) do
    if not seen[chunk.id] then
      seen[chunk.id] = true
      table.insert(all_results, chunk)
    end
  end

  -- Calculate combined scores
  for _, chunk in ipairs(all_results) do
    chunk.combined_score = calc_chunk_score(chunk, {
      query = query,
      current_file = opts.current_file,
      project_root = opts.project_root,
      weights = opts.weights,
    })
  end

  -- Sort by combined score (higher is better)
  table.sort(all_results, function(a, b)
    return a.combined_score > b.combined_score
  end)

  -- Return top N
  local results = {}
  for i = 1, math.min(limit, #all_results) do
    table.insert(results, all_results[i])
  end

  return results
end

---Get LSP definitions for current context
---@param current_file string
---@param cursor_line number
---@return table[] definitions
local function get_lsp_definitions(current_file, cursor_line)
  -- Use existing lsp_context module if available
  local ok, lsp_context = pcall(require, "editutor.lsp_context")
  if not ok then
    return {}
  end

  if not lsp_context.is_available() then
    return {}
  end

  -- Get identifiers around cursor
  local context = lsp_context.get_context({
    filepath = current_file,
    cursor_line = cursor_line,
    lines_around = 50,
  })

  return context.external_definitions or {}
end

---Build formatted context for LLM prompt
---@param query string
---@param opts table {current_file, cursor_line, project_root, budget, weights}
---@return string formatted_context
---@return table metadata
function M.build_context(query, opts)
  opts = opts or {}
  local budget = opts.budget or 4000 -- tokens
  local allocation = M.BUDGET_ALLOCATION

  local context_parts = {}
  local metadata = {
    chunks_included = 0,
    sources = {},
  }

  -- Estimate tokens (rough: 4 chars per token)
  local function estimate_tokens(text)
    return math.ceil(#text / 4)
  end

  local function add_context(label, content, max_tokens)
    if not content or content == "" then
      return 0
    end

    local tokens = estimate_tokens(content)
    if tokens > max_tokens then
      -- Truncate
      local max_chars = max_tokens * 4
      content = content:sub(1, max_chars) .. "\n... (truncated)"
      tokens = max_tokens
    end

    table.insert(context_parts, string.format("=== %s ===\n%s", label, content))
    return tokens
  end

  local used_tokens = 0

  -- 1. Current file context (30%)
  if opts.current_file and opts.cursor_line then
    local ok, lines = pcall(vim.fn.readfile, opts.current_file)
    if ok and lines then
      local start_line = math.max(1, opts.cursor_line - 50)
      local end_line = math.min(#lines, opts.cursor_line + 50)

      local current_context = {}
      for i = start_line, end_line do
        table.insert(current_context, string.format("%d: %s", i, lines[i]))
      end

      local current_budget = math.floor(budget * allocation.current_file)
      local filename = vim.fn.fnamemodify(opts.current_file, ":t")
      used_tokens = used_tokens
        + add_context(string.format("Current File: %s (lines %d-%d)", filename, start_line, end_line), table.concat(current_context, "\n"), current_budget)

      table.insert(metadata.sources, { type = "current_file", file = opts.current_file })
    end
  end

  -- 2. LSP definitions (25%)
  if opts.current_file and opts.cursor_line then
    local definitions = get_lsp_definitions(opts.current_file, opts.cursor_line)
    if #definitions > 0 then
      local def_parts = {}
      for _, def in ipairs(definitions) do
        table.insert(def_parts, string.format("-- %s (%s:%d-%d)\n%s", def.name or "unknown", vim.fn.fnamemodify(def.filepath or "", ":t"), def.start_line or 0, def.end_line or 0, def.content or ""))
      end

      local lsp_budget = math.floor(budget * allocation.lsp_definitions)
      used_tokens = used_tokens + add_context("LSP Definitions", table.concat(def_parts, "\n\n"), lsp_budget)

      table.insert(metadata.sources, { type = "lsp_definitions", count = #definitions })
    end
  end

  -- 3. BM25 search results (20%)
  if query and query ~= "" then
    local search_results = M.search_and_rank(query, {
      limit = 10,
      current_file = opts.current_file,
      project_root = opts.project_root,
      weights = opts.weights,
    })

    if #search_results > 0 then
      local search_parts = {}
      for _, chunk in ipairs(search_results) do
        local header = string.format(
          "-- %s %s (%s:%d-%d) [score: %.2f]",
          chunk.type or "chunk",
          chunk.name or "",
          vim.fn.fnamemodify(chunk.file_path or "", ":t"),
          chunk.start_line or 0,
          chunk.end_line or 0,
          chunk.combined_score or 0
        )
        table.insert(search_parts, header .. "\n" .. (chunk.content or ""))
      end

      local bm25_budget = math.floor(budget * allocation.bm25_results)
      used_tokens = used_tokens + add_context("Related Code (BM25)", table.concat(search_parts, "\n\n"), bm25_budget)

      metadata.chunks_included = #search_results
      table.insert(metadata.sources, { type = "bm25_search", count = #search_results })
    end
  end

  -- 4. Import graph (10%)
  if opts.current_file then
    local file_info = db.get_file(opts.current_file)
    if file_info and file_info.id then
      -- Get files that import current file
      local filename = vim.fn.fnamemodify(opts.current_file, ":t:r")
      local importers = db.get_importers(filename)

      if #importers > 0 then
        local import_parts = {}
        for _, imp in ipairs(importers) do
          table.insert(import_parts, string.format("- %s (line %d)", imp.path, imp.line_number or 0))
        end

        local import_budget = math.floor(budget * allocation.imports)
        used_tokens = used_tokens + add_context("Files importing this module", table.concat(import_parts, "\n"), import_budget)

        table.insert(metadata.sources, { type = "import_graph", count = #importers })
      end
    end
  end

  -- 5. Project docs (10%)
  if opts.project_root then
    local doc_files = { "README.md", "package.json", "Cargo.toml", "pyproject.toml", "go.mod" }
    local doc_content = {}

    for _, doc_file in ipairs(doc_files) do
      local doc_path = opts.project_root .. "/" .. doc_file
      if vim.fn.filereadable(doc_path) == 1 then
        local ok, content = pcall(vim.fn.readfile, doc_path)
        if ok and content then
          -- Take first 50 lines
          local preview = table.concat(vim.list_slice(content, 1, 50), "\n")
          table.insert(doc_content, string.format("-- %s\n%s", doc_file, preview))
        end
      end
    end

    if #doc_content > 0 then
      local doc_budget = math.floor(budget * allocation.project_docs)
      used_tokens = used_tokens + add_context("Project Documentation", table.concat(doc_content, "\n\n"), doc_budget)

      table.insert(metadata.sources, { type = "project_docs" })
    end
  end

  -- 6. Diagnostics (5%) - LSP errors/warnings
  if opts.current_file then
    local diagnostics = vim.diagnostic.get(0, { severity = { min = vim.diagnostic.severity.WARN } })

    if #diagnostics > 0 then
      local diag_parts = {}
      for _, diag in ipairs(diagnostics) do
        table.insert(diag_parts, string.format("Line %d: [%s] %s", diag.lnum + 1, vim.diagnostic.severity[diag.severity], diag.message))
      end

      local diag_budget = math.floor(budget * allocation.diagnostics)
      used_tokens = used_tokens + add_context("LSP Diagnostics", table.concat(diag_parts, "\n"), diag_budget)

      table.insert(metadata.sources, { type = "diagnostics", count = #diagnostics })
    end
  end

  metadata.total_tokens = used_tokens

  return table.concat(context_parts, "\n\n"), metadata
end

---Get context specifically for a code location
---@param filepath string
---@param line_start number
---@param line_end number
---@return string context
function M.get_location_context(filepath, line_start, line_end)
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return ""
  end

  local context_lines = {}
  for i = line_start, math.min(line_end, #lines) do
    if lines[i] then
      table.insert(context_lines, lines[i])
    end
  end

  return table.concat(context_lines, "\n")
end

return M
