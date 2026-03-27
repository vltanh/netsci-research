# EC-SBM v2

This repository implements a benchmark pipeline for evaluating synthetic network generators based on the Edge-Connected Stochastic Block Model (EC-SBM). The pipeline covers empirical data acquisition, synthetic network generation, community detection, and statistical comparison.

## Setup

```bash
# 1. Create and activate the conda environment
conda create -n nw python=3
conda activate nw

# 2. Install dependencies
conda install -c conda-forge graph-tool
conda update --all
conda install pandas requests tqdm seaborn scikit-learn
pip install git+https://github.com/vikramr2/python-mincut
pip install igraph leidenalg networkit

# 3. Build the constrained-clustering binary
cd constrained-clustering && sh easy_build_and_compile.sh && cd ..
```

All of the above is in `install.sh` for reference.

## Directory Structure

```
data/                               # All inputs and outputs (gitignored)
  empirical_networks/
    networks/<network>/<network>.csv
    stats/<network>/
  reference_clusterings/
    clusterings/<clustering>/<network>/com.csv
    stats/<clustering>/<network>/
  synthetic_networks/
    networks/<generator>/<clustering>/<network>/<run-id>/edge.csv
    stats/<generator>/<clustering>/<network>/<run-id>/
  estimated_clusterings/
    <generator>/<clustering>/
      clusterings/<algo>[+<pp>]/<network>/<run-id>/com.csv
      stats/<algo>[+<pp>]/<network>/<run-id>/
      acc/<algo>[+<pp>]/<network>/<run-id>/

network-generation/                 # EC-SBM synthetic network generator
community_detection/                # Community detection pipeline
network_evaluation/                 # (submodule) Stats and comparison scripts
constrained-clustering/             # (submodule) CC/WCC/CM post-processing binary

plots/                              # Generated figures (gitignored)
task_files/                         # SLURM task lists (gitignored)
slurm_output/                       # SLURM job logs (gitignored)
slurm_locks/                        # SLURM deduplication locks (gitignored)
```

## Pipeline Overview

The full experiment pipeline runs in five stages:

```
[1] Crawl networks         crawl_netzschleuder.py
[2] Compute emp. stats     compute_empirical_stats.sh  ──┐
[3] Run CD on real nets    community_detection/          │ reference data
    run_cd.sh (--real)                                  ─┘
[4] Generate syn. nets     network-generation/
    run_generator.sh                                     → synthetic networks
[5] Run CD on syn. nets    community_detection/
    run_cd.sh (--synthetic)                              → estimated clusterings
[6] Plot results           make_plots.sh / plot_stats.py
```

Stages 3–5 are typically run at scale via SLURM using `submit_array.sh`.

## Scripts

### Job Submission

#### `submit_array.sh`

Generates a task list and submits it as a SLURM array job. All tasks run in parallel up to a configurable concurrency limit.

```bash
./submit_array.sh --mode <mode> [OPTIONS]
```

**Common options:**

| Option | Description |
| --- | --- |
| `--mode cd` | Community detection mode. |
| `--mode gen` | Synthetic network generation mode. |
| `--network-list <file>` | Path to the list of network IDs (default: `data/networks_all.txt`). |
| `--run-id <id>` | Run identifier (default: `0`). |

**Options for `--mode cd`:**

| Option | Description |
| --- | --- |
| `--real` | Run on empirical networks. |
| `--generator <names...>` | Generator name(s) (synthetic only). |
| `--gt-clustering <names...>` | Ground-truth clustering ID(s) (synthetic only). |
| `--criterion <name>` | Connectedness criterion for WCC/CM (e.g., `sqrt`, `log`). |
| `--method <names...>` | CD algorithm(s) to run. |

**Options for `--mode gen`:**

| Option | Description |
| --- | --- |
| `--generator <names...>` | Generator name(s). |
| `--clustering <names...>` | Reference clustering ID(s) to generate from. |

#### `array_wrapper.sh`

The SLURM batch script executed by each array task. Handles lock-based deduplication (prevents the same task running twice if the array is re-submitted), signal handling for graceful timeout/cancel, and per-task log routing. Not invoked directly — called by `submit_array.sh` via `sbatch`.

