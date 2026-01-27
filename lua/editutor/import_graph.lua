-- editutor/import_graph.lua
-- Import graph analysis for adaptive context
-- Finds: files imported by current file + files that import current file

local M = {}

local project_scanner = require("editutor.project_scanner")
local cache = require("editutor.cache")

-- =============================================================================
-- Import Pattern Definitions
-- =============================================================================

-- Patterns for extracting import paths from source code
-- Each pattern returns the imported module/path
local function get_import_patterns()
  return {
    -- JavaScript/TypeScript
    javascript = {
      -- import x from 'path'
      -- import { x } from 'path'
      -- import * as x from 'path'
      "import%s+.-%s+from%s+['\"]([^'\"]+)['\"]",
      "import%s*%(%s*['\"]([^'\"]+)['\"]%s*%)",
      "import%s+['\"]([^'\"]+)['\"]",
      "require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)",
      "export%s+.-%s+from%s+['\"]([^'\"]+)['\"]",
    },
    typescript = "javascript",

    -- Python (removed ^ anchor - gmatch doesn't work with ^ for multiline)
    python = {
      "\nimport%s+([%w_%.]+)",
      "\nfrom%s+([%w_%.]+)%s+import",
      -- Also match at start of file
      "^import%s+([%w_%.]+)",
      "^from%s+([%w_%.]+)%s+import",
    },

    -- Lua
    lua = {
      "require%s*%(?%s*['\"]([^'\"]+)['\"]%s*%)?",
      "dofile%s*%(?%s*['\"]([^'\"]+)['\"]%s*%)?",
    },

    -- Go
    go = {
      "import%s+['\"]([^'\"]+)['\"]",
      "import%s+%w+%s+['\"]([^'\"]+)['\"]",
      "%s+['\"]([^'\"]+)['\"]",
    },

    -- Rust
    rust = {
      "use%s+([%w_:]+)",
      "mod%s+([%w_]+)%s*;",
      "extern%s+crate%s+([%w_]+)",
    },

    -- Ruby
    ruby = {
      "require%s+['\"]([^'\"]+)['\"]",
      "require_relative%s+['\"]([^'\"]+)['\"]",
      "load%s+['\"]([^'\"]+)['\"]",
    },

    -- PHP
    php = {
      "require%s+['\"]([^'\"]+)['\"]",
      "require_once%s+['\"]([^'\"]+)['\"]",
      "include%s+['\"]([^'\"]+)['\"]",
      "include_once%s+['\"]([^'\"]+)['\"]",
      "use%s+([%w_\\]+)",
    },

    -- C/C++
    c = {
      "#include%s*[\"<]([^\"'>]+)[\">]",
    },
    cpp = "c",

    -- Java
    java = {
      "import%s+([%w_.]+)%s*;",
      "import%s+static%s+([%w_.]+)%s*;",
    },

    -- Kotlin
    kotlin = {
      "import%s+([%w_.]+)",
    },

    -- Swift
    swift = {
      "import%s+([%w_]+)",
    },

    -- Elixir
    elixir = {
      "alias%s+([%w_.]+)",
      "import%s+([%w_.]+)",
      "use%s+([%w_.]+)",
      "require%s+([%w_.]+)",
    },

    -- Zig
    zig = {
      -- @import("std"), @import("file.zig"), @import("path/to/file.zig")
      "@import%s*%(%s*\"([^\"]+)\"%s*%)",
    },
  }
end

M.IMPORT_PATTERNS = get_import_patterns()

-- Extension to language mapping
M.EXT_TO_LANG = {
  js = "javascript",
  jsx = "javascript",
  mjs = "javascript",
  cjs = "javascript",
  ts = "typescript",
  tsx = "typescript",
  py = "python",
  pyw = "python",
  lua = "lua",
  go = "go",
  rs = "rust",
  rb = "ruby",
  rake = "ruby",
  php = "php",
  c = "c",
  h = "c",
  cpp = "cpp",
  cc = "cpp",
  cxx = "cpp",
  hpp = "cpp",
  java = "java",
  kt = "kotlin",
  kts = "kotlin",
  swift = "swift",
  ex = "elixir",
  exs = "elixir",
  zig = "zig",
}

-- =============================================================================
-- Import Extraction
-- =============================================================================

---Get language from file extension
---@param filepath string
---@return string|nil
function M.get_language(filepath)
  local ext = filepath:match("%.([^.]+)$")
  if not ext then return nil end
  return M.EXT_TO_LANG[ext:lower()]
end

---Get import patterns for a language
---@param lang string
---@return table|nil
function M.get_patterns(lang)
  local patterns = M.IMPORT_PATTERNS[lang]
  if type(patterns) == "string" then
    -- Reference to another language
    patterns = M.IMPORT_PATTERNS[patterns]
  end
  return patterns
end

---Extract raw imports from file content
---@param content string
---@param lang string
---@return string[] List of imported module/path strings
function M.extract_imports(content, lang)
  local patterns = M.get_patterns(lang)
  if not patterns then return {} end

  local imports = {}
  local seen = {}

  for _, pattern in ipairs(patterns) do
    for import_path in content:gmatch(pattern) do
      if not seen[import_path] then
        seen[import_path] = true
        table.insert(imports, import_path)
      end
    end
  end

  return imports
end

---Extract imports from a file
---@param filepath string
---@return string[] List of imported module/path strings
function M.extract_imports_from_file(filepath)
  local lang = M.get_language(filepath)
  if not lang then return {} end

  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then return {} end

  local content = table.concat(lines, "\n")
  return M.extract_imports(content, lang)
end

-- =============================================================================
-- Path Resolution
-- =============================================================================

---Check if import is a relative path
---@param import_path string
---@return boolean
function M.is_relative_import(import_path)
  return import_path:match("^%.") ~= nil or import_path:match("^/") ~= nil
end

---Check if import is likely a library (not project file)
---@param import_path string
---@param lang string
---@return boolean
function M.is_library_import(import_path, lang)
  -- Node.js built-ins
  local node_builtins = {
    "fs", "path", "os", "http", "https", "url", "util", "events",
    "stream", "buffer", "crypto", "child_process", "cluster",
    "net", "dns", "tls", "zlib", "readline", "repl", "vm",
    "assert", "async_hooks", "perf_hooks", "worker_threads",
  }

  -- Python standard library only (don't include external packages
  -- because we might be working IN those projects)
  local python_stdlib = {
    "os", "sys", "re", "json", "math", "random", "datetime", "time",
    "collections", "itertools", "functools", "operator", "typing",
    "pathlib", "shutil", "glob", "tempfile", "io", "pickle",
    "subprocess", "threading", "multiprocessing", "asyncio",
    "http", "urllib", "socket", "email", "html", "xml",
    "logging", "unittest", "argparse", "configparser",
    "dataclasses", "enum", "abc", "copy", "pprint",
    "contextlib", "inspect", "traceback", "warnings", "weakref",
    "hashlib", "hmac", "secrets", "base64", "binascii",
    "struct", "codecs", "unicodedata", "locale",
    "calendar", "zoneinfo", "heapq", "bisect", "array",
    "types", "textwrap", "difflib", "string",
    "builtins", "importlib", "pkgutil", "zipimport",
    "dis", "ast", "symtable", "token", "tokenize",
    "pdb", "profile", "cProfile", "timeit",
    "numbers", "decimal", "fractions", "cmath",
    "statistics", "csv", "sqlite3", "dbm", "gzip",
    "bz2", "lzma", "tarfile", "zipfile",
    "signal", "mmap", "ctypes", "platform",
  }

  if lang == "javascript" or lang == "typescript" then
    -- Check node builtins
    local base = import_path:match("^([^/]+)")
    for _, builtin in ipairs(node_builtins) do
      if base == builtin or base == "node:" .. builtin then
        return true
      end
    end
    -- Scoped packages and non-relative are likely npm packages
    if import_path:match("^@") then return true end
    if not M.is_relative_import(import_path) then
      -- Could be a local alias, but likely a package
      return true
    end
  elseif lang == "python" then
    local base = import_path:match("^([^%.]+)")
    for _, stdlib in ipairs(python_stdlib) do
      if base == stdlib then
        return true
      end
    end
  elseif lang == "go" then
    -- Standard library doesn't have dots in first segment
    if not import_path:match("%.") then return true end
  elseif lang == "rust" then
    -- std, core, alloc are standard
    if import_path:match("^std::") or import_path:match("^core::") or import_path:match("^alloc::") then
      return true
    end
  elseif lang == "zig" then
    -- std is Zig standard library
    if import_path == "std" then
      return true
    end
  end

  return false
end

---Resolve import path to actual file path
---@param import_path string The import string from source code
---@param source_file string The file containing the import
---@param project_root string Project root directory
---@param lang string Language
---@return string|nil Resolved absolute file path, or nil if not found
function M.resolve_import(import_path, source_file, project_root, lang)
  -- Skip library imports
  if M.is_library_import(import_path, lang) then
    return nil
  end

  local source_dir = vim.fn.fnamemodify(source_file, ":h")
  local resolved = nil

  -- Language-specific resolution
  if lang == "javascript" or lang == "typescript" then
    resolved = M._resolve_js_import(import_path, source_dir, project_root, lang)
  elseif lang == "python" then
    resolved = M._resolve_python_import(import_path, source_dir, project_root)
  elseif lang == "lua" then
    resolved = M._resolve_lua_import(import_path, source_dir, project_root)
  elseif lang == "go" then
    resolved = M._resolve_go_import(import_path, source_dir, project_root)
  elseif lang == "rust" then
    resolved = M._resolve_rust_import(import_path, source_dir, project_root)
  elseif lang == "c" or lang == "cpp" then
    resolved = M._resolve_c_import(import_path, source_dir, project_root)
  elseif lang == "zig" then
    resolved = M._resolve_zig_import(import_path, source_dir, project_root)
  else
    -- Generic: try relative resolution
    resolved = M._resolve_generic_import(import_path, source_dir, project_root)
  end

  -- Normalize resolved path to remove ./ and // artifacts
  if resolved then
    resolved = vim.fn.simplify(resolved)
  end

  return resolved
end

---Try multiple file extensions
---@param base_path string
---@param extensions string[]
---@return string|nil
local function try_extensions(base_path, extensions)
  for _, ext in ipairs(extensions) do
    local path = base_path .. ext
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end
  -- Also try as directory with index file
  for _, ext in ipairs(extensions) do
    local index_path = base_path .. "/index" .. ext
    if vim.fn.filereadable(index_path) == 1 then
      return index_path
    end
  end
  return nil
end

---Resolve JavaScript/TypeScript import
function M._resolve_js_import(import_path, source_dir, project_root, lang)
  local extensions = { ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", "" }

  if M.is_relative_import(import_path) then
    -- Relative import: ./foo or ../bar
    local base = source_dir .. "/" .. import_path
    base = vim.fn.fnamemodify(base, ":p"):gsub("/$", "")
    return try_extensions(base, extensions)
  else
    -- Could be alias (e.g., @/components) or bare import
    -- Try common alias patterns
    local alias_bases = {
      project_root .. "/src/" .. import_path:gsub("^@/", ""),
      project_root .. "/app/" .. import_path:gsub("^@/", ""),
      project_root .. "/lib/" .. import_path:gsub("^@/", ""),
      project_root .. "/" .. import_path,
    }
    for _, base in ipairs(alias_bases) do
      local resolved = try_extensions(base, extensions)
      if resolved then return resolved end
    end
  end

  return nil
end

---Resolve Python import
function M._resolve_python_import(import_path, source_dir, project_root)
  -- Convert dot notation to path
  local rel_path = import_path:gsub("%.", "/")

  -- Try as module file
  local candidates = {
    project_root .. "/" .. rel_path .. ".py",
    project_root .. "/" .. rel_path .. "/__init__.py",
    project_root .. "/src/" .. rel_path .. ".py",
    project_root .. "/src/" .. rel_path .. "/__init__.py",
    source_dir .. "/" .. rel_path .. ".py",
  }

  for _, path in ipairs(candidates) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  return nil
end

---Resolve Lua import
function M._resolve_lua_import(import_path, source_dir, project_root)
  -- Convert dot notation to path
  local rel_path = import_path:gsub("%.", "/")

  local candidates = {
    project_root .. "/" .. rel_path .. ".lua",
    project_root .. "/lua/" .. rel_path .. ".lua",
    project_root .. "/" .. rel_path .. "/init.lua",
    project_root .. "/lua/" .. rel_path .. "/init.lua",
    source_dir .. "/" .. rel_path .. ".lua",
  }

  for _, path in ipairs(candidates) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  return nil
end

---Resolve Go import
function M._resolve_go_import(import_path, source_dir, project_root)
  -- Go imports are usually full module paths
  -- Try to find in project by matching suffix
  local parts = vim.split(import_path, "/")
  local suffix = parts[#parts]

  -- Check if it matches any directory in project
  local candidates = {
    project_root .. "/" .. suffix,
    project_root .. "/internal/" .. suffix,
    project_root .. "/pkg/" .. suffix,
    project_root .. "/cmd/" .. suffix,
  }

  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir) == 1 then
      -- Find a .go file in this directory
      local handle = vim.loop.fs_scandir(dir)
      if handle then
        while true do
          local name, ftype = vim.loop.fs_scandir_next(handle)
          if not name then break end
          if ftype == "file" and name:match("%.go$") and not name:match("_test%.go$") then
            return dir .. "/" .. name
          end
        end
      end
    end
  end

  return nil
end

---Resolve Rust import
function M._resolve_rust_import(import_path, source_dir, project_root)
  -- Handle crate:: and super:: prefixes
  local path = import_path
    :gsub("^crate::", "")
    :gsub("^super::", "../")
    :gsub("::", "/")

  local candidates = {
    project_root .. "/src/" .. path .. ".rs",
    project_root .. "/src/" .. path .. "/mod.rs",
    source_dir .. "/" .. path .. ".rs",
  }

  for _, p in ipairs(candidates) do
    local normalized = vim.fn.fnamemodify(p, ":p")
    if vim.fn.filereadable(normalized) == 1 then
      return normalized
    end
  end

  return nil
end

---Resolve C/C++ include
function M._resolve_c_import(import_path, source_dir, project_root)
  local candidates = {
    source_dir .. "/" .. import_path,
    project_root .. "/" .. import_path,
    project_root .. "/include/" .. import_path,
    project_root .. "/src/" .. import_path,
  }

  for _, path in ipairs(candidates) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  return nil
end

---Generic import resolution
function M._resolve_generic_import(import_path, source_dir, project_root)
  if M.is_relative_import(import_path) then
    local path = vim.fn.fnamemodify(source_dir .. "/" .. import_path, ":p")
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end
  return nil
end

---Resolve Zig import
---@param import_path string The import string (e.g., "file.zig", "path/to/file.zig")
---@param source_dir string Directory of source file
---@param project_root string Project root directory
---@return string|nil Resolved file path
function M._resolve_zig_import(import_path, source_dir, project_root)
  -- Zig imports are file paths relative to source or project
  -- @import("foo.zig") looks for foo.zig relative to current file
  -- @import("path/to/foo.zig") looks for path/to/foo.zig

  local candidates = {
    -- Relative to source file
    source_dir .. "/" .. import_path,
    -- Relative to project root
    project_root .. "/" .. import_path,
    -- In src directory
    project_root .. "/src/" .. import_path,
    -- In lib directory
    project_root .. "/lib/" .. import_path,
  }

  for _, path in ipairs(candidates) do
    local normalized = vim.fn.fnamemodify(path, ":p")
    if vim.fn.filereadable(normalized) == 1 then
      return normalized
    end
  end

  return nil
end

-- =============================================================================
-- Import Graph Building
-- =============================================================================

---Get files that current file imports (outgoing edges)
---@param filepath string Current file path
---@param project_root string Project root
---@return string[] List of resolved file paths
function M.get_outgoing_imports(filepath, project_root)
  local lang = M.get_language(filepath)
  if not lang then return {} end

  local imports = M.extract_imports_from_file(filepath)
  local resolved = {}
  local seen = {}

  for _, import_path in ipairs(imports) do
    local resolved_path = M.resolve_import(import_path, filepath, project_root, lang)
    if resolved_path and not seen[resolved_path] then
      -- Verify it's within project root
      if resolved_path:sub(1, #project_root) == project_root then
        seen[resolved_path] = true
        table.insert(resolved, resolved_path)
      end
    end
  end

  return resolved
end

-- =============================================================================
-- Import Index (for fast incoming lookups)
-- =============================================================================

-- Cached import index: maps resolved filepath -> list of files that import it
M._import_index = nil
M._import_index_root = nil

---Build import index for entire project (done once, cached)
---@param project_root string
---@param scan_result table
---@return table<string, string[]> Index mapping filepath -> importers
local function build_import_index(project_root, scan_result)
  local index = {}

  for _, file in ipairs(scan_result.files) do
    if file.type == "source" then
      -- Normalize path to remove ./ and // artifacts
      local full_path = vim.fn.simplify(project_root .. "/" .. file.path)
      local file_lang = M.get_language(full_path)

      if file_lang then
        local imports = M.extract_imports_from_file(full_path)

        for _, import_path in ipairs(imports) do
          local resolved = M.resolve_import(import_path, full_path, project_root, file_lang)
          if resolved then
            if not index[resolved] then
              index[resolved] = {}
            end
            -- Avoid duplicates
            local found = false
            for _, existing in ipairs(index[resolved]) do
              if existing == full_path then
                found = true
                break
              end
            end
            if not found then
              table.insert(index[resolved], full_path)
            end
          end
        end
      end
    end
  end

  return index
end

---Get or build import index
---@param project_root string
---@param scan_result table
---@return table<string, string[]>
local function get_import_index(project_root, scan_result)
  -- Check if we have a valid cached index
  if M._import_index and M._import_index_root == project_root then
    return M._import_index
  end

  -- Build new index
  M._import_index = build_import_index(project_root, scan_result)
  M._import_index_root = project_root

  return M._import_index
end

---Invalidate import index (call when files change)
function M.invalidate_index()
  M._import_index = nil
  M._import_index_root = nil
end

---Get files that import current file (incoming edges)
---Uses cached import index for fast O(1) lookup instead of scanning all files
---@param filepath string Current file path
---@param project_root string Project root
---@param scan_result? table Cached project scan result
---@return string[] List of file paths that import current file
function M.get_incoming_imports(filepath, project_root, scan_result)
  local current_lang = M.get_language(filepath)
  if not current_lang then return {} end

  -- Get project files
  scan_result = scan_result or cache.get_project(project_root, function()
    return project_scanner.scan_project({ root = project_root })
  end)

  -- Use indexed lookup (O(1) instead of O(n) file reads)
  local index = get_import_index(project_root, scan_result)
  local incoming = index[filepath] or {}

  -- Filter out self (shouldn't happen but safety check)
  local result = {}
  for _, importer in ipairs(incoming) do
    if importer ~= filepath then
      table.insert(result, importer)
    end
  end

  return result
end

---Get full import graph for a file (depth=1 in both directions)
---@param filepath string Current file path
---@param project_root? string Project root (auto-detected if nil)
---@return table {outgoing: string[], incoming: string[], all: string[]}
function M.get_import_graph(filepath, project_root)
  project_root = project_root or project_scanner.get_project_root(filepath)

  local outgoing = M.get_outgoing_imports(filepath, project_root)
  local incoming = M.get_incoming_imports(filepath, project_root)

  -- Merge and dedupe
  local all = {}
  local seen = {}

  for _, path in ipairs(outgoing) do
    if not seen[path] then
      seen[path] = true
      table.insert(all, path)
    end
  end

  for _, path in ipairs(incoming) do
    if not seen[path] then
      seen[path] = true
      table.insert(all, path)
    end
  end

  return {
    outgoing = outgoing,
    incoming = incoming,
    all = all,
  }
end

return M
