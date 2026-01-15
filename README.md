# ai-editutor

> **"GitHub Copilot writes code for you. ai-editutor teaches you to write better code."**

A Neovim plugin that acts as your personal coding mentor - explaining concepts, guiding your thinking, and helping you truly understand code rather than just generating it.

## Why ai-editutor?

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

### LSP-Powered Context
```javascript
// Q: How does this service interact with the authentication module?
// - AI automatically gathers context from related project files via LSP
// - No indexing required - just works with your existing LSP setup
```

ai-editutor uses LSP go-to-definition to automatically find and include relevant code from your project files. It filters out library code and focuses only on YOUR code.

### Knowledge Tracking
- Every Q&A saved automatically
- Search your learning history
- Export to Markdown for review
- Track your learning progress

### Multi-Language Support
```vim
:EduTutorLang Vietnamese  " Switch to Vietnamese responses
:EduTutorLang English     " Switch to English responses
```

## Installation

### lazy.nvim
```lua
{
  "your-username/ai-editutor",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",  -- Recommended for better context
  },
  config = function()
    require("editutor").setup({
      provider = "claude",  -- or "openai", "ollama"
      api_key = os.getenv("ANTHROPIC_API_KEY"),
    })
  end,
}
```

### Optional Dependencies
```lua
dependencies = {
  "nvim-lua/plenary.nvim",          -- Required: HTTP requests
  "nvim-treesitter/nvim-treesitter", -- Recommended: Better context extraction
  "MunifTanjim/nui.nvim",           -- Optional: Enhanced UI
  "kkharji/sqlite.lua",             -- Optional: Better knowledge storage
}
```

## Quick Start

1. **Install the plugin** (see above)

2. **Set your API key**
   ```bash
   export ANTHROPIC_API_KEY="your-key-here"
   ```

3. **Ensure LSP is configured** for your language (for best context extraction)
   ```vim
   :LspInfo  " Check LSP status
   ```

4. **Open any code file and ask a question**
   ```python
   # Q: What does this regex do?
   pattern = r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$'
   ```

5. **Press `<leader>ma`** - See the explanation in a floating window

## Keybindings

| Key | Action |
|-----|--------|
| `<leader>ma` | Mentor Ask - trigger on current comment |
| `<leader>ms` | Mentor Stream - streaming response |
| `q` | Close popup |
| `y` | Copy answer to clipboard |
| `n` | Next hint (in hint mode) |

## Configuration

```lua
require("editutor").setup({
  -- LLM Provider
  provider = "claude",  -- "claude" | "openai" | "ollama"
  api_key = os.getenv("ANTHROPIC_API_KEY"),
  model = "claude-sonnet-4-20250514",

  -- Behavior
  default_mode = "question",  -- Default interaction mode
  language = "English",       -- or "Vietnamese"

  -- LSP Context Extraction
  context = {
    lines_around_cursor = 100,    -- Lines around cursor (50 above + 50 below)
    external_context_lines = 30,  -- Lines around each external definition
    max_external_symbols = 20,    -- Max external symbols to resolve via LSP
  },

  -- UI
  ui = {
    width = 80,
    height = 20,
    border = "rounded",
    max_width = 120,
  },

  -- Keymaps
  keymaps = {
    ask = "<leader>ma",
    stream = "<leader>ms",
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
|  2. Extract code context around cursor                    |
|  3. Use LSP to find related definitions in project        |
|  4. Filter out library code (node_modules, etc.)          |
|  5. Build pedagogical prompt with full context            |
|  6. Send to LLM (Claude/OpenAI/Ollama)                    |
|  7. Stream response to floating window                    |
|  8. Save to knowledge base                                |
+-----------------------------------------------------------+
```

### LSP Context Flow

```
Current File                    External Definitions
+-------------------+          +------------------------+
| // Q: question    |   LSP    | auth_service.ts        |
| import { auth }   | -------> | export function login  |
| auth.login()      |  go-to-  +------------------------+
+-------------------+   def    | user_repository.py     |
                               | class UserRepository   |
                               +------------------------+
```

ai-editutor finds symbols in your code and uses LSP to locate their definitions in OTHER project files. This gives the LLM context about how your code connects together.

## Project Structure

