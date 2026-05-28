# Don RDNA Lab — llama.cpp

A practical **Terminal User Interface (TUI)** for running large language models on AMD Radeon RX 7900 XTX (RDNA3) GPUs using **llama.cpp**.

It provides an easy way to:
- Install official prebuilt releases (Vulkan or ROCm)
- Build from source
- Run interactive inference or OpenAI-compatible servers
- Run benchmarks
- Monitor running instances

---

## Directory Structure & File Locations

By default everything lives under `~/llms/` (customizable via environment variables).

| Path                              | Purpose                                      | Notes |
|-----------------------------------|----------------------------------------------|-------|
| `~/llms/models/`                  | Your GGUF model files                        | Scanned by "Run Inference" and "Run Benchmark" |
| `~/llms/benchmarks/`              | Saved benchmark results                      | Auto-created. One `.txt` file per run |
| `~/llms/llama-<tag>-vulkan/`      | Official Vulkan prebuilt releases            | e.g. `llama-b9380-vulkan` |
| `~/llms/llama-<tag>-rocm/`        | Official ROCm prebuilt releases              | e.g. `llama-b9380-rocm` |
| `~/llms/llama.cpp/`               | Source checkout (when using Git + Build)     | Contains `build-vulkan/`, `build-rocm/`, etc. |
| `/tmp/llama-server.log`           | Live logs from the last launched server      | Used by "Show Status → View Logs" |

### Environment Variables

You can override the default locations:

```bash
export LLMS_DIR="$HOME/llms"           # Root directory
export MODELS_DIR="$LLMS_DIR/models"
export BENCHMARKS_DIR="$LLMS_DIR/benchmarks"

./don-rdna-lab.sh
```

---

## Main Menu

### 1. Setup llama.cpp

Sub-menu for installing and managing llama.cpp builds.

