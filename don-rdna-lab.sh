#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
# Don RDNA Lab — Official llama.cpp TUI
# ═══════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLMS_DIR="${LLMS_DIR:-$HOME/llms}"
MODELS_DIR="${MODELS_DIR:-$LLMS_DIR/models}"

source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || true
source "$SCRIPT_DIR/lib/llama.sh" 2>/dev/null || true

VERSION="0.2.0"

DIALOG_CMD=""
detect_dialog() {
    if command -v dialog &>/dev/null; then DIALOG_CMD="dialog"
    elif command -v whiptail &>/dev/null; then DIALOG_CMD="whiptail"
    else DIALOG_CMD=""; fi
}

require_dialog() {
    detect_dialog
    if [ -z "$DIALOG_CMD" ]; then
        echo "dialog or whiptail required"
        exit 1
    fi
}

dlg() { "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp v$VERSION" "$@"; }

list_models() {
    find "$MODELS_DIR" \( -name "*.gguf" -o -name "*.guff" \) -type f 2>/dev/null | sort
}

list_builds() {
    {
        find "$LLMS_DIR" -maxdepth 1 -type d -name "llama-*" 2>/dev/null
        find "$LLMS_DIR/llama.cpp" -maxdepth 1 -type d -name "build-*" 2>/dev/null
    } | sort
}

main_menu() {
    while true; do
        local choice
        choice=$(dlg --menu "Main Menu" 20 62 12 \
            1 "Setup llama.cpp" \
            2 "Run Inference" \
            3 "Quantize Model" \
            4 "Validate Model" \
            5 "Test Model" \
            6 "Run Benchmark" \
            7 "Show Status" \
            8 "API Endpoints" \
            9 "Quit" \
            3>&1 1>&2 2>&3) || exit 0

        case "$choice" in
            1) setup_llama ;;
            2) run_flow ;;
            3) quantize_flow ;;
            4) validate_model ;;
            5) test_model ;;
            6) benchmark_flow ;;
            7) status_screen ;;
            8) api_screen ;;
            9) exit 0 ;;
        esac
    done
}

setup_llama() {
    while true; do
        local choice
        choice=$(dlg --menu "Setup llama.cpp" 16 58 9             1 "Install Release Version"             2 "Use Git Clone + build-*"             3 "List detected builds"             4 "Back"             3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) install_release_version ;;
            2) use_git_clone_build ;;
            3) list_detected_builds ;;
            4) return ;;
        esac
    done
}

install_release_version() {
    local releases
    releases=$(curl -s "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=12" | grep '"tag_name"' | sed 's/.*"tag_name": "\([^"]*\)".*//')

    if [ -z "$releases" ]; then
        dlg --msgbox "Could not fetch releases" 6 40
        return
    fi

    local tag
    tag=$(dlg --menu "Select Release" 18 50 10         $(echo "$releases" | awk '{print NR, $1}')         3>&1 1>&2 2>&3) || return

    local selected_tag
    selected_tag=$(echo "$releases" | sed -n "${tag}p")

    dlg --msgbox "Installing release: $selected_tag
This may take a while..." 7 50

    local build_dir="$LLMS_DIR/llama-$selected_tag"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    cd "$build_dir"

    wget -q "https://github.com/ggml-org/llama.cpp/archive/refs/tags/${selected_tag}.tar.gz" -O llama.tar.gz || {
        dlg --msgbox "Failed to download release" 6 40
        return
    }

    tar -xzf llama.tar.gz --strip-components=1
    rm llama.tar.gz

    dlg --msgbox "Download complete. Now building..." 6 40

    # Build Vulkan by default for this flow
    cmake -B build-vulkan -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
    cmake --build build-vulkan -- -j"$(nproc)"

    dlg --msgbox "Release $selected_tag installed to:
$build_dir/build-vulkan" 7 55
}

use_git_clone_build() {
    clone_llama
    dlg --msgbox "Repo ready. Use setup-llama.sh to build Vulkan/ROCm/Fat into llama.cpp/build-*" 7 55
}

