# CLAUDE.md - AI EduTutor Development Guide

## Project Overview

**AI EduTutor** is a Neovim plugin that acts as a personal coding mentor - teaching developers through explanation rather than generating code automatically.

### Core Philosophy
> "Teach a person to fish, don't fish for them."

Unlike GitHub Copilot which writes code for you, AI EduTutor **explains concepts** so you can write better code yourself.

---

## Project Structure

```
ai-tutor/
├── lua/
│   └── editutor/
│       ├── init.lua              # Plugin entry point (v0.3.0)
│       ├── config.lua            # Configuration management
│       ├── parser.lua            # Comment parsing (// Q:, // S:, etc.)
│       ├── context.lua           # Context extraction via Tree-sitter
│       ├── prompts.lua           # Pedagogical prompt templates
│       ├── provider.lua          # LLM API (Claude, OpenAI, Ollama) + Streaming
│       ├── ui.lua                # Floating window + streaming display
│       ├── hints.lua             # Incremental hints (4 levels)
│       ├── knowledge.lua         # Knowledge tracking (SQLite/JSON fallback)
│       ├── rag.lua               # RAG integration (calls Python CLI)
│       └── health.lua            # :checkhealth editutor
├── python/
│   ├── pyproject.toml            # Package configuration
│   └── editutor_cli/
│       ├── __init__.py           # Package init (v0.1.0)
│       ├── cli.py                # CLI commands (index, query, status, clear)
│       ├── indexer.py            # LanceDB indexing with file hashing
│       ├── chunker.py            # AST-based chunking (Tree-sitter)
│       ├── embedder.py           # sentence-transformers embeddings
│       └── search.py             # Hybrid search (BM25 + vector + RRF)
├── plugin/
│   └── editutor.lua            # Lazy loading entry
├── doc/
│   └── editutor.txt            # Vim help documentation
├── research/                     # Reference implementations (cloned repos)
│   ├── core/                     # gp.nvim, wtf.nvim, backseat.nvim, etc.
│   ├── rag/                      # VectorCode, continue, SeaGOAT, etc.
│   ├── chunking/                 # astchunk, code-chunk
│   ├── ui/                       # nui.nvim, render-markdown.nvim
│   ├── backend/                  # lsp-ai, llm.nvim, lancedb
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

### Priority 2: RAG System

| Repo | Path | Learn From |
|------|------|------------|
| **VectorCode** | `research/rag/VectorCode/` | CLI + Plugin pattern, Neovim RAG integration |
| **continue** | `research/rag/continue/` | Two-stage retrieval, hybrid search, enterprise patterns |
| **astchunk** | `research/chunking/astchunk/` | AST-based chunking implementation |
| **lancedb** | `research/backend/lancedb/` | Embedded vector database |

### Priority 3: Reference

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

### VectorCode (RAG Pattern)
```
research/rag/VectorCode/
├── src/vectorcode/
│   ├── cli_utils.py            # CLI commands
│   ├── chunking.py             # Code chunking
│   └── subcommands/
│       ├── vectorise.py        # Indexing
│       └── query.py            # Search
└── lua/vectorcode/
    └── integrations/           # Neovim integration
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

# Python CLI installation (from python/ directory)
pip install -e .

# Index codebase
editutor-cli index /path/to/project

# Search codebase
editutor-cli query "How does authentication work?" --hybrid

# Check index status
editutor-cli status
```

### Plugin Usage (in Neovim)
```vim
" Core commands
<leader>ma           " Ask (normal)
<leader>ms           " Ask (streaming)
:EduTutorHint      " Progressive hints

" Mode commands
:EduTutorQuestion  " Q mode
:EduTutorSocratic  " S mode
:EduTutorReview    " R mode
:EduTutorDebug     " D mode
:EduTutorExplain   " E mode

" Knowledge commands
:EduTutorHistory   " Show Q&A history
:EduTutorSearch    " Search knowledge base
:EduTutorExport    " Export to markdown
:EduTutorStats     " Show statistics

" RAG commands
:EduTutorIndex     " Index codebase
:EduTutorRAG       " Ask with codebase context
:EduTutorRAGStatus " Show RAG status

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

### 1. CLI + Plugin Pattern (from VectorCode)
- **Python CLI**: Heavy computation (indexing, embedding generation)
- **Lua Plugin**: UI, context assembly, LLM calls
- **Communication**: JSON via stdout/stdin

### 2. RAG Stack
- **Chunking**: AST-based via Tree-sitter (astchunk pattern)
- **Embeddings**: all-MiniLM-L6-v2 (local) or voyage-code-3 (API)
- **Vector DB**: LanceDB (embedded, no Docker)
- **Search**: Hybrid (BM25 + semantic) with Reciprocal Rank Fusion

### 3. LLM Providers
Priority order:
1. Claude API (primary - best for teaching)
2. OpenAI API (fallback)
3. Ollama (local, privacy-focused)

### 4. UI Framework
- nui.nvim for floating windows
- render-markdown.nvim for response formatting

---

## Code Style Guidelines

### Lua
- Use `local` for all variables
- Prefer `vim.tbl_*` functions for table operations
- Use `vim.notify` for user messages
- Async operations via `plenary.job`
- Follow LazyVim conventions

### Python
- Type hints required
- Use `pathlib.Path` for file operations
- Async where beneficial (aiohttp for API calls)
- pytest for testing

---

## Key Dependencies

### Lua (Neovim plugins)
```lua
dependencies = {
  "nvim-lua/plenary.nvim",      -- Async utilities, HTTP
  "MunifTanjim/nui.nvim",       -- UI components
  "nvim-treesitter/nvim-treesitter",  -- AST parsing
  "MeanderingProgrammer/render-markdown.nvim",  -- Response formatting
}
```

### Python
```
sentence-transformers>=2.2.0
lancedb>=0.1.0
tree-sitter>=0.20.0
tree-sitter-languages>=1.0.0
click>=8.0.0
rich>=13.0.0
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

### Phase 3: RAG ✅ COMPLETE
- [x] Python CLI for indexing (editutor-cli)
- [x] AST-based chunking (Tree-sitter)
- [x] LanceDB vector storage
- [x] Hybrid search (BM25 + semantic + RRF)
- [x] Neovim integration (:EduTutorRAG)
- [x] Streaming response support

### Phase 4: Polish (In Progress)
- [x] Knowledge export to Markdown
- [x] Health check (:checkhealth editutor)
- [ ] Obsidian integration
- [ ] Team sharing
- [ ] Vietnamese language support
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

### Integration Tests
- Full flow: comment → parse → context → LLM → render
- RAG pipeline tests

### Manual Testing
```lua
-- Test comment in any file:
// Q: What does this function do?
-- Press <leader>ma and verify response
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

### Issue: RAG index outdated
```bash
# Re-index codebase
editutor-cli index --force /path/to/project
```

---

## Resources

- [Tree-sitter Neovim Guide](https://tree-sitter.github.io/tree-sitter/)
- [LanceDB Documentation](https://lancedb.github.io/lancedb/)
- [nui.nvim Wiki](https://github.com/MunifTanjim/nui.nvim/wiki)
- [Claude API Docs](https://docs.anthropic.com/)
- [Pedagogical AI Research (CS50.ai)](https://cs50.ai/)
