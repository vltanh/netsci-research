#!/bin/bash

# ==============================================================================
# Synthetic Network Generator (run_generator.sh)
# ==============================================================================
# This script generates a synthetic network based on an empirical network and 
# a reference clustering, then computes and compares network/cluster statistics.
#
# USAGE:
#   ./run_generator.sh <generator> <network_id> <clustering_id> [run_id]
#
# ------------------------------------------------------------------------------
# STEP 1: Generation Pipeline
# ------------------------------------------------------------------------------
# [Inputs]
#   - Empirical Edgelist : data/empirical_networks/netzschleuder/<network_id>/<network_id>.csv
#   - Ground Truth Coms  : data/reference_clusterings/clusterings/<clustering_id>/<network_id>/com.csv
# [Outputs]
#   - Synth Edgelist     : data/synthetic_networks/networks/<generator>/<clustering_id>/<network_id>/<run_id>/edge.csv
#
# ------------------------------------------------------------------------------
# STEP 2: Statistics Computation
# ------------------------------------------------------------------------------
# [Inputs]
#   - Synth Edgelist     : (Generated in Step 1)
#   - Ground Truth Coms  : (Same as Step 1, used as the reference community)
# [Outputs]
#   - Synth Cluster Stats: data/synthetic_networks/stats/<generator>/<clustering_id>/<network_id>/<run_id>/cluster/
#   - Synth Network Stats: data/synthetic_networks/stats/<generator>/<clustering_id>/<network_id>/<run_id>/network/
#
# ------------------------------------------------------------------------------
# STEP 3: Statistics Comparison
# ------------------------------------------------------------------------------
# [Inputs]
#   - Synth Cluster Stats: (Generated in Step 2)
#   - Synth Network Stats: (Generated in Step 2)
#   - Ref Cluster Stats  : data/reference_clusterings/stats/<clustering_id>/<network_id>/
#   - Emp Network Stats  : data/empirical_networks/stats/<network_id>/
# [Outputs]
#   - Comparison CSV     : data/synthetic_networks/stats/<generator>/<clustering_id>/<network_id>/<run_id>/comparison.csv
# ==============================================================================

GENERATOR=$1
NETWORK_ID=$2
CLUSTERING_ID=$3
RUN_ID=${4:-"0"} # Default to "0" if not provided

if [ -z "$NETWORK_ID" ] || [ -z "$CLUSTERING_ID" ] || [ -z "$GENERATOR" ]; then
    echo "Usage: $0 <generator> <network_id> <clustering_id> [run_id]"
    exit 1
fi

ACCEPTED_GENERATORS=("ec-sbm-v2" "ec-sbm-v2-SDG" "ec-sbm-v1.5")
if [[ ! " ${ACCEPTED_GENERATORS[*]} " =~ " ${GENERATOR} " ]]; then
    echo "Error: Unsupported generator '${GENERATOR}'. Accepted generators are: ${ACCEPTED_GENERATORS[*]}"
    exit 1
fi

# ==========================================
# Path Definitions
# ==========================================
INP_EDGE="data/empirical_networks/netzschleuder/${NETWORK_ID}/${NETWORK_ID}.csv"
INP_COM="data/reference_clusterings/clusterings/${CLUSTERING_ID}/${NETWORK_ID}/com.csv"

# Pre-computed stats directories (Reference & Empirical)
REFERENCE_STATS_DIR="data/reference_clusterings/stats/${CLUSTERING_ID}/${NETWORK_ID}"
EMPIRICAL_NETWORK_STATS_DIR="data/empirical_networks/stats/${NETWORK_ID}"

# Output directories for the synthetic generation (No trailing slashes)
OUT_DIR="data/synthetic_networks/networks/${GENERATOR}/${CLUSTERING_ID}/${NETWORK_ID}/${RUN_ID}"
STATS_DIR="data/synthetic_networks/stats/${GENERATOR}/${CLUSTERING_ID}/${NETWORK_ID}/${RUN_ID}"

# Split output paths for stats
SYNTH_CLUSTER_STATS_DIR="${STATS_DIR}/cluster"
SYNTH_NETWORK_STATS_DIR="${STATS_DIR}/network"

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
            --outdir "${cluster_out_dir}"; } 2> "${cluster_out_dir}/cluster_time.log"
    else
        echo "Cluster stats already done."
    fi

    # 2. Compute Network-Only Stats
    if [ ! -f "${network_out_dir}/done" ]; then
        mkdir -p "${network_out_dir}"
        { /usr/bin/time -v python network_evaluation/network_stats/compute_network_stats.py \
            --network "${edge_file}" \
            --outdir "${network_out_dir}"; } 1> "${network_out_dir}/out.log" 2> "${network_out_dir}/network_time.log"
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

