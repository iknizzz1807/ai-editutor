-- editutor/relevance_scorer.lua
-- File relevance scoring for context prioritization
-- Higher score = more relevant = should be included first

local M = {}

-- =============================================================================
-- Scoring Configuration
-- =============================================================================

M.SCORES = {
  -- Type definition files (highest priority)
  type_definition = 3,

  -- Same directory as current file
  same_directory = 2,

  -- Incoming import (file imports current file)
  incoming_import = 2,

  -- Outgoing import (current file imports this)
  outgoing_import = 1,

  -- Config/constants files
  config_file = 1,

  -- Small file (likely more focused)
  small_file = 1, -- < 200 lines

  -- Penalties
  test_file = -2,
  generated_file = -3,
  vendor_file = -5,
  large_file = -1, -- > 500 lines
}

-- =============================================================================
-- Pattern Matching
-- =============================================================================

-- Patterns for type definition files
M.TYPE_FILE_PATTERNS = {
  -- TypeScript/JavaScript
  "types%.ts$",
  "types%.tsx$",
  "types/",
  "%.d%.ts$",
  "interfaces%.ts$",
  "interfaces/",
  "models%.ts$",
  "models/",
  "schemas%.ts$",

  -- Python
  "types%.py$",
  "typing%.py$",
  "models%.py$",
  "_types%.py$",

  -- Go
  "types%.go$",
  "models%.go$",

  -- Rust
  "types%.rs$",
  "models%.rs$",

  -- C/C++
  "types%.h$",
  "types%.hpp$",
  "_types%.h$",

  -- Java
  "Types%.java$",
  "Models%.java$",
  "/dto/",
  "/entity/",
  "/model/",
}

-- Patterns for config files
M.CONFIG_FILE_PATTERNS = {
  "config%.ts$",
  "config%.js$",
  "config%.py$",
  "config%.lua$",
  "config%.go$",
  "constants%.ts$",
  "constants%.js$",
  "constants%.py$",
  "settings%.py$",
  "env%.ts$",
  "/config/",
  "/constants/",
}

-- Patterns for test files (penalty)
M.TEST_FILE_PATTERNS = {
  "_test%.go$",
  "_test%.ts$",
  "_test%.js$",
  "%.test%.ts$",
  "%.test%.js$",
  "%.test%.tsx$",
  "%.test%.jsx$",
  "%.spec%.ts$",
  "%.spec%.js$",
  "test_.*%.py$",
  ".*_test%.py$",
  "_spec%.rb$",
  "Test%.java$",
  "/tests?/",
  "/__tests__/",
}

-- Patterns for generated files (penalty)
M.GENERATED_FILE_PATTERNS = {
  "%.generated%.",
  "%.g%.ts$",
  "%.g%.dart$",
  "%.pb%.go$",
  "_pb2%.py$",
  "%.min%.js$",
  "%.bundle%.js$",
  "/generated/",
  "/gen/",
  "/dist/",
  "/build/",
}

-- Patterns for vendor files (heavy penalty)
M.VENDOR_FILE_PATTERNS = {
  "node_modules/",
  "vendor/",
  "third_party/",
  "external/",
  "%.cargo/",
  "site%-packages/",
  "__pycache__/",
}

-- =============================================================================
-- Core Scoring Functions
-- =============================================================================

---Check if filepath matches any pattern in list
---@param filepath string
---@param patterns string[]
---@return boolean
local function matches_patterns(filepath, patterns)
  for _, pattern in ipairs(patterns) do
    if filepath:match(pattern) then
      return true
    end
  end
  return false
end

---Get line count for a file (cached)
---@param filepath string
---@return number
local function get_line_count(filepath)
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return 0
  end
  return #lines
end

