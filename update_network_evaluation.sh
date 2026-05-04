#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

# shellcheck disable=SC1091
source "${ROOT}/_common/state.sh"

log() {
    builtin echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "==> Pulling network_evaluation in all checkouts..."
git -C "$ROOT/network_evaluation" checkout main
git -C "$ROOT/network_evaluation" pull

git -C "$ROOT/network-generation/network_evaluation" checkout main
git -C "$ROOT/network-generation/network_evaluation" pull

git -C "$ROOT/community-detection/network_evaluation" checkout main
git -C "$ROOT/community-detection/network_evaluation" pull

echo "==> Updating submodule pointer in network-generation..."
git -C "$ROOT/network-generation" add network_evaluation
git -C "$ROOT/network-generation" commit -m "update network_evaluation submodule" || echo "  (nothing to commit in network-generation)"
git -C "$ROOT/network-generation" push

echo "==> Updating submodule pointer in community-detection..."
git -C "$ROOT/community-detection" add network_evaluation
git -C "$ROOT/community-detection" commit -m "update network_evaluation submodule" || echo "  (nothing to commit in community-detection)"
git -C "$ROOT/community-detection" push

echo "==> Updating submodule pointers in root..."
git -C "$ROOT" add network_evaluation network-generation community-detection
git -C "$ROOT" commit -m "update network_evaluation submodule" || echo "  (nothing to commit in root)"
git -C "$ROOT" push

echo "Done."