# ==========================================
# 1. Run Generation Pipeline
# ==========================================
if [ ! -f "${OUT_DIR}/done" ]; then
    echo "Generating synthetic network..."

    if [[ "${GENERATOR}" == ec-sbm-v2* ]]; then
        # Generator Configuration Parsing
        if [[ "${GENERATOR}" == "ec-sbm-v2" ]]; then
            OUTLIER_MODE="combined"
            EDGE_CORRECTION="rewire"
            MATCH_ALGO="true_greedy"
        elif [[ "${GENERATOR}" == "ec-sbm-v2-SDG" ]]; then
            OUTLIER_MODE="singleton"
            EDGE_CORRECTION="drop"
            MATCH_ALGO="greedy"
        else
            OUTLIER_MODE="combined"
            EDGE_CORRECTION="rewire"
            MATCH_ALGO="true_greedy"
        fi

        mkdir -p "${OUT_DIR}"
        ./src/generate/ec-sbm/v2/pipeline.sh \
            --input-edgelist "${INP_EDGE}" \
            --input-clustering "${INP_COM}" \
            --output-dir "${OUT_DIR}" \
            --outlier-mode "${OUTLIER_MODE}" \
            --edge-correction "${EDGE_CORRECTION}" \
            --algorithm "${MATCH_ALGO}"
    elif [[ "${GENERATOR}" == "ec-sbm-v1.5" ]]; then
        mkdir -p "${OUT_DIR}"
        ./src/generate/ec-sbm/v1.5/pipeline.sh \
            --input-edgelist "${INP_EDGE}" \
            --input-clustering "${INP_COM}" \
            --output-dir "${OUT_DIR}"
    else
        echo "Error: Unsupported generator."
        exit 1
    fi

    if [ -f "${OUT_DIR}/edge.csv" ]; then
        touch "${OUT_DIR}/done"
    fi
else
    echo "Generation already done."
fi

if [ ! -f "${OUT_DIR}/edge.csv" ]; then
    echo "CRITICAL: Generation failed or timed out."
    exit 1
fi

# ==========================================
# 2. Run Statistics
# ==========================================
# Run stats using the newly generated network against the reference clustering
run_stats "${OUT_DIR}/edge.csv" "${INP_COM}" "${SYNTH_CLUSTER_STATS_DIR}" "${SYNTH_NETWORK_STATS_DIR}"

# ==========================================
# 3. Compare Statistics
# ==========================================
if [ ! -f "${STATS_DIR}/done" ]; then
    if [ -d "${SYNTH_CLUSTER_STATS_DIR}" ] && [ -d "${REFERENCE_STATS_DIR}" ] && \
       [ -d "${SYNTH_NETWORK_STATS_DIR}" ] && [ -d "${EMPIRICAL_NETWORK_STATS_DIR}" ]; then
        
        echo "Comparing stats..."
        mkdir -p "${STATS_DIR}"
        { /usr/bin/time -v python network_evaluation/compare/compare_pair.py \
            --cluster-1-folder "${SYNTH_CLUSTER_STATS_DIR}" \
            --cluster-2-folder "${REFERENCE_STATS_DIR}" \
            --network-1-folder "${SYNTH_NETWORK_STATS_DIR}" \
            --network-2-folder "${EMPIRICAL_NETWORK_STATS_DIR}" \
            --output-file "${STATS_DIR}/comparison.csv" \
            --is-compare-sequence; } 1> "${STATS_DIR}/out.log" 2> "${STATS_DIR}/error.log"
        
        if [ -f "${STATS_DIR}/comparison.csv" ]; then
            touch "${STATS_DIR}/done"
        fi
    else
        echo "Warning: Skipping comparison. One or more stat directories do not exist."
        echo "  - Synth Cluster Stats: ${SYNTH_CLUSTER_STATS_DIR}"
        echo "  - Synth Network Stats: ${SYNTH_NETWORK_STATS_DIR}"
        echo "  - Ref Cluster Stats:   ${REFERENCE_STATS_DIR}"
        echo "  - Ref Network Stats:   ${EMPIRICAL_NETWORK_STATS_DIR}"
    fi
else
    echo "Statistics comparison already done."
fi

if [ ! -f "${STATS_DIR}/comparison.csv" ]; then
    echo "CRITICAL: Comparison failed or timed out."
    exit 1
fi

echo "Process completed for ${GENERATOR} on ${NETWORK_ID} (Clustering: ${CLUSTERING_ID}, Run: ${RUN_ID})"
echo "[gen] ${GENERATOR} ${NETWORK_ID} ${CLUSTERING_ID} ${RUN_ID}" >> complete.log