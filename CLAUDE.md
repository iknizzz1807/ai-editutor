# CLAUDE.md - ai-editutor Development Guide

## Project Overview

**ai-editutor** - A Neovim plugin for developers who learn by building.

### Core Philosophy

> **Build projects. Ask questions. Level up.**

For developers building real projects who want to understand their code, not just ship it. Write comments naturally, get AI responses without breaking flow.

**Not** about coding faster. **About** learning while you build.

### v2.0.0 - Simplified: No Prefix Needed

**Key Change:** No more `Q:` or `C:` prefixes. Just write a comment naturally, and the LLM auto-detects your intent.

```javascript
// What is a closure?                    -> LLM explains
// function to validate email            -> LLM generates code
// Review this for security issues       -> LLM reviews
// Why does this return nil?             -> LLM debugs
```

**Response Format:**
- All responses in `/* [AI] ... */` block comment format
- Press `<leader>mt` to toggle response in float window (editable, syntax highlighted)
- Edit in float window, changes sync back to source file

**Key Features:**
- **No prefix needed** - LLM auto-detects question vs code request
- **[AI] marker** - Easy to identify AI responses: `/* [AI] ... */`
- **Float window toggle** - View/edit responses in floating window
- **Skip answered** - Comments with `[AI]` response below are skipped
- **Visual selection** - Select code block and ask about it
- **Streaming** - See response as it's generated
- **Adaptive context** - Full project (<20K tokens) or import graph + LSP

---

## Project Structure

```
ai-editutor/
├── lua/
│   └── editutor/
│       ├── init.lua              # Plugin entry point (v2.0.0)
│       ├── config.lua            # Configuration management
│       ├── parser.lua            # Comment detection near cursor
│       ├── context.lua           # Context extraction (full/adaptive)
│       ├── lsp_context.lua       # LSP-based context (go-to-definition)
│       ├── import_graph.lua      # Import graph analysis
│       ├── comment_writer.lua    # Insert responses with [AI] marker
│       ├── float_window.lua      # Toggle float window for responses
│       ├── prompts.lua           # Unified prompt (LLM auto-detects)
│       ├── provider.lua          # LLM API with inheritance + streaming
│       ├── knowledge.lua         # Knowledge tracking (date-based JSON)
│       ├── project_scanner.lua   # Project file scanning
│       ├── cache.lua             # LRU cache with TTL
│       ├── loading.lua           # Loading indicator
│       ├── debug_log.lua         # Debug logging
│       └── health.lua            # :checkhealth editutor
├── plugin/
│   └── editutor.lua              # Lazy loading entry
├── doc/
│   └── editutor.txt              # Vim help documentation
├── tests/
│   └── ...
├── README.md
└── CLAUDE.md                     # This file
```

---

## Architecture Overview

### v2.0 Flow (Simplified)

```
User writes comment: // What is a closure?
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. Find comment near cursor                                             │
│ 2. Check if already has [AI] response below -> skip if yes             │
│ 3. Extract context (full project < 20K OR import graph + LSP)          │
│ 4. Send to LLM (LLM auto-detects: question or code request)            │
│ 5. Stream response                                                      │
│ 6. Insert as /* [AI] ... */ block comment                              │
└─────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
Result:
    // What is a closure?
    /* [AI]
    A closure is a function that captures variables from its surrounding
    scope. When a function is defined inside another function, it has
    access to the outer function's variables even after the outer
    function has returned.
    
    Best practice: Use closures for data privacy and factory functions.
    Watch out: Memory leaks if closures hold references to large objects.
    */
```

### Float Window Toggle

Press `<leader>mt` near an AI response to:
1. Open float window with response content
2. Syntax highlighting (markdown)
3. Editable - make changes
4. `q` or `<Esc>` to close without saving
5. `<C-s>` or `:w` to save changes back to source file

### Skip Answered Comments

```javascript
function test() {
  // What is closure?           <- SKIPPED (already has [AI] below)
  /* [AI]
  A closure is a function...
  */

  // How does async work?       <- FOUND (unanswered)
  return 42;
}
```

The parser detects `/* [AI]` marker below comments and skips them.

### Visual Selection Support

```
1. Select code block with visual mode (v or V)
2. Write a comment about it
3. Press <leader>ma
4. Selected code is sent with "FOCUS ON THIS" label
```

### Context Extraction

```
                    Project Size Check
                         │
           ┌─────────────┴─────────────┐
           │                           │
    <= 20K tokens               > 20K tokens
           │                           │
           ▼                           ▼
    FULL_PROJECT                   ADAPTIVE
           │                           │
           ▼                           ▼
    All source files          ┌────────────────┐
    + Project tree            │ 1. Current file│
                              │ 2. Import graph│
                              │ 3. LSP defs    │
                              │ 4. Project tree│
                              └────────────────┘
```

### Comment Style Detection

The plugin automatically detects comment style based on filetype:

| Languages | Line Comment | Block Comment |
|-----------|--------------|---------------|
| JS/TS/Go/Rust/C/C++/Java | `//` | `/* */` |
| Python/Ruby/Shell | `#` | `""" """` or `=begin =end` |
| Lua/SQL/Haskell | `--` | `--[[ ]]` or `{- -}` |
| HTML/XML | - | `<!-- -->` |

AI responses always use block comments with `[AI]` marker.

---

## Key Files

### init.lua - Plugin Entry Point
- Version: 2.0.0
- Creates user commands (`:EduTutorAsk`, `:EduTutorToggle`, etc.)
- Sets up keymaps (ask + toggle)
- Main functions: `ask()`, `ask_visual()`, `toggle_float()`
- Multi-language UI messages (English, Vietnamese)

