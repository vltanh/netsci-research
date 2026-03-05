#!/bin/bash

NETWORK_ID=$1

if [ -z "$NETWORK_ID" ]; then
    echo "Usage: $0 <network_id>"
    exit 1
fi

# Paths
INP_EDGE="data/empirical_networks/netzschleuder/${NETWORK_ID}/${NETWORK_ID}.csv"
OUT_DIR="data/empirical_networks/stats/${NETWORK_ID}"

if [ ! -f "${INP_EDGE}" ]; then
    echo "Error: Empirical network edgelist not found at ${INP_EDGE}"
    exit 1
fi

echo "============================"
echo "Computing Empirical Network Stats for: ${NETWORK_ID}"
echo "============================"

mkdir -p "${OUT_DIR}"

# Run Network-Only Statistics
if [ ! -f "${OUT_DIR}/done" ]; then
    { /usr/bin/time -v python network_evaluation/network_stats/compute_network_stats.py \
        --network "${INP_EDGE}" \
        --outdir "${OUT_DIR}"; } 2> ${OUT_DIR}/error.log
else
    echo "Network stats already computed for ${NETWORK_ID}, skipping..."
fi

echo "Empirical stats saved to: ${OUT_DIR}"