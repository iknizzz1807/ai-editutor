#!/bin/bash
# Clone 200 repos for comprehensive testing
# ~22 repos per language × 9 languages

set -e

CACHE_DIR="${HOME}/.cache/editutor-tests/repos"
mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

clone_repo() {
    local name="$1"
    local url="$2"
    local depth="${3:-1}"

    if [ -d "$name" ]; then
        echo "  [SKIP] $name already exists"
        return 0
    fi

    echo "  [CLONE] $name"
    git clone --depth "$depth" "$url" "$name" 2>/dev/null || {
        echo "  [FAIL] $name"
        return 1
    }
}

echo "=== PYTHON REPOS (23) ==="
# Web frameworks & APIs
clone_repo "django" "https://github.com/django/django"
clone_repo "flask" "https://github.com/pallets/flask"
clone_repo "fastapi" "https://github.com/tiangolo/fastapi"
clone_repo "starlette" "https://github.com/encode/starlette"
clone_repo "sanic" "https://github.com/sanic-org/sanic"

# Data & ML
clone_repo "pandas" "https://github.com/pandas-dev/pandas"
clone_repo "numpy" "https://github.com/numpy/numpy"
clone_repo "scikit-learn" "https://github.com/scikit-learn/scikit-learn"
clone_repo "pytorch" "https://github.com/pytorch/pytorch"
clone_repo "transformers" "https://github.com/huggingface/transformers"

# CLI & Tools
clone_repo "click" "https://github.com/pallets/click"
clone_repo "rich" "https://github.com/Textualize/rich"
clone_repo "typer" "https://github.com/tiangolo/typer"
clone_repo "httpx" "https://github.com/encode/httpx"
clone_repo "requests" "https://github.com/psf/requests"

# Async & Networking
clone_repo "aiohttp" "https://github.com/aio-libs/aiohttp"
clone_repo "celery" "https://github.com/celery/celery"
clone_repo "dramatiq" "https://github.com/Bogdanp/dramatiq"

# Utilities
clone_repo "pydantic" "https://github.com/pydantic/pydantic"
clone_repo "sqlalchemy" "https://github.com/sqlalchemy/sqlalchemy"
clone_repo "alembic" "https://github.com/sqlalchemy/alembic"
clone_repo "pytest" "https://github.com/pytest-dev/pytest"
clone_repo "black" "https://github.com/psf/black"

echo ""
echo "=== JAVASCRIPT REPOS (22) ==="
# Frameworks
clone_repo "express" "https://github.com/expressjs/express"
clone_repo "koa" "https://github.com/koajs/koa"
clone_repo "fastify" "https://github.com/fastify/fastify"
clone_repo "hapi" "https://github.com/hapijs/hapi"

# Build tools
clone_repo "webpack" "https://github.com/webpack/webpack"
clone_repo "esbuild" "https://github.com/evanw/esbuild"
clone_repo "rollup" "https://github.com/rollup/rollup"
clone_repo "vite" "https://github.com/vitejs/vite"
clone_repo "parcel" "https://github.com/parcel-bundler/parcel"

# Utilities
clone_repo "lodash" "https://github.com/lodash/lodash"
clone_repo "axios" "https://github.com/axios/axios"
clone_repo "dayjs" "https://github.com/iamkun/dayjs"
clone_repo "moment" "https://github.com/moment/moment"
clone_repo "rxjs" "https://github.com/ReactiveX/rxjs"

# Testing
clone_repo "jest" "https://github.com/jestjs/jest"
clone_repo "mocha" "https://github.com/mochajs/mocha"
clone_repo "chai" "https://github.com/chaijs/chai"

# Node utilities
clone_repo "commander" "https://github.com/tj/commander.js"
clone_repo "inquirer" "https://github.com/SBoudrias/Inquirer.js"
clone_repo "chalk" "https://github.com/chalk/chalk"
clone_repo "ora" "https://github.com/sindresorhus/ora"
clone_repo "debug" "https://github.com/debug-js/debug"

echo ""
echo "=== TYPESCRIPT REPOS (22) ==="
# Frameworks
clone_repo "nest" "https://github.com/nestjs/nest"
clone_repo "trpc" "https://github.com/trpc/trpc"
clone_repo "hono" "https://github.com/honojs/hono"

