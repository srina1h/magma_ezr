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
CAPTAINRC="${2:-$REPO_ROOT/captainrc.5m}"
OUTPUT_DIR="${3:-$REPO_ROOT/ezr_results}"

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
"$SCRIPT_DIR/run_captain.sh" "$CAPTAINRC"

# Extract metrics from fuzzer_stats and monitor CSVs
RUN_OUTPUT="$OUTPUT_DIR/$RUN_LABEL"
mkdir -p "$RUN_OUTPUT"

# Run exp2json
BUGS_JSON="$RUN_OUTPUT/bugs.json"
python3 "$MAGMA/tools/benchd/exp2json.py" "$WORKDIR" "$BUGS_JSON" 2>/dev/null || true

# Extract coverage from fuzzer_stats (AFL writes this into the findings dir)
# Look in the cache/shared directory for fuzzer_stats
FUZZER_STATS=$(find "$WORKDIR" -name "fuzzer_stats" -type f 2>/dev/null | head -1)
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
