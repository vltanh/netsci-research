# ==============================================================================
# Clustering Stats Visualizer (plot_stats.py)
# ==============================================================================
# This script reads per-network stat files from a directory tree, aggregates
# the values across networks, and outputs a CSV and a PDF of boxplots for each
# requested stat, with one subplot per stat and one box per clustering method.
#
# USAGE:
#   python visualize_stats.py \
#       --path-template <template> \
#       --network-axis <name> --networks-list <file> \
#       --method-axis <name> --methods <ids...> --method-names <names...> \
#       [--set KEY=VALUE ...] \
#       --stats <ids...> --stat-names <names...> \
#       --output <dir>
#
# REQUIRED ARGUMENTS:
#   --path-template <tmpl>       : Template for the stats directory, with
#                                  {placeholders}. Two are iterators (see
#                                  --network-axis, --method-axis); the rest
#                                  are bound via --set KEY=VALUE.
#   --network-axis <name>        : Placeholder iterated over networks.
#   --networks-list <file>       : File with values for the network-axis placeholder.
#   --method-axis <name>         : Placeholder iterated over methods (y-axis).
#   --methods <ids...>           : Values for the method-axis placeholder.
#   --method-names <names...>    : Display names for each method.
#   --stats <ids...>             : List of stat IDs (e.g., node_coverage).
#   --stat-names <names...>      : Display names for each stat.
#   --output <dir>               : Directory to save outputs.
#
# OPTIONAL ARGUMENTS:
#   --set KEY=VALUE              : Bind a scalar to a template placeholder. Repeatable.
#   --hide-fliers                : Hide outliers in the generated boxplots.
#   --xlim <lo> <hi>             : X-axis limits for all subplots.
#   --plot-name <name>           : Base name for the output plot file.
#
# EXAMPLES:
#   python visualize_stats.py \
#       --path-template "data/stats/{generator}/{clustering}/{network}/0/cluster" \
#       --network-axis network --networks-list data/networks_val.txt \
#       --method-axis clustering \
#       --methods leiden-cpm-0.1 sbm-flat-best+cc \
#       --method-names "Leiden-CPM(0.1)" "SBM+CC" \
#       --set generator=ec-sbm-v2 \
#       --stats node_coverage ratio_wellconnected_clusters \
#       --stat-names "Node coverage" "Well-connected clusters" \
#       --xlim -0.1 1.1 \
#       --output plots/
# ==============================================================================

import argparse
import sys
import warnings
from pathlib import Path
from string import Formatter

import numpy as np
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
    ns = _cached_float_list(stats_dir, "n.txt")
    mincuts = _cached_float_list(stats_dir, "mincut.txt")
    if ns is None or mincuts is None:
        return None
    assert len(ns) == len(mincuts), (
        f"Row count mismatch in {stats_dir}: "
        f"n.txt ({len(ns)}) vs mincut.txt ({len(mincuts)})"
    )
    n_well = sum(1 for n, mc in zip(ns, mincuts) if mc > math.log10(n))
    return n_well / len(ns)


_FLOAT_LIST_CACHE = {}


def _cached_float_list(stats_dir, filename):
    key = (str(stats_dir), filename)
    if key in _FLOAT_LIST_CACHE:
        return _FLOAT_LIST_CACHE[key]
    values = read_float_list(stats_dir / filename)
    if values is None:
        warnings.warn(f"{filename} missing in {stats_dir}")
    elif len(values) == 0:
        warnings.warn(f"{filename} is empty in {stats_dir}")
        values = None
    _FLOAT_LIST_CACHE[key] = values
    return values


def _read_cluster_sizes(stats_dir):
    return _cached_float_list(stats_dir, "n.txt")


def compute_small_cluster_coverage(stats_dir, threshold=100):
    ns = _read_cluster_sizes(stats_dir)
    if ns is None:
        return None
    n_small = sum(n for n in ns if n < threshold)
    total_nodes = sum(ns)
    if total_nodes == 0:
        warnings.warn(f"No nodes found in {stats_dir}")
        return None
    return n_small / total_nodes


# Scalar fallbacks: <stat>.txt not on disk, but a single value can be derived.
FALLBACKS = {
    "ratio_wellconnected_clusters": compute_ratio_wellconnected_clusters,
    "small_cluster_coverage": compute_small_cluster_coverage,
}


# Aggregators over a per-cluster list. "pooled" is special: it returns the list
# itself, so every cluster becomes a point in the boxplot.
AGGREGATORS = {
    "min": lambda xs: float(min(xs)),
    "max": lambda xs: float(max(xs)),
    "mean": lambda xs: float(np.mean(xs)),
    "median": lambda xs: float(np.median(xs)),
    "q1": lambda xs: float(np.percentile(xs, 25)),
    "q3": lambda xs: float(np.percentile(xs, 75)),
    "pooled": lambda xs: [float(x) for x in xs],
}

