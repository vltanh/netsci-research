#!/bin/bash
#
# Regenerate examples/ trees in all three repos:
#   1. main repo (this directory)         — flat, mirrors data/ layout
#   2. network-generation/ submodule      — examples/{input,output}/ split
#   3. community-detection/ submodule     — examples/{input,output}/ split
#
# Reference clustering, generators, and CD algos are configured in the CONFIG
# block below (network name, REFERENCE_CLUSTERING_*, *_GENERATORS, *_CD_ALGOS).
# Reference clustering is computed once at main, then its com.csv is copied
# (cp -L; symlinks resolved) to netgen/comdet inputs.
#
# Layout per tree (<NET> = NETWORK_NAME, <CLID> = REFERENCE_CLUSTERING_ID):
#   MAIN (mirrors data/):
#     empirical_networks/{networks,stats}/<NET>/...
#     reference_clusterings/{clusterings,stats}/<CLID>/<NET>/...
#         (full chain: bases + meta + post-procs as the algo requires)
#     synthetic_networks/{networks,stats}/<gen>/<CLID>/<NET>/0/...
#         (full leaf incl .state, run.log)
#     estimated_clusterings/<gen>/<CLID>/{clusterings,acc}/...
#         (NO stats subtree)
#
#   NETGEN (input/output split):
#     input/empirical_networks/{networks,stats}/<NET>/...
#     input/reference_clusterings/{clusterings,stats}/<CLID>/<NET>/...
#         (single flat com.csv; symlinks resolved at copy time)
#     output/synthetic_networks/{networks,stats}/<gen>/<CLID>/<NET>/0/...
#         (full leaf incl .state, run.log)
#
#   COMDET (input/output split):
#     input/synthetic_networks/networks/<gen>/<CLID>/<NET>/0/{edge.csv,com.csv}
#         (ONLY edge + com; no stats, no .state, no run.log, no sources.json)
#     output/estimated_clusterings/<gen>/<CLID>/{clusterings,acc}/...
#         (full leaf incl .state, run.log; NO stats subtree)
#
# Idempotent: wipes each examples/ first, then rebuilds.
#
# Usage:
#     bash regenerate_examples.sh
#
# All inputs come from data/ in this repo (must already be populated).

set -euo pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NETGEN_DIR="${ROOT}/network-generation"
COMDET_DIR="${ROOT}/community-detection"

COMPUTE_NET_STATS="${ROOT}/compute_network_stats.sh"
COMPUTE_CLUSTER_STATS="${ROOT}/compute_cluster_stats.sh"
RUN_CD="${COMDET_DIR}/run_cd.sh"
RUN_GENERATOR="${NETGEN_DIR}/run_generator.sh"

# ============================================================================
# CONFIG — edit these to change what gets generated.
# ============================================================================

# Empirical network to seed the pipeline. Edit NETWORK_NAME and add the corresponding
# CSV to data/empirical_networks/networks/<name>/<name>.csv before running.
NETWORK_NAME="dnc"

# Reference clustering used as the planted partition for synthetic generation
# and as ground-truth for CD accuracy in main. Must be runnable end-to-end by
# community-detection/run_cd.sh on the empirical network. Examples:
#   sbm-flat-best+cc         (default)
#   leiden-cpm-0.0001
#   sbm-nested-best+wcc(log)
# The chain of bases/post-procs needed is inferred from the suffix.
REFERENCE_CLUSTERING_ALGO="sbm-flat-best"     # base algo for run_cd.sh
REFERENCE_CLUSTERING_PP="--run-cc"            # post-proc flags ("" for none)
REFERENCE_CLUSTERING_CRIT=""                  # criterion for wcc/cm (e.g. "piecewise"); "" for default
REFERENCE_CLUSTERING_ID="sbm-flat-best+cc"    # final dir name run_cd.sh produces (must match)

