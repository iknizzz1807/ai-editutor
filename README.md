# ai-editutor

> **"GitHub Copilot writes code for you. ai-editutor teaches you to write better code."**

A Neovim plugin that acts as your personal coding mentor - explaining concepts, guiding your thinking, and helping you truly understand code rather than just generating it.

## What's New in v0.9.0

**Intelligent Context System** - Major upgrade to how ai-editutor understands your code:

- **BM25 Search** via SQLite FTS5 - Find related code across your project
- **Multi-Signal Ranking** - 8 signals combine for precise context selection
- **5-Level Hints** - More granular progressive hints system
- **More Providers** - DeepSeek, Groq, Together, OpenRouter built-in
- **Streaming Improvements** - Debounced UI updates for smoother experience
- **Context Caching** - Smart caching with automatic invalidation

## What's New in v0.8.0

**Inline Comments UI** - Responses are now inserted directly as comments in your code file, right below your question. No floating windows - everything stays in your code.

```go
// Q: What's the difference between goroutine and thread?
/*
A: A goroutine is a lightweight thread managed by the Go runtime,
not the OS. Key differences:

1. Memory: goroutines start with ~2KB stack vs ~1MB for OS threads
2. Scheduling: Go runtime schedules goroutines (M:N model)
3. Communication: Use channels instead of shared memory

Example:
go func() {
    // This runs concurrently
}()

Learn more: Look into Go's scheduler and the GOMAXPROCS setting.
*/
func main() {
    // your code here
}
```

## Why ai-editutor?

| Problem | Solution |
|---------|----------|
| Copilot generates code - you just accept - you don't learn | AI explains - you write every line - you actually learn |
| Context switching to browser for docs | Ask questions directly in your editor |
| ChatGPT gives answers without teaching | Socratic questioning guides your thinking |
| Knowledge learned gets forgotten | Personal knowledge base you can search and review |

## Features

### Comment-Based Interaction (Inline Responses)

```javascript
// Q: What does this regex do?
/*
A: This regex validates a strong password:
- (?=.*[A-Z]) - at least one uppercase
- (?=.*[a-z]) - at least one lowercase
- (?=.*\d) - at least one digit
- .{8,} - minimum 8 characters

Common mistake: Forgetting anchors (^$) allows partial matches.
*/
const pattern = /^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$/;
```

### 5 Learning Modes

| Mode | Prefix | Purpose |
|------|--------|---------|
| **Question** | `// Q:` | Direct answers with explanations |
| **Socratic** | `// S:` | Guided discovery through questions |
| **Review** | `// R:` | Code review and best practices |
| **Debug** | `// D:` | Learn debugging methodology |
| **Explain** | `// E:` | Deep concept explanations |

### 5-Level Progressive Hints (v0.9.0)

Run `:EduTutorHint` multiple times on the same question:
- Level 1: **Conceptual** - What concepts are relevant?
- Level 2: **Strategic** - What approach to consider?
- Level 3: **Directional** - Where in the code to look?
- Level 4: **Specific** - What techniques to try?
- Level 5: **Solution** - Complete answer with explanation

### LSP-Powered Context

```typescript
// Q: How does this service interact with the authentication module?
// ai-editutor automatically gathers context from related project files via LSP
// No indexing required - just works with your existing LSP setup
```

### Conversation Memory

Ask follow-up questions without repeating context:
```python
# Q: What does this function do?
# A: [explanation inserted as comment]

# Q: Can you elaborate on the error handling?
# A: [AI remembers previous discussion, continues naturally]
```

### Multi-Language Support

```vim
:EduTutorLang Vietnamese  " Switch to Vietnamese responses
:EduTutorLang English     " Switch to English responses
```

## Installation

### Requirements

| Dependency | Required? | Purpose |
|------------|-----------|---------|
| `nvim-lua/plenary.nvim` | **Required** | HTTP requests, async utilities |
| `nvim-treesitter/nvim-treesitter` | Recommended | Better code chunking |
| `kkharji/sqlite.lua` | Recommended | BM25 search, project indexing |

**Without sqlite.lua**: Plugin works with LSP-only context (still very capable)
**With sqlite.lua**: Enables BM25 full-text search across entire project

### lazy.nvim (Recommended)
```lua
{
  "your-username/ai-editutor",
  dependencies = {
    "nvim-lua/plenary.nvim",           -- Required
    "nvim-treesitter/nvim-treesitter", -- Recommended
    "kkharji/sqlite.lua",              -- Recommended: enables BM25 search
  },
  config = function()
    require("editutor").setup({
      provider = "claude",  -- claude, openai, deepseek, groq, together, openrouter, ollama
    })
  end,
}
```

### packer.nvim
```lua
use {
  "your-username/ai-editutor",
  requires = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "kkharji/sqlite.lua",
  },
  config = function()
    require("editutor").setup({
      provider = "claude",
    })
  end,
}
```

