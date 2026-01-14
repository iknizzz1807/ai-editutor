# AI Code Mentor

> **"GitHub Copilot writes code for you. AI Code Mentor teaches you to write better code."**

A Neovim plugin that acts as your personal coding mentor - explaining concepts, guiding your thinking, and helping you truly understand code rather than just generating it.

## Why AI Code Mentor?

| Problem | Solution |
|---------|----------|
| Copilot generates code - you just accept - you don't learn | AI explains - you write every line - you actually learn |
| Context switching to browser for docs | Ask questions directly in your editor |
| ChatGPT gives answers without teaching | Socratic questioning guides your thinking |
| Knowledge learned gets forgotten | Personal knowledge base you can search and review |

## Features

### Comment-Based Interaction
```go
// Q: What's the difference between goroutine and thread?
// Press <leader>ma - Get explanation right in your editor

// S: Why might a mutex be better than a channel here?
// - AI asks guiding questions instead of giving direct answers

// R: Review this function for production readiness
// - Detailed code review with security, performance, best practices

// D: This function sometimes returns nil, help me debug
// - Guided debugging process, teaching you to find issues

// E: Explain the ownership system in Rust
// - Deep dive into concepts with examples
```

### 5 Learning Modes

| Mode | Prefix | Purpose |
|------|--------|---------|
| **Question** | `// Q:` | Direct answers with explanations |
| **Socratic** | `// S:` | Guided discovery through questions |
| **Review** | `// R:` | Code review and best practices |
| **Debug** | `// D:` | Learn debugging methodology |
| **Explain** | `// E:` | Deep concept explanations |

### Incremental Hints
- Ask once - subtle hint
- Ask again - clearer hint
- Ask third time - partial solution
- Ask fourth time - full solution with explanation

### Codebase-Aware (RAG)
```javascript
// Q: Where is authentication handled in this project?
// - AI searches your entire codebase and explains the auth flow
```

### Knowledge Tracking
- Every Q&A saved automatically
- Search your learning history
- Export to Markdown for review
- Track your learning progress

## Installation

### lazy.nvim
```lua
{
  "your-username/ai-code-mentor",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    require("codementor").setup({
      provider = "claude",  -- or "openai", "ollama"
      api_key = os.getenv("ANTHROPIC_API_KEY"),
    })
  end,
}
```

### Python CLI (for RAG features)
```bash
pip install codementor-cli

# Index your codebase
codementor-cli index /path/to/your/project
```

## Quick Start

1. **Install the plugin** (see above)

2. **Set your API key**
   ```bash
   export ANTHROPIC_API_KEY="your-key-here"
   ```

3. **Open any code file and ask a question**
   ```python
   # Q: What does this regex do?
   pattern = r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$'
   ```

4. **Press `<leader>ma`** - See the explanation in a floating window

## Keybindings

| Key | Action |
|-----|--------|
| `<leader>ma` | Mentor Ask - trigger on current comment |
| `<leader>mq` | Quick question mode |
| `<leader>ms` | Socratic mode |
| `<leader>mr` | Review current function |
| `<leader>md` | Debug assistance |
| `<leader>me` | Explain concept |
| `<leader>mk` | Search knowledge base |
| `<leader>mx` | Export knowledge to Markdown |

## Configuration

```lua
require("codementor").setup({
  -- LLM Provider
  provider = "claude",  -- "claude" | "openai" | "ollama"
  api_key = os.getenv("ANTHROPIC_API_KEY"),
  model = "claude-sonnet-4-20250514",

  -- Behavior
  default_mode = "question",  -- Default interaction mode
  hint_levels = 4,            -- Number of hint increments

  -- Context
  context_lines = 50,         -- Lines of context around question
  include_imports = true,     -- Include file imports in context

  -- RAG (requires codementor-cli)
  rag = {
    enabled = false,          -- Enable codebase-wide search
    db_path = "~/.codementor/vectors",
    top_k = 5,                -- Number of relevant chunks
  },

  -- Knowledge Tracking
  knowledge = {
    enabled = true,
    db_path = "~/.codementor/knowledge.db",
    auto_save = true,
  },

  -- UI
  ui = {
    width = 80,
    height = 20,
    border = "rounded",
  },

  -- Keymaps
  keymaps = {
    ask = "<leader>ma",
    close = "q",
    copy = "y",
    next_hint = "n",
  },
})
```

