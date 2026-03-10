# community_detection/run_cd.sh

# Custom simulating real
./community_detection/run_cd.sh \
    --algo sbm-flat-dc \
    --criterion log \
    --input-edgelist test/input/dnc/dnc.csv \
    --output-dir test/output/reference_clusterings \
    --network dnc \
    --run-stats \
    --run-cc --run-wcc --run-cm

./community_detection/run_cd.sh \
    --algo sbm-flat-dc \
    --criterion log \
    --real \
    --network dnc \
    --run-stats \
    --run-cc --run-wcc --run-cm

# Custom simulating synthetic
./community_detection/run_cd.sh \
    --algo sbm-flat-best \
    --criterion sqrt \
    --input-edgelist "test/output/synthetic_networks/networks/ec-sbm-v2/sbm-flat-best+wcc(log)/dnc/0/edge.csv" \
    --input-gt-clustering "test/output/reference_clusterings/clusterings/sbm-flat-best+wcc(log)/dnc/com.csv" \
    --output-dir test/output/estimated_clusterings \
    --network dnc --generator ec-sbm-v2 --gt-clustering-id "sbm-flat-best+wcc(log)" --run-id 0 \
    --run-stats --run-acc \
    --run-cc --run-wcc --run-cm

./community_detection/run_cd.sh \
    --algo sbm-flat-best \
    --criterion sqrt \
    --synthetic \
    --network dnc --generator ec-sbm-v2 --gt-clustering-id "sbm-flat-best+wcc(log)" --run-id 0 \
    --run-cc --run-wcc --run-cm --run-stats --run-acc

# network_generation/run_generator.sh

# Custom simulating macro
./network_generation/run_generator.sh \
    --generator ec-sbm-v2 --run-id 0 \
    --input-edgelist test/input/dnc/dnc.csv \
    --input-clustering "test/output/reference_clusterings/clusterings/sbm-flat-best+wcc(log)/dnc/com.csv" \
    --input-network-stats test/output/empirical_networks/stats/dnc \
    --input-cluster-stats "test/output/reference_clusterings/stats/sbm-flat-best+wcc(log)/dnc" \
    --output-dir test/output/synthetic_networks/ \
    --network dnc --clustering-id "sbm-flat-best+wcc(log)"  \
    --run-stats --run-comp

./network_generation/run_generator.sh \
    --generator ec-sbm-v2 --run-id 0 \
    --macro \
    --network dnc --clustering-id "sbm-flat-best+wcc(log)"  \
    --run-stats --run-comp