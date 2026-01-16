# ai-editutor Benchmark Results

Generated: 2026-01-16 22:21:32

Token Budget: 20.0K

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total Repos | 52 |
| Successful | 51 |
| Failed | 1 |
| Full Project Mode | 5 (10%) |
| LSP Selective Mode | 46 (90%) |

### Mode Distribution by Expected Size

| Expected Size | Repos | Full Project | LSP Selective |
|---------------|-------|--------------|---------------|
| small | 6 | 3 | 3 |
| medium | 30 | 2 | 28 |
| large | 15 | 0 | 15 |

### By Language

| Language | Repos | Avg Tokens | Full Project | LSP Selective |
|----------|-------|------------|--------------|---------------|
| C | 3 | 1.5M | 0 | 3 |
| C++ | 2 | 442.1K | 0 | 2 |
| Go | 5 | 426.5K | 0 | 5 |
| Java | 3 | 2.6M | 0 | 3 |
| JavaScript | 8 | 530.5K | 5 | 3 |
| Kotlin | 2 | 12.1M | 0 | 2 |
| Lua | 2 | 113.3K | 0 | 2 |
| PHP | 2 | 1.5M | 0 | 2 |
| Python | 10 | 2.8M | 0 | 10 |
| Ruby | 3 | 2.1M | 0 | 3 |
| Rust | 5 | 364.0K | 0 | 5 |
| TypeScript | 6 | 2.2M | 0 | 6 |

## Detailed Results

| # | Repository | Lang | Expected | Mode | Files | Lines | Tokens | Time |
|---|------------|------|----------|------|-------|-------|--------|------|
| 1 | is-odd | JavaScript | small | FULL | 10 | 432 | 2.8K | 0ms |
| 2 | minimist | JavaScript | small | FULL | 28 | 1.7K | 9.2K | 0ms |
| 3 | nanoid | JavaScript | medium | FULL | 24 | 1.8K | 12.9K | 0ms |
| 4 | clsx | JavaScript | small | FULL | 14 | 732 | 4.6K | 0ms |
| 5 | hyperapp | JavaScript | medium | LSP | 35 | 3.9K | 40.6K | 0ms |
| 6 | express | JavaScript | medium | LSP | 192 | 22.3K | 143.0K | 0ms |
| 7 | koa | JavaScript | medium | ERROR | - | - | - | - |
| 8 | chalk | JavaScript | medium | FULL | 20 | 1.6K | 11.4K | 0ms |
| 9 | date-fns | TypeScript | large | LSP | 1713 | 152.5K | 2.5M | 0ms |
| 10 | formik | TypeScript | medium | LSP | 239 | 21.6K | 170.2K | 0ms |
| 11 | core | TypeScript | large | LSP | 626 | 130.3K | 909.7K | 0ms |
| 12 | angular | TypeScript | large | LSP | 8321 | 893.4K | 7.4M | 0ms |
| 13 | react | JavaScript | large | LSP | 6662 | 583.2K | 4.0M | 0ms |
| 14 | nest | TypeScript | large | LSP | 2087 | 119.4K | 896.4K | 0ms |
| 15 | prisma | TypeScript | large | LSP | 3782 | 210.5K | 1.6M | 0ms |
| 16 | black | Python | medium | LSP | 402 | 44.8K | 326.0K | 0ms |
| 17 | poetry | Python | medium | LSP | 688 | 70.1K | 579.6K | 0ms |
| 18 | click | Python | medium | LSP | 134 | 23.2K | 182.5K | 0ms |
| 19 | cli | Python | medium | LSP | 213 | 21.9K | 166.1K | 0ms |
| 20 | tqdm | Python | small | LSP | 90 | 10.1K | 82.8K | 0ms |
| 21 | django | Python | large | LSP | 3400 | 362.5K | 3.2M | 0ms |
| 22 | fastapi | Python | medium | LSP | 2339 | 251.8K | 2.6M | 0ms |
| 23 | flask | Python | medium | LSP | 208 | 30.6K | 255.5K | 0ms |
| 24 | scrapy | Python | large | LSP | 513 | 91.2K | 788.1K | 0ms |
| 25 | pytorch | Python | large | LSP | 9830 | 2.2M | 19.5M | 0ms |
| 26 | ripgrep | Rust | medium | LSP | 142 | 39.3K | 343.2K | 0ms |
| 27 | fd | Rust | medium | LSP | 41 | 6.6K | 56.6K | 0ms |
| 28 | bat | Rust | medium | LSP | 284 | 28.5K | 406.4K | 0ms |
| 29 | starship | Rust | medium | LSP | 704 | 88.1K | 762.0K | 0ms |
| 30 | alacritty | Rust | medium | LSP | 209 | 29.7K | 252.0K | 0ms |
| 31 | gin | Go | medium | LSP | 116 | 20.6K | 158.1K | 0ms |
| 32 | fiber | Go | medium | LSP | 352 | 82.9K | 600.2K | 0ms |
| 33 | fzf | Go | medium | LSP | 112 | 23.2K | 172.1K | 0ms |
| 34 | lazygit | Go | medium | LSP | 1012 | 128.3K | 1.1M | 0ms |
| 35 | bubbletea | Go | medium | LSP | 152 | 15.8K | 99.2K | 0ms |
| 36 | spring-petclinic | Java | small | LSP | 89 | 6.1K | 51.0K | 0ms |
| 37 | guava | Java | large | LSP | 3278 | 710.6K | 6.4M | 0ms |
| 38 | okhttp | Kotlin | medium | LSP | 712 | 117.1K | 948.6K | 0ms |
| 39 | retrofit | Java | medium | LSP | 971 | 142.2K | 1.3M | 0ms |
| 40 | kotlin | Kotlin | large | LSP | 54393 | 2.6M | 23.2M | 0ms |
| 41 | jq | C | medium | LSP | 89 | 19.2K | 146.5K | 0ms |
| 42 | redis | C | large | LSP | 1376 | 224.4K | 1.8M | 0ms |
| 43 | curl | C | large | LSP | 2060 | 321.1K | 2.5M | 0ms |
| 44 | json | C++ | medium | LSP | 793 | 77.4K | 679.3K | 0ms |
| 45 | spdlog | C++ | medium | LSP | 163 | 23.5K | 205.0K | 0ms |
| 46 | rails | Ruby | large | LSP | 4283 | 505.8K | 4.2M | 0ms |
| 47 | jekyll | Ruby | medium | LSP | 637 | 44.9K | 368.1K | 0ms |
| 48 | brew | Ruby | medium | LSP | 1691 | 184.9K | 1.6M | 0ms |
| 49 | laravel | PHP | small | LSP | 55 | 2.4K | 36.9K | 0ms |
| 50 | framework | PHP | large | LSP | 2856 | 388.9K | 2.9M | 0ms |
| 51 | lazy.nvim | Lua | medium | LSP | 89 | 13.1K | 88.3K | 0ms |
| 52 | plenary.nvim | Lua | medium | LSP | 123 | 19.7K | 138.3K | 0ms |

