# CLAUDE.md - ai-editutor Development Guide

## Project Overview

**ai-editutor** is a Neovim plugin that acts as a personal coding mentor - teaching developers through explanation rather than generating code automatically.

### Core Philosophy
> "Teach a person to fish, don't fish for them."

Unlike GitHub Copilot which writes code for you, ai-editutor **explains concepts** so you can write better code yourself.

### v1.0.0 - Simplified Q: Only Mode
Major simplification: **One prefix to rule them all**. Just use `Q:` and express your intent naturally.
- `// Q: What is closure?` → explains the concept
- `// Q: Review this code` → gives code review
- `// Q: Debug: why does this return nil?` → guides debugging
- `// Q: Explain recursion using Socratic method` → asks guiding questions

**New in v1.0:**
- Simplified to Q: only (removed S/R/D/E modes)
- **Skip answered questions** - Q: with A: below are automatically skipped
- **Visual selection support** - Select code block and ask about it

---

## Project Structure

```
ai-editutor/
├── lua/
│   └── editutor/
│       ├── init.lua              # Plugin entry point (v1.1.0)
│       ├── config.lua            # Configuration management
│       ├── parser.lua            # Comment parsing (Q: only)
│       ├── context.lua           # Context extraction (full/adaptive)
│       ├── lsp_context.lua       # LSP-based context (go-to-definition)
│       ├── import_graph.lua      # Import graph analysis (NEW)
│       ├── comment_writer.lua    # Insert responses as inline comments
│       ├── prompts.lua           # Unified pedagogical prompt (bilingual)
│       ├── provider.lua          # LLM API with inheritance + streaming
│       ├── hints.lua             # 5-level progressive hints system
│       ├── knowledge.lua         # Knowledge tracking (SQLite/JSON)
│       ├── conversation.lua      # Session-based conversation memory
│       ├── project_context.lua   # Project docs context
│       ├── project_scanner.lua   # Project file scanning
│       ├── cache.lua             # LRU cache with TTL + autocmd invalidation
│       ├── loading.lua           # Loading indicator
│       ├── debug_log.lua         # Debug logging
│       └── health.lua            # :checkhealth editutor
├── plugin/
│   └── editutor.lua              # Lazy loading entry
├── doc/
│   └── editutor.txt              # Vim help documentation
├── tests/
│   ├── simplified_spec.lua       # v1.0 simplified tests
│   ├── comprehensive_test.lua    # Full test suite
│   └── ...
├── README.md
└── CLAUDE.md                     # This file
```

---

## Architecture Overview

### Simplified Flow (v1.0)

```
User writes: // Q: What is closure?
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│ 1. Parse Q: comment                                     │
│ 2. Check if already answered (A: below) → skip if yes  │
│ 3. Extract context (LSP + BM25 + visual selection)     │
│ 4. Build unified pedagogical prompt                    │
│ 5. Send to LLM (Claude/OpenAI/Ollama/etc.)            │
│ 6. Insert response as comment below question           │
└─────────────────────────────────────────────────────────┘
                    │
                    ▼
Result in code:
    // Q: What is closure?
    /*
    A: A closure is a function that captures variables
    from its enclosing scope...
    */
```

### Skip Answered Questions (NEW in v1.0)

```javascript
function test() {
  // Q: What is closure?       ← SKIPPED (already has A: below)
  /*
  A: A closure is a function...
  */

  // Q: How does async work?   ← FOUND (unanswered)
  return 42;
}
```

The parser automatically detects A: responses (block comments, line comments) and skips questions that have already been answered.

### Visual Selection Support (NEW in v1.0)

```
1. Select code block with visual mode (v or V)
2. Write // Q: Explain this function within selection
3. Press <leader>ma
4. Selected code is sent with "FOCUS ON THIS" label
```

The selected code becomes the primary context, with surrounding code as secondary context.

### Context Extraction: Two-Mode Approach

ai-editutor uses **adaptive context extraction** based on project size:

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

**ADAPTIVE Mode Details:**
1. **Current file** - Always included with line numbers
2. **Import graph (depth=1)** - Files imported by current + files that import current
3. **LSP definitions** - Deduplicated (skips files already in import graph)
4. **Project tree** - Always included

If adaptive context > 20K tokens → Error, won't execute

### Comment Style Detection

The plugin automatically detects the appropriate comment style based on filetype:

