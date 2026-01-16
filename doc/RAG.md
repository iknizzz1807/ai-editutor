# Comprehensive guide to building an AI coding tutor for Neovim

An AI coding tutor that teaches developers through explanation rather than generating code represents a philosophically distinct approach from mainstream AI coding tools. This research synthesizes findings across **9 key areas** to provide actionable guidance for improving the ai-editutor plugin, covering everything from RAG implementation to Socratic pedagogy to performance optimization. The core finding: the most effective educational AI assistants combine **AST-based code understanding**, **progressive hint systems** with 4-5 levels of scaffolding, **hybrid retrieval** (semantic + keyword), and **intent-aware context gathering** that respects token budgets while maximizing relevance.

---

## RAG techniques that actually work for code

Code RAG differs fundamentally from document RAG because code has explicit structure, cross-file dependencies, and semantic meaning tied to syntax. Research shows **AST-based chunking outperforms naive text splitting by 2.7-5.5 points** on benchmarks like SWE-bench and RepoEval.

### Code embedding models comparison

| Model | Dimensions | Context | Best For |
|-------|-----------|---------|----------|
| **Voyage Code-3** | 2048 (configurable) | 32K tokens | Best quality (13.8% better than OpenAI) |
| **Nomic Embed Code** | 7B params | 2048 tokens | Best open-source, Apache 2.0 |
| **CodeSage Large V2** | 1.3B params | 2048 tokens | Matryoshka learning, flexible dims |
| **Jina Code V2** | 137M params | 8192 tokens | Fast local inference |
| **all-MiniLM-L6-v2** | 384 | 512 tokens | Default local option (Continue.dev) |

Legacy models like **CodeBERT** and **GraphCodeBERT** significantly underperform modern alternatives—CodeBERT achieves 0.117 MRR versus Voyage Code-3's 0.973 MRR on retrieval benchmarks.

### AST-based chunking is essential

The **cAST paper** (EMNLP 2025) demonstrates that chunking code via Abstract Syntax Trees produces semantically coherent units that dramatically improve retrieval quality. The algorithm: parse with tree-sitter, recursively split large AST nodes, then merge siblings while respecting size limits. Since **tree-sitter is already built into Neovim**, this approach is naturally suited for your plugin.

The `code-chunk` library generates "contextualized text" that includes scope, hierarchy, and dependency information:

```
# src/services/user.ts
# Scope: UserService
# Defines: async getUser(id: string): Promise<User>
# Uses: Database
# After: constructor

async getUser(id: string): Promise<User> {
  return this.db.query('SELECT * FROM users WHERE id = ?', [id])
}
```

### Vector database selection for editor plugins

**LanceDB** emerges as the clear choice for Neovim plugins—it's embedded, serverless, and proven by Continue.dev. Key characteristics: **4MB idle memory**, ~150MB during search, 40-60ms latency, native TypeScript support, and disk-based persistence.

| Database | Architecture | Memory | Latency | Best For |
|----------|-------------|--------|---------|----------|
| **LanceDB** | Embedded | 4MB idle | 40-60ms | Local-first plugins ✓ |
| **Qdrant** | Client-server | ~400MB | 20-30ms | Production scale |
| **SQLite-vec** | Extension | Minimal | Variable | Minimal dependencies |
| **ChromaDB** | Embedded | Variable | Medium | Rapid prototyping |

### Hybrid retrieval beats pure semantic search

For code, neither BM25 (keyword) nor vector search alone is sufficient. BM25 catches exact identifiers and function names; vector search finds semantically similar patterns. The recommended approach uses **Reciprocal Rank Fusion (RRF)** to combine results:

```python
def rrf_score(rank, k=60):
    return 1 / (k + rank)

# Fuse BM25 + vector results, then optionally rerank with ColBERT
```

### Incremental indexing strategies

For frequently-changing files, track document versions with file hashes. Re-index only on save (not every keystroke) using debounced updates. **Cursor's Merkle tree approach** enables efficient sync—only modified files are re-processed, with embeddings cached by chunk hash in AWS for team sharing.

