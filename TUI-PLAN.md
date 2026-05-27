# Don RDNA Lab — Dialog TUI Implementation Plan

## Goal
Replace the current basic menu in `don-rdna-lab.sh` with a proper **dialog-based interactive TUI**.

## Constraints
- Must work over SSH
- Should use `dialog` (preferred) with `whiptail` fallback
- Keep everything in a single script (`don-rdna-lab.sh`)
- No heavy external dependencies beyond `dialog`/`whiptail`
- Must remain functional even if dialog is missing (graceful fallback)

## Phase Overview

### Phase 1: Foundation
- Add `require_dialog()` function that detects `dialog` or `whiptail`
- Create a set of wrapper functions:
  - `dlg_msg`
  - `dlg_menu`
  - `dlg_checklist`
  - `dlg_input`
  - `dlg_fselect`
  - `dlg_yesno`
- Define consistent dialog options (`--backtitle`, `--title`, `--clear`, etc.)
- Add a global `DIALOG` variable

### Phase 2: Data Layer
- Model discovery (`list_models`)
- Engine status detection (`has_hipengine`, `has_rocmfp4`, `has_turboquant`)
- Build status per engine
- Store user selections in variables (MODEL_PATH, ENGINE, BACKEND, CONTEXT, KV_TYPE, etc.)

### Phase 3: Main Menu
- Build the main interactive loop using `dlg_menu`
- Menu items:
  1. Setup / Install Engines
  2. Run Inference
  3. Quantize Model
  4. Run Benchmark
  5. Show Status
  6. Quit

### Phase 4: Core Flows
- **Run Inference flow**:
  - Model picker
  - Engine picker (with status)
  - Backend picker (ROCm0 / Vulkan0) with hint
  - Context size menu
  - KV cache type menu
  - Confirmation
  - Execute the appropriate `setup-*.sh run ...`

- **Quantize flow**:
  - Model picker (BF16 preferred)
  - Engine picker
  - Quant type selection (TQ4_1S, Q4_0_ROCMFP4, etc.)
  - Execute quantize command

- **Setup flow**:
  - Checklist of engines to set up
  - Run the setup scripts sequentially with progress messages

- **Status screen**:
  - Show which engines are cloned/built
  - Show last known benchmark numbers (if available)

### Phase 5: Polish & Robustness
- Handle case when `dialog` is not installed (offer to install or fall back to text menu)
- Better error messages when builds are missing
- Consistent back/cancel behavior
- Clean exit (reset terminal)
- Add `--text` flag to force text mode

### Phase 6: Final Validation
- Run `bash -n` on the new script
- Basic syntax and logic review
- Ensure all paths to `setup-*.sh` still work

## Execution Rules
- Write the new `don-rdna-lab.sh` in phases
- After each major section, verify syntax
- At the end, replace the old script completely
- Do not ask for confirmation between phases

## Success Criteria
- Running `./don-rdna-lab.sh` shows a nice dialog TUI
- All major flows (Run, Quantize, Setup, Status) are reachable via menus
- The script still works if `dialog` is missing (falls back gracefully)
- No breakage to the individual `setup-*.sh` scripts

---

Plan created. Now executing unattended.