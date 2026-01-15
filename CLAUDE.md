# CLAUDE.md - ai-editutor Development Guide

## Project Overview

**ai-editutor** is a Neovim plugin that acts as a personal coding mentor - teaching developers through explanation rather than generating code automatically.

### Core Philosophy
> "Teach a person to fish, don't fish for them."

Unlike GitHub Copilot which writes code for you, ai-editutor **explains concepts** so you can write better code yourself.

### v0.8.0 - Inline Comments UI
Responses are now inserted as **inline comments** directly in your code file, right below your question. No floating windows - everything stays in your code.

---

## Project Structure

```
ai-editutor/
├── lua/
│   └── editutor/
│       ├── init.lua              # Plugin entry point (v0.8.0)
│       ├── config.lua            # Configuration management
│       ├── parser.lua            # Comment parsing (// Q:, // S:, etc.)
│       ├── context.lua           # Context extraction (Tree-sitter)
│       ├── lsp_context.lua       # LSP-based context (go-to-definition)
│       ├── comment_writer.lua    # Insert responses as inline comments
│       ├── prompts.lua           # Pedagogical prompt templates
│       ├── provider.lua          # LLM API (Claude, OpenAI, Ollama)
│       ├── hints.lua             # Incremental hints (4 levels)
│       ├── knowledge.lua         # Knowledge tracking (SQLite/JSON fallback)
│       ├── conversation.lua      # Session-based conversation memory
│       ├── project_context.lua   # Project docs context
│       └── health.lua            # :checkhealth editutor
├── plugin/
│   └── editutor.lua              # Lazy loading entry
├── doc/
│   └── editutor.txt              # Vim help documentation
├── tests/
│   ├── spec/                     # Unit tests (plenary)
│   ├── fixtures/                 # Multi-language test projects
│   └── manual_lsp_test.lua       # Manual LSP verification script
├── README.md
└── CLAUDE.md                     # This file
```

---

## Architecture Overview

### Inline Comment Response (v0.8.0)

```
User writes: // Q: What is closure?
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│ 1. Parse comment (detect Q/S/R/D/E mode)               │
│ 2. Extract code context + LSP definitions              │
│ 3. Build pedagogical prompt                            │
│ 4. Send to LLM (Claude/OpenAI/Ollama)                  │
│ 5. Insert response as comment below question           │
└─────────────────────────────────────────────────────────┘
                    │
                    ▼
Result in code:
    // Q: What is closure?
    /*
    A: A closure is a function that captures variables
    from its enclosing scope...

    Example:
    function outer() {
      let x = 10;
      return function inner() { console.log(x); }
    }
    */
```

### Comment Style Detection

The plugin automatically detects the appropriate comment style based on filetype:

| Languages | Line Comment | Block Comment |
|-----------|--------------|---------------|
| JS/TS/Go/Rust/C/C++/Java | `//` | `/* */` |
| Python/Ruby/Shell | `#` | `""" """` or `=begin =end` |
| Lua/SQL/Haskell | `--` | `--[[ ]]` or `{- -}` |
| HTML/XML | - | `<!-- -->` |

Block comments are preferred when available.

### Context Extraction: LSP-Based

ai-editutor uses **LSP go-to-definition** for context extraction:

1. Extract code around cursor (±50 lines)
2. Use Tree-sitter to find all identifiers
3. For each identifier, call LSP textDocument/definition
4. Filter: only include PROJECT files (not libraries)
5. Read ±15 lines around each definition
6. Format all context for LLM prompt

**Why LSP instead of RAG?**
- Zero setup - works immediately with existing LSP
- No indexing/embedding required
- No Python dependencies
- Always up-to-date (LSP reads actual files)

---

## Key Files

### init.lua - Plugin Entry Point
- Version: 0.8.0
- Creates all user commands (`:EduTutor*`)
- Sets up keymaps
- Main functions: `ask()`, `ask_with_hints()`
- Multi-language UI messages (English, Vietnamese)

### comment_writer.lua - Inline Comment Insertion
- `get_style()` - Detect comment style for filetype
- `format_response()` - Format response as block/line comments
- `insert_response()` - Insert after question line
- `insert_or_replace()` - Replace existing response if present
- Supports 40+ languages

### lsp_context.lua - LSP Context Extraction
- `is_available()` - Check if LSP is running
- `get_project_root()` - Find git root or cwd
- `is_project_file()` - Filter out library code
- `extract_identifiers()` - Tree-sitter identifier extraction
- `get_definition()` - LSP textDocument/definition

### config.lua - Configuration
- Default provider: Claude (claude-sonnet-4-20250514)
- Context settings: 100 lines around cursor, 20 max external symbols
- Provider configs for Claude, OpenAI, Ollama
- Single keymap: `<leader>ma`

### prompts.lua - Pedagogical Prompts
- Concise prompts optimized for inline comments
- No emoji headers (plain text for code comments)
- Mode-specific instructions (Q/S/R/D/E)

---

## Key Commands

### Development
```bash
# Lint Lua
luacheck lua/

# Format Lua
stylua lua/

# Run tests
nvim --headless -c "PlenaryBustedDirectory tests/spec {minimal_init = 'tests/minimal_init.lua'}"
```