POOLED_AGGREGATORS = {"pooled"}


# Bases whose values are log-scale-natural; all aggregators inherit.
# A base is the <base> part of "<base>:<agg>", i.e. the filename stem of
# the per-cluster values file (e.g. "n" for n.txt).
LOG_SCALE_BASES = {"n"}

# Individual scalar stats (no base/aggregator split) that should be log-scale.
LOG_SCALE_STATS = set()


def _split_stat(stat):
    if ":" not in stat:
        return None, None
    base, agg = stat.split(":", 1)
    return base, agg


def use_log_scale(stat):
    base, _ = _split_stat(stat)
    if base is not None and base in LOG_SCALE_BASES:
        return True
    return stat in LOG_SCALE_STATS


def is_pooled_stat(stat):
    _, agg = _split_stat(stat)
    return agg in POOLED_AGGREGATORS


def get_common_networks(df, stat, all_methods):
    """Keep only networks that have valid data for all methods."""
    valid_networks = []
    for network_id, group in df.groupby("network_id"):
        if group["method_id"].nunique() != len(all_methods):
            continue
        if group[stat].isna().any():
            continue
        valid_networks.append(network_id)

    filtered_out = set(df["network_id"].unique()) - set(valid_networks)
    if filtered_out:
        print(
            f"Filtered out {len(filtered_out)} network(s) missing data across methods: "
            f"{sorted(filtered_out)}"
        )
    else:
        print(f"All {len(valid_networks)} networks retained (no filtering required).")

    return df[df["network_id"].isin(valid_networks)].copy()


def get_stat_value(stat, stats_dir):
    base, agg = _split_stat(stat)
    if base is not None:
        if agg not in AGGREGATORS:
            warnings.warn(f"Unknown aggregator {agg!r} in {stat!r}")
            return None
        xs = _cached_float_list(stats_dir, f"{base}.txt")
        if xs is None:
            return None
        return AGGREGATORS[agg](xs)

    stat_fp = stats_dir / f"{stat}.txt"
    if stat_fp.exists():
        return read_single_float(stat_fp)

    if stat in FALLBACKS:
        return FALLBACKS[stat](stats_dir)

    warnings.warn(
        f"{stat}.txt not found and no fallback defined for {stat!r} in {stats_dir}"
    )
    return None


def _parse_set_kv(value):
    if "=" not in value:
        raise argparse.ArgumentTypeError(
            f"--set expects KEY=VALUE, got {value!r}"
        )
    key, val = value.split("=", 1)
    if not key:
        raise argparse.ArgumentTypeError(f"--set has empty key in {value!r}")
    return key, val


