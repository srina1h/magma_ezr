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

CAPTAINRC="$REPO_ROOT/captainrc.dataset"
if [ ! -f "$CAPTAINRC" ]; then
    echo "ERROR: Captain config not found: $CAPTAINRC"
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
echo "CAPTAINRC=$CAPTAINRC"
echo ""

# Use run.sh with a timeout - it will build first, then start fuzzing
# We'll kill it after a short time to just test the build
echo "Running captain (will timeout after 60s to test build)..."
echo ""

# Run captain and capture output
if timeout 60 "$MAGMA/tools/captain/run.sh" "$CAPTAINRC" 2>&1 | tee /tmp/captain_test.log; then
    CAPTAIN_EXIT=0
else
    CAPTAIN_EXIT=$?
    # Timeout (124) is OK - it means build probably worked
    if [ "$CAPTAIN_EXIT" = "124" ]; then
        echo ""
        echo "✓ Build completed (timeout is expected - we just wanted to test the build)"
        CAPTAIN_EXIT=0
    fi
fi

# Check if build artifacts exist
BUILD_ARTIFACTS=$(find "$WORKDIR" -type f \( -name "*.o" -o -name "libpng_read_fuzzer" -o -name "*.a" \) 2>/dev/null | head -5)
if [ -n "$BUILD_ARTIFACTS" ]; then
    echo ""
    echo "✓ Build artifacts found:"
    echo "$BUILD_ARTIFACTS" | head -5
    echo ""
    echo "✓ Build successful! You can now run:"
    echo "  python3 scripts/build_dataset.py --budget 20m"
    exit 0
fi

# If we get here, build likely failed
echo ""
echo "✗ Build may have failed - no build artifacts found"
echo ""

# Show build logs
echo "Build logs:"
if [ -d "$WORKDIR/log" ]; then
    find "$WORKDIR/log" -type f 2>/dev/null | while read logfile; do
        echo ""
        echo "=== $logfile ==="
        tail -50 "$logfile"
    done
else
    echo "No build logs found in $WORKDIR/log"
fi

# Show captain output
if [ -f "/tmp/captain_test.log" ]; then
    echo ""
    echo "=== Captain output (last 100 lines) ==="
    tail -100 /tmp/captain_test.log
fi

echo ""
echo "Common issues:"
echo "  1. Missing dependencies - run: ./scripts/setup_local.sh"
echo "  2. AFL not installed - check: which afl-fuzz"
echo "  3. Build tools missing - ensure gcc, make, etc. are installed"
echo "  4. Check captainrc config - ensure FUZZERS=(afl) and afl_TARGETS=(libpng)"

exit 1
