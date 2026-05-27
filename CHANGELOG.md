# Changelog

All notable changes to Don RDNA Lab will be documented in this file.

## [0.1.0] - 2026-05-27

### Added
- Initial release focused exclusively on **TurboQuant** (llama.cpp fork)
- Interactive TUI (`don-rdna-lab.sh`) with the following features:
  - Setup TurboQuant (clone + build for Fat / Vulkan / ROCm)
  - Run Inference (`llama-cli` or `llama-server`)
  - Quantize models (TQ4_1S / TQ3_1S + turbo KV cache options)
  - Validate and test quantized models
  - Run benchmarks using correct binary selection
  - API Endpoints helper screen
- `setup-turboquant.sh` helper script with improved ROCm build support
- Default paths changed to `$HOME/llms`
- KV Cache type toggle (TurboQuant vs Standard) when starting `llama-server`
- MTP (Multi-Token Prediction) support with `--spec-type draft-mtp`
- Recommended server parameters matching TurboQuant best practices
- Context size options up to 262144 (256K)

### Changed
- Removed all references to hipEngine and ROCmFP4
- Project is now TurboQuant-only

### Notes
- ROCm build can be unstable in this fork; Vulkan is currently more reliable for most users
- Always use correct KV cache types (`turbo3` recommended with TQ models)