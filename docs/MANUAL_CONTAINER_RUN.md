# Manual Container Run (Debugging Only)

**Normal use:** Run via captain (`./scripts/run_knob_campaign.sh combo_0`). This doc is for debugging when captain fails.

## Prerequisites

1. **Apply patches and rebuild image:**
   ```bash
   ./scripts/apply_magma_patches.sh
   cd magma
   docker build -t magma/afl/libpng \
     --build-arg fuzzer_name=afl \
     --build-arg target_name=libpng \
     --build-arg USER_ID=$(id -u) \
     --build-arg GROUP_ID=$(id -g) \
     --build-arg canaries=1 \
     -f docker/Dockerfile .
   cd ..
   ```

2. **Fix core_pattern on host:**
   ```bash
   sudo ./scripts/fix_core_pattern.sh
   ```

## Manual Run

```bash
mkdir -p workdir/cache
SHARED="$(pwd)/workdir/cache"

docker run --rm -it \
  -e TIMEOUT=1200 \
  -e AFL_FAST_CAL=0 \
  -e AFL_NO_ARITH=0 \
  -e AFL_NO_HAVOC=0 \
  -e AFL_DISABLE_TRIM=0 \
  -e AFL_SHUFFLE_QUEUE=1 \
  -e AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
  -e AFL_SKIP_CPUFREQ=1 \
  -e AFL_NO_AFFINITY=1 \
  -e AFL_NO_UI=1 \
  -v "$(pwd)/workdir:/magma/workdir" \
  -v "$SHARED:/magma_shared" \
  magma/afl/libpng \
  /magma/run.sh
```

## Common Errors

- `Pipe at the beginning of 'core_pattern'` → Fix on host: `sudo ./scripts/fix_core_pattern.sh`
- `No usable test cases` → Patches should fix this; ensure image is rebuilt
- `rm: cannot remove ... runonce.tmp: Is a directory` → Clear cache: `rm -rf workdir/cache/runonce.tmp`
