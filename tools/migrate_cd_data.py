#!/usr/bin/env python3
"""Migrate pre-Phase-1 CD data dirs to the new state-system format.

Walks <root>/clusterings/<algo>/<network>/ leaf dirs and, for each one that
already has a com.csv, regenerates the metadata that the post-Phase-1
single_stage_pipeline.sh would have written: params.txt, done, pipeline.log,
error.log. Existing com.csv + run.log + error.log are left untouched.

Modes:
  In-place (default): rewrite source leaves with new metadata.
  --output-root DEST: source leaves untouched. Each source leaf is
    materialized (hardlink if same FS, else copy) under
    DEST/clusterings/<algo>/<network>/, then migrated there. Lets you keep
    the original tree byte-pristine while producing a parallel migrated tree.

After migration, the new dispatcher's is_step_done check passes (cache hit) and
no recompute is needed. Idempotent: rerun on already-migrated dirs is a no-op
modulo timestamps in pipeline.log / error.log.

Algos handled (path-encoded as <algo>[+<postproc>[(<criterion>)]] / <network>):
  leiden-{cpm-X | mod}                  base (input = edge.csv)
  infomap                                base
  ikc-K                                  base
  sbm-{flat | nested}-{dc | ndc | pp}   base
  sbm-{flat | nested}-best               meta (input = N variants' com + entropy)
  <algo>+cc                              postproc (input = edge.csv + base com)
  <algo>+wcc[(crit)]                     postproc
  <algo>+cm[(crit)]                      postproc

Usage:
    python3 tools/migrate_cd_data.py <clusterings-dir>
    python3 tools/migrate_cd_data.py <clusterings-dir> --dry-run
    python3 tools/migrate_cd_data.py <clusterings-dir> --algo-filter leiden-mod
    python3 tools/migrate_cd_data.py <src-clusterings-dir> --output-root <dest-data-root>

Path conventions (mirrors run_cd.sh post-Phase-1):
  data-root/clusterings/<algo>/<network>/{com.csv,...}
  data-root/empirical_networks/networks/<network>/<network>.csv  (input edge)

Stats / acc trees use a separate Python StateTracker; this tool only migrates
clusterings/. Run network_evaluation/* tools to refresh stats/acc dones.
"""

import argparse
import datetime as _dt
import hashlib
import os
import re
import shutil
import socket
import sys
from pathlib import Path


# ---------- algo decode ----------

POSTPROCS = ("cc", "wcc", "cm")
SBM_FLAT_VARIANTS = ("sbm-flat-dc", "sbm-flat-ndc", "sbm-flat-pp")
SBM_NESTED_VARIANTS = ("sbm-nested-dc", "sbm-nested-ndc")


def decode_algo(name):
    """Split <algo>+<postproc>[(<crit>)] -> (base, postproc_or_None, crit_or_None)."""
    if "+" in name:
        base, suffix = name.split("+", 1)
        m = re.match(r"^([a-z]+)(?:\((.+)\))?$", suffix)
        if not m:
            return base, None, None
        return base, m.group(1), m.group(2)
    return name, None, None


def base_inputs(base, network, inputs_root):
    """Inputs that drive this base algo's com.csv. Always = the network edge."""
    return [inputs_root / "empirical_networks" / "networks" / network / f"{network}.csv"]


def best_inputs(base, network, clusterings_dir):
    """Inputs for sbm-{flat,nested}-best meta-models (variants' com + entropy)."""
    if base == "sbm-flat-best":
        variants = SBM_FLAT_VARIANTS
    elif base == "sbm-nested-best":
        variants = SBM_NESTED_VARIANTS
    else:
        return None
    paths = []
    for v in variants:
        paths.append(clusterings_dir / v / network / "entropy.txt")
        paths.append(clusterings_dir / v / network / "com.csv")
    return paths


def postproc_inputs(base, network, inputs_root, clusterings_dir):
    """Inputs for <algo>+<pp>: input edge + base com."""
    edge = inputs_root / "empirical_networks" / "networks" / network / f"{network}.csv"
    base_com = clusterings_dir / base / network / "com.csv"
    return [edge, base_com]


