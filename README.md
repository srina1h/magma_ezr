# magma_ezr

Local Linux-based fuzzing benchmark for libpng with AFL parameter tuning. Runs 32 combinations of 5 AFL parameters to build a dataset of coverage and bug metrics.

## Prerequisites

- **Linux system** (Ubuntu/Debian/Fedora/Arch recommended)
- System packages: `util-linux`, `inotify-tools`, `git`, `python3`, `python3-pip`, `build-essential`
- Python packages: `pandas >= 1.1.0`, `matplotlib` (optional, for plotting)

## Quick Setup

```bash
# Clone the repository
git clone <repo-url>
cd magma_ezr

# Run setup script (installs dependencies)
./scripts/setup_local.sh

# If magma submodule is needed:
git submodule update --init --recursive
# OR manually clone:
# git clone https://github.com/HexHive/magma.git magma
```

## AFL Parameters

The system tunes 5 binary AFL parameters (2^5 = 32 combinations):

1. **AFL_FAST_CAL** (0/1) - Fast calibration mode
2. **AFL_NO_ARITH** (0/1) - Disable arithmetic mutations
3. **AFL_NO_HAVOC** (0/1) - Disable havoc mutations
4. **AFL_DISABLE_TRIM** (0/1) - Disable input trimming
5. **AFL_SHUFFLE_QUEUE** (0/1) - Shuffle input queue order

Parameters are defined in `scripts/afl_params.json`.

## Building the Dataset

### Verify build works first

Before running all combinations, verify that the build works:

```bash
# Test build (recommended first step)
./scripts/check_build.sh
```

This will attempt a test build and show any errors. Fix any build issues before proceeding.

### Run all 32 combinations

```bash
# Run with default 20-minute budget per combination
python3 scripts/build_dataset.py --budget 20m

# Or specify custom budget
python3 scripts/build_dataset.py --budget 30m
```

### Resume from saved state

If the system disconnects (e.g., VCL timeout), resume where you left off:

```bash
python3 scripts/build_dataset.py --resume
```

The system automatically saves state to `dataset_state.json` and tracks completed combinations.

### Preview combinations (dry run)

```bash
python3 scripts/build_dataset.py --dry-run
```

## Results

### Per-combination results

Each combination's results are stored in `dataset_results/combo_<N>/`:
- `metrics.json` - Coverage, bugs, paths, execution stats
- `bugs.json` - Detailed bug information from exp2json
- `fuzzer_stats` - Raw AFL fuzzer statistics

### Aggregate results

Generate a CSV dataset with all combinations:

```bash
python3 scripts/aggregate_results.py
```

Output: `dataset_results.csv` with columns:
- `combo_id` - Combination identifier (combo_0 through combo_31)
- `AFL_FAST_CAL`, `AFL_NO_ARITH`, `AFL_NO_HAVOC`, `AFL_DISABLE_TRIM`, `AFL_SHUFFLE_QUEUE` - Parameter values
- `bitmap_cvg_pct` - Coverage percentage
- `paths_total` - Total paths discovered
- `execs_done` - Total executions
- `execs_per_sec` - Execution rate
- `bugs_triggered` - Number of bugs triggered
- `bugs_reached` - Number of bugs reached

## State Management

The system maintains state in `dataset_state.json`:
- Tracks completed combinations
- Records in-progress combination
- Stores time budget and timestamps
- Enables automatic resume on restart

## Project Layout

- **magma/** — Magma v1.2.1 clone (captain, benchd, targets)
- **scripts/afl_params.json** — AFL parameter definitions
- **scripts/build_dataset.py** — Main dataset builder script
- **scripts/aggregate_results.py** — Results aggregator
- **scripts/setup_local.sh** — Local setup script
- **scripts/run_knob_campaign.sh** — Single campaign runner
- **captainrc.dataset** — Captain config for dataset runs (20m timeout)
- **dataset_results/** — Per-combination results (gitignored)
- **dataset_state.json** — Build state for resuming (gitignored)
- **dataset_results.csv** — Aggregated CSV dataset (gitignored)

## Workflow

1. **Setup**: Run `./scripts/setup_local.sh` once
2. **Build dataset**: Run `python3 scripts/build_dataset.py --budget 20m`
3. **Resume if needed**: Run `python3 scripts/build_dataset.py --resume` after disconnection
4. **Aggregate**: Run `python3 scripts/aggregate_results.py` to generate CSV

## Notes

- Each combination uses a separate `workdir` to avoid conflicts
- Workdirs are cleaned after metrics extraction to save space
- All operations are logged to `dataset_build.log`
- The system supports VCL disconnections via state saving/resuming
- Default time budget is 20 minutes per combination (configurable)

## References

- [Magma](https://github.com/HexHive/magma) v1.2.1
- [Magma docs](https://hexhive.epfl.ch/magma/)