**Key repositories:**
- **Continue.dev** (github.com/continuedev/continue) - LanceDB + hybrid retrieval implementation
- **CodeRAG** (github.com/Neverdecel/CodeRAG) - FAISS + file monitoring
- **code-graph-rag** (github.com/vitali87/code-graph-rag) - Knowledge graph with Memgraph

---

## Context engineering determines LLM effectiveness

Research shows context quality matters more than context quantity. Performance degrades **up to 2x** when functions reference forward-declared symbols, and adding call graph information as comments improves retrieval by **1.5-3x**.

### What context signals matter most

Based on research findings, prioritize in this order:
1. **Function/method signatures and type information** - Most critical
2. **Import statements and dependencies** - Essential for API understanding
3. **Call graph relationships** - Up to 3x improvement when injected
4. **Cross-file references** - Symbol definitions and usages
5. **Documentation and comments** - Especially docstrings near modified code
6. **Class/module structure** - Inheritance and interface implementations

### LSP capabilities to leverage

Neovim's LSP client provides everything needed for rich context extraction:

```lua
vim.lsp.buf.definition()           -- Symbol definitions
vim.lsp.buf.references()           -- All usages
vim.lsp.buf.hover()                -- Type info and docs
vim.lsp.buf.document_symbol()      -- File structure
vim.lsp.buf.incoming_calls()       -- Call hierarchy (callers)
vim.lsp.buf.outgoing_calls()       -- Call hierarchy (callees)
```

The **LSPRAG paper** (arXiv:2510.22210) demonstrates combining LSP lexical information with AST structural analysis for language-agnostic context extraction.

### Context window optimization

**Never exceed 85% context utilization**—Carnegie Mellon research shows quality degrades 23% beyond this threshold. Models also exhibit the "lost in the middle" problem, showing stronger recall for information in the **first 20%** and **final 10%** of the context window.

Sourcegraph's two-stage architecture provides a useful pattern: Stage 1 optimizes for recall (gather everything potentially relevant), Stage 2 optimizes for precision (ML-based ranking to fit token budget).

**Recommended budget allocation:**
- System prompt: 5%
- Current file: 30%
- Referenced definitions: 25%
- Call graph context: 15%
- Type information: 10%
- Documentation: 10%
- Diagnostics: 5%

**Key papers:**
- "Context Engineering for Multi-Agent LLM Code Assistants" (arXiv:2508.08322)
- "Evaluating Long Range Dependency Handling in Code Generation Models" (arXiv:2407.21049)

---

## Educational AI patterns for teaching without giving answers

The research strongly supports your "teach to fish" philosophy. Meta-analysis of **14,321 participants** found intelligent tutoring systems achieve effect sizes of **g = 0.42** against teacher-led instruction and **g = -0.11** against individual human tutoring (no significant difference). A Harvard 2024 study found AI tutoring produced **2x learning gains** compared to active learning classrooms.

### Implementing the Socratic method

The paper "Prompting Large Language Models With the Socratic Method" (Chang, 2023) identifies six key techniques:

1. **Definition**: Ask to define concepts before reasoning
2. **Elenchus (cross-examination)**: Validate credibility, identify inconsistencies
3. **Dialectic**: Explore opposing viewpoints through dialogue
4. **Maieutics**: "Intellectual midwifery"—extract knowledge the student already has
5. **Generalization**: Move from specific to general principles
6. **Counterfactual reasoning**: "What if" scenarios to test understanding

The core pattern: **always respond with a question before any explanation**.

### Progressive hint system design

Research from Carnegie Learning's Cognitive Tutor and programming education studies supports a **5-level progressive hint structure**:

| Level | Type | Example |
|-------|------|---------|
| 1 | Conceptual | "Think about what data structure would be efficient for lookups" |
| 2 | Strategic | "Consider time complexity differences between linear and hash-based approaches" |
| 3 | Directional | "A dictionary might help here. Why?" |
| 4 | Specific | "The dictionary's get() method could help. What key would you use?" |
| 5 | Near-solution | "Try: result = my_dict.get(search_key). What should search_key be?" |

