#!/bin/bash
# Clone 100 diverse repositories for ai-editutor testing
# Run: chmod +x scripts/clone_test_repos.sh && ./scripts/clone_test_repos.sh

set -e

TEST_DIR="${HOME}/.cache/editutor-tests/repos"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "=============================================="
echo "ai-editutor Test Repository Cloner (100 repos)"
echo "=============================================="
echo "Target directory: $TEST_DIR"
echo ""

clone_repo() {
    local url=$1
    local name=$(basename "$url" .git)

    if [ -d "$name" ]; then
        echo "[SKIP] $name"
    else
        echo "[CLONE] $name"
        git clone --depth 1 --quiet "$url" 2>/dev/null || echo "[FAIL] $name"
    fi
}

# =============================================================================
# JavaScript/TypeScript (15 repos)
# =============================================================================
echo "=== JavaScript/TypeScript (15 repos) ==="
clone_repo "https://github.com/sindresorhus/got"
clone_repo "https://github.com/colinhacks/zod"
clone_repo "https://github.com/pmndrs/zustand"
clone_repo "https://github.com/TanStack/query"
clone_repo "https://github.com/trpc/trpc"
clone_repo "https://github.com/prisma/prisma"
clone_repo "https://github.com/vercel/swr"
clone_repo "https://github.com/date-fns/date-fns"
clone_repo "https://github.com/lodash/lodash"
clone_repo "https://github.com/expressjs/express"
clone_repo "https://github.com/nestjs/nest"
clone_repo "https://github.com/remix-run/react-router"
clone_repo "https://github.com/axios/axios"
clone_repo "https://github.com/reduxjs/redux"
clone_repo "https://github.com/socketio/socket.io"

# =============================================================================
# Python (12 repos)
# =============================================================================
echo ""
echo "=== Python (12 repos) ==="
clone_repo "https://github.com/psf/requests"
clone_repo "https://github.com/pallets/flask"
clone_repo "https://github.com/fastapi/fastapi"
clone_repo "https://github.com/django/django"
clone_repo "https://github.com/pydantic/pydantic"
clone_repo "https://github.com/sqlalchemy/sqlalchemy"
clone_repo "https://github.com/pytest-dev/pytest"
clone_repo "https://github.com/python-poetry/poetry"
clone_repo "https://github.com/tiangolo/typer"
clone_repo "https://github.com/encode/httpx"
clone_repo "https://github.com/pallets/click"
clone_repo "https://github.com/celery/celery"

# =============================================================================
# Rust (10 repos)
# =============================================================================
echo ""
echo "=== Rust (10 repos) ==="
clone_repo "https://github.com/sharkdp/fd"
clone_repo "https://github.com/BurntSushi/ripgrep"
clone_repo "https://github.com/sharkdp/bat"
clone_repo "https://github.com/ajeetdsouza/zoxide"
clone_repo "https://github.com/starship/starship"
clone_repo "https://github.com/tokio-rs/axum"
clone_repo "https://github.com/serde-rs/serde"
clone_repo "https://github.com/tokio-rs/tokio"
clone_repo "https://github.com/clap-rs/clap"
clone_repo "https://github.com/rust-lang/rustlings"

# =============================================================================
# Go (10 repos)
# =============================================================================
echo ""
echo "=== Go (10 repos) ==="
clone_repo "https://github.com/junegunn/fzf"
clone_repo "https://github.com/jesseduffield/lazygit"
clone_repo "https://github.com/charmbracelet/bubbletea"
clone_repo "https://github.com/gin-gonic/gin"
clone_repo "https://github.com/gofiber/fiber"
clone_repo "https://github.com/spf13/cobra"
clone_repo "https://github.com/go-gitea/gitea"
clone_repo "https://github.com/containerd/containerd"
clone_repo "https://github.com/gorilla/mux"
clone_repo "https://github.com/stretchr/testify"

# =============================================================================
# Lua/Neovim (8 repos)
# =============================================================================
echo ""
echo "=== Lua/Neovim (8 repos) ==="
clone_repo "https://github.com/nvim-lua/plenary.nvim"
clone_repo "https://github.com/folke/lazy.nvim"
clone_repo "https://github.com/nvim-telescope/telescope.nvim"
clone_repo "https://github.com/neovim/nvim-lspconfig"
clone_repo "https://github.com/hrsh7th/nvim-cmp"
clone_repo "https://github.com/folke/which-key.nvim"
clone_repo "https://github.com/nvim-treesitter/nvim-treesitter"
clone_repo "https://github.com/folke/noice.nvim"

# =============================================================================
# Zig (4 repos)
# =============================================================================
echo ""
echo "=== Zig (4 repos) ==="
clone_repo "https://github.com/zigtools/zls"
clone_repo "https://github.com/ziglang/zig"
clone_repo "https://github.com/ghostty-org/ghostty"
clone_repo "https://github.com/tigerbeetle/tigerbeetle"

# =============================================================================
# C (6 repos)
# =============================================================================
echo ""
echo "=== C (6 repos) ==="
clone_repo "https://github.com/jqlang/jq"
clone_repo "https://github.com/redis/redis"
clone_repo "https://github.com/curl/curl"
clone_repo "https://github.com/git/git"
clone_repo "https://github.com/tmux/tmux"
clone_repo "https://github.com/htop-dev/htop"

