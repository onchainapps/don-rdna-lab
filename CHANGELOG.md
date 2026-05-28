# Changelog

## [0.5.0] - 2026-05-29

### Major Changes

- **Full interactive Benchmark module** — Now a guided experience like Run Inference. Walks through model, build, prompt size, generation length, ngl, repetitions, and flash-attn (on/off/auto). Results are automatically saved.
- **Release installer improvements**:
  - Direct, reliable downloads of official prebuilts.
  - Directories now named `llama-<tag>-vulkan` or `llama-<tag>-rocm` (allows side-by-side installs).
  - Proper extraction that preserves the original tarball structure.
  - No more fragile asset guessing or duplicate extraction logic.
- **Run Inference** no longer asks for backend/engine when the selected build already encodes it in the name (e.g. `llama-b9380-vulkan`).
- **Correct flag handling**:
  - `--flash-attn` now properly supports `on | off | auto` for inference (llama-cli / llama-server).
  - Removed all TurboQuant / turbo KV cache options (deprecated).
  - Switched to safe array-based command construction to eliminate "invalid argument" errors from empty flags.
- **Benchmark results** are now automatically saved to `~/llms/benchmarks/` with timestamped files containing the exact command + full output.
- **Show Status** now detects and displays running llama.cpp instances (PID, model, port).

### Fixed
- "Extraction failed" after download (duplicate extraction + premature archive deletion).
- Sudden TUI exit after long-running tools due to `set -e` + command substitution.
- "can't open input file" / "invalid device: Vulkan" when using prebuilt release directories.
- Unreliable `--textbox -` piping replaced with direct file display.
- Many other robustness and error reporting improvements.

### Removed
- Dead menu items: Quantize Model, Validate Model, Test Model.
- All Turbo KV cache logic and related smart defaults.
- Old normalization that forced files into `bin/` subdirectories for prebuilts (now preserves original structure).

### Changed
- Version bumped to 0.5.0.
- `list_builds`, `run_flow`, `status_screen`, and `benchmark_flow` now correctly handle both flat prebuilt layouts and traditional `bin/` layouts.

---

## [0.4.0] - 2026-05-28

### Fixed (from full code audit)
- Critical: Backend selection now uses correct device strings (`Vulkan` / `HIP` instead of broken `Vulkan0`/`ROCm0`)
- Critical: Release installer completely rewritten — removed invalid `unzip llama.zip` logic and improved extraction for current llama.cpp tarballs
- GitHub release fetching now prefers `jq` with graceful fallback
- Added overwrite confirmation before destroying existing build directories
- Added basic downloaded file size sanity check
- Fixed all shellcheck warnings (quoting, unused variables, `cd` error handling)
- Removed `.guff` typo in model discovery
- Changed CLI default generation length from `-n 128` to unlimited (`-n -1`)
- Removed dangerous soft-fail sourcing of library scripts
- Added proper `cd || return` safety throughout build functions
- Greatly improved stub menu items (quantize, status, benchmark, API now give actionable guidance)
- Added basic prerequisite checking on startup
- Reduced code duplication between setup-llama.sh and lib/llama.sh

### Added
- Smart default KV cache type (prefers "turbo" for model names containing TQ or "turbo")
- KV cache menu now includes "turbo / turbo3" option
- Download warning about lack of signature verification
- `check_prereqs()` run at startup

### Changed
- Version bumped to 0.4.0
- TUI backtitle now shows v0.4.0

---

## [0.3.0] - 2026-05-27

### Added
- Parameter review screen before launching any model (shows Model, Build, Backend, Context, MTP, KV Cache, Mode)
- New "Setup llama.cpp" menu with clear options:
  - Install Release Version (download + build tagged release)
  - Use Git Clone + build-*
  - List detected builds
- `list_builds()` now detects both `llama-*` folders and `llama.cpp/build-*` folders
- Version number displayed in TUI backtitle (`v0.3.0`)

### Changed
- `setup_llama()` now uses proper dialog menus (no more terminal drop)
- Benchmark and Run flows now correctly prefer Vulkan or ROCm binaries based on user selection
- Quantize flow no longer asks for KV cache type (moved to runtime)
- All paths default to `$HOME/llms`

### Fixed
- Removed duplicate menu entries
- Fixed benchmark binary selection logic
- Removed `--kv-unified` (was causing crashes on some builds)
- Multiple syntax and logic fixes from previous edits

---

## [0.2.0] - 2026-05-27

- Full migration from llama.cpp fork to official `ggml-org/llama.cpp`
- New `setup-llama.sh` with release selection + Vulkan/ROCm/Fat builds
- Clean TUI structure

---

## [0.1.0] - 2026-05-27

Initial llama.cpp-focused version (archived).