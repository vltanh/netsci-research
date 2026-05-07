#!/bin/sh

# # Very small

python network_evaluation/compare/aggregate_comparisons.py \
    --root data/synthetic_networks/stats/ \
    --output plots/verysmall/agg_comp.csv \
    --network-fp data/networks_verysmall.txt \
    --generators ec-sbm-v2 \
    --clusterings \
        sbm-flat-best+cc \
        "sbm-flat-best+wcc(piecewise)" \
        sbm-nested-best+cc \
        "sbm-nested-best+wcc(piecewise)"

python network_evaluation/compare/visualize_comparisons.py \
    --data-fp plots/verysmall/agg_comp.csv \
    --generators \
        ec-sbm-v2 \
        ec-sbm-v2 \
        ec-sbm-v2 \
        ec-sbm-v2 \
    --clusterings \
        "sbm-flat-best+cc" \
        "sbm-flat-best+wcc(piecewise)" \
        "sbm-nested-best+cc" \
        "sbm-nested-best+wcc(piecewise)" \
    --names \
        "EC-SBMv2 x SBM(Flat)+CC" \
        "EC-SBMv2 x SBM(Flat)+WCC(piecewise)" \
        "EC-SBMv2 x SBM(Nested)+CC" \
        "EC-SBMv2 x SBM(Nested)+WCC(piecewise)" \
    --stats \
        pseudo_diameter \
        char_time \
        global_ccoeff \
        degree \
        n_edges \
        deg_assort \
        node_percolation_targeted \
        node_percolation_random \
        local_ccoeff \
        local_ccoeff_nodes \
        pagerank \
        kcore \
    --types \
        scalar \
        scalar \
        scalar \
        sequence \
        scalar \
        scalar \
        scalar \
        scalar \
        scalar \
        sequence \
        sequence \
        sequence \
    --metrics \
        rel_diff \
        rel_diff \
        abs_diff \
        rmse \
        rel_diff \
        abs_diff \
        abs_diff \
        abs_diff \
        abs_diff \
        rmse \
        rmse \
        rmse \
    --network-fp data/networks_verysmall.txt \
    --output-dir plots/verysmall/ \
    --output-fn network \
    --hide-fliers

# Old list

# python network_evaluation/compare/aggregate_comparisons.py \
#     --root data/synthetic_networks/stats/ \
#     --output plots/old/agg_comp.csv \
#     --network-fp data/networks_all_old.txt \
#     --generators ec-sbm-v2 ec-sbm-v1 \
#     --clusterings \
#         leiden-cpm-0.1 \
#         "leiden-cpm-0.1+cm(log)" \
#         leiden-cpm-0.01 \
#         "leiden-cpm-0.01+cm(log)" \
#         leiden-cpm-0.001 \
#         "leiden-cpm-0.001+cm(log)" \
#         leiden-mod \
#         "leiden-mod+cm(log)" \
#         sbm-flat-best+cc \
#         "sbm-flat-best+wcc(log)" \
#         sbm-nested-best+cc \
#         "sbm-nested-best+wcc(log)"