## Sample Tree Structures

### Small Project (Full Project Mode): is-odd

- **Files:** 10
- **Lines:** 432
- **Tokens:** 2.8K
- **Mode:** full_project

```
is-odd/
|-- .editorconfig (14 lines)
|-- .eslintrc.json (130 lines)
|-- .gitattributes (10 lines)
|-- .gitignore (30 lines)
|-- .travis.yml (14 lines)
|-- .verb.md (13 lines)
|-- README.md (94 lines)
|-- index.js (25 lines)
|-- package.json (67 lines)
`-- test.js (35 lines)
```

### Medium Project: nanoid

- **Files:** 24
- **Lines:** 1.8K
- **Tokens:** 12.9K
- **Mode:** full_project

```
nanoid/
|-- .github/
|   `-- workflows/
|       |-- jsr.yml (26 lines)
|       |-- release.yml (44 lines)
|       `-- test.yml (73 lines)
|-- img/  (3 files)
|-- non-secure/
|   |-- index.d.ts (48 lines)
|   `-- index.js (34 lines)
|-- test/
|   |-- demo/
|   |   |-- index.html (47 lines)
|   |   |-- index.js (100 lines)
|   |   `-- vite.config.js (5 lines)
|   |-- benchmark.js (86 lines)
|   |-- bin.test.js (55 lines)
|   |-- index.test.js (224 lines)
|   |-- non-secure.test.js (107 lines)
|   `-- update-prebuild.js (21 lines)
|-- url-alphabet/
|   `-- index.js (5 lines)
|-- .editorconfig (9 lines)
|-- .gitignore (3 lines)
|-- README.md (500 lines)
|-- eslint.config.js (14 lines)
|-- index.browser.js (64 lines)
|-- index.d.ts (106 lines)
|-- index.js (87 lines)
|-- jsr.json (20 lines)
|-- nanoid.js (1 lines)
`-- package.json (132 lines)
```

