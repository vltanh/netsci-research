#!/bin/bash

# ==============================================================================
# Slurm Array Job Submitter (submit_array.sh)
# ==============================================================================
# This script generates a list of tasks (tasks.txt) for networks defined in a 
# text file and submits them as a SLURM array job.
#
# USAGE:
#   ./submit_array.sh --mode <mode> [OPTIONS] <methods/clusterings...>
#
# COMMON OPTIONS:
#   --network-list <file>    : Path to the list of network IDs (default: data/networks_all.txt).
#   --run-id <id>            : Identifier for the run (default: 0). Used in both syn-cd and gen.
#
# MODES & SPECIFIC OPTIONS:
#   --mode cd      : Run Community Detection (evaluates algorithms).
#       --real                   : Flag to run on empirical (real) networks.
#       --generator <name>       : (Synthetic only) Name of the network generator.
#       --gt-clustering <name>   : (Synthetic only) Name of the ground-truth clustering.
#       <methods...>             : Space-separated list of CD algorithms to run.
#
#   --mode gen     : Generate synthetic networks.
#       --generator <name>       : Name of the network generator (e.g., ec-sbm).
#       <clusterings...>         : Space-separated list of reference clusterings to generate. 
#
# EXAMPLES:
#   1. Community Detection on Real Networks:
#      ./submit_array.sh --mode cd --real leiden-cpm-0.1 sbm-flat-dc
#      (Note: This will run leiden-cpm-0.1 and sbm-flat-dc on all real networks)
#
#   2. Community Detection on Synthetic Networks:
#      ./submit_array.sh --mode cd --generator ec-sbm --gt-clustering leiden-cpm-0.1 leiden-cpm-0.1 sbm-flat-ndc
#      (Note: leiden-cpm-0.1 is used both as the ground-truth and the method for evaluation in this example)
#
#   3. Synthetic Network Generation (specific run-id):
#      ./submit_array.sh --mode gen --generator ec-sbm leiden-cpm-0.5+cm
#      (Note: This will use leiden-cpm-0.5+cm as the reference clustering for generation across all networks)
# ==============================================================================

CONCURRENCY_LIMIT=40
LOG_DIR_BASE="slurm_output"

# Create a unique task file name using the current timestamp and script Process ID ($$)
mkdir -p task_files
TASK_FILE="task_files/tasks_$(date +%Y%m%d_%H%M%S)_$$.txt"

# Default variables
mode=""
generator=""
gt_clustering=""
run_id="0"
is_real=0
network_list="data/networks_all.txt"
positional_args=()
# [CONFIGURABLE] Future variables for additional modes can be added here

# Parse named arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --mode) mode="$2"; shift 2 ;;
        --generator) generator="$2"; shift 2 ;;
        --gt-clustering) gt_clustering="$2"; shift 2 ;;
        --run-id) run_id="$2"; shift 2 ;;
        --network-list) network_list="$2"; shift 2 ;;
        --real) is_real=1; shift 1 ;;
        # [CONFIGURABLE] Future named arguments can be added here
        -*) echo "Unknown parameter passed: $1"; exit 1 ;;
        *) positional_args+=("$1"); shift 1 ;;
    esac
done

# [CONFIGURABLE] Future mode-specific validations can be added here
if [[ ! -f "${network_list}" ]]; then
    echo "Error: Network list file '${network_list}' not found."
    exit 1
fi

# Validate inputs based on mode
if [[ -z "${mode}" ]]; then
    echo "Error: --mode is required (e.g., --mode cd or --mode gen)."
    exit 1
fi

if [[ "${mode}" == "gen" ]]; then
    if [[ -z "${generator}" ]]; then
        echo "Error: --generator is required for mode 'gen'."
        exit 1
    fi
    clusterings=("${positional_args[@]}")
    echo "Mode: ${mode}, Generator: ${generator}, Run: ${run_id}"
elif [[ "${mode}" == "cd" ]]; then
    methods=("${positional_args[@]}")
    if [[ "${is_real}" -eq 1 ]]; then
        echo "Mode: cd (Real Networks)"
    else
        if [[ -z "${generator}" ]] || [[ -z "${gt_clustering}" ]]; then
            echo "Error: --generator and --gt-clustering are required for synthetic 'cd' mode unless --real is passed."
            exit 1
        fi
        echo "Mode: cd (Synthetic), Generator: ${generator}, GT: ${gt_clustering}, Run: ${run_id}"
    fi
# elif [[ "${mode}" == <mode> ]]; then
# [CONFIGURABLE] Future mode-specific validations can be added here
else
    echo "Unknown mode: ${mode}."
    exit 1
fi

: > "$TASK_FILE"

echo "Generating task list..."
for network_id in $(cat "${network_list}"); do
    if [[ -z "$network_id" ]]; then continue; fi

    if [[ "${mode}" == "cd" ]]; then
        for method in "${methods[@]}"; do
            script="run_cd.sh"
            
            if [[ "${is_real}" -eq 1 ]]; then
                job_name="${mode}_real_${network_id}_${method}"
                args="${method} ${network_id} real"
                log_path="${LOG_DIR_BASE}/${mode}/real/${method}/${network_id}"
            else
                job_name="${mode}_${generator}_${gt_clustering}_${network_id}_${run_id}_${method}"
                args="${method} ${network_id} ${generator} ${gt_clustering} ${run_id}"
                log_path="${LOG_DIR_BASE}/${mode}/${generator}/${gt_clustering}/${method}/${network_id}/${run_id}"
            fi
            
            echo "${script}|${args}|${log_path}|${job_name}" >> "$TASK_FILE"
        done
    elif [[ "${mode}" == "gen" ]]; then
        for clustering_id in "${clusterings[@]}"; do
            job_name="${mode}_${generator}_${network_id}_${clustering_id}_${run_id}"
            script="run_generator.sh"
            args="${generator} ${network_id} ${clustering_id} ${run_id}"
            log_path="${LOG_DIR_BASE}/${mode}/${generator}/${network_id}/${clustering_id}/${run_id}"
            
            echo "${script}|${args}|${log_path}|${job_name}" >> "$TASK_FILE"
        done
    # elif [[ "${mode}" == <mode> ]]; then
    # [CONFIGURABLE] 
    #   Future mode-specific task generation can be added here
    #   Remember to define 'script', 'args', 'log_path', and 'job_name' variables appropriately.
    else
        echo "Unknown mode during task generation: ${mode}."
        exit 1
    fi
done

total_tasks=$(wc -l < "$TASK_FILE")

if [[ "$total_tasks" -eq 0 ]]; then
    echo "No tasks generated. Did you forget to provide methods/clusterings at the end?"
    rm "$TASK_FILE"
    exit 0
fi

echo "Submitting array for ${total_tasks} tasks (Max Concurrency: ${CONCURRENCY_LIMIT})..."
sbatch --array=1-${total_tasks}%${CONCURRENCY_LIMIT} array_wrapper.sh "${TASK_FILE}"