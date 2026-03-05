import os
import time
import argparse
import logging
import requests
import pandas as pd
import graph_tool.all as gt
from functools import wraps


# --- Retry Decorator ---
def retry(max_retries=3, delay=2):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(1, max_retries + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_retries:
                        logging.error(f"    [!] Final attempt {attempt} failed: {e}")
                        raise e
                    logging.warning(
                        f"    [!] Attempt {attempt} failed ({e}). Retrying in {delay} seconds..."
                    )
                    time.sleep(delay)

        return wrapper

    return decorator


# --- Network Functions ---
@retry(max_retries=3, delay=2)
def fetch_network_ids():
    response = requests.get("https://networks.skewed.de/api/nets", timeout=10)
    response.raise_for_status()
    data = response.json()
    return list(data.keys()) if isinstance(data, dict) else data


@retry(max_retries=3, delay=2)
def fetch_network_metadata(net_id):
    response = requests.get(f"https://networks.skewed.de/api/net/{net_id}", timeout=10)
    response.raise_for_status()
    return response.json()


@retry(max_retries=3, delay=5)
def fetch_graph_tool_network(graph_key):
    return gt.collection.ns[graph_key]


def post_process_network(g):
    g.edge_properties.clear()

    # Force undirected so parallel edges are correctly identified and removed
    g.set_directed(False)

    gt.remove_self_loops(g)
    gt.remove_parallel_edges(g)

    deg = g.degree_property_map("total")
    vfilt = g.new_vertex_property("bool")
    vfilt.a = deg.a > 0
    g.set_vertex_filter(vfilt)
    g.purge_vertices()

    return g


def save_dataframe(data_list, filepath, message=None):
    if data_list:
        pd.DataFrame(data_list).to_csv(filepath, index=False)
        if message:
            logging.info(message)


def load_existing_csv_to_dict(filepath, index_col):
    if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
        try:
            df = pd.read_csv(filepath)
            return {row[index_col]: row for row in df.to_dict("records")}
        except Exception as e:
            logging.error(f"    [!] Could not load existing {filepath}: {e}")
    return {}


# --- Main Orchestration ---
def crawl_networks(output_dir, save_interval=10):
    stats_file = os.path.join(output_dir, "processed_networks_stats.csv")
    subnet_counts_file = os.path.join(output_dir, "network_subnet_counts.csv")

    existing_stats = load_existing_csv_to_dict(stats_file, "net_subnet")
    existing_subnet_counts = load_existing_csv_to_dict(subnet_counts_file, "net")

    try:
        logging.info("Fetching list of network ids...")
        network_ids = fetch_network_ids()
    except Exception as e:
        logging.critical(f"Failed to fetch network list. Exiting. Error: {e}")
        return

    # ==========================================
    # PHASE 1: Metadata Collection
    # ==========================================
    logging.info(f"--- PHASE 1: Gathering Metadata for {len(network_ids)} networks ---")
    networks_info = []
    subnet_counts = []

    for net in network_ids:
        try:
            d = fetch_network_metadata(net)
        except Exception:
            logging.warning(f"  -> Skipping {net}: Repeated metadata fetch failures.")
            continue

        if d.get("restricted", False):
            logging.info(f"  -> Skipping {net}: Network data is restricted.")
            continue

        subnets = d.get("nets", [net])
        num_subnets = len(subnets)

        if net in existing_subnet_counts:
            subnet_counts.append(existing_subnet_counts[net])
        else:
            subnet_counts.append({"net": net, "num_subnets": num_subnets})

        # Pre-extract all subnet data so we never parse `d` again
        subnets_data = []
        total_nodes = 0

        for subnet in subnets:
            is_single_net = num_subnets == 1 and subnet == net

            if is_single_net:
                graph_key = net
                net_subnet_id = net
                analysis_data = d.get("analyses", {})
            else:
                graph_key = f"{net}/{subnet}"
                net_subnet_id = f"{net}_{subnet}"
                analysis_data = d.get("analyses", {}).get(subnet, {})

            orig_nodes = analysis_data.get("num_vertices")
            orig_edges = analysis_data.get("num_edges")
            is_bipartite = analysis_data.get("is_bipartite")
            is_directed = analysis_data.get("is_directed")

            if orig_nodes:
                total_nodes += orig_nodes

            subnets_data.append(
                {
                    "graph_key": graph_key,
                    "net_subnet_id": net_subnet_id,
                    "orig_nodes": orig_nodes,
                    "orig_edges": orig_edges,
                    "is_bipartite": is_bipartite,
                    "is_directed": is_directed,
                }
            )

        networks_info.append(
            {
                "net": net,
                "num_subnets": num_subnets,
                "total_nodes": total_nodes,
                "subnets_data": subnets_data,
            }
        )

    save_dataframe(
        subnet_counts,
        subnet_counts_file,
        f"[*] Saved subnet counts to {subnet_counts_file}",
    )

    # Sort networks: First by number of subnets, then by total nodes (both ascending)
    networks_info.sort(key=lambda x: (x["num_subnets"], x["total_nodes"]))

    # ==========================================
    # PHASE 2: Downloading & Processing
    # ==========================================
    logging.info("--- PHASE 2: Downloading and Processing Networks ---")
    stats = []
    processed_count = 0

    for info in networks_info:
        net = info["net"]
        subnets_data = info["subnets_data"]

        logging.info(
            f"\nProcessing network: {net} ({info['num_subnets']} subnets, ~{info['total_nodes']} total nodes)"
        )
        net_dir = os.path.join(output_dir, net)

        for sub_info in subnets_data:
            graph_key = sub_info["graph_key"]
            net_subnet_id = sub_info["net_subnet_id"]

            if sub_info["is_bipartite"]:
                logging.info(f"  -> Skipping {graph_key}: Network is bipartite.")
                continue

            out_file = os.path.join(net_dir, f"{net_subnet_id}.csv")

            if os.path.exists(out_file) and os.path.getsize(out_file) > 0:
                logging.info(
                    f"  -> Skipping download for {graph_key}: File already exists."
                )

                if net_subnet_id in existing_stats:
                    stats.append(existing_stats[net_subnet_id])
                else:
                    logging.info(
                        f"      -> Stats missing from file. Computing from CSV..."
                    )
                    try:
                        existing_df = pd.read_csv(out_file)
                        unique_nodes = len(
                            set(existing_df["source"]).union(set(existing_df["target"]))
                        )
                        edge_count = len(existing_df)

                        stats.append(
                            {
                                "net": net,
                                "net_subnet": net_subnet_id,
                                "original_nodes": sub_info["orig_nodes"],
                                "original_edges": sub_info["orig_edges"],
                                "is_bipartite": sub_info["is_bipartite"],
                                "is_directed": sub_info["is_directed"],
                                "nodes": unique_nodes,
                                "edges": edge_count,
                            }
                        )
                    except Exception as e:
                        logging.error(
                            f"      -> Could not read existing file {out_file} for stats: {e}"
                        )
            else:
                logging.info(f"  -> Fetching graph: {graph_key}")
                try:
                    g = fetch_graph_tool_network(graph_key)
                    g = post_process_network(g)

                    edges_array = g.get_edges()[:, :2]
                    df = pd.DataFrame(edges_array, columns=["source", "target"])

                    # Create the directory ONLY right before we save the file
                    os.makedirs(net_dir, exist_ok=True)
                    df.to_csv(out_file, index=False)

                    logging.info(f"  -> Saved edgelist to: {out_file}")

                    stats.append(
                        {
                            "net": net,
                            "net_subnet": net_subnet_id,
                            "original_nodes": sub_info["orig_nodes"],
                            "original_edges": sub_info["orig_edges"],
                            "is_bipartite": sub_info["is_bipartite"],
                            "is_directed": sub_info["is_directed"],
                            "nodes": g.num_vertices(),
                            "edges": g.num_edges(),
                        }
                    )
                except Exception as e:
                    logging.error(
                        f"  -> Failed processing {graph_key} after retries. Error: {e}"
                    )
                    continue

            processed_count += 1
            if processed_count % save_interval == 0:
                save_dataframe(
                    stats,
                    stats_file,
                    f"    [*] Auto-saved stats at {processed_count} processed graphs...",
                )

    save_dataframe(
        stats, stats_file, f"[*] Final save completed! Total processed: {len(stats)}"
    )
    logging.info("Done!")


def setup_logging(output_dir):
    log_file = os.path.join(output_dir, "crawl.log")
    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
    )

    file_handler = logging.FileHandler(log_file)
    file_handler.setFormatter(formatter)

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.setLevel(logging.INFO)

    if logger.hasHandlers():
        logger.handlers.clear()

    logger.addHandler(file_handler)
    logger.addHandler(console_handler)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Crawl and process networks from Netzschleuder."
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        required=True,
        help="Target directory to save all networks.",
    )
    parser.add_argument(
        "--save-interval",
        type=int,
        default=10,
        help="Frequency of auto-saving the stats CSV.",
    )

    args = parser.parse_args()
    os.makedirs(args.output_dir, exist_ok=True)
    setup_logging(args.output_dir)

    crawl_networks(output_dir=args.output_dir, save_interval=args.save_interval)
