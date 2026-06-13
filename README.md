# ai-editutor

**A context-first Neovim assistant for developers who still want to think.**

`ai-editutor` lets you ask questions inside your codebase without handing the whole job to a coding agent. It gathers the smallest useful context around what you are doing, asks an LLM with that context, and writes the answer back inline so you can read, judge, learn, and keep control.

This project is built around one belief: **the assistant is only useful if its context is correct**.

LLMs have stale training data. Libraries, frameworks, APIs, and best practices change constantly. `ai-editutor` is designed to lean on your actual project, your local LSP, your installed dependencies, and the code around your question instead of pretending the model's knowledge cutoff is enough.

## Why

Modern coding agents are powerful, but they can also make you passive:

- they write too much before you understand the problem;
- they hide decisions behind large diffs;
- they make it easy to skip review;
- they can confidently use outdated framework knowledge;
- they often miss project-specific rules unless you keep repeating them.

`ai-editutor` takes a different shape. It is not trying to replace the developer. It is a pair-programming tutor that sits inside Neovim and answers questions with project context while keeping the code, question, and answer visible in the same file.

The goal is to help you:

- understand the code you are touching;
- ask precise questions at the exact location of confusion;
- get help that respects the current project design;
- catch mistakes, bad patterns, and risky assumptions early;
- stay involved instead of outsourcing your thinking.

## Core Idea

You put a temporary question block directly in the source file:

```python
# [Q:q_1737200000000]
# What does this function actually do?
# Is this merge order correct?
# What happens if config has no defaults key?
# [PENDING:q_1737200000000]
def process_user_data(data, config):
    normalized = {k.lower(): v for k, v in data.items() if v is not None}
    return {**config.get("defaults", {}), **normalized}
```

Then run `:EditutorAsk` or press `<leader>ma`.

The assistant sees the current file, relevant imports, incoming references, project structure, LSP diagnostics, and library/API information when available. It replaces the pending marker with an answer:

```python
# [Q:q_1737200000000]
# What does this function actually do?
# Is this merge order correct?
# What happens if config has no defaults key?
#
# This normalizes user data by lowercasing keys and dropping None values.
# The merge order means config defaults are applied first, then user data overrides them.
# `config.get("defaults", {})` is safe if the key is missing.
#
# Note: this assumes `config` is dict-like. If callers can pass None or another object,
# validate that before calling `.get()`.
def process_user_data(data, config):
    normalized = {k.lower(): v for k, v in data.items() if v is not None}
    return {**config.get("defaults", {}), **normalized}
```

Read it, question it, delete it, continue coding.

## What Makes It Different

### Context First

The context engine is the heart of this plugin. The assistant should not answer from vague memory when the project and local tools can provide better evidence.

`ai-editutor` currently gathers:

- current file content;
- project tree and source files for small projects;
- import graph context for larger projects;
- files imported by the current file;
- files that import the current file;
- transitive imports when budget allows;
- Tree-sitter semantic chunks for large files;
- LSP definitions for project symbols;
- LSP diagnostics near the question;
- LSP hover/library API information near the question.

The context system has a token budget and degrades from rich context to minimal context instead of blindly stuffing the prompt.

### Smart Context Extraction

![Context extraction flow](docs/context-extraction.svg)

The context extractor does not use one fixed strategy for every question. It first checks how large the project is, then chooses between two modes:

- **Full project mode** for small repositories: include the current file, project tree, and source/config files until the token budget is reached.
- **Adaptive mode** for larger repositories: start with the current file, then add related evidence in priority order and shrink the context only when needed.

In adaptive mode, the extractor builds context roughly like this:

1. **Current file first.** If it fits, the full current file is included. If it is too large, the extractor keeps the header/import area and the region around the question or cursor.
2. **Project tree next.** A compact tree gives the model orientation without spending much budget.
3. **Import graph expansion.** The extractor looks for files imported by the current file, files importing the current file, and transitive imports when the selected strategy allows it.
4. **Relevance scoring.** Related files are ranked higher when they are nearby, type/config files, direct imports, incoming importers, or small useful files. Tests, vendor files, generated files, and very large files are penalized.
5. **LSP definitions.** When enabled, identifiers from the current buffer are resolved through LSP so project symbol definitions can be included.
6. **Budget backtracking.** The strategy starts rich and falls back step by step: full related files, semantic chunks, direct imports, type/signature-only context, then minimal context.
7. **Extra evidence.** LSP hover/library information and diagnostics are added with separate small budgets, so library APIs and current typechecker errors can influence the answer.

