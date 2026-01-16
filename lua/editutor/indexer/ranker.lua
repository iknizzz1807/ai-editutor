-- editutor/indexer/ranker.lua
-- Multi-signal context ranking for precise LLM context selection
-- Combines: BM25, LSP definitions, file recency, directory proximity, import graph, recent access

local M = {}

local db = require("editutor.indexer.db")
local chunker = require("editutor.indexer.chunker")

-- =============================================================================
-- Query Preprocessing & Synonym Expansion
-- =============================================================================

-- Common programming synonyms for better search
M.SYNONYMS = {
  -- Authentication
  auth = { "authentication", "login", "logout", "signin", "signout", "session" },
  login = { "auth", "signin", "authenticate" },
  logout = { "signout", "auth" },
  session = { "token", "auth", "cookie" },

  -- Validation
  validate = { "check", "verify", "ensure", "assert", "sanitize" },
  check = { "validate", "verify", "test" },

  -- Error handling
  error = { "exception", "throw", "catch", "fail", "invalid" },
  handle = { "process", "manage", "catch" },

  -- Data operations
  fetch = { "get", "retrieve", "load", "request", "query" },
  save = { "store", "persist", "write", "update", "insert" },
  delete = { "remove", "destroy", "clear", "drop" },
  update = { "modify", "change", "edit", "patch" },

  -- Functions/Methods
  func = { "function", "method", "procedure", "handler" },
  callback = { "handler", "listener", "hook" },

  -- Data structures
  array = { "list", "collection", "items" },
  object = { "dict", "map", "hash", "record" },

  -- Async
  async = { "await", "promise", "future", "coroutine" },
  sync = { "synchronous", "blocking" },

  -- Security
  encrypt = { "hash", "cipher", "crypto", "secure" },
  password = { "pass", "pwd", "secret", "credential" },

  -- Common concepts
  config = { "configuration", "settings", "options", "prefs" },
  init = { "initialize", "setup", "bootstrap", "start" },
  parse = { "decode", "deserialize", "extract" },
  format = { "serialize", "encode", "stringify" },
}

-- Stop words to remove from queries (as set for O(1) lookup)
M.STOP_WORDS = {}
for _, word in ipairs({
  "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
  "have", "has", "had", "do", "does", "did", "will", "would", "could",
  "should", "may", "might", "must", "shall", "can", "need", "dare",
  "to", "of", "in", "for", "on", "with", "at", "by", "from", "as",
  "into", "through", "during", "before", "after", "above", "below",
  "between", "under", "again", "further", "then", "once", "here",
  "there", "when", "where", "why", "how", "all", "each", "few", "more",
  "most", "other", "some", "such", "no", "nor", "not", "only", "own",
  "same", "so", "than", "too", "very", "just", "also", "now", "this",
  "that", "these", "those", "i", "me", "my", "myself", "we", "our",
  "what", "which", "who", "whom", "if", "or", "and", "but", "because",
}) do
  M.STOP_WORDS[word] = true
end

---Convert camelCase/PascalCase to words
---@param str string
---@return string[]
local function split_camel_case(str)
  local words = {}
  -- Insert space before uppercase letters and split
  local spaced = str:gsub("(%l)(%u)", "%1 %2")
    :gsub("(%u)(%u%l)", "%1 %2")
    :gsub("_", " ")
    :gsub("-", " ")
  for word in spaced:gmatch("%S+") do
    table.insert(words, word:lower())
  end
  return words
end

---Extract key terms from natural language query
---@param query string
---@return string[] terms
local function extract_query_terms(query)
  local terms = {}
  local seen = {}

  -- Extract words (preserve case for camelCase splitting)
  for word in query:gmatch("[%w_]+") do
    local word_lower = word:lower()
    if #word > 1 and not M.STOP_WORDS[word_lower] then
      -- Split camelCase/snake_case (this needs original case)
      local parts = split_camel_case(word)
      for _, part in ipairs(parts) do
        local part_lower = part:lower()
        if #part > 1 and not M.STOP_WORDS[part_lower] and not seen[part_lower] then
          seen[part_lower] = true
          table.insert(terms, part_lower)
        end
      end
    end
  end

  return terms
end

