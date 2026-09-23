-- editutor/project_scanner.lua
-- Smart project scanner for ai-editutor
-- Detects source code, config files, and builds tree structure
-- Respects .gitignore and excludes non-essential files

local M = {}

-- =============================================================================
-- File Classification Patterns
-- =============================================================================

-- Folders to ALWAYS exclude (never scan inside)
M.EXCLUDE_FOLDERS = {
  -- Version control
  ".git", ".svn", ".hg", ".bzr",
  -- Dependencies
  "node_modules", "bower_components", "jspm_packages", "vendor",
  ".vendor", "__pypackages__", ".eggs", "eggs", "wheels",
  ".bundle", "Pods",
  -- Build output
  "build", "dist", "out", "target", "_build", "output", "bin", "obj",
  "cmake-build-debug", "cmake-build-release", "CMakeFiles",
  ".output", ".next", ".nuxt", ".docusaurus", ".svelte-kit",
  ".vitepress", ".vercel", ".netlify",
  -- Cache
  ".cache", ".parcel-cache", ".temp", ".tmp", "tmp", "temp",
  "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
  ".tox", ".nox", ".hypothesis", ".nyc_output", "coverage", "htmlcov",
  ".coverage", ".jest", ".vite", ".turbo", ".fusebox",
  -- IDE
  ".idea", ".vscode", ".vs",
  -- Virtual environments
  ".venv", "venv", "env", "ENV", ".pixi", ".conda",
  -- Logs
  "logs",
  -- Test artifacts
  "test-results", "playwright-report",
}

-- Folders typically containing generated data, benchmarks, artifacts, or datasets
-- Data/config files (json, yaml, csv, etc.) in these folders are treated as data, not source
M.DATA_FOLDERS = {
  "results", "result",
  "reports", "report",
  "artifacts", "artifact",
  "checkpoints", "checkpoint",
  "runs", "run",
  "data", "dataset", "datasets",
  "outputs",
  "benchmarks", "benchmark",
  "metrics",
  "fixtures_data", "testdata",
}

---Check if folder name matches known data folder
---@param folder_name string
---@return boolean
local function is_data_folder_name(folder_name)
  local lower = folder_name:lower()
  for _, df in ipairs(M.DATA_FOLDERS) do
    if lower == df then
      return true
    end
  end
  return false
end

---Check if path is inside a core source directory (src/, lib/, pkg/, app/, etc.)
---@param path string
---@return boolean
local function is_under_core_source_dir(path)
  if not path or path == "" then return false end
  local normalized = path:gsub("\\", "/")
  local core_patterns = {
    "^src/", "^source/", "^lib/", "^app/", "^core/", "^pkg/", "^internal/", "^lua/",
    "/src/", "/source/", "/lib/", "/app/", "/core/", "/pkg/", "/internal/", "/lua/",
  }
  for _, pat in ipairs(core_patterns) do
    if normalized:match(pat) then
      return true
    end
  end
  return false
end

---Check if path is inside a dedicated data folder (outside core source tree)
---@param path string Relative or absolute path
---@return boolean
local function is_in_data_folder(path)
  if not path or path == "" then return false end
  -- Any folder within src/, lib/, etc. is source code, never a data dump
  if is_under_core_source_dir(path) then
    return false
  end

  local normalized = path:gsub("\\", "/")
  local parts = vim.split(normalized, "/")
  -- Check directory components (excluding filename)
  for i = 1, #parts - 1 do
    if is_data_folder_name(parts[i]) then
      return true
    end
  end
  -- Also check if the path itself is a top-level directory
  if #parts == 1 and is_data_folder_name(parts[1]) then
    return true
  end
  return false
end

-- Source code file extensions
M.SOURCE_EXTENSIONS = {
  -- Web
  "js", "jsx", "ts", "tsx", "mjs", "cjs",
  "vue", "svelte", "astro",
  "html", "htm",
  "css", "scss", "sass", "less",
  -- Systems
  "c", "h", "cpp", "cc", "cxx", "hpp", "hxx",
  "rs", "go", "zig", "nim", "v", "odin",
  -- JVM
  "java", "kt", "kts", "scala", "clj", "cljs", "groovy",
  -- .NET
  "cs", "fs", "vb",
  -- Scripting
  "py", "pyw", "pyi",
  "rb", "rake",
  "pl", "pm",
  "php",
  "lua",
  "sh", "bash", "zsh", "fish",
  "ps1", "psm1",
  -- Mobile
  "swift", "m", "mm", "dart",
  -- Functional
  "hs", "ml", "mli", "erl", "ex", "exs", "elm",
  "lisp", "cl", "el", "scm", "rkt",
  -- Data/Config (source-like)
  "yaml", "yml", "toml", "json", "jsonc",
  "xml", "sql", "graphql", "gql",
  -- Markup
  "md", "markdown", "rst", "adoc", "org", "tex",
  -- Templates
  "ejs", "erb", "haml", "pug", "hbs", "jinja", "j2", "liquid", "twig",
  -- Shaders
  "glsl", "hlsl", "wgsl", "metal",
  -- Other
  "r", "jl", "proto", "thrift",
}