# python network_evaluation/compare/visualize_comparisons.py \
#     --data-fp plots/old/agg_comp.csv \
#     --generators \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#         ec-sbm-v2 \
#         ec-sbm-v1 \
#     --clusterings \
#         leiden-cpm-0.1 \
#         leiden-cpm-0.1 \
#         "leiden-cpm-0.1+cm(log)" \
#         "leiden-cpm-0.1+cm(log)" \
#         "leiden-cpm-0.1+cm" \
#         "leiden-cpm-0.1+cm" \
#         leiden-cpm-0.01 \
#         leiden-cpm-0.01 \
#         "leiden-cpm-0.01+cm(log)" \
#         "leiden-cpm-0.01+cm(log)" \
#         "leiden-cpm-0.01+cm" \
#         "leiden-cpm-0.01+cm" \
#         leiden-cpm-0.001 \
#         leiden-cpm-0.001 \
#         "leiden-cpm-0.001+cm(log)" \
#         "leiden-cpm-0.001+cm(log)" \
#         "leiden-cpm-0.001+cm" \
#         "leiden-cpm-0.001+cm" \
#         leiden-mod \
#         leiden-mod \
#         "leiden-mod+cm(log)" \
#         "leiden-mod+cm(log)" \
#         "leiden-mod+cm" \
#         "leiden-mod+cm" \
#         "sbm-flat-best+cc" \
#         "sbm-flat-best+cc" \
#         "sbm-flat-best+wcc(log)" \
#         "sbm-flat-best+wcc(log)" \
#         "sbm-flat-best+wcc(sqrt)" \
#         "sbm-flat-best+wcc(sqrt)" \
#         "sbm-nested-best+cc" \
#         "sbm-nested-best+cc" \
#         "sbm-nested-best+wcc(log)" \
#         "sbm-nested-best+wcc(log)" \
#         "sbm-nested-best+wcc(sqrt)" \
#         "sbm-nested-best+wcc(sqrt)" \
#     --names \
#         "EC-SBMv2 x Leiden-CPM(0.1)" \
#         "EC-SBMv1 x Leiden-CPM(0.1)" \
#         "EC-SBMv2 x Leiden-CPM(0.1)+CM(log)" \
#         "EC-SBMv1 x Leiden-CPM(0.1)+CM(log)" \
#         "EC-SBMv2 x Leiden-CPM(0.1)+CM(sqrt)" \
#         "EC-SBMv1 x Leiden-CPM(0.1)+CM(sqrt)" \
#         "EC-SBMv2 x Leiden-CPM(0.01)" \
#         "EC-SBMv1 x Leiden-CPM(0.01)" \
#         "EC-SBMv2 x Leiden-CPM(0.01)+CM(log)" \
#         "EC-SBMv1 x Leiden-CPM(0.01)+CM(log)" \
#         "EC-SBMv2 x Leiden-CPM(0.01)+CM(sqrt)" \
#         "EC-SBMv1 x Leiden-CPM(0.01)+CM(sqrt)" \
#         "EC-SBMv2 x Leiden-CPM(0.001)" \
#         "EC-SBMv1 x Leiden-CPM(0.001)" \
#         "EC-SBMv2 x Leiden-CPM(0.001)+CM(log)" \
#         "EC-SBMv1 x Leiden-CPM(0.001)+CM(log)" \
#         "EC-SBMv2 x Leiden-CPM(0.001)+CM(sqrt)" \
#         "EC-SBMv1 x Leiden-CPM(0.001)+CM(sqrt)" \
#         "EC-SBMv2 x Leiden-Mod" \
#         "EC-SBMv1 x Leiden-Mod" \
#         "EC-SBMv2 x Leiden-Mod+CM(log)" \
#         "EC-SBMv1 x Leiden-Mod+CM(log)" \
#         "EC-SBMv2 x Leiden-Mod+CM(sqrt)" \
#         "EC-SBMv1 x Leiden-Mod+CM(sqrt)" \
#         "EC-SBMv2 x SBM(Flat)+CC" \
#         "EC-SBMv1 x SBM(Flat)+CC" \
#         "EC-SBMv2 x SBM(Flat)+WCC(log)" \
#         "EC-SBMv1 x SBM(Flat)+WCC(log)" \
#         "EC-SBMv2 x SBM(Flat)+WCC(sqrt)" \
#         "EC-SBMv1 x SBM(Flat)+WCC(sqrt)" \
#         "EC-SBMv2 x SBM(Nested)+CC" \
#         "EC-SBMv1 x SBM(Nested)+CC" \
#         "EC-SBMv2 x SBM(Nested)+WCC(log)" \
#         "EC-SBMv1 x SBM(Nested)+WCC(log)" \
#         "EC-SBMv2 x SBM(Nested)+WCC(sqrt)" \
#         "EC-SBMv1 x SBM(Nested)+WCC(sqrt)" \
#     --stats \
#         pseudo_diameter \
#         char_time \
#         global_ccoeff \
#         degree \
#         n_edges \
#         deg_assort \
#         node_percolation_targeted \
#         node_percolation_random \
#         local_ccoeff \
#         local_ccoeff_nodes \
#         pagerank \
#         kcore \
#     --types \
#         scalar \
#         scalar \
#         scalar \
#         sequence \
#         scalar \
#         scalar \
#         scalar \
#         scalar \
#         scalar \
#         sequence \
#         sequence \
#         sequence \
#     --metrics \
#         rel_diff \
#         rel_diff \
#         abs_diff \
#         rmse \
#         rel_diff \
#         abs_diff \
#         abs_diff \
#         abs_diff \
#         abs_diff \
#         rmse \
#         rmse \
#         rmse \
#     --network-fp data/networks_train_old.txt \
#     --output-dir plots/old/train/ \
#     --output-fn network \
#     --hide-fliers