---Expand query with synonyms
---@param terms string[]
---@return string[] expanded
local function expand_with_synonyms(terms)
  local expanded = {}
  local seen = {}

  for _, term in ipairs(terms) do
    if not seen[term] then
      seen[term] = true
      table.insert(expanded, term)

      -- Add synonyms
      local syns = M.SYNONYMS[term]
      if syns then
        for _, syn in ipairs(syns) do
          if not seen[syn] then
            seen[syn] = true
            table.insert(expanded, syn)
          end
        end
      end
    end
  end

  return expanded
end

---Preprocess query for better search
---@param query string
---@return string processed_query
---@return string[] terms
function M.preprocess_query(query)
  local terms = extract_query_terms(query)
  local expanded = expand_with_synonyms(terms)
  return table.concat(expanded, " "), expanded
end

-- =============================================================================
-- Ranking Configuration
-- =============================================================================

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
-- These are DEFAULT values - adaptive allocation will adjust them
M.BUDGET_ALLOCATION = {
  current_file = 0.25, -- 25% for current file context
  lsp_definitions = 0.20, -- 20% for LSP definitions
  bm25_results = 0.20, -- 20% for BM25 search results
  call_graph = 0.15, -- 15% for callers/callees
  type_definitions = 0.08, -- 8% for type definitions (NEW)
  imports = 0.05, -- 5% for import graph
  project_docs = 0.05, -- 5% for README, package.json, etc.
  diagnostics = 0.02, -- 2% for LSP diagnostics/errors
}

-- =============================================================================
-- Adaptive Budget Allocation
-- =============================================================================

-- Query type patterns for classification
local QUERY_TYPE_PATTERNS = {
  -- Specific function/method questions
  specific_function = {
    patterns = { "function%s+%w+", "method%s+%w+", "def%s+%w+", "fn%s+%w+", "what does%s+%w+%s+do" },
    keywords = { "function", "method", "does", "work", "implement", "return" },
  },
  -- Debugging questions
  debugging = {
    patterns = { "error", "bug", "fix", "crash", "fail", "broken", "not working", "why" },
    keywords = { "error", "bug", "fix", "crash", "fail", "broken", "debug", "issue", "problem" },
  },
  -- Architecture/overview questions
  architecture = {
    patterns = { "how does.*work", "architecture", "structure", "overview", "design" },
    keywords = { "architecture", "structure", "overview", "design", "flow", "system", "pattern" },
  },
  -- Type/interface questions
  type_related = {
    patterns = { "type%s+%w+", "interface%s+%w+", "struct%s+%w+", "class%s+%w+" },
    keywords = { "type", "interface", "struct", "class", "model", "schema", "definition" },
  },
}

---Classify query type
---@param query string
---@return string query_type One of: specific_function, debugging, architecture, type_related, general
---@return number confidence 0-1
local function classify_query(query)
  local query_lower = query:lower()
  local scores = {}

  for qtype, config in pairs(QUERY_TYPE_PATTERNS) do
    local score = 0

    -- Check patterns
    for _, pattern in ipairs(config.patterns) do
      if query_lower:match(pattern) then
        score = score + 2
      end
    end

    -- Check keywords
    for _, keyword in ipairs(config.keywords) do
      if query_lower:find(keyword, 1, true) then
        score = score + 1
      end
    end

    scores[qtype] = score
  end

  -- Find highest score
  local max_score = 0
  local best_type = "general"
  for qtype, score in pairs(scores) do
    if score > max_score then
      max_score = score
      best_type = qtype
    end
  end

  local confidence = math.min(1, max_score / 5)
  return best_type, confidence
end

---Analyze search results quality
---@param results table[] BM25 search results
---@param query string Original query
---@return table quality {has_exact_match, avg_score, top_score, relevance}
local function analyze_results_quality(results, query)
  if not results or #results == 0 then
    return {
      has_exact_match = false,
      avg_score = 0,
      top_score = 0,
      relevance = "none",
    }
  end

  local query_lower = query:lower()
  local has_exact = false
  local total_score = 0
  local top_score = 0

  for _, r in ipairs(results) do
    local score = r.combined_score or 0
    total_score = total_score + score
    if score > top_score then
      top_score = score
    end

    -- Check for exact name match
    if r.name and r.name:lower() == query_lower then
      has_exact = true
    elseif r.name and query_lower:find(r.name:lower(), 1, true) then
      has_exact = true
    end
  end

  local avg_score = total_score / #results
  local relevance = "low"
  if top_score > 1.5 or has_exact then
    relevance = "high"
  elseif top_score > 0.8 then
    relevance = "medium"
  end

  return {
    has_exact_match = has_exact,
    avg_score = avg_score,
    top_score = top_score,
    relevance = relevance,
  }
