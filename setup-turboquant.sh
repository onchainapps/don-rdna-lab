#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
# setup-turboquant.sh — TurboQuant+ for RDNA3
# ═══════════════════════════════════════════════════════

PROJECT_DIR="${TURBOQUANT_DIR:-$HOME/llms/llama-cpp-turboquant}"
MODELS_DIR="$HOME/llms/models"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[$(date +%H:%M:%S)] $1${NC}"; }
warn()  { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ERROR: $1${NC}" >&2; }

ensure_cloned() {
    if [ ! -d "$PROJECT_DIR/.git" ]; then
        info "Repo not found, cloning first..."
        clone
    fi
}

check_prereqs() {
    for cmd in cmake hipcc git make; do
        command -v "$cmd" &>/dev/null || { error "$cmd missing"; return 1; }
    done
}

clone() {
    if [ -d "$PROJECT_DIR/.git" ]; then
        info "Already cloned"
        return 0
    fi
    git clone https://github.com/TheTom/llama-cpp-turboquant.git "$PROJECT_DIR"
    (cd "$PROJECT_DIR" && git checkout feature/turboquant-kv-cache)
}

build_rocm() {
    ensure_cloned
    cd "$PROJECT_DIR"
    rm -rf build-rocm
    echo "Building TurboQuant+ with ROCm support (gfx1100 only)..."
    echo "Note: HIP backend in this fork can be unstable."
    cmake -B build-rocm \
        -DCMAKE_HIP_ARCHITECTURES=gfx1100 \
        -DGGML_HIP=ON \
        -DCMAKE_BUILD_TYPE=Release
    if cmake --build build-rocm -- -j"$(nproc)"; then
        echo "ROCm build finished successfully."
    else
        echo ""
        echo "ROCm build failed. This fork's HIP backend may have issues."
        echo "Recommendation: Try 'build-vulkan' instead."
        return 1
    fi
}

build_fat() {
    ensure_cloned
    cd "$PROJECT_DIR"
    rm -rf build-fat
    echo "Building TurboQuant+ fat binary (TurboQuant + Vulkan)..."
    cmake -B build-fat \
        -DCMAKE_HIP_ARCHITECTURES="gfx1100;gfx942;gfx950" \
        -DGGML_HIP=ON \
        -DGGML_VULKAN=ON \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build build-fat -- -j"$(nproc)"
    echo "Fat build finished."
}

build_vulkan() {
    ensure_cloned
    cd "$PROJECT_DIR"
    rm -rf build-vulkan
    echo "Building TurboQuant+ with Vulkan support..."
    echo "Requires: vulkan-headers + libvulkan-dev (or equivalent)"
    cmake -B build-vulkan \
        -DGGML_VULKAN=ON \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build build-vulkan -- -j"$(nproc)"
    echo ""
    echo "Build finished."
    echo "Test with: ./build-vulkan/bin/llama-cli --list-devices"
}

quantize() {
    local model="${1:-}"
    local out="${2:-}"
    local type="${3:-TQ4_1S}"

    [ -z "$model" ] && { warn "Usage: quantize <model> [out] [type]"; return 1; }

    if [ -z "$out" ]; then
        out="${model%.gguf}-${type}.gguf"
    fi

    local bin
    if [ -d "$PROJECT_DIR/build-rocm/bin" ]; then
        bin="$PROJECT_DIR/build-rocm/bin/llama-quantize"
    elif [ -d "$PROJECT_DIR/build-fat/bin" ]; then
        bin="$PROJECT_DIR/build-fat/bin/llama-quantize"
    elif [ -d "$PROJECT_DIR/build-vulkan/bin" ]; then
        bin="$PROJECT_DIR/build-vulkan/bin/llama-quantize"
    else
        error "Build first"
        return 1
    fi

    echo "Quantizing with TurboQuant format: $type"
    HSA_OVERRIDE_GFX_VERSION=11.0.0 "$bin" "$model" "$out" "$type"
}

run() {
    local model="${1:-}"
    local backend="${2:-TurboQuant0}"
    local ctx="${3:-8192}"
    local max_tokens="${4:-128}"

    [ -z "$model" ] && { warn "Usage: run <model> [backend] [ctx] [tokens]"; return 1; }

    local bin
    if [ -d "$PROJECT_DIR/build-rocm/bin" ]; then
        bin="$PROJECT_DIR/build-rocm/bin/llama-cli"
    elif [ -d "$PROJECT_DIR/build-fat/bin" ]; then
        bin="$PROJECT_DIR/build-fat/bin/llama-cli"
    elif [ -d "$PROJECT_DIR/build-vulkan/bin" ]; then
        bin="$PROJECT_DIR/build-vulkan/bin/llama-cli"
    else
        error "No build found (rocm, fat, or vulkan)"
        return 1
    fi

    HSA_OVERRIDE_GFX_VERSION=11.0.0 \
    "$bin" -m "$model" -dev "$backend" -ngl 999 -c "$ctx" -n "$max_tokens" \
        -b 128 -ub 128 -fa on -ctk q8_0 -ctv q8_0
}

benchmark() {
    info "TurboQuant+ on RDNA3:"
    info "  TQ4_1S weights + turbo3 KV cache recommended"
    info "  Native DP4A + Walsh-Hadamard rotation"
    info "  ~4.6x KV cache compression possible"
}

status() {
    [ -d "$PROJECT_DIR/.git" ] && info "Cloned" || warn "Not cloned"
    [ -d "$PROJECT_DIR/build-rocm/bin" ] && info "TurboQuant build present" || warn "No TurboQuant build"
    [ -d "$PROJECT_DIR/build-fat/bin" ] && info "Fat build present" || warn "No fat build"
}

main() {
    local action="${1:-help}"
    shift || true
    case "$action" in
        prereqs) check_prereqs ;;
        clone)   clone ;;
        build-rocm) build_rocm ;;
        build-fat)  build_fat ;;
        build-vulkan) build_vulkan ;;
        quantize) quantize "$@" ;;
        run)     run "$@" ;;
        benchmark) benchmark ;;
        status)  status ;;
        help|*)  echo "Actions: prereqs|clone|build-rocm|build-fat|build-vulkan|quantize|run|benchmark|status" ;;
    esac
}

main "$@"
