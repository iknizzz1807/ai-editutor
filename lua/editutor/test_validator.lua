-- editutor/test_validator.lua
-- Reusable assertions for context extraction tests.

local M = {}

local config = require("editutor.config")
local import_graph = require("editutor.import_graph")
local project_scanner = require("editutor.project_scanner")

M.config = {
  max_auto_import_checks = 5,
  min_import_recall = 0.2,
  forbidden_context_patterns = {
    "/.git/",
    "node_modules/",
    "/dist/",
    "/build/",
    "__pycache__/",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".pdf",
    ".zip",
  },
}

-- =============================================================================
-- Helpers
-- =============================================================================

local function add(list, severity, kind, message, details)
  table.insert(list, {
    severity = severity,
    kind = kind,
    message = message,
    details = details,
  })
end

local function normalize_path(path)
  if not path then return "" end
  return path:gsub("\\", "/"):gsub("//+", "/")
end

local function contains_path(context_text, path)
  if not context_text or not path or path == "" then return false end
  path = normalize_path(path)
  local basename = vim.fn.fnamemodify(path, ":t")
  return context_text:find(path, 1, true) ~= nil
    or context_text:find(path:gsub("^/", ""), 1, true) ~= nil
    or (basename ~= "" and context_text:find(basename, 1, true) ~= nil)
end

local function contains_pattern(context_text, pattern)
  if not context_text or not pattern then return false end
  return context_text:find(pattern, 1, true) ~= nil or context_text:match(pattern) ~= nil
end

local function get_budget()
  return config.options.context and config.options.context.token_budget or 25000
end

local function relpath(path, root)
  path = normalize_path(path)
  root = normalize_path(root)
  if root ~= "" and path:sub(1, #root) == root then
    return path:sub(#root + 2)
  end
  return path
end

local function get_resolved_local_imports(filepath, project_root)
  local lang = import_graph.get_language(filepath)
  if not lang then return {} end

  local raw_imports = import_graph.extract_imports_from_file(filepath)
  local resolved = {}
  local seen = {}

  for _, import_path in ipairs(raw_imports) do
    local path = import_graph.resolve_import(import_path, filepath, project_root, lang)
    if path and not seen[path] then
      seen[path] = true
      table.insert(resolved, {
        import = import_path,
        path = normalize_path(path),
        relative = relpath(path, project_root),
      })
      if #resolved >= M.config.max_auto_import_checks then
        break
      end
    end
  end

  return resolved
end

-- =============================================================================
-- Heuristic Assertions
-- =============================================================================

function M.run_heuristics(tc, result, context_text, metadata)
  local assertions = {}
  local filepath = result.file_path
  local project_root = project_scanner.get_project_root(filepath)
  local current_rel = relpath(filepath, project_root)

  if not context_text or context_text == "" then
    add(assertions, "error", "non_empty_context", "Context must not be empty")
  end

  if not contains_path(context_text, current_rel) and not contains_path(context_text, filepath) then
    add(assertions, "error", "current_file", "Context must include the current file", {
      expected = current_rel,
    })
  end

  local tokens = (metadata and (metadata.total_tokens or (metadata.token_usage and metadata.token_usage.total)))
    or result.context.total_tokens
    or 0
  local budget = get_budget()
  if tokens > budget then
    add(assertions, "error", "token_budget", string.format("Context exceeds token budget (%d > %d)", tokens, budget))
  end

  local repo_file_hint = tc.repo .. "/" .. tc.file
  if not contains_path(context_text, repo_file_hint) and not contains_path(context_text, tc.file) then
    add(assertions, "warning", "project_tree", "Context should expose project/file identity", {
      expected = repo_file_hint,
    })
  end

  for _, pattern in ipairs(M.config.forbidden_context_patterns) do
    if context_text and context_text:find(pattern, 1, true) then
      add(assertions, "error", "forbidden_content", "Context contains excluded path or binary-like content", {
        pattern = pattern,
      })
    end
  end

  local local_imports = get_resolved_local_imports(filepath, project_root)
  if #local_imports > 0 then
    local hits = 0
    local misses = {}
    for _, item in ipairs(local_imports) do
      if contains_path(context_text, item.relative) or contains_path(context_text, item.path) then
        hits = hits + 1
      else
        table.insert(misses, item.relative)
      end
    end

    local recall = hits / #local_imports
    if recall < M.config.min_import_recall then
      add(assertions, "error", "local_import_recall", "Context should include at least some directly resolved local imports", {
        hits = hits,
        total = #local_imports,
        misses = misses,
      })
    end
  end

  local diagnostics_count = metadata
    and metadata.diagnostics
    and (metadata.diagnostics.count or 0)
    or 0
  if diagnostics_count > 0 and not context_text:find("=== LSP DIAGNOSTICS", 1, true) then
    add(assertions, "error", "diagnostics", "Diagnostics metadata exists but diagnostics section is missing")
  end

  return assertions
end

-- =============================================================================
-- Golden Assertions
-- =============================================================================

function M.run_golden(tc, context_text)
  local assertions = {}
  local expected = tc.expected
  if not expected then
    return assertions
  end

  for _, file in ipairs(expected.must_include_files or {}) do
    if not contains_path(context_text, file) then
      add(assertions, "error", "golden_file", "Missing required file in context", { expected = file })
    end
  end

  for _, symbol in ipairs(expected.must_include_symbols or {}) do
    if not context_text or not context_text:find(symbol, 1, true) then
      add(assertions, "error", "golden_symbol", "Missing required symbol in context", { expected = symbol })
    end
  end

  for _, pattern in ipairs(expected.must_include_patterns or {}) do
    if not contains_pattern(context_text, pattern) then
      add(assertions, "error", "golden_pattern", "Missing required pattern in context", { expected = pattern })
    end
  end

  for _, pattern in ipairs(expected.should_not_include or {}) do
    if contains_pattern(context_text, pattern) then
      add(assertions, "error", "golden_forbidden", "Context contains forbidden golden pattern", { pattern = pattern })
    end
  end

  return assertions
end

-- =============================================================================
-- Public API
-- =============================================================================

function M.validate(tc, result, context_text, metadata)
  local heuristic = M.run_heuristics(tc, result, context_text, metadata)
  local golden = M.run_golden(tc, context_text)
  local all = {}
  local errors = 0
  local warnings = 0

  for _, assertion in ipairs(heuristic) do
    table.insert(all, assertion)
  end
  for _, assertion in ipairs(golden) do
    table.insert(all, assertion)
  end

  for _, assertion in ipairs(all) do
    if assertion.severity == "error" then
      errors = errors + 1
    else
      warnings = warnings + 1
    end
  end

  return {
    passed = errors == 0,
    errors = errors,
    warnings = warnings,
    heuristic = heuristic,
    golden = golden,
    assertions = all,
    has_golden = tc.expected ~= nil,
  }
end

return M