-- Important config files (always include even without typical extensions)
M.CONFIG_FILES = {
  -- Build/Package
  "Makefile", "makefile", "GNUmakefile",
  "CMakeLists.txt",
  "Dockerfile", "Containerfile",
  "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml",
  "Vagrantfile", "Procfile", "Caddyfile",
  -- Package managers (excluding lock files - they are data, not useful for context)
  "package.json",
  "Gemfile",
  "Cargo.toml",
  "go.mod", "go.sum",
  "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt",
  "Pipfile",
  "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
  "pom.xml", "build.xml",
  "mix.exs", "rebar.config",
  "dune", "dune-project",
  "pubspec.yaml",
  "composer.json",
  "Podfile",
  -- Note: Lock files (*.lock, *-lock.*, *.lockb) are excluded as data
  -- Editor/Linter config
  ".editorconfig", ".prettierrc", ".prettierrc.json", ".prettierrc.yml",
  ".eslintrc", ".eslintrc.js", ".eslintrc.json", ".eslintrc.yml",
  ".stylelintrc", ".stylelintrc.json",
  "tsconfig.json", "jsconfig.json",
  ".babelrc", ".babelrc.json", "babel.config.js", "babel.config.json",
  "webpack.config.js", "webpack.config.ts",
  "rollup.config.js", "rollup.config.ts",
  "vite.config.js", "vite.config.ts", "vite.config.mjs",
  "next.config.js", "next.config.mjs", "next.config.ts",
  "nuxt.config.js", "nuxt.config.ts",
  "svelte.config.js", "astro.config.mjs",
  "tailwind.config.js", "tailwind.config.ts",
  "postcss.config.js", "postcss.config.cjs",
  "jest.config.js", "jest.config.ts",
  "vitest.config.js", "vitest.config.ts",
  "playwright.config.ts", "cypress.config.js",
  ".rubocop.yml", ".pylintrc", ".flake8",
  "pyrightconfig.json", "mypy.ini",
  ".clang-format", ".clang-tidy",
  "rustfmt.toml", ".rustfmt.toml", "clippy.toml",
  -- CI/CD
  ".travis.yml", ".gitlab-ci.yml", "Jenkinsfile",
  "azure-pipelines.yml", "bitbucket-pipelines.yml",
  "appveyor.yml", ".drone.yml", "cloudbuild.yaml",
  -- Documentation (keep only README and CONTRIBUTING - useful for understanding project)
  "README", "README.md", "README.rst", "README.txt",
  "CONTRIBUTING", "CONTRIBUTING.md",
  -- Note: Excluded from config (not useful for code understanding):
  -- CHANGELOG, HISTORY, LICENSE, AUTHORS, CODE_OF_CONDUCT, SECURITY
  -- Git
  ".gitignore", ".gitattributes", ".gitmodules",
  -- Environment templates
  ".env.example", ".env.sample", ".env.template",
  -- Other config
  ".nvmrc", ".node-version", ".python-version", ".ruby-version", ".tool-versions",
  "netlify.toml", "vercel.json", "fly.toml", "render.yaml",
  "firebase.json", ".firebaserc",
  "serverless.yml",
  -- Additional frameworks
  "angular.json", ".angular-cli.json",
  "ember-cli-build.js", ".ember-cli",
  "gatsby-config.js", "gatsby-node.js",
  "remix.config.js",
  "turbo.json",
  "lerna.json",
  "nx.json", "workspace.json", "project.json",
  "rush.json",
  ".prettierignore", ".eslintignore", ".dockerignore",
  "tslint.json",
  "biome.json", "biome.jsonc",
  "deno.json", "deno.jsonc",
  "bunfig.toml",
  -- Note: bun.lockb is binary, excluded
  -- Neovim/Vim
  "stylua.toml", ".stylua.toml",
  "selene.toml",
  ".luacheckrc", ".luarc.json",
  -- Claude/AI
  "CLAUDE.md", "AGENTS.md", "COPILOT.md",
  ".cursorrules", ".cursorignore",
}

-- Data/Binary extensions (never include content)
M.DATA_EXTENSIONS = {
  -- Images
  "png", "jpg", "jpeg", "gif", "bmp", "ico", "webp", "avif",
  "svg", "tiff", "tif", "raw", "psd", "ai", "eps", "heic", "heif",
  -- Video
  "mp4", "avi", "mov", "mkv", "webm", "flv", "wmv", "m4v", "mpeg", "mpg",
  -- Audio
  "mp3", "wav", "ogg", "flac", "aac", "m4a", "wma", "mid", "midi",
  -- Fonts
  "ttf", "otf", "woff", "woff2", "eot",
  -- Archives
  "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar",
  "jar", "war", "ear", "deb", "rpm", "dmg", "pkg", "msi", "exe",
  -- Documents
  "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp",
  -- Database
  "db", "sqlite", "sqlite3", "mdb", "accdb",
  -- Compiled/Binary
  "o", "obj", "a", "lib", "so", "dll", "dylib",
  "class", "pyc", "pyo", "pyd", "beam", "wasm",
  -- Keys/Certs (sensitive)
  "pem", "key", "crt", "cer", "p12", "pfx",
  -- ML models
  "h5", "hdf5", "pkl", "pickle", "pt", "pth", "onnx", "pb",
  "safetensors", "npy", "npz",
  -- Minified
  "min.js", "min.css", "bundle.js", "chunk.js",
  -- Maps
  "map",
  -- Lock files
  "lock",
  -- Tabular data
  "csv", "tsv",
  -- Line-delimited data
  "jsonl", "ndjson",
  -- Columnar/ML data
  "parquet", "arrow", "feather", "avro", "orc",
}

-- =============================================================================
-- Gitignore Parser
-- =============================================================================

