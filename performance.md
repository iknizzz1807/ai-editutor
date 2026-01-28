# Context Extraction Performance Report

## Testing Methodology

Test suite clones **real open-source repositories** and generates **real programming questions** at specific code locations. The context extraction system is then evaluated on how well it gathers relevant code context for each question.

### Test Setup
- **797 test cases** across 9 programming languages
- **50+ real repositories** (Django, React, Rust, Go, Zig, etc.)
- Questions target specific patterns: decorators, error handling, async/await, generics, etc.
- Each test measures: tokens extracted, files included, extraction time, library info gathered

### Repositories Tested
Django, Flask, FastAPI, Celery, Pandas, Scikit-learn, Transformers, React, Next.js, Express, Lodash, Zod, Svelte, Tokio, Axum, Serde, Clap, Ripgrep, Zig, ZLS, TigerBeetle, Ghostty, Neovim plugins, and many more.

---

## Results Summary

| Metric | Value |
|--------|-------|
| **Total test cases** | 769 |
| **Pass rate** | 100% |
| **Languages covered** | 9 |
| **Avg tokens/case** | 13,774 |
| **Avg files/case** | 13.5 |
| **Avg extraction time** | 1,862ms |

---

## Results by Language

| Language | Test Cases | Avg Tokens | Avg Files | With Library Info |
|----------|------------|------------|-----------|-------------------|
| Python | 184 | - | - | 92% |
| TypeScript | 111 | - | - | 38% |
| Rust | 108 | - | - | 66% |
| Go | 95 | - | - | 26% |
| Lua | 81 | - | - | 74% |
| C++ | 60 | - | - | 72% |
| C | 50 | - | - | 26% |
| Zig | 40 | - | - | 82% |
| JavaScript | 40 | - | - | 68% |

---

## Token Budget Compliance

The system enforces a **25,000 token budget** (21,000 for code + 2,000 for library info + 2,000 for diagnostics).

| Metric | Value |
|--------|-------|
| Min tokens | 939 |
| Max tokens | 23,494 |
| Avg tokens | 13,774 |
| Median tokens | 15,343 |
| **Budget compliance** | **100%** |

### Token Distribution

| Range | Count | Percentage |
|-------|-------|------------|
| ≤5,000 tokens | 85 | 11.6% |
| 5,001-15,000 tokens | 234 | 31.9% |
| 15,001-21,000 tokens | 364 | 49.7% |
| >21,000 tokens | 50 | 6.8% |

All cases above 21,000 tokens remain within the total 25,000 budget when accounting for library info and diagnostics separately.

---

## File Inclusion Analysis

The context extraction includes related files through import graph analysis (outgoing imports, incoming imports, transitive dependencies).

| Range | Count | Percentage |
|-------|-------|------------|
| Single file | 27 | 3.7% |
| 2-5 files | 106 | 14.5% |
| 6-15 files | 337 | 46.0% |
| >15 files | 263 | 35.9% |

| Metric | Value |
|--------|-------|
| Min files | 1 |
| Max files | 54 |
| Avg files | 13.5 |

### Single-File Cases Breakdown

27 cases extracted only 1 file. These are legitimate isolated files:

| Repository | Count | Reason |
|------------|-------|--------|
| rustlings | 10 | Educational exercises (intentionally isolated) |
| googletest | 10 | Header-only template library |
| zig (langref) | 4 | Standalone documentation examples |
| nvim-treesitter | 2 | Independent Lua modules |
| containerd | 1 | Go doc.go file |

---

## Library Info Extraction

The system extracts hover documentation for library/framework APIs found near question locations via LSP.

| Language | Cases | With Library Info | Avg Items/Case |
|----------|-------|-------------------|----------------|
| Python | 184 | 92% | 7.9 |
| Zig | 40 | 82% | 3.5 |
| Lua | 81 | 74% | 2.3 |
| C++ | 60 | 72% | 1.8 |
| JavaScript | 40 | 68% | 2.3 |
| Rust | 108 | 66% | 2.4 |
| TypeScript | 111 | 38% | 0.8 |
| Go | 95 | 26% | 0.4 |
| C | 50 | 26% | 0.4 |

Python shows highest library info extraction (92%) due to heavy use of external packages (pandas, numpy, django, etc.).

---

## Extraction Performance

| Metric | Value |
|--------|-------|
| Min extraction time | 126ms |
| Max extraction time | 17,829ms |
| Avg extraction time | 1,862ms |
| Total extraction time | 22.7 minutes |

The slowest case (lodash, 17.8s) was due to LSP server startup time. Typical cases complete in 1-2 seconds.

---

## LSP Integration

| Metric | Value |
|--------|-------|
| LSP available | 769/769 (100%) |
| LSP timeouts | 0 |
| LSP clients used | pyright, ruff, rust_analyzer, gopls, zls, tsserver, clangd, lua_ls |

---

## Strategy Level

The context extraction uses a 7-level backtracking strategy:
1. maximum
2. semantic_all
3. depth1_with_lsp
4. depth1_no_lsp
5. limited_imports
6. types_only
7. minimal

| Strategy | Cases | Percentage |
|----------|-------|------------|
| maximum | 769 | 100% |

All cases fit within budget at the maximum strategy level - no backtracking needed.

---

## Sample Test Cases

### Python (Django)
```
File: django/apps/config.py
Question: How does the @cached_property decorator work?
Result: 10 files, 15,274 tokens, 3,409ms
```

### Rust (Tokio)
```
File: tokio/src/sync/mutex.rs
Question: How does Tokio's async Mutex differ from std::sync::Mutex?
Result: 12 files, 18,500 tokens, 1,765ms
```

### Zig (ZLS)
```
File: zls/src/analyser/string_pool.zig
Question: How does Zig's comptime evaluation allow this data structure to be configured?
Result: 18 files, 12,938 tokens, 1,785ms
```

### Go (Containerd)
```
File: containerd/api/events/container.go
Question: How does the container event system work?
Result: 8 files, 14,200 tokens, 1,650ms
```

---

## Conclusion

The context extraction system demonstrates:

- **100% pass rate** across 769 real-world test cases
- **100% budget compliance** - all extractions within 25K token limit
- **Rich context** - average 13.5 files per extraction
- **Fast performance** - average 1.8 seconds per extraction
- **Strong LSP integration** - 100% LSP availability
- **Effective library detection** - especially for Python (92%) and Zig (82%)

The system successfully handles diverse codebases from small educational repos (rustlings) to large production systems (Django, Transformers, Tokio).