### vim-plug
```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'kkharji/sqlite.lua'
Plug 'your-username/ai-editutor'
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

4. **Press `<leader>ma`** - The explanation is inserted as a comment below your question

## Keybindings

| Key | Action |
|-----|--------|
| `<leader>ma` | Ask - response inserted as inline comment |

## Configuration

```lua
require("editutor").setup({
  -- LLM Provider (v0.9.0: more options)
  provider = "claude",  -- claude, openai, deepseek, groq, together, openrouter, ollama
  api_key = os.getenv("ANTHROPIC_API_KEY"),
  model = "claude-sonnet-4-20250514",

  -- Behavior
  default_mode = "question",
  language = "English",       -- or "Vietnamese"

  -- LSP Context Extraction
  context = {
    lines_around_cursor = 100,
    external_context_lines = 30,
    max_external_symbols = 20,
  },

  -- Indexer Settings (v0.9.0)
  indexer = {
    context_budget = 4000,      -- Total tokens for context
    debounce_ms = 1000,         -- File change debounce
    weights = {                 -- Ranking signal weights
      lsp_definition = 1.0,
      bm25_score = 0.5,
      directory_proximity = 0.3,
      git_recency = 0.2,
    },
  },

  -- Keymaps
  keymaps = {
    ask = "<leader>ma",
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
|  4. Build pedagogical prompt with full context            |
|  5. Send to LLM (Claude/OpenAI/Ollama)                    |
|  6. Insert response as comment below question             |
|  7. Save to knowledge base                                |
+-----------------------------------------------------------+
```

### Comment Style Detection

The plugin automatically uses the appropriate comment style:

| Languages | Comment Style |
|-----------|---------------|
| JS/TS/Go/Rust/C/C++/Java | `/* block comment */` |
| Python | `""" docstring """` |
| Lua/SQL | `--[[ block ]]` |
| HTML/XML | `<!-- comment -->` |
| Shell/YAML | `# line comment` |

## Commands

### Core Commands
| Command | Description |
|---------|-------------|
| `:EduTutorAsk` | Ask about current mentor comment |
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

### Indexer Commands (v0.9.0)
| Command | Description |
|---------|-------------|
| `:EduTutorIndex` | Index current project for BM25 search |
| `:EduTutorIndexStats` | Show indexer statistics |
| `:EduTutorClearCache` | Clear context cache |

### Other Commands
| Command | Description |
|---------|-------------|
| `:EduTutorLang` | Show/set response language |
| `:EduTutorConversation` | Show conversation info |
| `:EduTutorClearConversation` | Clear conversation |
| `:checkhealth editutor` | Check plugin health |

## Use Cases

### Learning a New Language
```rust
// Q: Why does Rust require explicit lifetime annotations here?
/*
A: Rust needs lifetimes to ensure the returned reference
is valid. Here, both inputs could have different lifetimes,
so you must specify which one the return value follows.

The 'a annotation says: "the return value lives as long as
the shorter of x and y's lifetimes."

Without this, Rust can't guarantee memory safety at compile time.
*/
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() { x } else { y }
}
```

### Code Review Before PR
```typescript
// R: Review this function before I submit the PR
/*
A: Issues found:

CRITICAL: No input validation - userId could be used for injection
WARNING: No error handling for failed fetch
WARNING: response.json() can throw if response isn't JSON

Improved version:
async function fetchUserData(userId: string) {
  if (!userId || typeof userId !== 'string') {
    throw new Error('Invalid userId');
  }
  const response = await fetch(`/api/users/${encodeURIComponent(userId)}`);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  return response.json();
}
*/
async function fetchUserData(userId: string) {
  const response = await fetch(`/api/users/${userId}`);
  return response.json();
}
```

## Comparison with Other Tools

| Feature | Copilot | ChatGPT | ai-editutor |
|---------|---------|---------|-------------|
| Code generation | Yes | Yes | No (by design) |
| In-editor | Yes | No | Yes |
| Teaches concepts | No | Partially | Yes (primary goal) |
| Inline responses | No | No | Yes |
| Socratic mode | No | No | Yes |
| Knowledge tracking | No | No | Yes |
| Project-aware context | Limited | No | Yes (LSP-based) |

## Project Structure

```
ai-editutor/
├── lua/editutor/
│   ├── init.lua              # Plugin entry (v0.9.0)
│   ├── comment_writer.lua    # Inline comment insertion
│   ├── parser.lua            # Comment parsing
│   ├── context.lua           # Context extraction
│   ├── lsp_context.lua       # LSP-based context
│   ├── prompts.lua           # Pedagogical prompts (bilingual)
│   ├── provider.lua          # LLM providers with inheritance
│   ├── hints.lua             # 5-level progressive hints
│   ├── knowledge.lua         # Q&A persistence
│   ├── conversation.lua      # Conversation memory
│   ├── cache.lua             # LRU cache with TTL (v0.9.0)
│   ├── health.lua            # Health check
│   └── indexer/              # Project indexing (v0.9.0)
│       ├── init.lua          # Indexer entry point
│       ├── db.lua            # SQLite + FTS5 (BM25)
│       ├── chunker.lua       # Tree-sitter AST chunking
│       └── ranker.lua        # Multi-signal ranking
├── doc/editutor.txt          # Vim help
├── README.md
└── CLAUDE.md                 # Development guide
```

## Roadmap

- [x] **v0.6.0**: LSP-based context extraction
- [x] **v0.7.0**: Conversation memory
- [x] **v0.8.0**: Inline comments UI
- [x] **v0.9.0**: Intelligent context system (BM25, multi-signal ranking)
- [ ] **Future**: Obsidian integration, Team sharing, Semantic embeddings

## Contributing

Contributions are welcome! Please read CLAUDE.md for development guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**Remember**: The goal isn't to code faster. It's to become a better developer.
