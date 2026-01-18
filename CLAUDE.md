# CLAUDE.md - ai-editutor Development Guide

## Project Overview

**ai-editutor** - A Neovim plugin for developers who learn by building.

### Core Philosophy

> **Build projects. Ask questions. Level up.**

For developers building real projects who want to understand their code, not just ship it. Write questions naturally in comment blocks, get AI responses without breaking flow.

**Not** about coding faster. **About** learning while you build.

### v3.0.0 - Question Blocks

**Key Change:** Explicit question blocks with `[Q:id]` and `[PENDING:id]` markers.

```javascript
// User spawns question block with <leader>mq
/* [Q:q_1737200000000]
What is a closure and when should I use it?
[PENDING:q_1737200000000]
*/

// After <leader>ma, AI responds:
/* [Q:q_1737200000000]
What is a closure and when should I use it?

A closure is a function that captures variables from its surrounding scope.
When the inner function is returned, it maintains access to those variables
even after the outer function has finished executing.

Use closures for:
- Data privacy (private variables)
- Factory functions
- Callbacks and event handlers

Watch out for memory leaks if closures hold references to large objects.
*/
```

**Key Features:**
- **Spawn question block** - `<leader>mq` creates a block with unique ID
- **Visual selection support** - Select code, then `<leader>mq` to ask about it
- **Batch processing** - Multiple `[PENDING]` questions answered in one request
- **JSON response** - LLM returns structured responses, reliable parsing
- **No streaming** - Wait for complete response (simpler, more reliable)

---

## Project Structure

```
ai-editutor/
├── lua/
│   └── editutor/
│       ├── init.lua              # Plugin entry point (v3.0.0)
│       ├── config.lua            # Configuration management
│       ├── parser.lua            # Question block detection
│       ├── context.lua           # Context extraction (full/adaptive)
│       ├── lsp_context.lua       # LSP-based context
│       ├── import_graph.lua      # Import graph analysis
│       ├── comment_writer.lua    # Spawn blocks, write responses
│       ├── prompts.lua           # System prompt (JSON response format)
│       ├── provider.lua          # LLM API client
│       ├── knowledge.lua         # Knowledge tracking (date-based JSON)
│       ├── project_scanner.lua   # Project file scanning
│       ├── cache.lua             # LRU cache with TTL
│       ├── loading.lua           # Loading indicator
│       ├── debug_log.lua         # Debug logging
│       └── health.lua            # :checkhealth editutor
├── plugin/
│   └── editutor.lua              # Lazy loading entry
├── doc/
│   └── editutor.txt              # Vim help documentation
├── tests/
│   └── ...
├── README.md
└── CLAUDE.md                     # This file
```

---

## Architecture Overview

### v3.0 Flow

```
1. User presses <leader>mq
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Spawn question block with unique ID (timestamp-based)                   │
│ /* [Q:q_1737200000000]                                                 │
│                                                                         │
│ [PENDING:q_1737200000000]                                              │
│ */                                                                      │
│ Cursor placed in block, insert mode                                     │
└─────────────────────────────────────────────────────────────────────────┘
         │
         ▼
2. User types question, exits insert mode
         │
         ▼
3. User presses <leader>ma
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. Scan current file for [PENDING:*] markers                           │
│ 2. If none found → notify user, stop                                   │
│ 3. Extract context (full project < 20K OR adaptive)                    │
│ 4. Build user prompt with all pending questions                        │
│ 5. Send to LLM, expect JSON response                                   │
│ 6. Parse JSON: { "q_123": "answer1", "q_456": "answer2" }             │
│ 7. Replace each [PENDING:id] with corresponding answer                 │
│ 8. Save to knowledge base                                              │
└─────────────────────────────────────────────────────────────────────────┘
```

### Visual Selection Support

```
1. Select code block with visual mode (v or V)
2. Press <leader>mq
3. Question block spawned with selected code quoted:

/* [Q:q_1737200000000]
Regarding this code:
```
function foo() {
  return bar();
}
```

[PENDING:q_1737200000000]
*/
```

### Question ID Format

- Format: `q_<timestamp_ms>` (e.g., `q_1737200000000`)
- Generated using `vim.loop.hrtime() / 1000000`
- Unique per question, no conflicts across files
- Future-proof for potential cross-file features

### Context Extraction

```
                    Project Size Check
                         │
           ┌─────────────┴─────────────┐
           │                           │
    <= 20K tokens               > 20K tokens
           │                           │
           ▼                           ▼
    FULL_PROJECT                   ADAPTIVE
           │                           │
           ▼                           ▼
    All source files          ┌────────────────┐
    + Project tree            │ 1. Current file│
                              │ 2. Import graph│
                              │ 3. LSP defs    │
                              │ 4. Project tree│
                              └────────────────┘
```

### JSON Response Format

LLM responds with JSON mapping question IDs to answers:

```json
{
  "q_1737200000000": "A closure is a function that...",
  "q_1737200001000": "Async/await allows you to write..."
}
```

---

## Key Files