---@class GitignorePattern
---@field pattern string The original pattern
---@field negated boolean Whether this is a negation pattern (!)
---@field lua_pattern string The converted Lua pattern
---@field anchored boolean Whether pattern is anchored to root (starts with /)
---@field dir_only boolean Whether pattern only matches directories (ends with /)

---Convert a gitignore pattern to Lua pattern
---@param pattern string
---@return string lua_pattern
---@return boolean anchored
---@return boolean dir_only
local function convert_gitignore_pattern(pattern)
  local anchored = false
  local dir_only = false

  -- Check for directory-only pattern (ends with /)
  if pattern:match("/$") then
    dir_only = true
    pattern = pattern:gsub("/$", "")
  end

  -- Check for anchored pattern (starts with /)
  if pattern:match("^/") then
    anchored = true
    pattern = pattern:gsub("^/", "")
  end

  -- If pattern contains / (not at start/end), it's anchored
  if pattern:match("/") then
    anchored = true
  end

  -- Convert to Lua pattern
  local lua_pattern = pattern
    -- Escape special characters first
    :gsub("([%.%+%-%^%$%(%)%[%]%%])", "%%%1")
    -- Handle **
    :gsub("%*%*", "<<<GLOBSTAR>>>")
    -- Handle *
    :gsub("%*", "[^/]*")
    -- Handle ?
    :gsub("%?", "[^/]")
    -- Restore **
    :gsub("<<<GLOBSTAR>>>", ".*")

  return lua_pattern, anchored, dir_only
end

---Parse .gitignore file and return structured patterns
---@param gitignore_path string
---@return GitignorePattern[] patterns
local function parse_gitignore(gitignore_path)
  local patterns = {}

  if vim.fn.filereadable(gitignore_path) ~= 1 then
    return patterns
  end

  local lines = vim.fn.readfile(gitignore_path)
  for _, line in ipairs(lines) do
    -- Skip empty lines and comments
    line = vim.trim(line)
    if line ~= "" and not line:match("^#") then
      local negated = false
      local raw_pattern = line

      -- Check for negation
      if line:match("^!") then
        negated = true
        raw_pattern = line:sub(2)
      end

      local lua_pattern, anchored, dir_only = convert_gitignore_pattern(raw_pattern)

      table.insert(patterns, {
        pattern = raw_pattern,
        negated = negated,
        lua_pattern = lua_pattern,
        anchored = anchored,
        dir_only = dir_only,
      })
    end
  end

  return patterns
end

---Check if a single pattern matches a path
---@param path string Relative path
---@param p GitignorePattern Pattern object
---@param is_dir boolean Whether the path is a directory
---@return boolean
local function pattern_matches(path, p, is_dir)
  -- If pattern is dir_only and path is not a directory, skip
  if p.dir_only and not is_dir then
    return false
  end

  local lua_pattern = p.lua_pattern

  if p.anchored then
    -- Anchored: must match from start
    if path:match("^" .. lua_pattern .. "$") then
      return true
    end
    if path:match("^" .. lua_pattern .. "/") then
      return true
    end
  else
    -- Not anchored: can match anywhere
    -- Match as full path
    if path:match("^" .. lua_pattern .. "$") then
      return true
    end
    -- Match as suffix after /
    if path:match("/" .. lua_pattern .. "$") then
      return true
    end
    -- Match as component
    if path:match("^" .. lua_pattern .. "/") then
      return true
    end
    if path:match("/" .. lua_pattern .. "/") then
      return true
    end
  end

  return false
end

---Check if a path matches gitignore patterns
---Patterns are processed in order; negation patterns can un-ignore
---@param path string Relative path
---@param patterns GitignorePattern[] Gitignore patterns
---@param is_dir boolean Whether the path is a directory
---@return boolean
local function matches_gitignore(path, patterns, is_dir)
  local ignored = false

  -- Process patterns in order - later patterns override earlier ones
  for _, p in ipairs(patterns) do
    if pattern_matches(path, p, is_dir) then
      if p.negated then
        ignored = false
      else
        ignored = true
      end
    end
  end

  return ignored
end

-- =============================================================================
-- File Classification
-- =============================================================================

---Check if filename is an excluded folder
---@param name string
---@return boolean
local function is_excluded_folder(name)
  for _, folder in ipairs(M.EXCLUDE_FOLDERS) do
    if name == folder then
      return true
    end
  end
  return false
end

---Check if filename is a config file
---@param name string
---@return boolean
local function is_config_file(name)
  for _, config in ipairs(M.CONFIG_FILES) do
    if name == config then
      return true
    end
  end
  return false
end

---Check if a path/name is an important project file worth surfacing in context.
---This intentionally reuses CONFIG_FILES so the scanner and context ranking agree.
---@param path string Relative path or filename
---@return boolean
function M.is_important_file(path)
  if not path or path == "" then
    return false
  end

  local normalized = path:gsub("\\", "/")
  local name = vim.fn.fnamemodify(normalized, ":t")

  if normalized:match("^%.github/workflows/[^/]+%.ya?ml$") then
    return true
  end

  -- Keep this as a root-level safety net, like Aider's important-file filter.
  -- Nested READMEs/configs are common in vendored docs/examples and add noise.
  if normalized:find("/", 1, true) then
    return false
  end

  if is_config_file(name) then
    return true
  end

  return false
end

