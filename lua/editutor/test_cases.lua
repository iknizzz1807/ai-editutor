-- editutor/test_cases.lua
-- Curated test cases for ai-editutor automated testing
-- Each case has specific file, line range, and contextual question

local M = {}

M.REPOS_DIR = vim.fn.expand("~/.cache/editutor-tests/repos")

-- =============================================================================
-- Test Case Structure
-- =============================================================================
-- {
--   repo = "repo_name",
--   lang = "language",
--   file = "relative/path/to/file",
--   lines = {start, end},  -- Line range for context
--   question = "Specific contextual question",
--   pattern = "What pattern this tests (for categorization)",
-- }

M.TEST_CASES = {
  -- ===========================================================================
  -- JavaScript/TypeScript
  -- ===========================================================================
  {
    repo = "zod",
    lang = "typescript",
    file = "packages/zod/src/v3/types.ts",
    lines = {62, 85},
    question = "Why does ParseInputLazyPath use a getter with caching instead of computing the path immediately in the constructor?",
    pattern = "lazy_evaluation",
  },
  {
    repo = "zod",
    lang = "typescript",
    file = "packages/zod/src/v3/types.ts",
    lines = {210, 221},
    question = "How does zod distinguish between synchronous and asynchronous parsing, and why wrap the result in Promise.resolve() in _parseAsync?",
    pattern = "async_handling",
  },
  {
    repo = "zustand",
    lang = "typescript",
    file = "src/vanilla.ts",
    lines = {60, 96},
    question = "Why does zustand use Object.is() for state comparison instead of checking if nextState !== state, and how does this impact re-render behavior?",
    pattern = "state_management",
  },
  {
    repo = "zustand",
    lang = "typescript",
    file = "src/middleware/persist.ts",
    lines = {31, 61},
    question = "Why does this function wrap the getStorage() call in a try-catch that returns undefined, and how does this handle server-side rendering scenarios?",
    pattern = "error_handling",
  },
  {
    repo = "axios",
    lang = "javascript",
    file = "lib/core/InterceptorManager.js",
    lines = {19, 40},
    question = "Why does eject() set handlers[id] to null instead of removing it from the array, and how does the forEach() method handle this?",
    pattern = "interceptor_pattern",
  },
  {
    repo = "axios",
    lang = "javascript",
    file = "lib/core/Axios.js",
    lines = {38, 63},
    question = "Why does this error handler manipulate the stack trace property, and what problem does appending the stack trace of a fresh Error solve?",
    pattern = "error_handling",
  },
  {
    repo = "express",
    lang = "javascript",
    file = "lib/application.js",
    lines = {59, 83},
    question = "Why does Express use a lazy-loaded router as a getter property instead of creating it immediately, and what architectural benefit does this provide?",
    pattern = "lazy_initialization",
  },
  {
    repo = "express",
    lang = "javascript",
    file = "lib/request.js",
    lines = {30, 79},
    question = "Why does Express create a custom object that inherits from IncomingMessage.prototype instead of directly extending it, and why special-case the Referer/Referrer headers?",
    pattern = "prototype_inheritance",
  },

  -- ===========================================================================
  -- Python
  -- ===========================================================================
  {
    repo = "fastapi",
    lang = "python",
    file = "fastapi/dependencies/utils.py",
    lines = {357, 524},
    question = "Why does the analyze_param function need to handle both Annotated and default value approaches for parameter metadata? What would happen if someone specified both?",
    pattern = "dependency_injection",
  },
  {
    repo = "fastapi",
    lang = "python",
    file = "fastapi/dependencies/utils.py",
    lines = {543, 551},
    question = "How does wrapping a sync contextmanager with contextmanager_in_threadpool allow it to work in an async context? Why is this necessary?",
    pattern = "async_context_manager",
  },
  {
    repo = "requests",
    lang = "python",
    file = "src/requests/adapters.py",
    lines = {200, 214},
    question = "Why can't poolmanager with its lambda function be pickled, and how does reinitializing it in __setstate__ solve the problem without losing state?",
    pattern = "serialization",
  },
  {
    repo = "requests",
    lang = "python",
    file = "src/requests/adapters.py",
    lines = {242, 278},
    question = "This method returns either a cached manager or creates a new SOCKS or HTTP proxy manager. How would you extend this to support additional proxy types?",
    pattern = "factory_pattern",
  },
  {
    repo = "pydantic",
    lang = "python",
    file = "pydantic/_internal/_model_construction.py",
    lines = {82, 156},
    question = "Why does Pydantic need special handling for Python 3.14's annotationlib and call_annotate_function? What changed between Python versions?",
    pattern = "metaclass",
  },
  {
    repo = "click",
    lang = "python",
    file = "src/click/decorators.py",
    lines = {51, 97},
    question = "How does the `ensure` parameter change the behavior of the decorator? When would you use ensure=True vs ensure=False?",
    pattern = "decorator_factory",
  },
  {
    repo = "click",
    lang = "python",
    file = "src/click/parser.py",
    lines = {51, 75},
    question = "Why use deques instead of lists for args and nargs_spec? What's the purpose of the nested _fetch function?",
    pattern = "argument_parsing",
  },

  -- ===========================================================================
  -- Rust
  -- ===========================================================================
  {
    repo = "fd",
    lang = "rust",
    file = "src/walk.rs",
    lines = {48, 72},
    question = "Why use IntoIterator trait instead of providing iter() method directly? What are the performance implications of Arc<Mutex<Option<Vec<>>>>?",
    pattern = "trait_implementation",
  },
  {
    repo = "fd",
    lang = "rust",
    file = "src/dir_entry.rs",
    lines = {80, 102},
    question = "Why does partial_cmp always return Some() instead of None? How does OnceCell ensure thread safety without Arc?",
    pattern = "lazy_initialization",
  },
  {
    repo = "ripgrep",
    lang = "rust",
    file = "crates/cli/src/process.rs",
    lines = {21, 79},
    question = "Why implement both Error trait and From conversion separately? How does String::from_utf8_lossy handle invalid UTF-8 gracefully?",
    pattern = "error_handling",
  },
  {
    repo = "ripgrep",
    lang = "rust",
    file = "crates/cli/src/process.rs",
    lines = {246, 268},
    question = "How does the Drop implementation prevent resource leaks? Why return Ok(0) when nread == 0 instead of propagating the close error?",
    pattern = "resource_management",
  },
  {
    repo = "axum",
    lang = "rust",
    file = "axum/src/json.rs",
    lines = {99, 114},
    question = "Why is the Content-Type check done before awaiting Bytes::from_request? How does the where clause constrain the generic types?",
    pattern = "async_trait",
  },
  {
    repo = "axum",
    lang = "rust",
    file = "axum/src/extension.rs",
    lines = {169, 187},
    question = "Why delegate Service trait methods instead of implementing custom polling logic? How do associated types enable zero-cost abstraction?",
    pattern = "service_pattern",
  },
  {
    repo = "tokio",
    lang = "rust",
    file = "tokio/src/fs/file.rs",
    lines = {152, 194},
    question = "Why use impl AsRef<Path> instead of &Path directly? How does .await at different points in the chain affect the Future semantics?",
    pattern = "async_io",
  },

  -- ===========================================================================
  -- Go
  -- ===========================================================================
  {
    repo = "gin",
    lang = "go",
    file = "context.go",
    lines = {275, 283},
    question = "How does Gin prevent concurrent map access panics while maintaining performance?",
    pattern = "concurrency",
  },
  {
    repo = "gin",
    lang = "go",
    file = "render/render.go",
    lines = {9, 34},
    question = "Why use blank assignments for interface implementation verification?",
    pattern = "interface_check",
  },
  {
    repo = "gin",
    lang = "go",
    file = "recovery.go",
    lines = {34, 80},
    question = "How do you implement middleware patterns with type-wrapped handlers?",
    pattern = "middleware",
  },
  {
    repo = "cobra",
    lang = "go",
    file = "command.go",
    lines = {117, 146},
    question = "What's the pattern for providing optional error handling in Go with function pointers?",
    pattern = "lifecycle_hooks",
  },
  {
    repo = "bubbletea",
    lang = "go",
    file = "tea.go",
    lines = {39, 65},
    question = "How does Bubble Tea implement the Elm Architecture in Go?",
    pattern = "elm_architecture",
  },
  {
    repo = "fzf",
    lang = "go",
    file = "src/reader.go",
    lines = {51, 73},
    question = "Why use atomic operations instead of mutexes for simple state changes?",
    pattern = "atomics",
  },

  -- ===========================================================================
  -- Lua/Neovim
  -- ===========================================================================
  {
    repo = "lazy.nvim",
    lang = "lua",
    file = "lua/lazy/async.lua",
    lines = {1, 46},
    question = "How does lazy.nvim manage coroutine execution with a time budget (M.BUDGET = 10ms)? What prevents CPU overload?",
    pattern = "coroutine_scheduler",
  },
  {
    repo = "lazy.nvim",
    lang = "lua",
    file = "lua/lazy/core/handler/event.lua",
    lines = {65, 95},
    question = "Why use the `done` variable pattern instead of just `once=true`? How does lazy.nvim handle cascading event triggers?",
    pattern = "event_handling",
  },
  {
    repo = "telescope.nvim",
    lang = "lua",
    file = "lua/telescope/debounce.lua",
    lines = {33, 48},
    question = "What is the significance of using `pcall()` around `vim.schedule_wrap(fn)`? How does wrapping errors protect the picker?",
    pattern = "debounce",
  },
  {
    repo = "nvim-cmp",
    lang = "lua",
    file = "lua/cmp/utils/async.lua",
    lines = {177, 202},
    question = "How does nvim-cmp prevent completion from blocking the UI? What happens when sources complete faster than the budget allows?",
    pattern = "async_scheduler",
  },
  {
    repo = "plenary.nvim",
    lang = "lua",
    file = "lua/plenary/async/control.lua",
    lines = {7, 40},
    question = "How does a Condvar block without actually blocking Neovim? What makes notify_all() safe from starvation?",
    pattern = "condvar",
  },
  {
    repo = "plenary.nvim",
    lang = "lua",
    file = "lua/plenary/job.lua",
    lines = {23, 62},
    question = "Why use a check handle that polls for pipe closure instead of waiting synchronously? How does this prevent blocking Neovim?",
    pattern = "job_control",
  },

  -- ===========================================================================
  -- Zig
  -- ===========================================================================
  {
    repo = "zls",
    lang = "zig",
    file = "src/analyser/InternPool.zig",
    lines = {1547, 1589},
    question = "How does the comptime type checking and inline field iteration prevent runtime type mismatches?",
    pattern = "comptime",
  },
  {
    repo = "zls",
    lang = "zig",
    file = "src/analyser/string_pool.zig",
    lines = {56, 98},
    question = "Why does the catch block attempt recovery even after allocation failure?",
    pattern = "error_handling",
  },
  {
    repo = "ghostty",
    lang = "zig",
    file = "src/termio/Termio.zig",
    lines = {83, 107},
    question = "Why use ArenaAllocator for thread-local initialization state instead of linear cleanup?",
    pattern = "memory_management",
  },
  {
    repo = "ghostty",
    lang = "zig",
    file = "src/termio/Exec.zig",
    lines = {47, 59},
    question = "How does errdefer cascade handle nested initialization failures?",
    pattern = "errdefer",
  },

  -- ===========================================================================
  -- C/C++
  -- ===========================================================================
  {
    repo = "jq",
    lang = "c",
    file = "src/jv.h",
    lines = {100, 112},
    question = "What is the pattern for variadic macro overloading in C, and why does jq use this technique for array construction?",
    pattern = "variadic_macro",
  },
  {
    repo = "jq",
    lang = "c",
    file = "src/execute.c",
    lines = {56, 78},
    question = "How does jq use union-based frame entries to unify closures and local variables, and what memory layout considerations does this impose?",
    pattern = "union_variant",
  },
  {
    repo = "redis",
    lang = "c",
    file = "src/adlist.c",
    lines = {26, 34},
    question = "Why does Redis use function pointers (dup, free, match) in list nodes instead of fixed operations?",
    pattern = "callback_pattern",
  },
  {
    repo = "redis",
    lang = "c",
    file = "src/zmalloc.h",
    lines = {18, 42},
    question = "How does Redis abstract allocator implementations at compile-time, and what's the significance of the double-expansion stringification macro?",
    pattern = "allocator_abstraction",
  },
  {
    repo = "json",
    lang = "cpp",
    file = "include/nlohmann/detail/meta/type_traits.hpp",
    lines = {52, 78},
    question = "How does the nlohmann library use template specialization and SFINAE patterns for compile-time type checking?",
    pattern = "sfinae",
  },
  {
    repo = "json",
    lang = "cpp",
    file = "include/nlohmann/detail/conversions/to_json.hpp",
    lines = {47, 72},
    question = "Why does external_constructor explicitly destroy old values before assignment, and how does this prevent memory leaks in union-based storage?",
    pattern = "union_memory",
  },
  {
    repo = "spdlog",
    lang = "cpp",
    file = "include/spdlog/details/circular_q.h",
    lines = {14, 57},
    question = "How does circular_q implement a lock-free queue with move-only semantics?",
    pattern = "lock_free",
  },
  {
    repo = "spdlog",
    lang = "cpp",
    file = "include/spdlog/async_logger-inl.h",
    lines = {34, 43},
    question = "How does spdlog use weak_ptr to handle async logger lifecycle?",
    pattern = "weak_ptr",
  },

  -- ===========================================================================
  -- Java/Kotlin
  -- ===========================================================================
  {
    repo = "guava",
    lang = "java",
    file = "guava/src/com/google/common/base/Converter.java",
    lines = {146, 188},
    question = "Why does Converter compose multiple generic type parameters (A, B, C) to create type-safe conversion chains?",
    pattern = "generics",
  },
  {
    repo = "guava",
    lang = "java",
    file = "guava/src/com/google/common/collect/ImmutableList.java",
    lines = {65, 281},
    question = "How does ImmutableList use generic variance (? extends E) in factory methods to accept flexible input types?",
    pattern = "variance",
  },
  {
    repo = "okhttp",
    lang = "kotlin",
    file = "okhttp/src/commonJvmAndroid/kotlin/okhttp3/OkHttpClient.kt",
    lines = {586, 728},
    question = "Why does OkHttpClient.Builder use mutable collections internally with apply {} lambda returns?",
    pattern = "builder_pattern",
  },
  {
    repo = "ktor",
    lang = "kotlin",
    file = "ktor-client/ktor-client-apache/jvm/src/io/ktor/client/engine/apache/ApacheEngine.kt",
    lines = {25, 89},
    question = "How does ApacheEngine combine coroutine context handling, suspend functions, and the builder pattern?",
    pattern = "coroutines",
  },

  -- ===========================================================================
  -- Ruby
  -- ===========================================================================
  {
    repo = "rails",
    lang = "ruby",
    file = "actionpack/lib/action_dispatch/middleware/callbacks.rb",
    lines = {1, 39},
    question = "How does Rails use metaprogramming with `define_callbacks` and `set_callback` to create a declarative middleware chain?",
    pattern = "metaprogramming",
  },
  {
    repo = "rails",
    lang = "ruby",
    file = "actioncable/lib/action_cable/connection/identification.rb",
    lines = {1, 49},
    question = "How does `identified_by` use metaprogramming to dynamically create accessor methods while tracking them in a registry?",
    pattern = "dynamic_methods",
  },
  {
    repo = "devise",
    lang = "ruby",
    file = "lib/devise/controllers/helpers.rb",
    lines = {42, 81},
    question = "How does Devise use `class_eval` with heredocs to generate scope-specific authentication helper methods?",
    pattern = "class_eval",
  },
  {
    repo = "devise",
    lang = "ruby",
    file = "lib/devise/models.rb",
    lines = {31, 52},
    question = "How does the `config` method create a computed property pattern that checks instance, parent class, and global defaults in order?",
    pattern = "computed_property",
  },

  -- ===========================================================================
  -- PHP
  -- ===========================================================================
  {
    repo = "laravel",
    lang = "php",
    file = "bootstrap/app.php",
    lines = {1, 18},
    question = "How does Laravel use method chaining and closure callbacks to create a declarative DSL for application configuration?",
    pattern = "fluent_dsl",
  },
  {
    repo = "symfony",
    lang = "php",
    file = "src/Symfony/Component/DependencyInjection/Container.php",
    lines = {51, 150},
    question = "How does Symfony's Container implement the service locator pattern with lazy loading and factory resolution?",
    pattern = "dependency_injection",
  },
  {
    repo = "symfony",
    lang = "php",
    file = "src/Symfony/Component/DependencyInjection/Definition.php",
    lines = {23, 150},
    question = "How does the Definition class use a fluent builder pattern with immutable metadata to describe service instantiation?",
    pattern = "service_definition",
  },
}

