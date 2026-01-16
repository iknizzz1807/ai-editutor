-- editutor/indexer/init.lua
-- Project indexer with BM25 search (FTS5) and multi-signal context ranking
-- No embeddings - uses LSP + Tree-sitter + BM25 for precise context

local M = {}

local db = require("editutor.indexer.db")
local chunker = require("editutor.indexer.chunker")
local ranker = require("editutor.indexer.ranker")

-- State
M._initialized = false
M._indexing = false
M._project_root = nil

-- Configuration
M.config = {
  -- Indexing settings
  batch_size = 50, -- Files per batch
  debounce_ms = 1000, -- Debounce file changes

  -- File patterns
  include_patterns = {
    "%.lua$", "%.py$", "%.js$", "%.ts$", "%.tsx$", "%.jsx$",
    "%.go$", "%.rs$", "%.rb$", "%.java$", "%.c$", "%.cpp$", "%.h$",
    "%.hpp$", "%.cs$", "%.swift$", "%.kt$", "%.scala$",
    "%.vue$", "%.svelte$", "%.php$", "%.ex$", "%.exs$",
  },
  exclude_patterns = {
    "node_modules", "%.git", "vendor", "%.venv", "venv",
    "target", "build", "dist", "__pycache__", "%.cache",
    "%.next", "%.nuxt", "coverage", "%.idea", "%.vscode",
  },

  -- Context limits
  max_chunks_per_file = 100,
  max_chunk_size = 2000, -- Non-whitespace characters
  context_budget = 4000, -- Total tokens for context

  -- Ranking weights
  weights = {
    lsp_definition = 1.0,
    lsp_reference = 0.3,
    bm25_score = 0.5,
    git_recency = 0.2,
    directory_proximity = 0.3,
    import_distance = 0.2,
    recent_access = 0.1,
  },
}

---Initialize the indexer
---@param opts? table Configuration options
---@return boolean success
---@return string|nil error
function M.setup(opts)
  if M._initialized then
    return true, nil
  end

  -- Merge config
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end

  -- Get project root
  M._project_root = M._get_project_root()

  -- Initialize database
  local ok, err = db.init(M._project_root)
  if not ok then
    return false, "Failed to initialize database: " .. (err or "unknown")
  end

  -- Setup autocmds for file watching
  M._setup_autocmds()

  M._initialized = true
  return true, nil
end

---Get project root (git root or cwd)
---@return string
function M._get_project_root()
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
  if git_root and git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    return git_root
  end
  return vim.fn.getcwd()
end

---Setup autocmds for file change detection
function M._setup_autocmds()
  local group = vim.api.nvim_create_augroup("EduTutorIndexer", { clear = true })

  -- Index on file save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      M._on_file_change(ev.file, "save")
    end,
  })

  -- Track file open for recent access
  vim.api.nvim_create_autocmd("BufRead", {
    group = group,
    callback = function(ev)
      M._on_file_open(ev.file)
    end,
  })

  -- Handle file deletion (via NeoTree, etc)
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(ev)
      local filepath = vim.api.nvim_buf_get_name(ev.buf)
      if filepath and filepath ~= "" then
        M._on_file_change(filepath, "delete")
      end
    end,
  })
end

-- Debounce state
local _debounce_timer = nil
local _pending_files = {}

---Handle file change with debouncing
---@param filepath string
---@param change_type string "save"|"delete"|"create"
function M._on_file_change(filepath, change_type)
  if not M._initialized then
    return
  end

  -- Check if file is in project and matches patterns
  if not M._should_index_file(filepath) then
    return
  end

  -- Add to pending queue
  _pending_files[filepath] = change_type

  -- Debounce
  if _debounce_timer then
    vim.fn.timer_stop(_debounce_timer)
  end

  _debounce_timer = vim.fn.timer_start(M.config.debounce_ms, function()
    vim.schedule(function()
      M._process_pending_files()
    end)
  end)
end

---Process pending file changes
function M._process_pending_files()
  if M._indexing then
    return
  end

  local files = _pending_files
  _pending_files = {}

  if vim.tbl_count(files) == 0 then
    return
  end

  M._indexing = true

  for filepath, change_type in pairs(files) do
    if change_type == "delete" then
      db.remove_file(filepath)
    else
      M._index_file(filepath)
    end
  end

  M._indexing = false
end

---Track file open for recent access
---@param filepath string
function M._on_file_open(filepath)
  if not M._initialized then
    return
  end

  if M._should_index_file(filepath) then
    db.mark_accessed(filepath)
  end
end

---Check if file should be indexed
---@param filepath string
---@return boolean
function M._should_index_file(filepath)
  if not filepath or filepath == "" then
    return false
  end

  -- Check if in project
  if not vim.startswith(filepath, M._project_root) then
    return false
  end

  -- Check exclude patterns
  for _, pattern in ipairs(M.config.exclude_patterns) do
    if filepath:match(pattern) then
      return false
    end
  end

  -- Check include patterns
  for _, pattern in ipairs(M.config.include_patterns) do
    if filepath:match(pattern) then
      return true
    end
  end

  return false
end

