# ==============================================================================
# Accuracy Metrics Visualizer (visualize_acc.py)
# ==============================================================================
# This script reads an aggregated accuracy CSV, filters the data based on
# specified generator/gt-clustering/algo methods, and outputs a summary CSV
# and a PDF of boxplots for the requested metrics.
#
# USAGE:
#   python visualize_acc.py [OPTIONS] --data-fp <file> --network-fp <file> \
#                           --output-dir <dir> --output-fn <name>
#
# REQUIRED ARGUMENTS (Group 1: Methods - Must be equal length):
#   --algos <algos...>           : List of algo IDs.
#   --names <names...>           : Display names for each algo.
#
# REQUIRED ARGUMENTS (Group 2: Metrics - Must be equal length):
#   --metrics <metrics...>       : List of metric IDs (e.g., ami ari nmi).
#   --metric-names <names...>    : Display names for each metric.
#
# REQUIRED ARGUMENTS (Group 3: Data):
#   --data-fp <file>             : Path to the aggregated accuracy CSV.
#   --network-fp <file>          : File containing the whitelist of network IDs.
#   --output-dir <dir>           : Directory to save outputs.
#   --output-fn <name>           : Base filename for outputs (without extension).
#
# OPTIONAL ARGUMENTS:
#   --hide-fliers                : Flag to hide outliers in the generated boxplots.
#   --xlim <lo> <hi>             : X-axis limits for the boxplots.
#
# EXAMPLES:
#   python visualize_acc.py \
#       --data-fp plots/cd_acc.csv \
#       --network-fp data/networks_val.txt \
#       --algos leiden-mod leiden-cpm-0.01 \
#       --names "Leiden-Mod" "Leiden-CPM(0.01)" \
#       --metrics ami ari nmi \
#       --metric-names AMI ARI NMI \
#       --output-dir plots/ --output-fn acc \
#       --xlim 0.0 1.0
# ==============================================================================

import argparse
import logging
import sys
from pathlib import Path
from typing import List, Optional

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

# --- Helper Functions ---


def q1(x):
    """Calculate the 25th percentile."""
    return x.quantile(0.25)


def q3(x):
    """Calculate the 75th percentile."""
    return x.quantile(0.75)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Visualize accuracy metrics from aggregated data."
    )
    parser.add_argument(
        "--data-fp",
        type=str,
        required=True,
        help="Path to the aggregated accuracy CSV.",
    )
    parser.add_argument(
        "--network-fp",
        type=str,
        required=True,
        help="File containing whitelist of network IDs.",
    )
    parser.add_argument(
        "--algos",
        nargs="+",
        required=True,
        help="List of algo IDs.",
    )
    parser.add_argument(
        "--names",
        nargs="+",
        required=True,
        help="Display names for each algo.",
    )
    parser.add_argument(
        "--metrics",
        nargs="+",
        required=True,
        help="List of metric IDs (e.g., ami ari nmi).",
    )
    parser.add_argument(
        "--metric-names",
        nargs="+",
        required=True,
        help="Display names for each metric.",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        required=True,
        help="Directory to save output plots and summaries.",
    )
    parser.add_argument(
        "--output-fn",
        type=str,
        required=True,
        help="Base filename for outputs (without extension).",
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
        help="X-axis limits for the boxplots.",
    )
    return parser.parse_args()


def get_common_networks_df(
    df: pd.DataFrame,
    methods: List[str],
    metrics: List[str],
    network_list: Optional[List[str]] = None,
) -> pd.DataFrame:
    """
    Filters the DataFrame to include only networks where ALL specified methods
    have valid (non-NaN) data for ALL metrics.
    """
    if network_list is not None:
        df = df[df["network_id"].isin(network_list)].copy()

    df_plot = df[df["Method"].isin(methods)].copy()

    valid_networks = []
    for net_id, group in df_plot.groupby("network_id"):
        if group["Method"].nunique() != len(methods):
            continue
        if group[metrics].isna().any().any():
            continue
        valid_networks.append(net_id)

    filtered_out = set(df_plot["network_id"].unique()) - set(valid_networks)
    if filtered_out:
        logger.info(
            f"Filtered out {len(filtered_out)} network(s) due to missing data: "
            f"{sorted(filtered_out)}"
        )
    else:
        logger.info(
            f"All {len(valid_networks)} networks retained (no filtering required)."
        )

    df_clean = df_plot[df_plot["network_id"].isin(valid_networks)].copy()
    df_clean["Method"] = pd.Categorical(
        df_clean["Method"], categories=methods, ordered=True
    )
    df_clean.sort_values("Method", inplace=True)

    return df_clean


