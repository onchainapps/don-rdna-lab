# Changelog

## [0.3.0] - 2026-05-27

### Added
- Parameter review screen before launching any model (shows Model, Build, Backend, Context, MTP, KV Cache, Mode)
- New "Setup llama.cpp" menu with clear options:
  - Install Release Version (download + build tagged release)
  - Use Git Clone + build-*
  - List detected builds
- `list_builds()` now detects both `llama-*` folders and `llama.cpp/build-*` folders
- KV Cache enforcement for TurboQuant models (forces `turbo*` when model name contains "TQ")
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

- Full migration from TurboQuant fork to official `ggml-org/llama.cpp`
- New `setup-llama.sh` with release selection + Vulkan/ROCm/Fat builds
- Clean TUI structure

---

## [0.1.0] - 2026-05-27

Initial TurboQuant-focused version (archived).