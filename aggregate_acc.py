# ==============================================================================
# Accuracy Metrics Aggregator (aggregate_acc.py)
# ==============================================================================
# This script searches through a structured directory of estimated clusterings,
# aggregates individual accuracy metric files using multiprocessing,
# and compiles them into a single master CSV. It also generates a completion
# summary identifying missing network replicates.
#
# EXPECTED FILE STRUCTURE:
#   <base_dir> / <generator> / <gt_clustering> / acc / <algo> / <network_id> / <run_id> / result.<metric>
#
# USAGE:
#   python aggregate_acc.py [OPTIONS] --base-dir <dir> --network-list <file> \
#                           --output <file> --generator <gen> \
#                           --gt-clustering <cluster> --algos <algos...>
#
# REQUIRED ARGUMENTS:
#   --base-dir <dir>         : Base directory containing the generated clusterings.
#   --network-list <file>    : File containing the list of network IDs to process.
#   --output <file>          : Output path for the aggregated data CSV.
#   --generator <str>        : Synthesis method (e.g., ec-sbm-v2).
#   --gt-clustering <str>    : Synthesis empirical clustering (e.g., sbm-flat-best+cc).
#   --algos <algos...>       : Clustering algorithms to collect (e.g., leiden-mod leiden-cpm-0.1).
#
# OPTIONAL ARGUMENTS:
#   --metrics <metrics...>   : Accuracy metrics to collect (default: ami ari nmi f1_score
#                              fnr fpr precision recall node_coverage).
#   --run-id <str>           : Run ID (default: 0).
#   --n-procs <int>          : Number of CPU processes for data aggregation (default: 16).
#
# EXAMPLES:
#   python aggregate_acc.py \
#       --base-dir data/estimated_clusterings/ \
#       --output plots/cd_acc.csv \
#       --network-list data/networks_val.txt \
#       --generator ec-sbm-v2 \
#       --gt-clustering sbm-flat-best+cc \
#       --algos leiden-mod leiden-cpm-0.1 leiden-cpm-0.01 \
#       --metrics ami ari nmi
# ==============================================================================

import argparse
import logging
import sys
import textwrap
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List

import pandas as pd
from tqdm import tqdm

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

# --- Constants ---

DEFAULT_METRICS = [
    "ami",
    "ari",
    "nmi",
    "f1_score",
    "fnr",
    "fpr",
    "precision",
    "recall",
    "node_coverage",
]

# --- Helper Functions ---


def parse_args():
    parser = argparse.ArgumentParser(
        description="Process graph clustering accuracy metrics and generate CSV."
    )
    parser.add_argument(
        "--base-dir",
        type=str,
        required=True,
        help="Base directory containing the generated clusterings",
    )
    parser.add_argument(
        "--network-list",
        type=str,
        required=True,
        help="File containing network IDs",
    )
    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="Path to save output CSV",
    )
    parser.add_argument(
        "--generator",
        type=str,
        required=True,
        help="Synthesis method",
    )
    parser.add_argument(
        "--gt-clustering",
        type=str,
        required=True,
        help="Synthesis empirical clustering",
    )
    parser.add_argument(
        "--algos",
        nargs="+",
        required=True,
        help="Clustering algorithms to collect",
    )
    parser.add_argument(
        "--metrics",
        nargs="+",
        default=DEFAULT_METRICS,
        help="Accuracy metrics to collect (default: ami ari nmi f1_score fnr fpr precision recall node_coverage)",
    )
    parser.add_argument(
        "--run-id",
        type=str,
        default="0",
        help="Run ID",
    )
    parser.add_argument(
        "--n-procs",
        type=int,
        default=16,
        help="Number of processes to use",
    )
    return parser.parse_args()


def _process_task(args: tuple) -> Dict[str, Any]:
    """
    Worker function to process a single network_id and algorithm combination.
    """
    (
        network_id,
        algo,
        base_dir,
        generator,
        gt_clustering,
        run_id,
        metrics_list,
    ) = args

    # Expected format: base_dir/<generator>/<gt-clustering>/acc/<algo>/<net-id>/<run-id>/result.<metric>
    acc_path = (
        base_dir / generator / gt_clustering / "acc" / algo / network_id / str(run_id)
    )

    row_data = {
        "network_id": network_id,
        "generator_id": generator,
        "gt_clustering_id": gt_clustering,
        "algo": algo,
    }

    # --- Read Accuracy Metrics ---
    for metric in metrics_list:
        metric_file = acc_path / f"result.{metric}"
        try:
            if metric_file.exists():
                raw = metric_file.read_text().strip()
                row_data[metric] = float(raw) if raw else None
            else:
                row_data[metric] = None
        except (ValueError, OSError):
            row_data[metric] = None

    return row_data


