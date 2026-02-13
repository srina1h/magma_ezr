#!/bin/bash
# Run captain only (build + fuzz). Use from repo root.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
export MAGMA="$REPO_ROOT/magma"
export WORKDIR="${WORKDIR:-$REPO_ROOT/workdir}"
CAPTAINRC="${1:-$REPO_ROOT/captainrc}"

# Validate paths
if [ ! -d "$MAGMA" ]; then
    echo "ERROR: Magma directory not found: $MAGMA" >&2
    echo "Please ensure magma is cloned. Run: ./scripts/setup_local.sh" >&2
    exit 1
fi

if [ ! -f "$MAGMA/tools/captain/run.sh" ]; then
    echo "ERROR: Captain script not found: $MAGMA/tools/captain/run.sh" >&2
    exit 1
fi

if [ ! -f "$CAPTAINRC" ]; then
    echo "ERROR: Captain config not found: $CAPTAINRC" >&2
    exit 1
fi

echo "MAGMA=$MAGMA WORKDIR=$WORKDIR captainrc=$CAPTAINRC" >&2
"$MAGMA/tools/captain/run.sh" "$CAPTAINRC"
