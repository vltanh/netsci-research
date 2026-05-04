# python visualize_stats.py \
#     --root data/synthetic_networks \
#     --networks data/networks_all_old.txt \
#     --generator ec-sbm-v2 \
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
#         "sbm-nested-best+wcc(log)" \
#     --clustering-names \
#         "Leiden-CPM(0.1)" \
#         "Leiden-CPM(0.1)+CM(log)" \
#         "Leiden-CPM(0.01)" \
#         "Leiden-CPM(0.01)+CM(log)" \
#         "Leiden-CPM(0.001)" \
#         "Leiden-CPM(0.001)+CM(log)" \
#         "Leiden-Mod" \
#         "Leiden-Mod+CM(log)" \
#         "SBM-Flat(best)+CC" \
#         "SBM-Flat(best)+WCC(log)" \
#         "SBM-Nested(best)+CC" \
#         "SBM-Nested(best)+WCC(log)" \
#     --stats \
#         node_coverage \
#         ratio_wellconnected_clusters \
#     --stat-names \
#         "Node coverage" \
#         "Proportion of well-connected clusters" \
#     --xlim -0.1 1.1 \
#     --output plots/old/stats/

# python visualize_stats.py \
#     --path-template "{root}/{generator}/{gt_clustering}/stats/{clustering}/{network}/0" \
#     --root data/estimated_clusterings \
#     --generator ec-sbm-v2 \
#     --gt-clustering leiden-cpm-0.1 \
#     --networks data/big.txt \
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
#         "sbm-nested-best+wcc(log)" \
#     --clustering-names \
#         "Leiden-CPM(0.1)" \
#         "Leiden-CPM(0.1)+CM(log)" \
#         "Leiden-CPM(0.01)" \
#         "Leiden-CPM(0.01)+CM(log)" \
#         "Leiden-CPM(0.001)" \
#         "Leiden-CPM(0.001)+CM(log)" \
#         "Leiden-Mod" \
#         "Leiden-Mod+CM(log)" \
#         "SBM-Flat(best)+CC" \
#         "SBM-Flat(best)+WCC(log)" \
#         "SBM-Nested(best)+CC" \
#         "SBM-Nested(best)+WCC(log)" \
#     --stats \
#         small_cluster_coverage \
#         cluster_size_min \
#         cluster_size_q1 \
#         cluster_size_median \
#         cluster_size_q3 \
#         cluster_size_max \
#         cluster_size_mean \
#     --stat-names \
#         "Small cluster coverage" \
#         "Min cluster size" \
#         "Q1 cluster size" \
#         "Median cluster size" \
#         "Q3 cluster size" \
#         "Max cluster size" \
#         "Mean cluster size" \
#     --plot-name "cluster_size_leiden-cpm-0.1" \
#     --log-scale \
#     --output plots/estimated/stats/

# python visualize_stats.py \
#     --path-template "{root}/{generator}/{gt_clustering}/stats/{clustering}/{network}/0" \
#     --root data/estimated_clusterings \
#     --generator ec-sbm-v2 \
#     --gt-clustering sbm-flat-best+cc \
#     --networks data/big.txt \
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
#         "sbm-nested-best+wcc(log)" \
#     --clustering-names \
#         "Leiden-CPM(0.1)" \
#         "Leiden-CPM(0.1)+CM(log)" \
#         "Leiden-CPM(0.01)" \
#         "Leiden-CPM(0.01)+CM(log)" \
#         "Leiden-CPM(0.001)" \
#         "Leiden-CPM(0.001)+CM(log)" \
#         "Leiden-Mod" \
#         "Leiden-Mod+CM(log)" \
#         "SBM-Flat(best)+CC" \
#         "SBM-Flat(best)+WCC(log)" \
#         "SBM-Nested(best)+CC" \
#         "SBM-Nested(best)+WCC(log)" \
#     --stats \
#         small_cluster_coverage \
#         cluster_size_min \
#         cluster_size_q1 \
#         cluster_size_median \
#         cluster_size_q3 \
#         cluster_size_max \
#         cluster_size_mean \
#     --stat-names \
#         "Small cluster coverage" \
#         "Min cluster size" \
#         "Q1 cluster size" \
#         "Median cluster size" \
#         "Q3 cluster size" \
#         "Max cluster size" \
#         "Mean cluster size" \
#     --plot-name "cluster_size_sbm-flat-best+cc" \
#     --log-scale \
#     --output plots/estimated/stats/

