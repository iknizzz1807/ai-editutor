-- editutor/lsp_library.lua
-- Fetch library API info via LSP (hover, completion)
-- For enriching context with exact signatures and available methods
-- v3.2: Uses async abstraction for cleaner parallel execution

local M = {}

local project_scanner = require("editutor.project_scanner")
local async = require("editutor.async")

-- =============================================================================
-- Configuration
-- =============================================================================

M.config = {
  scan_radius = 50, -- Lines before/after question block to scan
  max_tokens = 2000, -- Hard cap for library info
  max_methods_per_type = 20, -- Max methods to include per type
  max_identifiers = 15, -- Max identifiers to process
  timeout_ms = 3000, -- Timeout for LSP requests
}

-- Patterns to identify library paths (outside project)
M.LIBRARY_PATTERNS = {
  "node_modules",
  "site%-packages",
  "%.venv",
  "venv",
  "vendor",
  "%.cargo/registry",
  "%.rustup",
  "%.local/lib",
  "%.local/share",
  "/usr/lib",
  "/usr/local/lib",
  "%.luarocks",
  "go/pkg/mod",
}

-- =============================================================================
-- Helper Functions
-- =============================================================================

---Check if LSP is available
---@return boolean
function M.is_lsp_available()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  return #clients > 0
end

