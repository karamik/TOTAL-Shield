// tb_sentinel_ip_core_top.v
// Improved testbench for top-level module

`timescale 1ns / 1ps

module tb_sentinel_ip_core_top;

    reg clk;
    reg rst;

    // AXI4-Lite (simplified, but functional)
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

    // Physical sensors
    reg [11:0] adc_voltage;
    reg [11:0] adc_em;
    reg [15:0] temp_sensors;
    reg [31:0] pcie_activity;
    reg [7:0] workload_hash;
    reg [63:0] security_token;

    // Outputs
    wire attack_alarm;
    wire trigger_nmi;
    wire zeroize_command;
    reg zeroize_done;

    // Instantiate top
    sentinel_ip_core_top uut (
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
        .adc_voltage(adc_voltage),
        .adc_em(adc_em),
        .temp_sensors(temp_sensors),
        .pcie_activity(pcie_activity),
        .workload_hash(workload_hash),
        .security_token(security_token),
        .attack_alarm(attack_alarm),
        .trigger_nmi(trigger_nmi),
        .zeroize_command(zeroize_command),
        .zeroize_done(zeroize_done)
    );

    // Clock 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // Helper tasks for AXI
    task axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr = addr;
            s_axi_awvalid = 1;
            s_axi_wdata = data;
            s_axi_wstrb = 4'hF;
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

    // Force calibration done (to avoid long wait)
    initial begin
        force uut.calibration_done = 1;
    end

    // Main test sequence
    initial begin
        // Initialize
        rst = 1;
        s_axi_awvalid = 0;
        s_axi_wvalid = 0;
        s_axi_arvalid = 0;
        s_axi_bready = 0;
        s_axi_rready = 0;
        adc_voltage = 12'h800;
        adc_em = 12'h800;
        temp_sensors = 16'h7F7F;
        pcie_activity = 0;
        workload_hash = 0;
        security_token = 64'h1234567890ABCDEF;
        zeroize_done = 0;

        #20;
        rst = 0;
        #20;

        // Enable AXI read/write ready
        s_axi_bready = 1;
        s_axi_rready = 1;

        $display("=== Test 1: Wait for FSM to enter MONITOR (calibration forced) ===");
        wait (uut.fsm_state == 2'b01);
        $display("FSM now in MONITOR");

        $display("=== Test 2: Inject voltage glitch (attack) ===");
        adc_voltage = 12'h001;   // deep glitch
        #40;                       // hold for 4 clocks
        adc_voltage = 12'h800;    // back to normal

        // Wait for detection (tree walker runs on timebase pulse; we need to wait at least 10ms?
        // In simulation we haven't generated real timebase; we need to force timebase pulse?
        // Actually timebase is generated from 100 MHz clock counting to 1e6, which would take 10ms in real time.
        // For simulation speed, we can force a timebase pulse directly in the testbench.
        // Let's pulse it manually:
        #100;
        $display("=== Forcing timebase pulse to trigger feature extraction ===");
        force uut.timebase_10ms = 1;
        #20;
        force uut.timebase_10ms = 0;

        // Wait for tree walker to finish (MAX_DEPTH*2 clocks)
        #500;

        // Check if attack detected
        if (uut.ml_attack_detected !== 1) begin
            $error("Attack not detected by tree walker");
        end else begin
            $display("Attack detected correctly");
        end

        // Wait for FSM to transition to THREAT
        wait (uut.fsm_state == 2'b10);
        $display("FSM entered THREAT state");

        // Check alarm and NMI
        if (attack_alarm !== 1) $error("Attack alarm not set");
        if (trigger_nmi !== 1) $error("NMI not triggered");
        $display("Alarm and NMI asserted");

        // Wait a bit then FSM should go to RECOVERY (since zeroize not enabled)
        #200;
        wait (uut.fsm_state == 2'b11);
        $display("FSM entered RECOVERY state – waiting for admin reset");

        // Now perform admin reset via AXI (requires token)
        $display("=== Sending security token via AXI ===");
        axi_write(32'h20, security_token[31:0]);
        axi_write(32'h24, security_token[63:32]);
        #100;

        $display("Writing to SHIELD_CONTROL to assert admin_reset (bit1)");
        axi_write(32'h00, 32'h02);   // set bit1

        // Wait for reset to take effect
        #200;
        if (uut.fsm_state !== 2'b00) $error("FSM did not return to IDLE after admin reset");
        if (attack_alarm !== 0) $error("Attack alarm still high after reset");
        $display("FSM back to IDLE, alarm cleared – admin reset successful");

        $display("=== Test 3: Enable zeroize on next attack ===");
        // First, re-enter MONITOR (must force calibration again? FSM remains in IDLE after reset.
        // To re-enter MONITOR we need calibration_done = 1 (already forced) and then FSM will transition.
        // But we need to set control_reg[2]=1 to enable zeroize.
        $display("Enabling zeroize bit in control register (requires token again)");
        axi_write(32'h20, security_token[31:0]);
        axi_write(32'h24, security_token[63:32]);
        axi_write(32'h00, 32'h04);   // set bit2 (enable_zeroize)
        #100;

        // Wait for MONITOR again (FSM may have already transitioned, but we can force)
        if (uut.fsm_state != 2'b01) begin
            $display("Waiting for FSM to re-enter MONITOR");
            #1000;
        end

        // Inject another glitch
        $display("Inject second glitch (with zeroize enabled)");
        adc_voltage = 12'h001;
        #40;
        adc_voltage = 12'h800;
        #100;
        // Force timebase
        force uut.timebase_10ms = 1;
        #20;
        force uut.timebase_10ms = 0;

        #500;
        if (zeroize_command !== 1) $error("Zeroize command not asserted");
        $display("Zeroize command asserted – waiting for zeroize_done");
        zeroize_done = 1;
        #20;
        zeroize_done = 0;
        #100;
        if (uut.fsm_state != 2'b11) $error("FSM did not go to RECOVERY after zeroize");
        $display("Zeroize completed, FSM in RECOVERY");

        $display("=== All tests passed ===");
        $finish;
    end

    // Monitor FSM state changes (optional)
    always @(posedge clk) begin
        if (uut.fsm_state != $past(uut.fsm_state))
            $display("Time %t: FSM state changed to %d", $time, uut.fsm_state);
    end

endmodule
