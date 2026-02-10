#!/bin/bash
# Run captain only (build + fuzz). Use from repo root.
# When running in Docker runner: WORKDIR is set to /workspace/workdir.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
export MAGMA="$REPO_ROOT/magma"
export WORKDIR="${WORKDIR:-$REPO_ROOT/workdir}"
CAPTAINRC="${1:-$REPO_ROOT/captainrc}"
echo "MAGMA=$MAGMA WORKDIR=$WORKDIR captainrc=$CAPTAINRC"
"$MAGMA/tools/captain/run.sh" "$CAPTAINRC"
