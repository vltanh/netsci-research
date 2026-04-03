# Very small

python aggregate_acc.py \
    --base-dir data/estimated_clusterings/ \
    --output plots/cd/ec-sbm-v2/verysmall/sbm-flat-best+cc/agg_acc.csv \
    --network-list data/networks_verysmall.txt \
    --generator ec-sbm-v2 \
    --gt-clustering sbm-flat-best+cc \
    --algos \
        leiden-mod \
        "leiden-mod+cm(log)" \
        leiden-cpm-0.1 \
        "leiden-cpm-0.1+cm(log)" \
        leiden-cpm-0.01 \
        "leiden-cpm-0.01+cm(log)" \
        leiden-cpm-0.001 \
        "leiden-cpm-0.001+cm(log)"

python visualize_acc.py \
    --data-fp plots/cd/ec-sbm-v2/verysmall/sbm-flat-best+cc/agg_acc.csv \
    --network-fp data/networks_verysmall.txt \
    --algos \
        leiden-mod \
        "leiden-mod+cm(log)" \
        leiden-cpm-0.1 \
        "leiden-cpm-0.1+cm(log)" \
        leiden-cpm-0.01 \
        "leiden-cpm-0.01+cm(log)" \
        leiden-cpm-0.001 \
        "leiden-cpm-0.001+cm(log)" \
    --names \
        "Leiden-Mod" \
        "Leiden-Mod+CM(log)" \
        "Leiden-CPM(0.1)" \
        "Leiden-CPM(0.1)+CM(log)" \
        "Leiden-CPM(0.01)" \
        "Leiden-CPM(0.01)+CM(log)" \
        "Leiden-CPM(0.001)" \
        "Leiden-CPM(0.001)+CM(log)" \
    --metrics \
        ami \
        ari \
        nmi \
    --metric-names \
        AMI \
        ARI \
        NMI \
    --output-dir plots/cd/ec-sbm-v2/verysmall/sbm-flat-best+cc/ \
    --output-fn acc \
    --xlim 0.0 1.0

python aggregate_acc.py \
    --base-dir data/estimated_clusterings/ \
    --output plots/cd/ec-sbm-v2/verysmall/leiden-cpm-0.1/agg_acc.csv \
    --network-list data/networks_verysmall.txt \
    --generator ec-sbm-v2 \
    --gt-clustering leiden-cpm-0.1 \
    --algos \
        sbm-flat-dc+cc \
        "sbm-flat-dc+wcc(log)" \
        sbm-flat-ndc+cc \
        "sbm-flat-ndc+wcc(log)" \
        sbm-flat-pp+cc \
        "sbm-flat-pp+wcc(log)" \
        sbm-flat-best+cc \
        "sbm-flat-best+wcc(log)" \
        sbm-nested-dc+cc \
        "sbm-nested-dc+wcc(log)" \
        sbm-nested-ndc+cc \
        "sbm-nested-ndc+wcc(log)" \
        sbm-nested-best+cc \
        "sbm-nested-best+wcc(log)"

python visualize_acc.py \
    --data-fp plots/cd/ec-sbm-v2/verysmall/leiden-cpm-0.1/agg_acc.csv \
    --network-fp data/networks_verysmall.txt \
    --algos \
        sbm-flat-dc+cc \
        "sbm-flat-dc+wcc(log)" \
        sbm-flat-ndc+cc \
        "sbm-flat-ndc+wcc(log)" \
        sbm-flat-pp+cc \
        "sbm-flat-pp+wcc(log)" \
        sbm-flat-best+cc \
        "sbm-flat-best+wcc(log)" \
        sbm-nested-dc+cc \
        "sbm-nested-dc+wcc(log)" \
        sbm-nested-ndc+cc \
        "sbm-nested-ndc+wcc(log)" \
        sbm-nested-best+cc \
        "sbm-nested-best+wcc(log)" \
    --names \
        "SBM-Flat-DC+CC" \
        "SBM-Flat-DC+WCC(log)" \
        "SBM-Flat-NDC+CC" \
        "SBM-Flat-NDC+WCC(log)" \
        "SBM-Flat-PP+CC" \
        "SBM-Flat-PP+WCC(log)" \
        "SBM-Flat-Best+CC" \
        "SBM-Flat-Best+WCC(log)" \
        "SBM-Nested-DC+CC" \
        "SBM-Nested-DC+WCC(log)" \
        "SBM-Nested-NDC+CC" \
        "SBM-Nested-NDC+WCC(log)" \
        "SBM-Nested-Best+CC" \
        "SBM-Nested-Best+WCC(log)" \
    --metrics \
        ami \
        ari \
        nmi \
    --metric-names \
        AMI \
        ARI \
        NMI \
    --output-dir plots/cd/ec-sbm-v2/verysmall/leiden-cpm-0.1/ \
    --output-fn acc \
    --xlim 0.0 1.0