end

---Calculate adaptive budget allocation
---@param query string
---@param query_type string
---@param results_quality table
---@param opts table {current_file_has_answer}
---@return table allocation Adjusted budget allocation
local function calculate_adaptive_budget(query, query_type, results_quality, opts)
  opts = opts or {}

  -- Start with default allocation
  local allocation = vim.deepcopy(M.BUDGET_ALLOCATION)

  -- Adjust based on query type
  if query_type == "specific_function" then
    -- More budget to BM25 and call graph for specific function queries
    allocation.bm25_results = allocation.bm25_results + 0.08
    allocation.call_graph = allocation.call_graph + 0.05
    allocation.project_docs = allocation.project_docs - 0.08
    allocation.imports = allocation.imports - 0.05

  elseif query_type == "debugging" then
    -- More budget to current file and diagnostics for debugging
    allocation.current_file = allocation.current_file + 0.10
    allocation.diagnostics = allocation.diagnostics + 0.05
    allocation.project_docs = allocation.project_docs - 0.05
    allocation.call_graph = allocation.call_graph - 0.05
    allocation.type_definitions = allocation.type_definitions - 0.05

  elseif query_type == "architecture" then
    -- More budget to project docs and imports for architecture questions
    allocation.project_docs = allocation.project_docs + 0.10
    allocation.imports = allocation.imports + 0.05
    allocation.bm25_results = allocation.bm25_results - 0.08
    allocation.call_graph = allocation.call_graph - 0.07

  elseif query_type == "type_related" then
    -- More budget to type definitions
    allocation.type_definitions = allocation.type_definitions + 0.12
    allocation.lsp_definitions = allocation.lsp_definitions + 0.05
    allocation.call_graph = allocation.call_graph - 0.10
    allocation.project_docs = allocation.project_docs - 0.05
    allocation.imports = allocation.imports - 0.02
  end

  -- Adjust based on results quality
  if results_quality.relevance == "high" then
    -- BM25 found very relevant results, give it more budget
    allocation.bm25_results = allocation.bm25_results + 0.05
    allocation.current_file = allocation.current_file - 0.03
    allocation.project_docs = allocation.project_docs - 0.02

  elseif results_quality.relevance == "none" or results_quality.relevance == "low" then
    -- BM25 didn't find good results, rely more on current file
    allocation.current_file = allocation.current_file + 0.08
    allocation.lsp_definitions = allocation.lsp_definitions + 0.05
    allocation.bm25_results = allocation.bm25_results - 0.10
    allocation.call_graph = allocation.call_graph - 0.03
  end

  -- Ensure no negative values and normalize to sum to 1.0
  local total = 0
  for k, v in pairs(allocation) do
    allocation[k] = math.max(0.02, v) -- Minimum 2% for each category
    total = total + allocation[k]
  end

  -- Normalize
  for k, v in pairs(allocation) do
    allocation[k] = v / total
  end

  return allocation
end

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

---Calculate import graph distance (supports 2-hop)
---@param from_file string
---@param to_file string
---@return number 0-1 score (1 = directly imported, 0.5 = 2-hop)
local function calc_import_distance(from_file, to_file)
  -- Check if to_file is directly imported by from_file
  local from_info = db.get_file(from_file)
  if not from_info then
    return 0
  end

  -- Get the filename/module name of to_file
  local to_name = vim.fn.fnamemodify(to_file, ":t:r")

  -- Check direct imports (1-hop)
  local importers = db.get_importers(to_name)
  for _, imp in ipairs(importers) do
    if imp.path == from_file then
      return 1 -- Directly imported
    end
  end

  -- Check 2-hop imports (from_file imports X, X imports to_file)
  -- Get what from_file imports
  local from_name = vim.fn.fnamemodify(from_file, ":t:r")
  local from_importers = db.get_importers(from_name)

  -- For each file that from_file imports, check if it imports to_file
  for _, mid_imp in ipairs(from_importers) do
    if mid_imp.path and mid_imp.path ~= from_file then
      -- Check if this intermediate file imports to_file
      for _, to_imp in ipairs(importers) do
        if to_imp.path == mid_imp.path then
          return 0.5 -- 2-hop connection
        end
      end
    end
  end

  return 0
end