---Score a single file based on various criteria
---@param filepath string Full path to file
---@param current_file string Full path to current file (where questions are)
---@param relationship? string "incoming"|"outgoing"|nil
---@return number score
---@return table breakdown Detailed score breakdown
function M.score_file(filepath, current_file, relationship)
  local score = 0
  local breakdown = {}

  -- Vendor files (heavy penalty, usually should be excluded entirely)
  if matches_patterns(filepath, M.VENDOR_FILE_PATTERNS) then
    score = score + M.SCORES.vendor_file
    breakdown.vendor_file = M.SCORES.vendor_file
    return score, breakdown -- Early return, don't bother with other checks
  end

  -- Type definition files (+3)
  if matches_patterns(filepath, M.TYPE_FILE_PATTERNS) then
    score = score + M.SCORES.type_definition
    breakdown.type_definition = M.SCORES.type_definition
  end

  -- Same directory as current file (+2)
  local current_dir = vim.fn.fnamemodify(current_file, ":h")
  local file_dir = vim.fn.fnamemodify(filepath, ":h")
  if current_dir == file_dir then
    score = score + M.SCORES.same_directory
    breakdown.same_directory = M.SCORES.same_directory
  end

  -- Import relationship
  if relationship == "incoming" then
    -- File imports current file (more likely to be important)
    score = score + M.SCORES.incoming_import
    breakdown.incoming_import = M.SCORES.incoming_import
  elseif relationship == "outgoing" then
    -- Current file imports this file
    score = score + M.SCORES.outgoing_import
    breakdown.outgoing_import = M.SCORES.outgoing_import
  end

  -- Config/constants files (+1)
  if matches_patterns(filepath, M.CONFIG_FILE_PATTERNS) then
    score = score + M.SCORES.config_file
    breakdown.config_file = M.SCORES.config_file
  end

  -- File size scoring
  local line_count = get_line_count(filepath)
  if line_count > 0 and line_count < 200 then
    score = score + M.SCORES.small_file
    breakdown.small_file = M.SCORES.small_file
  elseif line_count > 500 then
    score = score + M.SCORES.large_file
    breakdown.large_file = M.SCORES.large_file
  end

  -- Test files (-2)
  if matches_patterns(filepath, M.TEST_FILE_PATTERNS) then
    score = score + M.SCORES.test_file
    breakdown.test_file = M.SCORES.test_file
  end

  -- Generated files (-3)
  if matches_patterns(filepath, M.GENERATED_FILE_PATTERNS) then
    score = score + M.SCORES.generated_file
    breakdown.generated_file = M.SCORES.generated_file
  end

  breakdown.line_count = line_count
  breakdown.total = score

  return score, breakdown
end

---Score and sort a list of files by relevance
---@param files table[] List of {path: string, relationship?: string, ...}
---@param current_file string Current file path
---@param opts? table {include_breakdown?: boolean, min_score?: number}
---@return table[] Sorted list with scores
function M.score_and_sort(files, current_file, opts)
  opts = opts or {}
  local include_breakdown = opts.include_breakdown
  local min_score = opts.min_score or -10 -- Filter out very low scores

  local scored = {}

  for _, file in ipairs(files) do
    local filepath = file.path or file.filepath or file
    local relationship = file.relationship

    local score, breakdown = M.score_file(filepath, current_file, relationship)

    if score >= min_score then
      local entry = vim.tbl_extend("force", {}, file)
      entry.relevance_score = score
      if include_breakdown then
        entry.score_breakdown = breakdown
      end
      table.insert(scored, entry)
    end
  end

  -- Sort by score descending
  table.sort(scored, function(a, b)
    return a.relevance_score > b.relevance_score
  end)

  return scored
end

---Filter files to only include types and high-relevance files
---@param files table[] List of files
---@param current_file string Current file path
---@param max_files? number Maximum files to return
---@return table[] Filtered and sorted files
function M.filter_types_and_high_relevance(files, current_file, max_files)
  max_files = max_files or 10

  local scored = M.score_and_sort(files, current_file, { min_score = 0 })

  -- Prioritize type files
  local result = {}
  local type_files = {}
  local other_files = {}

  for _, file in ipairs(scored) do
    local filepath = file.path or file.filepath or file
    if matches_patterns(filepath, M.TYPE_FILE_PATTERNS) then
      table.insert(type_files, file)
    else
      table.insert(other_files, file)
    end
  end

  -- Add type files first, then other high-relevance files
  for _, file in ipairs(type_files) do
    if #result < max_files then
      table.insert(result, file)
    end
  end

  for _, file in ipairs(other_files) do
    if #result < max_files then
      table.insert(result, file)
    end
  end

  return result
end

-- =============================================================================
-- Utility Functions
-- =============================================================================

---Check if a file should be excluded entirely (vendor, heavy generated)
---@param filepath string
---@return boolean
function M.should_exclude(filepath)
  return matches_patterns(filepath, M.VENDOR_FILE_PATTERNS)
end

---Check if a file is a test file
---@param filepath string
---@return boolean
function M.is_test_file(filepath)
  return matches_patterns(filepath, M.TEST_FILE_PATTERNS)
end

---Check if a file is a type definition file
---@param filepath string
---@return boolean
function M.is_type_file(filepath)
  return matches_patterns(filepath, M.TYPE_FILE_PATTERNS)
end

---Check if a file is a generated file
---@param filepath string
---@return boolean
function M.is_generated_file(filepath)
  return matches_patterns(filepath, M.GENERATED_FILE_PATTERNS)
end

---Get all scoring criteria for a file (for debugging)
---@param filepath string
---@param current_file string
---@param relationship? string
---@return table
function M.analyze_file(filepath, current_file, relationship)
  local score, breakdown = M.score_file(filepath, current_file, relationship)

  return {
    filepath = filepath,
    score = score,
    breakdown = breakdown,
    is_type_file = M.is_type_file(filepath),
    is_test_file = M.is_test_file(filepath),
    is_generated_file = M.is_generated_file(filepath),
    should_exclude = M.should_exclude(filepath),
  }
end

return M
