#!/bin/bash
#
# Push CD result trees to server via rsync. Counterpart to
# tools/sync_from_server.sh; same exclude list + flag shape.
#
# Workflow: pull (sync_from_server.sh) -> edit locally -> push (this).
#
# Defaults to --update (skip files where server is newer) so concurrent
# server-side writes are NOT clobbered. Pass --no-update to disable.
#
# Usage:
#   tools/sync_to_server.sh <user@host> <remote-data-dir> [<local-data-dir>]
#   tools/sync_to_server.sh <user@host> <remote-data-dir> [<local-data-dir>] --dry-run
#   tools/sync_to_server.sh <user@host> <remote-data-dir> [<local-data-dir>] --delete-after
#
# Examples:
#   tools/sync_to_server.sh CampusCluster /u/vltanh/ecsbmv2/data
#   tools/sync_to_server.sh CampusCluster /u/vltanh/ecsbmv2/data --dry-run
#
# Always recommended: dry-run first, especially when --delete-after is involved.

set -eu

SERVER="${1:?usage: sync_to_server.sh <user@host> <remote-data-dir> [<local-data-dir>] [rsync flags...]}"
REMOTE_DEST="${2:?missing remote-data-dir}"
LOCAL_SRC="${3:-/home/vltanh/Documents/netsci-research/data}"
shift 3 2>/dev/null || shift 2

# Trailing slash on source: copy contents, not the directory itself.
LOCAL_SRC="${LOCAL_SRC%/}/"
REMOTE_DEST="${REMOTE_DEST%/}/"

EXCLUDES=(
    --exclude '__pycache__/'
    --exclude '*.pyc'
    --exclude '*.tmp.*'
    --exclude 'done.tmp.*'
    --exclude 'core.*'
    --exclude '.state/'
    --exclude '*.swp'
    --exclude '.DS_Store'
)

# Default to --update so concurrent server-side writes don't get clobbered.
# Pass --no-update to disable (push everything regardless of server mtime).
EXTRA=()
USE_UPDATE=1
for arg in "$@"; do
    if [[ "${arg}" == "--no-update" ]]; then
        USE_UPDATE=0
    else
        EXTRA+=("${arg}")
    fi
done
[ "${USE_UPDATE}" -eq 1 ] && EXTRA+=(--update)

echo "[sync] ${LOCAL_SRC}"
echo "[sync]   -> ${SERVER}:${REMOTE_DEST}"
echo "[sync] extra flags: ${EXTRA[*]:-}"
echo

rsync -azh --partial --progress --human-readable \
    "${EXCLUDES[@]}" \
    "${EXTRA[@]}" \
    "${LOCAL_SRC}" "${SERVER}:${REMOTE_DEST}"

echo
echo "[sync] done. Server now reflects local edits (subject to --update gate)."
echo "[sync] If --delete-after was passed, files absent locally were removed remotely."