# =============================================================================
# C++ (6 repos)
# =============================================================================
echo ""
echo "=== C++ (6 repos) ==="
clone_repo "https://github.com/nlohmann/json"
clone_repo "https://github.com/gabime/spdlog"
clone_repo "https://github.com/fmtlib/fmt"
clone_repo "https://github.com/catchorg/Catch2"
clone_repo "https://github.com/google/googletest"
clone_repo "https://github.com/grpc/grpc"

# =============================================================================
# Java (5 repos)
# =============================================================================
echo ""
echo "=== Java (5 repos) ==="
clone_repo "https://github.com/google/guava"
clone_repo "https://github.com/square/okhttp"
clone_repo "https://github.com/ReactiveX/RxJava"
clone_repo "https://github.com/google/gson"
clone_repo "https://github.com/apache/kafka"

# =============================================================================
# Kotlin (4 repos)
# =============================================================================
echo ""
echo "=== Kotlin (4 repos) ==="
clone_repo "https://github.com/JetBrains/kotlin"
clone_repo "https://github.com/square/okio"
clone_repo "https://github.com/Kotlin/kotlinx.coroutines"
clone_repo "https://github.com/ktorio/ktor"

# =============================================================================
# Swift (4 repos)
# =============================================================================
echo ""
echo "=== Swift (4 repos) ==="
clone_repo "https://github.com/apple/swift-algorithms"
clone_repo "https://github.com/Alamofire/Alamofire"
clone_repo "https://github.com/ReactiveX/RxSwift"
clone_repo "https://github.com/vapor/vapor"

# =============================================================================
# C# / .NET (4 repos)
# =============================================================================
echo ""
echo "=== C# / .NET (4 repos) ==="
clone_repo "https://github.com/dotnet/runtime"
clone_repo "https://github.com/dotnet/aspnetcore"
clone_repo "https://github.com/App-vNext/Polly"
clone_repo "https://github.com/autofac/Autofac"

# =============================================================================
# Ruby (4 repos)
# =============================================================================
echo ""
echo "=== Ruby (4 repos) ==="
clone_repo "https://github.com/rails/rails"
clone_repo "https://github.com/jekyll/jekyll"
clone_repo "https://github.com/heartcombo/devise"
clone_repo "https://github.com/rspec/rspec-core"

# =============================================================================
# PHP (4 repos)
# =============================================================================
echo ""
echo "=== PHP (4 repos) ==="
clone_repo "https://github.com/laravel/laravel"
clone_repo "https://github.com/symfony/symfony"
clone_repo "https://github.com/composer/composer"
clone_repo "https://github.com/PHPMailer/PHPMailer"

# =============================================================================
# Elixir (3 repos)
# =============================================================================
echo ""
echo "=== Elixir (3 repos) ==="
clone_repo "https://github.com/elixir-lang/elixir"
clone_repo "https://github.com/phoenixframework/phoenix"
clone_repo "https://github.com/elixir-ecto/ecto"

# =============================================================================
# Scala (2 repos)
# =============================================================================
echo ""
echo "=== Scala (2 repos) ==="
clone_repo "https://github.com/scala/scala3"
clone_repo "https://github.com/akka/akka"

# =============================================================================
# Dart/Flutter (3 repos)
# =============================================================================
echo ""
echo "=== Dart/Flutter (3 repos) ==="
clone_repo "https://github.com/flutter/flutter"
clone_repo "https://github.com/felangel/bloc"
clone_repo "https://github.com/rrousselGit/riverpod"

# =============================================================================
# Vue/Svelte (3 repos)
# =============================================================================
echo ""
echo "=== Vue/Svelte (3 repos) ==="
clone_repo "https://github.com/vuejs/core"
clone_repo "https://github.com/sveltejs/svelte"
clone_repo "https://github.com/nuxt/nuxt"

# =============================================================================
# Shell/Bash (3 repos)
# =============================================================================
echo ""
echo "=== Shell/Bash (3 repos) ==="
clone_repo "https://github.com/ohmyzsh/ohmyzsh"
clone_repo "https://github.com/romkatv/powerlevel10k"
clone_repo "https://github.com/asdf-vm/asdf"

# =============================================================================
# Haskell (2 repos)
# =============================================================================
echo ""
echo "=== Haskell (2 repos) ==="
clone_repo "https://github.com/koalaman/shellcheck"
clone_repo "https://github.com/haskell/haskell-language-server"

# =============================================================================
# OCaml (2 repos)
# =============================================================================
echo ""
echo "=== OCaml (2 repos) ==="
clone_repo "https://github.com/ocaml/ocaml"
clone_repo "https://github.com/facebook/flow"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================="
echo "Clone complete!"
echo "=============================================="
echo ""

TOTAL=$(ls -d */ 2>/dev/null | wc -l)
echo "Total repos cloned: $TOTAL / 100"
echo ""
echo "Languages covered:"
echo "  - JavaScript/TypeScript (15)"
echo "  - Python (12)"
echo "  - Rust (10)"
echo "  - Go (10)"
echo "  - Lua/Neovim (8)"
echo "  - Zig (4)"
echo "  - C (6)"
echo "  - C++ (6)"
echo "  - Java (5)"
echo "  - Kotlin (4)"
echo "  - Swift (4)"
echo "  - C#/.NET (4)"
echo "  - Ruby (4)"
echo "  - PHP (4)"
echo "  - Elixir (3)"
echo "  - Scala (2)"
echo "  - Dart/Flutter (3)"
echo "  - Vue/Svelte (3)"
echo "  - Shell/Bash (3)"
echo "  - Haskell (2)"
echo "  - OCaml (2)"
echo ""
echo "Directory: $TEST_DIR"
