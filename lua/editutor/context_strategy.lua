-- editutor/context_strategy.lua
-- Smart backtracking strategy for fitting context into token budget
-- Never fails - always returns best possible context within budget

local M = {}

local config = require("editutor.config")
local project_scanner = require("editutor.project_scanner")
local import_graph = require("editutor.import_graph")
local semantic_chunking = require("editutor.semantic_chunking")
local relevance_scorer = require("editutor.relevance_scorer")
local cache = require("editutor.cache")

-- =============================================================================
-- Configuration
-- =============================================================================

M.DEFAULT_BUDGET = 25000

-- Backtracking levels - from maximum context to minimal
-- Each level reduces context until it fits budget
M.LEVELS = {
  {
    name = "maximum",
    description = "Full files, depth 2, with LSP",
    import_depth = 2,
    lsp = true,
    chunking = "full",
    max_import_files = 50,
    max_lsp_files = 30,
    chunking_threshold = 9999, -- Never chunk (full files)
  },
  {
    name = "semantic_all",
    description = "Semantic chunking for large files, depth 2, with LSP",
    import_depth = 2,
    lsp = true,
    chunking = "semantic",
    max_import_files = 50,
    max_lsp_files = 30,
    chunking_threshold = 300,
  },
  {
    name = "depth1_with_lsp",
    description = "Depth 1 only, with LSP, semantic chunking",
    import_depth = 1,
    lsp = true,
    chunking = "semantic",
    max_import_files = 30,
    max_lsp_files = 20,
    chunking_threshold = 200,
  },
  {
    name = "depth1_no_lsp",
    description = "Depth 1 only, no LSP, semantic chunking",
    import_depth = 1,
    lsp = false,
    chunking = "semantic",
    max_import_files = 20,
    chunking_threshold = 150,
  },
  {
    name = "limited_imports",
    description = "Top 10 imports by relevance, no LSP",
    import_depth = 1,
    lsp = false,
    chunking = "semantic",
    max_import_files = 10,
    chunking_threshold = 100,
  },
  {
    name = "types_only",
    description = "Only type definition files",
    import_depth = 1,
    lsp = false,
    chunking = "types_only",
    max_import_files = 10,
    types_only = true,
    chunking_threshold = 100,
  },
  {
    name = "minimal",
    description = "Current file only, no imports",
    import_depth = 0,
    lsp = false,
    chunking = "none",
    max_import_files = 0,
  },
}

-- =============================================================================
-- Helper Functions
-- =============================================================================

---Read file content
---@param filepath string
---@return string|nil content
---@return number line_count
local function read_file(filepath)
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return nil, 0
  end
  return table.concat(lines, "\n"), #lines
end

