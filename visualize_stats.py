# ==============================================================================
# Clustering Stats Visualizer (plot_stats.py)
# ==============================================================================
# This script reads per-network stat files from a directory tree, aggregates
# the values across networks, and outputs a CSV and a PDF of boxplots for each
# requested stat, with one subplot per stat and one box per clustering method.
#
# USAGE:
#   python visualize_stats.py --root <dir> --networks_list <file> \
#                        --generator <name> --output <dir> \
#                        --clusterings <ids...> --clustering-names <names...> \
#                        --stats <ids...> --stat-names <names...>
#
# REQUIRED ARGUMENTS (Group 1: Clusterings - Must be equal length):
#   --clusterings <ids...>       : List of clustering resolution IDs.
#   --clustering-names <names...>: Display names for each clustering.
#
# REQUIRED ARGUMENTS (Group 2: Stats - Must be equal length):
#   --stats <ids...>             : List of stat IDs (e.g., node_coverage).
#   --stat-names <names...>      : Display names for each stat.
#
# REQUIRED ARGUMENTS (Group 3: Data):
#   --root <dir>                 : Root directory for data.
#   --networks_list <file>       : File containing the list of network IDs.
#   --generator <name>           : Generative model subfolder (e.g., ec-sbm-v2).
#   --output <dir>               : Directory to save outputs.
#
# OPTIONAL ARGUMENTS:
#   --hide-fliers                : Flag to hide outliers in the generated boxplots.
#   --xlim <lo> <hi>             : X-axis limits for all subplots.
#
# EXAMPLES:
#   python visualize_stats.py \
#       --root data/ \
#       --networks_list data/networks_val.txt \
#       --generator ec-sbm-v2 \
#       --clusterings leiden-cpm-0.1 sbm-flat-best+cc \
#       --clustering-names "Leiden-CPM(0.1)" "SBM+CC" \
#       --stats node_coverage ratio_wellconnected_clusters \
#       --stat-names "Node coverage" "Well-connected clusters" \
#       --xlim -0.1 1.1 \
#       --output plots/
# ==============================================================================

import argparse
import sys
import warnings
from pathlib import Path

import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt


import math


def read_single_float(filepath):
    if not filepath.exists():
        warnings.warn(f"File not found: {filepath}")
        return None
    with open(filepath, "r") as f:
        raw = f.read().strip()
    try:
        return float(raw)
    except ValueError:
        warnings.warn(f"Cannot parse float from {filepath}: {raw!r}")
        return None


def read_float_list(filepath):
    if not filepath.exists():
        warnings.warn(f"File not found: {filepath}")
        return None
    results = []
    with open(filepath, "r") as f:
        for i, line in enumerate(f):
            raw = line.strip()
            if not raw:
                continue
            try:
                results.append(float(raw))
            except ValueError:
                warnings.warn(
                    f"Cannot parse float at line {i + 1} of {filepath}: {raw!r}"
                )
                return None
    return results


def compute_ratio_wellconnected_clusters(stats_dir):
    ns = read_float_list(stats_dir / "n.txt")
    mincuts = read_float_list(stats_dir / "mincut.txt")
    if ns is None and mincuts is None:
        warnings.warn(f"Both n.txt and mincut.txt missing in {stats_dir}")
        return None
    elif ns is None:
        warnings.warn(f"n.txt missing in {stats_dir}")
        return None
    elif mincuts is None:
        warnings.warn(f"mincut.txt missing in {stats_dir}")
        return None
    assert len(ns) == len(mincuts), (
        f"Row count mismatch in {stats_dir}: "
        f"n.txt ({len(ns)}) vs mincut.txt ({len(mincuts)})"
    )
    if len(ns) == 0:
        warnings.warn(f"n.txt and mincut.txt are empty in {stats_dir}")
        return None
    n_well = sum(1 for n, mc in zip(ns, mincuts) if mc > math.log10(n))
    return n_well / len(ns)


FALLBACKS = {
    "ratio_wellconnected_clusters": compute_ratio_wellconnected_clusters,
}


def get_common_networks(df, stat, all_clusterings):
    """Keep only networks that have valid data for all clusterings."""
    valid_networks = []
    for network_id, group in df.groupby("network_id"):
        if group["clustering_res"].nunique() != len(all_clusterings):
            continue
        if group[stat].isna().any():
            continue
        valid_networks.append(network_id)

    filtered_out = set(df["network_id"].unique()) - set(valid_networks)
    if filtered_out:
        print(
            f"Filtered out {len(filtered_out)} network(s) missing data across clusterings: "
            f"{sorted(filtered_out)}"
        )
    else:
        print(f"All {len(valid_networks)} networks retained (no filtering required).")

    return df[df["network_id"].isin(valid_networks)].copy()


def get_stat_value(stat, stats_dir):
    stat_fp = stats_dir / f"{stat}.txt"
    if stat_fp.exists():
        return read_single_float(stat_fp)

    if stat in FALLBACKS:
        return FALLBACKS[stat](stats_dir)

    warnings.warn(
        f"{stat}.txt not found and no fallback defined for {stat!r} in {stats_dir}"
    )
    return None


