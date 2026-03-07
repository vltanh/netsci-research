#!/bin/bash

# Constants
TIMEOUT="3d"

# Usage: ./run_cd_real.sh <algorithm> <network_id>
algo=$1
network_id=$2

# Base Output Directory
COMMDET_BASE="data/reference_clusterings/"

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
# Function: Run Statistics
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

echo "============================"
echo "${algo} ${network_id}"

inp_dir="data/empirical_networks/netzschleuder/${network_id}/"
inp_edge="${inp_dir}/${network_id}.csv"

if [ ! -f "${inp_edge}" ]; then
    echo "Input file ${inp_edge} does not exist. Skipping."
    continue
fi

base_root_clusterings="${COMMDET_BASE}/clusterings/"
base_root_stats="${COMMDET_BASE}/stats/"

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
out_dir="${base_root_clusterings}/${suffix}/${network_id}/"
stats_dir="${base_root_stats}/${suffix}/${network_id}/"
acc_dir="${base_root_acc}/${suffix}/${network_id}/"

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
                --model cpm -\
                -resolution "${leiden_res}"; } 2> "${out_dir}/error.log"
        elif [[ ${leiden_model} == mod ]]; then
            mkdir -p "${out_dir}"
            { timeout "${TIMEOUT}" /usr/bin/time -v python src/comm-det/leiden/run_leiden.py \
                --edgelist "${inp_edge}" \
                --output-directory "${out_dir}" \
                --model mod; } 2> "${out_dir}/error.log"
        else
            echo "Unknown leiden_model: ${leiden_model}"; continue
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
            mkdir -p "${out_dir}"
            sbm_flat_dc_root="${base_root_clusterings}/sbm-flat-dc/${network_id}"
            sbm_flat_ndc_root="${base_root_clusterings}/sbm-flat-ndc/${network_id}"
            sbm_flat_pp_root="${base_root_clusterings}/sbm-flat-pp/${network_id}"
            
            if python src/comm-det/sbm/choose_best_sbm.py \
                --entropy_files "${sbm_flat_dc_root}/entropy.txt" "${sbm_flat_ndc_root}/entropy.txt" "${sbm_flat_pp_root}/entropy.txt" \
                --com_files "${sbm_flat_dc_root}/com.csv" "${sbm_flat_ndc_root}/com.csv" "${sbm_flat_pp_root}/com.csv" \
                --out_dir "${out_dir}"; then
                touch "${base_done}"
            else
                echo "CRITICAL: Failed to select best flat model."
                exit 1
            fi
        elif [[ ${sbm_model} == "nested-best" ]]; then
            echo "Running nested-best (selecting best of dc, ndc)..."
            mkdir -p "${out_dir}"
            sbm_nested_dc_root="${base_root_clusterings}/sbm-nested-dc/${network_id}"
            sbm_nested_ndc_root="${base_root_clusterings}/sbm-nested-ndc/${network_id}"
            
            if python src/comm-det/sbm/choose_best_sbm.py \
                --entropy_files "${sbm_nested_dc_root}/entropy.txt" "${sbm_nested_ndc_root}/entropy.txt" \
                --com_files "${sbm_nested_dc_root}/com.csv" "${sbm_nested_ndc_root}/com.csv" \
                --out_dir "${out_dir}"; then
                touch "${base_done}"
            else
                echo "CRITICAL: Failed to select best nested model."
                exit 1
            fi
        else
            echo "Unknown sbm_model: ${sbm_model}"; continue
        fi
    else
        echo "Unknown method: ${algo}"; continue
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

    # 1. Symlink base stats folder instead of recomputing
    target_stats="${PWD}/${base_root_stats}/${best_algo}/${network_id}"
    if [ -e "${target_stats}" ]; then
        mkdir -p "$(dirname "${stats_dir}")"
        ln -sfn "${target_stats}" "${stats_dir}"
    else
        echo "Warning: Base stats folder ${target_stats} not found. Skipping symlink."
    fi

    # 2. Symlink post-processing & their respective stats folders instead of re-running them
    for pp in cc wcc cm; do
        # Skip if the run flag for this post-processing step is not set
        if [ "${pp}" == "cc" ] && [ "${IS_RUN_CC}" -ne 1 ]; then continue; fi
        if [ "${pp}" == "wcc" ] && [ "${IS_RUN_WCC}" -ne 1 ]; then continue; fi
        if [ "${pp}" == "cm" ] && [ "${IS_RUN_CM}" -ne 1 ]; then continue; fi

        target_pp_clust="${PWD}/${base_root_clusterings}/${best_algo}+${pp}/${network_id}"
        target_pp_stats="${PWD}/${base_root_stats}/${best_algo}+${pp}/${network_id}"
        
        # Check and link post-processing clustering
        if [ -e "${target_pp_clust}" ]; then
            mkdir -p "${base_root_clusterings}/${algo}+${pp}"
            ln -sfn "${target_pp_clust}" "${base_root_clusterings}/${algo}+${pp}/${network_id}"
        else
            echo "Warning: Post-processing cluster folder ${target_pp_clust} not found. Skipping symlink."
        fi

        # Check and link post-processing stats
        if [ -e "${target_pp_stats}" ]; then
            mkdir -p "${base_root_stats}/${algo}+${pp}"
            ln -sfn "${target_pp_stats}" "${base_root_stats}/${algo}+${pp}/${network_id}"
        else
            echo "Warning: Post-processing stats folder ${target_pp_stats} not found. Skipping symlink."
        fi
        
        # Check and link post-processing acc (if variable is set)
        if [ -n "${base_root_acc}" ]; then
            target_pp_acc="${PWD}/${base_root_acc}/${best_algo}+${pp}/${network_id}"
            if [ -e "${target_pp_acc}" ]; then
                mkdir -p "${base_root_acc}/${algo}+${pp}"
                ln -sfn "${target_pp_acc}" "${base_root_acc}/${algo}+${pp}/${network_id}"
            else
                echo "Warning: Post-processing acc folder ${target_pp_acc} not found. Skipping symlink."
            fi
        fi
    done

    echo "[cd-real] ${algo} ${network_id}" >> complete.log
    exit 0 # Safe early exit; all downstream paths are successfully symlinked