# Synthetic generators per repo. Add/remove generator names freely.
NETGEN_GENERATORS=(abcd abcd+o ec-sbm-v1 ec-sbm-v2 ec-sbm-v3 lfr npso sbm)
MAIN_GENERATORS=(ec-sbm-v2 sbm)
COMDET_GENERATORS=(ec-sbm-v2)                 # consumes netgen output

# CD algorithms run on the synthetic networks. Add/remove freely.
MAIN_CD_ALGOS=(leiden-cpm-0.1)
COMDET_CD_ALGOS=(leiden-cpm-0.1 leiden-mod louvain-mod ikc-5 infomap)

# Post-proc flags used for every CD invocation in step 4. run_cd.sh disables
# unsupported combos per-algo automatically. Empty array = no post-procs.
CD_POSTPROC_FLAGS=(--run-cc --run-wcc --run-cm)
CD_POSTPROC_CRITERION="piecewise"             # criterion for wcc/cm; "" for default

# Local aliases (don't edit unless you know what you're doing).
CLID="${REFERENCE_CLUSTERING_ID}"
NETGEN_GENS=("${NETGEN_GENERATORS[@]}")
MAIN_GENS=("${MAIN_GENERATORS[@]}")
COMDET_GENS=("${COMDET_GENERATORS[@]}")

# Resolved paths (post-config). DATA_EDGE depends on NETWORK_NAME.
DATA_EDGE="${ROOT}/data/empirical_networks/networks/${NETWORK_NAME}/${NETWORK_NAME}.csv"

# Build the post-proc flag list for CD invocations in step 4. Includes the
# criterion when CD_POSTPROC_CRITERION is non-empty.
CD_POSTPROC_ARGS=("${CD_POSTPROC_FLAGS[@]}")
if [[ -n "${CD_POSTPROC_CRITERION}" ]]; then
    CD_POSTPROC_ARGS+=(--criterion "${CD_POSTPROC_CRITERION}")
fi

# Build reference-CD post-proc flag list. Same shape as above but for the
# step that produces the reference clustering.
REF_CD_ARGS=()
[[ -n "${REFERENCE_CLUSTERING_PP}" ]] && REF_CD_ARGS+=(${REFERENCE_CLUSTERING_PP})
[[ -n "${REFERENCE_CLUSTERING_CRIT}" ]] && REF_CD_ARGS+=(--criterion "${REFERENCE_CLUSTERING_CRIT}")

# Pre-flight ------------------------------------------------------------------
for f in "${DATA_EDGE}" "${COMPUTE_NET_STATS}" "${COMPUTE_CLUSTER_STATS}" \
         "${RUN_CD}" "${RUN_GENERATOR}"; do
    [[ -e "${f}" ]] || { echo "ERROR: missing dependency: ${f}" >&2; exit 1; }
done

# ============================================================================
# MAIN repo: examples/ mirrors data/ layout (no input/output split).
# ============================================================================
MAIN_EX="${ROOT}/examples"
echo "==================================================================="
echo "MAIN: ${MAIN_EX}"
echo "==================================================================="
rm -rf "${MAIN_EX}"
mkdir -p "${MAIN_EX}/empirical_networks/networks/${NETWORK_NAME}"
MAIN_EDGE="${MAIN_EX}/empirical_networks/networks/${NETWORK_NAME}/${NETWORK_NAME}.csv"
cp "${DATA_EDGE}" "${MAIN_EDGE}"

echo "--- main: empirical network stats ---"
bash "${COMPUTE_NET_STATS}" --input-edgelist "${MAIN_EDGE}" \
    --output-dir "${MAIN_EX}/empirical_networks/stats/${NETWORK_NAME}"

echo "--- main: reference CD (${CLID}, full chain) ---"
bash "${RUN_CD}" --algo "${REFERENCE_CLUSTERING_ALGO}" \
    --input-edgelist "${MAIN_EDGE}" \
    --output-dir "${MAIN_EX}/reference_clusterings" \
    --network "${NETWORK_NAME}" \
    --run-stats --keep-state "${REF_CD_ARGS[@]}"

