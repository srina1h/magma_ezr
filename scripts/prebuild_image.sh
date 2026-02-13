#!/bin/bash
# Pre-build the Docker image so campaigns don't timeout during build.
# Run this once before running build_dataset.py.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

export MAGMA="${MAGMA:-$REPO_ROOT/magma}"

if [ ! -d "$MAGMA" ]; then
    echo "ERROR: magma directory not found: $MAGMA"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

if [ ! -f "$MAGMA/docker/Dockerfile" ]; then
    echo "ERROR: Dockerfile not found: $MAGMA/docker/Dockerfile"
    exit 1
fi

echo "Pre-building Docker image: magma/afl/libpng"
echo "This may take 10-20 minutes on first run..."
echo ""

cd "$MAGMA"
docker build -t magma/afl/libpng \
  --build-arg fuzzer_name=afl \
  --build-arg target_name=libpng \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  --build-arg canaries=1 \
  -f docker/Dockerfile .

echo ""
echo "✓ Docker image built successfully"
echo "You can now run: python3 scripts/build_dataset.py --budget 20m"