# State management
clone_repo "zustand" "https://github.com/pmndrs/zustand"
clone_repo "jotai" "https://github.com/pmndrs/jotai"
clone_repo "valtio" "https://github.com/pmndrs/valtio"
clone_repo "mobx" "https://github.com/mobxjs/mobx"
clone_repo "xstate" "https://github.com/statelyai/xstate"

# Validation & Schema
clone_repo "zod" "https://github.com/colinhacks/zod"
clone_repo "yup" "https://github.com/jquense/yup"
clone_repo "io-ts" "https://github.com/gcanti/io-ts"
clone_repo "typebox" "https://github.com/sinclairzx81/typebox"

# ORM & Database
clone_repo "prisma" "https://github.com/prisma/prisma"
clone_repo "drizzle-orm" "https://github.com/drizzle-team/drizzle-orm"
clone_repo "typeorm" "https://github.com/typeorm/typeorm"
clone_repo "kysely" "https://github.com/kysely-org/kysely"

# UI Libraries
clone_repo "radix-ui" "https://github.com/radix-ui/primitives"
clone_repo "shadcn-ui" "https://github.com/shadcn-ui/ui"
clone_repo "headlessui" "https://github.com/tailwindlabs/headlessui"

# Utilities
clone_repo "date-fns" "https://github.com/date-fns/date-fns"
clone_repo "effect" "https://github.com/Effect-TS/effect"
clone_repo "fp-ts" "https://github.com/gcanti/fp-ts"

echo ""
echo "=== GO REPOS (23) ==="
# Web frameworks
clone_repo "gin" "https://github.com/gin-gonic/gin"
clone_repo "echo" "https://github.com/labstack/echo"
clone_repo "fiber" "https://github.com/gofiber/fiber"
clone_repo "chi" "https://github.com/go-chi/chi"
clone_repo "gorilla-mux" "https://github.com/gorilla/mux"

# CLI
clone_repo "cobra" "https://github.com/spf13/cobra"
clone_repo "viper" "https://github.com/spf13/viper"
clone_repo "urfave-cli" "https://github.com/urfave/cli"
clone_repo "bubbletea" "https://github.com/charmbracelet/bubbletea"
clone_repo "lipgloss" "https://github.com/charmbracelet/lipgloss"

# Utilities
clone_repo "fzf" "https://github.com/junegunn/fzf"
clone_repo "lazygit" "https://github.com/jesseduffield/lazygit"
clone_repo "gum" "https://github.com/charmbracelet/gum"

# Database & ORM
clone_repo "gorm" "https://github.com/go-gorm/gorm"
clone_repo "sqlx" "https://github.com/jmoiron/sqlx"
clone_repo "ent" "https://github.com/ent/ent"

# Networking
clone_repo "grpc-go" "https://github.com/grpc/grpc-go"
clone_repo "nats" "https://github.com/nats-io/nats.go"
clone_repo "websocket" "https://github.com/gorilla/websocket"

# Testing & Tools
clone_repo "testify" "https://github.com/stretchr/testify"
clone_repo "golangci-lint" "https://github.com/golangci/golangci-lint"
clone_repo "air" "https://github.com/cosmtrek/air"
clone_repo "delve" "https://github.com/go-delve/delve"

echo ""
echo "=== RUST REPOS (22) ==="
# Async runtime
clone_repo "tokio" "https://github.com/tokio-rs/tokio"
clone_repo "async-std" "https://github.com/async-rs/async-std"

# Web frameworks
clone_repo "axum" "https://github.com/tokio-rs/axum"
clone_repo "actix-web" "https://github.com/actix/actix-web"
clone_repo "rocket" "https://github.com/rwf2/Rocket"
clone_repo "warp" "https://github.com/seanmonstar/warp"

# CLI
clone_repo "clap" "https://github.com/clap-rs/clap"
clone_repo "ripgrep" "https://github.com/BurntSushi/ripgrep"
clone_repo "bat" "https://github.com/sharkdp/bat"
clone_repo "fd" "https://github.com/sharkdp/fd"
clone_repo "exa" "https://github.com/ogham/exa"

# Serialization
clone_repo "serde" "https://github.com/serde-rs/serde"
clone_repo "serde_json" "https://github.com/serde-rs/json"