---Calculate name match score (improved with camelCase/snake_case handling)
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
    return 0.8
  end

  -- Split both into words (handle camelCase, snake_case, PascalCase)
  local query_words = split_camel_case(query)
  local name_words = split_camel_case(chunk_name)

  -- Calculate word overlap score
  local matched = 0
  for _, qw in ipairs(query_words) do
    if #qw > 1 then -- Skip single chars
      for _, nw in ipairs(name_words) do
        if nw == qw then
          matched = matched + 1
          break
        elseif nw:find(qw, 1, true) or qw:find(nw, 1, true) then
          matched = matched + 0.5
          break
        end
      end
    end
  end

  if #query_words > 0 then
    local overlap = matched / #query_words
    return 0.6 * overlap
  end

  -- Check synonyms
  for _, qw in ipairs(query_words) do
    local syns = M.SYNONYMS[qw]
    if syns then
      for _, syn in ipairs(syns) do
        if name_lower:find(syn, 1, true) then
          return 0.4
        end
      end
    end
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

  -- Preprocess query for better search
  local processed_query, terms = M.preprocess_query(query)

  -- Get BM25 results from FTS5 (use both original and processed)
  local bm25_results = db.search_bm25(processed_query, { limit = limit * 2 })

  -- Also search with original query if different
  if processed_query ~= query:lower() then
    local original_results = db.search_bm25(query, { limit = limit })
    for _, r in ipairs(original_results) do
      table.insert(bm25_results, r)
    end
  end

  -- Also search by exact name (try each term)
  local name_results = {}
  for _, term in ipairs(terms) do
    local results = db.search_by_name(term)
    for _, r in ipairs(results) do
      table.insert(name_results, r)
    end
  end

  -- Add original query name search
  local orig_name = db.search_by_name(query)
  for _, r in ipairs(orig_name) do
    table.insert(name_results, r)
  end

  -- Merge results (avoid duplicates)
  local seen = {}
  local all_results = {}

  for _, chunk in ipairs(bm25_results) do
    if chunk.id and not seen[chunk.id] then
      seen[chunk.id] = true
      table.insert(all_results, chunk)
    end
  end

  for _, chunk in ipairs(name_results) do
    if chunk.id and not seen[chunk.id] then
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

-- =============================================================================
-- Call Graph Context
-- =============================================================================

---Get related chunks via call graph (callers and callees)
---@param chunk table The chunk to find relations for
---@param opts table {max_callers, max_callees}
---@return table[] related_chunks
local function get_call_graph_context(chunk, opts)
  opts = opts or {}
  local max_callers = opts.max_callers or 3
  local max_callees = opts.max_callees or 5

  local related = {}

  -- Get callers (functions that call this one)
  if chunk.name then
    local callers = db.get_callers(chunk.name)
    for i, caller in ipairs(callers) do
      if i > max_callers then
        break
      end
      caller.relation = "caller"
      table.insert(related, caller)
    end
  end

  -- Get callees (functions this one calls)
  if chunk.id then
    local callees = db.get_callees(chunk.id)
    for i, callee in ipairs(callees) do
      if i > max_callees then
        break
      end
      callee.relation = "callee"
      table.insert(related, callee)
    end
  end

  return related
end

