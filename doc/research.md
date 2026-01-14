# Building an AI code mentor: projects, approaches, and technical foundations

**An AI mentor that explains rather than generates code is not just possible—it's an emerging category with dozens of existing projects, proven pedagogical approaches, and a clear technical path for Neovim implementation.** The key insight from research: tools like GitHub Copilot trade learning for speed, while purpose-built mentors like CS50.ai and wtf.nvim prioritize understanding through guided explanation. For a Vietnamese software engineering student using Neovim with LazyVim, the most viable starting points are **wtf.nvim** (569 stars, focused on explaining diagnostics), **backseat.nvim** (code review/teaching), and the **gp.nvim** prompt system—all of which can be extended or combined to create a comment-based mentor that keeps you in full control of your code.

---

## Neovim plugins that already implement the "mentor" concept

The Neovim ecosystem has evolved beyond simple code generation into territory that directly matches the AI mentor vision. **wtf.nvim** stands out as the clearest example of explanation-first design—when you encounter an error, the `:Wtf` command sends diagnostics plus contextual code to an LLM and returns a detailed explanation of *why* the error occurred, not just how to fix it. It supports OpenAI, Claude, DeepSeek, and Ollama, making it adaptable for local or API-based models.

**backseat.nvim** takes a different approach: it reviews your entire buffer for readability issues and highlights problematic code with inline explanations. The `:BackseatAsk` command lets you ask specific questions like "What does the function on line 20 do?" This is pure teaching without any autocomplete functionality. For interactive chat-based learning, **gp.nvim** (1,291 stars) includes first-class support for "explain something in a popup window" and supports custom prompts via `.gp.md` project files—enabling repository-specific teaching contexts.

The most feature-rich options are **ChatGPT.nvim** (4,008 stars) with its built-in `explain_code` and `code_readability_analysis` actions, and **codecompanion.nvim** (5,703 stars) which supports CLAUDE.md and .cursor/rules files for persistent mentor personalities. For local-first privacy, **gen.nvim** (1,496 stars) works entirely with Ollama, enabling offline mentoring with customizable prompts—particularly valuable when learning on a budget or in network-restricted environments.

| Plugin | Stars | Primary Strength | Best For |
|--------|-------|-----------------|----------|
| wtf.nvim | 569 | Diagnostic explanation | Understanding errors |
| backseat.nvim | 185 | Code review teaching | Learning readability |
| gp.nvim | 1,291 | Popup explanations + chat | Interactive Q&A |
| ChatGPT.nvim | 4,008 | Built-in explain actions | Polished UX |
| gen.nvim | 1,496 | Local Ollama support | Privacy, offline use |
| codeexplain.nvim | 89 | GPT4ALL local models | Zero API cost |

---

## VSCode and cross-editor approaches worth studying

Microsoft's official VS Code documentation includes a **Code Tutor Chat Participant tutorial** that demonstrates the exact architecture you're envisioning. The sample code creates an `@tutor` participant that explicitly guides students toward understanding rather than providing direct answers—the prompt engineering states: *"You are a coding tutor who helps students...emulate a real-world tutor by guiding the student to understand the concept instead of providing direct answers."* This MIT-licensed sample at github.com/microsoft/vscode-extension-samples is directly portable to Neovim plugin concepts.

**Continue.dev** deserves particular attention as an Apache 2.0 licensed project with 30k+ GitHub stars. Its architecture separates core LLM logic from editor UI, meaning the `core/` module could potentially be adapted for Neovim backends. Configuration via `config.yaml` allows defining custom slash commands like `/explain` with pedagogical prompts—exactly the customization needed for mentor behavior.

**Sourcegraph Cody** (also Apache 2.0) represents the gold standard for codebase-aware explanations. Its `/explain` command understands entire project structures through Sourcegraph's code graph technology, enabling answers to questions like "where is authentication handled?" across hundreds of files. For understanding legacy codebases or onboarding to new projects, this depth of context is transformative for learning.

---

## The AiComments convention enables comment-based interaction

A particularly elegant solution for "AI answers questions via comments" exists in the **AiComments** convention (github.com/ovidiuiliescu/AiComments), which defines a structured syntax for human-AI collaboration directly in code:

```javascript
/*[ ? This buffer size prevents overflow in upstream transport ]*/  // Context
/*[ ~ Never emit messages longer than 512 chars ]*/                 // Rule
/*[ > Implement rate limiting here ]*/                               // Task
/*[ : Rate limiting completed ]*/                                    // Done
```

The `?` prefix provides context/explanation, `~` marks invariants the AI must respect, `>` indicates tasks, and `:` marks completions. A Neovim plugin could parse these patterns using Tree-sitter, send the context to an LLM, and render explanations as virtual text or floating windows at the question location. This keeps all interaction *inside* your code files while maintaining complete control over what gets written.

---

## Technical architecture for building your own

The cleanest implementation path combines **LSP-AI** as a backend with custom Neovim frontend code. LSP-AI (github.com/SilasMarvin/lsp-ai) is an MIT-licensed Rust server that handles all LLM complexity—supporting llama.cpp, Ollama, OpenAI, Anthropic, and Gemini—while communicating via standard Language Server Protocol. This means you write Lua code for the Neovim UI (floating windows, virtual text, comment parsing) while LSP-AI manages model inference, context windowing, and streaming responses.

