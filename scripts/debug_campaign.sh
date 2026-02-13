#!/bin/bash
# Debug script to check why campaigns are failing
# Usage: ./scripts/debug_campaign.sh [combo_label]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

COMBO_LABEL="${1:-combo_1}"
WORKDIR="${WORKDIR:-$REPO_ROOT/workdir}"
RESULTS_DIR="$REPO_ROOT/dataset_results"

echo "Debugging campaign: $COMBO_LABEL"
echo "WORKDIR: $WORKDIR"
echo ""

# Check if workdir exists
if [ ! -d "$WORKDIR" ]; then
    echo "ERROR: Workdir not found: $WORKDIR"
    exit 1
fi

# Check logs
echo "=== Build Logs ==="
find "$WORKDIR/log" -name "*build*" -type f 2>/dev/null | while read logfile; do
    echo ""
    echo "--- $logfile ---"
    tail -50 "$logfile"
done

echo ""
echo "=== All Logs ==="
find "$WORKDIR/log" -type f 2>/dev/null | while read logfile; do
    echo ""
    echo "--- $logfile ---"
    tail -30 "$logfile"
done

echo ""
echo "=== Workdir Structure ==="
find "$WORKDIR" -type f -name "*.log" -o -name "*stats*" -o -name "*output*" 2>/dev/null | head -20

echo ""
echo "=== Metrics ==="
if [ -f "$RESULTS_DIR/$COMBO_LABEL/metrics.json" ]; then
    cat "$RESULTS_DIR/$COMBO_LABEL/metrics.json" | python3 -m json.tool
else
    echo "No metrics.json found for $COMBO_LABEL"
fi

echo ""
echo "=== Docker Images ==="
docker images | grep -E "magma|afl|libpng" | head -10 || echo "No relevant images found"

echo ""
echo "=== Docker Containers (all recent) ==="
docker ps -a --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}" | head -10

echo ""
echo "=== Check if magma/afl/libpng image exists ==="
if docker images magma/afl/libpng --format "{{.Repository}}:{{.Tag}}" | grep -q .; then
    echo "✓ Image exists:"
    docker images magma/afl/libpng
else
    echo "✗ Image magma/afl/libpng does NOT exist - build likely failed"
fi

echo ""
echo "=== Full Build Log ==="
if [ -f "$WORKDIR/log/afl_libpng_build.log" ]; then
    echo "Full build log ($(wc -l < "$WORKDIR/log/afl_libpng_build.log" | tr -d ' ') lines):"
    cat "$WORKDIR/log/afl_libpng_build.log"
else
    echo "No build log found"
fi

echo ""
echo "=== Check for fuzzer_stats ==="
FUZZER_STATS=$(find "$WORKDIR" -name "fuzzer_stats" -type f 2>/dev/null | head -1)
if [ -n "$FUZZER_STATS" ]; then
    echo "Found: $FUZZER_STATS"
    cat "$FUZZER_STATS"
else
    echo "No fuzzer_stats found"
fi

echo ""
echo "=== Test running container manually ==="
if docker images magma/afl/libpng --format "{{.Repository}}" | grep -q magma; then
    echo "Attempting to run container manually (will timeout after 10s)..."
    timeout 10 docker run --rm \
        -v "$WORKDIR:/magma/workdir" \
        -e MAGMA=/magma \
        -e WORKDIR=/magma/workdir \
        magma/afl/libpng \
        /bin/bash -c "echo 'Container started successfully'; sleep 5" 2>&1 || true
    echo ""
    echo "If container ran, the issue is with captain's container configuration"
else
    echo "Cannot test - image doesn't exist"
fi

echo ""
echo "=== Check workdir structure ==="
echo "Directories in workdir:"
find "$WORKDIR" -type d -maxdepth 2 | head -20
echo ""
echo "Files in workdir:"
find "$WORKDIR" -type f | head -20