list_detected_builds() {
    local builds=()
    while IFS= read -r b; do
        builds+=("$b" "$(basename "$b")")
    done < <(find "$LLMS_DIR" -maxdepth 2 -type d \( -name "llama-*" -o -name "build-*" \) 2>/dev/null | sort)

    if [ ${#builds[@]} -eq 0 ]; then
        dlg --msgbox "No builds detected" 6 40
        return
    fi

    dlg --menu "Detected Builds" 16 70 8 "${builds[@]}" 3>&1 1>&2 2>&3
}

run_flow() {
    local models=()
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        size=$(du -h "$f" 2>/dev/null | cut -f1)
        models+=("$f" "$(basename "$f") ($size)")
    done < <(list_models)

    if [ ${#models[@]} -eq 0 ]; then
        dlg --msgbox "No models found" 6 40
        return
    fi

    local model
    model=$(dlg --menu "Select Model" 22 75 14 "${models[@]}" 3>&1 1>&2 2>&3) || return

    local builds=()
    while IFS= read -r b; do
        builds+=("$b" "$(basename "$b")")
    done < <(list_builds)

    if [ ${#builds[@]} -eq 0 ]; then
        dlg --msgbox "No llama.cpp builds found. Run Setup first." 6 50
        return
    fi

    local build
    build=$(dlg --menu "Select Build" 16 60 8 "${builds[@]}" 3>&1 1>&2 2>&3) || return

    local backend
    backend=$(dlg --menu "Select Backend" 10 45 4 \
        Vulkan0 "Vulkan" \
        ROCm0   "ROCm (HIP)" \
        3>&1 1>&2 2>&3) || return

    local mtp
    mtp=$(dlg --menu "MTP?" 10 45 3 \
        off "Off" \
        on  "On" \
        3>&1 1>&2 2>&3) || mtp="off"

    local ctx
    ctx=$(dlg --menu "Context Size" 16 40 10 \
        8192 "8K" 16384 "16K" 32768 "32K" 65536 "64K" \
        131072 "128K" 180000 "180K" 190000 "190K" \
        200000 "200K" 220000 "220K" 240000 "240K" 262144 "256K" \
        3>&1 1>&2 2>&3) || ctx=8192

    local mtp_flag=""
    [[ "$mtp" == "on" ]] && mtp_flag="--spec-type draft-mtp"

    local kv="std"
    local mode
    mode=$(dlg --menu "Run mode" 10 48 3 \
        cli    "llama-cli" \
        server "llama-server" \
        3>&1 1>&2 2>&3) || mode="cli"
    local kv="std"

    local bin="$build/bin/llama-cli"
    [[ "$mode" == "server" ]] && bin="$build/bin/llama-server"

    if [ ! -f "$bin" ]; then
        dlg --msgbox "Binary not found: $bin" 6 50
        return
    fi

    # Show parameters before launch
    local kv_label
    [[ "$kv" == "turbo" ]] && kv_label="TurboQuant (turbo3)" || kv_label="Standard (q8_0)"

    local mtp_label
    [[ "$mtp" == "on" ]] && mtp_label="On" || mtp_label="Off"

    local confirm
    confirm=$(dlg --yesno "Launch Parameters:

Model:    $(basename "$model")
Build:    $(basename "$build")
Backend:  $backend
Context:  $ctx
MTP:      $mtp_label
KV Cache: $kv_label
Mode:     $mode

Proceed with launch?" 16 60 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return
    fi

    if [[ "$mode" == "server" ]]; then
        local port=8080
        (
            nohup "$bin" -m "$model" --port $port --host 0.0.0.0 -c "$ctx" \
                --parallel 1 --batch-size 1024 --ubatch-size 512 -ngl 99 \
                --jinja --verbosity 3 --flash-attn on \
                --cache-type-k q8_0 --cache-type-v q8_0 \
                $mtp_flag >> /tmp/llama-server.log 2>&1
        ) &
        sleep 1
        dlg --msgbox "Server started on port $port" 6 40
    else
        "$bin" -m "$model" -dev "$backend" -ngl 99 -c "$ctx" -n 128 $mtp_flag
    fi
}

quantize_flow() {
    dlg --msgbox "Quantization is currently done manually via setup-llama.sh" 6 50
}

validate_model() {
    dlg --msgbox "Validation coming soon" 6 40
}

test_model() {
    dlg --msgbox "Test coming soon" 6 40
}

benchmark_flow() {
    dlg --msgbox "Benchmark coming soon" 6 40
}

status_screen() {
    dlg --msgbox "llama.cpp Status Screen" 8 45
}

api_screen() {
    dlg --msgbox "http://localhost:8080/v1" 8 40
}

main() {
    require_dialog
    mkdir -p "$MODELS_DIR"
    main_menu
}

main "$@"