---Check if extension is source code
---@param ext string
---@return boolean
local function is_source_extension(ext)
  if not ext then return false end
  ext = ext:lower()
  for _, source_ext in ipairs(M.SOURCE_EXTENSIONS) do
    if ext == source_ext then
      return true
    end
  end
  return false
end

---Check if extension is data/binary
---@param ext string
---@return boolean
local function is_data_extension(ext)
  if not ext then return false end
  ext = ext:lower()
  for _, data_ext in ipairs(M.DATA_EXTENSIONS) do
    if ext == data_ext then
      return true
    end
  end
  return false
end

-- Lock file patterns (these are data, not source)
local LOCK_FILE_PATTERNS = {
  "%-lock%.yaml$",     -- pnpm-lock.yaml
  "%-lock%.json$",     -- package-lock.json
  "%.lock$",           -- Cargo.lock, yarn.lock, etc.
  "^lockfile$",        -- Some projects use this
  "%.lockb$",          -- bun.lockb
}

-- Files to exclude (not useful for code understanding)
local EXCLUDED_FILES = {
  -- Changelogs (just lists of changes, often very long)
  "^changelog",        -- CHANGELOG, CHANGELOG.md, changelog.md
  "^history",          -- HISTORY.md
  "^news",             -- NEWS, NEWS.md
  "^releases",         -- RELEASES.md
  -- Legal files
  "^license",          -- LICENSE, LICENSE.md, LICENSE.txt
  "^licence",          -- British spelling
  "^copying",          -- COPYING
  "^copyright",        -- COPYRIGHT
  "^patents",          -- PATENTS
  -- Community files
  "^authors",          -- AUTHORS, AUTHORS.md
  "^contributors",     -- CONTRIBUTORS.md
  "^maintainers",      -- MAINTAINERS.md
  "^codeowners",       -- CODEOWNERS
  "^code[_-]of[_-]conduct", -- CODE_OF_CONDUCT.md
  "^security",         -- SECURITY.md
  "^funding",          -- FUNDING.yml
  -- Misc non-code docs
  "^install",          -- INSTALL.md (often long setup instructions)
  "^upgrading",        -- UPGRADING.md
  "^migration",        -- MIGRATION.md
  "^deprecat",         -- DEPRECATED.md
  -- Localized READMEs (keep main README but skip translations)
  "^readme%..+%.", -- README.zh-CN.md, README.ko.md, etc. (has dot before extension)
  -- Data files (large, not useful for code understanding)
  "%.data%.",         -- *.data.json, *.data.yaml, etc.
  "%.sample%.",       -- *.sample.json, *.sample.yml, etc.
  "^dataset",         -- dataset.json, datasets/
  "^data%-",           -- data-config.json, etc.
}

---Check if filename should be excluded
---@param filename string
---@return boolean
local function is_excluded_file(filename)
  local lower = filename:lower()
  for _, pattern in ipairs(EXCLUDED_FILES) do
    if lower:match(pattern) then
      return true
    end
  end
  return false
end

---Check if filename is a lock file
---@param filename string
---@return boolean
local function is_lock_file(filename)
  local lower = filename:lower()
  for _, pattern in ipairs(LOCK_FILE_PATTERNS) do
    if lower:match(pattern) then
      return true
    end
  end
  return false
end

---Classify a file
---@param filepath string Full path
---@param filename string Just the filename
---@return string "source"|"config"|"data"|"unknown"
local function classify_file(filepath, filename)
  -- Get extension
  local ext = filename:match("%.([^.]+)$")
  local ext_lower = ext and ext:lower() or ""

  -- 1. Source code extensions ALWAYS take highest priority (never dropped by doc regexes)
  if is_source_extension(ext_lower) then
    -- Check for minified files or lockfiles
    if filename:match("%.min%.[a-z]+$") or filename:match("%.bundle%.js$") or filename:match("%.chunk%.js$") or is_lock_file(filename) then
      return "data"
    end
    return "source"
  end

  -- 2. Config files (exact match)
  if is_config_file(filename) then
    return "config"
  end

  -- 3. Check for lock files (these are data, not useful for context)
  if is_lock_file(filename) then
    return "data"
  end

  -- 4. Check for minified files
  if filename:match("%.min%.js$") or filename:match("%.min%.css$")
    or filename:match("%.bundle%.js$") or filename:match("%.chunk%.js$") then
    return "data"
  end

  -- 5. Excluded doc/changelog files (only applies to non-code files)
  if is_excluded_file(filename) then
    return "data"
  end

  -- 6. Check data extensions
  if is_data_extension(ext_lower) then
    return "data"
  end

  -- 7. In dedicated data folders (e.g. data/, results/), data/config extensions are data, not source
  if is_in_data_folder(filepath) and ext_lower ~= "" then
    local data_exts = {
      json = true, jsonc = true, yaml = true, yml = true, toml = true,
      xml = true, sql = true, csv = true, tsv = true, txt = true,
      log = true, md = true, markdown = true, rst = true,
    }
    if data_exts[ext_lower] then
      return "data"
    end
  end

  -- 8. Files starting with . that aren't config are usually hidden/system
  if filename:match("^%.") and not is_config_file(filename) then
    return "unknown"
  end

  return "unknown"
end

-- =============================================================================
-- Project Scanning
-- =============================================================================

---@class ProjectFile
---@field path string Relative path
---@field name string Filename
---@field type string "source"|"config"|"data"|"unknown"
---@field size number File size in bytes
---@field lines number|nil Line count (for source/config)