### init.lua - Plugin Entry Point
- Version: 3.0.0
- Main functions: `spawn_question()`, `spawn_question_visual()`, `ask()`
- Creates user commands and keymaps
- Parses JSON response from LLM

### parser.lua - Question Block Detection
- `generate_id()` - Generate unique timestamp-based ID
- `find_pending_questions()` - Scan buffer for `[PENDING:*]` blocks
- `find_question_by_id()` - Find specific question by ID
- `has_pending_questions()` - Check if any pending
- Supports both block and line comment styles

### comment_writer.lua - Block Spawning & Response Writing
- `spawn_question_block()` - Create new `[Q:id]...[PENDING:id]` block
- `replace_pending_with_response()` - Replace `[PENDING:id]` with answer
- `replace_pending_batch()` - Batch replace multiple questions
- Handles 40+ languages

### prompts.lua - System Prompt
- Instructs LLM to respond with JSON format
- Auto-detects question vs code request
- Bilingual support (English, Vietnamese)

### context.lua - Context Extraction
- `extract()` - Main entry, auto-selects mode
- `build_full_project_context()` - For small projects
- `build_adaptive_context()` - For large projects

---

## Key Commands

### Development
```bash
# Lint Lua
luacheck lua/

# Format Lua
stylua lua/

# Run tests
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.spec').run_all()" -c "qa"
```

### Plugin Usage (in Neovim)
```vim
" Core keymaps
<leader>mq           " Spawn new question block
<leader>ma           " Process all pending questions

" Commands
:EditutorQuestion    " Same as <leader>mq
:EditutorAsk         " Same as <leader>ma
:EditutorPending     " Show pending question count

" Knowledge commands
:EditutorHistory     " Show Q&A history
:EditutorBrowse      " Browse by date
:EditutorExport      " Export to markdown

" Language commands
:EditutorLang             " Show current language
:EditutorLang Vietnamese  " Switch to Vietnamese
:EditutorLang English     " Switch to English

" Other commands
:EditutorClearCache   " Clear context cache
:EditutorLog          " Open debug log

" Health check
:checkhealth editutor
```

---

## Usage Examples

### Basic Question

```javascript
// Press <leader>mq, type question:
/* [Q:q_1737200000000]
What is the time complexity of this algorithm?
[PENDING:q_1737200000000]
*/

// Press <leader>ma, AI responds:
/* [Q:q_1737200000000]
What is the time complexity of this algorithm?

The algorithm has O(n log n) time complexity because...
*/
```

### Multiple Questions

```javascript
/* [Q:q_1737200000000]
What is closure?
[PENDING:q_1737200000000]
*/

function example() {
  // ...code...
}

/* [Q:q_1737200001000]
How does async work?
[PENDING:q_1737200001000]
*/
```

Both answered in single request when `<leader>ma` is pressed.

### Visual Selection

```javascript
// Select this function, press <leader>mq:
function processData(items) {
  return items.filter(x => x.active).map(x => x.value);
}

// Question block created:
/* [Q:q_1737200000000]
Regarding this code:
```
function processData(items) {
  return items.filter(x => x.active).map(x => x.value);
}
```

[PENDING:q_1737200000000]
*/

// Type your question after the code block
```

---

## Configuration

```lua
require('editutor').setup({
  provider = "deepseek",  -- or "claude", "openai", "gemini", etc.
  model = "deepseek-chat",
  language = "Vietnamese",  -- or "English"
  keymaps = {
    question = "<leader>mq", -- Spawn question block
    ask = "<leader>ma",      -- Process pending questions
  },
  context = {
    token_budget = 20000,    -- Max tokens for context
  },
})
```

---

## Code Style Guidelines

### Lua
- Use `local` for all variables
- Prefer `vim.tbl_*` functions for table operations
- Use `vim.notify` for user messages
- Follow LazyVim conventions

---

## Version History

### v3.0.0 - Question Blocks (Current)
- New `[Q:id]` / `[PENDING:id]` block format
- Timestamp-based unique IDs
- Batch processing multiple questions
- JSON response format from LLM
- Removed streaming (simpler, more reliable)
- Removed float window (no longer needed)
- Visual selection support for code context

### v2.0.0 - Simplified
- Removed Q:/C: prefix requirement
- LLM auto-detects intent
- Float window for viewing/editing responses

### v1.x - Initial
- Basic Q&A with prefix markers
- Single question processing

---

## Common Issues & Solutions

### Issue: No pending questions found
```lua
-- Make sure you have [PENDING:id] markers in the file
-- Use <leader>mq to spawn a question block first
```

### Issue: JSON parse error
```lua
-- LLM may return malformed JSON
-- Check :EditutorLog for raw response
-- Try again or simplify your question
```

### Issue: LLM API timeout
```lua
require('editutor').setup({
  provider = {
    timeout = 60000,  -- 60 seconds
  }
})
```

---

## Resources

- [Tree-sitter Neovim Guide](https://tree-sitter.github.io/tree-sitter/)
- [Neovim LSP Documentation](https://neovim.io/doc/user/lsp.html)
- [Claude API Docs](https://docs.anthropic.com/)