MAIN_REF_COM="${MAIN_EX}/reference_clusterings/clusterings/${CLID}/${NETWORK_NAME}/com.csv"
MAIN_REF_STATS="${MAIN_EX}/reference_clusterings/stats/${CLID}/${NETWORK_NAME}"
[[ -e "${MAIN_REF_COM}" ]] || { echo "ERROR: main ref com.csv missing at ${MAIN_REF_COM}" >&2; exit 1; }

echo "--- main: synthetic networks (${MAIN_GENS[*]}) ---"
for gen in "${MAIN_GENS[@]}"; do
    bash "${RUN_GENERATOR}" \
        --generator "${gen}" --run-id 0 --seed 1 \
        --input-edgelist "${MAIN_EDGE}" \
        --input-clustering "${MAIN_REF_COM}" \
        --input-network-stats "${MAIN_EX}/empirical_networks/stats/${NETWORK_NAME}" \
        --input-cluster-stats "${MAIN_REF_STATS}" \
        --output-dir "${MAIN_EX}/synthetic_networks" \
        --network "${NETWORK_NAME}" --clustering-id "${CLID}" \
        --run-stats --run-comp --keep-state
done

echo "--- main: CD on synthetic (${MAIN_CD_ALGOS[*]}) ---"
for gen in "${MAIN_GENS[@]}"; do
    SYN_EDGE="${MAIN_EX}/synthetic_networks/networks/${gen}/${CLID}/${NETWORK_NAME}/0/edge.csv"
    [[ -e "${SYN_EDGE}" ]] || { echo "ERROR: ${SYN_EDGE} missing" >&2; exit 1; }
    for algo in "${MAIN_CD_ALGOS[@]}"; do
        bash "${RUN_CD}" --algo "${algo}" \
            --input-edgelist "${SYN_EDGE}" \
            --input-gt-clustering "${MAIN_REF_COM}" \
            --output-dir "${MAIN_EX}/estimated_clusterings" \
            --network "${NETWORK_NAME}" --generator "${gen}" \
            --gt-clustering-id "${CLID}" --run-id 0 \
            --run-acc "${CD_POSTPROC_ARGS[@]}" \
            --keep-state
    done
done

# Drop stats subtree under estimated_clusterings (per spec: no stats here).
find "${MAIN_EX}/estimated_clusterings" -maxdepth 4 -type d -name stats -exec rm -rf {} + 2>/dev/null || true

# ============================================================================
# NETGEN: examples/{input,output}/ split.
# ============================================================================
NG_EX="${NETGEN_DIR}/examples"
NG_IN="${NG_EX}/input"
NG_OUT="${NG_EX}/output"
echo
echo "==================================================================="
echo "NETGEN: ${NG_EX}"
echo "==================================================================="
rm -rf "${NG_EX}"
mkdir -p "${NG_IN}/empirical_networks/networks/${NETWORK_NAME}"
mkdir -p "${NG_IN}/empirical_networks/stats/${NETWORK_NAME}"
mkdir -p "${NG_IN}/reference_clusterings/clusterings/${CLID}/${NETWORK_NAME}"
mkdir -p "${NG_IN}/reference_clusterings/stats/${CLID}/${NETWORK_NAME}"

NG_EDGE="${NG_IN}/empirical_networks/networks/${NETWORK_NAME}/${NETWORK_NAME}.csv"
NG_REF_COM="${NG_IN}/reference_clusterings/clusterings/${CLID}/${NETWORK_NAME}/com.csv"
NG_NET_STATS="${NG_IN}/empirical_networks/stats/${NETWORK_NAME}"
NG_REF_STATS="${NG_IN}/reference_clusterings/stats/${CLID}/${NETWORK_NAME}"

cp "${MAIN_EDGE}" "${NG_EDGE}"
# cp -L resolves any symlink chain (e.g. sbm-flat-best+cc -> winner variant)
# to a single concrete com.csv at the destination.
cp -L "${MAIN_REF_COM}" "${NG_REF_COM}"