The result is a prompt built from the strongest available evidence instead of a blind dump of files. A planned improvement is a context self-audit step that explicitly tells the model what evidence was included and what might still be missing.

### Runtime Docs Over Stale Memory

The model may not know the version of a library you are actually using. `ai-editutor` tries to reduce that risk by pulling information from the active editor environment:

- LSP hover text can expose installed API signatures and docs;
- LSP definitions can show real project types and functions;
- diagnostics can reveal the current compiler/typechecker state;
- local imports reveal what code path you are actually working in.

The assistant should prefer this live context over general training knowledge. If context is incomplete or the model is unsure, it should say so instead of pretending certainty.

### Developer Stays In Control

Answers are inline and temporary. The plugin does not hide the reasoning in a chat window or silently rewrite your project.

You ask. You read. You decide.

Code generation exists, but it is intentionally request-block based. You still place the request, review the output, and keep control of what lands in the file.

### Project-Aware Feedback

The assistant is expected to do more than answer the literal question. If the surrounding code shows a bug, weak design, bad practice, tech debt, or mismatch with the existing architecture, it should call that out clearly.

The goal is not to produce comforting answers. The goal is to make the developer sharper.

## Features

- Inline question blocks with `[Q:id]` and `[PENDING:id]` markers.
- Batch processing of multiple pending questions in one file.
- Visual selection support: ask about selected code.
- Code request blocks with `[C:id]` and generated `[CODE:id]` responses.
- Adaptive project context extraction with token budgeting.
- Import graph analysis across common languages.
- Tree-sitter semantic chunking for large files.
- LSP-powered definitions, diagnostics, hover text, and library API hints.
- Local knowledge history stored as daily JSON files.
- Debug logs for inspecting prompt/context behavior.
- Health check for dependencies and provider setup.

## Quick Start

### Install

Using `lazy.nvim`:

```lua
{
  "iknizzz1807/ai-editutor",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("editutor").setup({
      provider = "gemini",
      model = "gemini-3-flash-preview",
    })
  end,
}
```

### Set API Key

For Gemini:

```bash
export GEMINI_API_KEY="your-key"
```

or:

```bash
export GOOGLE_API_KEY="your-key"
```

For NVIDIA:

```bash
export NVIDIA_API_KEY="your-key"
```

### Ask A Question

1. Move the cursor to the code you want to understand.
2. Press `<leader>mq` or run `:EditutorQuestion`.
3. Type your question in the block.
4. Press `<Esc>`.
5. Press `<leader>ma` or run `:EditutorAsk`.
6. Read the inline answer and decide what to do.

## Visual Selection

Select code first, then press `<leader>mq`:

```typescript
const result = data
  .filter(x => x.status === "active")
  .reduce((acc, item) => ({
    ...acc,
    [item.id]: item.value * multiplier,
  }), {});
```

The generated question block includes the selected code as context:

````typescript
/* [Q:q_1737200000000]
Regarding this code:
```
const result = data
  .filter(x => x.status === "active")
  .reduce((acc, item) => ({
    ...acc,
    [item.id]: item.value * multiplier,
  }), {});
```

Can this be simplified? Is reduce the right choice here?
[PENDING:q_1737200000000]
*/
````

## Code Requests

`ai-editutor` can also generate code from inline request blocks.

Use:

```vim
:EditutorCode
:EditutorExecute
```

or the default keymaps:

```text
<leader>mc  create code request
<leader>mx  execute pending code requests
```

This mode is for targeted generation, not full-agent autonomy. Prefer small requests that you can review carefully.

## Commands

| Command | Description |
| --- | --- |
| `:Editutor` | Process pending questions, lazy-load entry command |
| `:Editutor ask` | Same as `:EditutorAsk` |
| `:Editutor version` | Show plugin version |
| `:EditutorQuestion` | Create a question block |
| `:EditutorAsk` | Process pending questions in current file |
| `:EditutorCode` | Create a code request block |
| `:EditutorExecute` | Process pending code requests in current file |
| `:EditutorPending` | Show pending question count |
| `:EditutorHistory` | Show recent Q&A history |
| `:EditutorBrowse` | Browse saved knowledge by date |
| `:EditutorExport` | Export saved knowledge to Markdown |
| `:EditutorClearCache` | Clear context cache |
| `:EditutorLog` | Open debug log |
| `:EditutorClearLog` | Clear debug log |
| `:EditutorTestRun` | Run built-in context test runner commands |
| `:EditutorTestResults` | View test runner results |

