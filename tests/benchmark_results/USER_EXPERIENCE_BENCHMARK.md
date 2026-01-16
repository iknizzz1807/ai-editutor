# ai-editutor User Experience Benchmark

**Generated:** 2026-01-16 22:50:10

This benchmark simulates **REAL user experience**:
- Opens actual source files in Neovim buffers
- Places cursor at various lines (spread throughout files)
- Asks diverse question types (concept, review, debug, howto, understand)
- Records what context would be sent to LLM
- Tests across 50 repositories, ~20 questions each

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total Test Cases | 854 |
| Successful | 854 (100%) |
| Errors | 0 |
| **Full Project Mode** | 56 (7%) |
| **LSP Selective Mode** | 798 (93%) |
| Within Budget (20K) | 714 (84%) |
| Had LSP Available | 0 (0%) |
| **Avg Tokens per Query** | 14.7K |
| Avg External Files (LSP) | 0.0 |

## Results by Project Size

| Size | Tests | Full Project | LSP Selective | Avg Tokens | Within Budget |
|------|-------|--------------|---------------|------------|---------------|
| small | 118 | 38 (32%) | 80 (68%) | 4.7K | 116 (98%) |
| medium | 512 | 18 (4%) | 494 (96%) | 7.2K | 506 (99%) |
| large | 224 | 0 (0%) | 224 (100%) | 36.9K | 92 (41%) |

## Results by Language

| Language | Tests | Full Project | LSP Selective | Avg Tokens | Within Budget |
|----------|-------|--------------|---------------|------------|---------------|
| c | 40 | 0 | 40 | 10.7K | 38 (95%) |
| cpp | 40 | 0 | 40 | 6.9K | 40 (100%) |
| go | 120 | 0 | 120 | 6.0K | 120 (100%) |
| java | 38 | 0 | 38 | 9.9K | 38 (100%) |
| javascript | 134 | 56 | 78 | 32.6K | 110 (82%) |
| kotlin | 20 | 0 | 20 | 13.6K | 20 (100%) |
| lua | 60 | 0 | 60 | 2.3K | 60 (100%) |
| php | 40 | 0 | 40 | 23.1K | 18 (45%) |
| python | 132 | 0 | 132 | 11.6K | 100 (76%) |
| ruby | 58 | 0 | 58 | 29.9K | 20 (34%) |
| rust | 98 | 0 | 98 | 6.5K | 98 (100%) |
| typescript | 74 | 0 | 74 | 15.2K | 52 (70%) |

## Results by Question Type

| Question Type | Tests | Avg Tokens |
|---------------|-------|------------|
| review | 421 | 14.8K |
| debug | 421 | 14.8K |
| howto | 12 | 3.1K |

## Sample Context Previews

Examples showing what would be sent to LLM:

### Full Project Mode Example

**Repo:** clsx | **File:** test/lite.js | **Line:** 15

**Question:** Rate this code (review)

**Tokens:** 5.5K | **External Files:** 0

```
=== CURRENT FILE (question location) ===
// File: clsx/test/lite.js (line 15 is where the question was asked)
```javascript
       1: // @ts-check
       2: import { test } from 'uvu';
       3: import * as assert from 'uvu/assert';
       4: import * as mod from '../src/lite';
       5: 
       6: const fn = mod.default;
       7: 
       8: test('exports', () => {
       9: 	assert.type(mod.default, 'function', 'exports default function');
      10: 	assert.type(mod.clsx, 'function', 'exports named function');
      11: 	assert.is(mod.default, mod.clsx, 'exports are equal');
      12: 
      13: 	assert.type(mod.default(), 'string', '~> returns string output');
      14: 	assert.type(mod.clsx(), 'string', '~> returns string output');
>>>   15: });
      16: 
      17: test('strings', () => {
      18: 	assert.is(fn(''), '');
      19: 	assert.is(fn('foo'), 'foo');
      20: 	assert.is(fn(true && 'foo'), 'foo');
      21: 	assert.is(fn(false && 'foo'), '');
      22: });
      23: 
  
```

### LSP Selective Mode Example

**Repo:** hyperapp | **File:** tests/index.test.js | **Line:** 7

**Question:** Rate this code (review)

**Tokens:** 547 | **External Files:** 0

```
=== Current File ===
// File: hyperapp//tmp/editutor-ux-test/hyperapp/tests/index.test.js (31 lines)
```javascript
import { h, text } from "../index.js"
import { t, deepEqual } from "twist"

export default [
  t("hyperapp", [
    t("hyperscript function", [
      t("create virtual nodes", [
        deepEqual(h("zord", { foo: true }, []), {
          children: [],
          key: undefined,
          node: undefined,
          props: {
            foo: true,
          },
          type: undefined,
          tag: "zord",
        }),
      ]),
    ]),
    t("text function", [
      deepEqual(text("hyper"), {
        children: [],
        key: undefined,
        node: undefined,
        props: {},
        type: 3,
        tag: "hyper",
      }),
    ]),
  ]),
]
```

