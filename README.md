# ai-editutor

**Build projects. Ask questions. Level up.**

A Neovim plugin for developers who learn by building.

## The Problem

You're deep in your codebase. You hit a function you don't fully understand. You want to know:

- *"What exactly does this function do?"*
- *"Is there a library that handles this better?"*
- *"What's the best practice for error handling here?"*
- *"Why is this returning nil?"*

You could open ChatGPT. Copy your code. Paste it. Explain your project structure. Copy more context. Paste again. Get a generic answer that doesn't fit your codebase.

**Or you could just ask. Right here. In your code. With full context.**

## The Solution

```python
# You're looking at this function, confused:
def process_user_data(data, config):
    normalized = {k.lower(): v for k, v in data.items() if v is not None}
    return {**config.get("defaults", {}), **normalized}

# Press <leader>mq, type your question:
# [Q:q_1737200000000]
# What does this function do? Is the order of merging correct?
# What happens if config doesn't have "defaults" key?
# [PENDING:q_1737200000000]
```

Press `<leader>ma`. AI sees your code, your imports, your project structure. Answers with full context:

```python
# [Q:q_1737200000000]
# What does this function do? Is the order of merging correct?
# What happens if config doesn't have "defaults" key?
#
# This function:
# 1. Filters out None values and lowercases keys from input data
# 2. Merges with defaults from config (defaults first, then normalized overrides)
#
# The merge order is correct - user data overwrites defaults.
#
# If "defaults" key missing: config.get("defaults", {}) returns empty dict,
# so it just returns normalized data. Safe, no KeyError.
#
# Consider adding type hints for clarity:
# def process_user_data(data: dict[str, Any], config: dict) -> dict:
```

**Read it. Understand it. Delete the block. Keep coding.**

## Why This Works

### Context is Everything

ChatGPT doesn't know your codebase. You have to explain everything.

ai-editutor **automatically gathers context**:
- Full current file
- Files you import (and files that import you)
- Type definitions via LSP
- Project structure

When you ask "is this the right approach?", AI actually sees what approach you're using.

### Stay in Flow

No browser tabs. No copy-paste. No context switching.

```
Ask → Read → Understand → Delete → Keep building
```

The question block is temporary. It's a learning moment, not permanent documentation.

### Real Questions, Real Answers

Not "explain closures". But:

```javascript
/* [Q:q_...]
This useEffect runs on every render. How do I make it run only once?
And should I use useCallback for the handleSubmit inside?
[PENDING:q_...]
*/
useEffect(() => {
  fetchUserData();
}, []);

const handleSubmit = () => {
  // ...
};
```

```go
/* [Q:q_...]
Is there a stdlib function that does this? Or should I use a library?
What's idiomatic Go for this pattern?
[PENDING:q_...]
*/
func contains(slice []string, item string) bool {
    for _, v := range slice {
        if v == item {
            return true
        }
    }
    return false
}
```

```rust
/* [Q:q_...]
When should I use &str vs String here?
This function is called frequently, does it matter for performance?
[PENDING:q_...]
*/
fn process_name(name: String) -> String {
    name.trim().to_lowercase()
}
```

## Quick Start

**1. Install**

```lua
-- lazy.nvim
{
  "iknizzz1807/ai-editutor",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("editutor").setup({
      provider = "deepseek",  -- or claude, openai, gemini, ollama
    })
  end,
}
```

**2. Set your API key**

```bash
export DEEPSEEK_API_KEY="your-key"
# or ANTHROPIC_API_KEY, OPENAI_API_KEY, etc.
```

**3. Ask a question**

1. Navigate to code you want to understand
2. Press `<leader>mq` - question block appears
3. Type your question
4. Press `<Esc>`, then `<leader>ma`
5. Read the answer, delete the block, keep building

## Visual Selection

Select confusing code first, then press `<leader>mq`:

```typescript
// Select these lines, press <leader>mq:
const result = data
  .filter(x => x.status === 'active')
  .reduce((acc, item) => ({
    ...acc,
    [item.id]: item.value * multiplier
  }), {});

// Question block created with your selection quoted:
/* [Q:q_1737200000000]
Regarding this code:
```
const result = data
  .filter(x => x.status === 'active')
  .reduce((acc, item) => ({
    ...acc,
    [item.id]: item.value * multiplier
  }), {});
```

Can this be simplified? Is reduce the right choice here?
What if data is empty?
[PENDING:q_1737200000000]
*/
```

## Batch Questions

Multiple questions? Ask them all, process once:

```python
# [Q:q_1737200000000]
# What does this decorator do?
# [PENDING:q_1737200000000]

@lru_cache(maxsize=128)
def expensive_calculation(n):
    # ...

# [Q:q_1737200001000]
# Should I use lru_cache or functools.cache here?
# [PENDING:q_1737200001000]
```

Press `<leader>ma` once. Both answered.

## Configuration

```lua
require("editutor").setup({
  provider = "deepseek",
  model = "deepseek-chat",
  language = "Vietnamese",  -- or "English"

  keymaps = {
    question = "<leader>mq",
    ask = "<leader>ma",
  },

  context = {
    token_budget = 20000,
  },
})
```

## Providers

| Provider | Environment Variable | Notes |
|----------|---------------------|-------|
| DeepSeek | `DEEPSEEK_API_KEY` | Cheap, good for code |
| Claude | `ANTHROPIC_API_KEY` | Best quality |
| OpenAI | `OPENAI_API_KEY` | GPT-4o |
| Gemini | `GEMINI_API_KEY` | Google |
| Groq | `GROQ_API_KEY` | Fast inference |
| Ollama | - | Local, free |

## Commands

| Command | Description |
|---------|-------------|
| `:EditutorQuestion` | Spawn question block |
| `:EditutorAsk` | Process pending questions |
| `:EditutorPending` | Count pending questions |
| `:EditutorHistory` | View Q&A history |
| `:EditutorBrowse` | Browse by date |
| `:EditutorExport` | Export to markdown |
| `:EditutorLang` | Switch language |

## Knowledge Tracking

Every Q&A is saved. Review what you've learned:

```vim
:EditutorHistory    " Recent questions
:EditutorBrowse     " Browse by date
:EditutorExport     " Export to markdown for notes
```

Your learning history, searchable and exportable.

---

## Philosophy

This is not a code generator. This is not about shipping faster.

This is for the moments when you think *"I should understand this better"* - and then you actually do.

**Learn while you build. Understand while you ship.**

---

**Stop copy-pasting to ChatGPT. Start asking in context.**
