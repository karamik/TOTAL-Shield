// tree_walker_unified.v
module tree_walker_unified #(
    parameter NUM_TREES = 100,
    parameter MAX_NODES_PER_TREE = 127,
    parameter TOTAL_NODES = NUM_TREES * MAX_NODES_PER_TREE
)(
    input wire clk,
    input wire rst,
    input wire enable,
    input wire [15:0] features [0:16],
    input wire [4:0] ml_threshold,   // from AXI register
    output reg attack_detected,
    output reg [6:0] vote_count      // up to 100 trees
);

    `include "tree_nodes_unified.vh"

    integer t;
    reg [7:0] node_idx;
    reg [7:0] class_result [0:NUM_TREES-1];
    reg [6:0] votes;
    reg is_leaf;

    // Tree walker with generate loop (parallel tree walking)
    genvar tree_id;
    generate
        for (tree_id = 0; tree_id < NUM_TREES; tree_id = tree_id + 1) begin : tree_walkers
            reg [6:0] cur_node;
            reg [6:0] next_node;
            reg [6:0] offset;
            integer step;
            
            always @(posedge clk) begin
                if (rst) begin
                    class_result[tree_id] <= 0;
                end else if (enable) begin
                    offset = tree_id * MAX_NODES_PER_TREE;
                    cur_node = 0;
                    // Walk the tree (depth up to MAX_DEPTH) – sequential within tree
                    for (step = 0; step < MAX_DEPTH; step = step + 1) begin
                        is_leaf = (unified_node_leaf_class[offset + cur_node] != 8'hFF);
                        if (is_leaf) begin
                            class_result[tree_id] <= unified_node_leaf_class[offset + cur_node];
                            break;
                        end else begin
                            if (features[unified_node_feature[offset + cur_node]] <= 
                                $signed(unified_node_threshold[offset + cur_node]))
                                cur_node = unified_node_left[offset + cur_node];
                            else
                                cur_node = unified_node_right[offset + cur_node];
                        end
                    end
                    // If exhausted depth, assume leaf? Class by last node.
                    if (step == MAX_DEPTH) begin
                        class_result[tree_id] <= unified_node_leaf_class[offset + cur_node] & 1;
                    end
                end
            end
        end
    endgenerate

    // Majority vote (combinational)
    always @(*) begin
        votes = 0;
        for (t = 0; t < NUM_TREES; t = t + 1) begin
            if (class_result[t] == 1) votes = votes + 1;
        end
        vote_count = votes;
        attack_detected = (votes > ml_threshold);
    end

endmodule