# Database
clone_repo "diesel" "https://github.com/diesel-rs/diesel"
clone_repo "sqlx-rust" "https://github.com/launchbadge/sqlx"
clone_repo "sea-orm" "https://github.com/SeaQL/sea-orm"

# Error handling
clone_repo "anyhow" "https://github.com/dtolnay/anyhow"
clone_repo "thiserror" "https://github.com/dtolnay/thiserror"

# Utilities
clone_repo "rayon" "https://github.com/rayon-rs/rayon"
clone_repo "crossbeam" "https://github.com/crossbeam-rs/crossbeam"
clone_repo "parking_lot" "https://github.com/Amanieu/parking_lot"
clone_repo "tracing" "https://github.com/tokio-rs/tracing"

echo ""
echo "=== C REPOS (22) ==="
# System
clone_repo "linux" "https://github.com/torvalds/linux" 1
clone_repo "git" "https://github.com/git/git"
clone_repo "redis" "https://github.com/redis/redis"
clone_repo "nginx" "https://github.com/nginx/nginx"
clone_repo "curl" "https://github.com/curl/curl"

# Databases
clone_repo "sqlite" "https://github.com/sqlite/sqlite"
clone_repo "postgres" "https://github.com/postgres/postgres"
clone_repo "leveldb" "https://github.com/google/leveldb"

# Libraries
clone_repo "libuv" "https://github.com/libuv/libuv"
clone_repo "openssl" "https://github.com/openssl/openssl"
clone_repo "zlib" "https://github.com/madler/zlib"
clone_repo "jq" "https://github.com/jqlang/jq"
clone_repo "cjson" "https://github.com/DaveGamble/cJSON"

# Networking
clone_repo "libevent" "https://github.com/libevent/libevent"
clone_repo "libev" "https://github.com/enki/libev"
clone_repo "zeromq" "https://github.com/zeromq/libzmq"

# Multimedia
clone_repo "ffmpeg" "https://github.com/FFmpeg/FFmpeg"
clone_repo "mpv" "https://github.com/mpv-player/mpv"

# Embedded
clone_repo "micropython" "https://github.com/micropython/micropython"
clone_repo "zephyr" "https://github.com/zephyrproject-rtos/zephyr"

# Tools
clone_repo "tmux" "https://github.com/tmux/tmux"
clone_repo "htop" "https://github.com/htop-dev/htop"

echo ""
echo "=== C++ REPOS (22) ==="
# Frameworks
clone_repo "abseil-cpp" "https://github.com/abseil/abseil-cpp"
clone_repo "folly" "https://github.com/facebook/folly"
clone_repo "boost" "https://github.com/boostorg/boost"

# Game/Graphics
clone_repo "godot" "https://github.com/godotengine/godot"
clone_repo "imgui" "https://github.com/ocornut/imgui"
clone_repo "glfw" "https://github.com/glfw/glfw"

# Databases
clone_repo "rocksdb" "https://github.com/facebook/rocksdb"
clone_repo "foundationdb" "https://github.com/apple/foundationdb"

# Serialization
clone_repo "protobuf" "https://github.com/protocolbuffers/protobuf"
clone_repo "flatbuffers" "https://github.com/google/flatbuffers"
clone_repo "capnproto" "https://github.com/capnproto/capnproto"
clone_repo "msgpack-c" "https://github.com/msgpack/msgpack-c"

# Testing
clone_repo "googletest" "https://github.com/google/googletest"
clone_repo "catch2" "https://github.com/catchorg/Catch2"
clone_repo "doctest" "https://github.com/doctest/doctest"

# Logging
clone_repo "spdlog" "https://github.com/gabime/spdlog"
clone_repo "glog" "https://github.com/google/glog"

# JSON
clone_repo "nlohmann-json" "https://github.com/nlohmann/json"
clone_repo "rapidjson" "https://github.com/Tencent/rapidjson"
clone_repo "simdjson" "https://github.com/simdjson/simdjson"

# Networking
clone_repo "grpc" "https://github.com/grpc/grpc"
clone_repo "cpp-httplib" "https://github.com/yhirose/cpp-httplib"