---Index a single file
---@param filepath string
---@return boolean success
function M._index_file(filepath)
  -- Read file
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return false
  end

  local content = table.concat(lines, "\n")

  -- Check if file changed (hash comparison)
  local hash = vim.fn.sha256(content)
  if db.is_up_to_date(filepath, hash) then
    return true -- Already indexed
  end

  -- Get file info
  local stat = vim.loop.fs_stat(filepath)
  local mtime = stat and stat.mtime.sec or os.time()
  local language = M._detect_language(filepath)

  -- Update file record
  local file_id = db.upsert_file({
    path = filepath,
    hash = hash,
    mtime = mtime,
    language = language,
    line_count = #lines,
  })

  if not file_id then
    return false
  end

  -- Extract chunks using enhanced Tree-sitter chunker (with call graph & type refs)
  local chunks = chunker.extract_chunks_enhanced(filepath, content, {
    language = language,
    max_chunks = M.config.max_chunks_per_file,
    max_chunk_size = M.config.max_chunk_size,
  })

  -- Fallback to basic chunker if enhanced returns empty
  if #chunks == 0 then
    chunks = chunker.extract_chunks(filepath, content, {
      language = language,
      max_chunks = M.config.max_chunks_per_file,
      max_chunk_size = M.config.max_chunk_size,
    })
  end

  -- Remove old chunks for this file
  db.remove_chunks(file_id)

  -- Insert new chunks with enhanced metadata
  for _, chunk in ipairs(chunks) do
    chunk.file_id = file_id
    local chunk_id = db.insert_chunk(chunk)

    -- Store call graph
    if chunk_id and chunk.calls then
      for _, called_name in ipairs(chunk.calls) do
        db.insert_call(chunk_id, called_name)
      end
    end

    -- Store type references
    if chunk_id and chunk.type_refs then
      for _, type_name in ipairs(chunk.type_refs) do
        db.insert_type_ref(chunk_id, type_name)
      end
    end
  end

  -- Extract imports
  local imports = chunker.extract_imports(filepath, content, language)

  -- Remove old imports
  db.remove_imports(file_id)

  -- Insert new imports
  for _, imp in ipairs(imports) do
    imp.file_id = file_id
    db.insert_import(imp)
  end

  return true
end

---Detect language from filepath
---@param filepath string
---@return string
function M._detect_language(filepath)
  local ext_map = {
    lua = "lua",
    py = "python",
    js = "javascript",
    ts = "typescript",
    tsx = "tsx",
    jsx = "jsx",
    go = "go",
    rs = "rust",
    rb = "ruby",
    java = "java",
    c = "c",
    cpp = "cpp",
    h = "c",
    hpp = "cpp",
    cs = "c_sharp",
    swift = "swift",
    kt = "kotlin",
    scala = "scala",
    vue = "vue",
    svelte = "svelte",
    php = "php",
    ex = "elixir",
    exs = "elixir",
  }

  local ext = filepath:match("%.(%w+)$")
  return ext_map[ext] or ext or "unknown"
end

-- =============================================================================
-- Public API
-- =============================================================================

---Index entire project
---@param opts? table {force?: boolean, progress?: function}
---@return boolean success
---@return table stats
function M.index_project(opts)
  opts = opts or {}

  if not M._initialized then
    local ok, err = M.setup()
    if not ok then
      return false, { error = err }
    end
  end

  if M._indexing then
    return false, { error = "Already indexing" }
  end

  M._indexing = true

  local stats = {
    files_scanned = 0,
    files_indexed = 0,
    chunks_created = 0,
    errors = {},
  }

  -- Find all files
  local files = M._find_project_files()
  stats.files_scanned = #files

  -- Index in batches
  for i, filepath in ipairs(files) do
    local ok = M._index_file(filepath)
    if ok then
      stats.files_indexed = stats.files_indexed + 1
    else
      table.insert(stats.errors, filepath)
    end

    -- Progress callback
    if opts.progress then
      opts.progress(i, #files, filepath)
    end
  end

  stats.chunks_created = db.get_chunk_count()
  M._indexing = false

  return true, stats
end

---Find all project files to index
---@return string[]
function M._find_project_files()
  local files = {}

  local function scan_dir(dir)
    local handle = vim.loop.fs_scandir(dir)
    if not handle then
      return
    end

    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end

      local filepath = dir .. "/" .. name

      -- Skip excluded
      local skip = false
      for _, pattern in ipairs(M.config.exclude_patterns) do
        if name:match(pattern) or filepath:match(pattern) then
          skip = true
          break
        end
      end

      if not skip then
        if type == "directory" then
          scan_dir(filepath)
        elseif type == "file" then
          if M._should_index_file(filepath) then
            table.insert(files, filepath)
          end
        end
      end
    end
  end

  scan_dir(M._project_root)
  return files
end

---Search for relevant context
---@param query string Search query (usually the user's question)
---@param opts? table {limit?: number, current_file?: string, cursor_line?: number}
---@return table[] results Ranked list of context chunks
function M.search(query, opts)
  opts = opts or {}

  if not M._initialized then
    M.setup()
  end

  return ranker.search_and_rank(query, {
    limit = opts.limit or 20,
    current_file = opts.current_file,
    cursor_line = opts.cursor_line,
    project_root = M._project_root,
    weights = M.config.weights,
  })
end

---Get context for LLM prompt
---@param opts table {question?: string, current_file?: string, cursor_line?: number, budget?: number}
---@return string formatted_context
---@return table metadata
function M.get_context(opts)
  opts = opts or {}
  local budget = opts.budget or M.config.context_budget

  if not M._initialized then
    M.setup()
  end

  return ranker.build_context(opts.question or "", {
    current_file = opts.current_file,
    cursor_line = opts.cursor_line,
    project_root = M._project_root,
    budget = budget,
    weights = M.config.weights,
  })
end

---Get index statistics
---@return table stats
function M.get_stats()
  if not M._initialized then
    return { initialized = false }
  end

  return db.get_stats()
end

---Clear index and rebuild
---@return boolean success
function M.rebuild()
  if not M._initialized then
    return false
  end

  db.clear_all()
  return M.index_project()
end

---Check if indexer is ready
---@return boolean
function M.is_ready()
  return M._initialized and not M._indexing
end

return M
