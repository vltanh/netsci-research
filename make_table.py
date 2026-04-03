import pandas as pd
import numpy as np
import argparse
import sys

# ---------------------------------------------------------
# 1. Configuration
# ---------------------------------------------------------

METHOD_ORDER = [
    "Leiden-CPM(0.1)",
    "Leiden-CPM(0.01)",
    "Leiden-CPM(0.001)",
    "Leiden-CPM(0.0001)",
    "Leiden-Mod",
    "Infomap",
    "IKC(1)",
    "IKC(2)",
    "IKC(5)",
    "IKC(10)",
    "IKC(20)",
]

POST_PROC_ORDER = [
    "None",
    "+CC",
    "+WCC(log)",
    "+CM(log)",
]

METRIC_MAP = [
    ("ami", "AMI"),
    ("ari", "ARI"),
    ("nmi", "NMI"),
    ("f1_score", "F1"),
    ("comp_fpr", "Specificity"),
    ("precision", "Precision"),
    ("recall", "Recall"),
    ("node_coverage", "Node Coverage"),
]

# Mapping internal dataframe names to LaTeX Headers
STAT_DISPLAY_MAP = {
    "mean": "Avg",
    "median": "Med",
    "std": "Std",
    "count_best": "\\# best",
    "min": "Min",
    "max": "Max",
}

# Stats that should trigger highlighting logic (Max is Best)
HIGHLIGHT_STATS = [
    "mean",
    "median",
    "f1_score",
    "precision",
    "recall",
    "ami",
    "ari",
    "nmi",
    "node_coverage",
]

# ---------------------------------------------------------
# 2. Helpers
# ---------------------------------------------------------


def parse_method(name):
    for suffix in POST_PROC_ORDER:
        if name.endswith(suffix):
            return name[: -len(suffix)], suffix
    return name, "None"


def format_value(val, stat_name, is_global, is_group, show_group_best):
    r"""
    Formats the LaTeX string.
    - Global best: \textbf{}
    - Group best: \underline{} (if enabled)
    - Integers for counts, 3 decimals for floats
    """
    if "count" in stat_name:
        val_str = f"{int(val)}"
    else:
        val_str = f"{val:.3f}"

    style_applied = val_str

    if is_group and show_group_best:
        style_applied = f"\\underline{{{style_applied}}}"

    if is_global:
        style_applied = f"\\textbf{{{style_applied}}}"

    return style_applied


