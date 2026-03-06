#!/bin/bash

CONCURRENCY_LIMIT=40
LOG_DIR_BASE="slurm_output"
TASK_FILE="tasks.txt"

mode=$1; shift
if [[ "${mode}" == "gen" ]]; then
    generator=$1; shift
    echo "Mode: ${mode}, Generator: ${generator}"
elif [[ "${mode}" == "cd-real" ]]; then
    echo "Mode: ${mode}"
else
    echo "Unknown mode: ${mode}"
    exit 1
fi

: > "$TASK_FILE"

echo "Generating task list..."
for network_id in $(cat data/networks_all.txt)
do
    if [[ "${mode}" == "cd-real" ]]; then
        methods=("$@")
        for method in "${methods[@]}"; do
            job_name="${mode}_${network_id}_${method}"
            script="run_cd_real.sh"
            args="${method} ${network_id}"
            log_path="${LOG_DIR_BASE}/${mode}/${method}/${network_id}"
            
            echo "${script}|${args}|${log_path}|${job_name}" >> "$TASK_FILE"
        done
    elif [[ "${mode}" == "gen" ]]; then
        clusterings=("$@")
        for clustering_id in "${clusterings[@]}"; do
            job_name="${mode}_${generator}_${network_id}_${clustering_id}"
            script="run_generator.sh"
            args="${generator} ${network_id} ${clustering_id}"
            log_path="${LOG_DIR_BASE}/${mode}/${generator}/${network_id}/${clustering_id}"
            
            echo "${script}|${args}|${log_path}|${job_name}" >> "$TASK_FILE"
        done
    else
        echo "Unknown mode: ${mode}"
        exit 1
    fi
done

total_tasks=$(wc -l < "$TASK_FILE")

if [[ "$total_tasks" -eq 0 ]]; then
    echo "No tasks generated."
    rm "$TASK_FILE"
    exit 0
fi

echo "Submitting array for ${total_tasks} tasks (Max Concurrency: ${CONCURRENCY_LIMIT})..."
sbatch --array=1-${total_tasks}%${CONCURRENCY_LIMIT} array_wrapper.sh
