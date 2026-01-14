.PHONY: test test-file lint format help

# Run all tests
test:
	@echo "Running EduTutor tests..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"

# Run a specific test file
# Usage: make test-file FILE=tests/parser_spec.lua
test-file:
	@echo "Running $(FILE)..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)"

# Run tests with verbose output
test-verbose:
	@echo "Running EduTutor tests (verbose)..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/', {minimal_init = 'tests/minimal_init.lua', sequential = true})"

# Lint Lua files
lint:
	@echo "Linting Lua files..."
	@luacheck lua/ tests/ --no-unused-args --no-max-line-length || true

# Format Lua files
format:
	@echo "Formatting Lua files..."
	@stylua lua/ tests/ || echo "stylua not installed"

# Check health
health:
	@nvim --headless -c "checkhealth editutor" -c "qa!"

# Help
help:
	@echo "EduTutor Development Commands"
	@echo "=============================="
	@echo ""
	@echo "Testing:"
	@echo "  make test          - Run all tests"
	@echo "  make test-file FILE=tests/parser_spec.lua - Run specific test"
	@echo "  make test-verbose  - Run tests with verbose output"
	@echo ""
	@echo "Code Quality:"
	@echo "  make lint          - Lint Lua files with luacheck"
	@echo "  make format        - Format Lua files with stylua"
	@echo ""
	@echo "Other:"
	@echo "  make health        - Run health check"
	@echo "  make help          - Show this help"
