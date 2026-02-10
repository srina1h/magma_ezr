#!/bin/bash
# Run a 5-minute smoke benchmark then generate bugs.json and benchmark graphs.
# Requires Docker to be running (Docker Desktop on macOS).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker is not running. Start Docker Desktop and try again."
  exit 1
fi

echo "Building runner image (if needed)..."
docker compose build -q

echo "Running 5-minute smoke benchmark (captain + exp2json)..."
# Run as root so the container can access the host Docker socket for builds.
# BUILD_UID so Magma image writes to volumes as host user; BUILD_GID=1000 to avoid
# conflict with system gids (e.g. 20 on macOS).
# HOST_WORKDIR so fuzzer container volume mount works (host path for workdir)
HOST_WORKDIR="$(cd "$REPO_ROOT" && pwd)/workdir"
docker compose run --rm --user root \
  -e WORKDIR=/workspace/workdir \
  -e HOST_WORKDIR="$HOST_WORKDIR" \
  -e BUILD_UID=$(id -u) -e BUILD_GID=1000 \
  runner ./scripts/run_benchmark.sh /workspace/captainrc.smoke /workspace/bugs.json

# Fix ownership of results so host user owns the files
docker compose run --rm --user root --no-deps runner chown -R "$(id -u):$(id -g)" /workspace/workdir /workspace/bugs.json 2>/dev/null || true

echo "Generating benchmark graphs..."
python3 scripts/plot_benchmark.py bugs.json -o .

echo "Done. Results:"
echo "  bugs.json"
echo "  benchmark_time_to_first_bug.png"
echo "  benchmark_bugs_over_time.png"
echo "  benchmark_summary.csv"
echo "  benchmark_summary.json"
