---
name: Local AFL Parameter Tuning System
overview: Create a local Linux-based fuzzing system that runs 32 AFL parameter combinations on libpng, collects coverage/bugs, supports resuming from saved state, and removes Docker dependencies.
todos:
  - id: setup_params
    content: Create scripts/afl_params.json with 5 AFL parameter definitions
    status: pending
  - id: create_dataset_builder
    content: Create scripts/build_dataset.py - main script to run all 32 combinations with state management
    status: pending
  - id: modify_campaign_runner
    content: Modify scripts/run_knob_campaign.sh to work locally without Docker
    status: pending
  - id: create_setup_script
    content: Create scripts/setup_local.sh for initial Linux system setup
    status: pending
  - id: create_aggregator
    content: Create scripts/aggregate_results.py to generate final CSV dataset
    status: pending
  - id: cleanup_docker
    content: Delete Docker-related files (Dockerfile, docker-compose.yml, Docker scripts)
    status: pending
  - id: update_readme
    content: Update README.md with local execution instructions
    status: pending
isProject: false
---

# Local AFL Parameter Tuning System

## Overview

Transform the Docker-based magma fuzzing setup into a local Linux system that:

- Runs 32 combinations of 5 AFL parameters (2^5 = 32)
- Each combination runs for a configurable time budget (default: 20 minutes)
- Collects coverage and bug metrics
- Supports resuming from saved state (for VCL disconnections)
- Removes all Docker dependencies

## Key Components

### 1. AFL Parameter Configuration

Create `scripts/afl_params.json` to define the 5 tunable parameters (all binary):

```json
{
  "AFL_FAST_CAL": [0, 1],
  "AFL_NO_ARITH": [0, 1],
  "AFL_NO_HAVOC": [0, 1],
  "AFL_DISABLE_TRIM": [0, 1],
  "AFL_SHUFFLE_QUEUE": [0, 1]
}
```

This generates 2^5 = 32 combinations (all parameters are binary 0/1).

### 2. Main Dataset Builder Script

Create `scripts/build_dataset.py`:

- Generates all 32 parameter combinations
- Tracks completion state in `dataset_state.json`
- Runs each combination sequentially with time budget
- Extracts metrics (coverage, bugs) after each run
- Saves results to `dataset_results/`
- Supports resuming from last incomplete combination

### 3. Local Campaign Runner

Modify `scripts/run_knob_campaign.sh` to work locally:

- Remove Docker dependencies
- Use `magma/tools/captain/run.sh` directly
- Set AFL environment variables before running
- Extract metrics from `workdir/` and `bugs.json`

### 4. Setup Script

Create `scripts/setup_local.sh`:

- Install system dependencies (util-linux, inotify-tools, git, python3, etc.)
- Clone/fetch magma submodule if needed
- Verify magma structure exists
- Set up Python dependencies

### 5. State Management

- `dataset_state.json`: Tracks which combinations completed
- `dataset_results/`: Directory with per-combination results
- Each combination gets: `metrics.json`, `bugs.json`, `fuzzer_stats`, `workdir/`

### 6. Results Aggregation

Create `scripts/aggregate_results.py`:

- Reads all completed combinations
- Generates CSV: `dataset_results.csv` with columns:
  - Parameter values (5 columns)
  - Coverage %
  - Bugs triggered
  - Bugs reached
  - Paths total
  - Execs done
  - Wall time

## File Structure Changes

### Files to Create:

- `scripts/afl_params.json` - Parameter definitions
- `scripts/build_dataset.py` - Main dataset builder
- `scripts/setup_local.sh` - Local setup script
- `scripts/aggregate_results.py` - Results aggregator
- `scripts/run_local_campaign.sh` - Local campaign runner (modify existing)

### Files to Modify:

- `scripts/run_knob_campaign.sh` - Remove Docker, use local execution
- `scripts/run_captain.sh` - Ensure works without Docker

### Files to Delete:

- `Dockerfile`
- `docker-compose.yml`
- `scripts/run_smoke_and_plot.sh` (Docker-specific)
- `scripts/ezr_driver.py` (Docker-based, replace with build_dataset.py)
- Docker-related documentation in README

## Implementation Details

### State File Format (`dataset_state.json`):

```json
{
  "completed": ["combo_0", "combo_1", ...],
  "in_progress": "combo_15",
  "start_time": "2026-02-13T12:00:00",
  "last_update": "2026-02-13T14:30:00",
  "total_combinations": 32,
  "time_budget_minutes": 20
}
```

### Combination Labeling:

Each combination gets a unique label: `combo_0` through `combo_31`, based on binary encoding of the 5 parameter values (each 0 or 1). The label corresponds to the binary number formed by concatenating the parameter values in order.

### Metrics Extraction:

- Coverage: From `fuzzer_stats` → `bitmap_cvg`
- Bugs: From `bugs.json` → count of triggered bugs
- Paths: From `fuzzer_stats` → `paths_total`
- Time: Wall clock time for the combination

### Resume Logic:

1. Load `dataset_state.json`
2. Skip combinations in `completed` list
3. If `in_progress` exists, check if workdir has valid results
4. If valid, mark complete and continue; else restart that combination
5. Continue with next incomplete combination

## Execution Flow

1. **Setup**: `./scripts/setup_local.sh`
2. **Run dataset builder**: `python3 scripts/build_dataset.py --budget 20m`
3. **Resume if needed**: `python3 scripts/build_dataset.py --resume`
4. **Aggregate results**: `python3 scripts/aggregate_results.py`

## Dependencies

### System Packages (Linux):

- `util-linux` (for flock)
- `inotify-tools` (for inotifywait)
- `git`
- `python3`, `python3-pip`
- `build-essential` (for compiling)

### Python Packages:

- `pandas` (for results aggregation)
- Standard library: `json`, `subprocess`, `time`, `itertools`, `pathlib`

## Error Handling

- Timeout handling: Kill fuzzing process after time budget
- State corruption: Validate state file before resuming
- Partial results: Save metrics even if campaign doesn't complete fully
- Disk space: Check available space before starting

## Output Structure

```
dataset_results/
├── combo_0/
│   ├── metrics.json
│   ├── bugs.json
│   ├── fuzzer_stats
│   └── workdir/ (optional, can be cleaned)
├── combo_1/
│   └── ...
└── dataset_results.csv (aggregated)
```

## Notes

- Each combination uses a separate `workdir` to avoid conflicts
- Clean up workdirs after metrics extraction to save space
- Log all operations to `dataset_build.log`
- Support `--dry-run` to preview combinations without running

