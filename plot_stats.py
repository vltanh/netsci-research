import argparse
from pathlib import Path

import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

CLUSTERING_RESOLUTION_NAMES = {
    "leiden-cpm-0.1": "Leiden-CPM(0.1)",
    "leiden-cpm-0.1+cm(log)": "Leiden-CPM(0.1)+CM(log)",
    "sbm-flat-best+cc": "SBM+CC",
    "sbm-flat-best+wcc(log)": "SBM+WCC(log)",
}

STATS = [
    ("node_coverage", "Node coverage"),
    ("ratio_wellconnected_clusters", "Proportion of well-connected clusters"),
]

def read_single_float(filepath):
    """Helper to read a single float value from a text file."""
    if not filepath.exists():
        return None
    with open(filepath, 'r') as f:
        return float(f.read().strip())

def get_stat_value(stat, stats_dir):
    if stat == "node_coverage":
        return read_single_float(stats_dir / "node_coverage.txt")
    
    elif stat == "ratio_wellconnected_clusters":
        n_well = read_single_float(stats_dir / "n_wellconnected_clusters.txt")
        n_total = read_single_float(stats_dir / "n_clusters.txt")
        if n_well is not None and n_total is not None and n_total > 0:
            return n_well / n_total
        return None
        
    raise ValueError(f"Unknown stat {stat}")

def main():
    parser = argparse.ArgumentParser(description="Plot cluster coverage and connectivity stats.")
    parser.add_argument("--root", type=str, required=True, help="Root directory for data")
    parser.add_argument("--networks_list", type=str, default="data/networks_val.txt", help="File with list of network IDs")
    parser.add_argument("--network_model", type=str, default="ec-sbm-v2", help="Generative model or subfolder (e.g., ec-sbm-v2)")
    parser.add_argument("--output", type=str, required=True, help="Output folder")
    args = parser.parse_args()

    root = Path(args.root)
    output_fp = Path(args.output)
    output_fp.mkdir(parents=True, exist_ok=True)

    with open(args.networks_list) as f:
        network_ids = [line.strip() for line in f if line.strip()]

    fig, axes = plt.subplots(len(STATS), 1, figsize=(12, 4 * len(STATS)), dpi=300)
    if len(STATS) == 1:
        axes = [axes]

    for i, (ax, (stat, stat_name)) in enumerate(zip(axes, STATS)):
        stat_values = []

        for clustering_res, name in CLUSTERING_RESOLUTION_NAMES.items():
            for network_id in network_ids:
                # Target: data/synthetic_networks/stats/<method>/<clustering>/<network_id>/0/cluster/
                stats_dir = root / "synthetic_networks" / "stats" / args.network_model / clustering_res / network_id / "0" / "cluster"
                
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
            continue

        df = pd.DataFrame(stat_values, columns=["network_id", "clustering_res", stat])
        df["clustering_name"] = df["clustering_res"].map(CLUSTERING_RESOLUTION_NAMES)
        df.to_csv(output_fp / f"{stat}.csv", index=False)

        sns.set_theme(style="whitegrid")
        sns.boxplot(
            x="clustering_name",
            y=stat,
            data=df,
            ax=ax,
            showmeans=True,
            color="lightblue",
            fliersize=2,
            medianprops={"color": "red", "linewidth": 2, "alpha": 0.7},
        )
        
        ax.grid(True, axis="y", linestyle="--", alpha=0.7)
        if i != len(STATS) - 1:
            ax.set_xticklabels([])
            ax.set_xlabel("")
        else:
            ax.set_xlabel("Input clustering")
        
        if stat in ["node_coverage", "ratio_wellconnected_clusters"]:
            ax.set_ylim(-0.1, 1.1)
        ax.set_ylabel(stat_name)

    plt.tight_layout()
    plt.savefig(output_fp / "combined_stats.pdf", bbox_inches="tight")

if __name__ == "__main__":
    main()