#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLMS_DIR="${LLMS_DIR:-$HOME/llms}"
MODELS_DIR="${MODELS_DIR:-$LLMS_DIR/models}"
BENCHMARKS_DIR="${BENCHMARKS_DIR:-$LLMS_DIR/benchmarks}"

VERSION="0.6.0"

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
    if [ "$DIALOG_CMD" = "whiptail" ]; then
        echo "Note: whiptail has limited progress bar support. dialog is recommended for best experience."
        sleep 1.5
    fi
}

dlg() { "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp v$VERSION" "$@"; }

# === Progress Bar & Loading Helpers ===

is_dialog() {
    [ "$DIALOG_CMD" = "dialog" ]
}

# Show a simple infobox message (good for "Loading..." or "Please wait")
show_infobox() {
    local msg="$1"
    local h="${2:-6}"
    local w="${3:-55}"
    "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp v$VERSION" \
        --infobox "$msg" "$h" "$w"
}

# Run a long command and display its live output in a scrolling progress box.
# Excellent for cmake builds, git clone, extraction, etc.
# Usage: run_with_progressbox "Building with Vulkan..." cmake -B build-vulkan ...
run_with_progressbox() {
    local title="$1"; shift
    local height=22
    local width=95

    if is_dialog; then
        # dialog supports nice --progressbox
        "$@" 2>&1 | "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp v$VERSION" \
            --title " $title " --progressbox "$height" "$width"
        local exit_code=${PIPESTATUS[0]}
        return "$exit_code"
    else
        # whiptail fallback: just run the command with some status
        echo "=== $title ==="
        "$@"
    fi
}

# Download a file and show real progress from the download tool itself.
# We use --progressbox so you see the actual output from curl/wget (speed, %, ETA).
# This is honest — no fake or guessed percentages.
download_with_real_progress() {
    local url="$1"
    local outfile="$2"
    local title="${3:-Downloading}"

    if is_dialog; then
        # Show the tool's real progress output live
        if command -v curl &>/dev/null; then
            curl -L --fail --progress-bar "$url" -o "$outfile" 2>&1 | \
                "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp v$VERSION" \
                    --title " $title " --progressbox 10 80
            return "${PIPESTATUS[0]}"
        else
            wget --progress=bar:force:noscroll --timeout=90 --tries=2 "$url" -O "$outfile" 2>&1 | \
                "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp v$VERSION" \
                    --title " $title " --progressbox 10 80
            return "${PIPESTATUS[0]}"
        fi
    else
        # Plain fallback
        echo "Downloading: $title"
        wget --timeout=90 --tries=2 -q "$url" -O "$outfile" || return 1
    fi
}

list_models() {
    find "$MODELS_DIR" -name "*.gguf" -type f 2>/dev/null | sort
}

list_builds() {
    {
        find "$LLMS_DIR" -maxdepth 1 -type d -name "llama-*" 2>/dev/null
        [ -d "$LLMS_DIR/llama.cpp" ] && find "$LLMS_DIR/llama.cpp" -maxdepth 1 -type d -name "build-*" 2>/dev/null
    } | sort | uniq
}

find_binary() {
    local base="$1"
    local name="$2"
    if [ -x "$base/$name" ]; then
        echo "$base/$name"
    elif [ -x "$base/bin/$name" ]; then
        echo "$base/bin/$name"
    else
        echo ""
    fi
}

main_menu() {
    while true; do
        local choice
        choice=$(dlg --menu "Main Menu" 20 62 10 \
            1 "Setup llama.cpp" \
            2 "Run Inference" \
            3 "Run Benchmark" \
            4 "Show Status" \
            5 "API Endpoints" \
            6 "Quit" \
            3>&1 1>&2 2>&3) || exit 0

        case "$choice" in
            1) setup_llama ;;
            2) run_flow ;;
            3) benchmark_flow ;;
            4) status_screen ;;
            5) api_screen ;;
            6) exit 0 ;;
        esac
    done
}