### parser.lua - Comment Detection
- `find_question_near_cursor()` - Finds comment near cursor without [AI] response below
- `is_ai_response_start()` - Detects `/* [AI]` or `// [AI]` marker
- `find_ai_response_block()` - Finds and extracts AI response content
- `get_visual_selection()` - Get visual selection range and content

### prompts.lua - Unified Prompt
- Single `SYSTEM_PROMPT` - LLM auto-detects question vs code request
- No more mode-specific prompts
- Bilingual support (English, Vietnamese)
- `build_user_prompt()` - Includes cursor position hint

### comment_writer.lua - Response Insertion
- Always uses `/* [AI] ... */` format (or line comment equivalent)
- `AI_MARKER = "[AI]"` constant
- Streaming support: `start_streaming()`, `update_streaming()`, `finish_streaming()`
- `find_ai_response_block()` - For float window sync
- Supports 40+ languages

### float_window.lua - Float Window Toggle
- `toggle()` - Open/close float window for AI response
- `open()` - Open float with stripped comment content
- `close(save)` - Close, optionally save changes back
- Keymaps: `q`/`<Esc>` close, `<C-s>`/`:w` save
- Markdown syntax highlighting
- Editable buffer

### provider.lua - LLM API Client
- Declarative provider definitions with inheritance
- Built-in: Claude, OpenAI, Gemini, DeepSeek, Groq, Together, OpenRouter, Ollama
- Streaming with debounced UI updates

---

## Key Commands

### Development
```bash
# Lint Lua
luacheck lua/

# Format Lua
stylua lua/

# Run tests
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.simplified_spec').run_all()" -c "qa"
```

### Plugin Usage (in Neovim)
```vim
" Core keymaps
<leader>ma           " Ask about comment near cursor
<leader>mt           " Toggle AI response in float window

" Commands
:EduTutorAsk         " Same as <leader>ma
:EduTutorToggle      " Same as <leader>mt

" Knowledge commands
:EduTutorHistory     " Show Q&A history
:EduTutorBrowse      " Browse by date
:EduTutorExport      " Export to markdown

" Language commands
:EduTutorLang             " Show current language
:EduTutorLang Vietnamese  " Switch to Vietnamese
:EduTutorLang English     " Switch to English

" Other commands
:EduTutorClearCache   " Clear context cache
:EduTutorLog          " Open debug log

" Health check
:checkhealth editutor
```

---

## Usage Examples

### Asking Questions (No Prefix Needed)

```javascript
// What is the time complexity of this algorithm?
// Explain how closures work
// Review this function for security issues
// Why does this sometimes return nil?
// What's the best practice for error handling here?
```

### Requesting Code (No Prefix Needed)

```javascript
// function to validate email with regex
// async function to fetch user with retry logic
// React hook for debouncing input
// helper to deep clone an object
```

### Response Format

```javascript
// What is a closure?
/* [AI]
A closure is a function that "closes over" variables from its outer scope,
maintaining access to them even after the outer function has returned.

Example:
```js
function counter() {
  let count = 0;
  return () => ++count;
}
const increment = counter();
increment(); // 1
increment(); // 2
```

Best practice: Use for data privacy, callbacks, and factory functions.
Watch out: Can cause memory leaks if holding large objects.
*/
```

### Using Float Window

1. Position cursor near an AI response
2. Press `<leader>mt` to open in float window
3. Edit the content (markdown syntax highlighting)
4. Press `<C-s>` to save changes back to source file
5. Press `q` to close without saving

---

## Configuration

```lua
require('editutor').setup({
  provider = "deepseek",  -- or "claude", "openai", "gemini", etc.
  model = "deepseek-chat",
  language = "Vietnamese",  -- or "English"
  keymaps = {
    ask = "<leader>ma",      -- Ask about comment
    toggle = "<leader>mt",   -- Toggle float window
  },
  context = {
    token_budget = 20000,    -- Max tokens for context
  },
})
```

---

## Code Style Guidelines

### Lua
- Use `local` for all variables
- Prefer `vim.tbl_*` functions for table operations
- Use `vim.notify` for user messages
- Async operations via `plenary.job` and LSP async callbacks
- Follow LazyVim conventions

---

## Development Phases

### Phase 1-9: COMPLETE (v0.1 - v1.2)
See git history for details.

### Phase 10: v2.0 Simplification - COMPLETE
- [x] Removed Q:/C: prefix requirement
- [x] LLM auto-detects intent (question vs code request)
- [x] Unified `/* [AI] ... */` response format
- [x] Float window toggle for viewing/editing responses
- [x] Float window sync back to source file
- [x] Simplified keymaps (ask + toggle)

### Future Enhancements
- [ ] Obsidian integration
- [ ] Team sharing

---

## Common Issues & Solutions

### Issue: Comment not detected
```lua
-- Make sure you're near a comment line
-- The plugin searches 15 lines up/down from cursor
-- Comments with [AI] response below are skipped
```

### Issue: Float window not opening
```lua
-- Make sure there's an AI response below the comment
-- Look for /* [AI] ... */ block
-- Position cursor on or near the original comment
```

### Issue: Changes not saving from float window
```lua
-- Press <C-s> or use :w command in float window
-- Just pressing q or <Esc> closes without saving
```

### Issue: LLM API timeout
```lua
require('editutor').setup({
  provider = {
    timeout = 30000,  -- 30 seconds
  }
})
```

---

## Resources

- [Tree-sitter Neovim Guide](https://tree-sitter.github.io/tree-sitter/)
- [Neovim LSP Documentation](https://neovim.io/doc/user/lsp.html)
- [Claude API Docs](https://docs.anthropic.com/)
- [Pedagogical AI Research (CS50.ai)](https://cs50.ai/)
