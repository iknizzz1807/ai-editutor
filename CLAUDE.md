# CLAUDE.md - ai-editutor Development Guide

## Project Overview

**ai-editutor** is a Neovim plugin that acts as a personal coding mentor - teaching developers through explanation rather than generating code automatically.

### Core Philosophy
> "Teach a person to fish, don't fish for them."

Unlike GitHub Copilot which writes code for you, ai-editutor **explains concepts** so you can write better code yourself.

---

## Project Structure

```
ai-editutor/
├── lua/
│   └── editutor/
│       ├── init.lua              # Plugin entry point (v0.6.0)
│       ├── config.lua            # Configuration management
│       ├── parser.lua            # Comment parsing (// Q:, // S:, etc.)
│       ├── context.lua           # Context extraction (Tree-sitter)
│       ├── lsp_context.lua       # LSP-based context (go-to-definition)
│       ├── prompts.lua           # Pedagogical prompt templates
│       ├── provider.lua          # LLM API (Claude, OpenAI, Ollama) + Streaming
│       ├── ui.lua                # Floating window + streaming display
│       ├── hints.lua             # Incremental hints (4 levels)
│       ├── knowledge.lua         # Knowledge tracking (SQLite/JSON fallback)
│       └── health.lua            # :checkhealth editutor
├── plugin/
│   └── editutor.lua              # Lazy loading entry
├── doc/
│   └── editutor.txt              # Vim help documentation
├── tests/
│   ├── spec/                     # Unit tests (plenary)
│   ├── fixtures/                 # Multi-language test projects
│   │   ├── typescript-fullstack/ # TypeScript/React (11 files)
│   │   ├── python-django/        # Python/Django (11 files)
│   │   ├── go-gin/               # Go/Gin (10 files)
│   │   ├── rust-axum/            # Rust/Axum (9 files)
│   │   ├── java-spring/          # Java/Spring (8 files)
│   │   ├── cpp-server/           # C++/Crow (10 files)
│   │   ├── vanilla-frontend/     # HTML/CSS/JS (9 files)
│   │   ├── vue-app/              # Vue.js (10 files)
│   │   ├── svelte-app/           # Svelte (9 files)
│   │   └── angular-app/          # Angular (9 files)
│   └── manual_lsp_test.lua       # Manual LSP verification script
├── research/                     # Reference implementations (cloned repos)
│   ├── core/                     # gp.nvim, wtf.nvim, backseat.nvim
│   ├── ui/                       # nui.nvim, render-markdown.nvim
│   ├── backend/                  # lsp-ai, llm.nvim
│   └── reference/                # AiComments, vscode-extension-samples
├── README.md
└── CLAUDE.md                     # This file
```

---

## Architecture Overview

### Context Extraction: LSP-Based (v0.6.0+)

ai-editutor uses **LSP go-to-definition** for context extraction instead of RAG:

```
User writes // Q: question
       │
       ▼
┌─────────────────────────────────────────────────────────┐
│ 1. Extract code around cursor (±50 lines)               │
│ 2. Use Tree-sitter to find all identifiers              │
│ 3. For each identifier, call LSP textDocument/definition│
│ 4. Filter: only include PROJECT files (not libraries)   │
│ 5. Read ±15 lines around each definition                │
│ 6. Format all context for LLM prompt                    │
└─────────────────────────────────────────────────────────┘
       │
       ▼
LLM receives: current code + related definitions from project
```

**Why LSP instead of RAG?**
- Zero setup - works immediately with existing LSP
- No indexing/embedding required
- No Python dependencies
- Always up-to-date (LSP reads actual files)
- More precise (exact definitions, not similarity search)

**Excluded paths (library detection):**
```lua
M.exclude_patterns = {
  "node_modules", ".venv", "venv", "site%-packages",
  "vendor", "%.cargo/registry", "target/debug", "target/release",
  "/usr/", "/opt/", "%.local/lib/", "%.luarocks/",
}
```

---

## Research Repos Quick Reference

### Priority 1: Core Architecture

| Repo | Path | Learn From |
|------|------|------------|
| **gp.nvim** | `research/core/gp.nvim/` | Popup system, streaming, provider abstraction |
| **wtf.nvim** | `research/core/wtf.nvim/` | Explanation-first architecture, context collection |
| **nui.nvim** | `research/ui/nui.nvim/` | Floating window API |

### Priority 2: Reference

| Repo | Path | Learn From |
|------|------|------------|
| **AiComments** | `research/reference/AiComments/` | Comment syntax convention |
| **vscode-extension-samples** | `research/reference/vscode-extension-samples/` | Tutor prompt engineering |

---

## Key Files

### init.lua - Plugin Entry Point
- Version: 0.6.0
- Creates all user commands (`:EduTutor*`)
- Sets up keymaps
- Main functions: `ask()`, `ask_stream()`, `ask_with_hints()`
- Multi-language UI messages (English, Vietnamese)

### lsp_context.lua - LSP Context Extraction
- `is_available()` - Check if LSP is running
- `get_project_root()` - Find git root or cwd
- `is_project_file()` - Filter out library code
- `extract_identifiers()` - Tree-sitter identifier extraction
- `get_definition()` - LSP textDocument/definition
- `get_external_definitions()` - Async gather all external defs
- `format_for_prompt()` - Format context for LLM

