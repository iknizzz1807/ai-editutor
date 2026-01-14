-- tests/lsp_context_spec.lua
-- Unit tests for LSP context extraction

local lsp_context = require("editutor.lsp_context")

describe("lsp_context", function()
  describe("is_project_file", function()
    it("should return false for node_modules", function()
      assert.is_false(lsp_context.is_project_file("/project/node_modules/lodash/index.js"))
    end)

    it("should return false for .venv", function()
      assert.is_false(lsp_context.is_project_file("/project/.venv/lib/python3.9/site-packages/requests/__init__.py"))
    end)

    it("should return false for venv", function()
      assert.is_false(lsp_context.is_project_file("/project/venv/lib/python3.9/site-packages/flask/app.py"))
    end)

    it("should return false for site-packages", function()
      assert.is_false(lsp_context.is_project_file("/usr/lib/python3.9/site-packages/numpy/core/numeric.py"))
    end)

    it("should return false for vendor directory", function()
      assert.is_false(lsp_context.is_project_file("/project/vendor/github.com/gorilla/mux/mux.go"))
    end)

    it("should return false for cargo registry", function()
      assert.is_false(lsp_context.is_project_file("/home/user/.cargo/registry/cache/github.com-1ecc6299/serde-1.0.0/src/lib.rs"))
    end)

    it("should return false for /usr/ paths", function()
      assert.is_false(lsp_context.is_project_file("/usr/include/stdio.h"))
      assert.is_false(lsp_context.is_project_file("/usr/local/lib/node_modules/typescript/lib/typescript.js"))
    end)

    it("should return false for /opt/ paths", function()
      assert.is_false(lsp_context.is_project_file("/opt/homebrew/lib/python3.9/site-packages/pip/__init__.py"))
    end)

    it("should return false for .local/lib paths", function()
      assert.is_false(lsp_context.is_project_file("/home/user/.local/lib/python3.9/site-packages/click/__init__.py"))
    end)

    it("should return false for luarocks", function()
      assert.is_false(lsp_context.is_project_file("/home/user/.luarocks/share/lua/5.1/lfs.lua"))
    end)

    it("should return false for target/debug (Rust)", function()
      assert.is_false(lsp_context.is_project_file("/project/target/debug/deps/serde-abc123.rlib"))
    end)

    it("should return false for target/release (Rust)", function()
      assert.is_false(lsp_context.is_project_file("/project/target/release/myapp"))
    end)

    it("should return false for empty path", function()
      assert.is_false(lsp_context.is_project_file(""))
    end)

    it("should return false for nil path", function()
      assert.is_false(lsp_context.is_project_file(nil))
    end)

    -- Note: Positive tests depend on project root detection
    -- which requires git or cwd context
  end)

  describe("get_project_root", function()
    it("should return a non-empty string", function()
      local root = lsp_context.get_project_root()
      assert.is_not_nil(root)
      assert.is_true(#root > 0)
    end)

    it("should return a valid directory", function()
      local root = lsp_context.get_project_root()
      assert.equals(1, vim.fn.isdirectory(root))
    end)
  end)

  describe("_is_builtin", function()
    -- Common builtins
    it("should identify common keywords", function()
      assert.is_true(lsp_context._is_builtin("true", "lua"))
      assert.is_true(lsp_context._is_builtin("false", "python"))
      assert.is_true(lsp_context._is_builtin("nil", "lua"))
      assert.is_true(lsp_context._is_builtin("null", "javascript"))
      assert.is_true(lsp_context._is_builtin("self", "python"))
      assert.is_true(lsp_context._is_builtin("this", "javascript"))
    end)

    it("should identify control flow keywords", function()
      assert.is_true(lsp_context._is_builtin("if", "lua"))
      assert.is_true(lsp_context._is_builtin("for", "python"))
      assert.is_true(lsp_context._is_builtin("while", "javascript"))
      assert.is_true(lsp_context._is_builtin("return", "go"))
    end)

    -- Lua builtins
    it("should identify Lua builtins", function()
      assert.is_true(lsp_context._is_builtin("vim", "lua"))
      assert.is_true(lsp_context._is_builtin("print", "lua"))
      assert.is_true(lsp_context._is_builtin("pairs", "lua"))
      assert.is_true(lsp_context._is_builtin("ipairs", "lua"))
      assert.is_true(lsp_context._is_builtin("require", "lua"))
      assert.is_true(lsp_context._is_builtin("pcall", "lua"))
    end)

    -- Python builtins
    it("should identify Python builtins", function()
      assert.is_true(lsp_context._is_builtin("print", "python"))
      assert.is_true(lsp_context._is_builtin("len", "python"))
      assert.is_true(lsp_context._is_builtin("range", "python"))
      assert.is_true(lsp_context._is_builtin("isinstance", "python"))
      assert.is_true(lsp_context._is_builtin("Exception", "python"))
    end)

    -- JavaScript builtins
    it("should identify JavaScript builtins", function()
      assert.is_true(lsp_context._is_builtin("console", "javascript"))
      assert.is_true(lsp_context._is_builtin("window", "javascript"))
      assert.is_true(lsp_context._is_builtin("document", "javascript"))
      assert.is_true(lsp_context._is_builtin("JSON", "javascript"))
      assert.is_true(lsp_context._is_builtin("Promise", "javascript"))
      assert.is_true(lsp_context._is_builtin("fetch", "typescript"))
    end)

    -- Non-builtins
    it("should return false for user identifiers", function()
      assert.is_false(lsp_context._is_builtin("myFunction", "lua"))
      assert.is_false(lsp_context._is_builtin("config", "python"))
      assert.is_false(lsp_context._is_builtin("UserService", "javascript"))
      assert.is_false(lsp_context._is_builtin("handle_request", "go"))
    end)
  end)

  describe("get_lines_around", function()
    -- Create a temp file for testing
    local temp_file

    before_each(function()
      temp_file = os.tmpname()
      local f = io.open(temp_file, "w")
      if f then
        for i = 1, 100 do
          f:write(string.format("Line %d content\n", i))
        end
        f:close()
      end
    end)

    after_each(function()
      if temp_file then
        os.remove(temp_file)
      end
    end)

    it("should return content around a line", function()
      local content, start_line, end_line = lsp_context.get_lines_around(temp_file, 50, 5)

      assert.is_not_nil(content)
      assert.is_not_nil(start_line)
      assert.is_not_nil(end_line)
      assert.equals(45, start_line)
      assert.equals(55, end_line)
      assert.is_true(content:find("Line 50") ~= nil)
    end)

    it("should handle start of file", function()
      local content, start_line, end_line = lsp_context.get_lines_around(temp_file, 2, 5)

      assert.is_not_nil(content)
      assert.equals(0, start_line)
      assert.is_true(content:find("Line 1") ~= nil)
    end)

    it("should handle end of file", function()
      local content, start_line, end_line = lsp_context.get_lines_around(temp_file, 98, 5)

      assert.is_not_nil(content)
      assert.equals(99, end_line)
      assert.is_true(content:find("Line 100") ~= nil)
    end)

    it("should return nil for non-existent file", function()
      local content = lsp_context.get_lines_around("/non/existent/file.txt", 10, 5)
      assert.is_nil(content)
    end)
  end)

  describe("is_available", function()
    it("should return a boolean", function()
      local result = lsp_context.is_available()
      assert.is_boolean(result)
    end)
  end)

  describe("clear_cache", function()
    it("should clear the cache", function()
      -- Populate cache
      lsp_context._cache = { test = "data" }
      lsp_context._cache_bufnr = 1

      -- Clear it
      lsp_context.clear_cache()

      assert.same({}, lsp_context._cache)
      assert.is_nil(lsp_context._cache_bufnr)
    end)
  end)
end)
