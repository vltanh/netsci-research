#!/bin/bash
#
# Pull CD result trees from server via rsync. Incremental + resumable.
# Replaces ad-hoc scp transfers (which re-copy unchanged bytes every run).
#
# Usage:
#   tools/sync_from_server.sh <user@host> <remote-data-dir> [<local-data-dir>]
#   tools/sync_from_server.sh <user@host> <remote-data-dir> [<local-data-dir>] --delete-after
#   tools/sync_from_server.sh <user@host> <remote-data-dir> [<local-data-dir>] --dry-run
#
# Examples:
#   tools/sync_from_server.sh user@hpc.example ~/netsci-research/data
#   tools/sync_from_server.sh user@hpc.example ~/netsci-research/data /tmp/test --dry-run
#
# After sync, run tools/migrate_cd_data.py to refresh `done` files into the
# new state-system format if the server tree predates Phase 1.

set -eu

SERVER="${1:?usage: sync_from_server.sh <user@host> <remote-data-dir> [<local-data-dir>] [rsync flags...]}"
REMOTE_SRC="${2:?missing remote-data-dir}"
LOCAL_DEST="${3:-/home/vltanh/Documents/netsci-research/data}"
shift 3 2>/dev/null || shift 2

# Trailing slash on source: copy contents, not the directory itself.
REMOTE_SRC="${REMOTE_SRC%/}/"
LOCAL_DEST="${LOCAL_DEST%/}/"

mkdir -p "${LOCAL_DEST}"

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

echo "[sync] ${SERVER}:${REMOTE_SRC}"
echo "[sync]   -> ${LOCAL_DEST}"
echo "[sync] extra flags: $*"
echo

rsync -azh --partial --progress --human-readable \
    "${EXCLUDES[@]}" \
    "$@" \
    "${SERVER}:${REMOTE_SRC}" "${LOCAL_DEST}"

echo
echo "[sync] done. If server tree predates Phase 1 state-system,"
echo "[sync] run: python3 tools/migrate_cd_data.py ${LOCAL_DEST}<algo-tree-root>"
