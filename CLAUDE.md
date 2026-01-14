# CLAUDE.md - AI Code Mentor Development Guide

## Project Overview

**AI Code Mentor** is a Neovim plugin that acts as a personal coding mentor - teaching developers through explanation rather than generating code automatically.

### Core Philosophy
> "Teach a person to fish, don't fish for them."

Unlike GitHub Copilot which writes code for you, AI Code Mentor **explains concepts** so you can write better code yourself.

---

## Project Structure

```
ai-tutor/
├── lua/
│   └── codementor/
│       ├── init.lua              # Plugin entry point
│       ├── config.lua            # Configuration management
│       ├── parser.lua            # Comment parsing (// Q:, // S:, etc.)
│       ├── context.lua           # Context extraction via Tree-sitter
│       ├── provider.lua          # LLM API abstraction (Claude, OpenAI, Ollama)
│       ├── ui.lua                # Floating window rendering (nui.nvim)
│       ├── modes/
│       │   ├── question.lua      # Q: Direct question mode
│       │   ├── socratic.lua      # S: Socratic questioning mode
│       │   ├── review.lua        # R: Code review mode
│       │   ├── debug.lua         # D: Debug assistance mode
│       │   └── explain.lua       # E: Deep explanation mode
│       ├── hints.lua             # Incremental hints system
│       ├── knowledge.lua         # Knowledge tracking & storage
│       └── rag/
│           ├── chunker.lua       # AST-based code chunking
│           ├── embedder.lua      # Embedding generation interface
│           ├── search.lua        # Hybrid search (BM25 + vector)
│           └── retrieval.lua     # Two-stage retrieval
├── python/
│   └── codementor_cli/
│       ├── __init__.py
│       ├── cli.py                # CLI entry point
│       ├── indexer.py            # Codebase indexing
│       ├── chunker.py            # AST chunking (astchunk)
│       ├── embedder.py           # sentence-transformers
│       └── db.py                 # LanceDB operations
├── plugin/
│   └── codementor.lua            # Lazy loading entry
├── doc/
│   └── codementor.txt            # Vim help documentation
├── tests/
│   └── ...
├── research/                     # Reference implementations (cloned repos)
│   ├── core/                     # Core plugin architecture
│   │   ├── gp.nvim/              # Popup, streaming, multi-provider
│   │   ├── wtf.nvim/             # Explanation-first architecture
│   │   ├── backseat.nvim/        # Code review/teaching pattern
│   │   ├── ChatGPT.nvim/         # Built-in explain actions
│   │   ├── codecompanion.nvim/   # Workspaces, slash commands
│   │   └── gen.nvim/             # Local Ollama support
│   ├── rag/                      # RAG implementations
│   │   ├── VectorCode/           # Neovim RAG (CLI + Plugin)
│   │   ├── continue/             # Enterprise indexing, hybrid search
│   │   ├── code-graph-rag/       # Knowledge graph approach
│   │   ├── SeaGOAT/              # Local-first semantic search
│   │   └── semantic-code-search/ # Simple CLI semantic search
│   ├── chunking/                 # AST-based chunking
│   │   ├── astchunk/             # Python AST chunking
│   │   └── code-chunk/           # TypeScript AST chunker
│   ├── ui/                       # UI components
│   │   ├── nui.nvim/             # Floating windows, popups
│   │   └── render-markdown.nvim/ # Markdown rendering
│   ├── backend/                  # LLM integration
│   │   ├── lsp-ai/               # Rust LLM server
│   │   ├── llm.nvim/             # OpenAI-compatible API
│   │   └── lancedb/              # Embedded vector database
│   ├── reference/                # Concepts & patterns
│   │   ├── AiComments/           # Comment syntax convention
│   │   ├── vscode-extension-samples/ # VS Code tutor samples
│   │   ├── avante.nvim/          # Cursor-like IDE
│   │   └── CopilotChat.nvim/     # GitHub Copilot chat
│   └── tools/                    # AST search tools
│       └── ast-grep/             # Tree-sitter structural search
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
# Run tests
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Lint Lua
luacheck lua/

# Format Lua
stylua lua/

# Python CLI (from python/ directory)
pip install -e .
codementor-cli index /path/to/project
codementor-cli query "How does authentication work?"
```

### Plugin Usage (in Neovim)
```vim
" Trigger mentor on current comment
<leader>ma    " Mentor Ask

" Quick actions
<leader>mq    " Quick question (Q mode)
<leader>ms    " Socratic mode
<leader>mr    " Review current function
<leader>md    " Debug assistance
<leader>me    " Explain concept

" Knowledge
<leader>mk    " Search knowledge base
<leader>mx    " Export knowledge to markdown
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

### Phase 1: MVP (Current)
- [ ] Comment parsing (`// Q:` detection)
- [ ] Basic context collection (current buffer + 50 lines)
- [ ] Claude API integration
- [ ] Floating window response
- [ ] Single keybinding `<leader>ma`

### Phase 2: Multi-Mode
- [ ] 5 interaction modes (Q/S/R/D/E)
- [ ] Incremental hints system
- [ ] Basic knowledge tracking (SQLite)
- [ ] Mode-specific prompts

### Phase 3: RAG
- [ ] Python CLI for indexing
- [ ] AST-based chunking
- [ ] LanceDB vector storage
- [ ] Hybrid search
- [ ] Two-stage retrieval

### Phase 4: Polish
- [ ] Knowledge export to Markdown
- [ ] Obsidian integration
- [ ] Team sharing
- [ ] Vietnamese language support

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
require('codementor').setup({
  provider = {
    timeout = 30000,  -- 30 seconds
  }
})
```

### Issue: RAG index outdated
```bash
# Re-index codebase
codementor-cli index --force /path/to/project
```

---

## Resources

- [Tree-sitter Neovim Guide](https://tree-sitter.github.io/tree-sitter/)
- [LanceDB Documentation](https://lancedb.github.io/lancedb/)
- [nui.nvim Wiki](https://github.com/MunifTanjim/nui.nvim/wiki)
- [Claude API Docs](https://docs.anthropic.com/)
- [Pedagogical AI Research (CS50.ai)](https://cs50.ai/)
