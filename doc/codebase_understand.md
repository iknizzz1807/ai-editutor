# Building codebase RAG for AI code mentoring: a technical guide

**The most effective approach for AI codebase understanding combines AST-aware chunking via Tree-sitter, hybrid search (BM25 + vector embeddings), and a decoupled architecture where a Python/Rust CLI handles indexing while your Neovim plugin manages retrieval and context assembly.** This pattern, exemplified by VectorCode and Continue.dev, achieves **12.5% higher accuracy** than grep-only approaches and provides the foundation for sophisticated code mentoring.

For your Phase 3 implementation, the recommended stack is: **Tree-sitter for parsing → ChromaDB or LanceDB for vectors → UniXcoder or all-MiniLM-L6-v2 for embeddings → Reciprocal Rank Fusion for hybrid search**. This combination balances performance, local-first privacy, and Neovim integration simplicity.

---

## RAG implementations worth studying and adapting

The open-source ecosystem offers several production-ready RAG implementations for code. **Aider** (25k+ GitHub stars) takes a unique "repository map" approach—instead of embedding entire files, it uses Tree-sitter to extract symbol definitions, builds a dependency graph, and applies **PageRank** to rank the most important symbols within a configurable token budget. This fits large codebases into context windows efficiently.

**Continue.dev** (20k+ stars) provides the most directly adaptable architecture for editor integration. Its indexing system uses a multi-backend approach:

| Backend | Purpose | Storage |
|---------|---------|---------|
| LanceDB | Semantic vector search | `~/.continue/index/` |
| Tree-sitter | AST-based code structure | In-memory |
| ripgrep | Fast keyword fallback | System binary |

Continue's retrieval pipeline demonstrates enterprise-grade practices: embeddings retrieval first, optional HyDE (Hypothetical Document Embeddings) generation, keyword search via ripgrep, and LLM-based re-ranking using logprobs. The source code in `core/indexing/` and `core/context/providers/CodebaseContextProvider.ts` provides excellent reference implementations.

**code-graph-rag** (~1.4k stars) represents the knowledge-graph approach—it builds relationships (CALLS, DEFINES, CONTAINS) between code entities in Memgraph, enabling queries like "what functions call the authentication handler?" This architecture excels for understanding complex dependency chains but requires more infrastructure.

---

## How modern tools chunk code semantically

Fixed-size character or line-based chunking breaks semantic boundaries and degrades retrieval quality. **AST-based chunking using Tree-sitter is the industry standard**, with the cAST research paper (CMU, 2025) demonstrating a **4.3-point improvement in Recall@5** and **2.67-point improvement in Pass@1** on coding benchmarks.

The optimal chunking strategy follows these principles from Qodo's enterprise deployment across 10,000+ repositories:

1. **Preserve syntactic integrity**: Chunk boundaries align with complete functions, classes, or methods
2. **Pack to size budget**: Target ~500 tokens per chunk (not characters or lines)
3. **Include critical context**: Prepend imports, class definitions, and type signatures to method chunks
4. **Generate NL descriptions**: LLM-generated summaries embedded alongside code improve semantic search by bridging the vocabulary gap between natural language queries and code identifiers

The **code-chunk library** (supermemoryai/code-chunk) implements this well:

```javascript
const chunks = await chunk('src/user.ts', sourceCode)
// Each chunk includes:
// - contextualizedText: Code with scope context prepended
// - context.scope: [{ name: 'UserService', type: 'class' }]
// - context.entities: Functions, methods defined in chunk
```

For your Neovim plugin, **astchunk** (Python) provides the cleanest implementation with LangChain compatibility. It uses Tree-sitter's recursive descent through the AST, splitting only when nodes exceed the size budget and preserving the ability to concatenate chunks back into the original file.

---

## Embedding models for code retrieval

Code-specific embedding models significantly outperform general-purpose text embeddings for retrieval tasks. Based on CodeSearchNet benchmarks:

| Model | Dimensions | MRR Score | Best Use Case |
|-------|------------|-----------|---------------|
| **CodeT5+ 110M** | 256 | Highest | Production code search |
| **UniXcoder** | 768 | ~0.73 | Cross-language retrieval |
| **GraphCodeBERT** | 768 | 0.713 | Clone detection (uses data flow) |
| **all-MiniLM-L6-v2** | 384 | Good | Fast, local, general |
| **voyage-code-3** | 1024 | Excellent | Commercial API, optimized for code |

**UniXcoder** (microsoft/unixcoder-base) stands out for zero-shot code-to-code search, doubling MAP@R over baselines. It uniquely supports encoder-only, decoder-only, and encoder-decoder modes, trained on AST and comments as additional modalities.

For your local-first Neovim plugin, **all-MiniLM-L6-v2** via sentence-transformers offers the best tradeoff—384 dimensions keeps vector storage small, inference runs fast on CPU, and quality remains competitive. If you need better code understanding and can accept API costs, **voyage-code-3** is purpose-built for code retrieval.

A hybrid embedding strategy provides best results: embed both the raw code AND an LLM-generated natural language description of each chunk. This bridges the vocabulary mismatch where users search "authentication logic" but code contains `validateJWTToken()`.

---

## Vector databases for local Neovim integration

For a Neovim plugin requiring local-first operation with minimal dependencies:

| Database | Type | Query Latency | Lua/IPC Compatibility |
|----------|------|---------------|----------------------|
| **LanceDB** | Embedded | 40-60ms | REST API, easy IPC |
| **sqlite-vec** | SQLite extension | ~100ms for 10K vectors | SQLite protocol (lsqlite3 bindings) |
| **ChromaDB** | Embedded/server | ~10ms | REST API, Python-native |
| **Qdrant** | Server | 20-30ms | gRPC/REST, best hybrid search |

**LanceDB** is the strongest choice for Neovim integration—it's a single-file embedded database (SQLite-like) with native hybrid search, requiring no separate server process. Continue.dev chose it for exactly these reasons.

**sqlite-vec** deserves attention for Neovim specifically because Lua has mature SQLite bindings (lsqlite3). You can store vectors alongside metadata in a single `.db` file, query via familiar SQL, and leverage SQLite's FTS5 for keyword search—all without external processes.

**VectorCode** (the existing Neovim RAG plugin) chose **ChromaDB** with a Python CLI architecture. While this requires a Docker container or Python installation, it provides proven Neovim integration patterns you can reference.

---

## Semantic search versus traditional grep

Cursor's engineering team published compelling data: **semantic search achieves 12.5% higher accuracy** in answering codebase questions compared to grep-only approaches. On codebases with 1000+ files, this gap widens to **2.6% higher code retention**.

The fundamental difference:

- **grep/ripgrep**: Matches exact lexical patterns. Fast, deterministic, perfect for known identifiers. Searches the Linux kernel in ~360ms.
- **Semantic search**: Understands intent. "Where do we validate user permissions?" finds `checkAuthorizationLevel()` without knowing the function name.

**Hybrid search combining both is essential for production systems.** Cursor's agent uses grep AND semantic search together, achieving best results through complementary strengths. The implementation pattern uses **Reciprocal Rank Fusion (RRF)**:

```
RRF_score(doc) = Σ 1/(k + rank_i(doc))
```

Where k=60 is the standard constant. This elegantly combines ranked lists from different retrievers without requiring score normalization. Weaviate, Milvus, and LanceDB all support RRF natively.

For your Neovim plugin, implement hybrid search from the start: ripgrep for keyword matching, vector search for semantic queries, RRF fusion for final ranking.

---

## AST-based search tools for structural queries

Beyond embedding-based search, **AST-aware tools enable precise structural queries** that grep cannot express:

**ast-grep** (ast-grep/ast-grep) uses Tree-sitter for CST parsing with isomorphic pattern syntax—patterns look like actual code:

```bash
# Find console.log calls with any arguments
ast-grep -p 'console.log($$$ARGS)' -l js

# Replace var with let in JavaScript
ast-grep -p 'var $NAME = $VALUE' -r 'let $NAME = $VALUE' -l js
```

**Semgrep** excels at security scanning with semantic equivalence understanding—it knows `foo(a=1, b=2)` matches `foo(b=2, a=1)` in Python:

```yaml
rules:
  - id: use-sys-exit
    pattern: exit($X)
    fix: sys.exit($X)
```

**Comby** provides language-agnostic structural matching, useful when you don't need full AST parsing:

```bash
comby 'failUnlessEqual(:[a],:[b])' 'assertEqual(:[a],:[b])' example.py
```

For your AI mentor, these tools complement semantic search—students asking "show me all functions that don't handle errors" require AST queries that vector search cannot answer.

---

## Continue.dev's architecture as implementation reference

Continue.dev's open-source codebase (github.com/continuedev/continue) provides the most directly applicable architecture:

**Chunking flow**:
1. Check if entire file fits in context → use as single chunk
2. Parse AST via Tree-sitter, extract top-level functions/classes
3. For large items, truncate to signature + "..."
4. Recurse into nested methods for separate chunks
5. Target ~512 tokens optimal for embeddings

**Indexing architecture**:
```
CodebaseIndexer (core/core.ts)
    → File Walker (respects .gitignore)
    → Tree-sitter Parser (multi-language)
    → Embedding Provider (all-MiniLM-L6-v2 default)
    → LanceDB Writer (local SQLite-like storage)
```

**Retrieval pipeline**:
1. Dense embeddings retrieval
2. Optional HyDE (generate hypothetical code snippet for better matching)
3. Keyword search via ripgrep (parallel)
4. Re-ranking using LLM logprobs for "Yes/No" relevance
5. Ensemble combination

Continue's file watching handles incremental updates: `files/changed`, `files/created`, `files/deleted` events trigger selective re-indexing. Branch changes auto-trigger full reindex.

---

## VectorCode: the Neovim-native starting point

**VectorCode** (github.com/Davidyz/VectorCode) is the most complete existing Neovim RAG implementation and should be your primary reference:

**Architecture**:
- **Python CLI** for indexing: `vectorcode vectorise`
- **ChromaDB** for vector storage (Docker or local)
- **SentenceTransformer** for embeddings
- **Tree-sitter** (py-tree-sitter) for chunking
- **Neovim plugin** (Lua) for retrieval
- **MCP server** for AI agent integration

**Neovim integration pattern**:
```lua
-- Async caching for background retrieval
:VectorCode register  -- Register buffer for async context
:VectorCode query     -- Manual semantic query

-- Integration with codecompanion.nvim
strategies = {
  chat = {
    slash_commands = {
      codebase = require("vectorcode.integrations").codecompanion.chat.make_slash_command(),
    },
  },
}
```

VectorCode demonstrates the **CLI + Plugin pattern**: keep heavy computation (indexing, embedding generation) in Python/Rust where ecosystem is strongest, communicate with Neovim via stdout/stdin JSON protocol. This separation enables using battle-tested libraries (ChromaDB, sentence-transformers, tree-sitter-languages) while maintaining Lua-native editor integration.

---

## Cursor's Merkle tree innovation for incremental indexing

Cursor's engineering approach to incremental indexing deserves attention for scalability:

1. **Client-side chunking**: Code split into semantic chunks locally (AST-based)
2. **Merkle tree construction**: Compute hierarchical hashes of all files
3. **Server sync**: Send only hash tree, not code
4. **Change detection**: Every 10 minutes, compare trees → upload only changed file hashes
5. **Embedding generation**: Server embeds changed chunks
6. **Vector storage**: Turbopuffer (remote vector DB)

**Privacy-preserving query flow**:
```
Query → Embedding → Server vector search → Return obfuscated paths + line ranges → Client reads local files → Context assembly
```

