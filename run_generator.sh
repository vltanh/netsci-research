#!/bin/bash

GENERATOR=$1
NETWORK_ID=$2
CLUSTERING_ID=$3
RUN_ID=${4:-"0"} # Default to "0" if not provided

if [ -z "$NETWORK_ID" ] || [ -z "$CLUSTERING_ID" ] || [ -z "$GENERATOR" ]; then
    echo "Usage: $0 <generator> <network_id> <clustering_id> [run_id]"
    exit 1
fi

# ==========================================
# Generator Configuration Parsing
# ==========================================
if [[ "${GENERATOR}" == "ec-sbm-v2" ]]; then
    OUTLIER_MODE="combined"
    EDGE_CORRECTION="rewire" # Note: Kept as "rewire" matching the python args
    MATCH_ALGO="true_greedy"
elif [[ "${GENERATOR}" == "ec-sbm-v1.5" ]]; then
    OUTLIER_MODE="singleton"
    EDGE_CORRECTION="drop"
    MATCH_ALGO="greedy"
else
    # Fallback or additional generator mappings can be added here
    OUTLIER_MODE="combined"
    EDGE_CORRECTION="rewire"
    MATCH_ALGO="true_greedy"
fi

# ==========================================
# Path Definitions
# ==========================================
INP_EDGE="data/empirical_networks/netzschleuder/${NETWORK_ID}/${NETWORK_ID}.csv"
INP_COM="data/reference_clusterings/clusterings/${CLUSTERING_ID}/${NETWORK_ID}/com.csv"

# Pre-computed stats directories (Reference & Empirical)
REFERENCE_STATS_DIR="data/reference_clusterings/stats/${CLUSTERING_ID}/${NETWORK_ID}"
EMPIRICAL_NETWORK_STATS_DIR="data/empirical_networks/stats/${NETWORK_ID}"

# Output directories for the synthetic generation
OUT_DIR="data/synthetic_networks/${GENERATOR}/networks/${CLUSTERING_ID}/${NETWORK_ID}/${RUN_ID}/"
STATS_DIR="data/synthetic_networks/${GENERATOR}/stats/${CLUSTERING_ID}/${NETWORK_ID}/${RUN_ID}"

# New split output paths for stats
SYNTH_CLUSTER_STATS_DIR="${STATS_DIR}/cluster/"
SYNTH_NETWORK_STATS_DIR="${STATS_DIR}/network/"

# ==========================================
# Function: Run Statistics (Synthetic)
# ==========================================
run_stats() {
    local edge_file=$1
    local com_file=$2
    local cluster_out_dir=$3
    local network_out_dir=$4

    echo "Computing stats..."
    
    # 1. Compute Cluster-Dependent Stats
    if [ ! -f "${cluster_out_dir}/done" ]; then
        mkdir -p "${cluster_out_dir}"
        { /usr/bin/time -v python network_evaluation/network_stats/compute_cluster_stats.py \
            --network "${edge_file}" \
            --community "${com_file}" \
            --outdir "${cluster_out_dir}"; } 2> "${cluster_out_dir}/cluster_error.log"
        touch "${cluster_out_dir}/done"
        echo "Cluster stats completed."
    else
        echo "Cluster stats already done."
    fi

    # 2. Compute Network-Only Stats
    if [ ! -f "${network_out_dir}/done" ]; then
        mkdir -p "${network_out_dir}"
        { /usr/bin/time -v python network_evaluation/network_stats/compute_network_stats.py \
            --network "${edge_file}" \
            --outdir "${network_out_dir}"; } 2> "${network_out_dir}/network_error.log"
        touch "${network_out_dir}/done"
        echo "Network stats completed."
    else
        echo "Network stats already done."
    fi
}

# ==========================================
# Orchestration
# ==========================================
echo "============================"
echo "Running: ${GENERATOR} on ${NETWORK_ID} (Clustering: ${CLUSTERING_ID}, Run: ${RUN_ID})"

if [ ! -f "${INP_EDGE}" ]; then echo "CRITICAL: Input network missing: ${INP_EDGE}"; exit 1; fi
if [ ! -f "${INP_COM}" ]; then echo "CRITICAL: Input clustering missing: ${INP_COM}"; exit 1; fi

mkdir -p "${OUT_DIR}"

if [[ "${GENERATOR}" == ec-sbm-v2* ]]; then
    ./src/generate/ec-sbm/v2/pipeline.sh \
        --input-edgelist "${INP_EDGE}" \
        --input-clustering "${INP_COM}" \
        --output-dir "${OUT_DIR}" \
        --outlier-mode "${OUTLIER_MODE}" \
        --edge-correction "${EDGE_CORRECTION}" \
        --algorithm "${MATCH_ALGO}"
else
    echo "Notice: Generator ${GENERATOR} is not an ec-sbm variant. Pipeline skipped."
fi

# Run stats using the newly generated network against the reference clustering
if [ -f "${OUT_DIR}/edge.csv" ]; then
    run_stats "${OUT_DIR}/edge.csv" "${INP_COM}" "${SYNTH_CLUSTER_STATS_DIR}" "${SYNTH_NETWORK_STATS_DIR}"
else
    echo "Generation failed or incomplete. Cannot compute stats."
fi

# ==========================================
# Compare Statistics
# ==========================================
COMPARISON_OUT_CSV="${STATS_DIR}/comparison.csv"

# Validate that required directories exist before running
if [ -d "${SYNTH_CLUSTER_STATS_DIR}" ] && [ -d "${REFERENCE_STATS_DIR}" ] && \
   [ -d "${SYNTH_NETWORK_STATS_DIR}" ] && [ -d "${EMPIRICAL_NETWORK_STATS_DIR}" ]; then
    
    python network_evaluation/compare/compare_stats.py \
        --cluster-1-folder "${SYNTH_CLUSTER_STATS_DIR}" \
        --cluster-2-folder "${REFERENCE_STATS_DIR}" \
        --network-1-folder "${SYNTH_NETWORK_STATS_DIR}" \
        --network-2-folder "${EMPIRICAL_NETWORK_STATS_DIR}" \
        --output-file "${COMPARISON_OUT_CSV}" \
        --is-compare-sequence
    
    echo "Comparison results generated at: ${COMPARISON_OUT_CSV}"
else
    echo "Warning: Skipping comparison. One or more stat directories do not exist."
    echo "  - Synth Cluster Stats: ${SYNTH_CLUSTER_STATS_DIR}"
    echo "  - Synth Network Stats: ${SYNTH_NETWORK_STATS_DIR}"
    echo "  - Ref Cluster Stats:   ${REFERENCE_STATS_DIR}"
    echo "  - Ref Network Stats:   ${EMPIRICAL_NETWORK_STATS_DIR}"
fi

echo "[gen] ${GENERATOR} ${NETWORK_ID} ${CLUSTERING_ID} ${RUN_ID}" >> complete.log