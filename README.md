# ai-editutor

**Build projects. Ask questions. Level up.**

A Neovim plugin for developers who learn by building.

## Why

You're building something real. Not a tutorial. Not a toy project. Something you actually care about.

And you have questions. Small ones, big ones, weird ones. *"What's a closure again?" "Why is this nil?" "How do I handle this edge case?"*

You could switch to ChatGPT. Open a browser. Lose your flow. Copy context back and forth. Or scroll through Stack Overflow answers from 2015.

Or you could just ask. Right here. Right now. In your code.

```javascript
// Press <leader>mq to spawn a question block
/* [Q:q_1737200000000]
What is closure?
[PENDING:q_1737200000000]
*/
```

Press `<leader>ma`. Get an answer. Keep building.

**That's it.** No context switching. No copy-pasting. No breaking flow.

## The Philosophy

This is not a code generator. This is not about shipping faster.

This is about the moments when you're building something and you think *"wait, I should probably understand this better"* - and then you actually do, instead of just moving on.

**Learn while you build. Understand while you ship.**

Every question you ask is a chance to level up. Every answer stays in your codebase as a note to your future self.

## v3.0 - Question Blocks

Explicit question blocks with unique IDs. Reliable parsing. Batch processing.

```javascript
// 1. Press <leader>mq to spawn a question block
/* [Q:q_1737200000000]
What is closure and when should I use it?
[PENDING:q_1737200000000]
*/

// 2. Press <leader>ma to get answer
/* [Q:q_1737200000000]
What is closure and when should I use it?

A closure is a function that captures variables from its surrounding scope.
When the inner function is returned, it maintains access to those variables
even after the outer function has finished executing.

Use closures for:
- Data privacy (private variables)
- Factory functions
- Callbacks and event handlers

Watch out for memory leaks if closures hold references to large objects.
*/
```

### Key Features

- **Spawn question block** - `<leader>mq` creates a block with unique ID
- **Visual selection support** - Select code, then `<leader>mq` to ask about it
- **Batch processing** - Multiple `[PENDING]` questions answered in one request
- **Reliable parsing** - Marker-based response format, no JSON issues

### Visual Selection

Select code, press `<leader>mq`:

```javascript
// Select this function, press <leader>mq:
function processData(items) {
  return items.filter(x => x.active).map(x => x.value);
}

// Question block created with your selection:
/* [Q:q_1737200000000]
Regarding this code:
```
function processData(items) {
  return items.filter(x => x.active).map(x => x.value);
}
```

Why use filter before map here?
[PENDING:q_1737200000000]
*/
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
      provider = "claude",  -- or openai, deepseek, gemini, ollama
    })
  end,
}
```

**2. Set your API key**

```bash
export ANTHROPIC_API_KEY="your-key"
```

**3. Spawn a question block**

Press `<leader>mq` anywhere in your code. A question block appears:

```javascript
/* [Q:q_1737200000000]

[PENDING:q_1737200000000]
*/
```

Type your question, exit insert mode.

**4. Press `<leader>ma`**

Answer replaces the `[PENDING]` marker. You keep coding. You keep learning.

## Features

### Question Blocks
Explicit `[Q:id]` and `[PENDING:id]` markers:
- Unique timestamp-based IDs (no conflicts)
- Clear visual structure
- Easy to search and manage

### Batch Processing
Multiple pending questions answered in one request:
```javascript
/* [Q:q_1737200000000]
What is closure?
[PENDING:q_1737200000000]
*/

/* [Q:q_1737200001000]
How does async work?
[PENDING:q_1737200001000]
*/

// Press <leader>ma once -> both answered
```

### Context-Aware
Your questions get answered with full project context:
- Small projects (<20K tokens): Entire codebase included
- Large projects: Current file + imports + LSP definitions

### Visual Selection
Select confusing code, press `<leader>mq`:
- Selected code is quoted in the question block
- Type your question about the specific code
- AI focuses on your selection

### Knowledge That Stays
Every Q&A is saved by date. Review your learning history:
```vim
:EditutorHistory           " Recent Q&A
:EditutorBrowse            " Browse by date
:EditutorExport            " Export to markdown
```

## Configuration

```lua
require("editutor").setup({
  provider = "claude",           -- claude, openai, deepseek, gemini, groq, ollama
  model = "claude-sonnet-4-20250514",
  language = "English",          -- or "Vietnamese"

  context = {
    token_budget = 20000,
  },

  keymaps = {
    question = "<leader>mq",     -- Spawn question block
    ask = "<leader>ma",          -- Process pending questions
  },
})
```

## Providers

| Provider | Environment Variable |
|----------|---------------------|
| Claude | `ANTHROPIC_API_KEY` |
| OpenAI | `OPENAI_API_KEY` |
| Gemini | `GEMINI_API_KEY` |
| DeepSeek | `DEEPSEEK_API_KEY` |
| Groq | `GROQ_API_KEY` |
| Together | `TOGETHER_API_KEY` |
| OpenRouter | `OPENROUTER_API_KEY` |
| Ollama | Local, no key needed |

## Commands

| Command | What it does |
|---------|-------------|
| `:EditutorQuestion` | Spawn a new question block |
| `:EditutorAsk` | Process all pending questions |
| `:EditutorPending` | Show pending question count |
| `:EditutorHistory` | Recent Q&A history |
| `:EditutorBrowse` | Browse by date |
| `:EditutorExport` | Export to markdown |
| `:EditutorLang` | Switch language |
| `:EditutorClearCache` | Clear context cache |

## Keymaps

| Keymap | Mode | What it does |
|--------|------|-------------|
| `<leader>mq` | Normal | Spawn question block at cursor |
| `<leader>mq` | Visual | Spawn question block with selected code |
| `<leader>ma` | Normal | Process all pending questions |

---

**Stop context-switching. Start understanding.**

The best way to learn programming is to build things. This plugin makes sure you actually learn while you build.
