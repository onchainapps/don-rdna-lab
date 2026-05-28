#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/llama.sh"

LLMS_DIR="${LLMS_DIR:-$HOME/llms}"
LLAMA_DIR="${LLAMA_DIR:-$LLMS_DIR/llama.cpp}"

# Override build functions from lib/llama.sh with exit code checking
build_vulkan() {
    cd "$LLAMA_DIR" || { error "Failed to enter $LLAMA_DIR"; return 1; }
    rm -rf build-vulkan
    cmake -B build-vulkan -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release || { error "cmake (Vulkan) failed"; return 1; }
    cmake --build build-vulkan -- -j"$(nproc)" || { error "make (Vulkan) failed"; return 1; }
    info "Vulkan build complete"
}

build_rocm() {
    cd "$LLAMA_DIR" || { error "Failed to enter $LLAMA_DIR"; return 1; }
    rm -rf build-rocm
    cmake -B build-rocm \
        -DGGML_HIP=ON \
        -DCMAKE_HIP_ARCHITECTURES=gfx1100 \
        -DCMAKE_BUILD_TYPE=Release || {
        error "cmake (ROCm) failed — check rocminfo, hipcc, and driver"
        return 1
    }
    cmake --build build-rocm -- -j"$(nproc)" || { error "make (ROCm) failed"; return 1; }
    if [ ! -d "$LLAMA_DIR/build-rocm" ] || [ -z "$(find "$LLAMA_DIR/build-rocm" -maxdepth 2 -type f -executable -name 'llama-*' 2>/dev/null | head -1)" ]; then
        error "ROCm build produced no binaries — falling back"
        return 1
    fi
    info "ROCm build complete"
}

build_fat() {
    cd "$LLAMA_DIR" || { error "Failed to enter $LLAMA_DIR"; return 1; }
    rm -rf build-fat
    cmake -B build-fat \
        -DGGML_VULKAN=ON \
        -DGGML_HIP=ON \
        -DCMAKE_HIP_ARCHITECTURES=gfx1100 \
        -DCMAKE_BUILD_TYPE=Release || {
        error "cmake (Fat) failed"
        return 1
    }
    cmake --build build-fat -- -j"$(nproc)" || { error "make (Fat) failed"; return 1; }
    if [ ! -d "$LLAMA_DIR/build-fat" ] || [ -z "$(find "$LLAMA_DIR/build-fat" -maxdepth 2 -type f -executable -name 'llama-*' 2>/dev/null | head -1)" ]; then
        error "Fat build produced no binaries"
        return 1
    fi
    info "Fat build complete"
}

DIALOG_CMD=""
detect_dialog() {
    if command -v dialog &>/dev/null; then DIALOG_CMD="dialog"
    elif command -v whiptail &>/dev/null; then DIALOG_CMD="whiptail"
    else DIALOG_CMD=""; fi
}

is_dialog() { [ "$DIALOG_CMD" = "dialog" ]; }

# Run command with nice progress box when dialog is available
run_build_with_progress() {
    local title="$1"; shift
    if [ -n "$DIALOG_CMD" ] && is_dialog; then
        "$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp" \
            --title " $title " --progressbox 22 95
    else
        echo "=== $title ==="
        "$@"
    fi
}

_update_impl() {
    if [ ! -d "$LLAMA_DIR/.git" ]; then
        git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
    fi
    cd "$LLAMA_DIR" && git checkout master && git pull --rebase 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
}
update_to_latest() {
    run_build_with_progress "Updating to latest master" _update_impl
}

build_with_progress() {
    local type="$1"
    case "$type" in
        vulkan) run_build_with_progress "Building Vulkan backend" build_vulkan ;;
        rocm)   run_build_with_progress "Building ROCm (gfx1100) backend" build_rocm ;;
        fat)    run_build_with_progress "Building Fat (Vulkan + ROCm)" build_fat ;;
    esac
}

main() {
    mkdir -p "$LLMS_DIR"
    detect_dialog

    if [ -n "$DIALOG_CMD" ]; then
        # Dialog-based menu
        while true; do
            choice=$( "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp" \
                --menu "Build / Update llama.cpp" 16 60 8 \
                1 "Update to latest master" \
                2 "Clone / Update repository" \
                3 "Build Vulkan only" \
                4 "Build ROCm only (gfx1100)" \
                5 "Build Fat (Vulkan + ROCm)" \
                6 "Exit" \
                3>&1 1>&2 2>&3 ) || exit 0

            case "$choice" in
                1) update_to_latest ;;
                2) run_build_with_progress "Cloning / Updating llama.cpp" clone_llama ;;
                3) build_with_progress vulkan ;;
                4) build_with_progress rocm ;;
                5) build_with_progress fat ;;
                6) exit 0 ;;
            esac
        done
    else
        # Plain text fallback
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
            2) run_build_with_progress "Cloning / Updating llama.cpp" clone_llama ;;
            3) build_with_progress vulkan ;;
            4) build_with_progress rocm ;;
            5) build_with_progress fat ;;
            6) exit 0 ;;
            *) error "Invalid choice" ;;
        esac
    fi
}

main "$@"
