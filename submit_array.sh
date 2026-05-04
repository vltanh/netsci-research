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
#   --networks <args...>     : One or more network sources. Each arg is either a file
#                              path (read line-by-line) or a literal network ID.
#                              Concatenated and deduplicated, preserving input order.
#                              Defaults to "data/networks_all.txt".
#   --run-id <id>            : Identifier for the run (default: 0). Used in both syn-cd and gen.
#
# SLURM OPTIONS:
#   --time <time>            : Wall time limit (default: 04:00:00).
#   --mem <mem>              : Memory per node (default: 32G).
#   --partition <name>       : Partition to submit to (default: secondary).
#   --constraint <name>      : Node constraint (default: AE7713).
#   --dependency <cond...>   : One or more SLURM dependency conditions (e.g., afterok:123 afterany:456).
#                              Multiple conditions are comma-joined: afterok:123,afterany:456.
#   --concurrency <n>        : Max concurrent array tasks. Preferred if both are given.
#   --total-mem <mem>        : Total memory budget (e.g., 256G). Used to compute concurrency as floor(total-mem / mem)
#                              when --concurrency is not given. If neither is given, defaults to concurrency=4.
#   --extra-args <args...>   : Pass-through args appended verbatim to every per-task command line.
#                              Use to forward downstream flags. Greedy: consumes everything remaining,
#                              so place this flag last on the command line.
#                              For 'cd' mode (run_cd.sh): --run-stats, --run-cc, --run-acc, --run-wcc,
#                              --run-cm, --timeout <sec>, etc. Without these, run_cd.sh runs the algo
#                              but skips stats/accuracy/connectivity passes.
#                              For 'gen' mode (run_generator.sh): --run-stats, --run-comp, --keep-state,
#                              --n-threads, --outlier-mode, etc.
#                              Note: --seed is set by this script as (run_id + 1); don't override it here.
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
#      ./submit_array.sh --mode cd --real --criterion sqrt --method leiden-cpm-0.1 sbm-flat-ndc \
#          --extra-args --run-stats --run-cc
#
#   2. Community Detection on Synthetic Networks (Multiple Generators/Methods):
#      ./submit_array.sh --mode cd --generator ec-sbm dc-sbm --gt-clustering leiden-cpm-0.1 --method leiden-cpm-0.1 sbm-flat-ndc \
#          --extra-args --run-stats --run-acc --run-cc
#
#   3. Synthetic Network Generation (specific run-id):
#      ./submit_array.sh --mode gen --generator ec-sbm dc-sbm --clustering leiden-cpm-0.5+cm \
#          --extra-args --run-stats --run-comp
#
#   4. With SLURM overrides and dependencies:
#      ./submit_array.sh --mode cd --real --method leiden-cpm-0.1 --time 01:00:00 --mem 16G \
#          --dependency afterok:12345 afterany:67890 \
#          --extra-args --run-stats --run-cc --run-wcc --run-cm --timeout 3600
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common/state.sh"

log() {
    builtin echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

MAX_JOB_PER_ARRAY=1000
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
time="04:00:00"
mem="32G"
partition="secondary"
constraint="AE7713"
concurrency=""
total_mem=""

# Arrays for multi-argument flags
# [CONFIGURABLE] Add any additional arrays for multi-argument flags here
generators=()
gt_clusterings=()
methods=()
clusterings=()
dependencies=()
networks_args=()
extra_args=()

# Parse named arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --mode) mode="$2"; shift 2 ;;
        --run-id) run_id="$2"; shift 2 ;;
        --criterion) criterion="$2"; shift 2 ;;
        --real) is_real=1; shift 1 ;;
        --time) time="$2"; shift 2 ;;
        --mem) mem="$2"; shift 2 ;;
        --partition) partition="$2"; shift 2 ;;
        --constraint) constraint="$2"; shift 2 ;;
        --concurrency) concurrency="$2"; shift 2 ;;
        --total-mem) total_mem="$2"; shift 2 ;;
        # [CONFIGURABLE] Add any additional single-argument flags here

        --dependency)
            shift
            while [[ "$#" -gt 0 && ! "$1" == -* ]]; do
                dependencies+=("$1"); shift
            done
            ;;

        # Multi-argument parsing logic
        --networks)
            shift
            while [[ "$#" -gt 0 && ! "$1" == --* ]]; do
                networks_args+=("$1"); shift
            done
            ;;
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
        # Greedy pass-through: consumes everything remaining. Place last on the command line.
        --extra-args)
            shift
            while [[ "$#" -gt 0 ]]; do
                extra_args+=("$1"); shift
            done
            ;;
        # [CONFIGURABLE] Add any additional flags here following the same pattern

        -*) echo "Unknown parameter passed: $1"; exit 1 ;;
        *) echo "Unknown positional argument passed: $1. Please use flags (e.g., --method, --clustering)."; exit 1 ;;
    esac
done

# Compute concurrency from --total-mem / --mem if provided
# Converts a mem string (e.g., 32G, 512M, 1T, or bare bytes) to MB
mem_to_mb() {
    local v="$1"
    local num="${v%[KkMmGgTt]}"
    local unit="${v:${#num}}"
    case "$unit" in
        K|k) awk -v n="$num" 'BEGIN{printf "%.0f", n/1024}' ;;
        M|m|"") awk -v n="$num" 'BEGIN{printf "%.0f", n}' ;;
        G|g) awk -v n="$num" 'BEGIN{printf "%.0f", n*1024}' ;;
        T|t) awk -v n="$num" 'BEGIN{printf "%.0f", n*1024*1024}' ;;
        *) echo "Error: unrecognized memory unit in '$v'." >&2; exit 1 ;;
    esac
}

