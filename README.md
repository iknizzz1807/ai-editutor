# ai-editutor

**Build projects. Ask questions. Level up.**

A Neovim plugin for developers who learn by building.

## Why

You're building something real. Not a tutorial. Not a toy project. Something you actually care about.

And you have questions. Small ones, big ones, weird ones. *"What's a closure again?" "Why is this nil?" "How do I handle this edge case?"*

You could switch to ChatGPT. Open a browser. Lose your flow. Copy context back and forth. Or scroll through Stack Overflow answers from 2015.

Or you could just ask. Right here. Right now. In your code.

```javascript
// What is closure?
```

Press `<leader>ma`. Get an answer. Keep building.

**That's it.** No context switching. No copy-pasting. No breaking flow.

## The Philosophy

This is not a code generator. This is not about shipping faster.

This is about the moments when you're building something and you think *"wait, I should probably understand this better"* - and then you actually do, instead of just moving on.

**Learn while you build. Understand while you ship.**

Every question you ask is a chance to level up. Every answer stays in your codebase as a note to your future self.

## v2.0 - No Prefix Needed

Just write a comment. The AI figures out what you want.

```javascript
// What is closure?                    -> AI explains
// function to validate email          -> AI generates code
// Review this for security issues     -> AI reviews
// Why does this return nil?           -> AI debugs
```

All responses use the `/* [AI] ... */` format - easy to identify and edit.

### Example

```javascript
// What is a closure?
/* [AI]
A closure is a function that "remembers" variables from its outer scope
even after that scope has finished executing.

Example:
function counter() {
  let count = 0;
  return () => ++count;
}
const inc = counter();
inc(); // 1
inc(); // 2

Best practice: Use for data privacy, callbacks, and factory functions.
Watch out: Can cause memory leaks if holding references to large objects.
*/
```

### Float Window

Press `<leader>mt` to open the AI response in a floating window:
- Syntax highlighting (markdown)
- Editable - make changes directly
- `<C-s>` or `:w` to save changes back to source file
- `q` or `<Esc>` to close without saving

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

**3. Write a comment in your code**

```javascript
// Why would I use Map instead of a plain object?
```

**4. Press `<leader>ma`**

Answer appears as a comment. You keep coding. You keep learning.

## Features

### No Prefix Needed
Just write natural comments. The AI auto-detects your intent:
- Questions get explanations
- Code requests get working code
- Review requests get feedback

### [AI] Marker
All responses are marked with `[AI]` - easy to identify, search, and manage:
```javascript
/* [AI]
This is an AI response...
*/
```

### Float Window Toggle
Press `<leader>mt` to view/edit responses in a floating window:
- Markdown syntax highlighting
- Editable buffer
- Sync changes back to source file

### Context-Aware
Your questions get answered with full project context:
- Small projects (<20K tokens): Entire codebase included
- Large projects: Current file + imports + related definitions

### Visual Selection
Select confusing code, ask about it:
```
1. Visual select a code block
2. Add: // What does this do?
3. <leader>ma
```
The AI focuses on your selection.

### Skip Answered
Comments that already have an `[AI]` response below are automatically skipped.

### Knowledge That Stays
Every Q&A is saved by date. Review your learning history:
```vim
:EduTutorHistory           " Recent Q&A
:EduTutorBrowse            " Browse by date
:EduTutorExport            " Export to markdown
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
    ask = "<leader>ma",          -- Ask about comment
    toggle = "<leader>mt",       -- Toggle float window
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
| `:EduTutorAsk` | Ask about comment near cursor |
| `:EduTutorToggle` | Toggle AI response in float window |
| `:EduTutorHistory` | Recent Q&A history |
| `:EduTutorBrowse` | Browse by date |
| `:EduTutorExport` | Export to markdown |
| `:EduTutorLang` | Switch language |

## Keymaps

| Keymap | Mode | What it does |
|--------|------|-------------|
| `<leader>ma` | Normal | Ask about comment near cursor |
| `<leader>ma` | Visual | Ask about selected code |
| `<leader>mt` | Normal | Toggle AI response in float window |

---

**Stop context-switching. Start understanding.**

The best way to learn programming is to build things. This plugin makes sure you actually learn while you build.
