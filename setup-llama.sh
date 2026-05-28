#!/usr/bin/env bash
set -euo pipefail

LLMS_DIR="${LLMS_DIR:-$HOME/llms}"
LLAMA_DIR="${LLAMA_DIR:-$LLMS_DIR/llama.cpp}"

info() { echo "[$(date +%H:%M:%S)] $1"; }

fetch_releases() {
    curl -s "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=15" | \
        grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": "//;s/"//g'
}

clone_repo() {
    if [ -d "$LLAMA_DIR/.git" ]; then
        info "Updating repo..."
        cd "$LLAMA_DIR" && git fetch --tags
    else
        info "Cloning llama.cpp..."
        git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
    fi
}

build_vulkan() {
    cd "$LLAMA_DIR"
    rm -rf build-vulkan
    info "Building Vulkan..."
    cmake -B build-vulkan -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
    cmake --build build-vulkan -- -j"$(nproc)"
    info "Done → build-vulkan/"
}

build_rocm() {
    cd "$LLAMA_DIR"
    rm -rf build-rocm
    info "Building ROCm (gfx1100)..."
    cmake -B build-rocm -DGGML_HIP=ON -DCMAKE_HIP_ARCHITECTURES=gfx1100 -DCMAKE_BUILD_TYPE=Release
    cmake --build build-rocm -- -j"$(nproc)"
    info "Done → build-rocm/"
}

build_fat() {
    cd "$LLAMA_DIR"
    rm -rf build-fat
    info "Building Fat (Vulkan + ROCm)..."
    cmake -B build-fat \
        -DGGML_VULKAN=ON \
        -DGGML_HIP=ON \
        -DCMAKE_HIP_ARCHITECTURES=gfx1100 \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build build-fat -- -j"$(nproc)"
    info "Done → build-fat/"
}

main() {
    mkdir -p "$LLMS_DIR"
    echo ""
    echo "1) List recent releases"
    echo "2) Clone / Update repo"
    echo "3) Build Vulkan only"
    echo "4) Build ROCm only"
    echo "5) Build Fat (both)"
    echo "6) Exit"
    echo ""
    read -rp "Choice: " c

    case "$c" in
        1) fetch_releases ;;
        2) clone_repo ;;
        3) build_vulkan ;;
        4) build_rocm ;;
        5) build_fat ;;
        6) exit 0 ;;
        *) echo "Invalid" ;;
    esac
}

main "$@"