---@class ProjectFolder
---@field path string Relative path
---@field name string Folder name
---@field file_count number Number of files inside
---@field has_source boolean Contains source files
---@field truncated boolean If true, folder has many files (not fully listed)

---@class ProjectScanResult
---@field root string Project root path
---@field files ProjectFile[] All scanned files
---@field folders ProjectFolder[] Folder information
---@field total_tokens number Estimated total tokens (source + config)
---@field source_tokens number Estimated tokens for source code only
---@field tree_structure string Formatted tree structure

local _root_cache = {}

---Get project root from a specific file path (or current buffer)
---Uses vim.fs.root for zero-fork in-memory detection with fallback
---@param filepath? string File path to find project root for
---@return string
function M.get_project_root(filepath)
  local target_path = filepath
  if not target_path or target_path == "" then
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file and current_file ~= "" then
      target_path = current_file
    end
  end

  local dir
  if target_path and target_path ~= "" then
    dir = vim.fn.fnamemodify(target_path, ":p:h")
  else
    dir = vim.fn.getcwd()
  end

  if _root_cache[dir] then
    return _root_cache[dir]
  end

  -- Fast path: use vim.fs.root (Neovim >= 0.10, zero subprocess fork)
  if vim.fs and vim.fs.root then
    local root = vim.fs.root(dir, {
      ".git",
      "pnpm-workspace.yaml",
      "lerna.json",
      "turbo.json",
      "Cargo.toml",
      "pyproject.toml",
      "package.json",
      "go.mod",
      "Makefile",
    })
    if root and root ~= "" then
      _root_cache[dir] = root
      return root
    end
  end

  -- Fallback to git rev-parse if vim.fs.root did not find a marker
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")[1]
  if git_root and git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    _root_cache[dir] = git_root
    return git_root
  end

  _root_cache[dir] = dir
  return dir
end

---Estimate tokens with calibration for code symbols and multi-byte UTF-8
---@param text string
---@return number
function M.estimate_tokens(text)
  if not text or text == "" then return 0 end
  local bytes = #text
  local chars = vim.fn.strchars(text)
  local multibyte_count = bytes - chars

  -- Code and symbols average ~3.2 chars per token
  -- Non-ASCII multi-byte characters (Vietnamese, CJK) average ~1.2 tokens per character
  local base_tokens = chars / 3.2
  local unicode_penalty = multibyte_count * 0.6

  return math.ceil(base_tokens + unicode_penalty)
end

---Get language identifier for syntax highlighting
---@param ext string File extension
---@return string language
function M.get_language_for_ext(ext)
  if not ext or ext == "" then return "" end
  ext = ext:lower()

  local lang_map = {
    -- Web
    js = "javascript", jsx = "javascript", mjs = "javascript", cjs = "javascript",
    ts = "typescript", tsx = "typescript",
    vue = "vue", svelte = "svelte", astro = "astro",
    html = "html", htm = "html",
    css = "css", scss = "scss", sass = "sass", less = "less",
    -- Systems
    c = "c", h = "c",
    cpp = "cpp", cc = "cpp", cxx = "cpp", hpp = "cpp", hxx = "cpp",
    rs = "rust", go = "go", zig = "zig", odin = "odin",
    -- JVM
    java = "java", kt = "kotlin", kts = "kotlin", scala = "scala",
    clj = "clojure", cljs = "clojure", groovy = "groovy",
    -- .NET
    cs = "csharp", fs = "fsharp", vb = "vb",
    -- Scripting
    py = "python", pyw = "python", pyi = "python",
    rb = "ruby", rake = "ruby",
    pl = "perl", pm = "perl",
    php = "php",
    lua = "lua",
    sh = "bash", bash = "bash", zsh = "zsh", fish = "fish",
    ps1 = "powershell", psm1 = "powershell",
    -- Mobile
    swift = "swift", m = "objc", mm = "objc", dart = "dart",
    -- Functional
    hs = "haskell", ml = "ocaml", mli = "ocaml",
    erl = "erlang", ex = "elixir", exs = "elixir",
    elm = "elm", lisp = "lisp", el = "elisp", scm = "scheme", rkt = "racket",
    -- Config/Data
    json = "json", jsonc = "jsonc",
    yaml = "yaml", yml = "yaml",
    toml = "toml",
    xml = "xml",
    ini = "ini", cfg = "ini", conf = "ini",
    -- Markup
    md = "markdown", markdown = "markdown",
    rst = "rst", adoc = "asciidoc", org = "org", tex = "latex",
    -- Query
    sql = "sql", graphql = "graphql", gql = "graphql",
    -- Templates
    ejs = "ejs", erb = "erb", haml = "haml", pug = "pug",
    hbs = "handlebars", jinja = "jinja2", j2 = "jinja2",
    liquid = "liquid", twig = "twig",
    -- Shaders
    glsl = "glsl", hlsl = "hlsl", wgsl = "wgsl", metal = "metal",
    -- Other
    r = "r", jl = "julia", proto = "protobuf",
  }

  return lang_map[ext] or ext
end

---Score core folder priority (src, lib, app, core, etc.)
---@param name string
---@return number
local function core_folder_score(name)
  local lower = name:lower()
  if lower == "src" or lower == "source" then return 100 end
  if lower == "lib" then return 95 end
  if lower == "app" or lower == "core" or lower == "pkg" or lower == "internal" then return 90 end
  if lower == "lua" or lower == "packages" or lower == "modules" then return 85 end
  return 0