## How It Works

```
+-----------------------------------------------------------+
|  You write: // Q: How does this sorting algorithm work?   |
+-----------------------------+-----------------------------+
                              |
                              v
+-----------------------------------------------------------+
|  1. Parse comment (detect Q/S/R/D/E mode)                 |
|  2. Extract context (surrounding code via Tree-sitter)    |
|  3. [Optional] RAG search for related code                |
|  4. Build pedagogical prompt                              |
|  5. Send to LLM (Claude/OpenAI/Ollama)                    |
|  6. Render response in floating window                    |
|  7. Save to knowledge base                                |
+-----------------------------------------------------------+
```

## Project Structure

```
ai-tutor/
├── lua/codementor/           # Neovim plugin (Lua)
├── python/codementor_cli/    # RAG CLI (Python)
├── research/                 # Reference implementations
│   ├── core/                 # gp.nvim, wtf.nvim, etc.
│   ├── rag/                  # VectorCode, continue, etc.
│   ├── chunking/             # astchunk, code-chunk
│   ├── ui/                   # nui.nvim, render-markdown
│   ├── backend/              # lsp-ai, lancedb
│   ├── reference/            # AiComments, vscode samples
│   └── tools/                # ast-grep
├── README.md
└── CLAUDE.md                 # Development guide
```

## Comparison with Other Tools

| Feature | Copilot | ChatGPT | AI Code Mentor |
|---------|---------|---------|----------------|
| Code generation | Yes | Yes | No (by design) |
| In-editor | Yes | No | Yes |
| Teaches concepts | No | Partially | Yes (primary goal) |
| Socratic mode | No | No | Yes |
| Code review | No | Manual | Yes (`// R:`) |
| Knowledge tracking | No | No | Yes |
| Codebase-aware | Limited | No | Yes (RAG) |
| Open source | No | No | Yes |

## Use Cases

### Learning a New Language
```rust
// Q: Why does Rust require explicit lifetime annotations here?
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() { x } else { y }
}
// - Get explanation of ownership, borrowing, and lifetimes
```

### Understanding Legacy Code
```python
# E: Explain what this complex regex does step by step
pattern = r'(?P<protocol>https?):\/\/(?P<domain>[^\/]+)(?P<path>\/.*)?'
# - Detailed breakdown of each component
```

### Code Review Before PR
```typescript
// R: Review this function before I submit the PR
async function fetchUserData(userId: string) {
  const response = await fetch(`/api/users/${userId}`);
  return response.json();
}
// - Security issues, error handling, type safety feedback
```

### Debugging
```go
// D: This goroutine sometimes deadlocks, help me understand why
func process(ch chan int) {
    for {
        val := <-ch
        // process val
    }
}
// - Guided questions to help you discover the issue
```

## Roadmap

- [x] Project setup and architecture
- [x] Research reference implementations
- [ ] **Phase 1: MVP**
  - [ ] Comment parsing
  - [ ] Basic context collection
  - [ ] Claude API integration
  - [ ] Floating window UI
- [ ] **Phase 2: Multi-Mode**
  - [ ] 5 interaction modes
  - [ ] Incremental hints
  - [ ] Knowledge tracking
- [ ] **Phase 3: RAG**
  - [ ] Codebase indexing CLI
  - [ ] Hybrid search
  - [ ] Two-stage retrieval
- [ ] **Phase 4: Polish**
  - [ ] Obsidian integration
  - [ ] Team knowledge sharing
  - [ ] Vietnamese language support

## Contributing

Contributions are welcome! Please read our contributing guidelines first.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Built with inspiration from:
- [wtf.nvim](https://github.com/piersolenski/wtf.nvim) - Explanation-first architecture
- [gp.nvim](https://github.com/Robitx/gp.nvim) - Popup and streaming patterns
- [VectorCode](https://github.com/Davidyz/VectorCode) - Neovim RAG integration
- [CS50.ai](https://cs50.ai/) - Pedagogical AI design principles
- [Continue.dev](https://github.com/continuedev/continue) - Enterprise RAG patterns

---

**Remember**: The goal isn't to code faster. It's to become a better developer.
