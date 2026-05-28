#!/usr/bin/env bash

# llama.cpp specific functions

LLMS_DIR="${LLMS_DIR:-$HOME/llms}"
LLAMA_DIR="${LLAMA_DIR:-$LLMS_DIR/llama.cpp}"

clone_llama() {
    if [ -d "$LLAMA_DIR/.git" ]; then
        info "Updating llama.cpp..."
        cd "$LLAMA_DIR" && git fetch --tags
    else
        info "Cloning llama.cpp..."
        git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
    fi
}

build_vulkan() {
    cd "$LLAMA_DIR"
    rm -rf build-vulkan
    info "Building with Vulkan..."
    cmake -B build-vulkan -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
    cmake --build build-vulkan -- -j"$(nproc)"
    info "Vulkan build complete"
}

build_rocm() {
    cd "$LLAMA_DIR"
    rm -rf build-rocm
    info "Building with ROCm (gfx1100)..."
    cmake -B build-rocm \
        -DGGML_HIP=ON \
        -DCMAKE_HIP_ARCHITECTURES=gfx1100 \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build build-rocm -- -j"$(nproc)"
    info "ROCm build complete"
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
    info "Fat build complete"
}