```
ai-editutor/
├── lua/editutor/           # Neovim plugin (Lua)
│   ├── init.lua            # Plugin entry point (v0.6.0)
│   ├── config.lua          # Configuration management
│   ├── parser.lua          # Comment parsing (// Q:, etc.)
│   ├── context.lua         # Context extraction (Tree-sitter)
│   ├── lsp_context.lua     # LSP-based context (go-to-def)
│   ├── prompts.lua         # Pedagogical prompt templates
│   ├── provider.lua        # LLM providers + streaming
│   ├── ui.lua              # Floating window UI
│   ├── hints.lua           # Incremental hints (4 levels)
│   ├── knowledge.lua       # Q&A persistence
│   └── health.lua          # :checkhealth editutor
├── plugin/
│   └── editutor.lua        # Lazy loading entry
├── doc/
│   └── editutor.txt        # Vim help documentation
├── tests/                  # Test suite
│   ├── fixtures/           # Multi-language test projects
│   └── manual_lsp_test.lua # Manual LSP verification
├── README.md
└── CLAUDE.md               # Development guide
```

## Comparison with Other Tools

| Feature | Copilot | ChatGPT | ai-editutor |
|---------|---------|---------|-------------|
| Code generation | Yes | Yes | No (by design) |
| In-editor | Yes | No | Yes |
| Teaches concepts | No | Partially | Yes (primary goal) |
| Socratic mode | No | No | Yes |
| Code review | No | Manual | Yes (`// R:`) |
| Knowledge tracking | No | No | Yes |
| Project-aware context | Limited | No | Yes (LSP-based) |
| No external indexing | N/A | N/A | Yes (uses LSP) |
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

## Commands

### Core Commands
| Command | Description |
|---------|-------------|
| `:EduTutorAsk` | Ask about current mentor comment |
| `:EduTutorStream` | Ask with streaming response |
| `:EduTutorHint` | Ask with incremental hints |
| `:EduTutorModes` | Show available modes |

### Mode Commands
| Command | Description |
|---------|-------------|
| `:EduTutorQuestion` | Force Question mode |
| `:EduTutorSocratic` | Force Socratic mode |
| `:EduTutorReview` | Force Review mode |
| `:EduTutorDebug` | Force Debug mode |
| `:EduTutorExplain` | Force Explain mode |

### Knowledge Commands
| Command | Description |
|---------|-------------|
| `:EduTutorHistory` | Show Q&A history |
| `:EduTutorSearch [query]` | Search knowledge base |
| `:EduTutorExport [path]` | Export to markdown |
| `:EduTutorStats` | Show statistics |

### Language Commands
| Command | Description |
|---------|-------------|
| `:EduTutorLang` | Show current language |
| `:EduTutorLang Vietnamese` | Switch to Vietnamese |
| `:EduTutorLang English` | Switch to English |

## Health Check

Verify your setup:
```vim
:checkhealth editutor
```

This checks:
- Neovim version
- Required dependencies (plenary.nvim)
- Optional dependencies (nui.nvim, sqlite.lua)
- Tree-sitter availability
- LSP availability for current buffer
- Provider configuration and API key

## Roadmap

- [x] **Phase 1: MVP**
  - [x] Comment parsing
  - [x] Basic context collection
  - [x] Claude API integration
  - [x] Floating window UI
- [x] **Phase 2: Multi-Mode**
  - [x] 5 interaction modes
  - [x] Incremental hints
  - [x] Knowledge tracking
- [x] **Phase 3: LSP Context**
  - [x] LSP-based context extraction
  - [x] Go-to-definition for external symbols
  - [x] Project file filtering
  - [x] Streaming responses
- [x] **Phase 4: Polish**
  - [x] Vietnamese language support
  - [x] Health check
  - [x] Knowledge export
- [ ] **Future**
  - [ ] Obsidian integration
  - [ ] Team knowledge sharing
  - [ ] Enhanced UI with nui.nvim

## Contributing

Contributions are welcome! Please read our contributing guidelines first.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Built with inspiration from:
- [wtf.nvim](https://github.com/piersolenski/wtf.nvim) - Explanation-first architecture
- [gp.nvim](https://github.com/Robitx/gp.nvim) - Popup and streaming patterns
- [CS50.ai](https://cs50.ai/) - Pedagogical AI design principles

---

**Remember**: The goal isn't to code faster. It's to become a better developer.