def deduce_params(algo_name, base, postproc, crit):
    """Synthesize per-stage params.txt key=value list."""
    params = {}

    if postproc is None:
        # Base algo
        if base == "leiden-mod":
            params.update(model="mod", resolution="", n_iterations="2",
                          weighted="false", seed="1234")
        elif base.startswith("leiden-cpm-"):
            res = base[len("leiden-cpm-"):]
            params.update(model="cpm", resolution=res, n_iterations="2",
                          weighted="false", seed="1234")
        elif base == "infomap":
            params.update(seed="1")
        elif base.startswith("ikc-"):
            k = base[len("ikc-"):]
            params.update(k=k, seed="1")
        elif base in (SBM_FLAT_VARIANTS + SBM_NESTED_VARIANTS):
            method = base[len("sbm-"):]
            params.update(method=method, seed="1", n_threads="1")
        elif base == "sbm-flat-best":
            params.update(variants="flat-dc,flat-ndc,flat-pp", seed="1")
        elif base == "sbm-nested-best":
            params.update(variants="nested-dc,nested-ndc", seed="1")
        else:
            params.update(legacy="true", seed="1")
    else:
        # Post-proc: base-algo CD_PARAMS shape
        if postproc == "cc":
            params.update(criterion="0", n_threads="1", seed="1")
        elif postproc == "wcc":
            params.update(criterion=crit or "1log_10(n)", n_threads="1", seed="1")
        elif postproc == "cm":
            base_algo = ("leiden-cpm" if base.startswith("leiden-cpm-")
                         else "leiden-mod" if base == "leiden-mod"
                         else "")
            base_res = base[len("leiden-cpm-"):] if base.startswith("leiden-cpm-") else ""
            params.update(criterion=crit or "0.2n^0.5", base_algo=base_algo,
                          base_resolution=base_res, mincut_type="cactus",
                          n_threads="1", seed="1")

    return params


def deduce_outputs(algo_name, base, postproc, leaf_dir):
    """Outputs the new dispatcher would mark_done on for this stage."""
    outs = [leaf_dir / "com.csv"]
    if postproc is None:
        if base in (SBM_FLAT_VARIANTS + SBM_NESTED_VARIANTS):
            outs.append(leaf_dir / "entropy.txt")
        elif base in ("sbm-flat-best", "sbm-nested-best"):
            outs.append(leaf_dir / "best_model.txt")
            outs.append(leaf_dir / "models.txt")
    return outs


# ---------- file synthesis ----------

def write_params(path, params):
    """params.txt: sorted key=value lines, atomic write."""
    lines = sorted(f"{k}={v}" for k, v in params.items())
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text("\n".join(lines) + "\n")
    tmp.replace(path)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def write_done(path, paths_in_order):
    """sha256sum-compatible manifest, atomic."""
    lines = [f"{sha256_file(p)}  {p}" for p in paths_in_order]
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text("\n".join(lines) + "\n")
    tmp.replace(path)


def _ts_from_mtime(path, fallback):
    """ISO-Z UTC timestamp from path's mtime, or now() if path missing."""
    try:
        m = path.stat().st_mtime
        return _dt.datetime.utcfromtimestamp(m).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (OSError, ValueError):
        return fallback


def _prefix(label, lines):
    """[label] <line> for each line; empty input -> empty output."""
    return "".join(f"[{label}] {ln}" if ln else f"[{label}]\n"
                   for ln in lines.splitlines(keepends=True)) if lines else ""


def write_error_log(path, stage_name, leaf_dir, host="cc-login.campuscluster.illinois.edu"):
    """Frame the legacy error.log content with run_stage's EXECUTED/exit markers.

    Real run_stage layout:
        === <UTC> | pid=N | host=H | EXECUTED ===
        <time -v output (the legacy error.log content)>
        === exit=0 ===

    Idempotent: if `path` already starts with `=== ... | EXECUTED ===`, the
    file is already in script-shape; skip re-wrapping.
    """
    err = leaf_dir / "error.log"
    now_z = _dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    if not err.exists():
        path.write_text(
            f"=== {now_z} | pid=0 | host={host} | SKIPPED (legacy migration; no error.log) ===\n"
        )
        return
    body = err.read_text(errors="replace")
    if body.lstrip().startswith("===") and "EXECUTED" in body[:200]:
        return
    ts = _ts_from_mtime(err, now_z)
    if body and not body.endswith("\n"):
        body += "\n"
    content = (
        f"=== {ts} | pid=0 | host={host} | EXECUTED ===\n"
        f"{body}"
        f"=== exit=0 ===\n"
    )
    path.write_text(content)