def generate_summary_table(
    df_clean: pd.DataFrame,
    methods: List[str],
    metrics: List[str],
    metric_names: List[str],
    output_dir: Path,
    output_fn: str,
):
    """Generates a summary CSV containing standard statistics and 'count_best'."""
    logger.info(f"Generating Summary Table: summary_{output_fn}.csv")

    if df_clean.empty:
        logger.warning("Cleaned DataFrame is empty. Skipping summary generation.")
        return

    # A. Calculate Standard Stats
    # stats_stacked: index=(Method, stat_name), columns=metrics
    stats_stacked = df_clean.groupby("Method", observed=True)[metrics].agg(
        ["count", "min", q1, "median", q3, "max", "mean", "std"]
    ).stack(level=1, future_stack=True)

    # B. Calculate 'count_best' (higher is better for accuracy metrics)
    methods_idx = stats_stacked.index.get_level_values(0).unique()
    best_counts_df = pd.DataFrame(0, index=methods_idx, columns=metrics)

    for metric in metrics:
        pivoted = df_clean.pivot(index="network_id", columns="Method", values=metric)
        max_vals = pivoted.max(axis=1)
        is_best = pivoted.eq(max_vals, axis=0)
        best_counts_df[metric] = is_best.sum(axis=0)

    best_counts_df["Stat"] = "count_best"
    best_counts_df = best_counts_df.set_index("Stat", append=True)

    # C. Combine and save CSV (keep raw metric names as column headers)
    final_summary = pd.concat([stats_stacked, best_counts_df]).sort_index()

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"summary_{output_fn}.csv"
    final_summary.reset_index().to_csv(out_path, index=False)
    logger.info(f"Saved summary to {out_path}")


def plot_boxplots(
    df_clean: pd.DataFrame,
    metrics: List[str],
    metric_names: List[str],
    output_dir: Path,
    output_fn: str,
    hide_fliers: bool = False,
    xlim: Optional[tuple] = None,
):
    """Generates horizontal boxplots from a pre-cleaned DataFrame."""
    if df_clean.empty:
        logger.warning(f"DataFrame empty for plot {output_fn}. Skipping.")
        return

    logger.info(f"Generating Plot: {output_fn}.pdf")

    target_labels = df_clean["Method"].cat.categories.tolist()

    fig, axes = plt.subplots(
        nrows=1,
        ncols=len(metrics),
        figsize=(4 * len(metrics) + 2, len(target_labels) * 0.5 + 2),
        dpi=300,
        constrained_layout=True,
        sharey=True,
    )

    if len(metrics) == 1:
        axes = [axes]

    for idx, (metric, metric_name) in enumerate(zip(metrics, metric_names)):
        ax = axes[idx]

        ax.grid(True, which="major", axis="x", linestyle="--", color="lightgray")

        sns.boxplot(
            data=df_clean,
            x=metric,
            y="Method",
            ax=ax,
            order=target_labels,
            color="white",
            showmeans=True,
            showfliers=not hide_fliers,
            orient="h",
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

        if xlim:
            ax.set_xlim(*xlim)

        n_networks = df_clean["network_id"].nunique()
        ax.set_xlabel(f"{metric_name}\n({n_networks} networks)", fontsize=14)

        if idx == 0:
            ax.set_ylabel("Method", fontsize=14)
        else:
            ax.set_ylabel("")

        ax.tick_params(axis="x", labelsize=12)
        ax.tick_params(axis="y", labelsize=12)

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"{output_fn}.pdf"
    plt.savefig(out_path, bbox_inches="tight")
    logger.info(f"Saved plot to {out_path}")
    plt.close(fig)


# --- Main Execution ---

def main():
    args = parse_args()

    # 1. Validation
    if len(args.algos) != len(args.names):
        logger.critical("Arguments 'algos' and 'names' must have the same length.")
        sys.exit(1)

    if len(args.metrics) != len(args.metric_names):
        logger.critical("Arguments 'metrics' and 'metric-names' must have the same length.")
        sys.exit(1)

    # 2. Load data
    logger.info("Loading network whitelist and aggregated data...")
    network_list_path = Path(args.network_fp)
    if not network_list_path.exists():
        logger.critical(f"Network list file not found: {network_list_path}")
        sys.exit(1)

    with open(network_list_path, "r") as f:
        network_whitelist = [line.strip() for line in f if line.strip()]

    df_raw = pd.read_csv(args.data_fp)

    # 3. Map algo -> Method display name
    map_df = pd.DataFrame({"algo": args.algos, "Method": args.names})
    df_mapped = df_raw.merge(map_df, on="algo", how="inner")

    if df_mapped.empty:
        logger.warning(
            "No data found matching the provided algos."
        )
        sys.exit(0)

    # 3b. Derive complement columns for comp_fpr / comp_fnr if requested
    for comp, base in (("comp_fpr", "fpr"), ("comp_fnr", "fnr")):
        if comp in args.metrics:
            df_mapped[comp] = 1.0 - df_mapped[base]

    # 4. Filter to common networks with complete data
    df_clean = get_common_networks_df(
        df_mapped, args.names, args.metrics, network_whitelist
    )

    if df_clean.empty:
        logger.error("No valid networks remain after filtering. Exiting.")
        sys.exit(0)

    # 5. Output Generation
    output_dir = Path(args.output_dir)
    xlim = tuple(args.xlim) if args.xlim else None

    generate_summary_table(
        df_clean=df_clean,
        methods=args.names,
        metrics=args.metrics,
        metric_names=args.metric_names,
        output_dir=output_dir,
        output_fn=args.output_fn,
    )

    plot_boxplots(
        df_clean=df_clean,
        metrics=args.metrics,
        metric_names=args.metric_names,
        output_dir=output_dir,
        output_fn=args.output_fn,
        hide_fliers=args.hide_fliers,
        xlim=xlim,
    )

    logger.info("Processing complete.")


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent / "_common"))
    from pipeline_common import timed  # noqa: E402

    with timed("visualize_acc"):
        main()