end

---Get display priority for a folder
---@param folder ProjectFolder
---@return number
local function get_folder_priority(folder)
  local name = folder.name:lower()

  -- Tier 1: Core Source Folders (Top Priority - always rendered first)
  local core_score = core_folder_score(name)
  if core_score > 0 then
    return core_score
  end

  -- Tier 2: Any folder that contains source code
  if folder.has_source then
    -- Secondary source / test / doc folders
    if name:match("^test") or name:match("^spec") or name == "__tests__" then
      return 50
    elseif name == "docs" or name == "doc" or name == "examples" or name == "scripts" or name == "tools" then
      return 45
    else
      return 70 -- Standard source component (e.g. models, utils, api, controllers)
    end
  end

  -- Tier 3: Non-source utility folders
  if name == "docs" or name == "doc" or name == "scripts" or name == "tools" or name == "config" then
    return 30
  end

  -- Tier 4: Data / Output / Benchmark folders (Lowest priority)
  if is_data_folder_name(name) then
    return 10
  end

  -- Default for other folders without source
  return 20
end

---Get display priority for a file
---@param file ProjectFile
---@return number
local function get_file_priority(file)
  local name = file.name:lower()

  -- Tier 1: Key Entry Points (always show first)
  local entry_points = {
    ["main.py"] = 100, ["app.py"] = 98, ["index.ts"] = 98, ["index.js"] = 98,
    ["init.lua"] = 98, ["lib.rs"] = 98, ["main.rs"] = 98, ["main.go"] = 98,
    ["__init__.py"] = 95, ["mod.rs"] = 95,
  }
  if entry_points[name] then
    return entry_points[name]
  end

  -- Tier 2: Source Code Files
  if file.type == "source" then
    return 75
  end

  -- Tier 3: Project Configuration / Manifest
  if file.type == "config" then
    return 60
  end

  -- Tier 4: Documentation (README, etc.)
  if name:match("^readme") or name:match("%.md$") then
    return 40
  end

  -- Tier 5: Data / Other files
  return 20
end