# ---------------------------------------------------------
# 3. Main Logic
# ---------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="Convert CSV to LaTeX.")
    parser.add_argument("input_file", type=str, help="Path to input CSV")

    # Custom Arguments
    parser.add_argument(
        "--group-best",
        action="store_true",
        help="Underline the best value in the group.",
    )
    parser.add_argument(
        "--midrule", action="store_true", help="Add midrules between method groups."
    )
    parser.add_argument(
        "--stats",
        nargs="+",
        default=["mean", "count_best"],
        help="List of stats to display (e.g., mean std median count_best). Default: mean count_best",
    )
    parser.add_argument(
        "--separate-post",
        action="store_true",
        help="If set, puts Post-processing in a separate column. Default is attached to Method name.",
    )

    args = parser.parse_args()

    # --- Load Data ---
    try:
        df = pd.read_csv(args.input_file)
    except Exception as e:
        sys.exit(f"Error reading CSV: {e}")

    active_metrics = [m for m in METRIC_MAP if m[0] in df.columns]
    if not active_metrics:
        sys.exit("Error: No valid metrics found in CSV.")

    metric_cols = [m[0] for m in active_metrics]

    # --- Pivot Data ---
    required_stats = args.stats + ["count"]
    mask = df["level_1"].isin(required_stats)
    df_filtered = df[mask].copy()

    if df_filtered.empty:
        sys.exit(f"Error: No data found for requested stats: {args.stats}")

    try:
        pivot_df = df_filtered.pivot_table(
            index="Method", columns="level_1", values=metric_cols, aggfunc="first"
        )
    except KeyError:
        sys.exit("Error pivoting data. Ensure 'Method' and 'level_1' columns exist.")

    # --- Filter Valid Methods (Count > 0) ---
    check_metric = metric_cols[0]

    if (check_metric, "count") not in pivot_df.columns:
        sys.exit(f"Error: 'count' statistic missing for metric {check_metric}.")

    counts = pivot_df[(check_metric, "count")].fillna(0)
    valid_idx = counts[counts > 0].index

    if len(valid_idx) == 0:
        sys.exit("No methods with count > 0 found.")

    final_df = pivot_df.loc[valid_idx].copy()

    # --- Network Consistency Check ---
    unique_counts = counts.loc[valid_idx].unique()
    network_count = int(unique_counts[0]) if len(unique_counts) == 1 else "Variable"

    # --- Categorize & Sort ---
    parsed = final_df.index.to_series().apply(parse_method)

    # Store meta columns as tuples to match MultiIndex structure of Data
    final_df[("meta", "Base")] = parsed.apply(lambda x: x[0])
    final_df[("meta", "Post")] = parsed.apply(lambda x: x[1])

    final_df[("meta", "Base")] = pd.Categorical(
        final_df[("meta", "Base")], categories=METHOD_ORDER, ordered=True
    )
    final_df[("meta", "Post")] = pd.Categorical(
        final_df[("meta", "Post")], categories=POST_PROC_ORDER, ordered=True
    )

    final_df = final_df.sort_values([("meta", "Base"), ("meta", "Post")])

    # --- Pre-Calculate Highlighting ---
    highlight_map = {}

    for metric in metric_cols:
        highlight_map[metric] = {}
        for stat in args.stats:
            # Only highlight specific stats
            if stat not in HIGHLIGHT_STATS and stat != "count_best":
                # Fallback: if user asked for mean/median explicitly, we highlight them
                if stat != "mean" and stat != "median":
                    continue

            if (metric, stat) not in final_df.columns:
                continue

            series = final_df[(metric, stat)]
            if series.isnull().all():
                continue

            g_max = series.max()

            # Group by Base method to find local best
            grp_max = (
                final_df[(metric, stat)]
                .groupby(final_df[("meta", "Base")], observed=True)
                .transform("max")
            )

            highlight_map[metric][stat] = {"global": g_max, "group": grp_max}

    # --- Generate LaTeX Headers ---
    num_stats = len(args.stats)

    # Define Column Structure
    if args.separate_post:
        # Method + Post columns
        col_def = "l l "
        num_index_cols = 2
        header1_start = r"\multirow{2}{*}{Method} & \multirow{2}{*}{Post-processing}"
    else:
        # Combined Method column
        col_def = "l "
        num_index_cols = 1
        header1_start = r"\multirow{2}{*}{Method}"

    col_def += " ".join([" ".join(["c"] * num_stats)] * len(active_metrics))

    # Header Row 1
    header1 = r"\toprule" + "\n" + header1_start

    # Header Row 2 (Stats) - PREFILL WITH EMPTY CELLS FOR INDEX COLS
    header2 = " & " * (num_index_cols - 1)
    if num_index_cols > 0:
        header2 += " & "  # One more ampersand to separate last index col from data

    # Midrules for headers
    cmidrules = ""
    col_counter = num_index_cols + 1

    for i, (m_key, m_name) in enumerate(active_metrics):
        header1 += f" & \\multicolumn{{{num_stats}}}{{c}}{{{m_name}}}"
        cmidrules += f" \\cmidrule(lr){{{col_counter}-{col_counter + num_stats - 1}}}"
        col_counter += num_stats

        for stat in args.stats:
            display_name = STAT_DISPLAY_MAP.get(stat, stat)
            # Add to header2. Note: header2 already has index spacers
            if i == 0 and stat == args.stats[0]:
                # First data cell, remove leading ' & ' if appended blindly?
                # Actually simpler: append ' & name' to header2 string
                header2 += f"{display_name}"
            else:
                header2 += f" & {display_name}"

    latex = f"""\\begin{{table}}[h]
\\centering
\\begin{{tabular}}{{{col_def}}}
{header1} \\\\
{cmidrules}
{header2} \\\\
\\midrule
"""

    # --- Generate LaTeX Rows ---
    grouped = final_df.groupby(("meta", "Base"), observed=True)
    first_group = True

    for base, group in grouped:
        if group.empty:
            continue

        # Separator Logic
        if not first_group and args.midrule:
            latex += r"\midrule" + "\n"
        first_group = False

        num_rows = len(group)
        for i, (idx, row) in enumerate(group.iterrows()):

            # --- Column 1 & 2 Logic ---
            post_val = row[("meta", "Post")]

            if args.separate_post:
                # Separate Columns: Use Multirow for Method name
                method_cell = (
                    f"\\multirow{{{num_rows}}}{{*}}{{{base}}}" if i == 0 else ""
                )
                line = f"{method_cell} & {post_val}"
            else:
                # Combined Column: Attach Post to Method
                # If Post is 'None', just show Base, else Base+Post
                if post_val == "None":
                    display_name = base
                else:
                    display_name = f"{base}{post_val}"
                line = f"{display_name}"

            # --- Data Columns ---
            for m_key, m_name in active_metrics:
                for stat in args.stats:
                    if (m_key, stat) not in row or pd.isna(row[(m_key, stat)]):
                        line += " & -"
                        continue

                    val = row[(m_key, stat)]

                    is_glob = False
                    is_grp = False

                    if m_key in highlight_map and stat in highlight_map[m_key]:
                        h_data = highlight_map[m_key][stat]
                        is_glob = np.isclose(val, h_data["global"])
                        is_grp = np.isclose(val, h_data["group"][idx])

                    val_str = format_value(val, stat, is_glob, is_grp, args.group_best)
                    line += f" & {val_str}"

            latex += line + " \\\\\n"

    latex += f"""\\bottomrule
\\end{{tabular}}
\\caption{{Comparison of clustering methods ($N={network_count}$ networks).}}
\\label{{tab:results}}
\\end{{table}}
"""

    print(latex)


if __name__ == "__main__":
    main()
