#!/bin/bash

algo=$1
network_id=$2

# Base Output Directory
COMMDET_BASE="data/reference_clusterings/"

# Flags
IS_RUN_CC=1
IS_RUN_WCC=0
IS_RUN_CM=1

# Disable CC/WCC for specific algos
case ${algo} in
    leiden*|ikc*) IS_RUN_CC=0 ;;
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
echo "${algo} ${clustering} ${network_id}"

inp_dir="data/empirical_networks/netzschleuder/${network_id}/"
inp_edge="${inp_dir}/${network_id}.csv"

if [ ! -f "${inp_edge}" ]; then
    echo "Input file ${inp_edge} does not exist. Skipping."
    continue
fi

base_root_clusterings="${COMMDET_BASE}/clusterings/${network_id}/${clustering}/"
base_root_stats="${COMMDET_BASE}/stats/${network_id}/${clustering}/"

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
    sbm_model=$(echo ${algo} | cut -d'-' -f2)
fi

# ==========================================
# 1. Run Base Clustering
# ==========================================
suffix="${algo}"
out_dir="${base_root_clusterings}/${suffix}/"
stats_dir="${base_root_stats}/${suffix}/"
acc_dir="${base_root_acc}/${suffix}/"

base_com="${out_dir}/com.csv"
base_dens="${out_dir}/density.csv"
base_done="${out_dir}/done"

echo "Running clustering..."
mkdir -p "${out_dir}"

if [ ! -f "${base_done}" ]; then
    if [[ ${algo} == leiden* ]]; then
        if [[ ${leiden_model} == cpm ]]; then
            { timeout 3d /usr/bin/time -v python src/comm-det/leiden/run_leiden.py --edgelist "${inp_edge}" --output-directory "${out_dir}" --model cpm --resolution "${leiden_res}"; } 2> "${out_dir}/error.log"
        elif [[ ${leiden_model} == mod ]]; then
            { timeout 3d /usr/bin/time -v python src/comm-det/leiden/run_leiden.py --edgelist "${inp_edge}" --output-directory "${out_dir}" --model mod; } 2> "${out_dir}/error.log"
        else
            echo "Unknown leiden_model: ${leiden_model}"; continue
        fi
    elif [[ ${algo} == infomap ]]; then
        { timeout 3d /usr/bin/time -v python src/comm-det/infomap/run_infomap.py --edgelist "${inp_edge}" --output-directory "${out_dir}"; } 1> "${out_dir}/output.log" 2> "${out_dir}/error.log"
    elif [[ ${algo} == ikc* ]]; then
        { timeout 3d /usr/bin/time -v python src/comm-det/ikc/run_ikc.py --edgelist "${inp_edge}" --output-directory "${out_dir}" --kvalue "${ikc_k}"; } 1> "${out_dir}/output.log" 2> "${out_dir}/error.log"
    elif [[ ${algo} == sbm* ]]; then
        { timeout 3d /usr/bin/time -v python src/comm-det/sbm/run_sbm.py --edgelist "${inp_edge}" --output-directory "${out_dir}" --method "${sbm_model}"; } 1> "${out_dir}/output.log" 2> "${out_dir}/error.log"
    else
        echo "Unknown method: ${algo}"; continue
    fi

    if [ -f "${base_com}" ]; then 
        touch "${base_done}"
    fi
fi

if [ ! -f "${base_com}" ]; then
    echo "CRITICAL: Base clustering failed or timed out."
    continue
fi

run_stats "${inp_edge}" "${base_com}" "${stats_dir}"

