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
