# ai-editutor

> **Like having a senior developer sitting next to you.**

When you're coding and have a quick question - about a concept, a bug, or need some code - you just ask inline and get a concise, context-aware answer. No context switching to browser or ChatGPT.

## The Vision

Imagine having a patient senior dev beside you while coding. You can ask small questions anytime:

- "What's a closure again?"
- "Why does this return nil?"
- "Can you write a function to validate this?"

They answer quickly, understand your code, and you keep coding - **while learning**.

This is **not** about shipping faster. It's about **growing as a developer** while you work.

## Two Modes

**Q: (Question)** - Ask, learn, understand:
```javascript
// Q: What is closure?
/*
A: A closure is a function that "remembers" variables from its outer scope
even after that scope has finished executing.

Why it matters: Enables data privacy, callbacks, and functional patterns.
Watch out: Accidental closures in loops can cause bugs.
*/
```

**C: (Code)** - Generate code with context:
```javascript
// C: validate email with regex
function validateEmail(email) {
  const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return regex.test(email);
}
/*
Notes:
- Simple regex for common formats
- For strict validation, consider validator.js
*/
```

## Quick Start

1. **Install**
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

2. **Set API key**
```bash
export ANTHROPIC_API_KEY="your-key"
```

3. **Ask a question**
```python
# Q: What does this regex do?
pattern = r'^(?=.*[A-Z])(?=.*\d).{8,}$'
```

4. **Press `<leader>ma`** - Answer appears as a comment below.

## Features

### Context-Aware
The AI understands your project:
- Small projects (<20K tokens): Sends entire codebase
- Large projects: Sends current file + import graph + LSP definitions

### Visual Selection
Select code, write a question, get focused explanation:
```
1. Select code block (v or V)
2. Write // Q: Explain this
3. Press <leader>ma
```

### Skip Answered
Questions with answers below are automatically skipped - no re-asking.

### Knowledge Tracking
All Q&A pairs are saved. Search and review your learning history:
```vim
:EduTutorHistory     " Recent Q&A
:EduTutorSearch      " Search past questions
:EduTutorExport      " Export to markdown
```

## Commands

| Command | Description |
|---------|-------------|
| `:EduTutorAsk` | Ask Q:/C: at cursor |
| `:EduTutorHistory` | View Q&A history |
| `:EduTutorSearch` | Search knowledge base |
| `:EduTutorStats` | View statistics |
| `:EduTutorLang` | Switch language (English/Vietnamese) |

## Configuration

```lua
require("editutor").setup({
  provider = "claude",  -- claude, openai, deepseek, groq, ollama
  model = "claude-sonnet-4-20250514",
  language = "English",  -- or "Vietnamese"
  
  context = {
    token_budget = 20000,  -- Max context tokens
  },
  
  keymaps = {
    ask = "<leader>ma",
  },
})
```

## Supported Providers

| Provider | API Key Env Variable |
|----------|---------------------|
| Claude | `ANTHROPIC_API_KEY` |
| OpenAI | `OPENAI_API_KEY` |
| DeepSeek | `DEEPSEEK_API_KEY` |
| Groq | `GROQ_API_KEY` |
| Together | `TOGETHER_API_KEY` |
| OpenRouter | `OPENROUTER_API_KEY` |
| Ollama | (no key needed) |

## Philosophy

This plugin is **not** for:
- Shipping apps faster
- Meeting deadlines
- Replacing thinking

This plugin **is** for:
- Learning while building real projects
- Understanding code, not just writing it
- Growing as a developer every day

---

**The goal isn't to code faster. It's to become a better developer.**