## Configuration

```lua
require("editutor").setup({
  provider = "gemini",
  model = "gemini-3-flash-preview",

  keymaps = {
    question = "<leader>mq",
    ask = "<leader>ma",
    code = "<leader>mc",
    execute = "<leader>mx",
  },

  context = {
    token_budget = 25000,
    library_info_budget = 2000,
    library_scan_radius = 50,
  },
})
```

### Built-In Providers

| Provider | Environment Variable | Default Model |
| --- | --- | --- |
| `gemini` | `GEMINI_API_KEY` or `GOOGLE_API_KEY` | `gemini-3-flash-preview` |
| `nvidia` | `NVIDIA_API_KEY` | `moonshotai/kimi-k2.5` |

Custom providers can be registered or passed through `providers` in setup.

## Context Engine

The context engine chooses between two broad modes.

### Full Project Mode

If the project fits within the token budget, `ai-editutor` includes:

- current file first;
- project structure;
- other source/config files selected by the scanner.

### Adaptive Mode

If the project is too large, it uses a backtracking strategy:

| Level | Purpose |
| --- | --- |
| `maximum` | Full related files, import depth 2, LSP context |
| `semantic_all` | Semantic chunks for large files |
| `depth1_with_lsp` | Direct imports plus LSP definitions |
| `depth1_no_lsp` | Direct imports without LSP |
| `limited_imports` | Top related imports only |
| `types_only` | Type/signature oriented context |
| `minimal` | Current file only |

The system should always try to return the best possible context within budget rather than fail because the project is large.

## Project-Specific Guidance Files

This is an important design direction for the project.

Many projects need local instructions that are more reliable than generic model knowledge: architecture rules, preferred libraries, anti-patterns, domain vocabulary, testing conventions, framework version notes, and links to current docs.

A future direction is for `ai-editutor` to discover project guidance files such as:

- `EDITUTOR.md`
- `.editutor.md`
- `skills.md`
- `.editutor/skills.md`
- `.editutor/context.md`
- `.editutor/docs.md`

Suggested shape:

```markdown
# EDITUTOR.md

## Project Intent
What this project is trying to build and what tradeoffs matter.

## Architecture Rules
- Keep business logic in services, not UI components.
- Do not bypass the repository layer.

## Current Library Docs And Versions
- React: use the project-installed version and local docs, not generic assumptions.
- TanStack Query: prefer existing query key conventions in `src/queryKeys.ts`.

## Local Anti-Patterns
- Do not introduce global mutable state for request-scoped data.
- Do not add compatibility layers unless there is a real persisted/external contract.

## Review Checklist
- Does this match existing patterns?
- Is the error handling consistent?
- Is this relying on outdated API knowledge?
```

The assistant should treat these files as project policy, not casual notes. When they conflict with stale model knowledge, the project files should win.

This would make `ai-editutor` closer to a project-aware tutor: it knows not only the current code, but also the local rules of the codebase.

## Knowledge Tracking

Every answered question is saved locally under Neovim's data directory:

```text
stdpath("data")/editutor/knowledge/YYYY-MM-DD.json
```

Use:

```vim
:EditutorHistory
:EditutorBrowse
:EditutorExport
```

This history is meant to help you review what you learned, not to hide decisions in a black box.

## Development

Available Make targets:

```bash
make test
make test-file FILE=tests/parser_spec.lua
make test-verbose
make lint
make format
make health
```

Notes:

- `plenary.nvim` is required for HTTP requests and tests.
- `curl` is required for provider requests.
- Tree-sitter improves semantic extraction.
- LSP clients significantly improve context quality.
- The current repository may not include the full test fixtures referenced by the Makefile.

## Health Check

Run:

```vim
:checkhealth editutor
```

The health check verifies:

- Neovim version;
- `plenary.nvim`;
- Tree-sitter availability;
- `curl`;
- active provider and API key;
- context extraction mode;
- LSP availability;
- project scanner stats;
- knowledge storage;
- cache state.

## Philosophy

`ai-editutor` is not about shipping faster at any cost.

It is for the moment when you think:

> I should understand this before I let an AI change it.

The assistant should be sharp, context-aware, and honest about uncertainty. It should help you notice bad design, outdated assumptions, missing docs, and weak reasoning. It should make you better at reading and reviewing code, not worse.

The product succeeds if it helps you keep agency while still getting high-quality AI support.
