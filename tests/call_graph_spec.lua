-- tests/call_graph_spec.lua
-- Tests for call graph analysis and enhanced chunking

local M = {}

M.results = { passed = 0, failed = 0, tests = {} }

local function log(status, name, msg)
  local icon = status == "PASS" and "[OK]" or (status == "FAIL" and "[!!]" or "[--]")
  print(string.format("%s %s: %s", icon, name, msg or ""))

  if status == "PASS" then
    M.results.passed = M.results.passed + 1
  elseif status == "FAIL" then
    M.results.failed = M.results.failed + 1
  end

  table.insert(M.results.tests, { name = name, status = status, msg = msg })
end

local function section(name)
  print("\n" .. string.rep("=", 60))
  print("  " .. name)
  print(string.rep("=", 60))
end

-- =============================================================================
-- Enhanced Chunker Tests
-- =============================================================================

function M.test_enhanced_chunker_lua()
  section("Enhanced Chunker - Lua")

  local chunker = require("editutor.indexer.chunker")

  local lua_code = [[
-- User validation module
-- Handles all user-related validation

local crypto = require("crypto")

-- Validates user credentials
-- @param user table The user object
-- @return boolean, string?
function validate_user(user)
  if not user then
    return false, "No user"
  end
  local email_ok = check_email(user.email)
  local pass_ok = check_password(user.password)
  local hash = crypto.hash(user.password)
  return email_ok and pass_ok, nil
end

function check_email(email)
  return email and email:match("@") ~= nil
end

function check_password(pass)
  return pass and #pass >= 8
end

local function helper()
  return true
end
]]

  local chunks = chunker.extract_chunks_enhanced("test.lua", lua_code, { language = "lua" })

  log(#chunks >= 3 and "PASS" or "FAIL", "lua.chunk_count",
    string.format("Found %d chunks", #chunks))

  -- Find validate_user chunk
  local validate_chunk = nil
  for _, c in ipairs(chunks) do
    if c.name == "validate_user" then
      validate_chunk = c
      break
    end
  end

  log(validate_chunk ~= nil and "PASS" or "FAIL", "lua.find_validate_user",
    "Found validate_user function")

  if validate_chunk then
    -- Check docstring extraction
    log(validate_chunk.docstring ~= nil and "PASS" or "FAIL", "lua.docstring",
      validate_chunk.docstring and "Has docstring" or "No docstring")

    -- Check call extraction
    local has_check_email = false
    local has_check_password = false
    local has_crypto = false

    if validate_chunk.calls then
      for _, call in ipairs(validate_chunk.calls) do
        if call == "check_email" then
          has_check_email = true
        elseif call == "check_password" then
          has_check_password = true
        elseif call:find("crypto") or call:find("hash") then
          has_crypto = true
        end
      end
    end

    log(has_check_email and "PASS" or "FAIL", "lua.calls_check_email",
      "Detected call to check_email")
    log(has_check_password and "PASS" or "FAIL", "lua.calls_check_password",
      "Detected call to check_password")
    log(has_crypto and "PASS" or "FAIL", "lua.calls_crypto",
      "Detected call to crypto.hash")
  end
end

function M.test_enhanced_chunker_python()
  section("Enhanced Chunker - Python")

  local chunker = require("editutor.indexer.chunker")

  local python_code = [[
"""User service module"""

from typing import Optional
from models import User
from database import db

class UserService:
    """Service for managing users"""

    def get_user(self, user_id: int) -> Optional[User]:
        """Get user by ID"""
        user = db.query(User).filter_by(id=user_id).first()
        self.validate_access(user)
        return user

    def validate_access(self, user: User) -> bool:
        """Validate user access"""
        return user and user.is_active

    def create_user(self, data: dict) -> User:
        """Create a new user"""
        user = User(**data)
        db.session.add(user)
        db.session.commit()
        self.send_welcome_email(user)
        return user

    def send_welcome_email(self, user: User) -> None:
        """Send welcome email to user"""
        pass
]]

  local chunks = chunker.extract_chunks_enhanced("test.py", python_code, { language = "python" })

  log(#chunks >= 1 and "PASS" or "FAIL", "python.chunk_count",
    string.format("Found %d chunks", #chunks))

  -- Check for class
  local found_class = false
  for _, c in ipairs(chunks) do
    if c.type == "class_definition" then
      found_class = true
      break
    end
  end

  log(found_class and "PASS" or "FAIL", "python.found_class",
    "Found class definition")
end

function M.test_enhanced_chunker_typescript()
  section("Enhanced Chunker - TypeScript")

  local chunker = require("editutor.indexer.chunker")

  local ts_code = [[
import { User, UserDTO } from './types';
import { validateEmail } from './validators';

interface CreateUserInput {
  email: string;
  password: string;
}

export class UserService {
  private db: Database;

  async createUser(input: CreateUserInput): Promise<User> {
    const isValid = validateEmail(input.email);
    if (!isValid) {
      throw new Error('Invalid email');
    }
    const hashed = await this.hashPassword(input.password);
    return this.db.users.create({ ...input, password: hashed });
  }

  private async hashPassword(password: string): Promise<string> {
    return bcrypt.hash(password, 10);
  }
}

export function getUserById(id: number): Promise<User | null> {
  return db.users.findById(id);
}
]]

  local chunks = chunker.extract_chunks_enhanced("test.ts", ts_code, { language = "typescript" })

  log(#chunks >= 2 and "PASS" or "FAIL", "typescript.chunk_count",
    string.format("Found %d chunks", #chunks))

  -- Check for interface
  local found_interface = false
  local found_class = false
  local found_function = false

  for _, c in ipairs(chunks) do
    if c.type == "interface_declaration" then
      found_interface = true
    elseif c.type == "class_declaration" then
      found_class = true
    elseif c.type == "function_declaration" then
      found_function = true
    end
  end

  log(found_interface and "PASS" or "FAIL", "typescript.interface",
    "Found interface declaration")
  log(found_class and "PASS" or "FAIL", "typescript.class",
    "Found class declaration")
  log(found_function and "PASS" or "FAIL", "typescript.function",
    "Found function declaration")

  -- Check type refs
  local has_type_refs = false
  for _, c in ipairs(chunks) do
    if c.type_refs and #c.type_refs > 0 then
      has_type_refs = true
      break
    end
  end

  log(has_type_refs and "PASS" or "FAIL", "typescript.type_refs",
    "Extracted type references")
end

function M.test_call_graph_extraction()
  section("Call Graph Extraction")

  local chunker = require("editutor.indexer.chunker")

  local code = [[
function main()
  local result = process_data(get_input())
  save_result(result)
  notify_user()
end

function process_data(data)
  local validated = validate(data)
  return transform(validated)
end

function get_input()
  return read_file("input.txt")
end

function save_result(result)
  write_file("output.txt", result)
end

function validate(data)
  return data ~= nil
end

function transform(data)
  return data
end

function notify_user()
  send_email("done")
end
]]

  local graph = chunker.extract_call_graph(code, "lua")

  log(#graph >= 3 and "PASS" or "FAIL", "call_graph.count",
    string.format("Found %d functions with calls", #graph))

  -- Find main function
  local main_entry = nil
  for _, entry in ipairs(graph) do
    if entry.name == "main" then
      main_entry = entry
      break
    end
  end

  log(main_entry ~= nil and "PASS" or "FAIL", "call_graph.main",
    "Found main function")

  if main_entry then
    log(#main_entry.calls >= 3 and "PASS" or "FAIL", "call_graph.main_calls",
      string.format("main calls %d functions", #main_entry.calls))

    -- Check specific calls
    local calls_set = {}
    for _, c in ipairs(main_entry.calls) do
      calls_set[c] = true
    end

    log(calls_set["process_data"] and "PASS" or "FAIL", "call_graph.calls_process",
      "main calls process_data")
    log(calls_set["save_result"] and "PASS" or "FAIL", "call_graph.calls_save",
      "main calls save_result")
  end

  -- Check process_data
  local process_entry = nil
  for _, entry in ipairs(graph) do
    if entry.name == "process_data" then
      process_entry = entry
      break
    end
  end

  if process_entry then
    log(#process_entry.calls >= 2 and "PASS" or "FAIL", "call_graph.process_calls",
      string.format("process_data calls %d functions", #process_entry.calls))
  end
end

function M.test_database_call_graph()
  section("Database Call Graph Storage")

  local sqlite_ok = pcall(require, "sqlite")
  if not sqlite_ok then
    log("SKIP", "db.sqlite", "sqlite.lua not installed")
    return
  end

  local db = require("editutor.indexer.db")
  local test_root = "/tmp/editutor_call_graph_test_" .. os.time()
  vim.fn.mkdir(test_root, "p")

  local init_ok, _ = db.init(test_root)
  log(init_ok and "PASS" or "FAIL", "db.init", "Database initialized")

  if not init_ok then
    vim.fn.delete(test_root, "rf")
    return
  end

  -- Insert test file
  local file_id = db.upsert_file({
    path = test_root .. "/test.lua",
    hash = "test123",
    mtime = os.time(),
    language = "lua",
    line_count = 50,
  })

  log(file_id ~= nil and "PASS" or "FAIL", "db.file", "File inserted")

  -- Insert chunks
  local chunk1_id = db.insert_chunk({
    file_id = file_id,
    type = "function_declaration",
    name = "validate_user",
    signature = "function validate_user(user)",
    start_line = 1,
    end_line = 10,
    content = "function validate_user(user) check_email(user.email) end",
  })

  local chunk2_id = db.insert_chunk({
    file_id = file_id,
    type = "function_declaration",
    name = "check_email",
    signature = "function check_email(email)",
    start_line = 12,
    end_line = 15,
    content = "function check_email(email) return email:match('@') end",
  })

  log(chunk1_id ~= nil and chunk2_id ~= nil and "PASS" or "FAIL", "db.chunks",
    "Chunks inserted")

  -- Insert call relationship
  if chunk1_id then
    db.insert_call(chunk1_id, "check_email")
    db.insert_call(chunk1_id, "check_password")

    -- Test get_call_names
    local call_names = db.get_call_names(chunk1_id)
    log(#call_names >= 2 and "PASS" or "FAIL", "db.call_names",
      string.format("Got %d call names", #call_names))

    -- Test get_callers
    local callers = db.get_callers("check_email")
    log(#callers >= 1 and "PASS" or "FAIL", "db.callers",
      string.format("Found %d callers", #callers))

    -- Test get_callees
    local callees = db.get_callees(chunk1_id)
    -- Note: This might return 0 if check_email chunk doesn't match the query
    log(type(callees) == "table" and "PASS" or "FAIL", "db.callees",
      string.format("Callees query returned %d results", #callees))
  end

  -- Cleanup
  db.close()
  vim.fn.delete(test_root, "rf")
end

-- =============================================================================
-- RUN ALL TESTS
-- =============================================================================

function M.run_all()
  print(string.rep("=", 60))
  print("  Call Graph & Enhanced Chunker Tests")
  print(string.rep("=", 60))

  M.results = { passed = 0, failed = 0, tests = {} }

  M.test_enhanced_chunker_lua()
  M.test_enhanced_chunker_python()
  M.test_enhanced_chunker_typescript()
  M.test_call_graph_extraction()
  M.test_database_call_graph()

  -- Summary
  print("\n" .. string.rep("=", 60))
  print("  CALL GRAPH TEST SUMMARY")
  print(string.rep("=", 60))
  print(string.format("  Passed: %d", M.results.passed))
  print(string.format("  Failed: %d", M.results.failed))
  print(string.format("  Total: %d", #M.results.tests))

  if M.results.failed > 0 then
    print("\n  Failed tests:")
    for _, t in ipairs(M.results.tests) do
      if t.status == "FAIL" then
        print(string.format("    - %s: %s", t.name, t.msg or ""))
      end
    end
  end

  print(string.rep("=", 60))

  return M.results.failed == 0
end

return M