fi

run_stats "${inp_edge}" "${base_com}" "${stats_dir}"

# ==========================================
# 2. Run CC
# ==========================================
if [ "${IS_RUN_CC}" -eq 1 ]; then
    suffix="${algo}+cc"
    out_cc_dir="${base_root_clusterings}/${suffix}/${network_id}/"
    stats_cc_dir="${base_root_stats}/${suffix}/${network_id}/"
    acc_cc_dir="${base_root_acc}/${suffix}/${network_id}/"
    cc_com="${out_cc_dir}/com.csv"
    cc_done="${out_cc_dir}/done"
    
    mkdir -p "${out_cc_dir}"
    if [ ! -f "${cc_done}" ]; then
        echo "Running CC..."
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
    fi
fi

# ==========================================
# 3. Run WCC 
# ==========================================
if [ "${IS_RUN_WCC}" -eq 1 ]; then
    suffix="${algo}+wcc"
    out_wcc_dir="${base_root_clusterings}/${suffix}/${network_id}/"
    stats_wcc_dir="${base_root_stats}/${suffix}/${network_id}/"
    acc_wcc_dir="${base_root_acc}/${suffix}/${network_id}/"
    wcc_com="${out_wcc_dir}/com.csv"
    wcc_done="${out_wcc_dir}/done"
    
    mkdir -p "${out_wcc_dir}"
    if [ ! -f "${wcc_done}" ]; then
        echo "Running WCC..."
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
    fi
fi

# ==========================================
# 4. Run CM
# ==========================================
if [ "${IS_RUN_CM}" -eq 1 ]; then
    suffix="${algo}+cm"
    out_cm_dir="${base_root_clusterings}/${suffix}/${network_id}/"
    stats_cm_dir="${base_root_stats}/${suffix}/${network_id}/"
    acc_cm_dir="${base_root_acc}/${suffix}/${network_id}/"
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
    fi
fi

echo "[cd-real] ${algo} ${network_id}" >> complete.log