if [[ -n "${concurrency}" ]]; then
    echo "Concurrency: ${concurrency}"
elif [[ -n "${total_mem}" ]]; then
    mem_mb=$(mem_to_mb "${mem}")
    total_mb=$(mem_to_mb "${total_mem}")
    if [[ "${mem_mb}" -le 0 ]]; then
        echo "Error: --mem must be positive."
        exit 1
    fi
    concurrency=$(( total_mb / mem_mb ))
    if [[ "${concurrency}" -lt 1 ]]; then
        echo "Error: --total-mem (${total_mem}) is smaller than --mem (${mem})."
        exit 1
    fi
    echo "Computed concurrency: ${concurrency} (total-mem=${total_mem} / mem=${mem})"
else
    concurrency=4
    echo "Concurrency: ${concurrency} (default)"
fi

# Resolve --networks args into a deduplicated, ordered list of network IDs.
# Each arg is either a file path (read line-by-line) or a literal network ID.
if [[ ${#networks_args[@]} -eq 0 ]]; then
    networks_args=("data/networks_all.txt")
fi

declare -A net_seen
network_ids=()
add_network() {
    local n="$1"
    [[ -z "${n}" ]] && return
    if [[ -z "${net_seen[$n]}" ]]; then
        net_seen["${n}"]=1
        network_ids+=("${n}")
    fi
}
for arg in "${networks_args[@]}"; do
    if [[ -f "${arg}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            add_network "${line}"
        done < "${arg}"
    else
        add_network "${arg}"
    fi
done

if [[ ${#network_ids[@]} -eq 0 ]]; then
    echo "Error: No networks resolved from --networks args: ${networks_args[*]}"
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

extra_arg_str=""
if [[ ${#extra_args[@]} -gt 0 ]]; then
    extra_arg_str=" ${extra_args[*]}"
    echo "Pass-through extra args: ${extra_args[*]}"
fi

echo "Generating task list for ${#network_ids[@]} networks..."
for network_id in "${network_ids[@]}"; do
    if [[ "${mode}" == "cd" ]]; then
        crit_arg=""
        crit_suffix=""
        if [[ -n "${criterion}" ]]; then
            crit_arg="--criterion ${criterion}"
            crit_suffix="_${criterion}"
        fi

        if [[ "${is_real}" -eq 1 ]]; then
            for method in "${methods[@]}"; do
                script="community-detection/run_cd.sh"
                job_name="${mode}_real_${network_id}_${method}${crit_suffix}"
                args="--algo ${method} --network ${network_id} --real ${crit_arg}${extra_arg_str}"
                log_path="${LOG_DIR_BASE}/${mode}/real/${method}${crit_suffix}/${network_id}"

                echo "${script}|${args}|${log_path}|${job_name}" >> "$TASK_FILE"
            done
        else
            for generator in "${generators[@]}"; do
                for gt_clustering in "${gt_clusterings[@]}"; do
                    for method in "${methods[@]}"; do
                        script="community-detection/run_cd.sh"
                        job_name="${mode}_${generator}_${gt_clustering}_${network_id}_${run_id}_${method}${crit_suffix}"
                        args="--algo ${method} --network ${network_id} --synthetic --generator ${generator} --gt-clustering-id ${gt_clustering} --run-id ${run_id} ${crit_arg}${extra_arg_str}"
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
                script="network-generation/run_generator.sh"
                args="--generator ${generator} --run-id ${run_id} --seed $((run_id + 1)) --macro --network ${network_id} --clustering-id ${clustering_id}${extra_arg_str}"
                log_path="${LOG_DIR_BASE}/${mode}/${generator}/${network_id}/${clustering_id}/${run_id}"

                echo "${script}|${args}|${log_path}|${job_name}" >> "$TASK_FILE"
            done
        done

    # [CONFIGURABLE] Add any additional modes and their corresponding task generation logic here
    fi
done

total_tasks=$(wc -l < "$TASK_FILE")

if [[ "$total_tasks" -eq 0 ]]; then
    echo "No tasks generated. Did you forget to provide methods or clusterings?"
    rm "$TASK_FILE"
    exit 0
fi

echo "Generated ${total_tasks} total tasks."

sbatch_args=(--time="${time}" --mem="${mem}" --partition="${partition}" --constraint="${constraint}")
if [[ ${#dependencies[@]} -gt 0 ]]; then
    dep_str=$(IFS=,; echo "${dependencies[*]}")
    sbatch_args+=(--dependency="${dep_str}")
    echo "Dependencies: ${dep_str}"
fi

if [[ "$total_tasks" -le "$MAX_JOB_PER_ARRAY" ]]; then
    echo "Submitting single array job for ${total_tasks} tasks (Max Concurrency: ${concurrency})..."
    sbatch --array=1-${total_tasks}%${concurrency} "${sbatch_args[@]}" array_wrapper.sh "${TASK_FILE}"
else
    echo "Total tasks exceed MAX_JOB_PER_ARRAY (${MAX_JOB_PER_ARRAY}). Splitting into multiple jobs..."

    # Split the task file into chunks (-l lines, -d numeric suffixes, -a 3 suffix length)
    split -a 3 -d -l "${MAX_JOB_PER_ARRAY}" "${TASK_FILE}" "${TASK_FILE}_part_"

    for part_file in "${TASK_FILE}_part_"*; do
        part_tasks=$(wc -l < "${part_file}")
        echo "Submitting array for ${part_tasks} tasks from ${part_file}..."
        sbatch --array=1-${part_tasks}%${concurrency} "${sbatch_args[@]}" array_wrapper.sh "${part_file}"
    done
fi
