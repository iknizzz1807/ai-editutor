-- editutor/lsp_library.lua
-- Fetch library API info via LSP (hover, completion)
-- For enriching context with exact signatures and available methods

local M = {}

local project_scanner = require("editutor.project_scanner")

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

---Extract identifiers from lines using tree-sitter
---@param bufnr number
---@param start_line number 0-indexed
---@param end_line number 0-indexed
---@return table[] List of {name, line, col}
function M.extract_identifiers_in_range(bufnr, start_line, end_line)
  local identifiers = {}
  local seen = {}

  -- Get parser
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return identifiers
  end

  local tree = parser:parse()[1]
  if not tree then
    return identifiers
  end

  local root = tree:root()
  local lang = parser:lang()

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

---Get hover info for a position
---@param bufnr number
---@param line number 0-indexed
---@param col number 0-indexed
---@param callback function(hover_text: string|nil, error: string|nil)
function M.get_hover(bufnr, line, col, callback)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = { line = line, character = col },
  }

  local request_sent = false

  -- Set timeout
  local timer = vim.defer_fn(function()
    if not request_sent then
      callback(nil, "timeout")
    end
  end, M.config.timeout_ms)

  vim.lsp.buf_request(bufnr, "textDocument/hover", params, function(err, result)
    request_sent = true
    if timer then
      pcall(vim.fn.timer_stop, timer)
    end

    if err then
      callback(nil, tostring(err))
      return
    end

    if not result or not result.contents then
      callback(nil, nil) -- No error, just no info
      return
    end

    -- Extract text from hover result
    local hover_text
    if type(result.contents) == "string" then
      hover_text = result.contents
    elseif type(result.contents) == "table" then
      if result.contents.value then
        hover_text = result.contents.value
      elseif result.contents.kind then
        hover_text = result.contents.value or ""
      else
        -- Array of contents
        local parts = {}
        for _, content in ipairs(result.contents) do
          if type(content) == "string" then
            table.insert(parts, content)
          elseif content.value then
            table.insert(parts, content.value)
          end
        end
        hover_text = table.concat(parts, "\n")
      end
    end

    callback(hover_text, nil)
  end)
end

---Get definition location to check if it's a library
---@param bufnr number
---@param line number 0-indexed
---@param col number 0-indexed
---@param callback function(filepath: string|nil, is_library: boolean)
function M.get_definition_location(bufnr, line, col, callback)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = { line = line, character = col },
  }

  local project_root = project_scanner.get_project_root()
  local callback_called = false

  -- Timeout handler
  local timer = vim.defer_fn(function()
    if not callback_called then
      callback_called = true
      callback(nil, false)
    end
  end, M.config.timeout_ms)

  vim.lsp.buf_request(bufnr, "textDocument/definition", params, function(err, result)
    if callback_called then return end
    callback_called = true

    if timer then
      pcall(vim.fn.timer_stop, timer)
    end

    if err or not result then
      callback(nil, false)
      return
    end

    -- Get first definition location
    local uri
    if result.uri then
      uri = result.uri
    elseif result.targetUri then
      uri = result.targetUri
    elseif type(result) == "table" and #result > 0 then
      uri = result[1].uri or result[1].targetUri
    end

    if not uri then
      callback(nil, false)
      return
    end

    local filepath = vim.uri_to_fname(uri)
    local is_library = M.is_library_path(filepath, project_root)

    callback(filepath, is_library)
  end)
end