[Note: LSP not available - showing only current file context]

=== PROJECT STRUCTURE ===
```
hyperapp/
|-- .github/
|   `-- workflows/
|       `-- ci.yml (23 lines)
|-- docs/
|   |-- api/
|   |   |-- app.md (163 lines)
|   |   |
```

## Issues Found

| Issue | Count |
|-------|-------|
| Errors (file not found, etc.) | 0 |
| Over Token Budget | 140 |
| No LSP (limited context) | 658 |

## Per-Repository Summary

| Repository | Lang | Size | Tests | Mode | Avg Tokens | Budget |
|------------|------|------|-------|------|------------|--------|
| alacritty | rust | medium | 20 | LSP | 4.1K | 20/20 |
| bat | rust | medium | 18 | LSP | 7.0K | 18/18 |
| berry | typescript | large | 20 | LSP | 19.6K | 16/20 |
| black | python | medium | 20 | LSP | 6.1K | 20/20 |
| brew | ruby | large | 20 | LSP | 22.7K | 0/20 |
| bubbletea | go | medium | 20 | LSP | 3.2K | 20/20 |
| chalk | javascript | medium | 18 | FULL | 12.5K | 18/18 |
| cli | python | medium | 20 | LSP | 3.7K | 20/20 |
| click | python | medium | 20 | LSP | 2.1K | 20/20 |
| clsx | javascript | small | 20 | FULL | 5.5K | 20/20 |
| core | typescript | large | 16 | LSP | 7.9K | 16/16 |
| django | python | large | 14 | LSP | 43.8K | 0/14 |
| esbuild | go | large | 20 | LSP | 5.7K | 20/20 |
| express | javascript | medium | 18 | LSP | 3.2K | 18/18 |
| fastapi | python | large | 18 | LSP | 30.2K | 0/18 |
| fd | rust | medium | 20 | LSP | 4.3K | 20/20 |
| fiber | go | medium | 20 | LSP | 7.9K | 20/20 |
| flask | python | medium | 20 | LSP | 3.6K | 20/20 |
| formik | typescript | medium | 20 | LSP | 3.9K | 20/20 |
| framework | php | large | 20 | LSP | 43.4K | 0/20 |
| fzf | go | medium | 20 | LSP | 1.5K | 20/20 |
| gin | go | medium | 20 | LSP | 3.9K | 20/20 |
| hyperapp | javascript | small | 20 | LSP | 997.3 | 20/20 |
| jekyll | ruby | medium | 20 | LSP | 9.2K | 20/20 |
| jq | c | medium | 20 | LSP | 5.8K | 18/20 |
| json | cpp | medium | 20 | LSP | 10.9K | 20/20 |
| laravel | php | small | 20 | LSP | 2.9K | 18/20 |
| lazy.nvim | lua | medium | 20 | LSP | 1.8K | 20/20 |
| lazygit | go | large | 20 | LSP | 13.6K | 20/20 |
| lodash | javascript | medium | 20 | LSP | 37.6K | 16/20 |
| nanoid | javascript | small | 18 | FULL | 14.1K | 18/18 |
| nest | typescript | large | 18 | LSP | 29.5K | 0/18 |
| okhttp | kotlin | medium | 20 | LSP | 13.6K | 20/20 |
| plenary.nvim | lua | medium | 20 | LSP | 2.9K | 20/20 |
| rails | ruby | large | 18 | LSP | 60.8K | 0/18 |
| redis | c | large | 20 | LSP | 15.7K | 20/20 |
| retrofit | java | medium | 18 | LSP | 18.2K | 18/18 |
| ripgrep | rust | medium | 20 | LSP | 6.3K | 20/20 |
| spdlog | cpp | medium | 20 | LSP | 3.0K | 20/20 |
| spring-petclinic | java | small | 20 | LSP | 2.5K | 20/20 |
| starship | rust | medium | 20 | LSP | 10.6K | 20/20 |
| svelte | javascript | large | 20 | LSP | 147.3K | 0/20 |
| telescope.nvim | lua | medium | 20 | LSP | 2.2K | 20/20 |
| tqdm | python | small | 20 | LSP | 3.5K | 20/20 |
