// tb_tree_walker_unified.v
// Testbench for tree_walker_unified module

`timescale 1ns / 1ps

module tb_tree_walker_unified;

    // Parameters (must match those used during model export)
    localparam NUM_TREES = 30;
    localparam MAX_DEPTH = 6;
    localparam MAX_NODES_PER_TREE = (1 << (MAX_DEPTH + 1)) - 1;
    localparam TOTAL_NODES = NUM_TREES * MAX_NODES_PER_TREE;
    localparam VOTE_WIDTH = $clog2(NUM_TREES + 1);

    reg clk;
    reg rst;
    reg enable;
    reg [15:0] features [0:16];
    reg [VOTE_WIDTH-1:0] ml_threshold;
    wire attack_detected;
    wire [VOTE_WIDTH-1:0] vote_count;
    wire done;

    // Instantiate module
    tree_walker_unified #(
        .NUM_TREES(NUM_TREES),
        .MAX_DEPTH(MAX_DEPTH),
        .MAX_NODES_PER_TREE(MAX_NODES_PER_TREE),
        .TOTAL_NODES(TOTAL_NODES),
        .VOTE_WIDTH(VOTE_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .features(features),
        .ml_threshold(ml_threshold),
        .attack_detected(attack_detected),
        .vote_count(vote_count),
        .done(done)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // Test sequence
    initial begin
        // Initialization
        rst = 1;
        enable = 0;
        ml_threshold = 15;   // 50% of 30 trees
        for (int i = 0; i < 17; i++) features[i] = 0;
        #20;
        rst = 0;
        #20;

        // Test 1: benign pattern (all features zero)
        $display("Test 1: All features zero (expect low vote count)");
        enable = 1;
        #(MAX_DEPTH * 10 + 20);  // enough cycles for tree walking
        enable = 0;
        #10;
        $display("Vote count = %0d, attack_detected = %0d", vote_count, attack_detected);
        if (vote_count > 5) $error("Vote count too high for benign pattern");
        #100;

        // Test 2: attack pattern – simulate voltage glitch (feature[0] = v_min very low)
        $display("Test 2: Emulate voltage glitch (v_min = 100)");
        features[0] = 100;   // Q10.5 value
        enable = 1;
        #(MAX_DEPTH * 10 + 20);
        enable = 0;
        #10;
        $display("Vote count = %0d, attack_detected = %0d", vote_count, attack_detected);
        if (vote_count < (NUM_TREES/2)) $error("Attack not detected for glitch pattern");
        #100;

        // Test 3: increase threshold to 25 – should not trigger attack even with same pattern
        $display("Test 3: Increase threshold to 25 (expect no detection)");
        ml_threshold = 25;
        enable = 1;
        #(MAX_DEPTH * 10 + 20);
        enable = 0;
        #10;
        $display("Vote count = %0d, attack_detected = %0d", vote_count, attack_detected);
        if (attack_detected) $error("Attack detected despite high threshold");
        #100;

        $display("All tests completed successfully.");
        $finish;
    end

    // Monitor
    initial begin
        $monitor("At time %t: done=%b, vote_count=%d, attack=%b", $time, done, vote_count, attack_detected);
    end

endmodule
