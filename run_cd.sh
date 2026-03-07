#!/bin/bash

# ==========================================
# Community Detection Evaluation Pipeline
# ==========================================
#
# Pipeline Stages & Scripts Used
# ------------------------------------------------------
# 1. Base Clustering: Computes the initial community structure.
#    - Leiden:  python src/comm-det/leiden/run_leiden.py
#    - Infomap: python src/comm-det/infomap/run_infomap.py
#    - IKC:     python src/comm-det/ikc/run_ikc.py
#    - SBM:     python src/comm-det/sbm/run_sbm.py
#    - SBM Best Model Selection: python src/comm-det/sbm/choose_best_sbm.py
# 
# 2. Statistics Computation: Calculates network metrics for the estimated clustering.
#    - Script: python network_evaluation/network_stats/compute_cluster_stats.py
#
# 3. Accuracy Evaluation (Synthetic Only): Compares estimated clustering against ground truth.
#    - Script: python network_evaluation/commdet_acc/compute_cd_accuracy.py
#
# 4. Post-Processing: Refines the base clustering via Constrained Clustering variants (CC, WCC, CM).
#    - Binary: ./constrained-clustering/constrained_clustering
#
# 5. Post-Processing Evaluation: Re-runs the Statistics and Accuracy evaluations on the refined outputs.
#    - Uses the same scripts from Stages 2 & 3.
#
# ==========================================
# Expected Directory Structure (Inputs & Outputs)
# ==========================================
#
# CASE 1: Real Networks (Default or dataset_type="real")
# ------------------------------------------------------
# [Input]
# data/empirical_networks/netzschleuder/<network_id>/<network_id>.csv
#
# [Output]
# COMMDET_BASE = data/reference_clusterings/
# ├── clusterings/<algo>[+post_processing]/<network_id>/com.csv
# └── stats/<algo>[+post_processing]/<network_id>/done
#
#
# CASE 2: Synthetic Networks (<generator> <gt_clustering> [run_id=0])
# ------------------------------------------------------
# [Input]
# data/synthetic_networks/networks/<generator>/<gt_clustering>/<network_id>/<run_id>/edge.csv
# data/reference_clusterings/clusterings/<gt_clustering>/<network_id>/com.csv (Ground Truth)
#
# [Output]
# COMMDET_BASE = data/estimated_clusterings/<generator>/<gt_clustering>/
# ├── clusterings/<algo>[+post_processing]/<network_id>/<run_id>/com.csv
# ├── stats/<algo>[+post_processing]/<network_id>/<run_id>/done
# └── acc/<algo>[+post_processing]/<network_id>/<run_id>/done
#
# ==========================================

# Constants
TIMEOUT="3d"

# Usage for real networks:      ./run_cd_real.sh <algorithm> <network_id> [real]
# Usage for synthetic networks: ./run_cd_real.sh <algorithm> <network_id> <generator> <gt_clustering> [run_id]
algo=$1
network_id=$2

# Flags
IS_RUN_CC=1
IS_RUN_WCC=0
IS_RUN_CM=1

case ${algo} in
    ikc*) IS_RUN_CC=0; IS_RUN_WCC=0; IS_RUN_CM=0 ;;
    leiden*) IS_RUN_CC=0; IS_RUN_WCC=0 ;;
    sbm*) IS_RUN_CM=0 ;;
    infomap) IS_RUN_WCC=0; IS_RUN_CM=0 ;;
esac

# ==========================================
# Input/Output Path Routing (Real vs Synthetic)
# ==========================================
if [ "$#" -le 2 ] || [ "$3" == "real" ]; then
    is_real=1
    dataset_type="real"
    inp_edge="data/empirical_networks/netzschleuder/${network_id}/${network_id}.csv"
    COMMDET_BASE="data/reference_clusterings"
    out_subpath="${network_id}"
    gt_file="" # Not applicable for real networks
else
    is_real=0
    generator=$3
    gt_clustering=$4
    run_id=${5:-0} # Default to 0 if not provided
    dataset_type="${generator}/${gt_clustering} (run: ${run_id})"

    if [ -z "${generator}" ] || [ -z "${gt_clustering}" ]; then
        echo "Error: For synthetic networks, you must provide generator and gt-clustering."
        echo "Usage: $0 <algo> <network_id> <generator> <gt_clustering> [run_id]"
        exit 1
    fi

    inp_edge="data/synthetic_networks/networks/${generator}/${gt_clustering}/${network_id}/${run_id}/edge.csv"
    COMMDET_BASE="data/estimated_clusterings/${generator}/${gt_clustering}"
    out_subpath="${network_id}/${run_id}"
    gt_file="data/reference_clusterings/clusterings/${gt_clustering}/${network_id}/com.csv"