def parse_args():
    parser = argparse.ArgumentParser(
        description="Plot cluster coverage and connectivity stats."
    )
    parser.add_argument(
        "--root", type=str, required=True, help="Root directory for data"
    )
    parser.add_argument(
        "--networks_list", type=str, required=True, help="File with list of network IDs"
    )
    parser.add_argument(
        "--generator",
        type=str,
        required=True,
        help="Generative model subfolder (e.g., ec-sbm-v2)",
    )
    parser.add_argument("--output", type=str, required=True, help="Output folder")
    parser.add_argument(
        "--clusterings", nargs="+", required=True, help="Clustering resolution IDs"
    )
    parser.add_argument(
        "--clustering-names",
        nargs="+",
        required=True,
        help="Display names for each clustering",
    )
    parser.add_argument("--stats", nargs="+", required=True, help="Stat IDs to plot")
    parser.add_argument(
        "--stat-names", nargs="+", required=True, help="Display names for each stat"
    )
    parser.add_argument(
        "--hide-fliers",
        action="store_true",
        help="Hide outliers in the boxplots.",
    )
    parser.add_argument(
        "--xlim",
        nargs=2,
        type=float,
        metavar=("LO", "HI"),
        default=None,
        help="X-axis limits for all subplots",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    if len(args.clusterings) != len(args.clustering_names):
        print(
            "Arguments '--clusterings' and '--clustering-names' must have the same length.",
            file=sys.stderr,
        )
        sys.exit(1)

    if len(args.stats) != len(args.stat_names):
        print(
            "Arguments '--stats' and '--stat-names' must have the same length.",
            file=sys.stderr,
        )
        sys.exit(1)

    root = Path(args.root)
    output_fp = Path(args.output)
    output_fp.mkdir(parents=True, exist_ok=True)

    with open(args.networks_list) as f:
        network_ids = [line.strip() for line in f if line.strip()]

    clustering_name_map = dict(zip(args.clusterings, args.clustering_names))
    all_clustering_names = args.clustering_names
    selected_stats = list(zip(args.stats, args.stat_names))

    n_clusterings = len(all_clustering_names)
    fig, axes = plt.subplots(
        1,
        len(selected_stats),
        figsize=(4 * len(selected_stats) + 2, n_clusterings * 0.5 + 2),
        dpi=300,
        constrained_layout=True,
        sharey=True,
    )
    if len(selected_stats) == 1:
        axes = [axes]

    active_axes = []
    for ax, (stat, stat_name) in zip(axes, selected_stats):
        stat_values = []

        for clustering_res, name in clustering_name_map.items():
            for network_id in network_ids:
                stats_dir = (
                    root
                    / "stats"
                    / args.generator
                    / clustering_res
                    / network_id
                    / "0"
                    / "cluster"
                )

                if not stats_dir.exists():
                    print(f"Directory not found: {stats_dir}")
                    continue

                val = get_stat_value(stat, stats_dir)
                if val is not None:
                    stat_values.append((network_id, clustering_res, val))
                else:
                    print(f"Missing data for {stat} in {stats_dir}")

        if not stat_values:
            print(f"No data collected for {stat}. Skipping plot.")
            ax.set_visible(False)
            continue

        active_axes.append(ax)
        df = pd.DataFrame(stat_values, columns=["network_id", "clustering_res", stat])
        df = get_common_networks(df, stat, args.clusterings)
        df["clustering_name"] = df["clustering_res"].map(clustering_name_map)

        # Ensure all clusterings appear on y-axis even if they have no data
        present_names = set(df["clustering_name"])
        missing_names = [n for n in all_clustering_names if n not in present_names]
        if missing_names:
            padding = pd.DataFrame(
                {
                    "network_id": [None] * len(missing_names),
                    "clustering_res": [None] * len(missing_names),
                    stat: [float("nan")] * len(missing_names),
                    "clustering_name": missing_names,
                }
            )
            df = pd.concat([df, padding], ignore_index=True)

        df["clustering_name"] = pd.Categorical(
            df["clustering_name"], categories=all_clustering_names, ordered=True
        )
        df = df.sort_values("clustering_name")
        df.to_csv(output_fp / f"{stat}.csv", index=False)

        ax.grid(True, which="major", axis="x", linestyle="--", color="lightgray")

        sns.boxplot(
            y="clustering_name",
            x=stat,
            data=df,
            ax=ax,
            order=all_clustering_names,
            orient="h",
            color="white",
            showmeans=True,
            showfliers=not args.hide_fliers,
            boxprops={"edgecolor": "black", "linewidth": 1.5},
            whiskerprops={"color": "black", "linewidth": 1.5},
            capprops={"color": "black", "linewidth": 1.5},
            medianprops={"color": "red", "linewidth": 1},
            meanprops={
                "marker": "^",
                "markerfacecolor": "green",
                "markeredgecolor": "green",
                "markersize": 5,
            },
            flierprops={
                "marker": "o",
                "markerfacecolor": "black",
                "markeredgecolor": "black",
                "markersize": 3,
            },
        )

        n_networks = df["network_id"].nunique()

        if args.xlim:
            ax.set_xlim(*args.xlim)
        ax.set_xlabel(f"{stat_name}\n({n_networks} networks)", fontsize=14)
        ax.set_ylabel("")
        ax.tick_params(axis="x", labelsize=12)
        ax.tick_params(axis="y", labelsize=12)

    if active_axes:
        active_axes[0].set_ylabel("Input clustering", fontsize=14)

    plt.savefig(output_fp / "combined_stats.pdf", bbox_inches="tight")


if __name__ == "__main__":
    main()
