// tree_walker_unified.v
// Random Forest classifier with unified BRAM storage.
// Features: pipelined voting, step counter protection, dynamic threshold.
module tree_walker_unified #(
    parameter NUM_TREES = 100,
    parameter MAX_DEPTH = 6,
    parameter MAX_NODES_PER_TREE = (1 << (MAX_DEPTH + 1)) - 1, // 127 for depth 6
    parameter TOTAL_NODES = NUM_TREES * MAX_NODES_PER_TREE,
    parameter VOTE_WIDTH = $clog2(NUM_TREES + 1)
)(
    input wire clk,
    input wire rst,
    input wire enable,                      // start classification
    input wire [15:0] features [0:16],      // 17 fixed-point features
    input wire [VOTE_WIDTH-1:0] ml_threshold, // configurable threshold (from AXI)
    output reg attack_detected,
    output reg [VOTE_WIDTH-1:0] vote_count, // total attack votes
    output reg done                         // classification complete (single pulse)
);

    // Include unified BRAM arrays (defined in tree_nodes_unified.vh)
    `include "tree_nodes_unified.vh"

    // Tree walker FSM for each tree: we implement parallel trees using generate,
    // but each tree walks sequentially. We'll create an array of wires for tree results.
    localparam TREE_WALK_CYCLES = MAX_DEPTH + 2;  // +2 for pipeline
    reg [NUM_TREES-1:0] tree_result;        // 1 = attack, 0 = benign
    reg [NUM_TREES-1:0] tree_valid;         // high when result ready

    // Generate parallel tree walkers (each with its own state)
    genvar t;
    generate
        for (t = 0; t < NUM_TREES; t = t + 1) begin : tree_walkers
            reg [7:0] node_idx;
            reg [3:0] step_cnt;            // step counter (0..MAX_DEPTH)
            reg [7:0] offset;
            reg walk_done, walk_valid;
            reg result_reg;

            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    node_idx <= 0;
                    step_cnt <= 0;
                    walk_done <= 0;
                    walk_valid <= 0;
                    result_reg <= 0;
                end else if (enable && !walk_done) begin
                    offset = t * MAX_NODES_PER_TREE;
                    if (step_cnt == 0) begin
                        // Start walking from root
                        node_idx <= 0;
                        step_cnt <= 1;
                        walk_done <= 0;
                    end else if (step_cnt <= MAX_DEPTH) begin
                        // Check if current node is leaf
                        if (unified_node_leaf_class[offset + node_idx] != 8'hFF) begin
                            // Leaf: result = class (0 or 1)
                            result_reg <= unified_node_leaf_class[offset + node_idx];
                            walk_done <= 1;
                            walk_valid <= 1;
                        end else begin
                            // Internal node: compare feature with threshold
                            // Use $signed for threshold (Q10.5 fixed-point)
                            if (features[unified_node_feature[offset + node_idx]] <= 
                                $signed(unified_node_threshold[offset + node_idx]))
                                node_idx <= unified_node_left[offset + node_idx];
                            else
                                node_idx <= unified_node_right[offset + node_idx];
                            step_cnt <= step_cnt + 1;
                        end
                    end else begin
                        // Exceeded max depth – force leaf classification using last node's class
                        result_reg <= unified_node_leaf_class[offset + node_idx] & 1;
                        walk_done <= 1;
                        walk_valid <= 1;
                    end
                end else if (!enable) begin
                    walk_done <= 0;
                    walk_valid <= 0;
                end
            end

            assign tree_result[t] = result_reg;
            assign tree_valid[t] = walk_valid;
        end
    endgenerate

    // Tree completion detection: when all trees are valid
    reg [VOTE_WIDTH-1:0] vote_comb;
    reg [VOTE_WIDTH-1:0] vote_pipe;
    reg all_valid;

    always @* begin
        vote_comb = 0;
        for (int i = 0; i < NUM_TREES; i++) begin
            if (tree_valid[i] && tree_result[i])
                vote_comb = vote_comb + 1;
        end
    end

    // Pipeline register to break critical path (for large NUM_TREES)
    always @(posedge clk) begin
        if (rst) begin
            vote_pipe <= 0;
        end else begin
            vote_pipe <= vote_comb;
        end
    end

    // Check validity: all trees must have finished (for simplicity, we wait one extra cycle after all valid)
    reg all_valid_prev;
    always @(posedge clk) begin
        if (rst) begin
            all_valid <= 0;
            all_valid_prev <= 0;
        end else begin
            all_valid_prev <= &tree_valid;
            if (all_valid_prev && !all_valid) begin
                all_valid <= 1;
                vote_count <= vote_pipe;
                attack_detected <= (vote_pipe > ml_threshold);
                done <= 1;
            end else if (enable && !all_valid) begin
                done <= 0;
            end else if (!enable) begin
                all_valid <= 0;
                done <= 0;
            end
        end
    end

endmodule