def collect_dataframe(
    network_ids: List[str],
    algos: List[str],
    base_dir: Path,
    generator: str,
    gt_clustering: str,
    run_id: str,
    metrics: List[str],
    max_workers: int = 8,
) -> pd.DataFrame:

    tasks = []
    for network_id in network_ids:
        for algo in algos:
            tasks.append(
                (
                    network_id,
                    algo,
                    base_dir,
                    generator,
                    gt_clustering,
                    run_id,
                    metrics,
                )
            )

    logger.info(
        f"Starting data collection for {len(tasks)} tasks using {max_workers} workers."
    )

    df_data = []
    with ProcessPoolExecutor(max_workers=max_workers) as executor:
        future_to_task = {executor.submit(_process_task, task): task for task in tasks}

        for future in tqdm(
            as_completed(future_to_task),
            total=len(tasks),
            desc="Processing Metrics",
            unit="file",
        ):
            try:
                result = future.result()
                if result:
                    df_data.append(result)
            except Exception as e:
                task_info = future_to_task[future]
                logger.error(
                    f"Task failed for Net: {task_info[0]}, Algo: {task_info[1]}. Error: {e}"
                )

    if not df_data:
        logger.error("No data collected. Please check paths and inputs.")
        return pd.DataFrame()

    logger.info(f"Collected {len(df_data)} records. Formatting DataFrame...")

    df = pd.DataFrame(df_data)
    df["algo"] = pd.Categorical(df["algo"], categories=algos, ordered=True)
    df = df.sort_values(by=["network_id", "algo"]).reset_index(drop=True)

    return df


def print_completion_summary(
    df: pd.DataFrame, all_networks: List[str], algos: List[str], metrics: List[str]
):
    """
    Groups completion by algo and lists missing networks in a formatted output.
    """
    logger.info("Computing completion statistics...")
    total_expected = len(all_networks)
    expected_set = set(all_networks)

    print("\n" + "=" * 80)
    print(f"COMPLETION SUMMARY (Total Expected Networks per Algo: {total_expected})")
    print("=" * 80)

    for algo in algos:
        if df.empty:
            finished_set = set()
        else:
            finished_df = df.dropna(subset=metrics)
            subset = finished_df[finished_df["algo"] == algo]
            finished_set = set(subset["network_id"].unique())

        missing_set = expected_set - finished_set
        missing_list = sorted(list(missing_set))

        count_str = f"{len(finished_set)}/{total_expected}"
        print(f"  Algo: {algo:<35} | Count: {count_str}")

        if missing_list:
            prefix = "    Missing: "
            wrapper = textwrap.TextWrapper(
                initial_indent=prefix,
                subsequent_indent=" " * len(prefix),
                width=80,
            )
            print(wrapper.fill(", ".join(missing_list)))

    print("\n" + "=" * 80 + "\n")


# --- Main Execution ---

if __name__ == "__main__":
    args = parse_args()

    base_dir = Path(args.base_dir)
    output_fn = Path(args.output)
    output_dir = output_fn.parent
    output_dir.mkdir(parents=True, exist_ok=True)

    network_list_path = Path(args.network_list)
    if not network_list_path.exists():
        logger.critical(f"Network list file not found: {network_list_path}")
        sys.exit(1)

    with open(network_list_path, "r") as f:
        network_ids = [line.strip() for line in f.readlines() if line.strip()]

    logger.info("Collecting new data...")
    df = collect_dataframe(
        network_ids=network_ids,
        algos=args.algos,
        base_dir=base_dir,
        generator=args.generator,
        gt_clustering=args.gt_clustering,
        run_id=args.run_id,
        metrics=args.metrics,
        max_workers=args.n_procs,
    )

    if not df.empty:
        df.to_csv(output_fn, index=False)
        logger.info(f"Data saved to {output_fn}")

    # Print Global Completion Summary even if dataframe is empty (will show 0/N for all)
    print_completion_summary(
        df=df,
        all_networks=network_ids,
        algos=args.algos,
        metrics=args.metrics,
    )

    logger.info("Processing complete.")