fi

if [ ! -f "${inp_edge}" ]; then
    echo "Input file ${inp_edge} does not exist. Skipping."
    exit 1
fi

base_root_clusterings="${COMMDET_BASE}/clusterings"
base_root_stats="${COMMDET_BASE}/stats"
base_root_acc="${COMMDET_BASE}/acc"

# ==========================================
# Functions: Stats and Accuracy
# ==========================================
run_stats() {
    local edge_file=$1
    local com_file=$2
    local stats_dir=$3

    echo "Computing stats..."
    if [ ! -f "${stats_dir}/done" ]; then
        mkdir -p "${stats_dir}"
        { /usr/bin/time -v python network_evaluation/network_stats/compute_cluster_stats.py \
            --network "${edge_file}" \
            --community "${com_file}" \
            --outdir "${stats_dir}"; } 2> "${stats_dir}/error.log"
    else
        echo "Stats already done."
    fi
}

run_accuracy() {
    local edge_file=$1
    local gt_f=$2
    local est_file=$3
    local acc_d=$4

    echo "Computing accuracy..."
    if [ ! -f "${acc_d}/done" ]; then
        mkdir -p "${acc_d}"
        { /usr/bin/time -v python network_evaluation/commdet_acc/compute_cd_accuracy.py \
            --input-network "${edge_file}" \
            --gt-clustering "${gt_f}" \
            --est-clustering "${est_file}" \
            --output-prefix "${acc_d}/result"; } 2> "${acc_d}/error.log"
    else
        echo "Accuracy already done."
    fi
}

echo "============================"
echo "${algo} ${network_id} | Dataset: ${dataset_type}"

leiden_model=""
leiden_res=""
ikc_k=""
sbm_model=""

if [[ ${algo} == leiden* ]]; then
    leiden_model=$(echo ${algo} | cut -d'-' -f2)
    if [[ ${leiden_model} == cpm ]]; then
        leiden_res=$(echo ${algo} | cut -d'-' -f3)
    fi
elif [[ ${algo} == ikc* ]]; then
    ikc_k=$(echo ${algo} | cut -d'-' -f2)
elif [[ ${algo} == sbm* ]]; then
    sbm_model=$(echo ${algo} | cut -d'-' -f2-)
fi

# ==========================================
# 1. Run Base Clustering
# ==========================================
suffix="${algo}"
out_dir="${base_root_clusterings}/${suffix}/${out_subpath}/"
stats_dir="${base_root_stats}/${suffix}/${out_subpath}/"
acc_dir="${base_root_acc}/${suffix}/${out_subpath}/"

base_com="${out_dir}/com.csv"
base_dens="${out_dir}/density.csv"
base_done="${out_dir}/done"

