-- editutor/project_context.lua
-- Project-wide context gathering for better codebase understanding

local M = {}

local lsp_context = require("editutor.lsp_context")

-- Project documentation files to include
M.project_docs = {
  "README.md",
  "README",
  "ARCHITECTURE.md",
  "CONTRIBUTING.md",
  "package.json",
  "pyproject.toml",
  "Cargo.toml",
  "go.mod",
  "pom.xml",
  "build.gradle",
  "composer.json",
  "Gemfile",
  ".editorconfig",
}

-- Cache for project info
M._cache = {
  project_root = nil,
  docs = nil,
  workspace_symbols = nil,
  cached_at = 0,
}

-- Cache TTL in seconds
M.CACHE_TTL = 300 -- 5 minutes

---Check if cache is valid
---@return boolean
local function is_cache_valid()
  return (os.time() - M._cache.cached_at) < M.CACHE_TTL
end

---Get project root
---@return string
function M.get_project_root()
  if M._cache.project_root and is_cache_valid() then
    return M._cache.project_root
  end

  M._cache.project_root = lsp_context.get_project_root()
  return M._cache.project_root
end

---Read project documentation files
---@return table {filename: content}
function M.get_project_docs()
  if M._cache.docs and is_cache_valid() then
    return M._cache.docs
  end

  local root = M.get_project_root()
  local docs = {}

  for _, filename in ipairs(M.project_docs) do
    local filepath = root .. "/" .. filename
    local ok, content = pcall(vim.fn.readfile, filepath)

    if ok and content and #content > 0 then
      local text = table.concat(content, "\n")
      -- Limit size to prevent huge files
      if #text > 2000 then
        text = text:sub(1, 2000) .. "\n...[truncated]"
      end
      docs[filename] = text
    end
  end

  M._cache.docs = docs
  M._cache.cached_at = os.time()

  return docs
end

---Get project summary from docs
---@return string
function M.get_project_summary()
  local docs = M.get_project_docs()
  local parts = {}

  -- README first
  if docs["README.md"] then
    table.insert(parts, "=== Project README ===")
    table.insert(parts, docs["README.md"])
    table.insert(parts, "")
  elseif docs["README"] then
    table.insert(parts, "=== Project README ===")
    table.insert(parts, docs["README"])
    table.insert(parts, "")
  end

  -- Package info
  local pkg_files = { "package.json", "pyproject.toml", "Cargo.toml", "go.mod" }
  for _, pkg in ipairs(pkg_files) do
    if docs[pkg] then
      table.insert(parts, string.format("=== %s ===", pkg))
      table.insert(parts, docs[pkg])
      table.insert(parts, "")
      break -- Only include one
    end
  end

  return table.concat(parts, "\n")
end

---Get LSP references for a symbol at position
---@param bufnr number Buffer number
---@param line number 0-indexed line
---@param col number 0-indexed column
---@param callback function Callback(references)
function M.get_references(bufnr, line, col, callback)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = { line = line, character = col },
    context = { includeDeclaration = false },
  }

  vim.lsp.buf_request(bufnr, "textDocument/references", params, function(err, result)
    if err or not result then
      callback({})
      return
    end

    local references = {}
    local current_file = vim.api.nvim_buf_get_name(bufnr)

    for _, ref in ipairs(result) do
      local filepath = vim.uri_to_fname(ref.uri)

      -- Only include project files, skip current file
      if filepath ~= current_file and lsp_context.is_project_file(filepath) then
        local ref_line = ref.range and ref.range.start and ref.range.start.line or 0
        local content = lsp_context.get_lines_around(filepath, ref_line, 5)

        if content then
          table.insert(references, {
            filepath = filepath,
            line = ref_line,
            content = content,
          })
        end
      end
    end

    -- Limit to 5 references
    if #references > 5 then
      references = vim.list_slice(references, 1, 5)
    end

    callback(references)
  end)
end

