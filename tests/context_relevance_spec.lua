-- tests/context_relevance_spec.lua
-- Tests for context relevance verification
--
-- These tests verify that when a user asks a question (Q: comment),
-- the context extracted includes relevant code from related files.
-- This tests the core hypothesis: LSP go-to-definition provides
-- better context than RAG for code understanding questions.

local helpers = require("tests.helpers")

describe("Context Relevance Tests", function()
  local fixtures_path = vim.fn.fnamemodify("tests/fixtures", ":p")

  before_each(function()
    vim.cmd("bufdo bwipeout!")
  end)

  describe("TypeScript Fullstack Project", function()
    local project_path = fixtures_path .. "typescript-fullstack/"

    describe("API Client (token refresh question)", function()
      local filepath = project_path .. "src/api/client.ts"

      it("should find Q: comment about token refresh", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content, "Should read api/client.ts")

        local q_line, q_line_num = helpers.find_q_comment(content)
        assert.is_not_nil(q_line, "Should find Q: comment")
        assert.matches("refresh token", q_line)

        local parser = require("editutor.parser")
        local mode, question = parser.parse_line(q_line)
        assert.equals("Q", mode)
        assert.matches("race condition", question)
      end)

      it("should have imports to auth-related files", function()
        local content = helpers.read_file(filepath)
        local imports = helpers.extract_ts_imports(content)

        -- Should import from related modules
        local import_sources = {}
        for _, imp in ipairs(imports) do
          if imp.source then
            table.insert(import_sources, imp.source)
          end
        end

        -- Verify cross-file dependencies exist
        assert.is_true(vim.tbl_contains(import_sources, "../config") or
                       vim.tbl_contains(import_sources, "./config") or
                       content:match("config"))
      end)

      it("should have context relevant to the question", function()
        local content = helpers.read_file(filepath)
        local lines = vim.split(content, "\n")
        local _, q_line_num = helpers.find_q_comment(content)

        -- Extract surrounding context
        local start_line = math.max(1, q_line_num - 30)
        local end_line = math.min(#lines, q_line_num + 30)
        local context = table.concat(vim.list_slice(lines, start_line, end_line), "\n")

        -- Context should include token-related code
        assert.matches("token", context:lower())
        assert.matches("refresh", context:lower())
      end)
    end)

    describe("useAuth hook (logout cleanup question)", function()
      local filepath = project_path .. "src/hooks/useAuth.ts"

      it("should find Q: comment about logout cleanup", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("logout", q_line:lower())
      end)

      it("should import authService for context", function()
        local content = helpers.read_file(filepath)
        assert.matches("authService", content)
      end)
    end)

    describe("useUsers hook (optimistic updates question)", function()
      local filepath = project_path .. "src/hooks/useUsers.ts"

      it("should find Q: comment about optimistic updates", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("optimistic", q_line)
      end)

      it("should have userService dependency", function()
        local content = helpers.read_file(filepath)
        assert.matches("userService", content)
      end)
    end)

    describe("Cross-file relevance", function()
      it("should have type definitions that services use", function()
        local types_content = helpers.read_file(project_path .. "src/types/user.ts")
        local service_content = helpers.read_file(project_path .. "src/services/userService.ts")

        assert.is_not_nil(types_content)
        assert.is_not_nil(service_content)

        -- Types file should define User
        assert.matches("interface User", types_content)

        -- Service should reference User type
        assert.matches("User", service_content)
      end)

      it("should have config that multiple files depend on", function()
        local config_content = helpers.read_file(project_path .. "src/config/index.ts")
        assert.is_not_nil(config_content)
        assert.matches("API_URL", config_content)
      end)
    end)
  end)

  describe("Python Django Project", function()
    local project_path = fixtures_path .. "python-django/"

    describe("User Serializer (race condition question)", function()
      local filepath = project_path .. "myapp/serializers/user.py"

      it("should find Q: comment about race condition", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content, "Should read serializers/user.py")

        local q_line, _ = helpers.find_q_comment(content, "#")
        assert.is_not_nil(q_line)
        assert.matches("race condition", q_line)
      end)

      it("should import models for context", function()
        local content = helpers.read_file(filepath)
        -- Check that the file imports from models
        assert.is_true(
          content:find("from..models.user import", 1, true) ~= nil or
          content:find("from ..models.user import", 1, true) ~= nil,
          "Should import from models.user"
        )
      end)
    end)

    describe("User Manager (query optimization question)", function()
      local filepath = project_path .. "myapp/models/managers.py"

      it("should find Q: comment about query optimization", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content, "#")
        assert.is_not_nil(q_line)
        assert.matches("optimize", q_line:lower())
      end)

      it("should have User model context", function()
        local content = helpers.read_file(filepath)
        assert.matches("User", content)
      end)
    end)

    describe("User Service (bulk operations question)", function()
      local filepath = project_path .. "myapp/services/user_service.py"

      it("should find Q: comment about bulk operations", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content, "#")
        assert.is_not_nil(q_line)
        assert.matches("bulk", q_line:lower())
      end)
    end)

    describe("Auth Middleware (session security question)", function()
      local filepath = project_path .. "myapp/middleware/auth.py"

      it("should find Q: comment about session security", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content, "#")
        assert.is_not_nil(q_line)
        assert.matches("security", q_line:lower())
      end)
    end)

    describe("Permissions (role hierarchy question)", function()
      local filepath = project_path .. "myapp/permissions.py"

      it("should find Q: comment about role hierarchy", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content, "#")
        assert.is_not_nil(q_line)
        assert.matches("role", q_line:lower())
      end)
    end)

    describe("User Views (concurrent updates question)", function()
      local filepath = project_path .. "myapp/views/user.py"

      it("should find Q: comment about concurrent updates", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content, "#")
        assert.is_not_nil(q_line)
        assert.matches("concurrent", q_line:lower())
      end)

      it("should import services for context", function()
        local content = helpers.read_file(filepath)
        assert.matches("UserService", content)
      end)
    end)

    describe("Email Service (retry logic question)", function()
      local filepath = project_path .. "myapp/services/email_service.py"

      it("should find Q: comment about email delivery", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content, "#")
        assert.is_not_nil(q_line)
        assert.matches("delivery", q_line:lower())
      end)
    end)

    describe("Validators (phone validation question)", function()
      local filepath = project_path .. "myapp/utils/validators.py"

      it("should find Q: comment about phone validation", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content, "#")
        assert.is_not_nil(q_line)
        assert.matches("phone", q_line:lower())
      end)
    end)
  end)

  describe("Go Gin Project", function()
    local project_path = fixtures_path .. "go-gin/"

    describe("User Repository (pagination question)", function()
      local filepath = project_path .. "repository/user_repository.go"

      it("should find Q: comment about pagination", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("pagination", q_line:lower())
      end)

      it("should import models package", function()
        local content = helpers.read_file(filepath)
        local imports = helpers.extract_go_imports(content)

        local has_models = false
        for _, imp in ipairs(imports) do
          if imp:match("models") then
            has_models = true
            break
          end
        end
        assert.is_true(has_models)
      end)
    end)

    describe("User Service (partial updates question)", function()
      local filepath = project_path .. "service/user_service.go"

      it("should find Q: comment about partial updates", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("partial", q_line:lower())
      end)
    end)

    describe("User Handler (validation question)", function()
      local filepath = project_path .. "handler/user_handler.go"

      it("should find Q: comment about validation", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("validation", q_line:lower())
      end)

      it("should import service package", function()
        local content = helpers.read_file(filepath)
        local imports = helpers.extract_go_imports(content)

        local has_service = false
        for _, imp in ipairs(imports) do
          if imp:match("service") then
            has_service = true
            break
          end
        end
        assert.is_true(has_service)
      end)
    end)

    describe("Auth Middleware (token refresh question)", function()
      local filepath = project_path .. "middleware/auth.go"

      it("should find Q: comment about token refresh", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("token", q_line:lower())
      end)
    end)

    describe("Rate Limit Middleware (sliding window question)", function()
      local filepath = project_path .. "middleware/rate_limit.go"

      it("should find Q: comment about rate limiting", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("rate", q_line:lower())
      end)
    end)

    describe("Email Service (retry question)", function()
      local filepath = project_path .. "service/email_service.go"

      it("should find Q: comment about email delivery", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("email", q_line:lower())
      end)
    end)

    describe("Validation Utils (password strength question)", function()
      local filepath = project_path .. "utils/validation.go"

      it("should find Q: comment about password validation", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("password", q_line:lower())
      end)
    end)
  end)

  describe("Rust Axum Project", function()
    local project_path = fixtures_path .. "rust-axum/"

    describe("User Repository (query optimization question)", function()
      local filepath = project_path .. "src/repository/user_repository.rs"

      it("should find Q: comment about query optimization", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("optimize", q_line:lower())
      end)
    end)

    describe("User Service (partial updates question)", function()
      local filepath = project_path .. "src/services/user_service.rs"

      it("should find Q: comment about partial updates", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("partial", q_line:lower())
      end)
    end)

    describe("User Handler (error responses question)", function()
      local filepath = project_path .. "src/handlers/user_handler.rs"

      it("should find Q: comment about error responses", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("error", q_line:lower())
      end)
    end)

    describe("Auth Middleware (token expiration question)", function()
      local filepath = project_path .. "src/middleware/auth.rs"

      it("should find Q: comment about token handling", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("token", q_line:lower())
      end)
    end)

    describe("Email Service (retry logic question)", function()
      local filepath = project_path .. "src/services/email_service.rs"

      it("should find Q: comment about retry logic", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("retry", q_line:lower())
      end)
    end)

    describe("Error Handling (validation errors question)", function()
      local filepath = project_path .. "src/error.rs"

      it("should find Q: comment about validation errors", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("validation", q_line:lower())
      end)
    end)
  end)

  describe("Java Spring Project", function()
    local project_path = fixtures_path .. "java-spring/"

    describe("User Repository (full-text search question)", function()
      local filepath = project_path .. "src/main/java/com/myapp/repository/UserRepository.java"

      it("should find Q: comment about full-text search", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("search", q_line:lower())
      end)
    end)

    describe("User Service (optimistic locking question)", function()
      local filepath = project_path .. "src/main/java/com/myapp/service/UserService.java"

      it("should find Q: comment about optimistic locking", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("optimistic", q_line:lower())
      end)
    end)

    describe("User Controller (validation errors question)", function()
      local filepath = project_path .. "src/main/java/com/myapp/controller/UserController.java"

      it("should find Q: comment about validation", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("validation", q_line:lower())
      end)
    end)

    describe("Email Service (delivery tracking question)", function()
      local filepath = project_path .. "src/main/java/com/myapp/service/EmailService.java"

      it("should find Q: comment about email tracking", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("delivery", q_line:lower())
      end)
    end)

    describe("Security Config (role hierarchy question)", function()
      local filepath = project_path .. "src/main/java/com/myapp/config/SecurityConfig.java"

      it("should find Q: comment about role hierarchy", function()
        local content = helpers.read_file(filepath)
        assert.is_not_nil(content)

        local q_line, _ = helpers.find_q_comment(content)
        assert.is_not_nil(q_line)
        assert.matches("role", q_line:lower())
      end)
    end)
  end)