echo "Running clustering..."
if [ ! -f "${base_done}" ]; then
    if [[ ${algo} == leiden* ]]; then
        if [[ ${leiden_model} == cpm ]]; then
            mkdir -p "${out_dir}"
            { timeout "${TIMEOUT}" /usr/bin/time -v python src/comm-det/leiden/run_leiden.py \
                --edgelist "${inp_edge}" \
                --output-directory "${out_dir}" \
                --model cpm \
                --resolution "${leiden_res}"; } 2> "${out_dir}/error.log"
        elif [[ ${leiden_model} == mod ]]; then
            mkdir -p "${out_dir}"
            { timeout "${TIMEOUT}" /usr/bin/time -v python src/comm-det/leiden/run_leiden.py \
                --edgelist "${inp_edge}" \
                --output-directory "${out_dir}" \
                --model mod; } 2> "${out_dir}/error.log"
        else
            echo "Unknown leiden_model: ${leiden_model}"; exit 1
        fi
    elif [[ ${algo} == infomap ]]; then
        mkdir -p "${out_dir}"
        { timeout "${TIMEOUT}" /usr/bin/time -v python src/comm-det/infomap/run_infomap.py \
            --edgelist "${inp_edge}" \
            --output-directory "${out_dir}"; } 1> "${out_dir}/output.log" 2> "${out_dir}/error.log"
    elif [[ ${algo} == ikc* ]]; then
        mkdir -p "${out_dir}"
        { timeout "${TIMEOUT}" /usr/bin/time -v python src/comm-det/ikc/run_ikc.py \
            --edgelist "${inp_edge}" \
            --output-directory "${out_dir}" \
            --kvalue "${ikc_k}"; } 1> "${out_dir}/output.log" 2> "${out_dir}/error.log"
    elif [[ ${algo} == sbm* ]]; then
        if [[ ${sbm_model} =~ ^(flat-dc|flat-ndc|flat-pp|nested-dc|nested-ndc)$ ]]; then
            echo "Running ${sbm_model}..."
            mkdir -p "${out_dir}"
            { timeout "${TIMEOUT}" /usr/bin/time -v python src/comm-det/sbm/run_sbm.py \
                --edgelist "${inp_edge}" \
                --output-directory "${out_dir}" \
                --method "${sbm_model}"; } 2> "${out_dir}/error.log"
        elif [[ ${sbm_model} == "flat-best" ]]; then
            echo "Running flat-best (selecting best of dc, ndc, pp)..."
            sbm_flat_dc_root="${base_root_clusterings}/sbm-flat-dc/${out_subpath}"
            sbm_flat_ndc_root="${base_root_clusterings}/sbm-flat-ndc/${out_subpath}"
            sbm_flat_pp_root="${base_root_clusterings}/sbm-flat-pp/${out_subpath}"
            
            mkdir -p "${out_dir}"
            { timeout "${TIMEOUT}" /usr/bin/time -v python src/comm-det/sbm/choose_best_sbm.py \
                --entropy_files "${sbm_flat_dc_root}/entropy.txt" "${sbm_flat_ndc_root}/entropy.txt" "${sbm_flat_pp_root}/entropy.txt" \
                --com_files "${sbm_flat_dc_root}/com.csv" "${sbm_flat_ndc_root}/com.csv" "${sbm_flat_pp_root}/com.csv" \
                --out_dir "${out_dir}"; } 1> "${out_dir}/out.log" 2> "${out_dir}/error.log"

            if [ -f "${out_dir}/best_model.txt" ]; then
                best_model=$(cat "${out_dir}/best_model.txt")
                echo "Best SBM model selected: ${best_model}"
            else
                echo "Error: Best model selection failed. best_model.txt not found."
            fi
        elif [[ ${sbm_model} == "nested-best" ]]; then
            echo "Running nested-best (selecting best of dc, ndc)..."
            sbm_nested_dc_root="${base_root_clusterings}/sbm-nested-dc/${out_subpath}"
            sbm_nested_ndc_root="${base_root_clusterings}/sbm-nested-ndc/${out_subpath}"
            
            mkdir -p "${out_dir}"
            { timeout "${TIMEOUT}" /usr/bin/time -v python src/comm-det/sbm/choose_best_sbm.py \
                --entropy_files "${sbm_nested_dc_root}/entropy.txt" "${sbm_nested_ndc_root}/entropy.txt" \
                --com_files "${sbm_nested_dc_root}/com.csv" "${sbm_nested_ndc_root}/com.csv" \
                --out_dir "${out_dir}"; } 1> "${out_dir}/out.log" 2> "${out_dir}/error.log"

            if [ -f "${out_dir}/best_model.txt" ]; then
                best_model=$(cat "${out_dir}/best_model.txt")
                echo "Best SBM model selected: ${best_model}"
            else
                echo "Error: Best model selection failed. best_model.txt not found."
            fi
        else
            echo "Unknown sbm_model: ${sbm_model}"; exit 1
        fi
    else
        echo "Unknown method: ${algo}"; exit 1
    fi

    if [ -f "${base_com}" ]; then 
        touch "${base_done}"
    fi
fi

if [ ! -f "${base_com}" ]; then
    echo "CRITICAL: Base clustering failed or timed out."
    exit 1
fi