---Get display path (project_name/relative_path)
---@param filepath string
---@param project_root string
---@return string
local function get_display_path(filepath, project_root)
  local root_name = vim.fn.fnamemodify(project_root, ":t")
  if filepath:sub(1, #project_root) == project_root then
    return root_name .. "/" .. filepath:sub(#project_root + 2)
  end
  return root_name .. "/" .. vim.fn.fnamemodify(filepath, ":t")
end

---Get file content based on chunking mode and threshold
---@param filepath string
---@param level table Current strategy level
---@return string|nil content
---@return table metadata
local function get_file_content_for_level(filepath, level)
  local chunking_mode = level.chunking or "semantic"
  local threshold = level.chunking_threshold or 300

  return semantic_chunking.get_file_content(filepath, {
    threshold = threshold,
    mode = chunking_mode,
    max_tokens = 2000,
  })
end

-- =============================================================================
-- Import Graph with Depth Support
-- =============================================================================

---Get import files with configurable depth
---@param current_file string
---@param project_root string
---@param depth number 0, 1, or 2
---@return table[] List of {path, relationship, depth}
local function get_imports_with_depth(current_file, project_root, depth)
  if depth == 0 then
    return {}
  end

  local graph = import_graph.get_import_graph(current_file, project_root)
  local result = {}
  local seen = { [current_file] = true }

  -- Depth 1: direct imports
  for _, filepath in ipairs(graph.outgoing) do
    if not seen[filepath] then
      seen[filepath] = true
      table.insert(result, {
        path = filepath,
        relationship = "outgoing",
        depth = 1,
      })
    end
  end

  for _, filepath in ipairs(graph.incoming) do
    if not seen[filepath] then
      seen[filepath] = true
      table.insert(result, {
        path = filepath,
        relationship = "incoming",
        depth = 1,
      })
    end
  end

  -- Depth 2: imports of imports
  if depth >= 2 then
    local depth1_files = vim.deepcopy(result)
    for _, file_info in ipairs(depth1_files) do
      local sub_graph = import_graph.get_import_graph(file_info.path, project_root)

      for _, filepath in ipairs(sub_graph.outgoing) do
        if not seen[filepath] then
          seen[filepath] = true
          table.insert(result, {
            path = filepath,
            relationship = "transitive",
            depth = 2,
            via = file_info.path,
          })
        end
      end
    end
  end

  return result
end

-- =============================================================================
-- LSP Definitions (using new semantic extraction)
-- =============================================================================

---Get LSP definitions with definition-only extraction
---@param bufnr number
---@param callback function
---@param opts table
local function get_lsp_definitions(bufnr, callback, opts)
  local lsp_context = require("editutor.lsp_context")

  if not lsp_context.is_available() then
    callback({})
    return
  end

  local current_file = vim.api.nvim_buf_get_name(bufnr)
  local identifiers = lsp_context.extract_all_identifiers(bufnr)

  local definitions = {}
  local seen_files = {}
  local pending = #identifiers
  local completed = 0
  local max_files = opts.max_files or 30
  local callback_called = false
  local timeout_ms = opts.timeout or 10000 -- 10 second timeout for LSP definitions

  if pending == 0 then
    callback({})
    return
  end

  -- Timeout handler to prevent hanging forever
  vim.defer_fn(function()
    if not callback_called then
      callback_called = true
      callback(definitions) -- Return whatever we have so far
    end
  end, timeout_ms)

  for _, ident in ipairs(identifiers) do
    if callback_called then
      return -- Already timed out
    end

    if vim.tbl_count(seen_files) >= max_files then
      completed = completed + 1
      if completed >= pending and not callback_called then
        callback_called = true
        callback(definitions)
      end
      goto continue
    end

    lsp_context.get_definition(bufnr, ident.line, ident.col, function(locations)
      if callback_called then
        return -- Already timed out or completed
      end

      completed = completed + 1

      for _, loc in ipairs(locations) do
        local filepath = vim.uri_to_fname(loc.uri)

        if
          filepath ~= current_file
          and not seen_files[filepath]
          and lsp_context.is_project_file(filepath)
          and vim.tbl_count(seen_files) < max_files
        then
          seen_files[filepath] = true

          -- Extract only the definition, not the whole file
          local def_line = loc.range and loc.range.start and loc.range.start.line or 0
          local def_col = loc.range and loc.range.start and loc.range.start.character or 0

          local content, metadata =
            semantic_chunking.extract_definition_at(filepath, def_line, def_col)

          if content then
            table.insert(definitions, {
              name = ident.name,
              filepath = filepath,
              content = content,
              line = def_line,
              col = def_col,
              metadata = metadata,
              tokens = project_scanner.estimate_tokens(content),
            })
          end
        end
      end

      if completed >= pending and not callback_called then
        callback_called = true
        callback(definitions)
      end
    end)

    ::continue::
  end
end

-- =============================================================================
-- Context Building
-- =============================================================================

---Build context for a specific strategy level
---@param current_file string
---@param project_root string
---@param level table Strategy level configuration
---@param budget number Token budget
---@param callback function Callback(context, tokens, metadata)
local function build_context_for_level(current_file, project_root, level, budget, callback)
  local parts = {}
  local total_tokens = 0
  local files_metadata = {}

  local display_current = get_display_path(current_file, project_root)

  -- 1. Current file (always full)
  local current_content, current_lines = read_file(current_file)
  if not current_content then
    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    current_content = table.concat(buf_lines, "\n")
    current_lines = #buf_lines
  end

  local ext = current_file:match("%.([^.]+)$") or ""
  local language = project_scanner.get_language_for_ext(ext)
  local current_tokens = project_scanner.estimate_tokens(current_content)

  table.insert(parts, "=== CURRENT FILE (contains questions) ===")
  table.insert(parts, string.format("// File: %s", display_current))
  table.insert(parts, "```" .. language)
  table.insert(parts, current_content)
  table.insert(parts, "```")
  table.insert(parts, "")

  total_tokens = total_tokens + current_tokens
  table.insert(files_metadata, {
    path = display_current,
    tokens = current_tokens,
    lines = current_lines,
    source = "current",
    mode = "full",
  })

  -- Check if current file alone exceeds budget
  if total_tokens > budget then
    callback(table.concat(parts, "\n"), total_tokens, {
      level = level.name,
      files = files_metadata,
      warning = "current_file_exceeds_budget",
    })
    return
  end

  -- 2. Project tree (reserve ~5% of budget, max 1000 tokens)
  local tree_budget = math.min(budget * 0.05, 1000)
  local scan_result = cache.get_project(project_root, function()
    return project_scanner.scan_project({ root = project_root })
  end)

  local tree_content = scan_result.tree_structure
  local tree_tokens = project_scanner.estimate_tokens(tree_content)

  -- Truncate tree if needed
  if tree_tokens > tree_budget then
    local tree_lines = vim.split(tree_content, "\n")
    local max_lines = math.floor(#tree_lines * (tree_budget / tree_tokens))
    tree_lines = vim.list_slice(tree_lines, 1, max_lines)
    tree_content = table.concat(tree_lines, "\n") .. "\n... (truncated)"
    tree_tokens = project_scanner.estimate_tokens(tree_content)
  end

  local remaining_budget = budget - total_tokens - tree_tokens

  -- 3. Import files
  local import_files = {}
  if level.import_depth > 0 then
    import_files = get_imports_with_depth(current_file, project_root, level.import_depth)

    -- Score and sort by relevance
    import_files = relevance_scorer.score_and_sort(import_files, current_file)

    -- Filter to types only if specified
    if level.types_only then
      import_files = vim.tbl_filter(function(f)
        return relevance_scorer.is_type_file(f.path)
      end, import_files)
    end

    -- Limit number of files
    if level.max_import_files and #import_files > level.max_import_files then
      import_files = vim.list_slice(import_files, 1, level.max_import_files)
    end
  end

  -- Track included files for LSP deduplication
  local included_files = { [current_file] = true }

  -- Add import files within budget
  local import_parts = {}
  local import_tokens = 0
  local import_budget = remaining_budget * 0.7 -- 70% for imports

  for _, file_info in ipairs(import_files) do
    local filepath = file_info.path
    included_files[filepath] = true

    local content, metadata = get_file_content_for_level(filepath, level)
    if content then
      local file_tokens = project_scanner.estimate_tokens(content)

      if import_tokens + file_tokens <= import_budget then
        local file_ext = filepath:match("%.([^.]+)$") or ""
        local file_lang = project_scanner.get_language_for_ext(file_ext)
        local file_display = get_display_path(filepath, project_root)

        local relationship_str = file_info.relationship or "related"
        if file_info.depth == 2 then
          relationship_str = "transitive via " .. get_display_path(file_info.via or "", project_root)
        end

        local mode_str = metadata.mode or "unknown"
        table.insert(
          import_parts,
          string.format("// File: %s (%s, %s)", file_display, relationship_str, mode_str)
        )
        table.insert(import_parts, "```" .. file_lang)
        table.insert(import_parts, content)
        table.insert(import_parts, "```")
        table.insert(import_parts, "")

        import_tokens = import_tokens + file_tokens
        table.insert(files_metadata, {
          path = file_display,
          tokens = file_tokens,
          lines = metadata.lines or metadata.original_lines,
          source = "import",
          relationship = file_info.relationship,
          depth = file_info.depth,
          mode = mode_str,
          relevance_score = file_info.relevance_score,
        })
      end
    end
  end

  if #import_parts > 0 then
    table.insert(parts, string.format("=== RELATED FILES (imports, %d files) ===", #files_metadata - 1))
    table.insert(parts, "")
    for _, part in ipairs(import_parts) do
      table.insert(parts, part)
    end
  end

  total_tokens = total_tokens + import_tokens

  -- 4. LSP definitions (if enabled and budget allows)
  local lsp_budget = remaining_budget - import_tokens

  if level.lsp and lsp_budget > 500 then
    local bufnr = vim.api.nvim_get_current_buf()

    get_lsp_definitions(bufnr, function(definitions)
      local lsp_parts = {}
      local lsp_tokens = 0
      local lsp_count = 0

      for _, def in ipairs(definitions) do
        if not included_files[def.filepath] then
          if lsp_tokens + def.tokens <= lsp_budget then
            included_files[def.filepath] = true

            local file_ext = def.filepath:match("%.([^.]+)$") or ""
            local file_lang = project_scanner.get_language_for_ext(file_ext)
            local file_display = get_display_path(def.filepath, project_root)

            local mode_str = def.metadata and def.metadata.mode or "definition"
            table.insert(
              lsp_parts,
              string.format("// Definition: %s in %s (%s)", def.name, file_display, mode_str)
            )
            table.insert(lsp_parts, "```" .. file_lang)
            table.insert(lsp_parts, def.content)
            table.insert(lsp_parts, "```")
            table.insert(lsp_parts, "")

            lsp_tokens = lsp_tokens + def.tokens
            lsp_count = lsp_count + 1

            table.insert(files_metadata, {
              path = file_display,
              tokens = def.tokens,
              source = "lsp",
              symbol = def.name,
              mode = mode_str,
            })
          end
        end
      end

      if #lsp_parts > 0 then
        table.insert(parts, string.format("=== LSP DEFINITIONS (%d symbols) ===", lsp_count))
        table.insert(parts, "")
        for _, part in ipairs(lsp_parts) do
          table.insert(parts, part)
        end
      end

      total_tokens = total_tokens + lsp_tokens

      -- Add project tree at the end
      table.insert(parts, "=== PROJECT STRUCTURE ===")
      table.insert(parts, "```")
      table.insert(parts, tree_content)
      table.insert(parts, "```")

      total_tokens = total_tokens + tree_tokens

      callback(table.concat(parts, "\n"), total_tokens, {
        level = level.name,
        level_description = level.description,
        files = files_metadata,
        import_count = #import_files,
        lsp_count = lsp_count,
        tree_tokens = tree_tokens,
      })
    end, {
      max_files = level.max_lsp_files or 30,
    })
  else
    -- No LSP, finalize now
    table.insert(parts, "=== PROJECT STRUCTURE ===")
    table.insert(parts, "```")
    table.insert(parts, tree_content)
    table.insert(parts, "```")

    total_tokens = total_tokens + tree_tokens

    callback(table.concat(parts, "\n"), total_tokens, {
      level = level.name,
      level_description = level.description,
      files = files_metadata,
      import_count = #import_files,
      lsp_count = 0,
      lsp_skipped = level.lsp and "budget_insufficient" or "disabled_by_level",
      tree_tokens = tree_tokens,
    })
  end
end

-- =============================================================================
-- Main Entry Point
-- =============================================================================

---Build context with smart backtracking strategy
---@param current_file string
---@param callback function Callback(context, metadata)
---@param opts? table {budget?: number, timeout?: number}
function M.build_context_with_strategy(current_file, callback, opts)
  opts = opts or {}
  local budget = opts.budget or config.options.context and config.options.context.token_budget or M.DEFAULT_BUDGET
  local timeout_ms = opts.timeout or 25000 -- 25 second overall timeout

  local project_root = project_scanner.get_project_root(current_file)
  local level_index = 1
  local attempts = {}
  local callback_called = false

  -- Overall timeout handler
  vim.defer_fn(function()
    if not callback_called then
      callback_called = true
      -- Return whatever we have, or minimal context
      if #attempts > 0 then
        local best = attempts[#attempts]
        callback(best.context, {
          mode = "adaptive",
          strategy = {
            level_used = best.level,
            levels_tried = #attempts,
            timeout = true,
          },
          token_usage = {
            budget = budget,
            total = best.tokens,
            within_budget = best.tokens <= budget,
          },
          files_included = best.metadata and best.metadata.files or {},
          warning = "strategy_timeout_after_" .. timeout_ms .. "ms",
        })
      else
        -- No attempts completed, return empty with error
        callback("", {
          mode = "adaptive",
          error = "strategy_timeout_no_attempts",
          warning = "Context extraction timed out with no results",
        })
      end
    end
  end, timeout_ms)

  local function try_level()
    if callback_called then
      return -- Already timed out
    end

    if level_index > #M.LEVELS then
      if callback_called then return end
      callback_called = true
      -- All levels exhausted, return the best attempt (minimal level)
      local best = attempts[#attempts]
      callback(best.context, {
        mode = "adaptive",
        strategy = {
          level_used = best.level,
          levels_tried = #attempts,
          all_attempts = attempts,
        },
        token_usage = {
          budget = budget,
          total = best.tokens,
          within_budget = best.tokens <= budget,
        },
        files_included = best.metadata.files,
        warning = best.tokens > budget and "all_levels_exceeded_budget" or nil,
      })
      return
    end

    local level = M.LEVELS[level_index]

    build_context_for_level(current_file, project_root, level, budget, function(context, tokens, metadata)
      if callback_called then return end

      table.insert(attempts, {
        level = level.name,
        tokens = tokens,
        context = context,
        metadata = metadata,
      })

      if tokens <= budget then
        if callback_called then return end
        callback_called = true
        -- Success! This level fits
        callback(context, {
          mode = "adaptive",
          strategy = {
            level_used = level.name,
            level_description = level.description,
            level_index = level_index,
            levels_tried = level_index,
          },
          token_usage = {
            budget = budget,
            total = tokens,
            remaining = budget - tokens,
            within_budget = true,
          },
          files_included = metadata.files,
          import_count = metadata.import_count,
          lsp_count = metadata.lsp_count,
        })
      else
        -- Over budget, try next level
        level_index = level_index + 1
        try_level()
      end
    end)
  end

  try_level()
end

---Get available strategy levels (for debugging/display)
---@return table[]
function M.get_levels()
  return vim.deepcopy(M.LEVELS)
end

---Estimate which level would be used for current file
---@param current_file string
---@param budget? number
---@return string level_name
---@return table estimation
function M.estimate_level(current_file, budget)
  budget = budget or M.DEFAULT_BUDGET
  local project_root = project_scanner.get_project_root(current_file)

  -- Quick estimation based on project size
  local scan_result = cache.get_project(project_root, function()
    return project_scanner.scan_project({ root = project_root })
  end)

  local current_content = read_file(current_file)
  local current_tokens = current_content and project_scanner.estimate_tokens(current_content) or 0

  local import_files = get_imports_with_depth(current_file, project_root, 2)
  local estimated_import_tokens = #import_files * 500 -- Rough estimate

  local total_estimate = current_tokens + estimated_import_tokens

  local recommended_level = "maximum"
  if total_estimate > budget * 2 then
    recommended_level = "depth1_no_lsp"
  elseif total_estimate > budget * 1.5 then
    recommended_level = "semantic_all"
  elseif total_estimate > budget then
    recommended_level = "depth1_with_lsp"
  end

  return recommended_level,
    {
      current_tokens = current_tokens,
      import_count = #import_files,
      estimated_total = total_estimate,
      budget = budget,
      project_files = scan_result.source_files,
    }
end

return M