---Get workspace symbols matching a query
---@param query string Search query
---@param callback function Callback(symbols)
function M.get_workspace_symbols(query, callback)
  local params = { query = query }

  vim.lsp.buf_request(0, "workspace/symbol", params, function(err, result)
    if err or not result then
      callback({})
      return
    end

    local symbols = {}

    for _, sym in ipairs(result) do
      local filepath = vim.uri_to_fname(sym.location.uri)

      -- Only include project files
      if lsp_context.is_project_file(filepath) then
        table.insert(symbols, {
          name = sym.name,
          kind = vim.lsp.protocol.SymbolKind[sym.kind] or "Unknown",
          filepath = filepath,
          line = sym.location.range.start.line,
        })
      end
    end

    -- Limit results
    if #symbols > 20 then
      symbols = vim.list_slice(symbols, 1, 20)
    end

    callback(symbols)
  end)
end

---Get document symbols (outline) for current buffer
---@param bufnr number
---@param callback function Callback(symbols)
function M.get_document_symbols(bufnr, callback)
  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }

  vim.lsp.buf_request(bufnr, "textDocument/documentSymbol", params, function(err, result)
    if err or not result then
      callback({})
      return
    end

    local symbols = {}

    local function flatten_symbols(items, depth)
      depth = depth or 0
      for _, item in ipairs(items) do
        table.insert(symbols, {
          name = item.name,
          kind = vim.lsp.protocol.SymbolKind[item.kind] or "Unknown",
          line = item.range and item.range.start.line or item.selectionRange.start.line,
          depth = depth,
        })

        -- Recurse into children
        if item.children then
          flatten_symbols(item.children, depth + 1)
        end
      end
    end

    flatten_symbols(result)
    callback(symbols)
  end)
end

---Format document symbols as outline
---@param symbols table
---@return string
function M.format_document_outline(symbols)
  if #symbols == 0 then
    return ""
  end

  local parts = { "=== File Structure ===" }

  for _, sym in ipairs(symbols) do
    local indent = string.rep("  ", sym.depth)
    table.insert(parts, string.format("%s%s (%s) - line %d",
      indent, sym.name, sym.kind, sym.line + 1))
  end

  return table.concat(parts, "\n")
end

---Format references for prompt
---@param references table
---@param symbol_name string
---@return string
function M.format_references(references, symbol_name)
  if #references == 0 then
    return ""
  end

  local root = M.get_project_root()
  local parts = {
    string.format("=== Where '%s' is used ===", symbol_name),
    "",
  }

  for i, ref in ipairs(references) do
    local relative = ref.filepath:gsub(root .. "/", "")
    table.insert(parts, string.format("--- Usage %d: %s (line %d) ---",
      i, relative, ref.line + 1))
    table.insert(parts, "```")
    table.insert(parts, ref.content)
    table.insert(parts, "```")
    table.insert(parts, "")
  end

  return table.concat(parts, "\n")
end

---Get enhanced context with references and project info
---@param opts table {include_refs?: boolean, include_project?: boolean, include_outline?: boolean}
---@param callback function Callback(enhanced_context)
function M.get_enhanced_context(opts, callback)
  opts = opts or {}
  local include_refs = opts.include_refs ~= false
  local include_project = opts.include_project
  local include_outline = opts.include_outline

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1] - 1
  local cursor_col = cursor[2]

  local result = {
    project_summary = "",
    outline = "",
    references = "",
  }

  local pending = 0
  local function check_done()
    if pending == 0 then
      callback(result)
    end
  end

  -- Get project summary
  if include_project then
    result.project_summary = M.get_project_summary()
  end

  -- Get document outline
  if include_outline then
    pending = pending + 1
    M.get_document_symbols(bufnr, function(symbols)
      result.outline = M.format_document_outline(symbols)
      pending = pending - 1
      check_done()
    end)
  end

  -- Get references for symbol under cursor
  if include_refs then
    -- First, get the word under cursor
    local line_content = vim.api.nvim_buf_get_lines(bufnr, cursor_line, cursor_line + 1, false)[1]
    if line_content then
      local word = vim.fn.expand("<cword>")
      if word and word ~= "" then
        pending = pending + 1
        M.get_references(bufnr, cursor_line, cursor_col, function(refs)
          result.references = M.format_references(refs, word)
          pending = pending - 1
          check_done()
        end)
      end
    end
  end

  -- If no async operations, callback immediately
  if pending == 0 then
    callback(result)
  end
end

---Clear cache
function M.clear_cache()
  M._cache = {
    project_root = nil,
    docs = nil,
    workspace_symbols = nil,
    cached_at = 0,
  }
end

return M