# python visualize_stats.py \
#     --path-template "data/reference_clusterings/stats/{clustering}/{network}" \
#     --network-axis network \
#     --networks data/big.txt \
#     --method-axis clustering \
#     --methods \
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
#         "sbm-nested-best+wcc(log)" \
#     --method-names \
#         "Leiden-CPM(0.1)" \
#         "Leiden-CPM(0.1)+CM(log)" \
#         "Leiden-CPM(0.01)" \
#         "Leiden-CPM(0.01)+CM(log)" \
#         "Leiden-CPM(0.001)" \
#         "Leiden-CPM(0.001)+CM(log)" \
#         "Leiden-Mod" \
#         "Leiden-Mod+CM(log)" \
#         "SBM-Flat(best)+CC" \
#         "SBM-Flat(best)+WCC(log)" \
#         "SBM-Nested(best)+CC" \
#         "SBM-Nested(best)+WCC(log)" \
#     --stats \
#         small_cluster_coverage \
#         n:pooled \
#     --stat-names \
#         "Small cluster coverage" \
#         "Pooled cluster size" \
#     --plot-name "cluster_size_gt" \
#     --output plots/estimated/stats/

# python visualize_stats.py \
#     --path-template "data/reference_clusterings/stats/{clustering}/{network}" \
#     --network-axis network \
#     --networks data/networks_large.txt \
#     --method-axis clustering \
#     --methods \
#         leiden-cpm-0.1 \
#         "leiden-cpm-0.1+cm(log)" \
#         "leiden-cpm-0.1+cm(piecewise)" \
#         leiden-cpm-0.01 \
#         "leiden-cpm-0.01+cm(log)" \
#         "leiden-cpm-0.01+cm(piecewise)" \
#         leiden-cpm-0.001 \
#         "leiden-cpm-0.001+cm(log)" \
#         "leiden-cpm-0.001+cm(piecewise)" \
#         leiden-cpm-0.0001 \
#         "leiden-cpm-0.0001+cm(log)" \
#         "leiden-cpm-0.0001+cm(piecewise)" \
#         leiden-mod \
#         "leiden-mod+cm(log)" \
#         "leiden-mod+cm(piecewise)" \
#     --method-names \
#         "Leiden-CPM(0.1)" \
#         "Leiden-CPM(0.1)+CM(log)" \
#         "Leiden-CPM(0.1)+CM(piecewise)" \
#         "Leiden-CPM(0.01)" \
#         "Leiden-CPM(0.01)+CM(log)" \
#         "Leiden-CPM(0.01)+CM(piecewise)" \
#         "Leiden-CPM(0.001)" \
#         "Leiden-CPM(0.001)+CM(log)" \
#         "Leiden-CPM(0.001)+CM(piecewise)" \
#         "Leiden-CPM(0.0001)" \
#         "Leiden-CPM(0.0001)+CM(log)" \
#         "Leiden-CPM(0.0001)+CM(piecewise)" \
#         "Leiden-Mod" \
#         "Leiden-Mod+CM(log)" \
#         "Leiden-Mod+CM(piecewise)" \
#     --stats \
#         n:pooled \
#     --stat-names \
#         "Pooled cluster size" \
#     --plot-name "cluster_size_gt" \
#     --output plots/estimated/stats/

python visualize_stats.py \
    --path-template "data/reference_clusterings/stats/{clustering}/{network}" \
    --network-axis network \
    --networks data/networks_large.txt cen \
    --method-axis clustering \
    --methods \
        leiden-cpm-0.0001 \
    --method-names \
        "Leiden-CPM(0.0001)" \
    --stats \
        small_cluster_coverage \
        n:pooled \
    --stat-names \
        "Small cluster coverage" \
        "Pooled cluster size" \
    --plot-name "cluster_size_gt_leiden-cpm-0.0001" \
    --output plots/estimated/stats/

python visualize_stats.py \
    --path-template "data/reference_clusterings/stats/{clustering}/{network}" \
    --network-axis network \
    --networks data/networks_large.txt cen \
    --method-axis clustering \
    --methods \
        leiden-cpm-0.0001 \
        "leiden-cpm-0.0001+cm(piecewise)" \
    --method-names \
        "Leiden-CPM(0.0001)" \
        "Leiden-CPM(0.0001)+CM(piecewise)" \
    --stats \
        small_cluster_coverage \
        n:pooled \
    --stat-names \
        "Small cluster coverage" \
        "Pooled cluster size" \
    --plot-name "cluster_size_gt_leiden-cpm-0.0001+cm(F)" \
    --output plots/estimated/stats/

python visualize_stats.py \
    --path-template "data/reference_clusterings/stats/{clustering}/{network}" \
    --network-axis network \
    --networks cen \
    --method-axis clustering \
    --methods \
        leiden-cpm-0.0001 \
    --method-names \
        "Leiden-CPM(0.0001)" \
    --stats \
        small_cluster_coverage \
        n:pooled \
    --stat-names \
        "Small cluster coverage" \
        "Pooled cluster size" \
    --plot-name "cluster_size_gt_cen_leiden-cpm-0.0001" \
    --output plots/estimated/stats/