Educators rate **hints/clues highest** for learning value, followed by step-by-step plans and Socratic questioning. Fill-in-the-blank code rated **lowest**—the risk is passive copying rather than active learning.

### Scaffolding and fading

Based on Wood, Bruner & Ross's foundational research, implement **contingent control** (adjust support based on moment-to-moment performance) and **fading support** (gradually reduce assistance as competence develops). Target the **Zone of Proximal Development**—the space between independent ability and what can be achieved with assistance.

### Effective prompt engineering for tutoring

```
You are a Socratic coding tutor. Philosophy: "teach to fish, don't fish for them."

RULES:
1. NEVER write complete code solutions
2. ALWAYS ask a clarifying question before explanation
3. Use progressive hints (vague → specific)
4. If asked "just give me the answer," explain WHY you won't

HINT PROGRESSION:
- First request: Ask what they've tried
- Second: Conceptual hint
- Third: Strategic direction
- Fourth: Specific technical hint
- Fifth+: Near-solution guidance with explanation
```

**Key repositories:**
- **socratic-llm** (GiovanniGatti/socratic-llm) - Fine-tuned Phi-3-mini for Socratic dialogue
- **Mr.-Ranedeer-AI-Tutor** (JushBJJ/Mr.-Ranedeer-AI-Tutor) - Customizable GPT-4 tutor, 18k+ stars
- **DeepTutor** (HKUDS/DeepTutor) - RAG-based with multi-agent problem solving

---

## Learning from the Neovim AI plugin ecosystem

The ecosystem has matured significantly with **avante.nvim** (17k+ stars), **codecompanion.nvim** (5.6k+ stars), and others offering sophisticated architectures worth studying.

### avante.nvim architecture

Acts as a Cursor emulator with a layered design:
- **User Layer**: Commands and keymaps
- **Orchestration Layer**: UI components (Sidebar, Selection, Suggestion)
- **AI Layer**: LLM module with provider registry
- **Infrastructure Layer**: Configuration, persistence, utilities

Uses **per-tab isolated state** through component registries and native Rust binaries for performance-critical operations. Streaming uses curl with Server-Sent Events (SSE).

### codecompanion.nvim patterns

Employs an **adapter-based design** for pluggable LLM backends with a strategy pattern for different interactions. Key innovations:
- **Variables**: `#buffer`, `#file` for context injection
- **Slash commands**: `/file`, `/symbols`, `/buffer`
- **Tools**: `@editor`, `@cmd_runner` for agentic workflows
- **Native "Super Diff"** for tracking agent edits

### Common pain points from GitHub issues

1. **Auto-suggestions eating API credits** - Solution: `auto_suggestions = false` by default
2. **Context management is cumbersome** - Users want LSP/TreeSitter-based automatic context
3. **Streaming breaks with certain providers** - Different API response formats cause issues
4. **Diff preview behavior** - Users want side-by-side diff before applying changes

### Top feature requests across plugins

1. Better LSP integration for automatic context gathering
2. More provider support (Gemini, DeepSeek, local models)
3. MCP/Tool integration for agentic workflows
4. Workspace/project-aware context
5. Chat history persistence and search

### Essential Lua patterns

```lua
-- Provider interface pattern
---@class Provider
---@field endpoint string
---@field model string
---@field parse_response fun(data_stream, opts): nil

-- Async job pattern with plenary.nvim
local Job = require("plenary.job")
Job:new({
  command = "curl",
  args = { "-sSL", "--no-buffer", url },
  on_stdout = vim.schedule_wrap(function(_, data)
    -- Process streaming chunk on main thread
  end),
}):start()

-- Event system for extensibility
vim.api.nvim_exec_autocmds("User", { pattern = "AIDone", data = result })
```

---

## How production AI coding assistants handle context

### Cursor's codebase indexing

