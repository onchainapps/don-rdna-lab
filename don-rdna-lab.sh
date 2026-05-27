#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLMS_DIR="${LLMS_DIR:-$HOME/llms}"
MODELS_DIR="${MODELS_DIR:-$LLMS_DIR/models}"

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

dlg() { "$DIALOG_CMD" --backtitle "Don RDNA Lab — TurboQuant" "$@"; }

list_models() {
    find "$MODELS_DIR" \( -name "*.gguf" -o -name "*.guff" \) -type f 2>/dev/null | sort
}

main_menu() {
    while true; do
        local choice
        choice=$(dlg --menu "Main Menu" 20 60 11 \
            1 "Setup TurboQuant" \
            2 "Run Inference" \
            3 "Quantize Model" \
            4 "Validate Quantized Model" \
            5 "Test Quantized Model" \
            6 "Run Benchmark" \
            7 "Show Status" \
            8 "API Endpoints & Examples" \
            9 "Quit" \
            3>&1 1>&2 2>&3) || exit 0

        case "$choice" in
            1) setup_flow ;;
            2) run_flow ;;
            3) quantize_flow ;;
            4) validate_quantized_model ;;
            5) test_quantized_model ;;
            6) benchmark_flow ;;
            7) status_screen ;;
            8) api_endpoints_screen ;;
            9) exit 0 ;;
        esac
    done
}

setup_flow() {
    while true; do
        local choice
        choice=$(dlg --menu "Setup TurboQuant" 12 50 5 \
            1 "Clone repo" \
            2 "Build (Fat)" \
            3 "Build (Vulkan)" \
            4 "Build (ROCm)" \
            5 "Back" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) "$SCRIPT_DIR/setup-turboquant.sh" clone || true ;;
            2) "$SCRIPT_DIR/setup-turboquant.sh" build-fat || true ;;
            3) "$SCRIPT_DIR/setup-turboquant.sh" build-vulkan || true ;;
            4) "$SCRIPT_DIR/setup-turboquant.sh" build-rocm || true ;;
            5) return ;;
        esac
        dlg --msgbox "Done." 6 30
    done
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

    local mode
    mode=$(dlg --menu "Run mode" 10 48 3 \
        cli    "llama-cli" \
        server "llama-server" \
        3>&1 1>&2 2>&3) || mode="cli"

    if [[ "$mode" == "server" ]]; then
        local kv
        kv=$(dlg --menu "KV Cache" 10 50 3 \
            turbo "TurboQuant (turbo3)" \
            std   "Standard (q8_0)" \
            3>&1 1>&2 2>&3) || kv="turbo"

        local cache_flags
        [[ "$kv" == "turbo" ]] && cache_flags="--cache-type-k q8_0 --cache-type-v turbo3" || cache_flags="--cache-type-k q8_0 --cache-type-v q8_0"

        local port=8080
        local bin=""
        if [[ "$backend" == "Vulkan0" ]]; then
            [ -d "$LLMS_DIR/llama-cpp-turboquant/build-vulkan/bin" ] && bin="$LLMS_DIR/llama-cpp-turboquant/build-vulkan/bin/llama-server"
            [ -z "$bin" ] && [ -d "$LLMS_DIR/llama-cpp-turboquant/build-fat/bin" ] && bin="$LLMS_DIR/llama-cpp-turboquant/build-fat/bin/llama-server"
        else
            [ -d "$LLMS_DIR/llama-cpp-turboquant/build-rocm/bin" ] && bin="$LLMS_DIR/llama-cpp-turboquant/build-rocm/bin/llama-server"
            [ -z "$bin" ] && [ -d "$LLMS_DIR/llama-cpp-turboquant/build-fat/bin" ] && bin="$LLMS_DIR/llama-cpp-turboquant/build-fat/bin/llama-server"
        fi

        if [ -z "$bin" ] || [ ! -f "$bin" ]; then
            dlg --msgbox "No llama-server binary found" 6 45
            return
        fi

        (
            nohup "$bin" -m "$model" --port $port --host 0.0.0.0 -c "$ctx" \
                --parallel 1 --batch-size 1024 --ubatch-size 512 -ngl 99 \
                --jinja --verbosity 3 --flash-attn on $cache_flags $mtp_flag \
                --spec-draft-n-max 2 --spec-draft-p-min 0.75 \
                >> /tmp/llama-server.log 2>&1
        ) &
        sleep 1
        dlg --msgbox "Server started on port $port" 6 40
    else
        "$SCRIPT_DIR/setup-turboquant.sh" run "$model" "$backend" "$ctx" 128 $mtp_flag
    fi
}

