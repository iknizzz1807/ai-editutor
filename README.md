# ai-editutor

**Build projects. Ask questions. Level up.**

A Neovim plugin for developers who learn by building.

## Why

You're building something real. Not a tutorial. Not a toy project. Something you actually care about.

And you have questions. Small ones, big ones, weird ones. *"What's a closure again?" "Why is this nil?" "How do I handle this edge case?"*

You could switch to ChatGPT. Open a browser. Lose your flow. Copy context back and forth. Or scroll through Stack Overflow answers from 2015.

Or you could just ask. Right here. Right now. In your code.

```javascript
// Q: What is closure?
```

Press `<leader>ma`. Get an answer. Keep building.

**That's it.** No context switching. No copy-pasting. No breaking flow.

## The Philosophy

This is not a code generator. This is not about shipping faster.

This is about the moments when you're building something and you think *"wait, I should probably understand this better"* - and then you actually do, instead of just moving on.

**Learn while you build. Understand while you ship.**

Every question you ask is a chance to level up. Every answer stays in your codebase as a note to your future self.

## Two Modes

### Q: Question - Learn deeply

Ask anything. Get explanations that stick.

```python
# Q: What does this regex actually do?
pattern = r'^(?=.*[A-Z])(?=.*\d).{8,}$'
#
# A: This regex validates password strength:
# - (?=.*[A-Z]) - requires at least one uppercase letter
# - (?=.*\d) - requires at least one digit
# - .{8,} - requires minimum 8 characters
#
# The ^ and $ anchors ensure the entire string is checked.
# Lookaheads (?=...) check conditions without consuming characters.
#
# Watch out: This won't catch weak passwords like "Aaaaaaaa1"
# Consider: Adding special character requirement, or use zxcvbn library
```

### C: Code - Generate with understanding

Need code? Get working code + notes on what matters.

```javascript
// C: debounce function with cancel
function debounce(fn, delay) {
  let timeoutId;
  
  const debounced = (...args) => {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn(...args), delay);
  };
  
  debounced.cancel = () => clearTimeout(timeoutId);
  return debounced;
}
/*
Notes:
- Returns a wrapper that delays execution until delay ms of inactivity
- .cancel() lets you abort pending calls (useful for cleanup)
- Consider: lodash.debounce for leading/trailing options
*/
```

## Quick Start

**1. Install**

```lua
-- lazy.nvim
{
  "your-username/ai-editutor",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("editutor").setup({
      provider = "claude",  -- or openai, deepseek, ollama
    })
  end,
}
```

**2. Set your API key**

```bash
export ANTHROPIC_API_KEY="your-key"
```

**3. Write a question in your code**

```javascript
// Q: Why would I use Map instead of a plain object?
```

**4. Press `<leader>ma`**

Answer appears as a comment. You keep coding. You keep learning.

## Features

### Context-Aware
Your questions get answered with full project context:
- Small projects (<20K tokens): Entire codebase included
- Large projects: Current file + imports + related definitions

### Visual Selection
Select confusing code, ask about it:
```
1. Visual select a code block
2. Add: // Q: What does this do?
3. <leader>ma
```
The AI focuses on your selection.

### Knowledge That Stays
Every Q&A is saved to your codebase as comments. Search your learning history:
```vim
:EduTutorSearch closure    " Find past explanations
:EduTutorHistory           " Recent Q&A
:EduTutorExport            " Export to markdown
```

## Configuration

```lua
require("editutor").setup({
  provider = "claude",           -- claude, openai, deepseek, groq, ollama
  model = "claude-sonnet-4-20250514",
  language = "English",          -- or "Vietnamese"
  
  context = {
    token_budget = 20000,
  },
  
  keymaps = {
    ask = "<leader>ma",
  },
})
```

## Providers

| Provider | Environment Variable |
|----------|---------------------|
| Claude | `ANTHROPIC_API_KEY` |
| OpenAI | `OPENAI_API_KEY` |
| DeepSeek | `DEEPSEEK_API_KEY` |
| Groq | `GROQ_API_KEY` |
| Together | `TOGETHER_API_KEY` |
| OpenRouter | `OPENROUTER_API_KEY` |
| Ollama | Local, no key needed |

## Commands

| Command | What it does |
|---------|-------------|
| `:EduTutorAsk` | Process Q:/C: at cursor |
| `:EduTutorHistory` | Browse your Q&A history |
| `:EduTutorSearch` | Search past questions |
| `:EduTutorStats` | See your learning stats |
| `:EduTutorLang` | Switch language |

---

**Stop context-switching. Start understanding.**

The best way to learn programming is to build things. This plugin makes sure you actually learn while you build.