Uses **Merkle trees** for efficient change detection—only modified files are re-uploaded. Code is chunked locally using AST techniques, then embeddings are generated server-side and stored in **Turbopuffer** (remote vector DB). Key result: **12.5% improvement** in retrieval accuracy with semantic vs keyword search. Embeddings are cached by chunk hash in AWS for efficient team sharing.

### Aider's repo map

Builds a concise repository map using **tree-sitter** for AST parsing, then applies **PageRank algorithm** to rank files/symbols by importance. The repo map shows most important classes, functions, and signatures within a configurable token budget (default: 1k tokens).

```
aider/coders/base_coder.py:
│class Coder:
│    @classmethod
│    def create(self, main_model, edit_format, io, ...)
│    def run(self, with_message=None):
```

**Limitation discovered**: Assumes all symbols are unique—problematic for large monorepos with duplicate function names.

### Continue.dev's context providers

Implements a **modular context provider architecture**:
- `@File` - Any workspace file
- `@Code` - Specific functions/classes
- `@Git Diff` - Current branch changes
- `@Terminal` - Last command and output
- `@Problems` - IDE diagnostics
- `@Repository Map` - Aider-inspired codebase outline

Uses **LanceDB** for local vector storage with **all-MiniLM-L6-v2** as default embedding model. Supports configurable providers: Transformers.js (local), Ollama, Voyage AI, OpenAI.

### Sourcegraph Cody's evolution

Initially used embeddings but moved away due to privacy concerns and scaling issues. Current approach leverages **native Sourcegraph search** with adapted BM25 ranking—no code sent to embedding processors. Context window: **30k tokens** for user context, 15k for conversation. Achieved **35% reduction** in retrieval failure rate using contextual embeddings.

**Key documentation links:**
- Aider repo map: aider.chat/docs/repomap.html
- Continue context providers: docs.continue.dev/customization/context-providers
- Cursor indexing: docs.cursor.com/context/codebase-indexing

---

## Intent detection for routing to the right mode

Your plugin's modes (Question, Socratic, Review, Debug, Explain) require intelligent query classification. The most effective approach combines **rule-based pre-filtering**, **semantic routing**, and **LLM fallback**.

### Research-backed query classification

The Stack Overflow classification paper (ICPC 2018) identified **7 question categories** with 91% precision using regex patterns:

| Intent | Trigger Phrases |
|--------|-----------------|
| **Debug** | "doesn't work", "error", "exception", "fails", "what's wrong" |
| **Explain** | "what does...mean", "how does...work", "why" |
| **Review** | "is this correct", "can you review", "feedback" |
| **How-to** | "how to", "how can I", "is there a way to" |
| **Conceptual** | "what is the purpose", "should I use" |

### Semantic routing for speed

**Aurelio Labs' semantic-router** (github.com/aurelio-labs/semantic-router) provides ~50ms classification vs 1-2s for LLM calls:

```python
from semantic_router import Route, RouteLayer

debug_route = Route(
    name="debug",
    utterances=[
        "why isn't this working",
        "I'm getting an error",
        "this code fails when..."
    ]
)
```

### Ambiguity detection

**ClarifyGPT** (FSE 2024) detects ambiguous requirements using code consistency checks: generate N solutions, check if they're semantically consistent—if they diverge, the requirement is ambiguous and clarifying questions are needed. This improved GPT-4 from 70.96% to 80.80% on benchmarks.

### Recommended hybrid architecture

```
User Query → [Pre-filter] → [Intent Classifier] → [Mode Router]

Pre-filter:
├── Detect explicit mode requests ("/debug", "/explain")
├── Extract code context from buffer
└── Identify error messages in terminal

Intent Classifier:
├── Rule-based: Check trigger phrases (0ms)
├── Semantic Router: Embedding similarity (50ms)
└── LLM fallback: Ambiguous cases (1-2s)

Confidence thresholds:
├── >0.85: Route directly
├── 0.6-0.85: Route with possible clarification
└── <0.6: Ask clarifying question
```

---

## Knowledge enrichment and documentation linking

### Documentation aggregation tools

**DevDocs** (38k GitHub stars) aggregates 150+ API documentation sets with a unified search interface. Architecture: Ruby scraper converts HTML docs to normalized partials + JSON index files, enabling fast in-browser search across 100k+ strings.

