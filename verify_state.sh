#!/bin/bash

# Usage: ./verify_state.sh [directory_to_scan]
# Defaults to the current directory if none is provided.
#
# Independent of _common/state.sh today (uses sha256sum --quiet -c directly
# for streamed-progress UX); shares the done/done.tmp.* convention managed by
# state.sh's mark_done. Future: harmonize via is_state_tree_consistent.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common/state.sh"

TARGET_DIR="${1:-.}"

echo "=================================================="
echo "Cryptographic State Verifier"
echo "Scanning for ledgers and orphaned temporary files in: ${TARGET_DIR}"
echo "=================================================="

VALID=0
INVALID=0
ORPHANED=0
TOTAL=0

# 1. Verify standard ledgers
while IFS= read -r -d '' ledger; do
    ((TOTAL++))
    if error_out=$(sha256sum --quiet -c "$ledger" 2>&1); then
        ((VALID++))
        # \r moves cursor to start of line, \033[K clears the line from cursor to end
        printf "\r\033[K[ OK ] Valid ledgers verified: %d" "$VALID"
    else
        # Clear the counter line, print the failure, and drop to a new line
        printf "\r\033[K[FAILED]  %s\n" "$ledger"
        echo "$error_out" | sed 's/^/            -> /'
        ((INVALID++))
    fi
done < <(find "$TARGET_DIR" -type f -name "done" -print0)

# Drop to a new line after the loop finishes
printf "\n"

# 2. Detect orphaned temporary ledgers
echo "--------------------------------------------------"
while IFS= read -r -d '' orphan; do
    ((ORPHANED++))
    printf "[ORPHAN]  %s\n" "$orphan"
done < <(find "$TARGET_DIR" -type f -name "done.tmp.*" -print0)

echo "=================================================="
echo "Verification Summary"
echo "=================================================="
echo "Total Ledgers Found : $TOTAL"
echo "Intact State Nodes  : $VALID"
echo "Corrupted/Missing   : $INVALID"
echo "Orphaned Temp Files : $ORPHANED"

if [ "$INVALID" -gt 0 ] || [ "$ORPHANED" -gt 0 ]; then
    echo "Status: Inconsistencies detected. Review failed states and orphaned temp files."
    exit 1
else
    echo "Status: All evaluated states are cryptographically sound. No orphaned files."
    exit 0
fi