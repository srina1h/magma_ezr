#!/bin/bash
# Apply patches to magma to fix:
#   1. runonce.sh: rm runonce.tmp -> rm -f (avoid error when file missing)
#   2. magma/run.sh: timeout $TIMEOUT -> timeout ${TIMEOUT:-1200} (avoid empty TIMEOUT)
#   3. Any run.sh: sleep $POLL -> sleep ${POLL:-5}
# Run from repo root. Requires magma directory.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAGMA="$REPO_ROOT/magma"
PATCHES_DIR="$SCRIPT_DIR/../patches"

if [ ! -d "$MAGMA" ]; then
    echo "ERROR: magma directory not found: $MAGMA"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

echo "Applying patches to magma..."

# 1. runonce.sh: rm -> rm -f for runonce.tmp
if [ -f "$MAGMA/magma/runonce.sh" ]; then
    if grep -q 'rm "\$SHARED/runonce.tmp"' "$MAGMA/magma/runonce.sh" 2>/dev/null; then
        sed -i.bak 's/rm "\$SHARED\/runonce\.tmp"/rm -f "\$SHARED\/runonce.tmp"/g' "$MAGMA/magma/runonce.sh"
        rm -f "$MAGMA/magma/runonce.sh.bak"
        echo "  patched magma/magma/runonce.sh (rm -f)"
    fi
fi

# 2. magma/run.sh: timeout $TIMEOUT -> timeout ${TIMEOUT:-1200}
if [ -f "$MAGMA/magma/run.sh" ]; then
    if grep -q 'timeout \$TIMEOUT' "$MAGMA/magma/run.sh" 2>/dev/null; then
        sed -i.bak 's/timeout \$TIMEOUT/timeout ${TIMEOUT:-1200}/g' "$MAGMA/magma/run.sh"
        rm -f "$MAGMA/magma/run.sh.bak"
        echo "  patched magma/magma/run.sh (timeout default)"
    fi
fi

# 3. sleep $POLL -> sleep ${POLL:-5} in magma/run.sh
if [ -f "$MAGMA/magma/run.sh" ]; then
    if grep -q 'sleep \$POLL' "$MAGMA/magma/run.sh" 2>/dev/null; then
        sed -i.bak 's/sleep \$POLL/sleep ${POLL:-5}/g' "$MAGMA/magma/run.sh"
        rm -f "$MAGMA/magma/run.sh.bak"
        echo "  patched magma/magma/run.sh (sleep POLL default)"
    fi
fi

# 4. Find and fix cp corpus (often in fuzzers/afl/run.sh or similar)
for f in "$MAGMA/fuzzers/afl/run.sh" "$MAGMA/targets/libpng/run.sh" "$MAGMA"/fuzzers/*/run.sh; do
    if [ -f "$f" ]; then
        if grep -qE 'cp [^r-].*corpus|cp \$\w+.*corpus' "$f" 2>/dev/null; then
            sed -i.bak 's/cp \(\$[^ ]*corpus[^ ]*\)/cp -r \1/g' "$f" 2>/dev/null || true
            sed -i.bak 's/cp \(\${[^}]*corpus[^}]*\}\)/cp -r \1/g' "$f" 2>/dev/null || true
            rm -f "$f.bak" 2>/dev/null
            echo "  patched $f (cp -r corpus)"
        fi
    fi
done

echo "Done. Rebuild the Docker image so the container gets patched files:"
echo "  docker build -t magma/afl/libpng --build-arg fuzzer_name=afl --build-arg target_name=libpng --build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g) --build-arg canaries=1 -f $MAGMA/docker/Dockerfile $MAGMA"
echo ""
echo "Or run a campaign; captain will rebuild if needed."
echo "  ./scripts/run_knob_campaign.sh combo_0"
echo ""
