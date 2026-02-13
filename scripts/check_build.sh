#!/bin/bash
# Check if magma build is working by attempting a test build
# This helps diagnose build issues before running the full dataset

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

export MAGMA="$REPO_ROOT/magma"
export WORKDIR="${WORKDIR:-$REPO_ROOT/workdir_test}"

if [ ! -d "$MAGMA" ]; then
    echo "ERROR: Magma directory not found: $MAGMA"
    echo "Please run: ./scripts/setup_local.sh"
    exit 1
fi

if [ ! -f "$MAGMA/tools/captain/run.sh" ]; then
    echo "ERROR: Captain script not found: $MAGMA/tools/captain/run.sh"
    exit 1
fi

# Clean test workdir
if [ -d "$WORKDIR" ]; then
    rm -rf "$WORKDIR"
fi
mkdir -p "$WORKDIR"

echo "Testing build with captain..."
echo "MAGMA=$MAGMA"
echo "WORKDIR=$WORKDIR"
echo ""

# Try to build
if "$MAGMA/tools/captain/build.sh" "$REPO_ROOT/captainrc.dataset"; then
    echo ""
    echo "✓ Build successful!"
    echo "You can now run: python3 scripts/build_dataset.py --budget 20m"
else
    BUILD_EXIT=$?
    echo ""
    echo "✗ Build failed with exit code $BUILD_EXIT"
    echo ""
    echo "Build logs:"
    find "$WORKDIR/log" -type f 2>/dev/null | while read logfile; do
        echo ""
        echo "=== $logfile ==="
        tail -50 "$logfile"
    done
    echo ""
    echo "Common issues:"
    echo "  1. Missing dependencies - run: ./scripts/setup_local.sh"
    echo "  2. AFL not installed - check if afl-fuzz is in PATH"
    echo "  3. Build tools missing - ensure gcc, make, etc. are installed"
    exit $BUILD_EXIT
fi
