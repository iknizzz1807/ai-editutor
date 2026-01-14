#!/bin/bash
# Simple test runner for ai-editutor
# Usage: ./tests/run_tests.sh [test_file]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

if [ -n "$1" ]; then
    # Run specific test file
    echo "Running test: $1"
    nvim --headless -u tests/minimal_init.lua \
        -c "PlenaryBustedFile $1"
else
    # Run all tests
    echo "Running all ai-editutor tests..."
    echo "=============================="
    nvim --headless -u tests/minimal_init.lua \
        -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"
fi

echo ""
echo "Tests completed!"
