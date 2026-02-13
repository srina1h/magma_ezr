# Manual Container Run (for debugging)

When captain runs containers it sets up volumes and converts TIMEOUT. If you run the container manually, use the following.

## 1. Apply magma patches (required)

Magma has a few bugs that cause cp/rm/sleep errors. Apply our patches first:

```bash
./scripts/apply_magma_patches.sh
```

Then **rebuild the Docker image** so the container includes the patched scripts:

```bash
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

## 2. Fix core_pattern (required on most Linux systems)

AFL aborts with "Pipe at the beginning of 'core_pattern'" unless core dumps are written to a file. Run once (with sudo):

```bash
sudo ./scripts/fix_core_pattern.sh
```

Or manually:

```bash
echo core | sudo tee /proc/sys/kernel/core_pattern
```

## 3. TIMEOUT format

Use **seconds** in the container. In `captainrc.dataset` we use `TIMEOUT=1200` (20 minutes). Do not use `20m` when running manually.

## 4. Manual run with correct mounts and env

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

`AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1` reduces sensitivity to core_pattern in some setups, but fixing core_pattern (step 2) is still recommended.

## Errors you may see

| Error | Fix |
|-------|-----|
| `sleep: missing operand` | Apply patches and use `TIMEOUT=1200`. Rebuild image. |
| `cp: -r not specified` | Apply patches (adds `cp -r` for corpus). Rebuild image. |
| `rm: cannot remove ... runonce.tmp` | Apply patches (`rm -f`). Rebuild image. |
| `Pipe at the beginning of 'core_pattern'` | Run `sudo ./scripts/fix_core_pattern.sh` |

## Normal use (recommended)

Run captain instead of the container by hand; it sets up mounts and passes env:

```bash
./scripts/run_knob_campaign.sh combo_0
```