---Get type definitions used by chunks
---@param chunks table[] Chunks to find type definitions for
---@param opts table {max_types, project_root}
---@return table[] type_definitions
local function get_type_context(chunks, opts)
  opts = opts or {}
  local max_types = opts.max_types or 5

  local type_defs = {}
  local seen_types = {}

  for _, chunk in ipairs(chunks) do
    -- Extract type names from chunk content using patterns
    local content = chunk.content or ""

    -- Common type reference patterns
    local type_patterns = {
      -- TypeScript/JavaScript
      ":%s*([A-Z][%w_]+)", -- : TypeName
      "<%s*([A-Z][%w_]+)", -- <TypeName>
      "as%s+([A-Z][%w_]+)", -- as TypeName
      "implements%s+([A-Z][%w_]+)", -- implements TypeName
      "extends%s+([A-Z][%w_]+)", -- extends TypeName

      -- Go
      "%*?([A-Z][%w_]+)%s*{", -- TypeName{
      "func%s*%([^)]*%*?([A-Z][%w_]+)", -- func (x *TypeName)

      -- Rust
      "->%s*([A-Z][%w_]+)", -- -> TypeName
      "impl%s+([A-Z][%w_]+)", -- impl TypeName
      "<%s*([A-Z][%w_]+)%s*>", -- <TypeName>

      -- Python type hints
      ":%s*([A-Z][%w_]+)%s*[=,)]", -- : TypeName
      "->%s*([A-Z][%w_]+)", -- -> TypeName

      -- Java/C#
      "new%s+([A-Z][%w_]+)", -- new TypeName
      "([A-Z][%w_]+)%s+%w+%s*[=;]", -- TypeName varName
    }

    for _, pattern in ipairs(type_patterns) do
      for type_name in content:gmatch(pattern) do
        -- Filter out common non-type words and primitives
        local skip_words = {
          "String", "Int", "Float", "Double", "Boolean", "Bool", "Void",
          "True", "False", "None", "Null", "Nil", "Error", "Exception",
          "Object", "Array", "List", "Map", "Set", "Dict", "Promise",
          "Result", "Option", "Some", "Ok", "Err", "Self", "This",
        }

        local is_skip = false
        for _, skip in ipairs(skip_words) do
          if type_name == skip then
            is_skip = true
            break
          end
        end

        if not is_skip and not seen_types[type_name] and #type_defs < max_types then
          seen_types[type_name] = true

          -- Try to find type definition in database
          local definitions = db.get_type_definition(type_name)
          if #definitions > 0 then
            for _, def in ipairs(definitions) do
              def.referenced_by = chunk.name
              table.insert(type_defs, def)
            end
          else
            -- Also try BM25 search for the type
            local search_results = db.search_by_name(type_name)
            for _, result in ipairs(search_results) do
              if result.type and (
                result.type:find("interface") or
                result.type:find("type") or
                result.type:find("class") or
                result.type:find("struct") or
                result.type:find("enum")
              ) then
                result.referenced_by = chunk.name
                table.insert(type_defs, result)
                break
              end
            end
          end
        end
      end
    end
  end

  return type_defs
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

-- =============================================================================
-- Context Deduplication
-- =============================================================================

---Simple hash for content deduplication
---@param content string
---@return string hash
local function content_hash(content)
  -- Normalize: remove whitespace variations
  local normalized = content:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  -- Simple hash based on content
  local hash = 0
  for i = 1, math.min(#normalized, 500) do
    hash = (hash * 31 + normalized:byte(i)) % 2147483647
  end
  return string.format("%x_%d", hash, #normalized)
end

---Check if content is similar to already seen content
---@param content string
---@param seen_hashes table
---@param threshold number Similarity threshold (0.8 = 80% similar)
---@return boolean is_duplicate
local function is_duplicate_content(content, seen_hashes, threshold)
  threshold = threshold or 0.8
  local hash = content_hash(content)

  -- Exact hash match
  if seen_hashes[hash] then
    return true
  end

  -- Check for substring containment (one contains most of the other)
  for seen_hash, seen_content in pairs(seen_hashes) do
    -- If this content is mostly contained in seen content
    local shorter = #content < #seen_content and content or seen_content
    local longer = #content >= #seen_content and content or seen_content

    -- Quick length check
    if #shorter > 50 and #shorter / #longer > threshold then
      -- Check if shorter is a substring of longer
      if longer:find(shorter:sub(1, 100), 1, true) then
        return true
      end
    end
  end

  return false
end

---Build formatted context for LLM prompt
---@param query string
---@param opts table {current_file, cursor_line, project_root, budget, weights}
---@return string formatted_context
---@return table metadata
function M.build_context(query, opts)
  opts = opts or {}
  local budget = opts.budget or 4000 -- tokens

  local context_parts = {}
  local metadata = {
    chunks_included = 0,
    sources = {},
    deduplicated = 0, -- Track deduplication stats
    query_type = "general",
    query_confidence = 0,
  }

  -- Track seen content for deduplication
  local seen_content = {}

  -- Step 1: Classify query type for adaptive budget
  local query_type, query_confidence = classify_query(query or "")
  metadata.query_type = query_type
  metadata.query_confidence = query_confidence

  -- Step 2: Run BM25 search early to analyze results quality
  local search_results = {}
  if query and query ~= "" then
    search_results = M.search_and_rank(query, {
      limit = 10,
      current_file = opts.current_file,
      project_root = opts.project_root,
      weights = opts.weights,
    })
  end

  -- Step 3: Analyze search results quality
  local results_quality = analyze_results_quality(search_results, query or "")

  -- Step 4: Calculate adaptive budget allocation
  local allocation = calculate_adaptive_budget(query or "", query_type, results_quality, {
    current_file_has_answer = #search_results > 0 and search_results[1] and
      search_results[1].file_path == opts.current_file,
  })
  metadata.budget_allocation = allocation

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

  -- 3. BM25 search results (using results from adaptive budget analysis)
  if #search_results > 0 then
      local search_parts = {}
      local deduped_count = 0

      for _, chunk in ipairs(search_results) do
        local content = chunk.content or ""

        -- Skip if duplicate content
        if is_duplicate_content(content, seen_content) then
          deduped_count = deduped_count + 1
        else
          -- Mark as seen
          local hash = content_hash(content)
          seen_content[hash] = content

          local header = string.format(
            "-- %s %s (%s:%d-%d) [score: %.2f]",
            chunk.type or "chunk",
            chunk.name or "",
            vim.fn.fnamemodify(chunk.file_path or "", ":t"),
            chunk.start_line or 0,
            chunk.end_line or 0,
            chunk.combined_score or 0
          )
          table.insert(search_parts, header .. "\n" .. content)
        end
      end

      if #search_parts > 0 then
        local bm25_budget = math.floor(budget * allocation.bm25_results)
        used_tokens = used_tokens + add_context("Related Code (BM25)", table.concat(search_parts, "\n\n"), bm25_budget)
      end

      metadata.chunks_included = #search_parts
      metadata.deduplicated = (metadata.deduplicated or 0) + deduped_count
      table.insert(metadata.sources, { type = "bm25_search", count = #search_parts, deduped = deduped_count })

      -- 4. Call graph context (15%) - callers and callees of relevant functions
      local call_graph_parts = {}
      local seen_ids = {}
      local call_deduped = 0

      for _, chunk in ipairs(search_results) do
        if #call_graph_parts >= 10 then
          break
        end

        -- Get related functions via call graph
        local related = get_call_graph_context(chunk, {
          max_callers = 2,
          max_callees = 3,
        })

        for _, rel in ipairs(related) do
          if rel.id and not seen_ids[rel.id] then
            seen_ids[rel.id] = true
            local content = rel.content or ""

            -- Check for duplicate content
            if is_duplicate_content(content, seen_content) then
              call_deduped = call_deduped + 1
            else
              local hash = content_hash(content)
              seen_content[hash] = content

              local header = string.format(
                "-- %s %s (%s of %s) [%s:%d]",
                rel.type or "chunk",
                rel.name or "",
                rel.relation or "related",
                chunk.name or "?",
                vim.fn.fnamemodify(rel.file_path or "", ":t"),
                rel.start_line or 0
              )
              table.insert(call_graph_parts, header .. "\n" .. content)
            end
          end
        end
      end

      if #call_graph_parts > 0 then
        local call_budget = math.floor(budget * allocation.call_graph)
        used_tokens = used_tokens + add_context("Related Functions (Call Graph)", table.concat(call_graph_parts, "\n\n"), call_budget)

        metadata.deduplicated = (metadata.deduplicated or 0) + call_deduped
        table.insert(metadata.sources, { type = "call_graph", count = #call_graph_parts, deduped = call_deduped })
      end
  end

  -- 5. Type definitions (type_definitions%) - from adaptive budget
  local type_defs = get_type_context(search_results, {
    max_types = 5,
    project_root = opts.project_root,
  })

  if #type_defs > 0 then
    local type_parts = {}
    local type_deduped = 0

    for _, def in ipairs(type_defs) do
      local content = def.content or ""

      -- Check for duplicate content
      if is_duplicate_content(content, seen_content) then
        type_deduped = type_deduped + 1
      else
        local hash = content_hash(content)
        seen_content[hash] = content

        local header = string.format(
          "-- %s %s (used by %s) [%s:%d]",
          def.type or "type",
          def.name or "",
          def.referenced_by or "?",
          vim.fn.fnamemodify(def.file_path or "", ":t"),
          def.start_line or 0
        )
        table.insert(type_parts, header .. "\n" .. content)
      end
    end

    if #type_parts > 0 then
      local type_budget = math.floor(budget * allocation.type_definitions)
      used_tokens = used_tokens + add_context("Type Definitions", table.concat(type_parts, "\n\n"), type_budget)

      metadata.deduplicated = (metadata.deduplicated or 0) + type_deduped
      table.insert(metadata.sources, { type = "type_definitions", count = #type_parts, deduped = type_deduped })
    end
  end

  -- 6. Import graph
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

  -- 6. Project docs (8%)
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

  -- 7. Diagnostics (4%) - LSP errors/warnings
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
