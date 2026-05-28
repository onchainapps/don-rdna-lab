# Don RDNA Lab — llama.cpp

Clean TUI for running LLM inference on the RX 7900 XTX using **llama.cpp** (a llama.cpp fork).

## Focus

This project is now focused **exclusively** on llama.cpp.

## Features

- Setup (clone + build) llama.cpp (Vulkan + ROCm)
- Install official prebuilt releases directly from GitHub
- Run Inference with rich options (`llama-cli` or `llama-server`)
  - Very large contexts (up to 256K)
  - KV cache quantization (q8_0 or q4_0)
  - MTP speculative decoding
- Model discovery and build management
- API endpoint helper
- Actionable guidance for quantize / benchmark / status (via existing llama.cpp tools)

## Recommended Server Settings

```bash
--port 8080 --host 0.0.0.0 \
-c 180000 \
--parallel 1 \
--batch-size 1024 --ubatch-size 512 \
-ngl 99 \
--jinja \
--verbosity 3 \
--flash-attn on \
--cache-type-k q8_0 --cache-type-v q8_0 \
--spec-type draft-mtp \
--spec-draft-n-max 2 \
--spec-draft-p-min 0.75
```

## Quick Start

```bash
cd ~/llms/don-rdna-lab
./don-rdna-lab.sh
```

## Files

- `don-rdna-lab.sh` — Main TUI
- `setup-llama.sh` — Build and helper script

## Recent Improvements (v0.4.0)

A full code audit was performed in May 2026. All critical bugs were fixed, shellcheck is clean, and many previously non-functional menu items now provide useful guidance.

## Note

Other engines (hipEngine, ROCmFP4, TurboQuant) have been removed. This project is now focused exclusively on official llama.cpp.