def parse_args():
    parser = argparse.ArgumentParser(
        description="Plot cluster coverage and connectivity stats."
    )
    parser.add_argument("--output", type=str, required=True, help="Output folder")
    parser.add_argument(
        "--path-template",
        type=str,
        required=True,
        help="Template for the stats directory path, with {placeholders}. "
        "Two of them must be the network and method iterators (see "
        "--network-axis / --method-axis); any remaining placeholders are "
        "scalar values supplied via --set KEY=VALUE.",
    )
    parser.add_argument(
        "--network-axis",
        type=str,
        required=True,
        help="Name of the placeholder in --path-template that iterates over networks.",
    )
    parser.add_argument(
        "--networks-list",
        type=str,
        required=True,
        help="File with list of values for the network-axis placeholder.",
    )
    parser.add_argument(
        "--method-axis",
        type=str,
        required=True,
        help="Name of the placeholder in --path-template that iterates over methods (y-axis).",
    )
    parser.add_argument(
        "--methods",
        nargs="+",
        required=True,
        help="Values for the method-axis placeholder.",
    )
    parser.add_argument(
        "--method-names",
        nargs="+",
        required=True,
        help="Display names for each method.",
    )
    parser.add_argument(
        "--set",
        dest="set_values",
        action="append",
        default=[],
        type=_parse_set_kv,
        metavar="KEY=VALUE",
        help="Bind a scalar value to a template placeholder. Repeatable.",
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
    parser.add_argument(
        "--plot-name",
        type=str,
        default="combined_stats",
        help="Base name for the output plot file (default: combined_stats)",
    )
    return parser.parse_args()


def _template_placeholders(template):
    return {name for _, name, _, _ in Formatter().parse(template) if name}


def main():
    args = parse_args()

    if len(args.methods) != len(args.method_names):
        print(
            "Arguments '--methods' and '--method-names' must have the same length.",
            file=sys.stderr,
        )
        sys.exit(1)

    if len(args.stats) != len(args.stat_names):
        print(
            "Arguments '--stats' and '--stat-names' must have the same length.",
            file=sys.stderr,
        )
        sys.exit(1)

    placeholders = _template_placeholders(args.path_template)
    scalar_values = dict(args.set_values)

    for axis_flag, axis_name in [
        ("--network-axis", args.network_axis),
        ("--method-axis", args.method_axis),
    ]:
        if axis_name not in placeholders:
            print(
                f"{axis_flag} {axis_name!r} is not a placeholder in --path-template.",
                file=sys.stderr,
            )
            sys.exit(1)

    if args.network_axis == args.method_axis:
        print("--network-axis and --method-axis must differ.", file=sys.stderr)
        sys.exit(1)

    iter_axes = {args.network_axis, args.method_axis}
    required_scalars = placeholders - iter_axes
    missing_scalars = required_scalars - scalar_values.keys()
    if missing_scalars:
        print(
            f"Missing --set bindings for template placeholders: {sorted(missing_scalars)}",
            file=sys.stderr,
        )
        sys.exit(1)
    extra_scalars = scalar_values.keys() - placeholders
    if extra_scalars:
        print(
            f"--set bindings reference placeholders not in --path-template: "
            f"{sorted(extra_scalars)}",
            file=sys.stderr,
        )
        sys.exit(1)

    output_fp = Path(args.output)
    output_fp.mkdir(parents=True, exist_ok=True)

    with open(args.networks_list) as f:
        network_ids = [line.strip() for line in f if line.strip()]

    method_name_map = dict(zip(args.methods, args.method_names))
    all_method_names = args.method_names
    selected_stats = list(zip(args.stats, args.stat_names))

    n_methods = len(all_method_names)
    fig, axes = plt.subplots(
        1,
        len(selected_stats),
        figsize=(4 * len(selected_stats) + 2, n_methods * 0.5 + 2),
        dpi=300,
        constrained_layout=True,
        sharey=True,
    )
    if len(selected_stats) == 1:
        axes = [axes]

    active_axes = []
    for ax, (stat, stat_name) in zip(axes, selected_stats):
        stat_values = []

        for method_id in args.methods:
            for network_id in network_ids:
                fmt_kwargs = dict(scalar_values)
                fmt_kwargs[args.method_axis] = method_id
                fmt_kwargs[args.network_axis] = network_id
                stats_dir = Path(args.path_template.format(**fmt_kwargs))

                if not stats_dir.exists():
                    print(f"Directory not found: {stats_dir}")
                    continue

                val = get_stat_value(stat, stats_dir)
                if val is None:
                    print(f"Missing data for {stat} in {stats_dir}")
                elif is_pooled_stat(stat):
                    for v in val:
                        stat_values.append((network_id, method_id, float(v)))
                else:
                    stat_values.append((network_id, method_id, val))

        if not stat_values:
            print(f"No data collected for {stat}. Skipping plot.")
            ax.set_visible(False)
            continue

        active_axes.append(ax)
        df = pd.DataFrame(stat_values, columns=["network_id", "method_id", stat])
        df = get_common_networks(df, stat, args.methods)
        df["method_name"] = df["method_id"].map(method_name_map)

        # Ensure all methods appear on y-axis even if they have no data
        present_names = set(df["method_name"])
        missing_names = [n for n in all_method_names if n not in present_names]
        if missing_names:
            padding = pd.DataFrame(
                {
                    "network_id": [None] * len(missing_names),
                    "method_id": [None] * len(missing_names),
                    stat: [float("nan")] * len(missing_names),
                    "method_name": missing_names,
                }
            )
            df = pd.concat([df, padding], ignore_index=True)

        df["method_name"] = pd.Categorical(
            df["method_name"], categories=all_method_names, ordered=True
        )
        df = df.sort_values("method_name")
        df.to_csv(output_fp / f"{stat}.csv", index=False)

        ax.grid(True, which="major", axis="x", linestyle="--", color="lightgray")

        sns.boxplot(
            y="method_name",
            x=stat,
            data=df,
            ax=ax,
            order=all_method_names,
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

        if use_log_scale(stat):
            ax.set_xscale("log")
        if args.xlim:
            ax.set_xlim(*args.xlim)
        ax.set_xlabel(f"{stat_name}\n({n_networks} networks)", fontsize=14)
        ax.set_ylabel("")
        ax.tick_params(axis="x", labelsize=12)
        ax.tick_params(axis="y", labelsize=12)

    if active_axes:
        active_axes[0].set_ylabel(args.method_axis, fontsize=14)

    plt.savefig(output_fp / f"{args.plot_name}.pdf", bbox_inches="tight")


if __name__ == "__main__":
    main()
