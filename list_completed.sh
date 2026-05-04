#!/bin/bash

# ==============================================================================
# List Completed Networks (list_completed.sh)
# ==============================================================================
# Scans the tree and reports completed runs grouped by combo (generator,
# clustering, algo, ...). Completion = `done` file present at the leaf.
#
# Output: pretty-printed summary. For each combo, shows "<done>/<total>"
# where <total> is the size of the network filter list (or the count of
# distinct networks seen on disk if no list is given).
#
# USAGE:
#   ./list_completed.sh [--mode {gen|cd-real|cd-syn}] \
#                       [--network-list <file>] \
#                       [--clustering-list <file>] \
#                       [--root <dir>] \
#                       [--show-missing]
#
# OPTIONS:
#   --mode <m>               : Restrict to one section (default: all three).
#   --networks <args...>     : Filter to these networks. Each arg is either a
#                              file path (read line-by-line) or a literal
#                              network ID. Concatenated and deduplicated.
#   --clusterings <names...> : Only show these clusterings (space-separated,
#                              consumed until the next --flag). For cd-real
#                              this filters <algo>; for gen this filters
#                              <clustering>; for cd-syn this filters
#                              <gt-clustering>.
#   --root <dir>             : Tree root (default: data).
#   --counts-only            : Suppress per-network done/missing lists; show
#                              only the <done>/<total> summary line.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common/state.sh"

log() {
    builtin echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

mode=""
networks_args=()
clusterings_args=()
root="data"
counts_only=0

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --mode) mode="$2"; shift 2 ;;
        --networks)
            shift
            while [[ "$#" -gt 0 && ! "$1" == --* ]]; do
                networks_args+=("$1"); shift
            done
            ;;
        --clusterings)
            shift
            while [[ "$#" -gt 0 && ! "$1" == --* ]]; do
                clusterings_args+=("$1"); shift
            done
            ;;
        --root) root="$2"; shift 2 ;;
        --counts-only) counts_only=1; shift ;;
        -*) echo "Unknown parameter: $1" >&2; exit 1 ;;
        *) echo "Unexpected argument: $1" >&2; exit 1 ;;
    esac
done

if [[ ! -d "${root}" ]]; then
    echo "Error: tree root '${root}' not found." >&2
    exit 1
fi

# ----- Load filters -----
declare -A net_filter
have_net_filter=0
net_total=0
networks_in_order=()
network_sources=()  # for the header line
if [[ ${#networks_args[@]} -gt 0 ]]; then
    have_net_filter=1
    add_net() {
        local n="$1"
        [[ -z "${n}" ]] && return
        if [[ -z "${net_filter[$n]}" ]]; then
            net_filter["${n}"]=1
            networks_in_order+=("${n}")
            net_total=$((net_total + 1))
        fi
    }
    for arg in "${networks_args[@]}"; do
        if [[ -f "${arg}" ]]; then
            network_sources+=("${arg}")
            while IFS= read -r line || [[ -n "${line}" ]]; do
                add_net "${line}"
            done < "${arg}"
        else
            network_sources+=("${arg}")
            add_net "${arg}"
        fi
    done
fi

declare -A clust_filter
have_clust_filter=0
if [[ ${#clusterings_args[@]} -gt 0 ]]; then
    have_clust_filter=1
    for c in "${clusterings_args[@]}"; do
        clust_filter["${c}"]=1
    done
fi

in_net_filter() {
    [[ "${have_net_filter}" -eq 0 ]] && return 0
    [[ -n "${net_filter[$1]}" ]]
}
in_clust_filter() {
    [[ "${have_clust_filter}" -eq 0 ]] && return 0
    [[ -n "${clust_filter[$1]}" ]]
}

# ----- Collect leaves into associative arrays keyed by combo -----
# Per combo, we accumulate a space-separated list of done networks.
declare -A gen_done       # key="<gen>|<clust>"     -> "net1 net2 ..."
declare -A cdreal_done    # key="<algo>"            -> "net1 net2 ..."
declare -A cdsyn_done     # key="<gen>|<gt>|<algo>" -> "net1 net2 ..."

if [[ -z "${mode}" || "${mode}" == "gen" ]]; then
    while IFS= read -r d; do
        net=$(basename "$(dirname "$(dirname "${d}")")")
        in_net_filter "${net}" || continue
        clust=$(basename "$(dirname "$(dirname "$(dirname "${d}")")")")
        in_clust_filter "${clust}" || continue
        gen=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "${d}")")")")")
        key="${gen}|${clust}"
        gen_done["${key}"]+="${net} "
    done < <(find "${root}/synthetic_networks/networks" -mindepth 5 -maxdepth 5 -name done -type f 2>/dev/null)
fi

if [[ -z "${mode}" || "${mode}" == "cd-real" ]]; then
    while IFS= read -r d; do
        net=$(basename "$(dirname "${d}")")
        in_net_filter "${net}" || continue
        a=$(basename "$(dirname "$(dirname "${d}")")")
        in_clust_filter "${a}" || continue
        cdreal_done["${a}"]+="${net} "
    done < <(find "${root}/reference_clusterings/clusterings" -mindepth 3 -maxdepth 3 -name done -type f 2>/dev/null)
fi

if [[ -z "${mode}" || "${mode}" == "cd-syn" ]]; then
    while IFS= read -r d; do
        net=$(basename "$(dirname "$(dirname "${d}")")")
        in_net_filter "${net}" || continue
        a=$(basename "$(dirname "$(dirname "$(dirname "${d}")")")")
        gt=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$(dirname "${d}")")")")")")
        in_clust_filter "${gt}" || continue
        gen=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$(dirname "$(dirname "${d}")")")")")")")
        key="${gen}|${gt}|${a}"
        cdsyn_done["${key}"]+="${net} "
    done < <(find "${root}/estimated_clusterings" -mindepth 7 -maxdepth 7 -path '*/clusterings/*' -name done -type f 2>/dev/null)
