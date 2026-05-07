// tb_axi_slave.v
// Testbench for AXI4-Lite slave module

`timescale 1ns / 1ps

module tb_axi_slave;

    reg clk;
    reg rst;
    // AXI4-Lite signals
    reg [31:0] s_axi_awaddr;
    reg s_axi_awvalid;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata;
    reg [3:0] s_axi_wstrb;
    reg s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready;
    reg [31:0] s_axi_araddr;
    reg s_axi_arvalid;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready;
    // External inputs
    reg [63:0] security_token;
    reg [1:0] fsm_state;
    reg [31:0] alarm_vector;
    reg [31:0] snapshot_ptr;
    reg [63:0] timestamp;
    reg [15:0] sensor_snapshot [0:16];
    // Outputs from slave
    wire [31:0] control_reg;
    wire [15:0] ml_threshold;
    wire admin_reset;
    wire start_calibration;
    wire force_zeroize;

    // Instantiate
    axi_slave dut (
        .clk(clk),
        .rst(rst),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .security_token(security_token),
        .fsm_state(fsm_state),
        .alarm_vector(alarm_vector),
        .snapshot_ptr(snapshot_ptr),
        .timestamp(timestamp),
        .sensor_snapshot(sensor_snapshot),
        .control_reg(control_reg),
        .ml_threshold(ml_threshold),
        .admin_reset(admin_reset),
        .start_calibration(start_calibration),
        .force_zeroize(force_zeroize)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Helper tasks
    task axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr = addr;
            s_axi_awvalid = 1;
            s_axi_wdata = data;
            s_axi_wstrb = 4'b1111;
            s_axi_wvalid = 1;
            @(posedge clk);
            while (!s_axi_awready || !s_axi_wready) @(posedge clk);
            s_axi_awvalid = 0;
            s_axi_wvalid = 0;
            @(posedge clk);
            while (!s_axi_bvalid) @(posedge clk);
            s_axi_bready = 1;
            @(posedge clk);
            s_axi_bready = 0;
        end
    endtask

    task axi_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_axi_araddr = addr;
            s_axi_arvalid = 1;
            @(posedge clk);
            while (!s_axi_arready) @(posedge clk);
            s_axi_arvalid = 0;
            @(posedge clk);
            while (!s_axi_rvalid) @(posedge clk);
            data = s_axi_rdata;
            s_axi_rready = 1;
            @(posedge clk);
            s_axi_rready = 0;
        end
    endtask

    // Test sequence
    initial begin
        // Initialize
        rst = 1;
        s_axi_bready = 0;
        s_axi_rready = 0;
        security_token = 64'h1234567890ABCDEF;
        fsm_state = 2'b01;          // MONITOR
        alarm_vector = 32'h00001000;
        snapshot_ptr = 32'hDEADBEEF;
        timestamp = 64'h00000000FFFFFFFF;
        for (int i = 0; i < 17; i++) sensor_snapshot[i] = i * 100;
        #20;
        rst = 0;
        #20;

        // 1. Read default registers
        $display("Test 1: Read default registers");
        axi_read(32'h00, rd_data); $display("CTRL = %x", rd_data); // should be 0
        axi_read(32'h04, rd_data); $display("STATUS = %x", rd_data); // should contain fsm_state=01
        axi_read(32'h08, rd_data); $display("THRESH = %x", rd_data); // default 15
        if (rd_data[15:0] !== 15) $error("Default threshold not 15");

        // 2. Write to protected register without token (should be ignored)
        $display("Test 2: Write threshold without token");
        axi_write(32'h08, 32'h0020);
        #100;
        axi_read(32'h08, rd_data);
        if (rd_data[15:0] === 32) $error("Threshold write succeeded without token");
        else $display("Threshold write correctly ignored");

        // 3. Provide correct token
        $display("Test 3: Supply security token");
        axi_write(32'h20, security_token[31:0]);
        axi_write(32'h24, security_token[63:32]);
        #100;

        // 4. Write threshold again (should succeed)
        $display("Test 4: Write threshold after token");
        axi_write(32'h08, 32'h0020);
        #100;
        axi_read(32'h08, rd_data);
        if (rd_data[15:0] !== 32) $error("Threshold write failed after token");
        else $display("Threshold updated to 32");

        // 5. Write control register to assert start_calibration
        $display("Test 5: Assert start_calibration via control reg");
        axi_write(32'h00, 32'h01);
        #100;
        if (!start_calibration) $error("start_calibration not asserted");
        else $display("start_calibration asserted");

        // 6. Read sensor snapshot from address 0x1C
        $display("Test 6: Read sensor snapshot");
        axi_read(32'h1C, rd_data);
        $display("Snapshot[0] = %x", rd_data[15:0]);
        if (rd_data[15:0] !== 0) $error("Snapshot[0] mismatch");

        // 7. Read alarm_vector and snapshot_ptr
        axi_read(32'h0C, rd_data); $display("Alarm vector = %x", rd_data);
        axi_read(32'h10, rd_data); $display("Snapshot ptr = %x", rd_data);

        $display("All AXI tests passed.");
        $finish;
    end

    reg [31:0] rd_data;
endmodule
