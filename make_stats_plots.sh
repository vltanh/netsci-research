python visualize_stats.py \
    --root data/synthetic_networks \
    --networks_list data/networks_all_old.txt \
    --generator ec-sbm-v2 \
    --clusterings \
        leiden-cpm-0.1 \
        "leiden-cpm-0.1+cm(log)" \
        leiden-cpm-0.01 \
        "leiden-cpm-0.01+cm(log)" \
        leiden-cpm-0.001 \
        "leiden-cpm-0.001+cm(log)" \
        leiden-mod \
        "leiden-mod+cm(log)" \
        sbm-flat-best+cc \
        "sbm-flat-best+wcc(log)" \
        sbm-nested-best+cc \
        "sbm-nested-best+wcc(log)" \
    --clustering-names \
        "Leiden-CPM(0.1)" \
        "Leiden-CPM(0.1)+CM(log)" \
        "Leiden-CPM(0.01)" \
        "Leiden-CPM(0.01)+CM(log)" \
        "Leiden-CPM(0.001)" \
        "Leiden-CPM(0.001)+CM(log)" \
        "Leiden-Mod" \
        "Leiden-Mod+CM(log)" \
        "SBM-Flat(best)+CC" \
        "SBM-Flat(best)+WCC(log)" \
        "SBM-Nested(best)+CC" \
        "SBM-Nested(best)+WCC(log)" \
    --stats \
        node_coverage \
        ratio_wellconnected_clusters \
    --stat-names \
        "Node coverage" \
        "Proportion of well-connected clusters" \
    --xlim -0.1 1.1 \
    --output plots/old/stats/
