#!/bin/bash

# ==============================================================================
# Empirical Network Statistics Pipeline (run_empirical_stats.sh)
# ==============================================================================
# Computes network-only structural statistics for an empirical/reference network.
#
# USAGE:
#   Macro : ./run_empirical_stats.sh --macro --network <id>
#   Custom: ./run_empirical_stats.sh --input-edgelist <path> --output-dir <dir> [--network <id>]
#
# OPTIONS:
#   [Macros: Auto-populate input/output paths]
#     --macro               : Use standard paths for empirical networks.
#     --network <id>        : Network identifier (Required for --macro, optional for custom grouping).
#
#   [Custom Paths]
#     --input-edgelist <p>  : Custom path to the input edge list CSV.
#     --output-dir <dir>    : Target directory for stats outputs.
#
# PATH LEGEND:
#   [INP_EDGE]
#       Macro  -> data/empirical_networks/networks/<network_id>/<network_id>.csv
#       Custom -> <input_edgelist>
#   [OUT_DIR]
#       Macro  -> data/empirical_networks/stats/<network_id>
#       Custom -> <output_dir>
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
if [[ "${SCRIPT_DIR}" == *"/slurmd/job"* ]]; then
    SCRIPT_DIR="${SLURM_SUBMIT_DIR}"
fi

# ==========================================
# Helper Functions: Logging & State Tracking
# ==========================================
log() {
    builtin echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

is_step_done() {
    local done_file="$1"
    if [ ! -f "${done_file}" ]; then return 1; fi
    if ! sha256sum --status -c "${done_file}" 2>/dev/null; then
        log "State change detected. Recomputing..."
        return 1
    fi
    return 0
}

mark_done() {
    local done_file="$1"
    local stage_name="$2"
    read -r -a inputs <<< "$3"
    local out_dir="$4"
    
    local tmp_done="${done_file}.tmp.$$"
    
    sha256sum "${inputs[@]}" > "${tmp_done}"
    find "${out_dir}" -maxdepth 1 -type f ! -name "$(basename "${done_file}")" ! -name "$(basename "${tmp_done}")" -exec sha256sum {} + >> "${tmp_done}"
    
    mv "${tmp_done}" "${done_file}"
    log "Success [${stage_name}]: I/O hashes recorded atomically."
}

# ==========================================
# Argument Parsing
# ==========================================
network_id=""
is_macro=0
custom_input=""
custom_out_dir=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --network) network_id="$2"; shift 2 ;;
        --macro) is_macro=1; shift 1 ;;
        --input-edgelist) custom_input="$2"; shift 2 ;;
        --output-dir) custom_out_dir="$2"; shift 2 ;;
        -*) log "Unknown parameter passed: $1"; exit 1 ;;
        *) log "Unexpected argument: $1"; exit 1 ;;
    esac
done

# ==========================================
# Input/Output Path Routing (Unified)
# ==========================================
if [ "${is_macro}" -eq 1 ]; then
    if [ -z "${network_id}" ]; then
        log "Error: --network is required when using --macro."
        exit 1
    fi
    
    INP_EDGE="data/empirical_networks/networks/${network_id}/${network_id}.csv"
    OUT_DIR="data/empirical_networks/stats/${network_id}"
    dataset_name="${network_id}"
else
    if [ -z "${custom_input}" ] || [ -z "${custom_out_dir}" ]; then
        log "Error: In custom mode, you must provide --input-edgelist and --output-dir."
        exit 1
    fi
    
    INP_EDGE="${custom_input}"
    OUT_DIR="${custom_out_dir}"
    dataset_name="[Custom] ${network_id:+"${network_id}"}"
fi

if [ ! -f "${INP_EDGE}" ]; then
    log "CRITICAL: Empirical network edgelist not found at ${INP_EDGE}"
    exit 1
fi

# ==========================================
# Orchestration
# ==========================================
log "============================"
log "Computing Empirical Network Stats for: ${dataset_name}"
log "============================"

done_file="${OUT_DIR}/done"

log "Evaluating empirical stats state..."
if ! is_step_done "${done_file}"; then
    log "Computing Network Stats..."
    mkdir -p "${OUT_DIR}"
    
    # Run Network-Only Statistics
    { /usr/bin/time -v python "${SCRIPT_DIR}/network_evaluation/network_stats/compute_network_stats.py" \
        --network "${INP_EDGE}" \
        --outdir "${OUT_DIR}"; } 1> "${OUT_DIR}/out.log" 2> "${OUT_DIR}/error.log"
        
    # Lock the state
    if [ -f "${OUT_DIR}/error.log" ]; then
        mark_done "${done_file}" "Empirical Stats" "${INP_EDGE}" "${OUT_DIR}"
    fi
else
    log "Empirical stats already up-to-date. Skipping..."
fi

log "Process completed. Outputs mapped to: ${OUT_DIR}"