#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/llama.sh"

LLMS_DIR="${LLMS_DIR:-$HOME/llms}"
LLAMA_DIR="${LLAMA_DIR:-$LLMS_DIR/llama.cpp}"

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
        "$@" 2>&1 | "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp" \
            --title " $title " --progressbox 22 95
    else
        echo "=== $title ==="
        "$@"
    fi
}

update_to_latest() {
    if [ ! -d "$LLAMA_DIR/.git" ]; then
        clone_llama
    fi
    cd "$LLAMA_DIR" || { error "Failed to enter $LLAMA_DIR"; return 1; }
    info "Updating to latest master..."
    git checkout master
    git pull --rebase
    info "Repository is now at latest master"
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
            2) clone_llama ;;
            3) build_vulkan ;;
            4) build_rocm ;;
            5) build_fat ;;
            6) exit 0 ;;
            *) error "Invalid choice" ;;
        esac
    fi
}

main "$@"
