# Don RDNA Lab — llama.cpp

Clean TUI for running LLM inference on the RX 7900 XTX using **llama.cpp** (a llama.cpp fork).

## Focus

This project is now focused **exclusively** on llama.cpp.

## Features

- Setup (clone + build) llama.cpp
- Run Inference (`llama-cli` or `llama-server`)
- Quantize models (TQ4_1S / TQ3_1S + turbo KV cache)
- Validate and test quantized models
- Run benchmarks
- API endpoint helper

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
--cache-type-k q8_0 --cache-type-v turbo3 \
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

## Note

Other engines (hipEngine, ROCmFP4) have been removed. This project is now llama.cpp-only.