_LEIDEN_RUN_LOG_MAP = [
    (r"\[TIME\] Loading network: ", "load_network elapsed: "),
    (r"\[TIME\] Running Leiden algorithm: ", "leiden_run elapsed: "),
    (r"\[TIME\] Saving results: ", "save_results elapsed: "),
]
_INFOMAP_RUN_LOG_MAP = [
    (r"\[TIME\] Loading network: ", "load_network elapsed: "),
    (r"\[TIME\] Running Infomap algorithm: ", "infomap_run elapsed: "),
    (r"\[TIME\] Saving results: ", "save_results elapsed: "),
]
_IKC_RUN_LOG_MAP = [
    (r"\[TIME\] Loading network: ", "load_network elapsed: "),
    (r"\[TIME\] Running IKC algorithm: ", "ikc_run elapsed: "),
    (r"\[TIME\] Saving results: ", "save_results elapsed: "),
]
_SBM_RUN_LOG_MAP = [
    (r"\[TIME\] Loading network: ", "load_network elapsed: "),
    (r"\[TIME\] Initializing state: ", "sbm_init_state elapsed: "),
    (r"\[TIME\] Calculating entropy: ", "entropy elapsed: "),
    (r"\[TIME\] Storing refined partition: ", "save_results elapsed: "),
]


def _algo_run_log_mappings(base):
    if base.startswith("leiden-cpm-") or base == "leiden-mod":
        return _LEIDEN_RUN_LOG_MAP, "leiden"
    if base == "infomap":
        return _INFOMAP_RUN_LOG_MAP, "infomap"
    if base.startswith("ikc-"):
        return _IKC_RUN_LOG_MAP, "ikc"
    if base in (SBM_FLAT_VARIANTS + SBM_NESTED_VARIANTS):
        return _SBM_RUN_LOG_MAP, "sbm"
    return None, None


def transform_run_log(text, base, postproc):
    """Rewrite a server-era run.log into current-script wording.

    Preserves timestamps + numerical values; only swaps log message strings:
      [TIME] Loading network: X            -> load_network elapsed: X seconds
      [TIME] Running Leiden algorithm: X   -> leiden_run elapsed: X seconds
      [TIME] Initializing state: X         -> sbm_init_state elapsed: X seconds
      [TIME] Calculating entropy: X        -> entropy elapsed: X seconds
      [TIME] Storing refined partition: X  -> save_results elapsed: X seconds
      [TIME] Saving results: X             -> save_results elapsed: X seconds
      Removed N singleton nodes.           -> drop if N=0; rewrite to
                                              "Dropping N singleton cluster(s) from com.csv"
                                              if N>0 (matches drop_singleton_clusters)

    ikc-only line "Removed N singleton clusters." stays verbatim (the IKC
    print_clusters function is unchanged across the refactor).

    Idempotent: if no patterns match, content is returned unchanged.
    Post-procs (cc / wcc / cm / *-best) don't have an algo run.log on server
    so this function is not invoked for them.
    """
    if not text or postproc:
        return text
    mappings, family = _algo_run_log_mappings(base)
    if mappings is None:
        return text

    out = []
    for line in text.splitlines(keepends=True):
        for pat, repl in mappings:
            new_line, n = re.subn(pat, repl, line)
            if n:
                stripped = new_line.rstrip("\n")
                if "elapsed:" in stripped and not stripped.endswith("seconds"):
                    new_line = stripped + " seconds\n"
                line = new_line
                break

        # Singleton-drop wording change for leiden / infomap / sbm.
        # ikc keeps its own "Removed N singleton clusters." line verbatim.
        if family in ("leiden", "infomap", "sbm"):
            m = re.match(r"^(.*? - INFO - )Removed (\d+) singleton nodes\.\s*\n?$", line)
            if m:
                n = int(m.group(2))
                if n == 0:
                    continue  # drop_singleton_clusters skips logging when n=0
                line = f"{m.group(1)}Dropping {n} singleton cluster(s) from com.csv\n"

        out.append(line)

    return "".join(out)


def write_run_log_inplace(leaf_dir, base, postproc):
    """Rewrite the leaf's run.log to match current-script wording. Idempotent."""
    run_log = leaf_dir / "run.log"
    if not run_log.exists():
        return
    body = run_log.read_text(errors="replace")
    new_body = transform_run_log(body, base, postproc)
    if new_body != body:
        run_log.write_text(new_body)


