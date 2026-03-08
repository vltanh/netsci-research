#!/bin/bash

# ==============================================================================
# Slurm Array Job Submitter (submit_array.sh)
# ==============================================================================
# This script generates a list of tasks (tasks.txt) for networks defined in a 
# text file and submits them as a SLURM array job.
#
# USAGE:
#   ./submit_array.sh --mode <mode> [OPTIONS]
#
# COMMON OPTIONS:
#   --network-list <file>    : Path to the list of network IDs (default: data/networks_all.txt).
#   --run-id <id>            : Identifier for the run (default: 0). Used in both syn-cd and gen.
#
# MODES & SPECIFIC OPTIONS:
#   --mode cd      : Run Community Detection (evaluates algorithms).
#       --real                   : Flag to run on empirical (real) networks.
#       --generator <names...>   : (Synthetic only) Name(s) of the network generator(s).
#       --gt-clustering <names..>: (Synthetic only) Name(s) of the ground-truth clustering(s).
#       --criterion <name>       : (Optional) Connectedness criterion for WCC/CM (e.g., sqrt, log).
#       --method <names...>      : List of CD algorithms to run.
#
#   --mode gen     : Generate synthetic networks.
#       --generator <names...>   : Name(s) of the network generator(s) (e.g., ec-sbm).
#       --clustering <names...>  : List of reference clusterings to generate.
#
# EXAMPLES:
#   1. Community Detection on Real Networks:
#      ./submit_array.sh --mode cd --real --criterion sqrt --method leiden-cpm-0.1 sbm-flat-ndc
#
#   2. Community Detection on Synthetic Networks (Multiple Generators/Methods):
#      ./submit_array.sh --mode cd --generator ec-sbm dc-sbm --gt-clustering leiden-cpm-0.1 --method leiden-cpm-0.1 sbm-flat-ndc
#
#   3. Synthetic Network Generation (specific run-id):
#      ./submit_array.sh --mode gen --generator ec-sbm dc-sbm --clustering leiden-cpm-0.5+cm
# ==============================================================================

CONCURRENCY_LIMIT=40
LOG_DIR_BASE="slurm_output"

# Create a unique task file name using the current timestamp and script Process ID ($$)
mkdir -p task_files
TASK_FILE="task_files/tasks_$(date +%Y%m%d_%H%M%S)_$$.txt"

# Default variables
# [CONFIGURABLE] Add any additional default variables here
mode=""
run_id="0"
is_real=0
criterion=""
network_list="data/networks_all.txt"

# Arrays for multi-argument flags
# [CONFIGURABLE] Add any additional arrays for multi-argument flags here
generators=()
gt_clusterings=()
methods=()
clusterings=()

# Parse named arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --mode) mode="$2"; shift 2 ;;
        --run-id) run_id="$2"; shift 2 ;;
        --network-list) network_list="$2"; shift 2 ;;
        --criterion) criterion="$2"; shift 2 ;;
        --real) is_real=1; shift 1 ;;
        # [CONFIGURABLE] Add any additional single-argument flags here
        
        # Multi-argument parsing logic
        --generator)
            shift
            while [[ "$#" -gt 0 && ! "$1" == -* ]]; do
                generators+=("$1"); shift
            done
            ;;
        --gt-clustering)
            shift
            while [[ "$#" -gt 0 && ! "$1" == -* ]]; do
                gt_clusterings+=("$1"); shift
            done
            ;;
        --method)
            shift
            while [[ "$#" -gt 0 && ! "$1" == -* ]]; do
                methods+=("$1"); shift
            done
            ;;
        --clustering)
            shift
            while [[ "$#" -gt 0 && ! "$1" == -* ]]; do
                clusterings+=("$1"); shift
            done
            ;;
        # [CONFIGURABLE] Add any additional flags here following the same pattern
            
        -*) echo "Unknown parameter passed: $1"; exit 1 ;;
        *) echo "Unknown positional argument passed: $1. Please use flags (e.g., --method, --clustering)."; exit 1 ;;
    esac
done

