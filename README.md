# ai-editutor

> **"GitHub Copilot writes code for you. ai-editutor teaches you to write better code."**

A Neovim plugin that acts as your personal coding mentor - explaining concepts, guiding your thinking, and helping you truly understand code rather than just generating it.

## What's New in v1.2.0

**Two Modes: Q: (Question) and C: (Code)**

**Q: Mode** - Ask questions, learn deeply ("ask one, learn ten"):
- `// Q: What is closure?` - Deep explanation with best practices
- `// Q: Review this code` - Constructive code review
- `// Q: Debug: why does this return nil?` - Guided debugging
- Response inserted as **comment block** with A: prefix

**C: Mode** - Generate code with explanatory notes:
- `// C: function to validate email` - Generates actual working code
- `// C: async fetch with retry logic` - Production-ready code
- Response inserted as **actual code** + notes block

**Key Features:**
- **Streaming** - See response as it's generated
- **Skip Answered** - Q:/C: with response below are automatically skipped
- **Visual Selection** - Select code, write Q:/C:, get focused response
- **Adaptive Context** - Full project (<20K tokens) or import graph + LSP

```javascript
// Q: What's the difference between let and const?
/*
A: Both are block-scoped, but:
- const: Cannot be reassigned (immutable binding)
- let: Can be reassigned

Best practice: Use const by default, let when you need to reassign.
Watch out: const objects can still have properties modified!
*/
const x = 5;
let y = 10;

// C: validate email with regex
function validateEmail(email) {
  const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return regex.test(email);
}
/*
Notes:
- This regex handles most common formats
- For strict validation, consider validator.js
- Edge cases: + aliases, unicode domains
*/
```

## Why ai-editutor?

| Problem | Solution |
|---------|----------|
| Copilot generates code - you just accept - you don't learn | AI explains - you write every line - you actually learn |
| Context switching to browser for docs | Ask questions directly in your editor |
| ChatGPT gives answers without teaching | Express your intent: "Socratic method", "Review", "Debug" |
| Knowledge learned gets forgotten | Personal knowledge base you can search and review |

## Features

### Simple Q: Syntax

Just write `// Q:` and ask anything:

```python
# Q: What does this regex do?
"""
A: This regex validates a strong password:
- (?=.*[A-Z]) - at least one uppercase
- (?=.*[a-z]) - at least one lowercase
- (?=.*\d) - at least one digit
- .{8,} - minimum 8 characters

Common mistake: Forgetting anchors (^$) allows partial matches.
"""
pattern = r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$'
```

### Express Your Intent Naturally

```javascript
// Q: Review this function for security issues
// Q: Debug: why does this return undefined sometimes?
// Q: Explain closures step by step
// Q: What could be improved here?
// Q: Help me understand this using Socratic method
```

### Skip Answered Questions

Questions with A: responses below are automatically skipped:

```javascript
function test() {
  // Q: What is closure?       // SKIPPED (already answered)
  /*
  A: A closure is a function...
  */

  // Q: How does async work?   // FOUND (unanswered)
  return 42;
}
```

### Visual Selection Support

1. Select code block with `v` or `V`
2. Write `// Q: Explain this function` within selection
3. Press `<leader>ma`
4. Selected code is sent with focus priority

### 5-Level Progressive Hints

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
| `nvim-treesitter/nvim-treesitter` | Recommended | Better code parsing |