def write_pipeline_log(path, stage_name, seed, leaf_dir, err_log_path,
                       host="cc-login.campuscluster.illinois.edu"):
    """Build a pipeline.log shaped like single_stage_pipeline.sh would have.

    Layout:
        === Invocation <UTC> | seed=N | keep_state=0 | pid=0 | host=H ===
        === [stage] <abs path to error.log> ===
        [stage] <error.log lines>

        === [stage (python)] <abs path to run.log> ===
        [stage (python)] <run.log lines>
    """
    run_log = leaf_dir / "run.log"
    now_z = _dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    inv_ts = _ts_from_mtime(run_log if run_log.exists() else (leaf_dir / "com.csv"), now_z)

    parts = [
        f"=== Invocation {inv_ts} | seed={seed} | keep_state=0 | "
        f"pid=0 | host={host} ===\n"
    ]

    err_body = err_log_path.read_text(errors="replace") if err_log_path.exists() else ""
    parts.append(f"=== [{stage_name}] {err_log_path} ===\n")
    parts.append(_prefix(stage_name, err_body))
    parts.append("\n")

    if run_log.exists():
        run_body = run_log.read_text(errors="replace")
        parts.append(f"=== [{stage_name} (python)] {run_log} ===\n")
        parts.append(_prefix(f"{stage_name} (python)", run_body))
        parts.append("\n")

    path.write_text("".join(parts))


# ---------- output-root materialization ----------

# Files we copy/hardlink from a source leaf to a dest leaf before running the
# in-place migration logic at the dest. Anything not in this list is either
# regenerated by migrate_one (params.txt, done, pipeline.log) or considered
# stage output that doesn't ride along with com.csv (stats/, acc/ trees are
# migrated separately by their own tooling).
_LEAF_DATA_FILES = (
    "com.csv", "run.log", "error.log", "done",
    "entropy.txt", "best_model.txt", "models.txt",
)


def materialize_source_to_dest(source_leaf, dest_leaf, mode):
    """Mirror source leaf's data files to dest leaf via hardlink (or copy).

    Hardlink keeps source byte-pristine (com.csv NEVER touched binding) and
    costs ~zero disk on same filesystem. Falls back to copy on cross-FS.
    Idempotent: existing dest files are left as-is.
    """
    dest_leaf.mkdir(parents=True, exist_ok=True)
    for name in _LEAF_DATA_FILES:
        src = source_leaf / name
        if not src.exists():
            continue
        dst = dest_leaf / name
        if dst.exists():
            continue
        if mode == "hardlink":
            try:
                os.link(src, dst)
                continue
            except OSError:
                pass
        shutil.copy2(src, dst)


def _phase(algo_name):
    """Sort key: bases (0) before *-best (1) before post-procs (2).

    Ensures dest tree's bases are materialized before *-best meta-models look
    up variant inputs and before post-procs look up base com.csv inputs.
    """
    base, postproc, _crit = decode_algo(algo_name)
    if postproc:
        return 2
    if base in ("sbm-flat-best", "sbm-nested-best"):
        return 1
    return 0


# ---------- main ----------

