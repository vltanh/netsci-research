#!/bin/bash
#
# Drift detector for shared _common/ files (state.sh, pipeline_common.py).
# Compares CD + (when present) main-repo copies against the NG source-of-truth.
# Exits 0 if all bodies match; non-zero if any drift is detected.
# Run from any cwd; resolves paths relative to this script's location.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

NG_STATE="${ROOT}/network-generation/src/_common/state.sh"
NG_COMMON="${ROOT}/network-generation/src/pipeline_common.py"
CD_STATE="${ROOT}/community-detection/src/_common/state.sh"
CD_COMMON="${ROOT}/community-detection/src/_common/pipeline_common.py"
MAIN_STATE="${ROOT}/_common/state.sh"
MAIN_COMMON="${ROOT}/_common/pipeline_common.py"

drift_count=0

# state.sh: byte-equal modulo CD's leading "# Source:" header line(s).
diff_state_sh() {
    local label="$1"; local copy="$2"
    [ -f "${copy}" ] || { echo "[skip] state.sh: ${label} not present at ${copy}"; return; }
    # Strip leading lines starting with "# Source:" from copy, then byte-diff.
    local body
    body=$(awk 'NR == 1 && /^# Source:/ { next } { print }' "${copy}")
    if [ "$(printf "%s" "${body}")" = "$(cat "${NG_STATE}")" ]; then
        echo "[ok]   state.sh: ${label} matches NG"
    else
        echo "[FAIL] state.sh: ${label} drifted from NG"
        diff <(printf "%s" "${body}") "${NG_STATE}" | head -40
        drift_count=$((drift_count + 1))
    fi
}

diff_state_sh "CD" "${CD_STATE}"
diff_state_sh "main-repo" "${MAIN_STATE}"

# pipeline_common.py: function-level diff via Python AST. CD copy is a subset
# (decision 10) so we compare only same-named functions.
diff_pipeline_common() {
    local label="$1"; local copy="$2"
    [ -f "${copy}" ] || { echo "[skip] pipeline_common.py: ${label} not present at ${copy}"; return; }
    local rc
    python3 - "${NG_COMMON}" "${copy}" "${label}" <<'PY' || rc=$?
import ast
import sys

ng_path, copy_path, label = sys.argv[1], sys.argv[2], sys.argv[3]


def funcs(path):
    tree = ast.parse(open(path).read())
    return {
        node.name: ast.unparse(node)
        for node in tree.body
        if isinstance(node, ast.FunctionDef)
    }


ng = funcs(ng_path)
copy = funcs(copy_path)
shared = sorted(set(ng) & set(copy))
copy_only = sorted(set(copy) - set(ng))

if copy_only:
    print(f"[FAIL] pipeline_common.py: {label} has functions not in NG: {copy_only}")
    sys.exit(1)

drift = []
for name in shared:
    if ng[name] != copy[name]:
        drift.append(name)

if drift:
    print(f"[FAIL] pipeline_common.py: {label} body drift in: {drift}")
    sys.exit(1)

skipped = sorted(set(ng) - set(copy))
print(f"[ok]   pipeline_common.py: {label} matches NG ({len(shared)} shared, {len(skipped)} skipped: {skipped})")
PY
    if [ "${rc:-0}" -ne 0 ]; then
        drift_count=$((drift_count + 1))
    fi
}

diff_pipeline_common "CD" "${CD_COMMON}"
diff_pipeline_common "main-repo" "${MAIN_COMMON}"

echo "==="
if [ "${drift_count}" -eq 0 ]; then
    echo "All shared _common/ files are in sync."
    exit 0
else
    echo "DRIFT detected in ${drift_count} file(s)."
    exit 1
fi