### lazy.nvim (Recommended)
```lua
{
  "your-username/ai-editutor",
  dependencies = {
    "nvim-lua/plenary.nvim",           -- Required
    "nvim-treesitter/nvim-treesitter", -- Recommended
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
  },
  config = function()
    require("editutor").setup({
      provider = "claude",
    })
  end,
}
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

| Key | Mode | Action |
|-----|------|--------|
| `<leader>ma` | Normal | Ask about Q: at cursor |
| `<leader>ma` | Visual | Ask about selected code |

## Configuration

```lua
require("editutor").setup({
  -- LLM Provider
  provider = "claude",  -- claude, openai, deepseek, groq, together, openrouter, ollama
  api_key = os.getenv("ANTHROPIC_API_KEY"),
  model = "claude-sonnet-4-20250514",

  -- Behavior
  language = "English",       -- or "Vietnamese"

  -- Context Budget
  context = {
    token_budget = 20000,     -- Max tokens for context (default: 20000)
  },

  -- Keymaps
  keymaps = {
    ask = "<leader>ma",  -- Works in normal and visual mode
  },
})
```

## How It Works

```
+-----------------------------------------------------------+
|  You write: // Q: question   OR   // C: code description  |
+-----------------------------+-----------------------------+
                              |
                              v
+-----------------------------------------------------------+
|  1. Parse Q:/C: comment and detect mode                   |
|  2. Check if already answered → skip if yes               |
|  3. Extract context (full project or import graph + LSP)  |
|  4. Build mode-specific prompt                            |
|  5. Stream to LLM (Claude/OpenAI/DeepSeek/etc.)          |
|  6. Insert response based on mode:                        |
|     - Q: → comment block with A: prefix                   |
|     - C: → actual code + notes block                      |
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
| `:EduTutorAsk` | Ask about current Q: comment |
| `:EduTutorHint` | Ask with progressive hints (run multiple times) |

### Knowledge Commands
| Command | Description |
|---------|-------------|
| `:EduTutorHistory` | Show Q&A history |
| `:EduTutorSearch [query]` | Search knowledge base |
| `:EduTutorExport [path]` | Export to markdown |
| `:EduTutorStats` | Show statistics |

### Other Commands
| Command | Description |
|---------|-------------|
| `:EduTutorLang` | Show/set response language |
| `:EduTutorConversation` | Show conversation info |
| `:EduTutorClearConversation` | Clear conversation |
| `:EduTutorClearCache` | Clear context cache |
| `:EduTutorLog` | Open debug log |
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
*/
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() { x } else { y }
}
```

### Code Review
```typescript
// Q: Review this function for security issues
/*
A: Issues found:

CRITICAL: No input validation - userId could be used for injection
WARNING: No error handling for failed fetch
WARNING: response.json() can throw if response isn't JSON

Consider: Input validation, error handling, and encodeURIComponent.
*/
async function fetchUserData(userId: string) {
  const response = await fetch(`/api/users/${userId}`);
  return response.json();
}
```

### Debugging
```python
# Q: Debug: why does this return None sometimes?
"""
A: Possible causes:

1. The 'if' condition might not be met
2. No explicit return means implicit 'return None'
3. Check edge cases: empty input? zero values?

To debug: Add print statements before each return,
check what conditions are being met.
"""
def process(data):
    if data and data.get('value'):
        return data['value'] * 2
```

## Comparison with Other Tools

| Feature | Copilot | ChatGPT | ai-editutor |
|---------|---------|---------|-------------|
| Code generation | Auto | Yes | Yes (C: mode, intentional) |
| In-editor | Yes | No | Yes |
| Teaches concepts | No | Partially | Yes (Q: mode, primary goal) |
| Inline responses | No | No | Yes |
| Skip answered questions | No | No | Yes |
| Visual selection | No | No | Yes |
| Knowledge tracking | No | No | Yes |
| Project-aware context | Limited | No | Yes (import graph + LSP) |
| Streaming | Yes | Yes | Yes |

## Roadmap

- [x] **v0.6.0**: LSP-based context extraction
- [x] **v0.7.0**: Conversation memory
- [x] **v0.8.0**: Inline comments UI
- [x] **v0.9.0**: Intelligent context system (BM25, multi-signal ranking)
- [x] **v1.0.0**: Simplified Q: only mode, skip answered, visual selection
- [x] **v1.2.0**: C: code generation mode, streaming, adaptive context
- [ ] **Future**: Obsidian integration, Team sharing

## Contributing

Contributions are welcome! Please read CLAUDE.md for development guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**Remember**: The goal isn't to code faster. It's to become a better developer.