| Languages | Line Comment | Block Comment |
|-----------|--------------|---------------|
| JS/TS/Go/Rust/C/C++/Java | `//` | `/* */` |
| Python/Ruby/Shell | `#` | `""" """` or `=begin =end` |
| Lua/SQL/Haskell | `--` | `--[[ ]]` or `{- -}` |
| HTML/XML | - | `<!-- -->` |

Block comments are preferred when available.

---

## Key Files

### init.lua - Plugin Entry Point
- Version: 1.0.0
- Creates user commands (`:EduTutorAsk`, `:EduTutorHint`, etc.)
- Sets up keymaps (normal mode + visual mode)
- Main functions: `ask()`, `ask_visual()`, `ask_with_hints()`
- Multi-language UI messages (English, Vietnamese)

### parser.lua - Comment Parsing (Simplified in v1.0)
- Only parses `Q:` or `q:` prefix (case insensitive)
- `parse_line()` - Returns question string (not mode+question tuple)
- `has_answer_below()` - Detects A: response below question
- `find_query()` - Finds unanswered question, skips answered ones
- `get_visual_selection()` - Get visual selection range and content
- `find_query_in_range()` - Find Q: within visual selection

### prompts.lua - Unified Pedagogical Prompt
- Single system prompt that adapts to user's intent:
  - "What is X?" → explain the concept
  - "Review this" → give constructive feedback
  - "Why doesn't this work?" → guide debugging
  - "How do I..." → explain the approach
  - "Socratic method" → ask guiding questions
- `build_user_prompt()` - Accepts optional `selected_code` parameter
- Bilingual support (English, Vietnamese)

### comment_writer.lua - Inline Comment Insertion
- `get_style()` - Detect comment style for filetype
- `format_response()` - Format response as block/line comments with A: prefix
- `insert_or_replace()` - Replace existing response if present
- Supports 40+ languages

### hints.lua - 5-Level Progressive Hints
- Level 1: Conceptual - What concepts are relevant?
- Level 2: Strategic - What approach to consider?
- Level 3: Directional - Where in the code to look?
- Level 4: Specific - What techniques to try?
- Level 5: Solution - Complete answer with explanation
- Mode parameter is ignored (backwards compatible)

### provider.lua - LLM API Client
- Declarative provider definitions with inheritance
- Built-in: Claude, OpenAI, DeepSeek, Groq, Together, OpenRouter, Ollama
- Streaming with debounced UI updates

### import_graph.lua - Import Analysis (NEW in v1.1)
- Parse import statements for 12+ languages (JS/TS, Python, Lua, Go, Rust, etc.)
- `get_outgoing_imports()` - Files imported by current file
- `get_incoming_imports()` - Files that import current file
- `resolve_import()` - Resolve import path to actual file
- Library detection (node_modules, stdlib, etc.)

### context.lua - Context Extraction
- `detect_mode()` - Choose FULL_PROJECT or ADAPTIVE based on token budget
- `build_full_project_context()` - All source files for small projects
- `build_adaptive_context()` - Import graph + LSP (deduped) for large projects
- Budget enforcement: returns error if > 20K tokens

---

## Key Commands

### Development
```bash
# Lint Lua
luacheck lua/

# Format Lua
stylua lua/

# Run tests
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.simplified_spec').run_all()" -c "qa"
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.comprehensive_test').run_all()" -c "qa"
```

### Plugin Usage (in Neovim)
```vim
" Core command (normal mode + visual mode)
<leader>ma           " Ask - response inserted as inline comment

" Main commands
:EduTutorAsk         " Ask (same as <leader>ma)
:EduTutorHint        " Progressive hints (run multiple times for more detail)

" Knowledge commands
:EduTutorHistory     " Show Q&A history
:EduTutorSearch      " Search knowledge base
:EduTutorExport      " Export to markdown
:EduTutorStats       " Show statistics

" Language commands
:EduTutorLang             " Show current language
:EduTutorLang Vietnamese  " Switch to Vietnamese
:EduTutorLang English     " Switch to English

" Conversation commands
:EduTutorConversation       " Show conversation info
:EduTutorClearConversation  " Clear conversation

" Indexer commands
:EduTutorIndex        " Index project
:EduTutorIndex!       " Force re-index
:EduTutorIndexStats   " Show index statistics
:EduTutorClearCache   " Clear context cache

" Health check
:checkhealth editutor
```

---

## Comment Syntax (Simplified)

Only `Q:` prefix is supported. Express your intent naturally in the question:

```javascript
// Q: What is the time complexity of this algorithm?
// Q: Review this function for security issues
// Q: Debug: why does this sometimes return nil?
// Q: Explain closures in JavaScript
// Q: Help me understand this using Socratic method
// Q: What could be improved in this code?

// Lowercase also works
// q: what is a closure?
```

Supported comment styles:
- `// Q:` - JavaScript, TypeScript, Go, Rust, C, C++, Java
- `# Q:` - Python, Ruby, Shell, YAML
- `-- Q:` - Lua, SQL, Haskell
- `/* Q:` - CSS, multi-line blocks
- `<!-- Q:` - HTML, XML

---

## Code Style Guidelines

### Lua
- Use `local` for all variables
- Prefer `vim.tbl_*` functions for table operations
- Use `vim.notify` for user messages
- Async operations via `plenary.job` and LSP async callbacks
- Follow LazyVim conventions

---

## Key Dependencies

### Required
```lua
dependencies = {
  "nvim-lua/plenary.nvim",      -- Async utilities, HTTP
}
```

### Recommended
```lua
dependencies = {
  "nvim-treesitter/nvim-treesitter",  -- AST parsing, better chunking
  "kkharji/sqlite.lua",               -- BM25 search, knowledge storage
}
```

---

## Provider System

### Built-in Providers
```lua
-- Available providers with inheritance
M.PROVIDERS = {
  claude     = { ... },           -- Claude API (Anthropic)
  openai     = { ... },           -- OpenAI API
  deepseek   = { __inherited_from = "openai", ... },  -- DeepSeek
  groq       = { __inherited_from = "openai", ... },  -- Groq
  together   = { __inherited_from = "openai", ... },  -- Together AI
  openrouter = { __inherited_from = "openai", ... },  -- OpenRouter
  ollama     = { ... },           -- Local Ollama
}
```

### Adding Custom Providers
```lua
require('editutor.provider').register_provider('my_provider', {
  __inherited_from = 'openai',
  name = 'my_provider',
  url = 'https://my-api.com/v1/chat/completions',
  model = 'my-model',
  api_key = function()
    return os.getenv('MY_API_KEY')
  end,
})
```

---

## Development Phases

### Phase 1-7: COMPLETE (v0.1 - v0.9)
See git history for details.

### Phase 8: Simplification - COMPLETE (v1.0.0)
- [x] Simplified to Q: only mode (removed S/R/D/E)
- [x] Unified system prompt that adapts to intent
- [x] Skip answered questions (Q: with A: below)
- [x] Visual selection support
- [x] Visual mode keymap

### Future Enhancements
- [ ] Obsidian integration
- [ ] Team sharing

---

## Testing Strategy

### Test Files
```bash
# v1.0 simplified tests (69 tests)
tests/simplified_spec.lua

# Comprehensive tests (34 tests)
tests/comprehensive_test.lua

# Integration tests (24 tests)
tests/integration_test.lua

# Call graph tests (19 tests)
tests/call_graph_spec.lua

# Adaptive budget tests (19 tests)
tests/adaptive_budget_spec.lua
```

### Running Tests
```bash
# Run all simplified tests
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.simplified_spec').run_all()" -c "qa"

# Run comprehensive tests
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.comprehensive_test').run_all()" -c "qa"
```

---

## Common Issues & Solutions

### Issue: Q: not detected
```lua
-- Make sure the format is correct:
// Q: your question here   -- Correct
// Q your question         -- Wrong (missing colon)
//Q: question              -- Correct (no space after //)
```

### Issue: Already answered question being re-asked
```lua
-- The parser should skip Q: with A: below
-- Check if the A: response format is correct:
/*
A: response here
*/
-- or
// A: response here
```

### Issue: Visual selection not working
```vim
" Make sure to:
1. Enter visual mode (v or V)
2. Select the code block
3. Include a // Q: comment in the selection
4. Press <leader>ma
```

### Issue: LLM API timeout
```lua
require('editutor').setup({
  provider = {
    timeout = 30000,  -- 30 seconds
  }
})
```

---

## Resources

- [Tree-sitter Neovim Guide](https://tree-sitter.github.io/tree-sitter/)
- [Neovim LSP Documentation](https://neovim.io/doc/user/lsp.html)
- [Claude API Docs](https://docs.anthropic.com/)
- [Pedagogical AI Research (CS50.ai)](https://cs50.ai/)
