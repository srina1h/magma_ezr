#!/bin/bash
# Run captain (build + fuzz) then exp2json to produce bugs.json.
# Use from repo root. For macOS, run inside the runner container.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
export MAGMA="$REPO_ROOT/magma"
export WORKDIR="${WORKDIR:-$REPO_ROOT/workdir}"
CAPTAINRC="${1:-$REPO_ROOT/captainrc}"
BUGS_JSON="${2:-$REPO_ROOT/bugs.json}"

echo "[run_benchmark] Running captain..."
"$SCRIPT_DIR/run_captain.sh" "$CAPTAINRC"

echo "[run_benchmark] Running exp2json..."
python3 "$MAGMA/tools/benchd/exp2json.py" "$WORKDIR" "$BUGS_JSON"
echo "[run_benchmark] Wrote $BUGS_JSON"
