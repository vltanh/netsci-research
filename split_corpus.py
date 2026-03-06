import random


def ordered_split(input_file, ratios=(0.7, 0.15, 0.15), seed=0):
    # 1. Load lines
    with open(input_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    total = len(lines)

    # 2. Create a list of assignments (0, 1, or 2) based on ratios
    num_train = int(total * ratios[0])
    num_val = int(total * ratios[1])
    num_test = total - num_train - num_val

    assignments = ([0] * num_train) + ([1] * num_val) + ([2] * num_test)

    # 3. Shuffle ONLY the assignments, not the data
    random.seed(seed)
    random.shuffle(assignments)

    # 4. Distribute lines based on the shuffled assignment map
    train_lines, val_lines, test_lines = [], [], []

    for i, line in enumerate(lines):
        target = assignments[i]
        if target == 0:
            train_lines.append(line)
        elif target == 1:
            val_lines.append(line)
        else:
            test_lines.append(line)

    # 5. Save files
    files = [
        "data/networks_train.txt",
        "data/networks_val.txt",
        "data/networks_test.txt",
    ]
    datasets = [train_lines, val_lines, test_lines]

    for name, content in zip(files, datasets):
        with open(name, "w", encoding="utf-8") as f:
            f.writelines(content)
        print(f"Done: {name} ({len(content)} lines, order preserved)")


# Execute
ordered_split("data/networks_all.txt", ratios=(0.5, 0.2, 0.3), seed=0)
