#!/bin/bash
# Apply patches to magma for better compatibility.
# Fixes: timeout/sleep defaults, cp/rm edge cases, seeds fallback for manual runs.
# Run from repo root. Requires magma directory.
# Note: Patches are optional when using captain (normal path).

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

# 1. runonce.sh: rm -> rm -rf for runonce.tmp (file or dir), and cp -> cp -r so directory corpus works
if [ -f "$MAGMA/magma/runonce.sh" ]; then
    if grep -q 'rm "\$SHARED/runonce.tmp"' "$MAGMA/magma/runonce.sh" 2>/dev/null; then
        sed -i.bak 's/rm "\$SHARED\/runonce\.tmp"/rm -rf "\$SHARED\/runonce.tmp"/g' "$MAGMA/magma/runonce.sh"
        # Also fix already-patched rm -f so we get rm -rf
        sed -i.bak 's/rm -f "\$SHARED\/runonce\.tmp"/rm -rf "\$SHARED\/runonce.tmp"/g' "$MAGMA/magma/runonce.sh"
        rm -f "$MAGMA/magma/runonce.sh.bak"
        echo "  patched magma/magma/runonce.sh (rm -rf for runonce.tmp)"
    fi
    if grep -q 'cp --force "\$1"' "$MAGMA/magma/runonce.sh" 2>/dev/null; then
        sed -i.bak 's/cp --force "\$1"/cp -r --force "\$1"/g' "$MAGMA/magma/runonce.sh"
        rm -f "$MAGMA/magma/runonce.sh.bak"
        echo "  patched magma/magma/runonce.sh (cp -r for \$1)"
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

# 3b. magma/run.sh: when $1 is empty, use TARGET/corpus/PROGRAM for seeds (for manual docker run)
if [ -f "$MAGMA/magma/run.sh" ]; then
    if grep -q 'seeds=("\$1"/\*)' "$MAGMA/magma/run.sh" 2>/dev/null; then
        sed -i.bak 's/seeds=("\$1"\/*)/seeds=("${1:-$TARGET\/corpus\/$PROGRAM}"\/*)/g' "$MAGMA/magma/run.sh"
        rm -f "$MAGMA/magma/run.sh.bak" 2>/dev/null
        echo "  patched magma/magma/run.sh (seeds from corpus when no \$1)"
    fi
fi

# 3d. Fuzzer run scripts: use corpus/PROGRAM as AFL input dir (seeds live in corpus/PROGRAM/, not corpus/)
for f in "$MAGMA/fuzzers/afl/run.sh" "$MAGMA/fuzzers/aflplusplus/run.sh" "$MAGMA/fuzzers/aflfast/run.sh" "$MAGMA/fuzzers/libfuzzer/run.sh"; do
    if [ -f "$f" ] && grep -q '\$TARGET/corpus[^/]' "$f" 2>/dev/null; then
        sed -i.bak 's|\$TARGET/corpus"|\$TARGET/corpus/\$PROGRAM"|g' "$f"
        sed -i.bak 's|"\$TARGET/corpus"|"\$TARGET/corpus/\$PROGRAM"|g' "$f"
        rm -f "$f.bak" 2>/dev/null
        echo "  patched $f (AFL -i corpus/PROGRAM)"
    fi
done

# 3e. Fuzzer run scripts: add afl-fuzz -s ${AFL_SEED:-42} for reproducible RNG across experiments
for f in "$MAGMA/fuzzers/afl/run.sh" "$MAGMA/fuzzers/aflplusplus/run.sh" "$MAGMA/fuzzers/aflfast/run.sh"; do
    if [ -f "$f" ] && grep -q 'afl-fuzz' "$f" 2>/dev/null && ! grep -q 'AFL_SEED\|-s \${AFL_SEED' "$f" 2>/dev/null; then
        sed -i.bak 's/afl-fuzz /afl-fuzz -s ${AFL_SEED:-42} /g' "$f"
        rm -f "$f.bak" 2>/dev/null
        echo "  patched $f (afl-fuzz -s AFL_SEED for fixed RNG)"
    fi
done

# 4. Any .sh under magma: on lines containing "corpus", change "cp " to "cp -r " (avoid double -r)
find "$MAGMA" -name "*.sh" -type f 2>/dev/null | while read -r f; do
    if grep -q "corpus" "$f" 2>/dev/null && grep -q '\bcp ' "$f" 2>/dev/null; then
        # Only replace "cp " with "cp -r " on lines that contain corpus; skip if already "cp -r"
        if grep -qE 'corpus.*\bcp [^r-]|\bcp [^r-].*corpus' "$f" 2>/dev/null; then
            sed -i.bak '/corpus/ s/\bcp -r /cp -r /g; /corpus/ s/\bcp /cp -r /g' "$f"
            rm -f "$f.bak" 2>/dev/null
            echo "  patched $f (cp -r for corpus lines)"
        fi
    fi
done

echo "Done. Rebuild the Docker image so the container gets patched files:"
echo "  docker build -t magma/afl/libpng --build-arg fuzzer_name=afl --build-arg target_name=libpng --build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g) --build-arg canaries=1 -f $MAGMA/docker/Dockerfile $MAGMA"
echo ""
echo "Or run a campaign; captain will rebuild if needed."
echo "  ./scripts/run_knob_campaign.sh combo_0"
echo ""
