#!/usr/bin/env python3
# export_model_to_bram_unified.py
# Export Random Forest to unified BRAM arrays for Verilog

import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
import os

# ---------- Configuration ----------
NUM_TREES = 100          # масштабируем
MAX_DEPTH = 6
NUM_FEATURES = 17
MAX_NODES_PER_TREE = (1 << (MAX_DEPTH + 1)) - 1   # для полного бинарного дерева глубины 6 -> 127 узлов
OUTPUT_DIR = "../rtl/bram_init"
VERILOG_HEADER = "tree_nodes_unified.vh"
# -----------------------------------

def quantize_fixed_point(value, frac_bits=5, int_bits=10):
    scale = 1 << frac_bits
    max_val = (1 << (int_bits + frac_bits - 1)) - 1
    min_val = -(1 << (int_bits + frac_bits - 1))
    q = int(round(value * scale))
    return np.clip(q, min_val, max_val)

def export_trees_to_unified_mem(clf, max_nodes_per_tree, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    
    # Инициализируем массивы с запасом (по умолчанию 0 / 0xFF)
    num_trees = len(clf.estimators_)
    total_nodes = num_trees * max_nodes_per_tree
    
    node_feature = np.zeros(total_nodes, dtype=np.uint8)        # 5 бит feature (0..16), но храним как 8 бит
    node_threshold = np.zeros(total_nodes, dtype=np.int16)      # 16 бит signed
    node_left = np.zeros(total_nodes, dtype=np.uint8)           # 8 бит
    node_right = np.zeros(total_nodes, dtype=np.uint8)
    node_leaf_class = np.full(total_nodes, 0xFF, dtype=np.uint8) # 0xFF = internal node marker
    
    for tree_id, tree in enumerate(clf.estimators_):
        tree_data = tree.tree_
        n_nodes = tree_data.node_count
        offset = tree_id * max_nodes_per_tree
        
        for node_id in range(n_nodes):
            idx = offset + node_id
            # feature
            if tree_data.children_left[node_id] != tree_data.children_right[node_id]:
                node_feature[idx] = tree_data.feature[node_id] & 0x1F   # feature index 0..16
            else:
                node_feature[idx] = 0   # leaf, feature unused
            
            # threshold (only for internal nodes)
            thr = 0
            if tree_data.children_left[node_id] != tree_data.children_right[node_id]:
                thr = tree_data.threshold[node_id]
            node_threshold[idx] = quantize_fixed_point(thr, frac_bits=5, int_bits=10)
            
            # children
            left = tree_data.children_left[node_id] if tree_data.children_left[node_id] != -1 else 0
            right = tree_data.children_right[node_id] if tree_data.children_right[node_id] != -1 else 0
            node_left[idx] = left & 0xFF
            node_right[idx] = right & 0xFF
            
            # leaf class (0 or 1), for internal nodes keep 0xFF
            if tree_data.children_left[node_id] == tree_data.children_right[node_id]:
                values = tree_data.value[node_id][0]
                node_leaf_class[idx] = np.argmax(values) & 0x1
    
    # Сохраняем как .mem файлы (hex)
    feature_file = os.path.join(output_dir, "unified_feature.mem")
    threshold_file = os.path.join(output_dir, "unified_threshold.mem")
    left_file = os.path.join(output_dir, "unified_left.mem")
    right_file = os.path.join(output_dir, "unified_right.mem")
    class_file = os.path.join(output_dir, "unified_class.mem")
    
    with open(feature_file, 'w') as f:
        for v in node_feature:
            f.write(f"{v:02X}\n")
    with open(threshold_file, 'w') as f:
        for v in node_threshold:
            # signed 16-bit hex
            if v < 0:
                v_hex = f"{(v + (1<<16)) & 0xFFFF:04X}"
            else:
                v_hex = f"{v:04X}"
            f.write(f"{v_hex}\n")
    with open(left_file, 'w') as f:
        for v in node_left:
            f.write(f"{v:02X}\n")
    with open(right_file, 'w') as f:
        for v in node_right:
            f.write(f"{v:02X}\n")
    with open(class_file, 'w') as f:
        for v in node_leaf_class:
            f.write(f"{v:02X}\n")
    
    return total_nodes, max_nodes_per_tree

def generate_verilog_header(output_dir, num_trees, max_nodes_per_tree, total_nodes):
    header_path = os.path.join(output_dir, VERILOG_HEADER)
    with open(header_path, 'w') as f:
        f.write("// Auto-generated unified BRAM arrays\n")
        f.write("// DO NOT EDIT MANUALLY\n\n")
        f.write("`ifndef TREE_NODES_UNIFIED_VH\n")
        f.write("`define TREE_NODES_UNIFIED_VH\n\n")
        f.write(f"`define NUM_TREES {num_trees}\n")
        f.write(f"`define MAX_NODES_PER_TREE {max_nodes_per_tree}\n")
        f.write(f"`define TOTAL_NODES {total_nodes}\n\n")
        
        f.write("// BRAM arrays (single memory block)\n")
        f.write("reg [4:0] unified_node_feature [0:`TOTAL_NODES-1];\n")
        f.write("reg signed [15:0] unified_node_threshold [0:`TOTAL_NODES-1];\n")
        f.write("reg [7:0] unified_node_left [0:`TOTAL_NODES-1];\n")
        f.write("reg [7:0] unified_node_right [0:`TOTAL_NODES-1];\n")
        f.write("reg [7:0] unified_node_leaf_class [0:`TOTAL_NODES-1];\n\n")
        
        f.write("// Load initialization files\n")
        f.write("initial begin\n")
        f.write("    $readmemh(\"bram_init/unified_feature.mem\", unified_node_feature);\n")
        f.write("    $readmemh(\"bram_init/unified_threshold.mem\", unified_node_threshold);\n")
        f.write("    $readmemh(\"bram_init/unified_left.mem\", unified_node_left);\n")
        f.write("    $readmemh(\"bram_init/unified_right.mem\", unified_node_right);\n")
        f.write("    $readmemh(\"bram_init/unified_class.mem\", unified_node_leaf_class);\n")
        f.write("end\n\n")
        
        f.write("`endif\n")
    print(f"Verilog header written to {header_path}")

def main():
    # Генерация или загрузка данных
    X, y = make_classification(n_samples=100000, n_features=NUM_FEATURES,
                               n_informative=10, n_redundant=3, flip_y=0.05, random_state=42)
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)
    
    clf = RandomForestClassifier(n_estimators=NUM_TREES, max_depth=MAX_DEPTH, n_jobs=-1)
    clf.fit(X_train, y_train)
    print(f"Accuracy: {clf.score(X_test, y_test):.2%}")
    
    total_nodes, max_nodes = export_trees_to_unified_mem(clf, MAX_NODES_PER_TREE, OUTPUT_DIR)
    generate_verilog_header(OUTPUT_DIR, NUM_TREES, max_nodes, total_nodes)
    print("Done.")

if __name__ == "__main__":
    main()