setup_llama() {
    while true; do
        local choice
        choice=$(dlg --menu "Setup llama.cpp" 14 55 7 \
            1 "Install Release Version" \
            2 "Use Git Clone + build-*" \
            3 "List detected builds" \
            4 "Back" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) install_release_version ;;
            2) use_git_clone_build ;;
            3) list_detected_builds ;;
            4) return ;;
        esac
    done
}

install_release_version() {
    local releases_json
    releases_json=$(curl -sL --max-time 15 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=12" || true)

    local releases=""
    if command -v jq &>/dev/null; then
        releases=$(echo "$releases_json" | jq -r '.[].tag_name' 2>/dev/null | head -12)
    else
        # Fallback parser
        releases=$(echo "$releases_json" | grep -o '"tag_name":"[^"]*"' | sed 's/.*"tag_name":"\([^"]*\)".*/\1/' | head -12)
    fi

    if [ -z "$releases" ]; then
        dlg --msgbox "Could not fetch releases from GitHub.\n\nInstall 'jq' for more reliable parsing." 8 55
        return
    fi

    local menu_items=()
    while IFS= read -r tag; do
        [ -n "$tag" ] && menu_items+=("$tag" "$tag")
    done <<< "$releases"

    local selected_tag
    selected_tag=$(dlg --menu "Select Release" 18 50 10 "${menu_items[@]}" 3>&1 1>&2 2>&3) || return

    local build_type
    build_type=$(dlg --menu "Choose binary type" 10 45 3 \
        vulkan "Vulkan (x86_64)" \
        rocm   "ROCm (x86_64)" \
        3>&1 1>&2 2>&3) || return

    # === Simple & direct download (as requested) ===
    local archive_name
    if [[ "$build_type" == "vulkan" ]]; then
        archive_name="llama-${selected_tag}-bin-ubuntu-vulkan-x64.tar.gz"
    else
        archive_name="llama-${selected_tag}-bin-ubuntu-rocm-7.2-x64.tar.gz"
    fi

    local download_url="https://github.com/ggml-org/llama.cpp/releases/download/${selected_tag}/${archive_name}"
    local tmp_archive="/tmp/${archive_name}"

    # Download with live progress
    if ! download_with_real_progress "$download_url" "$tmp_archive" "Downloading $archive_name"; then
        # Try common ROCm version fallback
        if [[ "$build_type" == "rocm" ]]; then
            rm -f "$tmp_archive"
            archive_name="llama-${selected_tag}-bin-ubuntu-rocm-7.3-x64.tar.gz"
            download_url="https://github.com/ggml-org/llama.cpp/releases/download/${selected_tag}/${archive_name}"
            tmp_archive="/tmp/${archive_name}"
            if ! download_with_real_progress "$download_url" "$tmp_archive" "Downloading $archive_name (fallback)"; then
                dlg --msgbox "Download failed for $archive_name" 8 50
                rm -f "$tmp_archive"
                return
            fi
        else
            dlg --msgbox "Failed to download:\n$archive_name" 8 50
            rm -f "$tmp_archive"
            return
        fi
    fi

    # Determine final directory name based on selected engine
    local engine
    [[ "$build_type" == "vulkan" ]] && engine="vulkan" || engine="rocm"

    local final_name="llama-${selected_tag}-${engine}"
    local target_dir="$LLMS_DIR/$final_name"

    # Handle existing directory
    if [ -d "$target_dir" ]; then
        dlg --yesno "Directory $target_dir already exists.\nOverwrite?" 8 60 || {
            rm -f "$tmp_archive"
            return
        }
        rm -rf "$target_dir"
    fi

    # Extract the tarball into a temporary location first
    local extract_tmp
    extract_tmp=$(mktemp -d)

    if ! tar_output=$(tar -xzf "$tmp_archive" -C "$extract_tmp" 2>&1); then
        dlg --msgbox "Extraction failed for $archive_name\n\nError from tar:\n$tar_output" 12 70
        rm -rf "$extract_tmp" "$tmp_archive"
        return
    fi

    rm -f "$tmp_archive"

    # Find the directory that was created by the tarball (usually "llama-bXXXX")
    local extracted_dir
    extracted_dir=$(find "$extract_tmp" -mindepth 1 -maxdepth 1 -type d | head -1)

    if [ -z "$extracted_dir" ]; then
        # Fallback: if the tarball extracted files directly (rare for these releases)
        extracted_dir="$extract_tmp"
    fi

    # Move/rename it to our desired final name
    mv "$extracted_dir" "$target_dir" || {
        dlg --msgbox "Failed to place extracted files into $target_dir" 8 50
        rm -rf "$extract_tmp"
        return
    }

    rm -rf "$extract_tmp"

    # Verify something useful was installed
    local found_exe
    found_exe=$(find "$target_dir" -maxdepth 2 -type f -executable \( -name 'llama-cli' -o -name 'llama-server' \) 2>/dev/null | head -1)

    if [ -n "$found_exe" ]; then
        dlg --msgbox "Installed successfully!\n\nLocation: $target_dir\n\nOriginal tarball structure preserved.\nYou can now select this build from 'Run Inference'." 12 65
    else
        dlg --msgbox "Download + extract finished, but no llama executables were found.\n\nCheck manually: $target_dir" 10 60
    fi
}

use_git_clone_build() {
    dlg --msgbox "Launching build helper.\n\nLong builds will show live real-time output from cmake/make." 8 55
    "$SCRIPT_DIR/setup-llama.sh" || dlg --msgbox "Build process failed. Check the terminal output for details." 7 55
}

list_detected_builds() {
    local builds=()
    while IFS= read -r b; do builds+=("$b" "$(basename "$b")"); done < <(list_builds)

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
    while IFS= read -r b; do builds+=("$b" "$(basename "$b")"); done < <(list_builds)

    if [ ${#builds[@]} -eq 0 ]; then
        dlg --msgbox "No builds found. Run Setup first." 6 50
        return
    fi

    local build
    build=$(dlg --menu "Select Build" 16 60 8 "${builds[@]}" 3>&1 1>&2 2>&3) || return

    # Infer backend from build directory name when possible (new release naming)
    local backend=""
    local use_dev_flag=""

    if [[ "$build" == *"-rocm"* || "$build" == *"build-rocm"* ]]; then
        backend="HIP"
        use_dev_flag=""          # These prebuilts are already backend-specific
    elif [[ "$build" == *"-vulkan"* || "$build" == *"build-vulkan"* ]]; then
        backend="Vulkan"
        use_dev_flag=""
    else
        # Only ask if we can't infer (e.g. source builds like build-vulkan)
        backend=$(dlg --menu "Select Backend" 10 45 4 \
            Vulkan "Vulkan" \
            HIP    "ROCm (HIP)" \
            3>&1 1>&2 2>&3) || return
        use_dev_flag="-dev $backend"
    fi

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

    local flash_attn
    flash_attn=$(dlg --menu "Flash Attention (--flash-attn)" 12 55 4 \
        auto "auto (recommended)" \
        on   "on" \
        off  "off" \
        3>&1 1>&2 2>&3) || flash_attn="auto"

    # === Batching Parameters ===
    local parallel
    parallel=$(dlg --menu "Parallel Sequences (--parallel)" 14 72 5 \
        1 "1  - Best for single user / lowest VRAM usage" \
        2 "2  - Good balance for most people" \
        4 "4  - Higher throughput (needs more VRAM)" \
        8 "8  - Max throughput (high VRAM usage)" \
        3>&1 1>&2 2>&3) || parallel=1

    local batch_size
    batch_size=$(dlg --menu "Batch Size (--batch-size)" 14 72 5 \
        512  "512  - Very safe, lower memory use" \
        1024 "1024 - Solid default for most models" \
        2048 "2048 - Recommended for 7900 XTX" \
        4096 "4096 - Aggressive (high VRAM required)" \
        3>&1 1>&2 2>&3) || batch_size=2048

    local ubatch_size
    ubatch_size=$(dlg --menu "Micro Batch Size (--ubatch-size)" 14 72 5 \
        256  "256  - Very safe" \
        512  "512  - Good default" \
        1024 "1024 - Faster per-batch processing" \
        3>&1 1>&2 2>&3) || ubatch_size=512

    local ngl
    ngl=$(dlg --menu "GPU Layers Offload (-ngl / --n-gpu-layers)" 16 78 7 \
        99  "99  - Offload as much as possible to VRAM (recommended for 7900 XTX)" \
        80  "80  - High VRAM usage, lower system RAM usage" \
        60  "60  - Medium-high VRAM usage" \
        40  "40  - Medium VRAM usage" \
        20  "20  - Low VRAM usage (more layers stay in system RAM)" \
        0   "0   - CPU only (everything in system RAM)" \
        3>&1 1>&2 2>&3) || ngl=99

    # === Additional Performance Options ===
    local cont_batching
    cont_batching=$(dlg --menu "Continuous Batching (--cont-batching)" 12 72 3 \
        on  "on  - Recommended for servers (better throughput with multiple requests)" \
        off "off - Simpler, can be more stable for single-user use" \
        3>&1 1>&2 2>&3) || cont_batching="on"

    local mmap
    mmap=$(dlg --menu "Memory Map Model (--mmap)" 12 72 3 \
        on  "on  - Recommended. Uses less system RAM. Model still loads into VRAM via -ngl." \
        off "off - Load full model into system RAM first (then offload to VRAM)." \
        3>&1 1>&2 2>&3) || mmap="on"

    local mlock
    mlock=$(dlg --menu "Lock Model in RAM (--mlock)" 12 72 3 \
        off "off - Recommended. Avoid forcing model into system RAM." \
        on  "on  - Lock into system RAM (prevents swap, uses more system memory)." \
        3>&1 1>&2 2>&3) || mlock="off"

    local mode
    mode=$(dlg --menu "Run mode" 10 48 3 \
        cli    "llama-cli" \
        server "llama-server" \
        3>&1 1>&2 2>&3) || mode="cli"

    local kv
    kv=$(dlg --menu "KV Cache" 10 55 4 \
        q8_0 "q8_0 - Recommended for most models" \
        q4_0 "q4_0 - More aggressive quantization" \
        3>&1 1>&2 2>&3) || kv="q8_0"

    local cache_flags
    if [[ "$kv" == "q4_0" ]]; then
        cache_flags="--cache-type-k q4_0 --cache-type-v q4_0"
    else
        cache_flags="--cache-type-k q8_0 --cache-type-v q8_0"
    fi

    # Parameter review
    local mtp_label
    [[ "$mtp" == "on" ]] && mtp_label="On" || mtp_label="Off"

    if ! dlg --yesno "Launch Parameters:

Model:     $(basename "$model")
Build:     $(basename "$build")
Backend:   $backend
Context:   $ctx
MTP:       $mtp_label
KV Cache:  $kv
FlashAttn: $flash_attn

--parallel:     $parallel
--batch-size:   $batch_size
--ubatch-size:  $ubatch_size
-ngl:           $ngl

--cont-batching: $cont_batching
--mmap:         $mmap     (system RAM)
--mlock:        $mlock    (system RAM)

Mode:      $mode

Proceed?" 24 55; then
        return
    fi

    local cli_bin
    cli_bin=$(find_binary "$build" "llama-cli")

    local bin="$cli_bin"
    if [[ "$mode" == "server" ]]; then
        bin=$(find_binary "$build" "llama-server")
    fi

    if [ -z "$bin" ] || [ ! -f "$bin" ]; then
        dlg --msgbox "Binary not found for $mode\n\nSearched in:\n  $build/\n  $build/bin/\n\nBuild may be incomplete." 11 55
        return
    fi

    if [[ "$mode" == "server" ]]; then
        local port=8080
        show_infobox "Starting llama-server...\n\nLoading model into VRAM.\nWatch the log for real progress."

        # Build server command safely (avoid empty args)
        local server_args=(
            -m "$model"
            --port "$port"
            --host 0.0.0.0
            -c "$ctx"
            --parallel "$parallel"
            --batch-size "$batch_size"
            --ubatch-size "$ubatch_size"
            -ngl "$ngl"
            --jinja
            --verbosity 3
        )

        # Add flash-attn with proper on/off/auto value
        server_args+=(--flash-attn "$flash_attn")

        if [ -n "$use_dev_flag" ]; then
            server_args+=($use_dev_flag)
        fi

        # Additional performance options
        if [[ "$cont_batching" == "on" ]]; then
            server_args+=(--cont-batching)
        fi

        if [[ "$mmap" == "on" ]]; then
            server_args+=(--mmap)
        else
            server_args+=(--no-mmap)
        fi

        if [[ "$mlock" == "on" ]]; then
            server_args+=(--mlock)
        fi

        # Add cache flags only if set
        if [ -n "$cache_flags" ]; then
            # shellcheck disable=SC2206
            server_args+=($cache_flags)
        fi

        # Add MTP flags only if enabled
        if [ -n "$mtp_flag" ]; then
            # shellcheck disable=SC2206
            server_args+=($mtp_flag --spec-draft-n-max 2 --spec-draft-p-min 0.75)
        fi

        # Show exact command for debugging
        local server_cmd="$bin ${server_args[*]}"
        if ! dlg --yesno "About to run server:\n\n$server_cmd\n\nProceed?" 14 80; then
            return
        fi

        (
            nohup "$bin" "${server_args[@]}" \
                >> /tmp/llama-server.log 2>&1
        ) &

        sleep 1

        if is_dialog; then
            "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp v$VERSION" \
                --title " llama-server startup log (press OK or ESC to close) " \
                --tailbox /tmp/llama-server.log 26 130
        fi

        dlg --msgbox "Server launched on port $port\n\nLog file: /tmp/llama-server.log" 8 50
    else
        show_infobox "Loading model with $backend backend..."

        local cli_args=(
            -m "$model"
            -ngl "$ngl"
            -c "$ctx"
            -n -1
            --parallel "$parallel"
            --batch-size "$batch_size"
            --ubatch-size "$ubatch_size"
        )

        if [ -n "$use_dev_flag" ]; then
            cli_args+=($use_dev_flag)
        fi

        cli_args+=(--flash-attn "$flash_attn")

        # Additional performance options
        if [[ "$cont_batching" == "on" ]]; then
            cli_args+=(--cont-batching)
        fi

        if [[ "$mmap" == "on" ]]; then
            cli_args+=(--mmap)
        else
            cli_args+=(--no-mmap)
        fi

        if [[ "$mlock" == "on" ]]; then
            cli_args+=(--mlock)
        fi

        if [ -n "$mtp_flag" ]; then
            # shellcheck disable=SC2206
            cli_args+=($mtp_flag)
        fi

        "$bin" "${cli_args[@]}"
    fi
}

benchmark_flow() {
    # Pick model
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
    model=$(dlg --menu "Select Model for Benchmark" 22 75 14 "${models[@]}" 3>&1 1>&2 2>&3) || return

    if [ ! -f "$model" ]; then
        dlg --msgbox "Selected model file does not exist:\n\n$model" 8 70
        return
    fi

    # Pick build
    local builds=()
    while IFS= read -r b; do builds+=("$b" "$(basename "$b")"); done < <(list_builds)

    if [ ${#builds[@]} -eq 0 ]; then
        dlg --msgbox "No builds found. Run Setup first." 6 50
        return
    fi

    local build
    build=$(dlg --menu "Select Build for Benchmark" 16 60 8 "${builds[@]}" 3>&1 1>&2 2>&3) || return

    # Infer backend from build name
    local backend=""
    local use_dev_flag=""

    if [[ "$build" == *"-rocm"* || "$build" == *"build-rocm"* ]]; then
        backend="HIP"
        use_dev_flag=""          # Prebuilt ROCm builds don't need -dev
    elif [[ "$build" == *"-vulkan"* || "$build" == *"build-vulkan"* ]]; then
        backend="Vulkan"
        use_dev_flag=""          # Prebuilt Vulkan builds don't need -dev
    else
        backend=$(dlg --menu "Select Backend" 10 45 4 \
            Vulkan "Vulkan" \
            HIP    "ROCm (HIP)" \
            3>&1 1>&2 2>&3) || return
        use_dev_flag="-dev $backend"
    fi

    # Walk through common benchmark parameters (similar to run inference)
    local prompt_size
    prompt_size=$(dlg --menu "Prompt Size (-p)" 14 50 6 \
        512 "512 tokens" \
        1024 "1024 tokens" \
        2048 "2048 tokens" \
        4096 "4096 tokens" \
        3>&1 1>&2 2>&3) || prompt_size=512

    local gen_size
    gen_size=$(dlg --menu "Generation Length (-n)" 14 50 6 \
        128 "128 tokens" \
        256 "256 tokens" \
        512 "512 tokens" \
        3>&1 1>&2 2>&3) || gen_size=128

    local ngl
    ngl=$(dlg --menu "GPU Layers Offload (-ngl / --n-gpu-layers)" 16 78 7 \
        99  "99  - Offload as much as possible to VRAM (recommended for 7900 XTX)" \
        80  "80  - High VRAM usage, lower system RAM usage" \
        60  "60  - Medium-high VRAM usage" \
        40  "40  - Medium VRAM usage" \
        20  "20  - Low VRAM usage (more layers stay in system RAM)" \
        0   "0   - CPU only (everything in system RAM)" \
        3>&1 1>&2 2>&3) || ngl=99

    # === Additional Performance Options (same as Run Inference) ===
    local cont_batching
    cont_batching=$(dlg --menu "Continuous Batching (--cont-batching)" 12 72 3 \
        on  "on  - Recommended for realistic server-like benchmarking" \
        off "off - Simpler scheduling" \
        3>&1 1>&2 2>&3) || cont_batching="on"

    local mmap
    mmap=$(dlg --menu "Memory Map Model (--mmap)" 12 72 3 \
        on  "on  - Recommended. Uses less system RAM. Model still loads into VRAM via -ngl." \
        off "off - Load full model into system RAM first (then offload to VRAM)." \
        3>&1 1>&2 2>&3) || mmap="on"

    local mlock
    mlock=$(dlg --menu "Lock Model in RAM (--mlock)" 12 72 3 \
        off "off - Recommended. Avoid forcing model into system RAM." \
        on  "on  - Lock into system RAM (prevents swap, uses more system memory)." \
        3>&1 1>&2 2>&3) || mlock="off"

    local reps
    reps=$(dlg --menu "Number of Runs (-r)" 12 50 4 \
        3 "3 runs (default)" \
        5 "5 runs" \
        1 "1 run (quick)" \
        3>&1 1>&2 2>&3) || reps=3

    local use_flash
    use_flash=$(dlg --menu "Flash Attention (--flash-attn)" 10 55 3 \
        1 "On (1) - Recommended on modern GPUs" \
        0 "Off (0)" \
        3>&1 1>&2 2>&3) || use_flash=1

    # Find the bench binary (support both layouts)
    local bench_bin
    if [ -x "$build/llama-bench" ]; then
        bench_bin="$build/llama-bench"
    elif [ -x "$build/bin/llama-bench" ]; then
        bench_bin="$build/bin/llama-bench"
    else
        dlg --msgbox "llama-bench not found in this build." 6 50
        return
    fi

    # Confirm
    if ! dlg --yesno "Benchmark Parameters:

Model:   $(basename "$model")
Build:   $(basename "$build")
Backend: $backend

-p: $prompt_size
-n: $gen_size
-ngl: $ngl
-r:  $reps
--flash-attn: $use_flash

--cont-batching: $cont_batching
--mmap:          $mmap     (system RAM)
--mlock:         $mlock    (system RAM)

Run benchmark?" 20 55; then
        return
    fi

    # Build command using correct flags from llama-bench --help
    local bench_args=(
        -m "$model"
        -p "$prompt_size"
        -n "$gen_size"
        -ngl "$ngl"
        -r "$reps"
        -b 512
        -ub 512
        --flash-attn "$use_flash"
    )

    # Additional performance options (structured for llama-bench)
    if [[ "$cont_batching" == "on" ]]; then
        bench_args+=(--cont-batching)
    fi

    if [[ "$mmap" == "on" ]]; then
        bench_args+=(--mmap)
    else
        bench_args+=(--no-mmap)
    fi

    if [[ "$mlock" == "on" ]]; then
        bench_args+=(--mlock)
    fi

    # Only add -dev for builds that need it (source builds)
    if [ -n "$use_dev_flag" ]; then
        bench_args+=($use_dev_flag)
    fi

    # Show the exact command for debugging / transparency
    local cmd_str="$bench_bin ${bench_args[*]}"
    if ! dlg --yesno "About to run:\n\n$cmd_str\n\nProceed?" 14 85; then
        return
    fi

    # Clear the "Running..." message before starting the long command
    clear

    # Run llama-bench safely (protect against set -e)
    local bench_status=0
    local stdout_file
    local stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)

    set +e
    "$bench_bin" "${bench_args[@]}" > "$stdout_file" 2> "$stderr_file"
    bench_status=$?
    set -e

    local bench_stdout
    local bench_stderr
    bench_stdout=$(cat "$stdout_file")
    bench_stderr=$(cat "$stderr_file")
    rm -f "$stdout_file" "$stderr_file"

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local safe_build
    safe_build=$(basename "$build" | tr -c '[:alnum:]_.-' '_')
    local result_file="$BENCHMARKS_DIR/benchmark-${safe_build}-${timestamp}.txt"

    # Save results + command used + any stderr
    {
        echo "=== Benchmark run: $timestamp ==="
        echo "Command:"
        echo "  $cmd_str"
        echo ""
        echo "=== stdout ==="
        echo "$bench_stdout"
        if [ -n "$bench_stderr" ]; then
            echo ""
            echo "=== stderr ==="
            echo "$bench_stderr"
        fi
    } > "$result_file"

    # Combine for display
    local display_output="$bench_stdout"
    if [ -n "$bench_stderr" ]; then
        display_output="$display_output"$'\n\n'"--- stderr (may contain non-fatal messages) ---"$'\n'"$bench_stderr"
    fi

    if [ $bench_status -eq 0 ]; then
        # Explicit success message pointing to the saved file
        dlg --msgbox "Benchmark completed successfully!\n\nResults saved to:\n$result_file\n\nPress OK to view the detailed output." 12 70

        # Show results directly from the saved file (much more reliable)
        "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp v$VERSION" \
            --title " llama-bench results " \
            --textbox "$result_file" 30 95
    else
        # Failure - use the saved file
        "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp v$VERSION" \
            --title " llama-bench error " \
            --textbox "$result_file" 28 95
    fi
}

status_screen() {
    # Run the entire status screen with set +e to prevent any
    # non-critical command (grep, find, wc, dialog return codes, etc.)
    # from killing the TUI.
    set +e

    local status="llama.cpp Status\n\n"

    # Running instances detection
    local running=""
    local processes
    local has_server=0
    local server_pids=()

    processes=$(ps -eo pid=,args= 2>/dev/null | grep -E '(llama-server|llama-cli)' | grep -v grep | head -10)

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local pid cmd
        pid=$(echo "$line" | awk '{print $1}')
        cmd=$(echo "$line" | cut -d' ' -f2-)

        local is_server=0
        if echo "$cmd" | grep -q "llama-server"; then
            is_server=1
            has_server=1
            server_pids+=("$pid")
        fi

        local model=""
        local port=""
        echo "$cmd" | grep -q -- "-m " && model=$(echo "$cmd" | sed -n 's/.*-m \([^ ]*\).*/\1/p' | xargs basename 2>/dev/null)
        echo "$cmd" | grep -q -- "--port " && port=$(echo "$cmd" | sed -n 's/.*--port \([^ ]*\).*/\1/p')

        local label="PID $pid"
        if [ "$is_server" = 1 ]; then
            label+=" [SERVER]"
        fi
        [ -n "$model" ] && label+=" | Model: $model"
        [ -n "$port" ] && label+=" | Port: $port"

        running+="  $label\n"
    done <<< "$processes"

    if [ -n "$running" ]; then
        status+="Running llama.cpp instances:\n$running\n"
    else
        status+="No running llama.cpp instances detected.\n\n"
    fi

    # Builds
    status+="Models dir: $MODELS_DIR\n"
    status+="Models found: $(list_models 2>/dev/null | wc -l || echo 0)\n\n"

    local builds
    builds=$(list_builds 2>/dev/null || true)
    if [ -n "$builds" ]; then
        status+="Detected builds:\n"
        while IFS= read -r b; do
            local bin_count=0
            if [ -d "$b/bin" ]; then
                bin_count=$(find "$b/bin" -maxdepth 1 -type f -executable 2>/dev/null | wc -l || echo 0)
            fi
            local flat_count
            flat_count=$(find "$b" -maxdepth 1 -type f -executable -name 'llama-*' 2>/dev/null | wc -l || echo 0)
            bin_count=$((bin_count + flat_count))
            status+="  $(basename "$b") — $bin_count executables\n"
        done <<< "$builds"
    else
        status+="No builds detected.\n"
    fi

    dlg --msgbox "$status" 20 75

    # Offer to view live logs if a llama-server is running
    if [ "$has_server" = 1 ] && [ -f /tmp/llama-server.log ]; then
        if is_dialog; then
            if dlg --yesno "A llama-server is currently running.\n\nView live logs from /tmp/llama-server.log?" 8 55; then
                "$DIALOG_CMD" --backtitle "Don RDNA Lab — llama.cpp v$VERSION" \
                    --title " llama-server log (↑↓/PgUp/PgDn/Home/End to scroll • ESC/q to close) " \
                    --tailbox /tmp/llama-server.log 34 140
            fi
        else
            if dlg --yesno "A llama-server is currently running.\n\nLog file: /tmp/llama-server.log\n\nOpen it with 'less +F' (full width + follow mode) in another terminal?" 11 65; then
                echo ""
                echo "Recommended command (gives full terminal width + live follow):"
                echo "  less +F /tmp/llama-server.log"
                echo ""
                read -p "Press Enter to continue..."
            fi
        fi
    elif [ "$has_server" = 1 ]; then
        dlg --msgbox "A llama-server appears to be running, but /tmp/llama-server.log was not found." 8 60
    fi

    # Offer to kill running server(s)
    if [ "$has_server" = 1 ] && [ ${#server_pids[@]} -gt 0 ]; then
        if dlg --yesno "Kill the running llama-server process(es)?\n\nPIDs: ${server_pids[*]}" 10 55; then
            for pid in "${server_pids[@]}"; do
                kill "$pid" 2>/dev/null
            done
            dlg --msgbox "Termination signal sent to server process(es).\n\nYou may want to check Status again in a moment." 8 60
        fi
    fi

    set -e  # RESTORE before returning
}


api_screen() {
    dlg --msgbox "OpenAI-compatible API endpoint:\n\nhttp://localhost:8080/v1\n\nStart a server via 'Run Inference' → server mode.\n\nTest with:\ncurl http://localhost:8080/v1/models" 12 60
}

check_prereqs() {
    local missing=()
    for cmd in git cmake curl wget; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    local notes=""
    command -v rocminfo &>/dev/null && command -v hipcc &>/dev/null && notes+="ROCm SDK detected\n"
    command -v vulkaninfo &>/dev/null && command -v glslc &>/dev/null && notes+="Vulkan SDK detected\n"

    if [ ${#missing[@]} -gt 0 ] || [ -n "$notes" ]; then
        local msg=""
        [ ${#missing[@]} -gt 0 ] && msg+="Missing required tools:\n${missing[*]}\n\n"
        [ -n "$notes" ] && msg+="$notes"
        dlg --msgbox "$msg" 10 55
    fi
}

main() {
    require_dialog
    mkdir -p "$MODELS_DIR" "$BENCHMARKS_DIR"
    check_prereqs
    main_menu
}

main "$@"