This architecture enables **O(log n) change detection** via Merkle trees and team sharing of embeddings (same repo users share work). While you likely want local-first for your plugin, the incremental update algorithm applies: store file content hashes, re-index only changed files.

---

## Neovim plugins and APIs for your implementation

The Neovim AI plugin ecosystem provides integration patterns:

| Plugin | Focus | Codebase Features |
|--------|-------|-------------------|
| **avante.nvim** (~17K stars) | Cursor-like IDE experience | Project instructions via avante.md |
| **codecompanion.nvim** (~6K stars) | Flexible AI chat | Workspaces, variables, slash commands |
| **VectorCode** (~400 stars) | Codebase RAG | Full indexing + retrieval |
| **CopilotChat.nvim** (~3.5K stars) | GitHub Copilot chat | Buffer/viewport context |

**Key Neovim APIs for your plugin**:

```lua
-- Tree-sitter integration (built-in)
local parser = vim.treesitter.get_parser(bufnr, lang)
local tree = parser:parse()[1]
local query = vim.treesitter.query.parse(lang, query_string)

-- LSP integration
vim.lsp.buf.definition()
vim.lsp.buf.references()
client.request('textDocument/documentSymbol', params, handler)

-- Async job management (plenary.nvim)
local Job = require("plenary.job")
Job:new({
  command = "your-indexer-cli",
  args = { "query", "--json", query_text },
  on_exit = function(job, code)
    local result = vim.json.decode(table.concat(job:result(), "\n"))
    callback(result)
  end,
}):start()

-- File watching
local handle = vim.loop.new_fs_event()
handle:start(project_root, { recursive = true }, function(err, fname, status)
  if status.change then queue_reindex(fname) end
end)
```

**Recommended dependencies**: plenary.nvim (async utilities), nvim-treesitter (parser management), nui.nvim (UI components), telescope.nvim (fuzzy picker for results).

---

## Technical implementation: indexing 100K+ line codebases

### Chunking strategy

Use AST-based chunking with Tree-sitter. The **astchunk** library implements the recommended recursive split-then-merge algorithm:

```python
from astchunk import ASTChunkBuilder
chunk_builder = ASTChunkBuilder(
    max_chunk_size=500,  # tokens, not characters
    language="python",
    metadata_template="default"
)
chunks = chunk_builder.chunkify(code)
```

**Key parameters**:
- Target **500-1000 tokens per chunk** (optimal for embeddings)
- Include **50-200 token overlap** for context continuity
- Prepend **import statements** and **class definitions** to method chunks

### Incremental indexing

Git-based change detection is most efficient:

```bash
# Store last indexed commit hash
git rev-parse HEAD > .vectorcode/last_index

# On trigger, find changed files
git diff-index --name-only $(cat .vectorcode/last_index) HEAD
```

For real-time updates, use **fswatch** (cross-platform) or vim.loop.new_fs_event(). Key consideration: Linux's inotify defaults to 8192 watchers—increase for large codebases:

```bash
echo fs.inotify.max_user_watches=65536 | sudo tee -a /etc/sysctl.conf
```

### Hybrid search implementation

```python
# Reciprocal Rank Fusion combining BM25 + vector search
def hybrid_search(query, k=60):
    bm25_results = bm25_search(query)  # ripgrep or FTS5
    vector_results = vector_search(embed(query))
    
    rrf_scores = {}
    for rank, doc in enumerate(bm25_results):
        rrf_scores[doc.id] = rrf_scores.get(doc.id, 0) + 1/(k + rank)
    for rank, doc in enumerate(vector_results):
        rrf_scores[doc.id] = rrf_scores.get(doc.id, 0) + 1/(k + rank)
    
    return sorted(rrf_scores.items(), key=lambda x: x[1], reverse=True)
```

### Context window management

For LLM context assembly, prioritize chunks:
1. Highest hybrid search score (most relevant)
2. Import statements for retrieved code
3. Class/function definitions containing retrieved methods
4. Related test files

