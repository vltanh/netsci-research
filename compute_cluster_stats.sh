#!/bin/bash

# ==============================================================================
# Cluster Statistics Pipeline (compute_cluster_stats.sh)
# ==============================================================================
# Computes cluster-dependent statistics for a network and a community assignment.
#
# USAGE:
#   Real     : ./compute_cluster_stats.sh --real --network <id> --clustering <id>
#   Synthetic: ./compute_cluster_stats.sh --synthetic \
#                  --network <id> --generator <gen> --gt-clustering <id> \
#                  --clustering <id> [--run-id <id>]
#   Custom   : ./compute_cluster_stats.sh \
#                  --input-edgelist <path> --input-clustering <path> --output-dir <dir>
#
# OPTIONS:
#   [Macro: Real Networks]
#     --real                   : Use standard paths for empirical network CD results.
#     --network <id>           : Network identifier.
#     --clustering <id>        : Clustering identifier (CD algorithm output).
#
#   [Macro: Synthetic Networks]
#     --synthetic              : Use standard paths for synthetic network CD results.
#     --network <id>           : Network identifier.
#     --generator <gen>        : Generator identifier.
#     --gt-clustering <id>     : Ground-truth clustering identifier.
#     --clustering <id>        : Clustering identifier (estimated CD output).
#     --run-id <id>            : Run identifier (default: 0).
#
#   [Custom Paths]
#     --input-edgelist <p>     : Path to the input edge list CSV.
#     --input-clustering <p>   : Path to the community/clustering CSV.
#     --output-dir <dir>       : Target directory for stats outputs.
#
# PATH LEGEND:
#   [INP_EDGE]
#       Real      -> data/empirical_networks/networks/<network>/<network>.csv
#       Synthetic -> data/synthetic_networks/networks/<generator>/<gt-clustering>/<network>/<run-id>/edge.csv
#       Custom    -> <input-edgelist>
#   [INP_COM]
#       Real      -> data/reference_clusterings/clusterings/<clustering>/<network>/com.csv
#       Synthetic -> data/estimated_clusterings/<generator>/<gt-clustering>/clusterings/<clustering>/<network>/<run-id>/com.csv
#       Custom    -> <input-clustering>
#   [OUT_DIR]
#       Real      -> data/reference_clusterings/stats/<clustering>/<network>
#       Synthetic -> data/estimated_clusterings/<generator>/<gt-clustering>/stats/<clustering>/<network>/<run-id>
#       Custom    -> <output-dir>
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
if [[ "${SCRIPT_DIR}" == *"/slurmd/job"* ]]; then
    SCRIPT_DIR="${SLURM_SUBMIT_DIR}"
fi

# ==========================================
# Helper Functions: Logging
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
clustering_id=""
generator=""
gt_clustering_id=""
run_id="0"

custom_input=""
custom_com=""
custom_out_dir=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --real) is_real=1; shift ;;
        --synthetic) is_synthetic=1; shift ;;
        --network) network_id="$2"; shift 2 ;;
        --clustering) clustering_id="$2"; shift 2 ;;
        --generator) generator="$2"; shift 2 ;;
        --gt-clustering) gt_clustering_id="$2"; shift 2 ;;
        --run-id) run_id="$2"; shift 2 ;;
        --input-edgelist) custom_input="$2"; shift 2 ;;
        --input-clustering) custom_com="$2"; shift 2 ;;
        --output-dir) custom_out_dir="$2"; shift 2 ;;
        -*) log "Unknown parameter passed: $1"; exit 1 ;;
        *) log "Unexpected argument: $1"; exit 1 ;;
    esac
done

# ==========================================
# Input/Output Path Routing (Unified)
# ==========================================
if [ "${is_real}" -eq 1 ]; then
    if [ -z "${network_id}" ] || [ -z "${clustering_id}" ]; then
        log "Error: --network and --clustering are required for --real."
        exit 1
    fi
    INP_EDGE="data/empirical_networks/networks/${network_id}/${network_id}.csv"
    INP_COM="data/reference_clusterings/clusterings/${clustering_id}/${network_id}/com.csv"
    OUT_DIR="data/reference_clusterings/stats/${clustering_id}/${network_id}"
    dataset_name="${network_id} | Clustering: ${clustering_id}"

elif [ "${is_synthetic}" -eq 1 ]; then
    if [ -z "${network_id}" ] || [ -z "${generator}" ] || [ -z "${gt_clustering_id}" ] || [ -z "${clustering_id}" ]; then
        log "Error: --network, --generator, --gt-clustering, and --clustering are required for --synthetic."
        exit 1
    fi
    INP_EDGE="data/synthetic_networks/networks/${generator}/${gt_clustering_id}/${network_id}/${run_id}/edge.csv"
    INP_COM="data/estimated_clusterings/${generator}/${gt_clustering_id}/clusterings/${clustering_id}/${network_id}/${run_id}/com.csv"
    OUT_DIR="data/estimated_clusterings/${generator}/${gt_clustering_id}/stats/${clustering_id}/${network_id}/${run_id}"
    dataset_name="${network_id} | Generator: ${generator} | GT: ${gt_clustering_id} | Clustering: ${clustering_id} | Run: ${run_id}"

else
    if [ -z "${custom_input}" ] || [ -z "${custom_com}" ] || [ -z "${custom_out_dir}" ]; then
        log "Error: In custom mode, --input-edgelist, --input-clustering, and --output-dir are required."
        exit 1
    fi
    INP_EDGE="${custom_input}"
    INP_COM="${custom_com}"
    OUT_DIR="${custom_out_dir}"
    dataset_name="[Custom]${network_id:+" ${network_id}"}"
fi

if [ ! -f "${INP_EDGE}" ]; then
    log "CRITICAL: Edge list not found at ${INP_EDGE}"
    exit 1
fi
if [ ! -f "${INP_COM}" ]; then
    log "CRITICAL: Clustering file not found at ${INP_COM}"
    exit 1
fi

# ==========================================
# Orchestration
# ==========================================
log "============================"
log "Computing Cluster Stats for: ${dataset_name}"
log "============================"

log "Evaluating cluster stats state via Python StateTracker..."
mkdir -p "${OUT_DIR}"

{ /usr/bin/time -v python "${SCRIPT_DIR}/network_evaluation/network_stats/compute_cluster_stats.py" \
    --network "${INP_EDGE}" \
    --community "${INP_COM}" \
    --outdir "${OUT_DIR}"; } 2> "${OUT_DIR}/error.log"

if [ ${?} -ne 0 ]; then
    log "ERROR: Cluster Stats computation failed."
else
    log "Cluster Stats evaluation complete."
fi

log "Process completed. Outputs mapped to: ${OUT_DIR}"