echo "--- netgen: empirical network stats ---"
bash "${COMPUTE_NET_STATS}" --input-edgelist "${NG_EDGE}" --output-dir "${NG_NET_STATS}"

echo "--- netgen: reference cluster stats ---"
bash "${COMPUTE_CLUSTER_STATS}" --input-edgelist "${NG_EDGE}" \
    --input-clustering "${NG_REF_COM}" --output-dir "${NG_REF_STATS}"

echo "--- netgen: synthetic networks (${NETGEN_GENS[*]}) ---"
for gen in "${NETGEN_GENS[@]}"; do
    bash "${RUN_GENERATOR}" \
        --generator "${gen}" --run-id 0 --seed 1 \
        --input-edgelist "${NG_EDGE}" \
        --input-clustering "${NG_REF_COM}" \
        --input-network-stats "${NG_NET_STATS}" \
        --input-cluster-stats "${NG_REF_STATS}" \
        --output-dir "${NG_OUT}/synthetic_networks" \
        --network "${NETWORK_NAME}" --clustering-id "${CLID}" \
        --run-stats --run-comp --keep-state
done

# ============================================================================
# COMDET: examples/{input,output}/ split.
# Input is just edge.csv + com.csv from a netgen-produced ec-sbm-v2 leaf.
# ============================================================================
CD_EX="${COMDET_DIR}/examples"
CD_IN="${CD_EX}/input"
CD_OUT="${CD_EX}/output"
echo
echo "==================================================================="
echo "COMDET: ${CD_EX}"
echo "==================================================================="
rm -rf "${CD_EX}"

for gen in "${COMDET_GENS[@]}"; do
    SRC="${NG_OUT}/synthetic_networks/networks/${gen}/${CLID}/${NETWORK_NAME}/0"
    DST="${CD_IN}/synthetic_networks/networks/${gen}/${CLID}/${NETWORK_NAME}/0"
    [[ -e "${SRC}/edge.csv" && -e "${SRC}/com.csv" ]] || \
        { echo "ERROR: netgen output missing ${SRC}/{edge.csv,com.csv}" >&2; exit 1; }
    mkdir -p "${DST}"
    # Strip stats/state/logs — only edge + com travel.
    cp "${SRC}/edge.csv" "${DST}/edge.csv"
    cp "${SRC}/com.csv" "${DST}/com.csv"
done

echo "--- comdet: CD on input synthetic (${COMDET_CD_ALGOS[*]}) ---"
for gen in "${COMDET_GENS[@]}"; do
    SYN_EDGE="${CD_IN}/synthetic_networks/networks/${gen}/${CLID}/${NETWORK_NAME}/0/edge.csv"
    SYN_GT="${CD_IN}/synthetic_networks/networks/${gen}/${CLID}/${NETWORK_NAME}/0/com.csv"
    for algo in "${COMDET_CD_ALGOS[@]}"; do
        bash "${RUN_CD}" --algo "${algo}" \
            --input-edgelist "${SYN_EDGE}" \
            --input-gt-clustering "${SYN_GT}" \
            --output-dir "${CD_OUT}/estimated_clusterings" \
            --network "${NETWORK_NAME}" --generator "${gen}" \
            --gt-clustering-id "${CLID}" --run-id 0 \
            --run-acc "${CD_POSTPROC_ARGS[@]}" \
            --keep-state
    done
done

# Drop stats subtree under estimated_clusterings (per spec: no stats here).
find "${CD_OUT}/estimated_clusterings" -maxdepth 4 -type d -name stats -exec rm -rf {} + 2>/dev/null || true

echo
echo "==================================================================="
echo "DONE"
echo "==================================================================="
echo "  main:   ${MAIN_EX}"
echo "  netgen: ${NG_EX}"
echo "  comdet: ${CD_EX}"