# python network_evaluation/compare/visualize_comparisons.py \
#     --data-fp plots/old/agg_comp.csv \
#     --generators \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#     --clusterings \
#         leiden-cpm-0.1 \
#         "leiden-cpm-0.1+cm(log)" \
#         leiden-cpm-0.01 \
#         "leiden-cpm-0.01+cm(log)" \
#         leiden-cpm-0.001 \
#         "leiden-cpm-0.001+cm(log)" \
#         leiden-mod \
#         "leiden-mod+cm(log)" \
#         "sbm-flat-best+cc" \
#         "sbm-flat-best+wcc(log)" \
#         "sbm-nested-best+cc" \
#         "sbm-nested-best+wcc(log)" \
#     --names \
#         "EC-SBMv2 x Leiden-CPM(0.1)" \
#         "EC-SBMv2 x Leiden-CPM(0.1)+CM(log)" \
#         "EC-SBMv2 x Leiden-CPM(0.01)" \
#         "EC-SBMv2 x Leiden-CPM(0.01)+CM(log)" \
#         "EC-SBMv2 x Leiden-CPM(0.001)" \
#         "EC-SBMv2 x Leiden-CPM(0.001)+CM(log)" \
#         "EC-SBMv2 x Leiden-Mod" \
#         "EC-SBMv2 x Leiden-Mod+CM(log)" \
#         "EC-SBMv2 x SBM(Flat)+CC" \
#         "EC-SBMv2 x SBM(Flat)+WCC(log)" \
#         "EC-SBMv2 x SBM(Nested)+CC" \
#         "EC-SBMv2 x SBM(Nested)+WCC(log)" \
#     --stats \
#         pseudo_diameter \
#         char_time \
#         global_ccoeff \
#         degree \
#         n_edges \
#         deg_assort \
#         node_percolation_targeted \
#         node_percolation_random \
#         local_ccoeff \
#         local_ccoeff_nodes \
#         pagerank \
#         kcore \
#     --types \
#         scalar \
#         scalar \
#         scalar \
#         sequence \
#         scalar \
#         scalar \
#         scalar \
#         scalar \
#         scalar \
#         sequence \
#         sequence \
#         sequence \
#     --metrics \
#         rel_diff \
#         rel_diff \
#         abs_diff \
#         rmse \
#         rel_diff \
#         abs_diff \
#         abs_diff \
#         abs_diff \
#         abs_diff \
#         rmse \
#         rmse \
#         rmse \
#     --network-fp data/networks_all_old.txt \
#     --output-dir plots/old/all/ \
#     --output-fn network_ecsbmv2 \
#     --hide-fliers

# python network_evaluation/compare/visualize_comparisons.py \
#     --data-fp plots/old/agg_comp.csv \
#     --generators \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#     --clusterings \
#         leiden-cpm-0.1 \
#         "leiden-cpm-0.1+cm(log)" \
#         "sbm-flat-best+cc" \
#         "sbm-flat-best+wcc(log)" \
#     --names \
#         "EC-SBMv2 x Leiden-CPM(0.1)" \
#         "EC-SBMv2 x Leiden-CPM(0.1)+CM(log)" \
#         "EC-SBMv2 x SBM(Flat)+CC" \
#         "EC-SBMv2 x SBM(Flat)+WCC(log)" \
#     --stats \
#         pseudo_diameter \
#         char_time \
#         global_ccoeff \
#         degree \
#         n_edges \
#         deg_assort \
#         node_percolation_targeted \
#         node_percolation_random \
#         local_ccoeff \
#         local_ccoeff_nodes \
#         pagerank \
#         kcore \
#     --types \
#         scalar \
#         scalar \
#         scalar \
#         sequence \
#         scalar \
#         scalar \
#         scalar \
#         scalar \
#         scalar \
#         sequence \
#         sequence \
#         sequence \
#     --metrics \
#         rel_diff \
#         rel_diff \
#         abs_diff \
#         rmse \
#         rel_diff \
#         abs_diff \
#         abs_diff \
#         abs_diff \
#         abs_diff \
#         rmse \
#         rmse \
#         rmse \
#     --network-fp data/networks_train_old.txt \
#     --output-dir plots/old/train/ \
#     --output-fn network_ecsbm \
#     --hide-fliers