fi

# ----- Pretty print -----
list_label="all networks on disk"
if [[ "${have_net_filter}" -eq 1 ]]; then
    list_label="${network_sources[*]} (${net_total} unique networks)"
fi

count_done() {
    local s="$1"
    local arr=(${s})
    echo "${#arr[@]}"
}

# Print a comma-separated list of networks under a given label, wrapped to
# fit a soft column width. Indents continuation lines.
print_list() {
    local label="$1"; shift
    local items=("$@")
    if [[ ${#items[@]} -eq 0 ]]; then
        printf '      %s: (none)\n' "${label}"
        return
    fi
    local indent_label="      ${label}: "
    local indent_cont="$(printf '%*s' ${#indent_label} '')"
    local line="${indent_label}"
    local first_on_line=1
    local max_width=100
    for it in "${items[@]}"; do
        local sep=", "
        [[ "${first_on_line}" -eq 1 ]] && sep=""
        local candidate="${line}${sep}${it}"
        if [[ ${#candidate} -gt ${max_width} && "${first_on_line}" -ne 1 ]]; then
            printf '%s\n' "${line},"
            line="${indent_cont}${it}"
        else
            line="${candidate}"
        fi
        first_on_line=0
    done
    printf '%s\n' "${line}"
}

# Print done + missing for a combo. $1 is space-separated done network ids.
print_combo_detail() {
    [[ "${counts_only}" -eq 1 ]] && return
    local done_str="$1"
    local done_arr=()
    declare -A done_map
    for n in ${done_str}; do
        if [[ -z "${done_map[$n]}" ]]; then
            done_map["${n}"]=1
            done_arr+=("${n}")
        fi
    done
    if [[ "${have_net_filter}" -eq 1 ]]; then
        # Use input order; partition into done / missing.
        local d_in_order=() m_in_order=()
        for n in "${networks_in_order[@]}"; do
            if [[ -n "${done_map[$n]}" ]]; then
                d_in_order+=("${n}")
            else
                m_in_order+=("${n}")
            fi
        done
        print_list "done" "${d_in_order[@]}"
        print_list "missing" "${m_in_order[@]}"
    else
        # No filter: just sort and print done; missing is undefined.
        local sorted=()
        while IFS= read -r n; do sorted+=("${n}"); done < <(printf '%s\n' "${done_arr[@]}" | sort)
        print_list "done" "${sorted[@]}"
    fi
}

denom() {
    if [[ "${have_net_filter}" -eq 1 ]]; then echo "${net_total}"; else echo "?"; fi
}

echo "Root: ${root}"
echo "Networks: ${list_label}"
[[ "${have_clust_filter}" -eq 1 ]] && echo "Clusterings filter: ${clusterings_args[*]}"
echo

if [[ -z "${mode}" || "${mode}" == "gen" ]]; then
    echo "[gen]  generator / clustering"
    if [[ ${#gen_done[@]} -eq 0 ]]; then
        echo "  (none)"
    else
        for key in $(printf '%s\n' "${!gen_done[@]}" | sort); do
            gen="${key%%|*}"
            clust="${key#*|}"
            done_n=$(count_done "${gen_done[$key]}")
            printf '  %-12s  %-40s  %s/%s\n' "${gen}" "${clust}" "${done_n}" "$(denom)"
            print_combo_detail "${gen_done[$key]}"
        done
    fi
    echo
fi

if [[ -z "${mode}" || "${mode}" == "cd-real" ]]; then
    echo "[cd-real]  algo (= clustering)"
    if [[ ${#cdreal_done[@]} -eq 0 ]]; then
        echo "  (none)"
    else
        for a in $(printf '%s\n' "${!cdreal_done[@]}" | sort); do
            done_n=$(count_done "${cdreal_done[$a]}")
            printf '  %-40s  %s/%s\n' "${a}" "${done_n}" "$(denom)"
            print_combo_detail "${cdreal_done[$a]}"
        done
    fi
    echo
fi

if [[ -z "${mode}" || "${mode}" == "cd-syn" ]]; then
    echo "[cd-syn]  generator / gt-clustering / algo"
    if [[ ${#cdsyn_done[@]} -eq 0 ]]; then
        echo "  (none)"
    else
        for key in $(printf '%s\n' "${!cdsyn_done[@]}" | sort); do
            gen="${key%%|*}"
            rest="${key#*|}"
            gt="${rest%%|*}"
            a="${rest#*|}"
            done_n=$(count_done "${cdsyn_done[$key]}")
            printf '  %-12s  %-30s  %-25s  %s/%s\n' "${gen}" "${gt}" "${a}" "${done_n}" "$(denom)"
            print_combo_detail "${cdsyn_done[$key]}"
        done
    fi
    echo
fi