# ==========================================
# Symlink Shortcut for "Best" Meta-Models
# ==========================================
if [[ ${sbm_model} == "flat-best" || ${sbm_model} == "nested-best" ]]; then
    best_model_file="${out_dir}/best_model.txt"
    if [ ! -f "${best_model_file}" ]; then
        echo "Error: ${best_model_file} not found. Could not link downstream tasks."
        exit 1
    fi
    
    best_algo=$(cat "${best_model_file}")

    if [ ! -L "${base_com}" ] || [ ! -e "${base_com}" ]; then
        echo "CRITICAL: Symlink ${base_com} does not exist or is broken."
        exit 1
    fi

    echo "Best model successfully read as: ${best_algo}. Symlinking downstream folders..."

    # 1. Symlink base stats folder
    target_stats="${PWD}/${base_root_stats}/${best_algo}/${out_subpath}"
    if [ -e "${target_stats}" ]; then
        mkdir -p "$(dirname "${stats_dir}")"
        ln -sfn "${target_stats}" "${stats_dir}"
    else
        echo "Warning: Base stats folder ${target_stats} not found. Skipping symlink."
    fi

    # 1b. Symlink base acc folder (for synthetic)
    if [ "${is_real}" -eq 0 ]; then
        target_acc="${PWD}/${base_root_acc}/${best_algo}/${out_subpath}"
        if [ -e "${target_acc}" ]; then
            mkdir -p "$(dirname "${acc_dir}")"
            ln -sfn "${target_acc}" "${acc_dir}"
        fi
    fi

    # 2. Symlink post-processing & their respective stats/acc folders
    for pp in cc wcc cm; do
        if [ "${pp}" == "cc" ] && [ "${IS_RUN_CC}" -ne 1 ]; then continue; fi
        if [ "${pp}" == "wcc" ] && [ "${IS_RUN_WCC}" -ne 1 ]; then continue; fi
        if [ "${pp}" == "cm" ] && [ "${IS_RUN_CM}" -ne 1 ]; then continue; fi

        target_pp_clust="${PWD}/${base_root_clusterings}/${best_algo}+${pp}/${out_subpath}"
        target_pp_stats="${PWD}/${base_root_stats}/${best_algo}+${pp}/${out_subpath}"
        
        # Check and link post-processing clustering
        if [ -e "${target_pp_clust}" ]; then
            mkdir -p "$(dirname "${base_root_clusterings}/${algo}+${pp}/${out_subpath}")"
            ln -sfn "${target_pp_clust}" "${base_root_clusterings}/${algo}+${pp}/${out_subpath}"
        else
            echo "Warning: Post-processing cluster folder ${target_pp_clust} not found. Skipping symlink."
        fi

        # Check and link post-processing stats
        if [ -e "${target_pp_stats}" ]; then
            mkdir -p "$(dirname "${base_root_stats}/${algo}+${pp}/${out_subpath}")"
            ln -sfn "${target_pp_stats}" "${base_root_stats}/${algo}+${pp}/${out_subpath}"
        else
            echo "Warning: Post-processing stats folder ${target_pp_stats} not found. Skipping symlink."
        fi
        
        # Check and link post-processing acc (for synthetic)
        if [ "${is_real}" -eq 0 ]; then
            target_pp_acc="${PWD}/${base_root_acc}/${best_algo}+${pp}/${out_subpath}"
            if [ -e "${target_pp_acc}" ]; then
                mkdir -p "$(dirname "${base_root_acc}/${algo}+${pp}/${out_subpath}")"
                ln -sfn "${target_pp_acc}" "${base_root_acc}/${algo}+${pp}/${out_subpath}"
            else
                echo "Warning: Post-processing acc folder ${target_pp_acc} not found. Skipping symlink."
            fi
        fi
    done

    echo "[cd-done] ${algo} ${network_id} ${dataset_type}" >> complete.log
    exit 0
fi

run_stats "${inp_edge}" "${base_com}" "${stats_dir}"
if [ "${is_real}" -eq 0 ]; then
    run_accuracy "${inp_edge}" "${gt_file}" "${base_com}" "${acc_dir}"
fi

# ==========================================
# 2. Run CC
# ==========================================
if [ "${IS_RUN_CC}" -eq 1 ]; then
    suffix="${algo}+cc"
    out_cc_dir="${base_root_clusterings}/${suffix}/${out_subpath}/"
    stats_cc_dir="${base_root_stats}/${suffix}/${out_subpath}/"
    acc_cc_dir="${base_root_acc}/${suffix}/${out_subpath}/"
    cc_com="${out_cc_dir}/com.csv"
    cc_done="${out_cc_dir}/done"
    
    if [ ! -f "${cc_done}" ]; then
        echo "Running CC..."
        mkdir -p "${out_cc_dir}"
        { timeout "${TIMEOUT}" /usr/bin/time -v ./constrained-clustering/constrained_clustering \
            MincutOnly \
            --edgelist "${inp_edge}" \
            --existing-clustering "${base_com}" \
            --num-processors 1 \
            --output-file "${cc_com}" \
            --log-file "${out_cc_dir}/cc.log" \
            --log-level 1 \
            --connectedness-criterion 0; } 2> "${out_cc_dir}/error.log"
        [ -f "${cc_com}" ] && touch "${cc_done}"
    else
        echo "CC already done."
    fi
    
    if [ -f "${cc_com}" ]; then
        run_stats "${inp_edge}" "${cc_com}" "${stats_cc_dir}"
        if [ "${is_real}" -eq 0 ]; then
            run_accuracy "${inp_edge}" "${gt_file}" "${cc_com}" "${acc_cc_dir}"
        fi
    fi
