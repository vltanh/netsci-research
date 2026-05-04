#!/bin/bash

# ==============================================================================
# Network Statistics Pipeline (compute_network_stats.sh)
# ==============================================================================
# Computes network-only structural statistics for an empirical or synthetic network.
#
# USAGE:
#   Real     : ./compute_network_stats.sh --real --network <id>
#   Synthetic: ./compute_network_stats.sh --synthetic \
#                  --network <id> --generator <gen> --clustering <id> [--run-id <id>]
#   Custom   : ./compute_network_stats.sh \
#                  --input-edgelist <path> --output-dir <dir>
#
# OPTIONS:
#   [Macro: Real Networks]
#     --real                   : Use standard paths for empirical networks.
#     --network <id>           : Network identifier.
#
#   [Macro: Synthetic Networks]
#     --synthetic              : Use standard paths for synthetic networks.
#     --network <id>           : Network identifier.
#     --generator <gen>        : Generator identifier.
#     --clustering <id>        : Reference clustering identifier.
#     --run-id <id>            : Run identifier (default: 0).
#
#   [Custom Paths]
#     --input-edgelist <p>     : Path to the input edge list CSV.
#     --output-dir <dir>       : Target directory for stats outputs.
#
# PATH LEGEND:
#   [INP_EDGE]
#       Real      -> data/empirical_networks/networks/<network>/<network>.csv
#       Synthetic -> data/synthetic_networks/networks/<generator>/<clustering>/<network>/<run-id>/edge.csv
#       Custom    -> <input-edgelist>
#   [OUT_DIR]
#       Real      -> data/empirical_networks/stats/<network>
#       Synthetic -> data/synthetic_networks/stats/<generator>/<clustering>/<network>/<run-id>/network
#       Custom    -> <output-dir>
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
if [[ "${SCRIPT_DIR}" == *"/slurmd/job"* ]]; then
    SCRIPT_DIR="${SLURM_SUBMIT_DIR}"
fi

# Shared helpers; Python-side StateTracker handles compute caching.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common/state.sh"

# ==========================================
# Helper Functions: Logging & State Tracking
# ==========================================
log() {
    builtin echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# ==========================================
# Argument Parsing
# ==========================================
is_real=0
is_synthetic=0
network_id=""
generator=""
clustering_id=""
run_id="0"

custom_input=""
custom_out_dir=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --real) is_real=1; shift ;;
        --synthetic) is_synthetic=1; shift ;;
        --network) network_id="$2"; shift 2 ;;
        --generator) generator="$2"; shift 2 ;;
        --clustering) clustering_id="$2"; shift 2 ;;
        --run-id) run_id="$2"; shift 2 ;;
        --input-edgelist) custom_input="$2"; shift 2 ;;
        --output-dir) custom_out_dir="$2"; shift 2 ;;
        -*) log "Unknown parameter passed: $1"; exit 1 ;;
        *) log "Unexpected argument: $1"; exit 1 ;;
    esac
done

# ==========================================
# Input/Output Path Routing (Unified)
# ==========================================
if [ "${is_real}" -eq 1 ]; then
    if [ -z "${network_id}" ]; then
        log "Error: --network is required for --real."
        exit 1
    fi
    INP_EDGE="data/empirical_networks/networks/${network_id}/${network_id}.csv"
    OUT_DIR="data/empirical_networks/stats/${network_id}"
    dataset_name="${network_id}"

elif [ "${is_synthetic}" -eq 1 ]; then
    if [ -z "${network_id}" ] || [ -z "${generator}" ] || [ -z "${clustering_id}" ]; then
        log "Error: --network, --generator, and --clustering are required for --synthetic."
        exit 1
    fi
    INP_EDGE="data/synthetic_networks/networks/${generator}/${clustering_id}/${network_id}/${run_id}/edge.csv"
    OUT_DIR="data/synthetic_networks/stats/${generator}/${clustering_id}/${network_id}/${run_id}/network"
    dataset_name="${network_id} | Generator: ${generator} | Clustering: ${clustering_id} | Run: ${run_id}"

else
    if [ -z "${custom_input}" ] || [ -z "${custom_out_dir}" ]; then
        log "Error: In custom mode, --input-edgelist and --output-dir are required."
        exit 1
    fi
    INP_EDGE="${custom_input}"
    OUT_DIR="${custom_out_dir}"
    dataset_name="[Custom]${network_id:+" ${network_id}"}"
fi

if [ ! -f "${INP_EDGE}" ]; then
    log "CRITICAL: Edge list not found at ${INP_EDGE}"
    exit 1
fi

# ==========================================
# Orchestration
# ==========================================
log "============================"
log "Computing Network Stats for: ${dataset_name}"
log "============================"

mkdir -p "${OUT_DIR}"
log_invocation_header "${OUT_DIR}/run.log" "n/a" "0"
log "Evaluating network stats state via Python StateTracker..."

{ /usr/bin/time -v python "${SCRIPT_DIR}/network_evaluation/network_stats/compute_network_stats.py" \
    --network "${INP_EDGE}" \
    --outdir "${OUT_DIR}"; } 2> "${OUT_DIR}/error.log"

if [ ${?} -ne 0 ]; then
    log "ERROR: Network Stats computation failed."
else
    log "Network Stats evaluation complete."
fi

log "Process completed. Outputs mapped to: ${OUT_DIR}"