# Old (train)

python aggregate_acc.py \
    --base-dir data/estimated_clusterings/ \
    --output plots/cd/ec-sbm-v2/old/train/sbm-flat-best+cc/agg_acc.csv \
    --network-list data/networks_train_old.txt \
    --generator ec-sbm-v2 \
    --gt-clustering sbm-flat-best+cc \
    --algos \
        leiden-mod \
        "leiden-mod+cm(log)" \
        leiden-cpm-0.1 \
        "leiden-cpm-0.1+cm(log)" \
        leiden-cpm-0.01 \
        "leiden-cpm-0.01+cm(log)" \
        leiden-cpm-0.001 \
        "leiden-cpm-0.001+cm(log)"

python visualize_acc.py \
    --data-fp plots/cd/ec-sbm-v2/old/train/sbm-flat-best+cc/agg_acc.csv \
    --network-fp data/networks_train_old.txt \
    --algos \
        leiden-mod \
        "leiden-mod+cm(log)" \
        leiden-cpm-0.1 \
        "leiden-cpm-0.1+cm(log)" \
        leiden-cpm-0.01 \
        "leiden-cpm-0.01+cm(log)" \
        leiden-cpm-0.001 \
        "leiden-cpm-0.001+cm(log)" \
    --names \
        "Leiden-Mod" \
        "Leiden-Mod+CM(log)" \
        "Leiden-CPM(0.1)" \
        "Leiden-CPM(0.1)+CM(log)" \
        "Leiden-CPM(0.01)" \
        "Leiden-CPM(0.01)+CM(log)" \
        "Leiden-CPM(0.001)" \
        "Leiden-CPM(0.001)+CM(log)" \
    --metrics \
        ami \
        ari \
        nmi \
    --metric-names \
        AMI \
        ARI \
        NMI \
    --output-dir plots/cd/ec-sbm-v2/old/train/sbm-flat-best+cc/ \
    --output-fn acc \
    --xlim 0.0 1.0

python aggregate_acc.py \
    --base-dir data/estimated_clusterings/ \
    --output plots/cd/ec-sbm-v2/old/train/leiden-cpm-0.1/agg_acc.csv \
    --network-list data/networks_train_old.txt \
    --generator ec-sbm-v2 \
    --gt-clustering leiden-cpm-0.1 \
    --algos \
        sbm-flat-dc+cc \
        "sbm-flat-dc+wcc(log)" \
        sbm-flat-ndc+cc \
        "sbm-flat-ndc+wcc(log)" \
        sbm-flat-pp+cc \
        "sbm-flat-pp+wcc(log)" \
        sbm-flat-best+cc \
        "sbm-flat-best+wcc(log)" \
        sbm-nested-dc+cc \
        "sbm-nested-dc+wcc(log)" \
        sbm-nested-ndc+cc \
        "sbm-nested-ndc+wcc(log)" \
        sbm-nested-best+cc \
        "sbm-nested-best+wcc(log)"

python visualize_acc.py \
    --data-fp plots/cd/ec-sbm-v2/old/train/leiden-cpm-0.1/agg_acc.csv \
    --network-fp data/networks_train_old.txt \
    --algos \
        sbm-flat-dc+cc \
        "sbm-flat-dc+wcc(log)" \
        sbm-flat-ndc+cc \
        "sbm-flat-ndc+wcc(log)" \
        sbm-flat-pp+cc \
        "sbm-flat-pp+wcc(log)" \
        sbm-flat-best+cc \
        "sbm-flat-best+wcc(log)" \
        sbm-nested-dc+cc \
        "sbm-nested-dc+wcc(log)" \
        sbm-nested-ndc+cc \
        "sbm-nested-ndc+wcc(log)" \
        sbm-nested-best+cc \
        "sbm-nested-best+wcc(log)" \
    --names \
        "SBM-Flat-DC+CC" \
        "SBM-Flat-DC+WCC(log)" \
        "SBM-Flat-NDC+CC" \
        "SBM-Flat-NDC+WCC(log)" \
        "SBM-Flat-PP+CC" \
        "SBM-Flat-PP+WCC(log)" \
        "SBM-Flat-Best+CC" \
        "SBM-Flat-Best+WCC(log)" \
        "SBM-Nested-DC+CC" \
        "SBM-Nested-DC+WCC(log)" \
        "SBM-Nested-NDC+CC" \
        "SBM-Nested-NDC+WCC(log)" \
        "SBM-Nested-Best+CC" \
        "SBM-Nested-Best+WCC(log)" \
    --metrics \
        ami \
        ari \
        nmi \
    --metric-names \
        AMI \
        ARI \
        NMI \
    --output-dir plots/cd/ec-sbm-v2/old/train/leiden-cpm-0.1/ \
    --output-fn acc \
    --xlim 0.0 1.0