#### 1.1 Install Release Version
- Downloads official prebuilt binaries directly from the [llama.cpp GitHub releases](https://github.com/ggml-org/llama.cpp/releases).
- You choose a tag (e.g. `b9380`) and backend (**Vulkan** or **ROCm**).
- The release is extracted and installed to:
  - `~/llms/llama-<tag>-vulkan/` or
  - `~/llms/llama-<tag>-rocm/`
- These directories are automatically detected by the rest of the TUI.

#### 1.2 Use Git Clone + build-*
- Launches `setup-llama.sh`
- Lets you clone/update the llama.cpp source and build it yourself.
- Creates directories inside `~/llms/llama.cpp/` such as:
  - `build-vulkan/`
  - `build-rocm/`
  - `build-fat/`

#### 1.3 List detected builds
- Shows all currently detected builds (both release prebuilts and source builds).

---

### 2. Run Inference

The main way to actually use models.

**Flow:**
1. Select a GGUF model from `~/llms/models/`
2. Select a build (the list shows both release and source builds)
3. **Backend is auto-detected** when possible:
   - Builds named `llama-*-vulkan` or `build-vulkan` → Vulkan
   - Builds named `llama-*-rocm` or `build-rocm` → ROCm/HIP
   - For ambiguous builds you will be asked to choose
4. Choose options:
   - MTP (speculative decoding) on/off
   - Context size (up to 256K)
   - KV Cache type (`q8_0` or `q4_0`)
   - Flash Attention (`auto` / `on` / `off`)
5. Choose mode:
   - **llama-cli** → Interactive chat
   - **llama-server** → Starts an OpenAI-compatible server on port 8080 (logs go to `/tmp/llama-server.log`)

Before launching, you see a final confirmation screen with all parameters.

---

### 3. Run Benchmark

A full guided interface for `llama-bench`.

**Flow:**
1. Select model
2. Select build (backend auto-detected when possible)
3. Choose benchmark parameters:
   - Prompt size (`-p`)
   - Generation length (`-n`)
   - GPU layers (`-ngl`)
   - Number of repetitions (`-r`)
   - Flash Attention (`--flash-attn 0/1`)
4. Review the exact command that will be run
5. `llama-bench` runs with live output

**Results:**
- Full output is displayed in a scrollable box
- **Automatically saved** to:
  ```
  ~/llms/benchmarks/benchmark-<build>-<timestamp>.txt
  ```
- The file contains the exact command + complete stdout/stderr

---

### 4. Show Status

Gives an overview of your current setup.

Displays:
- Number of models found
- List of detected builds with executable counts
- Currently running `llama-server` or `llama-cli` processes (with PID, model name, and port when detectable)

**Special behavior for servers:**
- If a `llama-server` is detected and `/tmp/llama-server.log` exists, you will be offered the option to **view live logs** using a tailing dialog.

---

### 5. API Endpoints

Quick reference showing the default OpenAI-compatible endpoint:

```
http://localhost:8080/v1
```

Includes a one-line `curl` example to test if a server is running.

---

### 6. Quit

Exits the TUI.

---

## How Builds Are Named (Important)

| Type                    | Example Directory              | Notes |
|-------------------------|--------------------------------|-------|
| Official Vulkan release | `llama-b9380-vulkan`           | Installed via "Install Release Version" |
| Official ROCm release   | `llama-b9380-rocm`             | Installed via "Install Release Version" |
| Source build (Vulkan)   | `llama.cpp/build-vulkan`       | Built via `setup-llama.sh` |
| Source build (ROCm)     | `llama.cpp/build-rocm`         | Built via `setup-llama.sh` |

The TUI uses the directory name to automatically know which backend a build supports.

---

## Log Files

| File                          | Description                          |
|-------------------------------|--------------------------------------|
| `/tmp/llama-server.log`       | Logs from the most recently started server (via "Run Inference") |
| `~/llms/benchmarks/*.txt`     | Saved benchmark runs with full output and commands |

---

## Tips

- Use **dialog** instead of **whiptail** for the best experience (especially progress boxes and tailboxes).
- For the best performance on a 7900 XTX, most people use the official Vulkan or ROCm prebuilts rather than building from source.
- You can safely have multiple versions of the same tag with different backends thanks to the `-vulkan` / `-rocm` naming.

---

## Requirements

- `dialog` (strongly recommended) or `whiptail`
- `curl`, `wget`, `git`, `cmake`
- For ROCm builds: ROCm installed and working
- For Vulkan builds: Vulkan drivers + headers

---

This project is intended as a practical daily driver for running large-context models on high-end AMD consumer GPUs.

---

## Current Version

**v0.6.0** (as of late May 2026)

See [CHANGELOG.md](CHANGELOG.md) for the full history of changes.

---

## Project Structure

```
don-rdna-lab/
├── don-rdna-lab.sh      # Main TUI (the core of the project)
├── setup-llama.sh       # Source build helper (called from the TUI)
├── lib/
│   ├── common.sh        # Shared logging utilities
│   └── llama.sh         # Build functions (clone, build-vulkan, etc.)
├── README.md
└── CHANGELOG.md
```

**Note on modularity**: The project is only *partially* modular. The bulk of the logic (menus, flows, command construction) lives inside `don-rdna-lab.sh`. The `setup-llama.sh` + `lib/` files are the most cleanly separated parts.

---

## Common Issues & Troubleshooting

- **TUI exits unexpectedly** (especially on "Show Status"): Usually caused by `set -e` + `grep` returning non-zero when no processes are found. This has been heavily hardened in recent versions.
- **"Invalid device" or similar errors** when running prebuilts: Make sure you're not forcing `-dev Vulkan` on a build that was compiled only for one backend. The TUI tries to avoid this automatically for release installs.
- **Benchmark or inference feels slow**: Make sure you're using a recent prebuilt release rather than an old source build.

---

## Contributing

Pull requests and issues are welcome. The project is developed iteratively based on real usage on RDNA3 hardware.

When making changes, please:
- Test with both `dialog` and `whiptail` when possible.
- Keep the guided, step-by-step style of the flows (Run Inference, Benchmark).
- Update the README and CHANGELOG when adding or changing user-facing behavior.

---

## License

This project is provided as-is for personal and lab use. It wraps the excellent work of the llama.cpp project (https://github.com/ggml-org/llama.cpp).