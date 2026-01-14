-- tests/manual_lsp_test.lua
-- Manual test script to verify LSP context extraction behavior
--
-- HOW TO USE:
-- 1. Open Neovim in the fixture project directory
-- 2. Open the file containing Q: comment
-- 3. Position cursor on the Q: line
-- 4. Run: :luafile tests/manual_lsp_test.lua
-- 5. Check the output in the floating window
--
-- Or run specific test:
-- :lua require('tests.manual_lsp_test').test_typescript_fullstack()

local M = {}

-- Configuration
local FIXTURES_PATH = vim.fn.fnamemodify("tests/fixtures", ":p")
local RESULTS = {}

-- Helper: Print with highlight
local function log(msg, level)
  level = level or "INFO"
  local hl = {
    INFO = "Normal",
    OK = "DiagnosticOk",
    WARN = "DiagnosticWarn",
    ERROR = "DiagnosticError",
    HEADER = "Title",
  }
  vim.api.nvim_echo({{msg .. "\n", hl[level] or "Normal"}}, true, {})
  table.insert(RESULTS, {msg = msg, level = level})
end

-- Helper: Check if file path contains expected string
local function path_contains(path, expected)
  return path and path:lower():find(expected:lower(), 1, true) ~= nil
end

-- Helper: Read file content
local function read_file(filepath)
  local f = io.open(filepath, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

-- Helper: Find Q: comment line number
local function find_q_line(content, prefix)
  prefix = prefix or "//"
  local line_num = 0
  for line in content:gmatch("[^\n]+") do
    line_num = line_num + 1
    if line:match(prefix .. "%s*Q:") then
      return line_num, line
    end
  end
  return nil, nil
end

-- Core test function: Gather LSP context and verify relevance
local function test_lsp_context(opts)
  local filepath = opts.filepath
  local comment_prefix = opts.comment_prefix or "//"
  local expected_files = opts.expected_files or {}
  local expected_symbols = opts.expected_symbols or {}
  local description = opts.description or filepath

  log("=" .. string.rep("=", 60), "HEADER")
  log("Testing: " .. description, "HEADER")
  log("File: " .. filepath)

  -- Read file
  local content = read_file(filepath)
  if not content then
    log("ERROR: Cannot read file: " .. filepath, "ERROR")
    return false
  end

  -- Find Q: line
  local q_line_num, q_line = find_q_line(content, comment_prefix)
  if not q_line_num then
    log("ERROR: No Q: comment found in file", "ERROR")
    return false
  end
  log("Found Q: at line " .. q_line_num .. ": " .. q_line:sub(1, 80))

  -- Open file in buffer
  vim.cmd("edit " .. filepath)
  local bufnr = vim.api.nvim_get_current_buf()

  -- Wait for LSP to attach
  vim.wait(2000, function()
    return #vim.lsp.get_clients({bufnr = bufnr}) > 0
  end)

  local clients = vim.lsp.get_clients({bufnr = bufnr})
  if #clients == 0 then
    log("WARN: No LSP client attached (LSP may not be configured)", "WARN")
    log("Skipping LSP context test - checking file structure only", "WARN")

    -- Fall back to checking imports exist
    local imports_ok = true
    for _, expected in ipairs(expected_files) do
      if content:find(expected, 1, true) then
        log("  [IMPORT OK] Found reference to: " .. expected, "OK")
      else
        log("  [IMPORT MISSING] Expected reference to: " .. expected, "WARN")
        imports_ok = false
      end
    end
    return imports_ok
  end

  log("LSP clients: " .. table.concat(vim.tbl_map(function(c) return c.name end, clients), ", "))

  -- Position cursor at Q: line
  vim.api.nvim_win_set_cursor(0, {q_line_num, 0})

  -- Try to gather LSP context
  local lsp_context_ok, lsp_context = pcall(require, "editutor.lsp_context")
  if not lsp_context_ok then
    log("WARN: editutor.lsp_context not available", "WARN")
    return false
  end

  -- Gather context
  log("Gathering LSP context...")
  local gathered = lsp_context.gather(bufnr, q_line_num)

  if not gathered or vim.tbl_isempty(gathered) then
    log("WARN: No context gathered from LSP", "WARN")
    return false
  end

  -- Check gathered files
  log("Gathered " .. vim.tbl_count(gathered) .. " context items:")

  local found_files = {}
  for symbol, data in pairs(gathered) do
    local file = data.filepath or data.file or ""
    log("  - " .. symbol .. " -> " .. vim.fn.fnamemodify(file, ":t"))
    table.insert(found_files, file)
  end

  -- Verify expected files were gathered
  local all_found = true
  log("\nVerifying expected context:")
  for _, expected in ipairs(expected_files) do
    local found = false
    for _, file in ipairs(found_files) do
      if path_contains(file, expected) then
        found = true
        break
      end
    end
    if found then
      log("  [OK] Found: " .. expected, "OK")
    else
      log("  [MISSING] Expected: " .. expected, "ERROR")
      all_found = false
    end
  end

  -- Verify expected symbols
  if #expected_symbols > 0 then
    log("\nVerifying expected symbols:")
    for _, symbol in ipairs(expected_symbols) do
      if gathered[symbol] then
        log("  [OK] Found symbol: " .. symbol, "OK")
      else
        log("  [MISSING] Expected symbol: " .. symbol, "ERROR")
        all_found = false
      end
    end
  end

  return all_found
end

-- Test: TypeScript Fullstack
function M.test_typescript_fullstack()
  RESULTS = {}
  local base = FIXTURES_PATH .. "typescript-fullstack/"

  -- Test 1: API Client - token refresh question
  test_lsp_context({
    filepath = base .. "src/api/client.ts",
    description = "TypeScript: API Client (token refresh race condition)",
    expected_files = {"authService", "config", "auth.ts"},
    expected_symbols = {"refreshToken", "apiClient"},
  })

  -- Test 2: useAuth hook
  test_lsp_context({
    filepath = base .. "src/hooks/useAuth.ts",
    description = "TypeScript: useAuth hook (session persistence)",
    expected_files = {"authService", "storage", "auth.ts"},
  })

  -- Test 3: useUsers hook
  test_lsp_context({
    filepath = base .. "src/hooks/useUsers.ts",
    description = "TypeScript: useUsers hook (optimistic updates)",
    expected_files = {"userService", "user.ts"},
  })

  M.print_summary()
end

-- Test: Python Django
function M.test_python_django()
  RESULTS = {}
  local base = FIXTURES_PATH .. "python-django/"

  test_lsp_context({
    filepath = base .. "myapp/serializers/user.py",
    comment_prefix = "#",
    description = "Python: User Serializer (race condition)",
    expected_files = {"models/user", "validators"},
  })

  test_lsp_context({
    filepath = base .. "myapp/views/user.py",
    comment_prefix = "#",
    description = "Python: User Views (concurrent updates)",
    expected_files = {"user_service", "serializers"},
  })

  test_lsp_context({
    filepath = base .. "myapp/services/user_service.py",
    comment_prefix = "#",
    description = "Python: User Service (bulk operations)",
    expected_files = {"models/user", "email_service"},
  })

  M.print_summary()
end

-- Test: Go Gin
function M.test_go_gin()
  RESULTS = {}
  local base = FIXTURES_PATH .. "go-gin/"

  test_lsp_context({
    filepath = base .. "repository/user_repository.go",
    description = "Go: User Repository (cursor pagination)",
    expected_files = {"models/user", "models"},
  })

  test_lsp_context({
    filepath = base .. "handler/user_handler.go",
    description = "Go: User Handler (validation errors)",
    expected_files = {"service/user_service", "models"},
  })

  test_lsp_context({
    filepath = base .. "middleware/auth.go",
    description = "Go: Auth Middleware (token refresh)",
    expected_files = {"config", "models"},
  })

  M.print_summary()
end

-- Test: Rust Axum
function M.test_rust_axum()
  RESULTS = {}
  local base = FIXTURES_PATH .. "rust-axum/"

  test_lsp_context({
    filepath = base .. "src/services/user_service.rs",
    description = "Rust: User Service (partial updates)",
    expected_files = {"user_repository", "models/user", "email_service"},
  })

  test_lsp_context({
    filepath = base .. "src/handlers/user_handler.rs",
    description = "Rust: User Handler (error responses)",
    expected_files = {"user_service", "error"},
  })

  M.print_summary()
end

-- Test: Java Spring
function M.test_java_spring()
  RESULTS = {}
  local base = FIXTURES_PATH .. "java-spring/"

  test_lsp_context({
    filepath = base .. "src/main/java/com/myapp/service/UserService.java",
    description = "Java: User Service (optimistic locking)",
    expected_files = {"UserRepository", "User.java", "EmailService"},
  })

  test_lsp_context({
    filepath = base .. "src/main/java/com/myapp/controller/UserController.java",
    description = "Java: User Controller (validation errors)",
    expected_files = {"UserService", "UserResponse"},
  })

  M.print_summary()
end

-- Test: C++ Server
function M.test_cpp_server()
  RESULTS = {}
  local base = FIXTURES_PATH .. "cpp-server/"

  test_lsp_context({
    filepath = base .. "src/service/user_service.cpp",
    description = "C++: User Service (optimistic locking)",
    expected_files = {"user_service.hpp", "user_repository.hpp", "user.hpp"},
  })

  test_lsp_context({
    filepath = base .. "include/service/user_service.hpp",
    description = "C++: User Service header (password memory safety)",
    expected_files = {"user.hpp", "user_repository.hpp"},
  })

  test_lsp_context({
    filepath = base .. "include/middleware/auth_middleware.hpp",
    description = "C++: Auth Middleware (token refresh, rate limiting)",
    expected_files = {"user.hpp", "config.hpp"},
  })

  test_lsp_context({
    filepath = base .. "include/utils/validation.hpp",
    description = "C++: Validation Utils (password entropy)",
    expected_files = {},
  })

  M.print_summary()
end

-- Test: Vanilla Frontend (HTML/CSS/JS)
function M.test_vanilla_frontend()
  RESULTS = {}
  local base = FIXTURES_PATH .. "vanilla-frontend/"

  test_lsp_context({
    filepath = base .. "src/js/api/client.js",
    description = "JS: API Client (request interceptors)",
    expected_files = {"storage", "config"},
  })

  test_lsp_context({
    filepath = base .. "src/js/services/auth.js",
    description = "JS: Auth Service (cross-tab sync)",
    expected_files = {"client", "storage", "events"},
  })

  test_lsp_context({
    filepath = base .. "src/js/services/user.js",
    description = "JS: User Service (optimistic updates)",
    expected_files = {"client", "events"},
  })

  test_lsp_context({
    filepath = base .. "src/js/components/UserList.js",
    description = "JS: UserList Component (virtual scrolling)",
    expected_files = {"user", "auth", "events"},
  })

  M.print_summary()
end

-- Test: Vue.js App
function M.test_vue_app()
  RESULTS = {}
  local base = FIXTURES_PATH .. "vue-app/"

  test_lsp_context({
    filepath = base .. "src/composables/useAuth.ts",
    description = "Vue: useAuth (cross-tab sync)",
    expected_files = {"authService", "useStorage", "user.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/composables/useUsers.ts",
    description = "Vue: useUsers (optimistic updates)",
    expected_files = {"userService", "user.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/api/client.ts",
    description = "Vue: API Client (exponential backoff)",
    expected_files = {"user.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/composables/useValidation.ts",
    description = "Vue: useValidation (async validation)",
    expected_files = {},
  })

  M.print_summary()
end

-- Test: Svelte App
function M.test_svelte_app()
  RESULTS = {}
  local base = FIXTURES_PATH .. "svelte-app/"

  test_lsp_context({
    filepath = base .. "src/lib/stores/auth.ts",
    description = "Svelte: Auth Store (hydration mismatch)",
    expected_files = {"authService", "types.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/lib/stores/users.ts",
    description = "Svelte: Users Store (optimistic updates, rollback)",
    expected_files = {"userService", "types.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/lib/api/client.ts",
    description = "Svelte: API Client (request deduplication)",
    expected_files = {"types.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/lib/utils/validation.ts",
    description = "Svelte: Validation (async validation with actions)",
    expected_files = {},
  })

  M.print_summary()
end

-- Test: Angular App
function M.test_angular_app()
  RESULTS = {}
  local base = FIXTURES_PATH .. "angular-app/"

  test_lsp_context({
    filepath = base .. "src/app/services/auth.service.ts",
    description = "Angular: Auth Service (silent token refresh)",
    expected_files = {"user.model.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/app/services/user.service.ts",
    description = "Angular: User Service (RxJS state management)",
    expected_files = {"user.model.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/app/interceptors/auth.interceptor.ts",
    description = "Angular: Auth Interceptor (request queue)",
    expected_files = {"auth.service.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/app/guards/auth.guard.ts",
    description = "Angular: Auth Guard (role-based, lazy modules)",
    expected_files = {"auth.service.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/app/components/user-list/user-list.component.ts",
    description = "Angular: UserList (virtual scrolling CDK)",
    expected_files = {"user.service.ts", "auth.service.ts", "user.model.ts"},
  })

  test_lsp_context({
    filepath = base .. "src/app/components/login-form/login-form.component.ts",
    description = "Angular: LoginForm (async validators)",
    expected_files = {"auth.service.ts"},
  })

  M.print_summary()
end

-- Run all tests
function M.test_all()
  RESULTS = {}
  log("Running ALL LSP Context Tests", "HEADER")
  log("=" .. string.rep("=", 60), "HEADER")

  M.test_typescript_fullstack()
  M.test_python_django()
  M.test_go_gin()
  M.test_rust_axum()
  M.test_java_spring()
  M.test_cpp_server()
  M.test_vanilla_frontend()
  M.test_vue_app()
  M.test_svelte_app()
  M.test_angular_app()

  M.print_summary()
end

-- Print test summary
function M.print_summary()
  log("\n" .. string.rep("=", 60), "HEADER")
  log("TEST SUMMARY", "HEADER")

  local ok_count = 0
  local warn_count = 0
  local error_count = 0

  for _, r in ipairs(RESULTS) do
    if r.level == "OK" then ok_count = ok_count + 1
    elseif r.level == "WARN" then warn_count = warn_count + 1
    elseif r.level == "ERROR" then error_count = error_count + 1
    end
  end

  log(string.format("OK: %d | WARN: %d | ERROR: %d", ok_count, warn_count, error_count))

  if error_count > 0 then
    log("Some tests FAILED - check context gathering", "ERROR")
  elseif warn_count > 0 then
    log("Tests passed with warnings - LSP may not be fully configured", "WARN")
  else
    log("All tests PASSED!", "OK")
  end
end

-- Quick test current buffer
function M.test_current_buffer()
  RESULTS = {}
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  local prefix_map = {
    python = "#",
    lua = "--",
    sql = "--",
  }

  test_lsp_context({
    filepath = filepath,
    comment_prefix = prefix_map[filetype] or "//",
    description = "Current buffer: " .. vim.fn.fnamemodify(filepath, ":t"),
    expected_files = {},  -- No expectations, just show what's gathered
  })

  M.print_summary()
end

-- Show help
function M.help()
  print([[
LSP Context Manual Test Script
==============================

Commands:
  :lua require('tests.manual_lsp_test').test_all()              -- Run all tests
  :lua require('tests.manual_lsp_test').test_typescript_fullstack()
  :lua require('tests.manual_lsp_test').test_python_django()
  :lua require('tests.manual_lsp_test').test_go_gin()
  :lua require('tests.manual_lsp_test').test_rust_axum()
  :lua require('tests.manual_lsp_test').test_java_spring()
  :lua require('tests.manual_lsp_test').test_cpp_server()
  :lua require('tests.manual_lsp_test').test_vanilla_frontend()
  :lua require('tests.manual_lsp_test').test_vue_app()
  :lua require('tests.manual_lsp_test').test_svelte_app()
  :lua require('tests.manual_lsp_test').test_angular_app()
  :lua require('tests.manual_lsp_test').test_current_buffer()   -- Test current file
  :lua require('tests.manual_lsp_test').help()                  -- Show this help

Requirements:
  - LSP servers must be installed and configured
  - TypeScript: tsserver/typescript-language-server
  - Python: pyright or pylsp
  - Go: gopls
  - Rust: rust-analyzer
  - Java: jdtls
  - C++: clangd
  - JavaScript: tsserver (for JS files too) or eslint-lsp
  - Vue: volar or vue-language-server
  - Svelte: svelte-language-server
  - Angular: angular-language-server

The test will:
  1. Open fixture file with Q: comment
  2. Find the Q: line and position cursor
  3. Call lsp_context.gather() to collect definitions
  4. Verify expected files/symbols are in the gathered context
  5. Report OK/WARN/ERROR for each expectation
]])
end

return M
