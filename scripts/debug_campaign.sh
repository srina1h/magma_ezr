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
echo "=== Docker Containers (if any running) ==="
docker ps -a | grep -E "afl|libpng" | head -5 || echo "No relevant containers found"

echo ""
echo "=== Check for fuzzer_stats ==="
FUZZER_STATS=$(find "$WORKDIR" -name "fuzzer_stats" -type f 2>/dev/null | head -1)
if [ -n "$FUZZER_STATS" ]; then
    echo "Found: $FUZZER_STATS"
    cat "$FUZZER_STATS"
else
    echo "No fuzzer_stats found"
fi