For codebase-aware mentoring, a **RAG pipeline** significantly improves answer quality. The recommended stack:
- **LanceDB** (embedded, serverless) for vector storage—no separate database server needed
- **Tree-sitter** (already in Neovim) for language-aware code chunking
- **Hybrid search** combining BM25 keyword matching with semantic vectors, which Anthropic's research shows reduces retrieval errors by 49%

Context management is critical. Best practices from production systems include: respecting function/class boundaries when chunking code, preprocessing identifiers (converting `camelCase` to separate words for better embeddings), and implementing token-aware context windows that prioritize recently-accessed code.

```
┌──────────────────────────────────────────────────────────────┐
│                    Neovim Plugin (Lua)                        │
│   Comment Parser → UI (nui.nvim) → LSP Integration           │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│   Backend: LSP-AI or Custom Core                             │
│   - Context manager (Tree-sitter parsing)                    │
│   - RAG pipeline (LanceDB + embeddings)                      │
│   - Streaming response handler                               │
└────────────────────────┬─────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────┐
│   LLM: Ollama (local) | OpenAI | Claude | Custom endpoint    │
└──────────────────────────────────────────────────────────────┘
```

Key Neovim dependencies: **plenary.nvim** (async utilities, HTTP), **nui.nvim** (floating windows, inputs), **nvim-treesitter** (code parsing), and **render-markdown.nvim** (rendering AI responses with formatting).

---

## Academic research validates the mentor-over-generator approach

Harvard's **CS50.ai** deployment to thousands of students provides the strongest evidence for pedagogically-designed AI tutors. Professor David Malan explicitly describes the system as "similar in spirit to ChatGPT but designed to be *less* helpful"—it assists students in finding bugs rather than providing solutions, explains error messages in simpler terms, and uses "guardrails" to prevent over-helpfulness. The result: extensive positive student feedback and 24/7 "office hours" approximating 1:1 student-to-teacher ratios.

Research from Georgia State University and MIT identifies five design principles for effective AI tutors:
1. **Multiple hint styles**—toggle between Socratic questioning and direct feedback
2. **Adaptive debugging by experience level**—step-by-step for novices, pinpointed errors for advanced users
3. **Incremental hinting**—subtle clues first, partial snippets after struggles, full solutions only after multiple attempts
4. **Reflection prompts**—ask "Why does this fix the problem?" after providing help
5. **Seamless IDE integration**—minimize context switching with built-in editors

A critical finding from ScienceDirect (2025): *student performance negatively correlates with frequency of AI tool usage* when those tools provide direct code generation. This validates the mentor concept—AI that explains rather than generates may produce better learning outcomes even while appearing "less helpful" in the short term.

---

## Open-source starting points ranked by viability

For building on existing code rather than starting from scratch, these projects offer the strongest foundations:

**Tier 1 - Directly extensible for mentor concept:**
- **gp.nvim** — Highly customizable prompts, popup explanations already implemented, LazyVim compatible
- **wtf.nvim** — Clean diagnostic explanation architecture, WTFPL license allows any modification
- **llm.nvim (Kurama622)** — Supports any OpenAI-compatible API with custom streaming handlers

**Tier 2 - Architecture reference:**
- **Continue.dev** — Best-documented architecture separating core logic from UI, Apache 2.0
- **LSP-AI** — Rust backend handling model complexity, MIT license, editor-agnostic

**Tier 3 - Concept validation:**
- **VS Code tutor samples** — Microsoft's official tutorial code demonstrates prompt engineering for teaching
- **LlamaTutor** — Together AI's open-source interactive tutor with 90k users

For a Neovim-native implementation, **forking gp.nvim and adding comment-based interaction** (parsing `// Q:` patterns and rendering answers as virtual text) would require the least effort while providing the most flexibility. The existing popup explanation infrastructure handles the hardest UI problems.

---

## Conclusion: a clear path forward

The AI mentor concept isn't speculative—it's an active development category with production deployments at Harvard, Khan Academy, and thousands of Neovim users. The technical stack is mature: LSP-AI or direct API calls for LLM communication, Tree-sitter for code understanding, nui.nvim for UI, and RAG pipelines for codebase awareness. The pedagogical principles are validated: guide rather than give, explain rather than generate, and use incremental hints that preserve learner agency.

For a Vietnamese engineering student wanting 100% code control, the winning formula combines **wtf.nvim's diagnostic explanation approach** with **gp.nvim's customizable prompt system** and a **comment-based interaction pattern** inspired by AiComments. Start by installing these existing plugins to understand their behavior, then either extend them or build a focused tool that parses question comments (`// Q: Why does this loop terminate?`), gathers context via Tree-sitter, queries an LLM with pedagogical prompting, and renders answers as floating windows or virtual text. The entire project is achievable as a **single Lua file under 500 lines** if you leverage the existing ecosystem—or can grow into a full-featured mentor system with RAG and adaptive difficulty as skills develop.