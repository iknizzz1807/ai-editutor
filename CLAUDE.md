# CLAUDE.md - ai-editutor Development Guide

## Project Overview

**ai-editutor** is a Neovim plugin that acts as a personal coding mentor - teaching developers through explanation rather than generating code automatically.

### Core Philosophy
> "Teach a person to fish, don't fish for them."

Unlike GitHub Copilot which writes code for you, ai-editutor has **two intentional modes**:
- **Q: (Question)** - Explains concepts deeply ("ask one, learn ten")
- **C: (Code)** - Generates code with explanatory notes

### v1.2.0 - Two Modes: Q: and C:

**Q: Mode** - Question/Explain (teach, don't just answer):
- `// Q: What is closure?` → deep explanation with best practices, pitfalls, resources
- `// Q: Review this code` → constructive code review
- `// Q: Debug: why does this return nil?` → guided debugging
- Response inserted as **comment block** (A: prefix)

**C: Mode** - Code Generation (working code + notes):
- `// C: function to validate email with regex` → generates actual code
- `// C: async function to fetch user data with retry` → production-ready code
- Response inserted as **actual code** + notes block

**Key Features:**
- **Skip answered questions** - Q:/C: with response below are automatically skipped
- **Visual selection support** - Select code block and ask about it
- **Streaming** - See response as it's generated
- **Adaptive context** - Full project (<20K tokens) or import graph + LSP

---

## Project Structure

```
ai-editutor/
├── lua/
│   └── editutor/
│       ├── init.lua              # Plugin entry point (v1.2.0)
│       ├── config.lua            # Configuration management
│       ├── parser.lua            # Comment parsing (Q: and C: modes)
│       ├── context.lua           # Context extraction (full/adaptive)
│       ├── lsp_context.lua       # LSP-based context (go-to-definition)
│       ├── import_graph.lua      # Import graph analysis
│       ├── comment_writer.lua    # Insert responses (Q: as comments, C: as code)
│       ├── prompts.lua           # Mode-specific prompts (Q: teach, C: generate)
│       ├── provider.lua          # LLM API with inheritance + streaming
│       ├── hints.lua             # 5-level progressive hints system
│       ├── knowledge.lua         # Knowledge tracking (SQLite/JSON)
│       ├── conversation.lua      # Session-based conversation memory
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

### Two-Mode Flow (v1.2)

```
User writes: // Q: What is closure?     OR     // C: validate email function
                    │                                      │
                    ▼                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. Parse Q:/C: comment and detect mode                                  │
│ 2. Check if already answered → skip if yes                              │
│ 3. Extract context (full project < 20K OR import graph + LSP)          │
│ 4. Build mode-specific prompt (Q: pedagogical / C: code generation)    │
│ 5. Stream to LLM (Claude/OpenAI/DeepSeek/etc.)                         │
│ 6. Insert response based on mode                                        │
└─────────────────────────────────────────────────────────────────────────┘
                    │                                      │
                    ▼                                      ▼
Q: Result:                              C: Result:
    // Q: What is closure?                  // C: validate email function
    /*                                      
    A: A closure is a function...           function validateEmail(email) {
    - Best practice: ...                      const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    - Watch out: ...                          return regex.test(email);
    - Learn more: ...                       }
    */                                      /*
                                            Notes:
                                            - This uses a simplified regex...
                                            - For production, consider...
                                            */
```

### Skip Answered Questions

```javascript
function test() {
  // Q: What is closure?       ← SKIPPED (already has A: below)
  /*
  A: A closure is a function...
  */

  // C: helper to format date  ← SKIPPED (code already generated below)
  function formatDate(d) { ... }

  // Q: How does async work?   ← FOUND (unanswered)
  return 42;
}
```

The parser automatically detects responses below Q:/C: comments and skips them.

### Visual Selection Support

```
1. Select code block with visual mode (v or V)
2. Write // Q: Explain this function (or // C: refactor this)
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
- Version: 1.2.0
- Creates user commands (`:EduTutorAsk`, `:EduTutorHint`, etc.)
- Sets up keymaps (normal mode + visual mode)
- Main functions: `ask()`, `ask_visual()`, `ask_with_hints()`
- Multi-language UI messages (English, Vietnamese)
- Mode-aware processing (Q: vs C:)

### parser.lua - Comment Parsing (Q: and C: modes)
- Parses `Q:` (question) and `C:` (code) prefixes (case insensitive)
- `parse_line()` - Returns `(question, mode)` tuple
- `has_answer_below()` - Detects response below Q:/C: comment
- `find_query()` - Finds unanswered query, skips answered ones
- `get_visual_selection()` - Get visual selection range and content
- `find_query_in_range()` - Find Q:/C: within visual selection

### prompts.lua - Mode-Specific Prompts
- **Q: mode (SYSTEM_PROMPT_QUESTION):**
  - "Ask one, learn ten" philosophy
  - Best practices, pitfalls, real-world examples
  - Direct answer + why + watch out + learn more
- **C: mode (SYSTEM_PROMPT_CODE):**
  - Generate working code (not pseudocode)
  - Match project's coding style
  - Include notes block with caveats/alternatives
- `get_system_prompt(mode)` - Returns prompt based on mode
- Bilingual support (English, Vietnamese)

### comment_writer.lua - Response Insertion
- **Q: mode:** Response as block/line comments with A: prefix
- **C: mode:** Code inserted as-is + notes block
- Streaming support:
  - `start_streaming()`, `update_streaming()`, `finish_streaming()` - Q: mode
  - `start_streaming_code()`, `update_streaming_code()`, `finish_streaming_code()` - C: mode
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

" Other commands
:EduTutorClearCache   " Clear context cache
:EduTutorLog          " Open debug log

" Health check
:checkhealth editutor
```

---

## Comment Syntax (Simplified)

Use `Q:` prefix for questions and `C:` prefix for code generation:

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

## C: Code Generation Mode

Use `C:` prefix to generate code:

```javascript
// C: function to validate email with regex
// C: async function to fetch user with retry logic
// C: React hook for debouncing input
// C: helper to deep clone an object

// Lowercase also works
// c: sort array by property
```

**Response format:**
```javascript
// C: function to validate email
function validateEmail(email) {
  const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return regex.test(email);
}
/*
Notes:
- This regex handles most common email formats
- For strict validation, consider: validator.js library
- Edge cases: + aliases, unicode domains
*/
```

The code is inserted as actual executable code, followed by a notes comment block.

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
  "nvim-treesitter/nvim-treesitter",  -- AST parsing, better code context
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

### Phase 9: C: Mode + Streaming - COMPLETE (v1.2.0)
- [x] Added C: code generation mode
- [x] Mode-specific prompts (Q: teach, C: generate)
- [x] Streaming support for both modes
- [x] Import graph for adaptive context
- [x] DeepSeek provider support

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
