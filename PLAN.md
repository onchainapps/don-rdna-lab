# Don RDNA Lab — Rebuild Plan

## Current State Assessment

The existing scripts have multiple critical issues:
- Broken `MAX_TOKENS=***` placeholder syntax in two files
- `eval "$command"` in main script (security + fragility)
- Incomplete/broken function bodies from generation artifacts
- Unbalanced if/fi and brace counting (false positives from string matching)
- No actual testing or validation of the run/quantize paths
- Hardcoded server paths that may not exist

## Goal

Create a clean, working, maintainable set of scripts that:
1. Allow installing and using hipEngine, ROCmFP4, and TurboQuant+ on RDNA3
2. Provide a unified interactive CLI (`don-rdna-lab.sh`)
3. Have working `quantize` and `run` functions
4. Pass shellcheck and bash -n
5. Are safe (no eval of untrusted input)
6. Are testable in a headless environment

## Rebuild Strategy

**Option A (Incremental Fix)**: Patch the existing broken scripts
- High risk of missing edge cases
- Existing structural damage is deep

**Option B (Clean Rewrite)**: Rewrite all four scripts from scratch following a proven pattern
- Lower long-term maintenance cost
- Can be made correct by construction
- Recommended approach

We will use **Option B**.

## Plan

### Phase 1: Design the CLI interface (documented in code)

The main `don-rdna-lab.sh` will support:
- `setup` — clone + build + install all three engines
- `menu` — interactive TUI (model, backend, context, kv-cache, mtp)
- `run <engine> <model>` — non-interactive run
- `quantize <engine> <model> <type>` — quantize a BF16 model
- `benchmark` — run comparative benchmarks
- `status` — show installed versions and build status

Each setup-*.sh script will be a focused, single-purpose tool:
- `setup-hipengine.sh` — clone, lfs, pip install variants, run, server, benchmark
- `setup-rocmfp4-rdna3.sh` — clone, build-gfx1100, build-strix, quantize, run, benchmark
- `setup-turboquant.sh` — clone, build-rocm, build-vulkan, build-fat, quantize, run, benchmark

### Phase 2: Rewrite the three setup scripts

Each setup script will follow this structure:
1. Header + strict mode (`set -euo pipefail`)
2. Color helpers (info/warn/error)
3. `check_prereqs()` — required binaries + versions
4. Action functions (clone, build-*, install-*, quantize, run, benchmark, status)
5. `main()` dispatcher with case statement
6. No `eval`
7. All long-running commands use proper quoting and error propagation
8. `MAX_TOKENS` and other variables properly defaulted

### Phase 3: Rewrite the main launcher

`don-rdna-lab.sh` will:
- Use a proper menu system with `select` or numbered read
- Never use `eval`
- Capture model paths safely
- Pass arguments as arrays to child scripts
- Have a `--dry-run` / `--help` mode
- Source common helpers if needed (but keep self-contained for simplicity)

### Phase 4: Validation

After writing:
- `bash -n` on every .sh file
- `shellcheck` (if available) with warnings noted
- Manual review of the `run` and `quantize` code paths for correctness
- Ensure all three engines have consistent action names where possible

### Phase 5: Documentation update

Update README.md with:
- Quick start
- Engine comparison table (performance + when to use)
- Known limitations
- Server copy instructions

## Execution Order (Unattended)

1. Write new `setup-hipengine.sh`
2. Write new `setup-rocmfp4-rdna3.sh`
3. Write new `setup-turboquant.sh`
4. Write new `don-rdna-lab.sh`
5. Write new `README.md`
6. Run syntax validation on all files
7. If any syntax error remains, fix immediately before proceeding
8. Final directory listing and summary

## Success Criteria

- All four .sh files pass `bash -n`
- No `MAX_TOKENS=***` or similar placeholders remain
- No `eval "$command"` patterns
- `quantize` and `run` functions have complete, correct logic for at least one engine each
- The interactive menu in the main script is functional
- README accurately describes the current state and usage

## Notes

- We will not actually execute `git clone` or `cmake` during this run (no network / long builds)
- The scripts will be correct in structure and logic
- User can later run `setup` on the target machine

---

This plan will be executed unattended after creation.