quantize_flow() {
    local models=()
    while IFS= read -r m; do models+=("$m" "$(basename "$m")"); done < <(list_models)

    if [ ${#models[@]} -eq 0 ]; then
        dlg --msgbox "No models found in models/ folder" 6 50
        return
    fi

    local model
    model=$(dlg --menu "Select BF16 Model to Quantize" 20 75 12 "${models[@]}" 3>&1 1>&2 2>&3) || return

    local qtype
    qtype=$(dlg --menu "Weight Quantization (default: TQ4_1S)" 10 50 3         TQ4_1S "TQ4_1S (~4.5 bits) - Recommended"         TQ3_1S "TQ3_1S (~3.5 bits)"         3>&1 1>&2 2>&3) || qtype="TQ4_1S"

    local kvtype
    kvtype=$(dlg --menu "KV Cache Quantization (default: turbo3)" 12 55 5         turbo3 "turbo3 (~3.5 bits) - Recommended"         turbo2 "turbo2 (~2.0 bits) - Aggressive"         turbo4 "turbo4 (~4.5 bits) - Highest quality"         none   "No KV cache quantization"         3>&1 1>&2 2>&3) || kvtype="turbo3"

    local framework
    framework=$(dlg --menu "Quantize using which build?" 10 50 3         rocm   "ROCm (recommended for turbo KV)"         vulkan "Vulkan"         3>&1 1>&2 2>&3) || framework="rocm"

    # Only pass weight quantization type
    "$SCRIPT_DIR/setup-turboquant.sh" quantize "$model" "" "$qtype"

    if [[ "$kvtype" != "none" ]]; then
        dlg --msgbox "Note: KV cache ($kvtype) is applied at runtime via -ctk/-ctv, not during quantization." 7 60
    fi
}
validate_quantized_model() { echo "Validate"; }
test_quantized_model() { echo "Test"; }
benchmark_flow() {
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
    model=$(dlg --menu "Select Model" 20 75 12 "${models[@]}" 3>&1 1>&2 2>&3) || return

    local backend
    backend=$(dlg --menu "Select Backend" 10 45 4         Vulkan0 "Vulkan"         ROCm0   "ROCm (HIP)"         3>&1 1>&2 2>&3) || return

    local bin=""
    if [[ "$backend" == "Vulkan0" ]]; then
        [ -d "$LLMS_DIR/llama-cpp-turboquant/build-vulkan/bin" ] && bin="$LLMS_DIR/llama-cpp-turboquant/build-vulkan/bin/llama-bench"
        [ -z "$bin" ] && [ -d "$LLMS_DIR/llama-cpp-turboquant/build-fat/bin" ] && bin="$LLMS_DIR/llama-cpp-turboquant/build-fat/bin/llama-bench"
    else
        [ -d "$LLMS_DIR/llama-cpp-turboquant/build-rocm/bin" ] && bin="$LLMS_DIR/llama-cpp-turboquant/build-rocm/bin/llama-bench"
        [ -z "$bin" ] && [ -d "$LLMS_DIR/llama-cpp-turboquant/build-fat/bin" ] && bin="$LLMS_DIR/llama-cpp-turboquant/build-fat/bin/llama-bench"
    fi

    if [ -z "$bin" ] || [ ! -f "$bin" ]; then
        dlg --msgbox "No llama-bench binary found for $backend" 6 50
        return
    fi

    local result_file="$LLMS_DIR/results/benchmark_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "$LLMS_DIR/results"

    dlg --msgbox "Running benchmark...\nResults saved to:\n$result_file" 7 50

    "$bin" -m "$model" -ngl 99 -b 512 -ub 512 -n 128 -p 512 -dev "$backend"         2>&1 | tee -a "$result_file"

    dlg --msgbox "Benchmark complete!\nResults: $result_file" 6 50
}
status_screen() { dlg --msgbox "TurboQuant Status" 8 40; }
api_endpoints_screen() { dlg --msgbox "http://localhost:8080/v1" 8 40; }

main() {
    require_dialog
    mkdir -p "$MODELS_DIR"
    main_menu
}

main "$@"