# python network_evaluation/compare/visualize_comparisons.py \
#     --data-fp plots/old/agg_comp.csv \
#     --generators \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#         ec-sbm-v1 \
#     --clusterings \
#         leiden-cpm-0.1 \
#         "leiden-cpm-0.1+cm(log)" \
#         "leiden-cpm-0.01+cm" \
#         leiden-mod \
#         "leiden-mod+cm(log)" \
#         "leiden-mod+cm" \
#         "sbm-flat-best+cc" \
#         "sbm-flat-best+wcc(log)" \
#         "sbm-flat-best+wcc(sqrt)" \
#         "sbm-nested-best+cc" \
#         "sbm-nested-best+wcc(log)" \
#         "sbm-nested-best+wcc(sqrt)" \
#     --names \
#         "EC-SBMv1 x Leiden-CPM(0.1)" \
#         "EC-SBMv1 x Leiden-CPM(0.1)+CM(log)" \
#         "EC-SBMv1 x Leiden-CPM(0.1)+CM(sqrt)" \
#         "EC-SBMv1 x Leiden-Mod" \
#         "EC-SBMv1 x Leiden-Mod+CM(log)" \
#         "EC-SBMv1 x Leiden-Mod+CM(sqrt)" \
#         "EC-SBMv1 x SBM(Flat)+CC" \
#         "EC-SBMv1 x SBM(Flat)+WCC(log)" \
#         "EC-SBMv1 x SBM(Flat)+WCC(sqrt)" \
#         "EC-SBMv1 x SBM(Nested)+CC" \
#         "EC-SBMv1 x SBM(Nested)+WCC(log)" \
#         "EC-SBMv1 x SBM(Nested)+WCC(sqrt)" \
#     --stats \
#         pseudo_diameter \
#         char_time \
#         global_ccoeff \
#         degree \
#         n_edges \
#         deg_assort \
#         node_percolation_targeted \
#         node_percolation_random \
#         local_ccoeff \
#         local_ccoeff_nodes \
#         pagerank \
#         kcore \
#     --types \
#         scalar \
#         scalar \
#         scalar \
#         sequence \
#         scalar \
#         scalar \
#         scalar \
#         scalar \
#         scalar \
#         sequence \
#         sequence \
#         sequence \
#     --metrics \
#         rel_diff \
#         rel_diff \
#         abs_diff \
#         rmse \
#         rel_diff \
#         abs_diff \
#         abs_diff \
#         abs_diff \
#         abs_diff \
#         rmse \
#         rmse \
#         rmse \
#     --network-fp data/networks_train_old.txt \
#     --output-dir plots/old/train/ \
#     --output-fn network_ecsbmv1 \
#     --hide-fliers

# python network_evaluation/compare/visualize_comparisons.py \
#     --data-fp plots/old/agg_comp.csv \
#     --generators \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#     --clusterings \
#         leiden-cpm-0.1 \
#         "leiden-cpm-0.1+cm(log)" \
#         "leiden-cpm-0.01+cm" \
#         leiden-mod \
#         "leiden-mod+cm(log)" \
#         "leiden-mod+cm" \
#         "sbm-flat-best+cc" \
#         "sbm-flat-best+wcc(log)" \
#         "sbm-flat-best+wcc(sqrt)" \
#         "sbm-nested-best+cc" \
#         "sbm-nested-best+wcc(log)" \
#         "sbm-nested-best+wcc(sqrt)" \
#     --names \
#         "EC-SBMv2 x Leiden-CPM(0.1)" \
#         "EC-SBMv2 x Leiden-CPM(0.1)+CM(log)" \
#         "EC-SBMv2 x Leiden-CPM(0.1)+CM(sqrt)" \
#         "EC-SBMv2 x Leiden-Mod" \
#         "EC-SBMv2 x Leiden-Mod+CM(log)" \
#         "EC-SBMv2 x Leiden-Mod+CM(sqrt)" \
#         "EC-SBMv2 x SBM(Flat)+CC" \
#         "EC-SBMv2 x SBM(Flat)+WCC(log)" \
#         "EC-SBMv2 x SBM(Flat)+WCC(sqrt)" \
#         "EC-SBMv2 x SBM(Nested)+CC" \
#         "EC-SBMv2 x SBM(Nested)+WCC(log)" \
#         "EC-SBMv2 x SBM(Nested)+WCC(sqrt)" \
#     --stats \
#         conductance \
#         modularity \
#         degree_density \
#         edge_density \
#         m \
#         c \
#         mincut \
#     --types \
#         sequence \
#         sequence \
#         sequence \
#         sequence \
#         sequence \
#         sequence \
#         sequence \
#     --metrics \
#         rmse \
#         rmse \
#         rmse \
#         rmse \
#         mean_l1 \
#         mean_l1 \
#         mean_l1 \
#     --network-fp data/networks_train_old.txt \
#     --output-dir plots/old/train/ \
#     --output-fn cluster_ecsbmv2 \
#     --hide-fliers
