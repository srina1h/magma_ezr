#!/bin/bash
# Run a single knob campaign: build (if needed) + fuzz + extract metrics.
# Usage: ./scripts/run_knob_campaign.sh <run_label> [captainrc] [output_dir]
#
# AFL knobs are read from env vars: AFL_FAST_CAL, AFL_NO_ARITH, AFL_NO_HAVOC, etc.
# Results are written to <output_dir>/<run_label>/metrics.json
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

RUN_LABEL="${1:?Usage: run_knob_campaign.sh <run_label> [captainrc] [output_dir]}"
CAPTAINRC="${2:-$REPO_ROOT/captainrc.dataset}"
OUTPUT_DIR="${3:-$REPO_ROOT/dataset_results}"

export MAGMA="$REPO_ROOT/magma"
export WORKDIR="${WORKDIR:-$REPO_ROOT/workdir}"

# Clean previous workdir for this run
if [ -d "$WORKDIR" ]; then
    rm -rf "$WORKDIR"
fi
mkdir -p "$WORKDIR"

# Run captain (build + fuzz)
echo "[knob_campaign] Label=$RUN_LABEL Config=$CAPTAINRC"
echo "[knob_campaign] AFL knobs:"
env | grep '^AFL_' | sort || true

# Fixed RNG seed so all configuration experiments are comparable (afl-fuzz -s seed)
export AFL_SEED="${AFL_SEED:-42}"

# Export AFL environment variables so they're available to captain and Docker containers
# Captain's run.sh should pass these to the containers it creates
export AFL_FAST_CAL="${AFL_FAST_CAL:-0}"
export AFL_NO_ARITH="${AFL_NO_ARITH:-0}"
export AFL_NO_HAVOC="${AFL_NO_HAVOC:-0}"
export AFL_DISABLE_TRIM="${AFL_DISABLE_TRIM:-0}"
export AFL_SHUFFLE_QUEUE="${AFL_SHUFFLE_QUEUE:-0}"
export AFL_SKIP_CPUFREQ="${AFL_SKIP_CPUFREQ:-1}"
export AFL_NO_AFFINITY="${AFL_NO_AFFINITY:-1}"
export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES="${AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES:-1}"
export AFL_NO_UI="${AFL_NO_UI:-1}"

# Check if magma exists
if [ ! -d "$MAGMA" ]; then
    echo "ERROR: Magma directory not found: $MAGMA"
    echo "Please run: ./scripts/setup_local.sh"
    exit 1
fi

if [ ! -f "$MAGMA/tools/captain/run.sh" ]; then
    echo "ERROR: Captain script not found: $MAGMA/tools/captain/run.sh"
    echo "Magma may not be properly initialized"
    exit 1
fi

if [ ! -f "$CAPTAINRC" ]; then
    echo "ERROR: Captain config not found: $CAPTAINRC"
    exit 1
fi

echo "[knob_campaign] Running captain..."
CAPTAIN_START=$(date +%s)
if ! "$SCRIPT_DIR/run_captain.sh" "$CAPTAINRC"; then
    CAPTAIN_EXIT=$?
    CAPTAIN_ELAPSED=$(($(date +%s) - CAPTAIN_START))
    echo "ERROR: Captain failed with exit code $CAPTAIN_EXIT after ${CAPTAIN_ELAPSED}s" >&2
    
    # Check if Docker image was built
    echo "" >&2
    echo "Checking Docker image..." >&2
    if docker images magma/afl/libpng --format "{{.Repository}}" | grep -q magma; then
        echo "✓ Docker image exists" >&2
    else
        echo "✗ Docker image magma/afl/libpng does NOT exist - build failed!" >&2
    fi
    
    # Check build logs for more info
    BUILD_LOG=$(find "$WORKDIR/log" -name "*build*" -type f 2>/dev/null | head -1)
    if [ -n "$BUILD_LOG" ] && [ -f "$BUILD_LOG" ]; then
        echo "" >&2
        echo "Build log: $BUILD_LOG" >&2
        echo "Last 100 lines:" >&2
        tail -100 "$BUILD_LOG" >&2
    fi
    
    # Check for run/fuzzing logs
    echo "" >&2
    echo "Checking for fuzzing/run logs..." >&2
    find "$WORKDIR/log" -type f 2>/dev/null | while read logfile; do
        echo "=== $logfile ===" >&2
        tail -50 "$logfile" >&2
        echo "" >&2
    done
    
    # Check for container logs in workdir
    echo "Checking for container output..." >&2
    find "$WORKDIR" -name "*.log" -o -name "*output*" -o -name "*error*" 2>/dev/null | head -10 | while read logfile; do
        echo "=== $logfile ===" >&2
        tail -50 "$logfile" >&2
        echo "" >&2
    done
    
    exit $CAPTAIN_EXIT
fi

