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
  -- Check for excluded files first (not useful for code understanding)
  if is_excluded_file(filename) then
    return "data"  -- Treat as data so it won't be included
  end

  -- Check config files (exact match)
  if is_config_file(filename) then
    return "config"
  end

  -- Check for lock files (these are data, not useful for context)
  if is_lock_file(filename) then
    return "data"
  end

  -- Get extension
  local ext = filename:match("%.([^.]+)$")

  -- Check for minified files
  if filename:match("%.min%.js$") or filename:match("%.min%.css$")
    or filename:match("%.bundle%.js$") or filename:match("%.chunk%.js$") then
    return "data"
  end

  -- Check data extensions
  if is_data_extension(ext) then
    return "data"
  end

  -- Check source extensions
  if is_source_extension(ext) then
    return "source"
  end

  -- Files starting with . that aren't config are usually hidden/system
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
---@field total_tokens number Estimated total tokens
---@field tree_structure string Formatted tree structure

---Get project root from a specific file path (or current buffer)
---@param filepath? string File path to find project root for
---@return string
function M.get_project_root(filepath)
  -- If filepath provided, find git root from that directory
  if filepath and filepath ~= "" then
    local dir = vim.fn.fnamemodify(filepath, ":h")
    if vim.fn.isdirectory(dir) == 1 then
      local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")[1]
      if git_root and git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
        return git_root
      end
      -- Fallback: return the directory containing the file
      return dir
    end
  end
  
  -- Fallback to current buffer's file
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file and current_file ~= "" then
    local dir = vim.fn.fnamemodify(current_file, ":h")
    if vim.fn.isdirectory(dir) == 1 then
      local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")[1]
      if git_root and git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
        return git_root
      end
    end
  end
  
  -- Last fallback: CWD
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
  if git_root and git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    return git_root
  end
  return vim.fn.getcwd()
end

---Estimate tokens from text (rough: 1 token ~ 4 chars)
---@param text string
---@return number
function M.estimate_tokens(text)
  return math.ceil(#text / 4)
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
    rs = "rust", go = "go", zig = "zig",
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

  ---Scan directory recursively
  ---@param dir string
  ---@param rel_path string
  local function scan_dir(dir, rel_path)
    local handle = vim.loop.fs_scandir(dir)
    if not handle then return end

    local items = {}
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      table.insert(items, { name = name, type = type })
    end

    -- Sort: folders first, then alphabetically
    table.sort(items, function(a, b)
      if a.type == "directory" and b.type ~= "directory" then return true end
      if a.type ~= "directory" and b.type == "directory" then return false end
      return a.name < b.name
    end)

    local source_count = 0
    local total_count = 0

    for _, item in ipairs(items) do
      local name = item.name
      local item_type = item.type
      local full_path = dir .. "/" .. name
      local item_rel_path = rel_path == "" and name or (rel_path .. "/" .. name)

      -- Skip excluded folders
      if item_type == "directory" and is_excluded_folder(name) then
        goto continue
      end

      -- Skip gitignored
      local is_dir = (item_type == "directory")
      if matches_gitignore(item_rel_path, gitignore_patterns, is_dir) then
        goto continue
      end

      if item_type == "directory" then
        -- Initialize folder stats
        folder_stats[item_rel_path] = { files = 0, has_source = false }

        -- Recurse
        scan_dir(full_path, item_rel_path)

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

      elseif item_type == "file" then
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
          -- 100KB is generous for most source files
          local max_file_size = 100 * 1024  -- 100KB

          -- Allow larger files for main source (not in test directories)
          local in_test_dir = item_rel_path:match("test") or item_rel_path:match("spec")
                          or item_rel_path:match("fixture") or item_rel_path:match("__snapshots__")
          if in_test_dir then
            max_file_size = 50 * 1024  -- 50KB for test files
          end

          if size > max_file_size then
            -- Skip large files (likely generated/fixture data)
            goto continue
          end

          source_count = source_count + 1
          local lines = nil

          -- Read line count for source/config
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
      end

      ::continue::
    end
  end

  scan_dir(root, "")

  -- Build tree structure
  local tree = M.build_tree_structure(root, files, folders)

  -- Calculate total tokens
  -- Rough estimate: average 40 chars per line, 4 chars per token = 10 tokens per line
  local total_tokens = 0
  for _, file in ipairs(files) do
    if file.lines then
      total_tokens = total_tokens + (file.lines * 10)
    end
  end
  total_tokens = total_tokens + M.estimate_tokens(tree)

  return {
    root = root,
    files = files,
    folders = folders,
    total_tokens = total_tokens,
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

  -- Build folder lookup
  local folder_lookup = {}
  for _, folder in ipairs(folders) do
    folder_lookup[folder.path] = folder
  end

  -- Build file lookup by parent folder
  local files_by_folder = { [""] = {} }
  for _, file in ipairs(files) do
    local parent = vim.fn.fnamemodify(file.path, ":h")
    if parent == "." then parent = "" end
    if not files_by_folder[parent] then
      files_by_folder[parent] = {}
    end
    table.insert(files_by_folder[parent], file)
  end

  -- Get direct children of a folder path
  local function get_children(parent_path)
    local children_folders = {}
    local children_files = files_by_folder[parent_path] or {}

    for _, folder in ipairs(folders) do
      local folder_parent = vim.fn.fnamemodify(folder.path, ":h")
      if folder_parent == "." then folder_parent = "" end
      if folder_parent == parent_path then
        table.insert(children_folders, folder)
      end
    end

    -- Sort alphabetically
    table.sort(children_folders, function(a, b) return a.name < b.name end)
    table.sort(children_files, function(a, b) return a.name < b.name end)

    return children_folders, children_files
  end

  -- Recursive function to build tree
  local function build_subtree(parent_path, prefix)
    local child_folders, child_files = get_children(parent_path)

    -- Combine into one list for proper last-item detection
    local items = {}
    for _, folder in ipairs(child_folders) do
      table.insert(items, { type = "folder", data = folder })
    end
    for _, file in ipairs(child_files) do
      table.insert(items, { type = "file", data = file })
    end

    for i, item in ipairs(items) do
      local is_last = (i == #items)
      local connector = is_last and "`-- " or "|-- "
      local child_prefix = prefix .. (is_last and "    " or "|   ")

      if item.type == "folder" then
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

---Ensure .editutor.log is in .gitignore
---@param project_root string
function M.ensure_gitignore_entry(project_root)
  local gitignore_path = project_root .. "/.gitignore"
  local entry = ".editutor.log"

  -- Read existing content
  local lines = {}
  if vim.fn.filereadable(gitignore_path) == 1 then
    lines = vim.fn.readfile(gitignore_path)

    -- Check if already present
    for _, line in ipairs(lines) do
      if vim.trim(line) == entry then
        return -- Already present
      end
    end
  end

  -- Add entry
  table.insert(lines, entry)
  vim.fn.writefile(lines, gitignore_path)
end

return M