echo ""
echo "=== ZIG REPOS (22) ==="
# Core
clone_repo "zig" "https://github.com/ziglang/zig"
clone_repo "std-lib-zig" "https://github.com/ziglang/zig" # std in same repo

# Applications
clone_repo "ghostty" "https://github.com/ghostty-org/ghostty"
clone_repo "bun" "https://github.com/oven-sh/bun"
clone_repo "tigerbeetle" "https://github.com/tigerbeetle/tigerbeetle"

# Games
clone_repo "zig-gamedev" "https://github.com/michal-z/zig-gamedev"
clone_repo "mach" "https://github.com/hexops/mach"

# Networking
clone_repo "zap" "https://github.com/zigzap/zap"
clone_repo "zig-network" "https://github.com/MasterQ32/zig-network"

# Utilities
clone_repo "ziglings" "https://github.com/ratfactor/ziglings"
clone_repo "zig-string" "https://github.com/JakubSzark/zig-string"

# Build
clone_repo "gyro" "https://github.com/mattnite/gyro"
clone_repo "zigmod" "https://github.com/nektro/zigmod"

# Embedded
clone_repo "microzig" "https://github.com/ZigEmbeddedSys/microzig"

# Parsers
clone_repo "zig-parser" "https://github.com/Hejsil/zig-parser-combinators"

# Memory
clone_repo "zig-allocators" "https://github.com/andrewrk/zig-allocators"

# Crypto
clone_repo "zig-crypto" "https://github.com/jedisct1/zig-crypto"

# Compression
clone_repo "zig-zlib" "https://github.com/marler182/zig-zlib"
clone_repo "zig-lz4" "https://github.com/marler182/zig-lz4"

# HTTP
clone_repo "zhp" "https://github.com/andrewrk/zhp"
clone_repo "http-zig" "https://github.com/truemedian/http.zig"

echo ""
echo "=== LUA REPOS (22) ==="
# Neovim plugins
clone_repo "telescope.nvim" "https://github.com/nvim-telescope/telescope.nvim"
clone_repo "nvim-treesitter" "https://github.com/nvim-treesitter/nvim-treesitter"
clone_repo "nvim-lspconfig" "https://github.com/neovim/nvim-lspconfig"
clone_repo "nvim-cmp" "https://github.com/hrsh7th/nvim-cmp"
clone_repo "lazy.nvim" "https://github.com/folke/lazy.nvim"
clone_repo "mason.nvim" "https://github.com/williamboman/mason.nvim"
clone_repo "which-key.nvim" "https://github.com/folke/which-key.nvim"
clone_repo "noice.nvim" "https://github.com/folke/noice.nvim"
clone_repo "neo-tree.nvim" "https://github.com/nvim-neo-tree/neo-tree.nvim"
clone_repo "lualine.nvim" "https://github.com/nvim-lualine/lualine.nvim"

# Core libraries
clone_repo "plenary.nvim" "https://github.com/nvim-lua/plenary.nvim"
clone_repo "nui.nvim" "https://github.com/MunifTanjim/nui.nvim"

# Completion
clone_repo "luasnip" "https://github.com/L3MON4D3/LuaSnip"
clone_repo "cmp-nvim-lsp" "https://github.com/hrsh7th/cmp-nvim-lsp"

# Git
clone_repo "gitsigns.nvim" "https://github.com/lewis6991/gitsigns.nvim"
clone_repo "diffview.nvim" "https://github.com/sindrets/diffview.nvim"
clone_repo "neogit" "https://github.com/NeogitOrg/neogit"

# Debug
clone_repo "nvim-dap" "https://github.com/mfussenegger/nvim-dap"
clone_repo "nvim-dap-ui" "https://github.com/rcarriga/nvim-dap-ui"

# UI
clone_repo "bufferline.nvim" "https://github.com/akinsho/bufferline.nvim"
clone_repo "indent-blankline.nvim" "https://github.com/lukas-reineke/indent-blankline.nvim"
clone_repo "nvim-notify" "https://github.com/rcarriga/nvim-notify"

echo ""
echo "=== SUMMARY ==="
TOTAL=$(find "$CACHE_DIR" -maxdepth 1 -type d | wc -l)
echo "Total repos: $((TOTAL - 1))"
echo "Location: $CACHE_DIR"
