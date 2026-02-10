# magma_ezr

Magma-based fuzzing benchmark for libpng with captain-driven AFL campaigns, result summarization (exp2json), and benchmark graphs (time to first bug, bugs over time).

## Prerequisites

- **Docker** (Docker Desktop on macOS, or `docker.io` on Linux).
- **Linux (native):** `util-linux`, `inotify-tools`, `git` (captain’s `run.sh` uses these).
- **macOS:** No extra host packages; use the **Docker runner** so captain runs inside a Linux container (see below).
- **Python (for exp2json and plotting):** `pandas >= 1.1.0`, `matplotlib` (or use the runner image which includes them).

## Layout

- **magma/** — Magma v1.2.1 clone (captain, benchd, targets).
- **captainrc** — Captain config: AFL, libpng, `WORKDIR`, `CACHE_ON_DISK=1` for Docker.
- **scripts/run_captain.sh** — Runs captain only (build + fuzz).
- **scripts/run_benchmark.sh** — Runs captain then exp2json → `bugs.json`.
- **scripts/plot_benchmark.py** — Reads `bugs.json`, writes benchmark graphs and summary CSV/JSON.
- **workdir/** — Created by captain (build logs, campaign data); gitignored.
- **bugs.json** — Output of exp2json; gitignored.

## Quick start (Linux)

```bash
# From repo root
./scripts/run_benchmark.sh
# Then plot (optional)
python3 scripts/plot_benchmark.py bugs.json -o .
```

For a short smoke test, edit `captainrc` and set `TIMEOUT=10m`, then run again.

## Platform note (Apple Silicon)

Magma’s AFL+libpng Docker image targets **x86_64 Linux**. On **Apple Silicon (M1/M2)** the image is built with `--platform linux/amd64` and run via emulation on Apple Silicon. First build/fuzzing may be slower than native x86 (e.g. cloud VM or Intel Mac). The **plotting pipeline** and **sample results** work on any platform.

## macOS: run in Docker (recommended)

Captain’s `run.sh` needs Linux (inotifywait, flock, etc.). Run it inside the provided runner image so your Mac stays clean:

```bash
# Build the runner image (once)
docker compose build

# Run full benchmark (captain + exp2json). Uses captainrc with WORKDIR=/workspace/workdir
docker compose run --rm -e RUNNER_UID=$(id -u) -e RUNNER_GID=$(id -g) runner ./scripts/run_benchmark.sh

# Or run only captain
docker compose run --rm -e RUNNER_UID=$(id -u) -e RUNNER_GID=$(id -g) runner ./scripts/run_captain.sh
```

Then on the host (or inside the same image with `workdir` mounted):

```bash
python3 scripts/plot_benchmark.py workdir/../bugs.json -o .
# If bugs.json is at repo root after run_benchmark.sh:
python3 scripts/plot_benchmark.py bugs.json -o .
```

`RUNNER_UID` / `RUNNER_GID` match your user so files in `workdir/` are owned by you.

**Manual flow (no run.sh):** From the host you can still run `magma/tools/captain/build.sh` and `start.sh` for a single campaign; see the plan (Section 9.3) for exact commands and directory layout for exp2json.

## Captain config (captainrc)

- **WORKDIR** — Set to `./workdir` by default; when running in the Docker runner it is overridden to `/workspace/workdir` so output lands on your Mac.
- **CACHE_ON_DISK=1** — Required when captain runs inside Docker (no tmpfs).
- **FUZZERS=(afl)**, **afl_TARGETS=(libpng)** — Single fuzzer and target.
- **TIMEOUT** — e.g. `24h` for a full benchmark, `10m` for a smoke test.
- **REPEAT** — Number of campaigns per program (increase for distributions).

## Outputs

- **workdir/log/** — Build and run logs.
- **workdir/ar/afl/libpng/libpng_read_fuzzer/0/, 1/, …** — Per-run data (monitor CSVs in `monitor/`, or inside `ball.tar`).
- **bugs.json** — Summary from `magma/tools/benchd/exp2json.py` (time to first reach/trigger per bug per run).
- **benchmark_time_to_first_bug.png** — Bar chart: bug ID vs time (min) to first trigger.
- **benchmark_bugs_over_time.png** — Cumulative bugs triggered over time (one curve per run).
- **benchmark_summary.csv** / **benchmark_summary.json** — Per-bug min/median trigger times and run counts.

## Metrics

- **Time to first bug (per bug):** From `bugs.json` → `results.afl.libpng.libpng_read_fuzzer.<run>.triggered`; use min (or median) across runs.
- **How long to catch bugs:** Shown by the cumulative plot and the per-bug times in the summary.

## References

- [Magma](https://github.com/HexHive/magma) v1.2.1
- [Magma docs](https://hexhive.epfl.ch/magma/)
