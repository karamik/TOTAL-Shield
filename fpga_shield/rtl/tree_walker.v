// tree_walker.v
module tree_walker (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire [15:0] features [0:16],  // 17 features
    output reg attack_detected,
    output reg [4:0] vote_count         // how many trees voted attack
);

    // Node structure: {is_leaf, feature_idx, threshold, left_child, right_child, leaf_class}
    // We'll store nodes in BRAM initialised from .mem file.
    // For simplicity, we hardcode a small example with 2 trees depth 2.
    
    localparam NUM_TREES = 30;
    localparam MAX_DEPTH = 6;
    
    reg [4:0] tree_votes; // count of trees predicting attack
    
    // Example: node format (packed)
    // 32-bit word: {1'b is_leaf, 5'b feature_idx, 16'b threshold, 2'b reserved, 8'b child_or_class}
    // Better to use separate arrays.
    reg [0:NUM_TREES-1][0:(1<<MAX_DEPTH)-1] node_feature;
    reg [0:NUM_TREES-1][0:(1<<MAX_DEPTH)-1] node_threshold;
    reg [0:NUM_TREES-1][0:(1<<MAX_DEPTH)-1] node_left;
    reg [0:NUM_TREES-1][0:(1<<MAX_DEPTH)-1] node_right;
    reg [0:NUM_TREES-1][0:(1<<MAX_DEPTH)-1] node_leaf_class;
    
    // Load initialised values (from Python script)
    initial begin
        // This would be replaced by $readmemh or embedded values
        // Example for one tree (tree 0):
        // node_feature[0][0] = 0; node_threshold[0][0] = 100; ...
    end
    
    integer t, idx;
    reg [7:0] cur_node;
    reg [7:0] class_result [0:NUM_TREES-1];
    
    always @(posedge clk) begin
        if (rst) begin
            attack_detected <= 0;
            vote_count <= 0;
        end else if (enable) begin
            // Walk each tree (sequential over trees, but can be parallelised)
            tree_votes = 0;
            for (t = 0; t < NUM_TREES; t = t + 1) begin
                cur_node = 0;
                while (!node_leaf_class[t][cur_node]) begin
                    if (features[node_feature[t][cur_node]] <= node_threshold[t][cur_node])
                        cur_node = node_left[t][cur_node];
                    else
                        cur_node = node_right[t][cur_node];
                end
                class_result[t] = node_leaf_class[t][cur_node];
                if (class_result[t] == 1) tree_votes = tree_votes + 1;
            end
            vote_count <= tree_votes;
            attack_detected <= (tree_votes > {ML_THRESHOLD}); // threshold from register
        end
    end
endmodule
