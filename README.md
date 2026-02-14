# magma_ezr

Run magma fuzzing benchmark with different AFL parameter combinations. Collects coverage and bug metrics for 32 combinations (2^5) of 5 AFL parameters.

## Quick Start

```bash
# 1. Setup (one time)
./scripts/setup_local.sh

# 2. Fix core_pattern (required on Linux, one time)
sudo ./scripts/fix_core_pattern.sh

# 3. Run all 32 combinations (builds image once, then 20 min fuzzing per combo)
python3 scripts/build_dataset.py --budget 20m

# 4. Generate CSV results
python3 scripts/aggregate_results.py
```

**Detailed guide:** See [FROM_SCRATCH.md](FROM_SCRATCH.md) for step-by-step instructions.

The system uses captain (magma's orchestration tool) and passes AFL parameters via environment variables.

## Prerequisites

- **Linux** (Ubuntu/Debian/Fedora/Arch)
- **Docker** (for building targets; setup script installs it)
- Python 3 with `pandas`

## AFL Parameters

5 binary parameters (32 combinations):

- `AFL_FAST_CAL` (0/1) - Fast calibration
- `AFL_NO_ARITH` (0/1) - Disable arithmetic mutations
- `AFL_NO_HAVOC` (0/1) - Disable havoc mutations
- `AFL_DISABLE_TRIM` (0/1) - Disable input trimming
- `AFL_SHUFFLE_QUEUE` (0/1) - Shuffle queue order

Defined in `scripts/afl_params.json`.

## Setup Details

### Initial Setup

```bash
./scripts/setup_local.sh
```

This installs Docker, dependencies, and optionally clones magma. If magma already exists, it applies patches (fixes for timeout/sleep defaults).

### Fix core_pattern (Linux only)

AFL requires core dumps written to a file. Fix once:

```bash
sudo ./scripts/fix_core_pattern.sh
```

To make persistent: add `kernel.core_pattern=core` to `/etc/sysctl.conf`, then `sudo sysctl -p`.

### Build vs fuzz time

`build_dataset.py` first ensures the Docker image exists: if not, it runs a **full build with no time limit** (10–20 min). Only after the build finishes does it run each of the 32 campaigns; each campaign gets the **full time budget for fuzzing** (e.g. 20m) plus a small buffer. So the budget is for fuzzing only, not build.

To skip the build phase (image already built): `python3 scripts/build_dataset.py --budget 20m --skip-build`

## Running Campaigns

### Run all combinations

```bash
python3 scripts/build_dataset.py --budget 20m
```

### Resume after disconnection

```bash
python3 scripts/build_dataset.py --resume
```

### Run single combination

```bash
AFL_SHUFFLE_QUEUE=1 ./scripts/run_knob_campaign.sh combo_0
```

### Verify build first

```bash
./scripts/check_build.sh
```

## Results

### Per-combination

`dataset_results/combo_<N>/`:
- `metrics.json` - Coverage, bugs, paths, exec stats
- `bugs.json` - Detailed bug info
- `fuzzer_stats` - Raw AFL stats

### Aggregate CSV

```bash
python3 scripts/aggregate_results.py
```

Output: `dataset_results.csv` with all combinations and metrics.

## Project Structure

- `magma/` - Magma benchmark (captain, targets)
- `scripts/build_dataset.py` - Main runner (32 combinations)
- `scripts/run_knob_campaign.sh` - Single campaign runner
- `scripts/aggregate_results.py` - CSV generator
- `captainrc.dataset` - Captain config (TIMEOUT=1200s)
- `dataset_results/` - Results (gitignored)
- `dataset_state.json` - Resume state (gitignored)

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Pipe at the beginning of 'core_pattern'` | Run `sudo ./scripts/fix_core_pattern.sh` |
| Build fails | Check Docker is running: `sudo systemctl status docker` |
| `permission denied` / `docker.sock` | Your user can't access Docker. Run: `sudo usermod -aG docker $USER`, then log out and back in (or `newgrp docker`). |
| Campaign finishes too fast | Check `dataset_results/combo_X/fuzzer_stats` - if `execs_done=0`, build likely failed |
| execs_done=0 but campaign ran ~20m | Captain ran but no fuzzer_stats. See `dataset_build.log` for "Last campaign output". Run manually: `./scripts/run_knob_campaign.sh combo_0 2>&1 | tee combo0.log` and inspect `workdir/` and `workdir/log/`. |

For manual container debugging, see `docs/MANUAL_CONTAINER_RUN.md` (not needed for normal use).

## References

- [Magma](https://github.com/HexHive/magma) v1.2.1
- [Magma docs](https://hexhive.epfl.ch/magma/)
