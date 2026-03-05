#!/bin/bash
#SBATCH --job-name=ecsbmv2_array
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#SBATCH --time=04:00:00
#SBATCH --mem=32G
#SBATCH --partition=secondary
#SBATCH --constraint="G84688|emeraldrapids"

TASK_FILE="tasks.txt"

# Retrieve and Parse Task
TASK_LINE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${TASK_FILE}")
IFS='|' read -r SCRIPT ARGS LOG_PATH JOB_NAME <<< "$TASK_LINE"

# Check if Job is Already Running
LOCK_DIR="slurm_locks/${JOB_NAME}.lock"

# Ensure the parent lock folder exists (safe to run concurrently)
mkdir -p "slurm_locks"

# Try to create the lock directory.
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    # If we are here, another process holds the lock.
    exit 0
fi

# Dynamically Rename Job
scontrol update JobId=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} Name="${JOB_NAME}"

# Setup Logging
mkdir -p "${LOG_PATH}"
LOG_FILE="${LOG_PATH}/${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out"
exec > "${LOG_FILE}" 2>&1

echo "Lock acquired: ${LOCK_DIR}"
echo "Starting Job: ${JOB_NAME}"

# Execute
./${SCRIPT} ${ARGS}
EXIT_CODE=$?

# 4. Release Lock
rmdir "${LOCK_DIR}"
exit $EXIT_CODE
