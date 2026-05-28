#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || true
source "$SCRIPT_DIR/lib/llama.sh" 2>/dev/null || true

LLMS_DIR="${LLMS_DIR:-$HOME/llms}"
LLAMA_DIR="${LLAMA_DIR:-$LLMS_DIR/llama.cpp}"

update_to_latest() {
    if [ ! -d "$LLAMA_DIR/.git" ]; then
        clone_llama
    fi
    cd "$LLAMA_DIR"
    info "Updating to latest master..."
    git checkout master
    git pull --rebase
    info "Repository is now at latest master"
}

build_vulkan() {
    cd "$LLAMA_DIR"
    rm -rf build-vulkan
    info "Building latest with Vulkan..."
    cmake -B build-vulkan -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
    cmake --build build-vulkan -- -j"$(nproc)"
    info "Vulkan build complete → build-vulkan/"
}

build_rocm() {
    cd "$LLAMA_DIR"
    rm -rf build-rocm
    info "Building latest with ROCm (gfx1100)..."
    cmake -B build-rocm \
        -DGGML_HIP=ON \
        -DCMAKE_HIP_ARCHITECTURES=gfx1100 \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build build-rocm -- -j"$(nproc)"
    info "ROCm build complete → build-rocm/"
}

build_fat() {
    cd "$LLAMA_DIR"
    rm -rf build-fat
    info "Building latest Fat (Vulkan + ROCm)..."
    cmake -B build-fat \
        -DGGML_VULKAN=ON \
        -DGGML_HIP=ON \
        -DCMAKE_HIP_ARCHITECTURES=gfx1100 \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build build-fat -- -j"$(nproc)"
    info "Fat build complete → build-fat/"
}

main() {
    mkdir -p "$LLMS_DIR"

    echo ""
    echo "1) Update to latest master"
    echo "2) Clone / Update repo"
    echo "3) Build Vulkan only (latest)"
    echo "4) Build ROCm only (latest)"
    echo "5) Build Fat (latest)"
    echo "6) Exit"
    echo ""
    read -rp "Choice: " c

    case "$c" in
        1) update_to_latest ;;
        2) clone_llama ;;
        3) build_vulkan ;;
        4) build_rocm ;;
        5) build_fat ;;
        6) exit 0 ;;
        *) error "Invalid choice" ;;
    esac
}

main "$@"
