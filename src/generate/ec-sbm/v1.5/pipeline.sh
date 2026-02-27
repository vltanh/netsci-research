#!/bin/bash

input_edgelist=$1
input_clustering=$2
output_dir=$3

if [ ! -f "${input_edgelist}" ] || [ ! -f "${input_clustering}" ]; then
    echo "The input network or clustering file does not exist."
    exit 1
fi

# ==========================================
# Helper Function: Check for valid output
# ==========================================
# Checks if file exists and has a size greater than 0 bytes.
check_valid_output() {
    local file_path=$1
    local stage_name=$2

    if [ ! -f "${file_path}" ]; then
        echo "Error [${stage_name}]: Output file ${file_path} was not created."
        exit 1
    fi

    if [ ! -s "${file_path}" ]; then
        echo "Error [${stage_name}]: Output file ${file_path} is completely empty (0 bytes)."
        exit 1
    fi
    
    local line_count=$(wc -l < "${file_path}")
    echo "Success [${stage_name}]: Generated ${file_path} with $((line_count - 1)) edge records."
}

# ==========================================
# STAGE 1: Clustered Generation
# ==========================================
echo "=== Starting Stage 1: Core Clustered Generation ==="
STG1_CLEAN_DIR="${output_dir}/clustered/clean"
STG1_SETUP_DIR="${output_dir}/clustered/setup"
STG1_DIR="${output_dir}/clustered"
mkdir -p "${STG1_CLEAN_DIR}" "${STG1_SETUP_DIR}" "${STG1_DIR}"

# 1a. Clean Outliers
{ /usr/bin/time -v python clean_outlier.py \
    --edgelist "${input_edgelist}" \
    --clustering "${input_clustering}" \
    --output-folder "${STG1_CLEAN_DIR}"; } 2> "${STG1_CLEAN_DIR}/time_and_err.log"

# 1b. Setup Profiling
{ /usr/bin/time -v python setup.py \
    --edgelist "${STG1_CLEAN_DIR}/edge.csv" \
    --clustering "${STG1_CLEAN_DIR}/com.csv" \
    --output-folder "${STG1_SETUP_DIR}" \
    --generator ecsbm; } 2> "${STG1_SETUP_DIR}/time_and_err.log"

# 1c. Generate Clustered
{ /usr/bin/time -v python gen_clustered.py \
    --node-id "${STG1_SETUP_DIR}/node_id.csv" \
    --cluster-id "${STG1_SETUP_DIR}/cluster_id.csv" \
    --assignment "${STG1_SETUP_DIR}/assignment.csv" \
    --degree "${STG1_SETUP_DIR}/degree.csv" \
    --mincut "${STG1_SETUP_DIR}/mincut.csv" \
    --edge-counts "${STG1_SETUP_DIR}/edge_counts.csv" \
    --output-folder "${STG1_DIR}"; } 2> "${STG1_DIR}/time_and_err.log"

check_valid_output "${STG1_DIR}/edge.csv" "Stage 1"


# ==========================================
# STAGE 2: Outlier Generation & First Merge
# ==========================================
echo "=== Starting Stage 2: Outlier Generation & Merge ==="
STG2_OUTLIER_DIR="${output_dir}/outlier/edges"
STG2_DIR="${output_dir}/outlier"
mkdir -p "${STG2_OUTLIER_DIR}" "${STG2_DIR}"

# 2a. Generate Outliers
{ /usr/bin/time -v python gen_outlier.py \
    --edgelist "${input_edgelist}" \
    --clustering "${input_clustering}" \
    --output-folder "${STG2_OUTLIER_DIR}"; } 2> "${STG2_OUTLIER_DIR}/time_and_err.log"

check_valid_output "${STG2_OUTLIER_DIR}/edge_outlier.csv" "Stage 2a (Outlier Gen)"

# 2b. Combine Clustered + Outliers
{ /usr/bin/time -v python combine_edgelists.py \
    --edgelist-1 "${STG1_DIR}/edge.csv" \
    --name-1 "clustered" \
    --edgelist-2 "${STG2_OUTLIER_DIR}/edge_outlier.csv" \
    --name-2 "outlier" \
    --output-folder "${STG2_DIR}" \
    --output-filename "edge.csv"; } 2> "${STG2_DIR}/time_and_err.log"

check_valid_output "${STG2_DIR}/edge.csv" "Stage 2b (First Combine)"

# # 2c. Cleanup Intermediate Files
# echo "Cleaning up Stage 1 and 2 intermediate edgelists..."
# rm -f "${STG1_DIR}/edge.csv" "${STG2_OUTLIER_DIR}/edge_outlier.csv"


# ==========================================
# STAGE 3: Degree Matching & Final Merge
# ==========================================
echo "=== Starting Stage 3: Degree Matching & Final Merge ==="
STG3_MATCH_DIR="${output_dir}/match_degree"
STG3_DIR="${output_dir}"
mkdir -p "${STG3_MATCH_DIR}"

# 3a. Match Degrees
{ /usr/bin/time -v python match_degree.py \
    --input-edgelist "${STG2_DIR}/edge.csv" \
    --ref-edgelist "${input_edgelist}" \
    --ref-clustering "${input_clustering}" \
    --output-folder "${STG3_MATCH_DIR}"; } 2> "${STG3_MATCH_DIR}/time_and_err.log"

check_valid_output "${STG3_MATCH_DIR}/degree_matching_edge.csv" "Stage 3a (Degree Match)"

# 3b. Final Combination
{ /usr/bin/time -v python combine_edgelists.py \
    --edgelist-1 "${STG2_DIR}/edge.csv" \
    --json-1 "${STG2_DIR}/sources.json" \
    --edgelist-2 "${STG3_MATCH_DIR}/degree_matching_edge.csv" \
    --name-2 "match_degree" \
    --output-folder "${STG3_DIR}" \
    --output-filename "edge.csv"; } 2> "${STG3_DIR}/time_and_err.log"

check_valid_output "${STG3_DIR}/edge.csv" "Stage 3b (Final Combine)"

# # 3c. Cleanup Intermediate Files
# echo "Cleaning up Stage 3 intermediate edgelists..."
# rm -f "${STG2_DIR}/edge.csv" "${STG3_MATCH_DIR}/degree_matching_edge.csv"

echo "=== Pipeline execution completed successfully! ==="
echo "Final Network: ${STG3_DIR}/edge.csv"
echo "Provenance JSON: ${STG3_DIR}/sources.json"