# Extract metrics from fuzzer_stats and monitor CSVs
RUN_OUTPUT="$OUTPUT_DIR/$RUN_LABEL"
mkdir -p "$RUN_OUTPUT"

# Run exp2json
BUGS_JSON="$RUN_OUTPUT/bugs.json"
python3 "$MAGMA/tools/benchd/exp2json.py" "$WORKDIR" "$BUGS_JSON" 2>/dev/null || true

# Extract coverage from fuzzer_stats (AFL writes into findings; captain may put it in workdir/ar/.../ball.tar)
FUZZER_STATS=$(find "$WORKDIR" -name "fuzzer_stats" -type f 2>/dev/null | head -1)
EXTRACT_DIR=""

# If not found, captain may have archived output in ball.tar - extract and look inside
if [ -z "$FUZZER_STATS" ]; then
    BALL_TAR=$(find "$WORKDIR" -name "ball.tar" -type f 2>/dev/null | head -1)
    if [ -n "$BALL_TAR" ]; then
        EXTRACT_DIR=$(mktemp -d)
        if tar -xf "$BALL_TAR" -C "$EXTRACT_DIR" 2>/dev/null; then
            FUZZER_STATS=$(find "$EXTRACT_DIR" -name "fuzzer_stats" -type f 2>/dev/null | head -1)
        fi
    fi
fi

COVERAGE=0
PATHS_TOTAL=0
EXECS_DONE=0
EXECS_PER_SEC=0

if [ -n "$FUZZER_STATS" ]; then
    COVERAGE=$(grep -oP 'bitmap_cvg\s*:\s*\K[0-9.]+' "$FUZZER_STATS" 2>/dev/null || echo "0")
    PATHS_TOTAL=$(grep -oP 'paths_total\s*:\s*\K[0-9]+' "$FUZZER_STATS" 2>/dev/null || echo "0")
    EXECS_DONE=$(grep -oP 'execs_done\s*:\s*\K[0-9]+' "$FUZZER_STATS" 2>/dev/null || echo "0")
    EXECS_PER_SEC=$(grep -oP 'execs_per_sec\s*:\s*\K[0-9.]+' "$FUZZER_STATS" 2>/dev/null || echo "0")
    cp "$FUZZER_STATS" "$RUN_OUTPUT/fuzzer_stats"
fi
[ -n "$EXTRACT_DIR" ] && [ -d "$EXTRACT_DIR" ] && rm -rf "$EXTRACT_DIR"

if [ -z "$FUZZER_STATS" ]; then
    echo "[knob_campaign] WARNING: no fuzzer_stats found under $WORKDIR or inside ball.tar" >&2
    echo "[knob_campaign] workdir contents:" >&2
    find "$WORKDIR" -type f 2>/dev/null | head -50 >&2
    echo "[knob_campaign] workdir log dir:" >&2
    ls -la "$WORKDIR/log" 2>/dev/null >&2 || true
    for f in "$WORKDIR"/log/*; do
        [ -f "$f" ] && echo "--- $f (last 20 lines) ---" >&2 && tail -20 "$f" 2>/dev/null >&2
    done 2>/dev/null || true
fi

# Count bugs from bugs.json
BUGS_TRIGGERED=0
BUGS_REACHED=0
if [ -f "$BUGS_JSON" ]; then
    BUGS_TRIGGERED=$(python3 -c "
import json
d = json.load(open('$BUGS_JSON'))
r = d.get('results',{})
count = 0
for f in r.values():
  for t in f.values():
    for p in t.values():
      for run in p.values():
        count += len(run.get('triggered',{}))
print(count)
" 2>/dev/null || echo "0")
    BUGS_REACHED=$(python3 -c "
import json
d = json.load(open('$BUGS_JSON'))
r = d.get('results',{})
count = 0
for f in r.values():
  for t in f.values():
    for p in t.values():
      for run in p.values():
        count += len(run.get('reached',{}))
print(count)
" 2>/dev/null || echo "0")
fi

# Collect AFL knob settings
AFL_KNOBS=$(env | grep '^AFL_' | sort | tr '\n' ';' || echo "defaults")

# Write metrics JSON
cat > "$RUN_OUTPUT/metrics.json" <<EOF
{
  "label": "$RUN_LABEL",
  "captainrc": "$CAPTAINRC",
  "afl_knobs": "$AFL_KNOBS",
  "bitmap_cvg_pct": $COVERAGE,
  "paths_total": $PATHS_TOTAL,
  "execs_done": $EXECS_DONE,
  "execs_per_sec": $EXECS_PER_SEC,
  "bugs_triggered": $BUGS_TRIGGERED,
  "bugs_reached": $BUGS_REACHED
}
EOF

echo "[knob_campaign] Results → $RUN_OUTPUT/metrics.json"
cat "$RUN_OUTPUT/metrics.json"
