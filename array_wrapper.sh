#!/bin/bash
#SBATCH --job-name=ecsbmv2_array
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#SBATCH --signal=B:SIGUSR1@60

TASK_FILE=$1

if [[ -z "${TASK_FILE}" ]] || [[ ! -f "${TASK_FILE}" ]]; then
    echo "CRITICAL ERROR: Task file '${TASK_FILE}' not provided or not found!"
    exit 1
fi

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

# =========================================================
# SIGNAL HANDLING & CLEANUP
# =========================================================

# 1. General Cleanup (Fires on normal completion OR custom exits)
cleanup_lock() {
    rmdir "${LOCK_DIR}" 2>/dev/null
    echo "Lock released: ${LOCK_DIR}"
}
trap cleanup_lock EXIT

# 2. Timeout/Cancel Handler
signal_handler() {
    echo "Caught timeout or cancel signal. Cleaning up..."
    # If the child process is running, terminate it cleanly
    if [[ -n "${CHILD_PID}" ]]; then
        kill -TERM "${CHILD_PID}" 2>/dev/null
    fi
    # Exiting here will automatically trigger the 'EXIT' trap above
    exit 124
}
# Trap SIGUSR1 (our 60s timeout warning) and SIGTERM (manual scancel)
trap signal_handler SIGUSR1 SIGTERM

# =========================================================

# Dynamically Rename Job
scontrol update JobId=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} Name="${JOB_NAME}"

# Setup Logging
mkdir -p "${LOG_PATH}"
LOG_FILE="${LOG_PATH}/${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out"
exec > "${LOG_FILE}" 2>&1

echo "Lock acquired: ${LOCK_DIR}"
echo "Starting Job: ${JOB_NAME}"

# Execute in the background so bash can still intercept signals
./${SCRIPT} ${ARGS} &
CHILD_PID=$!

# Wait for the task to finish
wait ${CHILD_PID}
EXIT_CODE=$?

# Exit with the script's actual exit code.
# The trap we set for 'EXIT' will automatically remove the lock.
exit $EXIT_CODE