-- =============================================================================
-- Helper Functions
-- =============================================================================

---Get test cases by language
---@param lang string
---@return table[]
function M.get_by_language(lang)
  local result = {}
  for _, tc in ipairs(M.TEST_CASES) do
    if tc.lang == lang then
      table.insert(result, tc)
    end
  end
  return result
end

---Get test cases by repo
---@param repo string
---@return table[]
function M.get_by_repo(repo)
  local result = {}
  for _, tc in ipairs(M.TEST_CASES) do
    if tc.repo == repo then
      table.insert(result, tc)
    end
  end
  return result
end

---Get test cases by pattern
---@param pattern string
---@return table[]
function M.get_by_pattern(pattern)
  local result = {}
  for _, tc in ipairs(M.TEST_CASES) do
    if tc.pattern == pattern then
      table.insert(result, tc)
    end
  end
  return result
end

---Get full file path for a test case
---@param tc table Test case
---@return string
function M.get_file_path(tc)
  return string.format("%s/%s/%s", M.REPOS_DIR, tc.repo, tc.file)
end

---Get statistics
---@return table
function M.get_stats()
  local langs = {}
  local repos = {}
  local patterns = {}

  for _, tc in ipairs(M.TEST_CASES) do
    langs[tc.lang] = (langs[tc.lang] or 0) + 1
    repos[tc.repo] = (repos[tc.repo] or 0) + 1
    patterns[tc.pattern] = (patterns[tc.pattern] or 0) + 1
  end

  return {
    total = #M.TEST_CASES,
    by_language = langs,
    by_repo = repos,
    by_pattern = patterns,
  }
end

---Validate all test cases (check files exist)
---@return table {valid: table[], invalid: table[]}
function M.validate()
  local valid = {}
  local invalid = {}

  for _, tc in ipairs(M.TEST_CASES) do
    local path = M.get_file_path(tc)
    if vim.fn.filereadable(path) == 1 then
      table.insert(valid, tc)
    else
      table.insert(invalid, {
        test_case = tc,
        path = path,
        error = "file not found",
      })
    end
  end

  return { valid = valid, invalid = invalid }
end

return M