### config.lua - Configuration
- Default provider: Claude (claude-sonnet-4-20250514)
- Context settings: 100 lines around cursor, 20 max external symbols
- Provider configs for Claude, OpenAI, Ollama
- UI and keymap settings

### provider.lua - LLM Communication
- `query_async()` - Non-streaming request
- `query_stream()` - Streaming with SSE parsing
- Supports Claude, OpenAI, Ollama APIs
- Error handling and retry logic

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

# Manual LSP context test (in Neovim)
:lua require('tests.manual_lsp_test').test_all()
:lua require('tests.manual_lsp_test').test_typescript_fullstack()
:lua require('tests.manual_lsp_test').test_vue_app()
```

### Plugin Usage (in Neovim)
```vim
" Core commands
<leader>ma           " Ask (normal)
<leader>ms           " Ask (streaming)
:EduTutorHint        " Progressive hints

" Mode commands
:EduTutorQuestion    " Q mode
:EduTutorSocratic    " S mode
:EduTutorReview      " R mode
:EduTutorDebug       " D mode
:EduTutorExplain     " E mode

" Knowledge commands
:EduTutorHistory     " Show Q&A history
:EduTutorSearch      " Search knowledge base
:EduTutorExport      " Export to markdown
:EduTutorStats       " Show statistics

" Language commands
:EduTutorLang             " Show current language
:EduTutorLang Vietnamese  " Switch to Vietnamese
:EduTutorLang English     " Switch to English

" Health check
:checkhealth editutor
```

---

## Comment Syntax

The plugin parses these comment patterns:

```javascript
// Q: What is the time complexity of this algorithm?
// S: Why might using a hash map be better here?
// R: Review this function for security issues
// D: This function sometimes returns nil, why?
// E: Explain closures in JavaScript
```

Supported in all languages via Tree-sitter comment node detection.

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
  "MunifTanjim/nui.nvim",       -- Enhanced UI components
  "MeanderingProgrammer/render-markdown.nvim",  -- Response formatting
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
- [x] Streaming response support

### Phase 4: Polish - COMPLETE
- [x] Knowledge export to Markdown
- [x] Health check (:checkhealth editutor)
- [x] Vietnamese language support (:EduTutorLang)
- [x] Enhanced prompts (best practices, examples, anti-patterns)

### Future Enhancements
- [ ] Obsidian integration
- [ ] Team sharing
- [ ] nui.nvim enhanced UI

---

## Prompting Guidelines

### Pedagogical Prompt Structure
```
You are a coding mentor helping a developer understand concepts.

Guidelines:
1. EXPLAIN concepts, don't just give solutions
2. Use Socratic questioning when appropriate
3. Provide incremental hints (subtle → clearer → partial → full)
4. Reference the actual code context provided
5. Suggest follow-up learning topics
6. Keep explanations concise but thorough

Context:
- Language: {language}
- Current file: {filepath}
- Code context:
{code_context}

Question: {user_question}
```

### Mode-Specific Prompts
- **Q (Question)**: Direct, educational answer with examples
- **S (Socratic)**: Ask guiding questions, don't answer directly
- **R (Review)**: Point out issues, suggest improvements, praise good parts
- **D (Debug)**: Guide debugging process, don't fix directly
- **E (Explain)**: Deep dive with What/Why/How/When/Examples

---

## Testing Strategy

### Unit Tests (tests/spec/)
- Parser tests (comment detection)
- Context extraction tests
- Mode logic tests
- Config validation tests

### Fixture Projects (tests/fixtures/)
Each fixture contains:
- 8-11 files with realistic cross-file dependencies
- `// Q:` comments asking real programming questions
- Import chains for LSP to follow

**Fixtures:**
| Language | Files | Key Patterns |
|----------|-------|--------------|
| TypeScript/React | 11 | hooks → services → api → types |
| Python/Django | 11 | views → services → models |
| Go/Gin | 10 | handlers → services → repository |
| Rust/Axum | 9 | handlers → services → models |
| Java/Spring | 8 | controllers → services → repos |
| C++/Crow | 10 | handlers → services → models |
| Vanilla JS | 9 | components → services → api |
| Vue.js | 10 | composables → services → api |
| Svelte | 9 | stores → services → api |
| Angular | 9 | components → services → guards |

### Manual LSP Testing
```lua
-- In Neovim with LSP configured:
:lua require('tests.manual_lsp_test').test_all()

-- Test specific framework:
:lua require('tests.manual_lsp_test').test_vue_app()
:lua require('tests.manual_lsp_test').test_angular_app()

-- Test current buffer:
:lua require('tests.manual_lsp_test').test_current_buffer()
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
" Lua: lua_ls (lua-language-server)
" Python: pyright or pylsp
" TypeScript: typescript-language-server
" Go: gopls
" Rust: rust-analyzer
```

### Issue: No external context appearing
```lua
-- ai-editutor will warn if LSP is unavailable
-- Check :checkhealth editutor for LSP status
-- External definitions only come from PROJECT files
-- Library paths (node_modules, etc.) are excluded
```

---

## Resources

- [Tree-sitter Neovim Guide](https://tree-sitter.github.io/tree-sitter/)
- [Neovim LSP Documentation](https://neovim.io/doc/user/lsp.html)
- [nui.nvim Wiki](https://github.com/MunifTanjim/nui.nvim/wiki)
- [Claude API Docs](https://docs.anthropic.com/)
- [Pedagogical AI Research (CS50.ai)](https://cs50.ai/)