**Compression technique**: For large files, generate LLM summaries (~80% size reduction) and embed summaries alongside code for retrieval, but return original code for context.

---

## Recommended architecture for your Neovim plugin

Based on this research, implement a **CLI + Plugin architecture**:

```
┌─────────────────────────────────────────────────────────────┐
│            Neovim Plugin (Lua)                              │
│  - Buffer registration, async job management                │
│  - Context assembly, UI (telescope picker)                  │
│  - Integration with codecompanion.nvim/avante.nvim          │
└────────────────────────┬────────────────────────────────────┘
                         │ JSON via stdout/stdin
                         ▼
┌─────────────────────────────────────────────────────────────┐
│            CLI Tool (Python or Rust)                        │
│  Commands: index, query, watch                              │
├─────────────────────────────────────────────────────────────┤
│  Tree-sitter → AST Chunking → Embeddings → Vector Store     │
│         └── all-MiniLM-L6-v2 ──┘    └── LanceDB/ChromaDB    │
│                                                             │
│  ripgrep ─────────────────────────┬──── BM25 Keywords       │
│                                   │                         │
│         Reciprocal Rank Fusion ◀──┴──── Hybrid Results      │
└─────────────────────────────────────────────────────────────┘
```

**Phase 3 implementation checklist**:

1. **Indexing CLI** (Python recommended for ecosystem):
   - tree-sitter-languages for multi-language AST parsing
   - astchunk or custom chunker targeting 500 tokens
   - sentence-transformers with all-MiniLM-L6-v2
   - LanceDB for single-file vector storage
   - SQLite FTS5 for keyword search

2. **Neovim Plugin** (Lua):
   - plenary.job for async CLI communication
   - Buffer registration for automatic context
   - vim.loop.new_fs_event() for file watching
   - Slash commands for codecompanion.nvim integration

3. **Query interface**:
   - Hybrid search with RRF (k=60)
   - Context priority ranking
   - Token budget management for LLM context windows

---

## Open-source repositories to fork or study

| Project | GitHub | What to Learn |
|---------|--------|---------------|
| **VectorCode** | Davidyz/VectorCode | Neovim integration patterns, ChromaDB setup |
| **Continue.dev** | continuedev/continue | Enterprise indexing, multi-backend retrieval |
| **code-graph-rag** | vitali87/code-graph-rag | Knowledge graph approach, Memgraph integration |
| **astchunk** | yilinjz/astchunk | AST-based chunking implementation |
| **SeaGOAT** | kantord/SeaGOAT | Local-first semantic search CLI |
| **grepai** | yoanbernabeu/grepai | MCP server pattern, file watching |
| **semantic-code-search** | sturdy-dev/semantic-code-search | Simple CLI semantic search |

For embedding generation, reference **microsoft/unixcoder-base** and **Salesforce/codet5p-110m-embedding**. For chunking, **supermemoryai/code-chunk** provides excellent contextual metadata handling.

---

## Conclusion

Building effective codebase RAG for your AI mentor plugin requires combining proven patterns: **AST-aware chunking** preserves code semantics, **hybrid search** (BM25 + vectors with RRF fusion) captures both exact matches and conceptual queries, and a **decoupled CLI architecture** enables using Python's rich ML ecosystem while maintaining Lua-native Neovim integration.

Start with VectorCode's architecture as your foundation—it demonstrates working Neovim integration patterns. Improve upon it by adding hybrid search (VectorCode currently uses vector-only retrieval), implementing Cursor-style incremental indexing via content hashes, and integrating LLM-generated code summaries for better semantic matching.

The 12.5% accuracy improvement from semantic search over grep-only approaches, combined with 15-30% recall gains from hybrid search, justifies the implementation complexity. For a Vietnamese engineering student building an AI code mentor, this provides the technical depth needed to compete with commercial tools while maintaining open-source accessibility.