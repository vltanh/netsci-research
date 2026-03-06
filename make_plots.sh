#!/bin/sh

python aggregate_comparisons.py \
    --output-dir plots/ec-sbm/ \
    --output-fn agg_comp.csv \
    --generators ec-sbm-v2 ec-sbm-v1.5 \
    --clusterings \
        leiden-cpm-0.5 \
        leiden-cpm-0.5+cm \
        leiden-cpm-0.1 \
        leiden-cpm-0.1+cm \
        leiden-mod \
        leiden-mod+cm

python visualize_comparisons.py \
    --data-fp plots/ec-sbm/agg_comp.csv \
    --generators \
        ec-sbm-v2 \
        ec-sbm-v1.5 \
        ec-sbm-v2 \
        ec-sbm-v1.5 \
        ec-sbm-v2 \
        ec-sbm-v1.5 \
        ec-sbm-v2 \
        ec-sbm-v1.5 \
        ec-sbm-v2 \
        ec-sbm-v1.5 \
        ec-sbm-v2 \
        ec-sbm-v1.5 \
    --clusterings \
        leiden-cpm-0.5 \
        leiden-cpm-0.5 \
        leiden-cpm-0.5+cm \
        leiden-cpm-0.5+cm \
        leiden-cpm-0.1 \
        leiden-cpm-0.1 \
        leiden-cpm-0.1+cm \
        leiden-cpm-0.1+cm \
        leiden-mod \
        leiden-mod \
        leiden-mod+cm \
        leiden-mod+cm \
    --names \
        "EC-SBMv2 x Leiden-CPM(0.5)" \
        "EC-SBMv1.5 x Leiden-CPM(0.5)" \
        "EC-SBMv2 x Leiden-CPM(0.5)+CM" \
        "EC-SBMv1.5 x Leiden-CPM(0.5)+CM" \
        "EC-SBMv2 x Leiden-CPM(0.1)" \
        "EC-SBMv1.5 x Leiden-CPM(0.1)" \
        "EC-SBMv2 x Leiden-CPM(0.1)+CM" \
        "EC-SBMv1.5 x Leiden-CPM(0.1)+CM" \
        "EC-SBMv2 x Leiden-Mod" \
        "EC-SBMv1.5 x Leiden-Mod" \
        "EC-SBMv2 x Leiden-Mod+CM" \
        "EC-SBMv1.5 x Leiden-Mod+CM" \
    --stats \
        degree \
        n_edges \
        deg_assort \
        diameter \
        global_ccoeff \
        local_ccoeff \
    --types \
        sequence \
        scalar \
        scalar \
        scalar \
        scalar \
        scalar \
    --metrics \
        rmse \
        rel_diff \
        abs_diff \
        rel_diff \
        abs_diff \
        abs_diff \
    --network-fp data/networks_train.txt \
    --output-dir plots/ec-sbm/train/ \
    --output-fn network \
    --hide-fliers

# python visualize_comparisons.py \
#     --data-fp plots/ec-sbm-v2/agg_comp.csv \
#     --generators \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#         ec-sbm-v2 \
#     --clusterings \
#         leiden-cpm-0.5 \
#         leiden-cpm-0.5+cm \
#         leiden-cpm-0.1 \
#         leiden-cpm-0.1+cm \
#         leiden-mod \
#         leiden-mod+cm \
#     --names \
#         "EC-SBMv2 x Leiden-CPM(0.5)" \
#         "EC-SBMv2 x Leiden-CPM(0.5)+CM" \
#         "EC-SBMv2 x Leiden-CPM(0.1)" \
#         "EC-SBMv2 x Leiden-CPM(0.1)+CM" \
#         "EC-SBMv2 x Leiden-Mod" \
#         "EC-SBMv2 x Leiden-Mod+CM" \
#     --stats \
#         degree \
#         n_edges \
#         deg_assort \
#         diameter \
#         global_ccoeff \
#         local_ccoeff \
#     --types \
#         sequence \
#         scalar \
#         scalar \
#         scalar \
#         scalar \
#         scalar \
#     --metrics \
#         rmse \
#         rel_diff \
#         abs_diff \
#         rel_diff \
#         abs_diff \
#         abs_diff \
#     --network-fp data/networks_train.txt \
#     --output-dir plots/ec-sbm-v2/train/ \
#     --output-fn network \
#     --hide-fliers