### Large Project (LSP Selective Mode): date-fns

- **Files:** 1713
- **Lines:** 152.5K
- **Tokens:** 2.5M
- **Mode:** lsp_selective

```
date-fns/
|-- .devcontainer/
|   |-- scripts/
|   |   |-- on-create.sh (7 lines)
|   |   |-- on-update.sh (31 lines)
|   |   `-- post-create.sh (7 lines)
|   |-- Dockerfile (6 lines)
|   `-- devcontainer.json (50 lines)
|-- .github/
|   |-- ISSUE_TEMPLATE/
|   |   `-- issue-report.md (28 lines)
|   `-- workflows/
|       |-- attw_tests.yaml (20 lines)
|       |-- browser_tests.yaml (24 lines)
|       |-- code_quality.yaml (27 lines)
|       |-- coverage.yaml (21 lines)
|       |-- node_tests.yaml (28 lines)
|       |-- smoke_tests.yaml (28 lines)
|       `-- tz_tests.yaml (22 lines)
|-- codemods/
|   `-- expectify.js (257 lines)
|-- docs/
|   |-- cdn.md (111 lines)
|   |-- config.d.ts (2 lines)
|   |-- config.js (135 lines)
|   |-- fp.md (72 lines)
|   |-- gettingStarted.md (76 lines)
|   |-- i18n.md (91 lines)
|   |-- i18nContributionGuide.md (1059 lines)
|   |-- release.md (19 lines)
|   |-- timeZones.md (127 lines)
|   |-- unicodeTokens.md (54 lines)
|   `-- webpack.md (53 lines)
|-- examples/
|   |-- cdn/
|   |   |-- README.md (5 lines)
|   |   |-- basic.js (8 lines)
|   |   |-- dom.js (35 lines)
|   |   |-- fp.js (8 lines)
|   |   |-- locale.js (8 lines)
|   |   |-- locales.js (14 lines)
|   |   `-- package.json (21 lines)
|   |-- lodash-fp/
|   |   |-- .babelrc (3 lines)
|   |   |-- README.md (23 lines)
|   |   |-- example.js (25 lines)
|   |   `-- package.json (20 lines)
|   |-- node-esm/
|   |   |-- README.md (5 lines)
|   |   |-- constants.js (3 lines)
... (2992 more lines)
```

## Top 10 by Token Count

| # | Repository | Tokens | Files | Mode |
|---|------------|--------|-------|------|
| 1 | kotlin | 23.2M | 54393 | lsp_selective |
| 2 | pytorch | 19.5M | 9830 | lsp_selective |
| 3 | angular | 7.4M | 8321 | lsp_selective |
| 4 | guava | 6.4M | 3278 | lsp_selective |
| 5 | rails | 4.2M | 4283 | lsp_selective |
| 6 | react | 4.0M | 6662 | lsp_selective |
| 7 | django | 3.2M | 3400 | lsp_selective |
| 8 | framework | 2.9M | 2856 | lsp_selective |
| 9 | fastapi | 2.6M | 2339 | lsp_selective |
| 10 | curl | 2.5M | 2060 | lsp_selective |

## Top 10 Smallest (Best Full Project Candidates)

| # | Repository | Tokens | Files | Mode |
|---|------------|--------|-------|------|
| 1 | is-odd | 2.8K | 10 | full_project |
| 2 | clsx | 4.6K | 14 | full_project |
| 3 | minimist | 9.2K | 28 | full_project |
| 4 | chalk | 11.4K | 20 | full_project |
| 5 | nanoid | 12.9K | 24 | full_project |
| 6 | laravel | 36.9K | 55 | lsp_selective |
| 7 | hyperapp | 40.6K | 35 | lsp_selective |
| 8 | spring-petclinic | 51.0K | 89 | lsp_selective |
| 9 | fd | 56.6K | 41 | lsp_selective |
| 10 | tqdm | 82.8K | 90 | lsp_selective |

## File Extension Distribution

| Extension | Count |
|-----------|-------|