**Dash/Zeal** use Apple's docset format: HTML documentation + XML metadata + SQLite search index. The **doc2dash** tool converts Sphinx/MkDocs docs to this format.

### Building knowledge graphs for programming concepts

**Graph4Code** (github.com/wala/graph4code) provides a toolkit for building code knowledge graphs from 1.3M+ Python files, 2,300+ modules, and 47M forum posts. Graph structure:
- **Nodes**: Classes, functions, methods
- **Edges**: Usage patterns, data flow, control flow
- **Links**: Documentation, examples, forum discussions

### Learning path generation

Research supports using **topological ranking** on knowledge graphs to generate prerequisite-respecting learning sequences. The ant colony optimization approach produces paths highly similar to expert-created ones.

```javascript
LearningPath {
  nodes: [
    { concept: "variables", level: 1, resources: [...] },
    { concept: "conditionals", level: 2, resources: [...] },
    { concept: "functions", level: 3, resources: [...] }
  ],
  edges: [
    { from: "variables", to: "conditionals", type: "prerequisite" }
  ]
}
```

### Citation format for AI tutor responses

```markdown
## Explanation
[Your explanation]

## References
- [MDN: Array.prototype.map()](https://developer.mozilla.org/...)
- [Python Docs: List Comprehensions](https://docs.python.org/...)

## Related Topics
- [Next: Higher-Order Functions](/learning-path/higher-order-functions)
```

---

## Performance optimization for real-time assistance

### Latency targets

**Sub-300ms perceived latency** is the gold standard for code completion tools. Tabnine achieves ~190ms for local model inference. The key metric is **Time-to-First-Token (TTFT)**—if AI takes too long to show the first word, developers continue typing or give up.

### Caching strategies

**Semantic caching** stores responses based on meaning rather than exact input, using vector similarity to match semantically similar queries. **GPTCache** (github.com/zilliztech/GPTCache) can reduce latency from 4 seconds (cache miss) to 0.03 seconds (cache hit).

For code contexts, cache embeddings indexed by chunk hash. Cursor caches embeddings in AWS by chunk hash for efficient team sharing—same code across developers hits cache.

**Multi-layer caching system:**
1. Layer 1: Exact match check → instant retrieval
2. Layer 2: Semantic caching → NLP similarity detection
3. Layer 3: LLM generation (fallback)

### Developer pain points to avoid

Stack Overflow 2024/2025 surveys reveal critical insights:
- **76% of developers** use or plan to use AI tools
- **Only 43% trust AI accuracy** (46% actively distrust)
- **#1 complaint (66%)**: "Almost right, but not quite" solutions
- **63% cite** missing project context as major issue
- Favorability dropped from 77% (2023) to ~60% (2025)

**What developers actually want:**
- Tools that work where they already are
- Less context switching
- Clear source attribution and explanation of reasoning
- Acting as "junior pair programmer, not senior consultant"
- Making developers think MORE, not less

---

## Recommended architecture for ai-editutor

Based on all research findings, here's the recommended architecture:

```
┌─────────────────────────────────────────────────────────┐
│                   ai-editutor Architecture               │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. Intent Classifier                                    │
│      ├── Rule-based pre-filter (explicit /commands)      │
│      ├── Semantic router (embedding similarity)          │
│      └── LLM fallback (ambiguous queries)               │
│                                                          │
│  2. Context Engine                                       │
│      ├── LSP client (definitions, references, types)     │
│      ├── Tree-sitter (AST chunking, native to Neovim)   │
│      ├── Repo map (PageRank-ranked symbols)             │
│      └── Incremental indexer (hash-based updates)       │
│                                                          │
│  3. RAG Pipeline                                         │
│      ├── Embedding: Voyage Code-3 (API) or Nomic (local)│
│      ├── Vector DB: LanceDB (embedded)                   │
│      ├── Retrieval: Hybrid (BM25 + semantic)            │
│      └── Reranking: RRF fusion                          │
│                                                          │
│  4. Educational Response Generator                       │
│      ├── Socratic mode: Question-first responses         │
│      ├── Progressive hints: 5-level scaffolding          │
│      ├── Review mode: Constructive feedback patterns     │
│      └── Debug mode: Guided problem-solving             │
│                                                          │
│  5. Knowledge Enrichment                                 │
│      ├── Documentation linking (DevDocs, MDN)           │
│      ├── Concept graph traversal                         │
│      └── Learning path suggestions                       │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Implementation priorities

**Phase 1 (Core):**
- LSP-based context gathering (definitions, references, diagnostics)
- Tree-sitter AST chunking (already in Neovim)
- 5-level progressive hint system
- Socratic response patterns with question-first approach

**Phase 2 (Enhanced):**
- LanceDB integration for local vector storage
- Hybrid retrieval (BM25 + embeddings)
- Intent classification with semantic routing
- Project-specific rules via `.editutor.md` files

**Phase 3 (Advanced):**
- PageRank-based repo map (Aider-style)
- Incremental indexing with Merkle trees
- Knowledge graph for concept relationships
- Learning path generation and progress tracking

---

## Essential resources and repositories

### RAG and embeddings
- **Continue.dev** - github.com/continuedev/continue - LanceDB + hybrid retrieval (26.9k stars)
- **Aider** - github.com/Aider-AI/aider - Repo map with PageRank (39.7k stars)
- **code-graph-rag** - github.com/vitali87/code-graph-rag - Knowledge graph approach

### Neovim plugins to study
- **avante.nvim** - github.com/yetone/avante.nvim - Cursor emulator (17k stars)
- **codecompanion.nvim** - github.com/olimorris/codecompanion.nvim - Adapter-based design (5.6k stars)
- **gp.nvim** - github.com/Robitx/gp.nvim - Minimal dependencies, hooks-based

### Educational AI
- **Mr.-Ranedeer-AI-Tutor** - github.com/JushBJJ/Mr.-Ranedeer-AI-Tutor - Customizable tutor (18k stars)
- **socratic-llm** - github.com/GiovanniGatti/socratic-llm - Fine-tuned Phi-3 for Socratic dialogue
- **DeepTutor** - github.com/HKUDS/DeepTutor - RAG-based with multi-agent reasoning

### Key academic papers
- "cAST: Enhancing Code RAG with Structural Chunking via AST" (EMNLP 2025)
- "Prompting LLMs With the Socratic Method" (Chang, 2023, arXiv:2303.08769)
- "Scaffolding Metacognition in Programming Education" (arXiv:2511.04144)
- "ClarifyGPT: Empowering LLM Code Generation with Intention Clarification" (FSE 2024)
- "Context Engineering for Multi-Agent LLM Code Assistants" (arXiv:2508.08322)

### Performance and caching
- **GPTCache** - github.com/zilliztech/GPTCache - Semantic cache for LLMs
- **semantic-router** - github.com/aurelio-labs/semantic-router - Fast intent classification
- **CocoIndex** - Rust-based incremental indexing with tree-sitter

---

## Conclusion

Building an effective AI coding tutor requires balancing **technical sophistication** with **pedagogical soundness**. The research strongly validates your "teach to fish" philosophy—studies show AI tutors achieve learning gains equivalent to human tutors when properly designed, with the key being Socratic questioning and progressive scaffolding rather than answer-giving.

The most impactful technical improvements for ai-editutor would be: implementing **AST-based code chunking** using Neovim's built-in tree-sitter, adding **hybrid retrieval** with LanceDB for local vector search, building a **5-level progressive hint system** that respects Zone of Proximal Development principles, and using **LSP-powered context gathering** to automatically include relevant definitions and references.

Developer surveys consistently show frustration with AI tools that are "almost right but not quite"—an educational tool that teaches understanding rather than providing potentially-wrong solutions directly addresses this pain point. The opportunity is significant: by focusing on explanation and guided discovery, ai-editutor can occupy a distinct and valuable niche in the AI coding assistant landscape.