---Scan project and return structured result
---@param opts? table {root?: string, max_file_lines?: number}
---@return ProjectScanResult
function M.scan_project(opts)
  opts = opts or {}
  local root = opts.root or M.get_project_root()
  local max_file_lines = opts.max_file_lines or 1000

  -- Parse .gitignore
  local gitignore_patterns = parse_gitignore(root .. "/.gitignore")

  local files = {}
  local folders = {}
  local folder_stats = {} -- Track stats per folder

  local MAX_SCAN_DEPTH = 12
  local MAX_SUBDIRS_PER_FOLDER = 50
  local MAX_TOTAL_FOLDERS = 800
  local total_folders_scanned = 0
  local seen_inodes = {}

  ---Scan directory recursively
  ---@param dir string
  ---@param rel_path string
  ---@param depth? number
  local function scan_dir(dir, rel_path, depth)
    depth = depth or 0
    if depth > MAX_SCAN_DEPTH or total_folders_scanned >= MAX_TOTAL_FOLDERS then
      return
    end
    total_folders_scanned = total_folders_scanned + 1

    local handle = vim.loop.fs_scandir(dir)
    if not handle then return end

    local dir_items = {}
    local file_items = {}
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      -- Resolve directory symlinks
      if type == "link" then
        local stat = vim.loop.fs_stat(dir .. "/" .. name)
        if stat then
          type = stat.type
        end
      end
      if type == "directory" then
        table.insert(dir_items, name)
      else
        table.insert(file_items, name)
      end
    end

    -- If inside a dedicated data folder (outside core source tree), stop recursing into deep subdirs
    local is_data_dir = is_in_data_folder(rel_path)
    if is_data_dir and depth > 0 then
      if folder_stats[rel_path] then
        folder_stats[rel_path].files = #file_items + #dir_items
        folder_stats[rel_path].has_source = false
      end
      return
    end

    -- Filter out excluded and gitignored directories
    local valid_dirs = {}
    for _, name in ipairs(dir_items) do
      local item_rel_path = rel_path == "" and name or (rel_path .. "/" .. name)
      if not is_excluded_folder(name) and not matches_gitignore(item_rel_path, gitignore_patterns, true) then
        table.insert(valid_dirs, name)
      end
    end

    -- If folder has too many subdirectories (e.g. 10,000 subfolders), cap and sort by core priority
    local excess_dirs_count = 0
    if #valid_dirs > MAX_SUBDIRS_PER_FOLDER then
      excess_dirs_count = #valid_dirs - MAX_SUBDIRS_PER_FOLDER
      table.sort(valid_dirs, function(a, b)
        local pa = core_folder_score(a)
        local pb = core_folder_score(b)
        if pa ~= pb then return pa > pb end
        return a < b
      end)
      valid_dirs = vim.list_slice(valid_dirs, 1, MAX_SUBDIRS_PER_FOLDER)
    else
      table.sort(valid_dirs, function(a, b)
        local pa = core_folder_score(a)
        local pb = core_folder_score(b)
        if pa ~= pb then return pa > pb end
        return a < b
      end)
    end

    local source_count = 0
    local total_count = 0

    for _, name in ipairs(valid_dirs) do
      local full_path = dir .. "/" .. name
      local item_rel_path = rel_path == "" and name or (rel_path .. "/" .. name)

      -- Prevent cyclic symlinks via inode tracking
      local stat = vim.loop.fs_stat(full_path)
      if stat and stat.dev and stat.ino then
        local ino_key = stat.dev .. ":" .. stat.ino
        if seen_inodes[ino_key] then
          goto continue_dir
        end
        seen_inodes[ino_key] = true
      end

      -- Initialize folder stats
      folder_stats[item_rel_path] = { files = 0, has_source = false }

      -- Recurse
      scan_dir(full_path, item_rel_path, depth + 1)

      -- Get folder info
      local stats = folder_stats[item_rel_path]
      local truncated = stats.files > 50

      table.insert(folders, {
        path = item_rel_path,
        name = name,
        file_count = stats.files,
        has_source = stats.has_source,
        truncated = truncated,
      })

      -- Propagate stats to parent
      if rel_path ~= "" and folder_stats[rel_path] then
        folder_stats[rel_path].files = folder_stats[rel_path].files + stats.files
        folder_stats[rel_path].has_source = folder_stats[rel_path].has_source or stats.has_source
      end

      ::continue_dir::
    end

    if excess_dirs_count > 0 and rel_path ~= "" and folder_stats[rel_path] then
      folder_stats[rel_path].files = folder_stats[rel_path].files + excess_dirs_count
    end

    for _, name in ipairs(file_items) do
      local full_path = dir .. "/" .. name
      local item_rel_path = rel_path == "" and name or (rel_path .. "/" .. name)

      -- Skip gitignored
      if matches_gitignore(item_rel_path, gitignore_patterns, false) then
        goto continue_file
      end

      total_count = total_count + 1

      -- Classify file
      local file_type = classify_file(full_path, name)

      -- Update folder stats
      if rel_path ~= "" and folder_stats[rel_path] then
        folder_stats[rel_path].files = folder_stats[rel_path].files + 1
        if file_type == "source" or file_type == "config" then
          folder_stats[rel_path].has_source = true
        end
      end

      -- Only include source and config files
      if file_type == "source" or file_type == "config" then
        local stat = vim.loop.fs_stat(full_path)
        local size = stat and stat.size or 0

        -- Skip very large files (likely test fixtures, generated data, etc.)
        local max_file_size = 100 * 1024  -- 100KB
        local in_test_dir = item_rel_path:match("test") or item_rel_path:match("spec")
                        or item_rel_path:match("fixture") or item_rel_path:match("__snapshots__")
        if in_test_dir then
          max_file_size = 50 * 1024  -- 50KB for test files
        end

        if size > max_file_size then
          goto continue_file
        end

        source_count = source_count + 1
        local lines = nil

        local ok, content = pcall(vim.fn.readfile, full_path)
        if ok then
          lines = #content
        end

        table.insert(files, {
          path = item_rel_path,
          name = name,
          type = file_type,
          size = size,
          lines = lines,
        })
      end

      ::continue_file::
    end
  end

  scan_dir(root, "", 0)

  -- Build tree structure
  local tree = M.build_tree_structure(root, files, folders)

  -- Calculate tokens: separate source code from config/docs
  -- Rough estimate: average 40 chars per line, 4 chars per token = 10 tokens per line
  local total_tokens = 0
  local source_tokens = 0
  for _, file in ipairs(files) do
    if file.lines then
      local file_tokens = file.lines * 10
      total_tokens = total_tokens + file_tokens
      if file.type == "source" then
        source_tokens = source_tokens + file_tokens
      end
    end
  end
  local tree_token_est = M.estimate_tokens(tree)
  total_tokens = total_tokens + tree_token_est
  source_tokens = source_tokens + tree_token_est

  return {
    root = root,
    files = files,
    folders = folders,
    total_tokens = total_tokens,
    source_tokens = source_tokens,
    tree_structure = tree,
  }
end