# Validate network list
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
    if [[ ${#generators[@]} -eq 0 ]]; then
        echo "Error: At least one --generator is required for mode 'gen'."
        exit 1
    fi
    if [[ ${#clusterings[@]} -eq 0 ]]; then
        echo "Error: At least one --clustering is required for mode 'gen'."
        exit 1
    fi
    echo "Mode: ${mode}, Generators: ${generators[*]}, Run: ${run_id}"
    
elif [[ "${mode}" == "cd" ]]; then
    if [[ ${#methods[@]} -eq 0 ]]; then
        echo "Error: At least one --method is required for mode 'cd'."
        exit 1
    fi
    
    crit_display="default"
    if [[ -n "${criterion}" ]]; then crit_display="${criterion}"; fi

    if [[ "${is_real}" -eq 1 ]]; then
        echo "Mode: cd (Real Networks), Criterion: ${crit_display}"
    else
        if [[ ${#generators[@]} -eq 0 ]] || [[ ${#gt_clusterings[@]} -eq 0 ]]; then
            echo "Error: --generator and --gt-clustering are required for synthetic 'cd' mode unless --real is passed."
            exit 1
        fi
        echo "Mode: cd (Synthetic), Generators: ${generators[*]}, GTs: ${gt_clusterings[*]}, Run: ${run_id}, Criterion: ${crit_display}"
    fi

# [CONFIGURABLE] Add any additional validation logic here based on the flags you have defined
else
    echo "Unknown mode: ${mode}."
    exit 1
fi

: > "$TASK_FILE"

echo "Generating task list..."
while IFS= read -r network_id || [[ -n "$network_id" ]]; do
    if [[ -z "$network_id" ]]; then continue; fi 

    if [[ "${mode}" == "cd" ]]; then
        crit_arg=""
        crit_suffix=""
        if [[ -n "${criterion}" ]]; then 
            crit_arg="--criterion ${criterion}"
            crit_suffix="_${criterion}"
        fi

        if [[ "${is_real}" -eq 1 ]]; then
            for method in "${methods[@]}"; do
                script="run_cd.sh"
                job_name="${mode}_real_${network_id}_${method}${crit_suffix}"
                args="--algo ${method} --network ${network_id} --real ${crit_arg}"
                log_path="${LOG_DIR_BASE}/${mode}/real/${method}${crit_suffix}/${network_id}"
                
                echo "${script}|${args}|${log_path}|${job_name}" >> "$TASK_FILE"
            done
        else
            for generator in "${generators[@]}"; do
                for gt_clustering in "${gt_clusterings[@]}"; do
                    for method in "${methods[@]}"; do
                        script="run_cd.sh"
                        job_name="${mode}_${generator}_${gt_clustering}_${network_id}_${run_id}_${method}${crit_suffix}"
                        args="--algo ${method} --network ${network_id} --generator ${generator} --gt-clustering ${gt_clustering} --run-id ${run_id} ${crit_arg}"
                        log_path="${LOG_DIR_BASE}/${mode}/${generator}/${gt_clustering}/${method}${crit_suffix}/${network_id}/${run_id}"
                        
                        echo "${script}|${args}|${log_path}|${job_name}" >> "$TASK_FILE"
                    done
                done
            done
        fi
        
    elif [[ "${mode}" == "gen" ]]; then
        for generator in "${generators[@]}"; do
            for clustering_id in "${clusterings[@]}"; do
                job_name="${mode}_${generator}_${network_id}_${clustering_id}_${run_id}"
                script="run_generator.sh"
                args="${generator} ${network_id} ${clustering_id} ${run_id}"
                log_path="${LOG_DIR_BASE}/${mode}/${generator}/${network_id}/${clustering_id}/${run_id}"
                
                echo "${script}|${args}|${log_path}|${job_name}" >> "$TASK_FILE"
            done
        done

    # [CONFIGURABLE] Add any additional modes and their corresponding task generation logic here
    fi
done < "${network_list}"

total_tasks=$(wc -l < "$TASK_FILE")

if [[ "$total_tasks" -eq 0 ]]; then
    echo "No tasks generated. Did you forget to provide methods or clusterings?"
    rm "$TASK_FILE"
    exit 0
fi

echo "Submitting array for ${total_tasks} tasks (Max Concurrency: ${CONCURRENCY_LIMIT})..."
sbatch --array=1-${total_tasks}%${CONCURRENCY_LIMIT} array_wrapper.sh "${TASK_FILE}"