### Plugin Usage (in Neovim)
```vim
" Core command
<leader>ma           " Ask - response inserted as inline comment

" Mode commands
:EduTutorQuestion    " Q mode
:EduTutorSocratic    " S mode
:EduTutorReview      " R mode
:EduTutorDebug       " D mode
:EduTutorExplain     " E mode
:EduTutorHint        " Progressive hints (run multiple times)

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

" Health check
:checkhealth editutor
```

---

## Comment Syntax

The plugin parses these comment patterns:

```javascript
// Q: What is the time complexity of this algorithm?
// A: The response will be inserted here as a comment...

// S: Why might using a hash map be better here?
// R: Review this function for security issues
// D: This function sometimes returns nil, why?
// E: Explain closures in JavaScript
```

Supported in all languages via comment pattern detection.

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
  "nvim-treesitter/nvim-treesitter",  -- AST parsing, better context
}
```

### Optional
```lua
dependencies = {
  "kkharji/sqlite.lua",         -- Enhanced knowledge storage
}
```

---

## Development Phases

### Phase 1: MVP - COMPLETE
- [x] Comment parsing (`// Q:` detection)
- [x] Basic context collection (current buffer + 50 lines)
- [x] Claude API integration
- [x] Floating window response
- [x] Single keybinding `<leader>ma`

### Phase 2: Multi-Mode - COMPLETE
- [x] 5 interaction modes (Q/S/R/D/E)
- [x] Incremental hints system (4 levels)
- [x] Knowledge tracking (JSON fallback, SQLite optional)
- [x] Mode-specific pedagogical prompts
- [x] Knowledge search and export

### Phase 3: LSP Context - COMPLETE (v0.6.0)
- [x] LSP-based context extraction
- [x] Go-to-definition for external symbols
- [x] Project file filtering (exclude libraries)
- [x] Tree-sitter fallback when no LSP
- [x] Configurable context window (100 lines default)

### Phase 4: Polish - COMPLETE
- [x] Knowledge export to Markdown
- [x] Health check (:checkhealth editutor)
- [x] Vietnamese language support (:EduTutorLang)

### Phase 5: Conversation Memory - COMPLETE (v0.7.0)
- [x] Session-based conversation memory
- [x] Smart session management (file + line proximity)
- [x] Project documentation context (README, package.json)
- [x] Conversation management commands

### Phase 6: Inline Comments UI - COMPLETE (v0.8.0)
- [x] Response as inline comments (no floating window)
- [x] Auto-detect comment style per language
- [x] Block comment support for 40+ languages
- [x] Replace existing response on re-ask
- [x] Concise prompts optimized for inline display

### Future Enhancements
- [ ] Obsidian integration
- [ ] Team sharing

---

## Prompting Guidelines

### Inline Comment Prompts
Since responses appear as code comments, prompts instruct the LLM to:
- Keep responses concise and structured
- Avoid emoji headers
- Use plain text formatting
- Include 1-2 code examples when helpful
- Focus on the key points

### Mode-Specific Prompts
- **Q (Question)**: Direct answer, brief explanation, one example
- **S (Socratic)**: Guiding questions, don't answer directly
- **R (Review)**: Critical issues, warnings, suggestions, what's good
- **D (Debug)**: Symptoms, hypothesis, verification steps, fix pattern
- **E (Explain)**: What/Why/How/When/Example/Next

---

## Testing Strategy

### Unit Tests (tests/spec/)
- Parser tests (comment detection)
- Context extraction tests
- Comment writer tests
- Config validation tests

### Fixture Projects (tests/fixtures/)
Each fixture contains:
- 8-11 files with realistic cross-file dependencies
- `// Q:` comments asking real programming questions
- Import chains for LSP to follow

### Manual LSP Testing
```lua
-- In Neovim with LSP configured:
:lua require('tests.manual_lsp_test').test_all()

-- Test specific framework:
:lua require('tests.manual_lsp_test').test_vue_app()
:lua require('tests.manual_lsp_test').test_angular_app()
```

---

## Common Issues & Solutions

### Issue: Tree-sitter parser not found
```lua
-- Ensure language is installed
:TSInstall python javascript go rust
```

### Issue: LLM API timeout
```lua
-- Increase timeout in config
require('editutor').setup({
  provider = {
    timeout = 30000,  -- 30 seconds
  }
})
```

### Issue: LSP not attaching
```vim
" Check LSP status
:LspInfo

" Ensure LSP server is installed for your language
```

### Issue: Wrong comment style
```lua
-- Check if filetype is detected correctly
:set filetype?

-- comment_writer.lua supports 40+ languages
-- Add custom styles in comment_writer.comment_styles table
```

---

## Resources

- [Tree-sitter Neovim Guide](https://tree-sitter.github.io/tree-sitter/)
- [Neovim LSP Documentation](https://neovim.io/doc/user/lsp.html)
- [Claude API Docs](https://docs.anthropic.com/)
- [Pedagogical AI Research (CS50.ai)](https://cs50.ai/)