---Build tree structure string for display
---Shows source folders in detail, data folders as summary
---@param root string
---@param files ProjectFile[]
---@param folders ProjectFolder[]
---@return string
function M.build_tree_structure(root, files, folders)
  local lines = {}
  local root_name = vim.fn.fnamemodify(root, ":t")
  table.insert(lines, root_name .. "/")

  -- Build folder lookup by parent folder in O(N)
  local folders_by_parent = { [""] = {} }
  for _, folder in ipairs(folders) do
    local parent = vim.fn.fnamemodify(folder.path, ":h")
    if parent == "." then parent = "" end
    if not folders_by_parent[parent] then
      folders_by_parent[parent] = {}
    end
    table.insert(folders_by_parent[parent], folder)
  end

  -- Build file lookup by parent folder in O(N)
  local files_by_folder = { [""] = {} }
  for _, file in ipairs(files) do
    local parent = vim.fn.fnamemodify(file.path, ":h")
    if parent == "." then parent = "" end
    if not files_by_folder[parent] then
      files_by_folder[parent] = {}
    end
    table.insert(files_by_folder[parent], file)
  end

  -- Get direct children of a folder path in O(1)
  local function get_children(parent_path)
    local children_folders = folders_by_parent[parent_path] or {}
    local children_files = files_by_folder[parent_path] or {}

    -- Sort folders with priority: Core source (src, lib) first, then source folders, data folders last
    table.sort(children_folders, function(a, b)
      local pa = get_folder_priority(a)
      local pb = get_folder_priority(b)
      if pa ~= pb then
        return pa > pb
      end
      return a.name < b.name
    end)

    -- Sort files with priority: entry points first, source files next, config/data last
    table.sort(children_files, function(a, b)
      local pa = get_file_priority(a)
      local pb = get_file_priority(b)
      if pa ~= pb then
        return pa > pb
      end
      return a.name < b.name
    end)

    return children_folders, children_files
  end

  -- Recursive function to build tree
  local function build_subtree(parent_path, prefix)
    local child_folders, child_files = get_children(parent_path)

    -- Limit folders per directory to prevent 10,000 subfolders explosion
    local max_folders_per_dir = 20
    local extra_folders = 0
    if #child_folders > max_folders_per_dir then
      extra_folders = #child_folders - max_folders_per_dir
      child_folders = vim.list_slice(child_folders, 1, max_folders_per_dir)
    end

    -- Limit files per folder to prevent huge directories from dominating the tree
    local max_files_per_dir = 25
    local extra_files = 0
    if #child_files > max_files_per_dir then
      extra_files = #child_files - max_files_per_dir
      child_files = vim.list_slice(child_files, 1, max_files_per_dir)
    end

    -- Combine into one list for proper last-item detection
    local items = {}
    for _, folder in ipairs(child_folders) do
      table.insert(items, { type = "folder", data = folder })
    end
    if extra_folders > 0 then
      table.insert(items, { type = "more_folders", count = extra_folders })
    end
    for _, file in ipairs(child_files) do
      table.insert(items, { type = "file", data = file })
    end
    if extra_files > 0 then
      table.insert(items, { type = "more_files", count = extra_files })
    end

    for i, item in ipairs(items) do
      local is_last = (i == #items)
      local connector = is_last and "`-- " or "|-- "
      local child_prefix = prefix .. (is_last and "    " or "|   ")

      if item.type == "more_folders" then
        table.insert(lines, prefix .. connector .. string.format("... (%d more directories)", item.count))
      elseif item.type == "more_files" then
        table.insert(lines, prefix .. connector .. string.format("... (%d more files)", item.count))
      elseif item.type == "folder" then
        local folder = item.data
        if folder.has_source then
          -- Source folder: show in detail
          table.insert(lines, prefix .. connector .. folder.name .. "/")
          build_subtree(folder.path, child_prefix)
        elseif folder.file_count > 0 then
          -- Data folder: show summary only
          table.insert(lines, prefix .. connector .. folder.name .. "/  (" .. folder.file_count .. " files)")
        else
          -- Empty folder (rare)
          table.insert(lines, prefix .. connector .. folder.name .. "/")
        end
      else
        -- File
        local file = item.data
        local size_info = file.lines and string.format(" (%d lines)", file.lines) or ""
        table.insert(lines, prefix .. connector .. file.name .. size_info)
      end
    end
  end

  -- Build from root
  build_subtree("", "")

  return table.concat(lines, "\n")
end

---Read all source files and return combined content
---@param scan_result ProjectScanResult
---@param opts? table {max_lines_per_file?: number}
---@return string content
---@return table metadata {files_included, total_lines, total_tokens}
function M.read_all_sources(scan_result, opts)
  opts = opts or {}
  local max_lines = opts.max_lines_per_file or 1000

  local parts = {}
  local files_included = {}
  local total_lines = 0
  local total_tokens = 0

  -- Get project root name for file path prefix
  local root_name = vim.fn.fnamemodify(scan_result.root, ":t")

  for _, file in ipairs(scan_result.files) do
    if file.type == "source" or file.type == "config" then
      local full_path = scan_result.root .. "/" .. file.path

      local ok, lines = pcall(vim.fn.readfile, full_path)
      if ok and lines then
        local line_count = #lines
        local content = table.concat(lines, "\n")

        -- Truncate if too long
        if line_count > max_lines then
          lines = vim.list_slice(lines, 1, max_lines)
          content = table.concat(lines, "\n") .. "\n... (truncated, " .. line_count .. " total lines)"
          line_count = max_lines
        end

        -- Get language for syntax highlighting
        local ext = file.name:match("%.([^.]+)$") or ""
        local lang = M.get_language_for_ext(ext)

        -- File path from project root: ai-editutor/lua/editutor/file.lua
        local display_path = root_name .. "/" .. file.path

        table.insert(parts, string.format("// File: %s", display_path))
        table.insert(parts, "```" .. lang)
        table.insert(parts, content)
        table.insert(parts, "```")
        table.insert(parts, "")

        table.insert(files_included, {
          path = display_path,
          lines = line_count,
          tokens = M.estimate_tokens(content),
        })

        total_lines = total_lines + line_count
        total_tokens = total_tokens + M.estimate_tokens(content)
      end
    end
  end

  return table.concat(parts, "\n"), {
    files_included = files_included,
    total_lines = total_lines,
    total_tokens = total_tokens,
  }
end

---Ensure editutor log files are in .gitignore
---@param project_root string
function M.ensure_gitignore_entry(project_root)
  local gitignore_path = project_root .. "/.gitignore"
  local entry = ".editutor/editutor.log*"

  -- Read existing content
  local lines = {}
  if vim.fn.filereadable(gitignore_path) == 1 then
    lines = vim.fn.readfile(gitignore_path)

    -- Check if already present
    for _, line in ipairs(lines) do
      local trimmed = vim.trim(line)
      if trimmed == entry or trimmed == ".editutor.log" then
        return -- Already present
      end
    end
  end

  -- Add entry
  table.insert(lines, entry)
  vim.fn.writefile(lines, gitignore_path)
end

return M
