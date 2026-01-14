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
│       ├── context.lua           # Context extraction (Tree-sitter + LSP)
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
├── research/                     # Reference implementations (cloned repos)
│   ├── core/                     # gp.nvim, wtf.nvim, backseat.nvim, etc.
│   ├── ui/                       # nui.nvim, render-markdown.nvim
│   ├── backend/                  # lsp-ai, llm.nvim
│   ├── reference/                # AiComments, vscode-extension-samples
│   └── tools/                    # ast-grep
├── README.md
└── CLAUDE.md                     # This file
```

---

## Research Repos Quick Reference

### Priority 1: Core Architecture (Start Here)

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

## Key Files to Study

### gp.nvim (Core Architecture)
```
research/core/gp.nvim/lua/gp/
├── init.lua        # Entry point, command registration
├── config.lua      # Configuration patterns
├── dispatcher.lua  # Request handling, streaming
├── render.lua      # UI rendering
└── helper.lua      # Utility functions
```

### wtf.nvim (Explanation Pattern)
```
research/core/wtf.nvim/lua/wtf/
├── init.lua                    # Plugin setup
├── ai/
│   ├── client.lua              # LLM client abstraction
│   └── providers/
│       ├── anthropic.lua       # Claude integration
│       └── openai.lua          # OpenAI integration
├── search.lua                  # Context extraction
└── diagnostics.lua             # Error handling
```

### nui.nvim (UI)
```
research/ui/nui.nvim/lua/nui/
├── popup/
│   └── init.lua                # Floating window
├── input/
│   └── init.lua                # Input component
└── layout/
    └── init.lua                # Layout management
```

---

## Key Commands

### Development
```bash
# Lint Lua
luacheck lua/

# Format Lua
stylua lua/
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

## Architecture Decisions

### 1. LSP-Based Context (v0.6.0+)
- **Context Extraction**: Uses LSP go-to-definition for related code
- **Scope**: Only project files (filters out library code)
- **Fallback**: Tree-sitter context when LSP unavailable
- **Performance**: Limited to 100 lines around cursor

### 2. LLM Providers
Priority order:
1. Claude API (primary - best for teaching)
2. OpenAI API (fallback)
3. Ollama (local, privacy-focused)

### 3. UI Framework
- nui.nvim for floating windows
- render-markdown.nvim for response formatting

### 4. Knowledge Tracking
- SQLite (if sqlite.lua available) or JSON fallback
- Searchable Q&A history
- Export to Markdown

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
  "nvim-treesitter/nvim-treesitter",  -- AST parsing, better fallback
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

### Phase 1: MVP ✅ COMPLETE
- [x] Comment parsing (`// Q:` detection)
- [x] Basic context collection (current buffer + 50 lines)
- [x] Claude API integration
- [x] Floating window response
- [x] Single keybinding `<leader>ma`

### Phase 2: Multi-Mode ✅ COMPLETE
- [x] 5 interaction modes (Q/S/R/D/E)
- [x] Incremental hints system (4 levels)
- [x] Knowledge tracking (JSON fallback, SQLite optional)
- [x] Mode-specific pedagogical prompts
- [x] Knowledge search and export

### Phase 3: LSP Context ✅ COMPLETE (v0.6.0)
- [x] LSP-based context extraction
- [x] Go-to-definition for external symbols
- [x] Project file filtering (exclude libraries)
- [x] Tree-sitter fallback when no LSP
- [x] Configurable context window (100 lines default)
- [x] Streaming response support

### Phase 4: Polish ✅ COMPLETE
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

### Unit Tests
- Parser tests (comment detection)
- Context extraction tests
- Mode logic tests
- LSP context tests

### Integration Tests
- Full flow: comment → parse → context → LLM → render
- LSP context with external definitions

### Manual Testing
```lua
-- Test comment in any file:
// Q: What does this function do?
-- Press <leader>ma and verify response

-- Test LSP context:
-- 1. Open a file with LSP running
-- 2. Navigate to code that uses external symbols
-- 3. Add a Q: comment and run :EduTutorAsk
-- 4. Verify context includes external definitions
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
" Lua: lua-language-server
" Python: pyright or pylsp
" TypeScript: typescript-language-server
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
