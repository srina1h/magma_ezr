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

# Pass AFL environment variables to captain
# Captain should pass these to Docker containers it creates
export AFL_SKIP_CPUFREQ="${AFL_SKIP_CPUFREQ:-1}"
export AFL_NO_AFFINITY="${AFL_NO_AFFINITY:-1}"
export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES="${AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES:-1}"
export AFL_NO_UI="${AFL_NO_UI:-1}"

# Pass through any AFL_* variables that are set
# (These should be set by run_knob_campaign.sh before calling this script)
"$MAGMA/tools/captain/run.sh" "$CAPTAINRC"