---Check if a filepath is a library (outside project)
---@param filepath string
---@param project_root string
---@return boolean
function M.is_library_path(filepath, project_root)
  if not filepath or filepath == "" then
    return false
  end

  -- Check against library patterns
  for _, pattern in ipairs(M.LIBRARY_PATTERNS) do
    if filepath:match(pattern) then
      return true
    end
  end

  -- Check if outside project root
  if project_root and filepath:sub(1, #project_root) ~= project_root then
    return true
  end

  return false
end

---Estimate tokens for text
---@param text string
---@return number
local function estimate_tokens(text)
  if not text then return 0 end
  return math.ceil(#text / 4)
end

---Check if hover text looks like library/std documentation
---@param hover_text string
---@param lang string|nil Language name (e.g., "rust", "go", "python")
---@return boolean
local function looks_like_library_hover(hover_text, lang)
  if not hover_text or hover_text == "" then
    return false
  end

  -- Common patterns across languages suggesting library/API docs
  local common_patterns = {
    "^pub ", -- Rust public items
    "^func ", -- Go functions
    "^type ", -- Go types
    "^package ", -- Go package docs
    "^class ", -- Python/TS classes
    "^def ", -- Python functions
    "^interface ", -- TS/Go interfaces
    "^struct ", -- Go/Rust structs
    "^enum ", -- Rust/TS enums
    "^trait ", -- Rust traits
    "^const ", -- Constants
    "^var ", -- Variables
    "%(method%)", -- Method indicators
    "%(function%)", -- Function indicators
  }

  -- Language-specific patterns
  local lang_patterns = {
    rust = {
      "std::", "core::", "alloc::", "tokio::", "serde::", "async%-std::",
      "pub fn", "pub struct", "pub enum", "pub trait", "pub type", "pub mod",
      "impl%s", "extern crate", "#%[derive",
    },
    go = {
      "^func %(%w+ %*?%w+%)", -- Method receiver
      "^func %w+%(", -- Function
      "package %w+", -- Package reference
      "fmt%.", "io%.", "os%.", "net%.", "http%.", "context%.", "sync%.",
      "encoding%.", "strings%.", "bytes%.", "time%.", "errors%.",
    },
    python = {
      "^def ", "^class ", "^async def ",
      "-> ", "Args:", "Returns:", "Raises:", "Parameters:",
      "numpy%.", "pandas%.", "torch%.", "tensorflow%.",
      "from typing", "Optional%[", "List%[", "Dict%[", "Tuple%[",
    },
    typescript = {
      "^interface ", "^type ", "^class ", "^function ", "^const ", "^enum ",
      "^export ", "^declare ", "^namespace ",
      ": %w+%[%]", ": Promise<", ": Observable<",
    },
    javascript = {
      "^function ", "^class ", "^const ", "^let ", "^var ",
      "Promise%.", "Array%.", "Object%.", "String%.",
    },
    c = {
      "^typedef ", "^struct ", "^enum ", "^union ",
      "#include", "size_t", "void%s*%*", "int%s+%w+%(",
    },
    cpp = {
      "^template", "^class ", "^struct ", "^namespace ",
      "std::", "boost::", "virtual ", "override",
    },
  }

  -- Check common patterns
  for _, pattern in ipairs(common_patterns) do
    if hover_text:match(pattern) then
      return true
    end
  end

  -- Check language-specific patterns
  if lang and lang_patterns[lang] then
    for _, pattern in ipairs(lang_patterns[lang]) do
      if hover_text:match(pattern) then
        return true
      end
    end
  end

  -- Fallback: check all language patterns if lang not specified
  if not lang then
    for _, patterns in pairs(lang_patterns) do
      for _, pattern in ipairs(patterns) do
        if hover_text:match(pattern) then
          return true
        end
      end
    end
  end

  return false
end

---Extract identifiers from lines using tree-sitter
---@param bufnr number
---@param start_line number 0-indexed
---@param end_line number 0-indexed
---@return table[] List of {name, line, col}
function M.extract_identifiers_in_range(bufnr, start_line, end_line)
  local identifiers = {}
  local seen = {}
  local debug_log = require("editutor.debug_log")

  -- Get parser
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    debug_log.log("[LSP_LIB] Tree-sitter parser not available", "DEBUG")
    return identifiers
  end

  local tree = parser:parse()[1]
  if not tree then
    debug_log.log("[LSP_LIB] Tree-sitter parse failed", "DEBUG")
    return identifiers
  end

  local root = tree:root()
  local lang = parser:lang()
  debug_log.log(string.format("[LSP_LIB] Language: %s", lang), "DEBUG")

  -- Query for identifiers
  local query_string = "(identifier) @id"

  -- Language-specific queries
  if lang == "lua" then
    query_string = "[(identifier) (dot_index_expression)] @id"
  elseif lang == "python" then
    query_string = "[(identifier) (attribute)] @id"
  elseif lang == "javascript" or lang == "typescript" or lang == "tsx" then
    query_string = "[(identifier) (property_identifier) (member_expression)] @id"
  elseif lang == "go" then
    query_string = "[(identifier) (selector_expression)] @id"
  elseif lang == "rust" then
    query_string = "[(identifier) (field_expression)] @id"
  end

  local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if not ok_query or not query then
    debug_log.log(string.format("[LSP_LIB] Query parse failed for %s: %s", lang, query_string), "DEBUG")
    return identifiers
  end

  for _, node in query:iter_captures(root, bufnr, start_line, end_line + 1) do
    local row, col = node:start()

    -- Only include nodes in our range
    if row >= start_line and row <= end_line then
      local name = vim.treesitter.get_node_text(node, bufnr)

      -- Skip short names and duplicates
      if name and #name > 1 and not seen[name] then
        seen[name] = true
        table.insert(identifiers, {
          name = name,
          line = row,
          col = col,
        })
      end
    end
  end

  return identifiers
end

---Parse question text to find mentioned identifiers
---@param question_text string
---@return string[] List of potential identifier names
function M.parse_question_for_identifiers(question_text)
  local identifiers = {}
  local seen = {}

  -- Match patterns like: module.method, ClassName, function_name
  -- Pattern: word characters with dots (e.g., pd.DataFrame, requests.get)
  for match in question_text:gmatch("[%w_]+%.[%w_%.]+") do
    if not seen[match] then
      seen[match] = true
      table.insert(identifiers, match)
    end
  end

  -- Also match standalone identifiers that look like class/function names
  for match in question_text:gmatch("[A-Z][%w_]+") do
    if not seen[match] then
      seen[match] = true
      table.insert(identifiers, match)
    end
  end

  return identifiers
end

-- =============================================================================
-- LSP Request Functions
-- =============================================================================

---Get hover info for a position (async version)
---Must be called from within an async context
---@param bufnr number
---@param line number 0-indexed
---@param col number 0-indexed
---@param timeout_ms? number Optional timeout (default: config.timeout_ms)
---@return string|nil hover_text, string|nil error
function M.get_hover_async(bufnr, line, col, timeout_ms)
  timeout_ms = timeout_ms or M.config.timeout_ms
  local hover_text = async.lsp_hover(bufnr, line, col, timeout_ms)
  return hover_text, nil
end

---Get hover info for a position (callback version)
---@param bufnr number
---@param line number 0-indexed
---@param col number 0-indexed
---@param callback function(hover_text: string|nil, error: string|nil)
function M.get_hover(bufnr, line, col, callback)
  async.run(function()
    local hover_text, err = M.get_hover_async(bufnr, line, col)
    async.scheduler()
    callback(hover_text, err)
  end)
end

---Get definition location to check if it's a library (async version)
---Must be called from within an async context
---@param bufnr number
---@param line number 0-indexed
---@param col number 0-indexed
---@param timeout_ms? number Optional timeout (default: config.timeout_ms)
---@return string|nil filepath, boolean is_library
function M.get_definition_location_async(bufnr, line, col, timeout_ms)
  timeout_ms = timeout_ms or M.config.timeout_ms
  local debug_log = require("editutor.debug_log")
  local project_root = project_scanner.get_project_root()

  local locations = async.lsp_definition(bufnr, line, col, timeout_ms)

  if not locations or #locations == 0 then
    debug_log.log("[LSP_LIB] Definition result is nil or empty", "DEBUG")
    return nil, false
  end

  -- Get first location
  local first = locations[1]
  if not first or not first.uri then
    debug_log.log("[LSP_LIB] Could not extract URI from result", "DEBUG")
    return nil, false
  end

  debug_log.log(string.format("[LSP_LIB] Extracted URI: %s", first.uri), "DEBUG")

  local filepath = vim.uri_to_fname(first.uri)
  local is_library = M.is_library_path(filepath, project_root)

  return filepath, is_library
end

---Get definition location to check if it's a library (callback version)
---@param bufnr number
---@param line number 0-indexed
---@param col number 0-indexed
---@param callback function(filepath: string|nil, is_library: boolean)
function M.get_definition_location(bufnr, line, col, callback)
  async.run(function()
    local filepath, is_library = M.get_definition_location_async(bufnr, line, col)
    async.scheduler()
    callback(filepath, is_library)
  end)
end

-- =============================================================================
-- Main Extraction Function
-- =============================================================================

---@class LibraryInfo
---@field identifier string The identifier name
---@field type string|nil The type (if known)
---@field hover string|nil Hover documentation
---@field methods table[]|nil Available methods
---@field source string "hover"|"completion"|"both"
---@field error string|nil Error message if failed

---@class LibraryInfoResult
---@field items LibraryInfo[]
---@field total_tokens number
---@field errors string[]

---Extract library info for identifiers around question block
---@param bufnr number Buffer number
---@param question_start_line number 0-indexed line where question block starts
---@param question_end_line number 0-indexed line where question block ends
---@param question_text string The question text (to parse for mentioned identifiers)
---@param callback function(result: LibraryInfoResult)
---Process a single identifier to extract library info (async helper)
---@param bufnr number
---@param ident table {name, line, col}
---@param lang string|nil Language for pattern matching
---@return table|nil info Library info or nil if not a library
local function process_identifier_async(bufnr, ident, lang)
  local debug_log = require("editutor.debug_log")

  -- Skip if no position
  if not ident.line then
    return nil
  end

  -- Get definition location
  local def_path, is_library = M.get_definition_location_async(bufnr, ident.line, ident.col)

  if is_library then
    -- Confirmed library, fetch hover info
    debug_log.log(string.format("[LSP_LIB] %s: IS library (path=%s)", ident.name, tostring(def_path)), "DEBUG")
    local hover_text = M.get_hover_async(bufnr, ident.line, ident.col)

    if hover_text then
      local tokens = estimate_tokens(hover_text)
      debug_log.log(string.format("[LSP_LIB] %s: hover found (%d tokens)", ident.name, tokens), "DEBUG")
      return {
        identifier = ident.name,
        hover = hover_text,
        source = "hover",
        tokens = tokens,
      }
    end
  elseif def_path == nil then
    -- No definition path - try hover fallback
    debug_log.log(string.format("[LSP_LIB] %s: no def path, trying hover fallback", ident.name), "DEBUG")
    local hover_text = M.get_hover_async(bufnr, ident.line, ident.col)

    if hover_text then
      local is_std_or_lib = looks_like_library_hover(hover_text, lang)
      if is_std_or_lib then
        debug_log.log(string.format("[LSP_LIB] %s: detected as lib via hover content", ident.name), "DEBUG")
        local tokens = estimate_tokens(hover_text)
        return {
          identifier = ident.name,
          hover = hover_text,
          source = "hover",
          tokens = tokens,
        }
      else
        debug_log.log(string.format("[LSP_LIB] %s: hover doesn't look like lib", ident.name), "DEBUG")
      end
    end
  else
    debug_log.log(string.format("[LSP_LIB] %s: not library (path=%s)", ident.name, tostring(def_path)), "DEBUG")
  end

  return nil
end

---Extract library info for identifiers (async version)
---Must be called from within an async context
---@param bufnr number Buffer number
---@param question_start_line number 0-indexed
---@param question_end_line number 0-indexed
---@param question_text string
---@param opts? table {timeout_ms?: number}
---@return LibraryInfoResult
function M.extract_library_info_async(bufnr, question_start_line, question_end_line, question_text, opts)
  opts = opts or {}
  local timeout_ms = opts.timeout_ms or 15000
  local debug_log = require("editutor.debug_log")

  local result = {
    items = {},
    total_tokens = 0,
    errors = {},
  }

  if not M.is_lsp_available() then
    table.insert(result.errors, "LSP not available")
    return result
  end

  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local scan_start = math.max(0, question_start_line - M.config.scan_radius)
  local scan_end = math.min(total_lines - 1, question_end_line + M.config.scan_radius)

  debug_log.log(string.format("[LSP_LIB] Scan range: %d-%d (total: %d lines)", scan_start, scan_end, total_lines), "DEBUG")

  -- Extract identifiers
  local code_identifiers = M.extract_identifiers_in_range(bufnr, scan_start, scan_end)
  local question_identifiers = M.parse_question_for_identifiers(question_text)

  debug_log.log(string.format("[LSP_LIB] Code identifiers: %d, Question identifiers: %d",
    #code_identifiers, #question_identifiers), "DEBUG")

  -- Combine and deduplicate
  local all_identifiers = {}
  local seen = {}

  for _, name in ipairs(question_identifiers) do
    if not seen[name] then
      seen[name] = true
      local found = false
      for _, ident in ipairs(code_identifiers) do
        if ident.name:match(name) or name:match(ident.name) then
          table.insert(all_identifiers, ident)
          found = true
          break
        end
      end
      if not found then
        table.insert(all_identifiers, { name = name, line = nil, col = nil, from_question = true })
      end
    end
  end

  for _, ident in ipairs(code_identifiers) do
    if not seen[ident.name] and #all_identifiers < M.config.max_identifiers then
      seen[ident.name] = true
      table.insert(all_identifiers, ident)
    end
  end

  if #all_identifiers > M.config.max_identifiers then
    all_identifiers = vim.list_slice(all_identifiers, 1, M.config.max_identifiers)
  end

  debug_log.log(string.format("[LSP_LIB] Total identifiers to process: %d", #all_identifiers), "DEBUG")

  if #all_identifiers == 0 then
    return result
  end

  -- Get language for pattern matching
  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr)
  local lang = ok_parser and parser and parser:lang() or nil

  -- Create tasks for parallel execution
  local tasks = {}
  for _, ident in ipairs(all_identifiers) do
    table.insert(tasks, function()
      return process_identifier_async(bufnr, ident, lang)
    end)
  end

  -- Execute in parallel with timeout
  local results, meta = async.parallel_limited(tasks, {
    max_concurrent = 5,
    timeout_ms = timeout_ms,
  })

  if meta.timed_out then
    table.insert(result.errors, "Library info extraction timeout")
  end

  -- Collect results respecting token budget
  local lib_found = 0
  for _, info in pairs(results) do
    if info and info.hover then
      lib_found = lib_found + 1
      if result.total_tokens + info.tokens <= M.config.max_tokens then
        result.total_tokens = result.total_tokens + info.tokens
        table.insert(result.items, info)
      end
    end
  end

  debug_log.log(string.format("[LSP_LIB] Complete: lib_found=%d, items=%d, tokens=%d",
    lib_found, #result.items, result.total_tokens), "DEBUG")

  return result
end

---Extract library info for identifiers (callback version)
---@param bufnr number Buffer number
---@param question_start_line number 0-indexed line where question block starts
---@param question_end_line number 0-indexed line where question block ends
---@param question_text string The question text (to parse for mentioned identifiers)
---@param callback function(result: LibraryInfoResult)
function M.extract_library_info(bufnr, question_start_line, question_end_line, question_text, callback)
  async.run(function()
    local result = M.extract_library_info_async(bufnr, question_start_line, question_end_line, question_text)
    async.scheduler()
    callback(result)
  end)
end

-- =============================================================================
-- Formatting
-- =============================================================================

---Format library info for inclusion in prompt
---@param info_result LibraryInfoResult
---@return string formatted
---@return table metadata
function M.format_for_prompt(info_result)
  if not info_result or #info_result.items == 0 then
    return "", { items = 0, tokens = 0 }
  end

  local parts = {}
  table.insert(parts, "=== LIBRARY API INFO ===")
  table.insert(parts, "")

  for _, item in ipairs(info_result.items) do
    table.insert(parts, string.format("[%s]", item.identifier))

    if item.hover then
      -- Clean up hover text (remove markdown code blocks if present)
      local hover_clean = item.hover
        :gsub("```%w*\n", "")
        :gsub("\n```", "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")

      -- Truncate if too long
      if #hover_clean > 500 then
        hover_clean = hover_clean:sub(1, 500) .. "..."
      end

      table.insert(parts, hover_clean)
    end

    if item.methods and #item.methods > 0 then
      table.insert(parts, "Available methods:")
      for _, method in ipairs(item.methods) do
        local method_str = "  - " .. method.name
        if method.detail and method.detail ~= "" then
          method_str = method_str .. ": " .. method.detail
        end
        table.insert(parts, method_str)
      end
    end

    table.insert(parts, "")
  end

  -- Add errors note if any
  if #info_result.errors > 0 then
    table.insert(parts, "Note: Some library info unavailable:")
    for _, err in ipairs(info_result.errors) do
      table.insert(parts, "  - " .. err)
    end
    table.insert(parts, "")
  end

  local formatted = table.concat(parts, "\n")

  return formatted, {
    items = #info_result.items,
    tokens = info_result.total_tokens,
    errors = #info_result.errors,
  }
end

return M