def migrate_one(leaf_dir, inputs_root, clusterings_dir, algo, network, dry_run, verbose):
    com = leaf_dir / "com.csv"
    if not com.exists():
        if verbose:
            print(f"  skip {algo}/{network}: no com.csv")
        return "skip_no_com"
    # Require legacy done file too: a dir without done is an incomplete server
    # run + we can't safely produce a valid current-state done.
    if not (leaf_dir / "done").exists():
        if verbose:
            print(f"  skip {algo}/{network}: no legacy done")
        return "skip_no_done"

    base, postproc, crit = decode_algo(algo)

    # Inputs
    if postproc:
        inputs = postproc_inputs(base, network, inputs_root, clusterings_dir)
    elif base in ("sbm-flat-best", "sbm-nested-best"):
        inputs = best_inputs(base, network, clusterings_dir)
        if inputs is None:
            return "skip_unknown_best"
    else:
        inputs = base_inputs(base, network, inputs_root)

    missing_inputs = [p for p in inputs if not p.exists()]
    if missing_inputs:
        if verbose:
            print(f"  skip {algo}/{network}: missing inputs {missing_inputs[0]}")
        return "skip_missing_input"

    # Outputs
    outputs = deduce_outputs(algo, base, postproc, leaf_dir)
    missing_outputs = [p for p in outputs if not p.exists()]
    if missing_outputs:
        if verbose:
            print(f"  skip {algo}/{network}: missing outputs {missing_outputs[0]}")
        return "skip_missing_output"

    # Synthesize new metadata
    params = deduce_params(algo, base, postproc, crit)
    seed = params.get("seed", "1")

    if dry_run:
        return "would_migrate"

    params_path = leaf_dir / "params.txt"
    done_path = leaf_dir / "done"
    pipeline_log = leaf_dir / "pipeline.log"
    err_log_path = leaf_dir / "error.log"

    stage_name = base if not postproc else postproc

    write_params(params_path, params)
    write_error_log(err_log_path, stage_name, leaf_dir)
    write_run_log_inplace(leaf_dir, base, postproc)
    write_pipeline_log(pipeline_log, stage_name, seed, leaf_dir, err_log_path)

    # done = sha256(inputs + params.txt + outputs), in that order
    manifest = list(inputs) + [params_path] + outputs
    write_done(done_path, manifest)

    return "migrated"


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("clusterings_dir",
                        help="Path to source dir containing <algo>/<network>/ leaf dirs "
                             "(e.g. data/reference_clusterings/clusterings)")
    parser.add_argument("--inputs-root", default=None,
                        help="Path containing empirical_networks/networks/... "
                             "(default: <clusterings_dir>'s grandparent dir)")
    parser.add_argument("--output-root", default=None,
                        help="Write migrated tree under <output-root>/clusterings/ "
                             "instead of in-place. Source tree stays untouched.")
    parser.add_argument("--copy-mode", choices=("hardlink", "copy"), default="hardlink",
                        help="How to materialize source data files at dest under "
                             "--output-root (default: hardlink, falls back to copy "
                             "on cross-filesystem).")
    parser.add_argument("--dry-run", action="store_true",
                        help="Report what would be migrated without writing")
    parser.add_argument("--algo-filter", default=None,
                        help="Only migrate algos matching this prefix")
    parser.add_argument("--network-filter", default=None,
                        help="Only migrate networks matching this prefix")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="Print per-dir status")
    args = parser.parse_args()

    src_clusterings_dir = Path(args.clusterings_dir).resolve()
    if not src_clusterings_dir.is_dir():
        print(f"ERROR: {src_clusterings_dir} does not exist", file=sys.stderr)
        sys.exit(1)

    inputs_root = (Path(args.inputs_root).resolve() if args.inputs_root
                   else src_clusterings_dir.parent.parent)

    if args.output_root:
        dest_clusterings_dir = Path(args.output_root).resolve() / "clusterings"
        if not args.dry_run:
            dest_clusterings_dir.mkdir(parents=True, exist_ok=True)
    else:
        dest_clusterings_dir = src_clusterings_dir

    # Collect (algo, network, src_leaf), then phase-sort so bases land at dest
    # before *-best meta-models and post-procs look up their inputs there.
    entries = []
    for algo_dir in src_clusterings_dir.iterdir():
        if not algo_dir.is_dir():
            continue
        algo = algo_dir.name
        if args.algo_filter and not algo.startswith(args.algo_filter):
            continue
        for net_dir in algo_dir.iterdir():
            if not net_dir.is_dir():
                continue
            network = net_dir.name
            if args.network_filter and not network.startswith(args.network_filter):
                continue
            entries.append((algo, network, net_dir))
    entries.sort(key=lambda t: (_phase(t[0]), t[0], t[1]))

    counts = {}
    for algo, network, src_leaf in entries:
        if args.output_root:
            dest_leaf = dest_clusterings_dir / algo / network
            if not args.dry_run:
                materialize_source_to_dest(src_leaf, dest_leaf, args.copy_mode)
        else:
            dest_leaf = src_leaf
        # Under --output-root + --dry-run we skip materialize, so the existence
        # checks in migrate_one have to look at source. Point both at src then.
        check_leaf = src_leaf if (args.output_root and args.dry_run) else dest_leaf
        check_clusterings = (src_clusterings_dir
                             if (args.output_root and args.dry_run)
                             else dest_clusterings_dir)
        status = migrate_one(check_leaf, inputs_root, check_clusterings,
                             algo, network, args.dry_run, args.verbose)
        counts[status] = counts.get(status, 0) + 1

    print(f"\nMigration summary{' (dry-run)' if args.dry_run else ''}:")
    for k in sorted(counts):
        print(f"  {k}: {counts[k]}")
    total = sum(counts.values())
    print(f"  total: {total}")


if __name__ == "__main__":
    main()