fi

# ==========================================
# 3. Run WCC 
# ==========================================
if [ "${IS_RUN_WCC}" -eq 1 ]; then
    suffix="${algo}+wcc"
    out_wcc_dir="${base_root_clusterings}/${suffix}/${out_subpath}/"
    stats_wcc_dir="${base_root_stats}/${suffix}/${out_subpath}/"
    acc_wcc_dir="${base_root_acc}/${suffix}/${out_subpath}/"
    wcc_com="${out_wcc_dir}/com.csv"
    wcc_done="${out_wcc_dir}/done"
    
    if [ ! -f "${wcc_done}" ]; then
        echo "Running WCC..."
        mkdir -p "${out_wcc_dir}"
        { timeout "${TIMEOUT}" /usr/bin/time -v ./constrained-clustering/constrained_clustering \
            MincutOnly \
            --connectedness-criterion "1log_10(n)" \
            --edgelist "${inp_edge}" \
            --existing-clustering "${base_com}" \
            --num-processors 1 \
            --output-file "${wcc_com}" \
            --log-file "${out_wcc_dir}/wcc.log" \
            --log-level 1; } 2> "${out_wcc_dir}/error.log"
        [ -f "${wcc_com}" ] && touch "${wcc_done}"
    else
        echo "WCC already done."
    fi

    if [ -f "${wcc_com}" ]; then
        run_stats "${inp_edge}" "${wcc_com}" "${stats_wcc_dir}"
        if [ "${is_real}" -eq 0 ]; then
            run_accuracy "${inp_edge}" "${gt_file}" "${wcc_com}" "${acc_wcc_dir}"
        fi
    fi
fi

# ==========================================
# 4. Run CM
# ==========================================
if [ "${IS_RUN_CM}" -eq 1 ]; then
    suffix="${algo}+cm"
    out_cm_dir="${base_root_clusterings}/${suffix}/${out_subpath}/"
    stats_cm_dir="${base_root_stats}/${suffix}/${out_subpath}/"
    acc_cm_dir="${base_root_acc}/${suffix}/${out_subpath}/"
    cm_com="${out_cm_dir}/com.csv"
    cm_done="${out_cm_dir}/done"
    
    if [ ! -f "${cm_done}" ]; then
        echo "Running CM..."
        if [[ ${algo} == leiden* ]]; then
            if [[ ${leiden_model} == cpm ]]; then
                mkdir -p "${out_cm_dir}"
                { timeout "${TIMEOUT}" /usr/bin/time -v ./constrained-clustering/constrained_clustering \
                    CM \
                    --mincut-type "cactus" \
                    --connectedness-criterion "0.2n^0.5" \
                    --edgelist "${inp_edge}" \
                    --existing-clustering "${base_com}" \
                    --algorithm "leiden-cpm" \
                    --clustering-parameter "${leiden_res}" \
                    --num-processors 1 \
                    --output-file "${cm_com}" \
                    --history-file "${out_cm_dir}/history.log" \
                    --log-file "${out_cm_dir}/cm.log" \
                    --log-level 1; } 2> "${out_cm_dir}/error.log"
            elif [[ ${leiden_model} == mod ]]; then
                mkdir -p "${out_cm_dir}"
                { timeout "${TIMEOUT}" /usr/bin/time -v ./constrained-clustering/constrained_clustering \
                    CM \
                    --mincut-type "cactus" \
                    --connectedness-criterion "0.2n^0.5" \
                    --edgelist "${inp_edge}" \
                    --existing-clustering "${base_com}" \
                    --algorithm "leiden-mod" \
                    --num-processors 1 \
                    --output-file "${cm_com}" \
                    --history-file "${out_cm_dir}/history.log" \
                    --log-file "${out_cm_dir}/cm.log" \
                    --log-level 1; } 2> "${out_cm_dir}/error.log"
            fi
        else
            echo "CM not implemented for ${algo}"
        fi
        [ -f "${cm_com}" ] && touch "${cm_done}"
    else
        echo "CM already done."
    fi

    if [ -f "${cm_com}" ]; then
        run_stats "${inp_edge}" "${cm_com}" "${stats_cm_dir}"
        if [ "${is_real}" -eq 0 ]; then
            run_accuracy "${inp_edge}" "${gt_file}" "${cm_com}" "${acc_cm_dir}"
        fi
    fi
fi

echo "[cd-done] ${algo} ${network_id} ${dataset_type}" >> complete.log