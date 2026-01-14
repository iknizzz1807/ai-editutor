# EduTutor Tests

Unit tests for the AI EduTutor Neovim plugin.

## Requirements

- Neovim 0.9.0+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) installed

## Running Tests

### Using Make (recommended)

```bash
# Run all tests
make test

# Run a specific test file
make test-file FILE=tests/parser_spec.lua

# Run tests with verbose output
make test-verbose
```

### Using the shell script

```bash
# Run all tests
./tests/run_tests.sh

# Run a specific test file
./tests/run_tests.sh tests/parser_spec.lua
```

### Using nvim directly

```bash
nvim --headless -u tests/minimal_init.lua \
    -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

## Test Files

| File | Description |
|------|-------------|
| `parser_spec.lua` | Tests for comment parsing (// Q:, // S:, etc.) |
| `config_spec.lua` | Tests for configuration and provider setup |
| `lsp_context_spec.lua` | Tests for LSP-based context extraction |
| `context_spec.lua` | Tests for context formatting |
| `prompts_spec.lua` | Tests for prompt generation |
| `knowledge_spec.lua` | Tests for knowledge tracking |

## Notes

- **No API key required** - All unit tests use mocked responses
- Tests create temporary buffers and files which are cleaned up automatically
- Integration tests with real LLM calls are optional (see below)

## Integration Tests

To run integration tests that actually call an LLM:

```bash
# Set API key
export ANTHROPIC_API_KEY=your-key-here

# Run integration tests (if available)
nvim --headless -u tests/minimal_init.lua \
    -c "PlenaryBustedFile tests/integration_spec.lua"
```

## Writing New Tests

Tests use [plenary.nvim's test harness](https://github.com/nvim-lua/plenary.nvim#plenarytest_harness) which is based on [busted](https://olivinelabs.com/busted/).

Example test structure:

```lua
describe("module_name", function()
  before_each(function()
    -- Setup before each test
  end)

  after_each(function()
    -- Cleanup after each test
  end)

  describe("function_name", function()
    it("should do something", function()
      local result = my_function()
      assert.equals("expected", result)
    end)
  end)
end)
```

### Assertions

Common assertions:

```lua
assert.equals(expected, actual)
assert.is_true(value)
assert.is_false(value)
assert.is_nil(value)
assert.is_not_nil(value)
assert.is_string(value)
assert.is_table(value)
assert.is_number(value)
assert.same(expected_table, actual_table)  -- Deep comparison
assert.has_no.errors(function() ... end)
```