---Get completion items at position (for listing available methods)
---@param bufnr number
---@param line number 0-indexed
---@param col number 0-indexed
---@param callback function(items: table[]|nil)
function M.get_completion_items(bufnr, line, col, callback)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = { line = line, character = col },
    context = {
      triggerKind = 1, -- Invoked
    },
  }

  local timer = vim.defer_fn(function()
    callback(nil)
  end, M.config.timeout_ms)

  vim.lsp.buf_request(bufnr, "textDocument/completion", params, function(err, result)
    if timer then
      pcall(vim.fn.timer_stop, timer)
    end

    if err or not result then
      callback(nil)
      return
    end

    local items = result.items or result
    if not items or #items == 0 then
      callback(nil)
      return
    end

    -- Extract method info
    local methods = {}
    for i, item in ipairs(items) do
      if i > M.config.max_methods_per_type then
        break
      end

      local kind = item.kind
      -- Filter to functions/methods (kind 2=Method, 3=Function, 6=Variable)
      if kind == 2 or kind == 3 or kind == 6 then
        table.insert(methods, {
          name = item.label,
          detail = item.detail or "",
          documentation = item.documentation and
              (type(item.documentation) == "string" and item.documentation or item.documentation.value) or nil,
        })
      end
    end

    callback(methods)
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
function M.extract_library_info(bufnr, question_start_line, question_end_line, question_text, callback)
  local result = {
    items = {},
    total_tokens = 0,
    errors = {},
  }

  local callback_called = false
  local overall_timeout_ms = 15000 -- 15 second overall timeout

  -- Overall timeout handler
  vim.defer_fn(function()
    if not callback_called then
      callback_called = true
      table.insert(result.errors, "Library info extraction timeout")
      callback(result)
    end
  end, overall_timeout_ms)

  if not M.is_lsp_available() then
    if not callback_called then
      callback_called = true
      table.insert(result.errors, "LSP not available")
      callback(result)
    end
    return
  end

  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  -- Calculate scan range (±50 lines around question block)
  local scan_start = math.max(0, question_start_line - M.config.scan_radius)
  local scan_end = math.min(total_lines - 1, question_end_line + M.config.scan_radius)

  -- Extract identifiers from code around question
  local code_identifiers = M.extract_identifiers_in_range(bufnr, scan_start, scan_end)

  -- Parse question text for mentioned identifiers
  local question_identifiers = M.parse_question_for_identifiers(question_text)

  -- Combine and deduplicate
  local all_identifiers = {}
  local seen = {}

  -- Prioritize identifiers mentioned in question
  for _, name in ipairs(question_identifiers) do
    if not seen[name] then
      seen[name] = true
      -- Find position in code if possible
      local found = false
      for _, ident in ipairs(code_identifiers) do
        if ident.name:match(name) or name:match(ident.name) then
          table.insert(all_identifiers, ident)
          found = true
          break
        end
      end
      if not found then
        -- Add without position (will skip LSP lookup)
        table.insert(all_identifiers, { name = name, line = nil, col = nil, from_question = true })
      end
    end
  end

  -- Add code identifiers
  for _, ident in ipairs(code_identifiers) do
    if not seen[ident.name] and #all_identifiers < M.config.max_identifiers then
      seen[ident.name] = true
      table.insert(all_identifiers, ident)
    end
  end

  -- Limit total identifiers
  if #all_identifiers > M.config.max_identifiers then
    all_identifiers = vim.list_slice(all_identifiers, 1, M.config.max_identifiers)
  end

  if #all_identifiers == 0 then
    if not callback_called then
      callback_called = true
      callback(result)
    end
    return
  end

  -- Process each identifier
  local pending = #all_identifiers
  local completed = 0

  local function check_complete()
    if completed >= pending and not callback_called then
      callback_called = true
      callback(result)
    end
  end

  for _, ident in ipairs(all_identifiers) do
    if callback_called then return end

    -- Skip if no position (from question text only, not found in code)
    if not ident.line then
      completed = completed + 1
      check_complete()
      goto continue
    end

    -- First check if it's a library
    M.get_definition_location(bufnr, ident.line, ident.col, function(def_path, is_library)
      if callback_called then return end

      if not is_library then
        -- Not a library, skip
        completed = completed + 1
        check_complete()
        return
      end

      -- It's a library! Fetch hover info
      M.get_hover(bufnr, ident.line, ident.col, function(hover_text, hover_err)
        if callback_called then return end

        local info = {
          identifier = ident.name,
          hover = hover_text,
          source = hover_text and "hover" or nil,
          error = hover_err,
        }

        if hover_text then
          local tokens = estimate_tokens(hover_text)

          -- Check token budget
          if result.total_tokens + tokens <= M.config.max_tokens then
            result.total_tokens = result.total_tokens + tokens
            table.insert(result.items, info)
          end
        elseif hover_err then
          table.insert(result.errors, string.format("%s: %s", ident.name, hover_err))
        end

        completed = completed + 1
        check_complete()
      end)
    end)

    ::continue::
  end

  -- Handle case where all identifiers were skipped
  check_complete()
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
