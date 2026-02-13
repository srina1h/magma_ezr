# From Scratch Guide

Complete step-by-step guide to run magma with AFL parameter tuning.

## Step 1: Setup (one time)

```bash
# Clone repo
git clone <repo-url>
cd magma_ezr

# Initialize magma submodule
git submodule update --init --recursive

# Run setup (installs Docker, dependencies)
./scripts/setup_local.sh

# If Docker was just installed, logout/login or run:
newgrp docker
```

## Step 2: Fix core_pattern (Linux, one time)

```bash
sudo ./scripts/fix_core_pattern.sh
```

This is required for AFL. The container uses the host kernel, so fix it on the host.

## Step 3: Pre-build Docker image (recommended)

Pre-build the image so campaigns don't timeout during build:

```bash
./scripts/prebuild_image.sh
```

This takes 10-20 minutes on first run. After this, campaigns will start fuzzing immediately.

Alternatively, verify build works (also builds image):

```bash
./scripts/check_build.sh
```

## Step 4: Run all 32 combinations

```bash
python3 scripts/build_dataset.py --budget 20m
```

This runs each of the 32 AFL parameter combinations for 20 minutes each. Results are saved to `dataset_results/combo_<N>/`.

## Step 5: Resume if disconnected

If your session disconnects (e.g., VCL timeout), resume:

```bash
python3 scripts/build_dataset.py --resume
```

State is saved in `dataset_state.json`.

## Step 6: Generate CSV results

```bash
python3 scripts/aggregate_results.py
```

Output: `dataset_results.csv` with all combinations and metrics.

## That's It

- **Setup**: `./scripts/setup_local.sh` + `sudo ./scripts/fix_core_pattern.sh`
- **Run**: `python3 scripts/build_dataset.py --budget 20m`
- **Resume**: `python3 scripts/build_dataset.py --resume`
- **Results**: `python3 scripts/aggregate_results.py`

The system uses captain (magma's tool) and passes AFL parameters via environment variables. No manual Docker commands needed.

## Troubleshooting

- **Build fails**: Check Docker: `docker ps`. If needed: `sudo systemctl start docker`
- **Campaign finishes in <1s**: Check `dataset_results/combo_X/fuzzer_stats` - if `execs_done=0`, build likely failed
- **Core pattern error**: Run `sudo ./scripts/fix_core_pattern.sh` again

For manual container debugging, see `docs/MANUAL_CONTAINER_RUN.md` (not needed for normal use).