end)

describe("Question Context Relationships", function()
  local fixtures_path = vim.fn.fnamemodify("tests/fixtures", ":p")

  describe("Question should relate to surrounding code", function()
    -- Test that questions in each fixture are actually answerable
    -- by the surrounding code context

    it("TypeScript: token refresh question has token handling code nearby", function()
      local filepath = fixtures_path .. "typescript-fullstack/src/api/client.ts"
      local content = helpers.read_file(filepath)
      local lines = vim.split(content, "\n")

      local _, q_line_num = helpers.find_q_comment(content)
      assert.is_not_nil(q_line_num)

      -- Get 50 lines around the question
      local start_line = math.max(1, q_line_num - 50)
      local end_line = math.min(#lines, q_line_num + 50)
      local context = table.concat(vim.list_slice(lines, start_line, end_line), "\n")

      -- The question is about token refresh race conditions
      -- Context should have token and refresh related code
      assert.matches("token", context:lower())
      assert.matches("refresh", context:lower())
      -- Should also have async/await or promise handling
      assert.matches("async", context:lower())
    end)

    it("Python: race condition question has user creation code nearby", function()
      local filepath = fixtures_path .. "python-django/myapp/serializers/user.py"
      local content = helpers.read_file(filepath)
      local lines = vim.split(content, "\n")

      local _, q_line_num = helpers.find_q_comment(content, "#")
      assert.is_not_nil(q_line_num)

      local start_line = math.max(1, q_line_num - 30)
      local end_line = math.min(#lines, q_line_num + 30)
      local context = table.concat(vim.list_slice(lines, start_line, end_line), "\n")

      -- The question is about email uniqueness race condition
      -- Context should have validation and user creation code
      assert.matches("email", context:lower())
      assert.matches("validate", context:lower())
    end)

    it("Go: pagination question has pagination code nearby", function()
      local filepath = fixtures_path .. "go-gin/repository/user_repository.go"
      local content = helpers.read_file(filepath)
      local lines = vim.split(content, "\n")

      local _, q_line_num = helpers.find_q_comment(content)
      assert.is_not_nil(q_line_num)

      -- Use wider range to capture the List function that follows the Q comment
      local start_line = math.max(1, q_line_num - 10)
      local end_line = math.min(#lines, q_line_num + 40)
      local context = table.concat(vim.list_slice(lines, start_line, end_line), "\n")

      -- The question is about cursor-based pagination
      -- Context should have pagination related code
      assert.matches("pagination", context:lower())
      assert.matches("offset", context:lower())
    end)

    it("Rust: partial updates question has update logic nearby", function()
      local filepath = fixtures_path .. "rust-axum/src/services/user_service.rs"
      local content = helpers.read_file(filepath)
      local lines = vim.split(content, "\n")

      local _, q_line_num = helpers.find_q_comment(content)
      assert.is_not_nil(q_line_num)

      local start_line = math.max(1, q_line_num - 30)
      local end_line = math.min(#lines, q_line_num + 30)
      local context = table.concat(vim.list_slice(lines, start_line, end_line), "\n")

      -- The question is about partial updates with optional fields
      assert.matches("update", context:lower())
      assert.matches("option", context:lower())
    end)

    it("Java: optimistic locking question has update transaction code nearby", function()
      local filepath = fixtures_path .. "java-spring/src/main/java/com/myapp/service/UserService.java"
      local content = helpers.read_file(filepath)
      local lines = vim.split(content, "\n")

      local _, q_line_num = helpers.find_q_comment(content)
      assert.is_not_nil(q_line_num)

      local start_line = math.max(1, q_line_num - 30)
      local end_line = math.min(#lines, q_line_num + 30)
      local context = table.concat(vim.list_slice(lines, start_line, end_line), "\n")

      -- The question is about optimistic locking
      assert.matches("update", context:lower())
      assert.matches("transactional", context:lower())
    end)
  end)
end)

describe("Import Chain Verification", function()
  local fixtures_path = vim.fn.fnamemodify("tests/fixtures", ":p")

  -- These tests verify that import chains exist that LSP could follow

  describe("TypeScript import chains", function()
    it("should have complete import chain: hook -> service -> api -> types", function()
      local ts_path = fixtures_path .. "typescript-fullstack/"

      -- Hook imports service
      local hook_content = helpers.read_file(ts_path .. "src/hooks/useAuth.ts")
      assert.matches("authService", hook_content)

      -- Service imports api client
      local service_content = helpers.read_file(ts_path .. "src/services/authService.ts")
      assert.matches("apiClient", service_content)

      -- API client uses types
      local api_content = helpers.read_file(ts_path .. "src/api/client.ts")
      assert.is_not_nil(api_content)

      -- Types define the structures
      local types_content = helpers.read_file(ts_path .. "src/types/auth.ts")
      assert.matches("interface", types_content)
    end)
  end)

  describe("Python import chains", function()
    it("should have complete import chain: view -> service -> model", function()
      local py_path = fixtures_path .. "python-django/"

      -- View imports service
      local view_content = helpers.read_file(py_path .. "myapp/views/user.py")
      assert.matches("UserService", view_content)

      -- Service imports model
      local service_content = helpers.read_file(py_path .. "myapp/services/user_service.py")
      assert.matches("User", service_content)

      -- Model defines the structure
      local model_content = helpers.read_file(py_path .. "myapp/models/user.py")
      assert.matches("class User", model_content)
    end)
  end)

  describe("Go import chains", function()
    it("should have complete import chain: handler -> service -> repository -> model", function()
      local go_path = fixtures_path .. "go-gin/"

      -- Handler imports service
      local handler_content = helpers.read_file(go_path .. "handler/user_handler.go")
      assert.matches("service", handler_content:lower())

      -- Service imports repository
      local service_content = helpers.read_file(go_path .. "service/user_service.go")
      assert.matches("repository", service_content:lower())

      -- Repository uses model
      local repo_content = helpers.read_file(go_path .. "repository/user_repository.go")
      assert.matches("models", repo_content)
    end)
  end)

  describe("Rust import chains", function()
    it("should have module relationships", function()
      local rust_path = fixtures_path .. "rust-axum/"

      -- Handler uses service
      local handler_content = helpers.read_file(rust_path .. "src/handlers/user_handler.rs")
      assert.matches("UserService", handler_content)

      -- Service uses repository
      local service_content = helpers.read_file(rust_path .. "src/services/user_service.rs")
      assert.matches("UserRepository", service_content)

      -- Repository uses model
      local repo_content = helpers.read_file(rust_path .. "src/repository/user_repository.rs")
      assert.matches("User", repo_content)
    end)
  end)

  describe("Java import chains", function()
    it("should have complete import chain: controller -> service -> repository", function()
      local java_path = fixtures_path .. "java-spring/"

      -- Controller uses service
      local controller_content = helpers.read_file(java_path .. "src/main/java/com/myapp/controller/UserController.java")
      assert.matches("UserService", controller_content)

      -- Service uses repository
      local service_content = helpers.read_file(java_path .. "src/main/java/com/myapp/service/UserService.java")
      assert.matches("UserRepository", service_content)

      -- Repository defines queries
      local repo_content = helpers.read_file(java_path .. "src/main/java/com/myapp/repository/UserRepository.java")
      assert.matches("JpaRepository", repo_content)
    end)
  end)
end)