---

### Pipeline Scripts

#### `compute_empirical_stats.sh`

Computes network-level structural statistics for an empirical network. Must be run before `--run-comp` in `network-generation/run_generator.sh`.

```bash
# Macro mode
./compute_empirical_stats.sh --macro --network <id>

# Custom mode
./compute_empirical_stats.sh --input-edgelist <path> --output-dir <dir>
```

#### `network-generation/run_generator.sh`

Generates a synthetic network from an empirical network and a reference clustering. See [network-generation/README.md](network-generation/README.md) for full documentation.

#### `community_detection/run_cd.sh`

Runs community detection (and optional post-processing and evaluation) on a network. See [community_detection/README.md](community_detection/README.md) for full documentation.

---

### Analysis & Plotting

#### `make_plots.sh`

Aggregates comparison CSVs from `data/synthetic_networks/stats/` and generates figures via `network_evaluation/compare/visualize_comparisons.py`.

#### `plot_stats.py`

Plots cluster-level statistics (e.g., node coverage, proportion of well-connected clusters) across algorithms and networks.

---

### Utilities

#### `verify_state.sh`

Audits all SHA256 state ledgers (`done` files) across a directory tree. Reports corrupted states and orphaned temporary files.

```bash
./verify_state.sh [directory]   # defaults to current directory
```

#### `check.sh`

Scans `data/reference_clusterings/` for `error.log` files containing `"Command terminated by signal 4"` (illegal instruction — typically a dependency or hardware mismatch error).

#### `crawl_netzschleuder.py`

Fetches network metadata and edge lists from the [Netzschleuder](https://networks.skewed.de/) repository and writes them to `data/empirical_networks/`.

#### `split_corpus.py`

Splits a network list file into train/val/test subsets with shuffled assignment and preserved line order.

---

## Examples

### 1. Compute empirical statistics

```bash
# For all networks in a list
while IFS= read -r network; do
    ./compute_empirical_stats.sh --macro --network "${network}"
done < data/networks_all.txt
```

### 2. Run community detection on real networks (SLURM)

```bash
./submit_array.sh \
    --mode cd --real \
    --criterion log \
    --method leiden-cpm-0.1 sbm-flat-dc sbm-flat-ndc sbm-flat-pp sbm-nested-dc sbm-nested-ndc
```

### 3. Generate synthetic networks (SLURM)

```bash
./submit_array.sh \
    --mode gen \
    --generator ec-sbm-v2 ec-sbm-v1.5 \
    --clustering "leiden-cpm-0.1+cm(log)" "sbm-flat-best+wcc(log)"
```

### 4. Run community detection on synthetic networks (SLURM)

```bash
./submit_array.sh \
    --mode cd \
    --generator ec-sbm-v2 \
    --gt-clustering "sbm-flat-best+wcc(log)" \
    --criterion sqrt \
    --method sbm-flat-best leiden-cpm-0.1
```

### 5. Single-network test run (custom mode, no SLURM)

```bash
# Generate
./network-generation/run_generator.sh \
    --generator ec-sbm-v2 --run-id 0 \
    --input-edgelist test/input/dnc/dnc.csv \
    --input-clustering "test/output/reference_clusterings/clusterings/sbm-flat-best+wcc(log)/dnc/com.csv" \
    --output-dir test/output/synthetic_networks/ \
    --network dnc --clustering-id "sbm-flat-best+wcc(log)" \
    --run-stats --run-comp

# Detect communities
./community_detection/run_cd.sh \
    --algo sbm-flat-best --criterion sqrt \
    --input-edgelist "test/output/synthetic_networks/networks/ec-sbm-v2/sbm-flat-best+wcc(log)/dnc/0/edge.csv" \
    --input-gt-clustering "test/output/reference_clusterings/clusterings/sbm-flat-best+wcc(log)/dnc/com.csv" \
    --output-dir test/output/estimated_clusterings \
    --network dnc --generator ec-sbm-v2 --gt-clustering-id "sbm-flat-best+wcc(log)" --run-id 0 \
    --run-stats --run-acc --run-cc --run-wcc --run-cm
```

### 6. Verify state integrity

```bash
./verify_state.sh data/
```