# ==========================================
# 2. Run CC
# ==========================================
if [ "${IS_RUN_CC}" -eq 1 ]; then
    suffix="${algo}+cc"
    out_cc_dir="${base_root_clusterings}/${suffix}/"
    stats_cc_dir="${base_root_stats}/${suffix}/"
    acc_cc_dir="${base_root_acc}/${suffix}/"
    cc_com="${out_cc_dir}/com.csv"
    cc_done="${out_cc_dir}/done"
    
    mkdir -p "${out_cc_dir}"
    if [ ! -f "${cc_done}" ]; then
        { timeout 3d /usr/bin/time -v ./constrained-clustering/constrained_clustering \
            MincutOnly \
            --edgelist "${inp_edge}" \
            --existing-clustering "${base_com}" \
            --num-processors 1 \
            --output-file "${cc_com}" \
            --log-file "${out_cc_dir}/cc.log" \
            --log-level 2 \
            --connectedness-criterion 0; } 2> "${out_cc_dir}/error.log"
        [ -f "${cc_com}" ] && touch "${cc_done}"
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
    out_wcc_dir="${base_root_clusterings}/${suffix}/"
    stats_wcc_dir="${base_root_stats}/${suffix}/"
    acc_wcc_dir="${base_root_acc}/${suffix}/"
    wcc_com="${out_wcc_dir}/com.csv"
    wcc_done="${out_wcc_dir}/done"
    
    mkdir -p "${out_wcc_dir}"
    if [ ! -f "${wcc_done}" ]; then
        { timeout 3d /usr/bin/time -v ./constrained-clustering/constrained_clustering \
            MincutOnly \
            --connectedness-criterion "1log_10(n)" \
            --edgelist "${inp_edge}" \
            --existing-clustering "${base_com}" \
            --num-processors 1 \
            --output-file "${wcc_com}" \
            --log-file "${out_wcc_dir}/wcc.log" \
            --log-level 2; } 2> "${out_wcc_dir}/error.log"
        [ -f "${wcc_com}" ] && touch "${wcc_done}"
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
    out_cm_dir="${base_root_clusterings}/${suffix}/"
    stats_cm_dir="${base_root_stats}/${suffix}/"
    acc_cm_dir="${base_root_acc}/${suffix}/"
    cm_com="${out_cm_dir}/com.csv"
    cm_done="${out_cm_dir}/done"
    
    if [ ! -f "${cm_done}" ]; then
        if [[ ${algo} == leiden* ]]; then
            if [[ ${leiden_model} == cpm ]]; then
                mkdir -p "${out_cm_dir}"
                # { timeout 3d /usr/bin/time -v python cm_pipeline/scripts/run_cm.py --no-prune \
                #     --input "${inp_edge}" --existing-clustering "${base_com}" --working-directory "${out_cm_dir}" \
                #     --output "${cm_com}" --threshold 1log10 --clusterer leiden --resolution "${leiden_res}"; } 1> "${out_cm_dir}/output.log" 2> "${out_cm_dir}/error.log"
                { timeout 3d /usr/bin/time -v ./constrained-clustering/constrained_clustering \
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
                { timeout 3d /usr/bin/time -v ./constrained-clustering/constrained_clustering \
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
                    --log-level 2; } 2> "${out_cm_dir}/error.log"
            fi
        elif [[ ${algo} == infomap ]]; then
            mkdir -p "${out_cm_dir}"
            { timeout 3d /usr/bin/time -v python cm_pipeline/scripts/run_cm.py --no-prune \
                --input "${inp_edge}" --existing-clustering "${base_com}" --working-directory "${out_cm_dir}" \
                --output "${cm_com}" --threshold 1log10 --clusterer external \
                --clusterer_args infomap_cm_cargs.json --clusterer_file cm_pipeline/hm01/clusterers/external_clusterers/infomap_wrapper.py; } 1> "${out_cm_dir}/output.log" 2> "${out_cm_dir}/error.log"
        elif [[ ${algo} == ikc* ]]; then
            mkdir -p "${out_cm_dir}"
            { timeout 3d /usr/bin/time -v python cm_pipeline/scripts/run_cm.py --no-prune \
                --input "${inp_edge}" --existing-clustering "${base_com}" --working-directory "${out_cm_dir}" \
                --output "${cm_com}" --threshold 1log10 --clusterer ikc --k "${ikc_k}"; } 1> "${out_cm_dir}/output.log" 2> "${out_cm_dir}/error.log"
        else
            echo "CM not implemented for ${algo}"
        fi
        [ -f "${cm_com}" ] && touch "${cm_done}"
    fi

    if [ -f "${cm_com}" ]; then
        run_stats "${inp_edge}" "${cm_com}" "${stats_cm_dir}"
    fi
fi

echo "[cd-real] ${algo} ${network_id}" >> complete.log