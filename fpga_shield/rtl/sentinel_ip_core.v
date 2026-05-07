// sentinel_ip_core_top.v
// Top module for TOTAL Shield Sentinel IP Core
// Integrates FSM, timebase, feature extractor, tree walker, and AXI4-Lite slave.

module sentinel_ip_core_top (
    input wire clk,                     // 100 MHz system clock
    input wire rst,                     // asynchronous active-high reset

    // AXI4-Lite interface
    input wire [31:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    input wire [31:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input wire s_axi_rready,

    // Physical sensor inputs
    input wire [11:0] adc_voltage,
    input wire [11:0] adc_em,
    input wire [15:0] temp_sensors,     // 16 × 8-bit packed
    input wire [31:0] pcie_activity,
    input wire [7:0]  workload_hash,

    // Security token (from physical eFUSE or external pin)
    input wire [63:0] security_token,

    // Outputs
    output wire attack_alarm,
    output wire trigger_nmi,
    output wire zeroize_command,
    input wire zeroize_done
);

    // -----------------------------------------------------------------
    // Internal signals
    // -----------------------------------------------------------------
    // FSM state (output to AXI status register)
    reg [1:0] fsm_state;
    localparam IDLE     = 2'b00,
               MONITOR  = 2'b01,
               THREAT   = 2'b10,
               RECOVERY = 2'b11;

    // Control signals from AXI
    wire [31:0] control_reg;
    wire [15:0] ml_threshold;
    wire admin_reset_pulse;
    wire start_calibration_pulse;
    wire force_zeroize_pulse;

    // Feature extractor
    wire timebase_10ms;
    wire enable_feature;
    wire [15:0] features [0:16];    // 17 features, Q10.5 format

    // Tree walker
    wire ml_attack_detected;
    wire [6:0] vote_count;           // up to 100 trees -> 7 bits
    wire tree_done;

    // Calibration
    reg calibration_done;
    reg [9:0] calib_cnt;             // count up to 1023 (approx 1000 samples)
    reg collecting_baseline;
    wire start_calib;

    // FSM control
    reg enable_monitor;
    reg attack_latched;
    reg zeroize_cmd;
    reg nmi_pulse;
    reg alarm_out;

    // -----------------------------------------------------------------
    // Instantiate AXI slave
    // -----------------------------------------------------------------
    wire admin_reset, start_calib_axi, force_zeroize_axi;
    axi_slave axl (
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
        .alarm_vector(32'h0),        // placeholder, can be connected to feature extractor
        .snapshot_ptr(32'h0),        // placeholder
        .timestamp(64'h0),           // placeholder
        .sensor_snapshot({16{16'h0}}), // placeholder
        .control_reg(control_reg),
        .ml_threshold(ml_threshold),
        .admin_reset(admin_reset),
        .start_calibration(start_calib_axi),
        .force_zeroize(force_zeroize_axi)
    );

    assign start_calibration_pulse = start_calib_axi;
    assign admin_reset_pulse = admin_reset;
    assign force_zeroize_pulse = force_zeroize_axi;

    // -----------------------------------------------------------------
    // Calibration logic
    // -----------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            calib_cnt <= 0;
            calibration_done <= 0;
            collecting_baseline <= 0;
        end else if (start_calibration_pulse || (fsm_state == IDLE && !calibration_done)) begin
            collecting_baseline <= 1;
            if (collecting_baseline) begin
                if (calib_cnt == 1023) begin
                    calib_cnt <= 0;
                    calibration_done <= 1;
                    collecting_baseline <= 0;
                end else begin
                    calib_cnt <= calib_cnt + 1;
                end
            end
        end else if (admin_reset_pulse) begin
            calibration_done <= 0;
            collecting_baseline <= 0;
            calib_cnt <= 0;
        end
    end

    // -----------------------------------------------------------------
    // Timebase (only enabled in MONITOR state)
    // -----------------------------------------------------------------
    timebase tb (
        .clk(clk),
        .rst(rst),
        .enable(enable_monitor),
        .pulse_10ms(timebase_10ms)
    );

    // -----------------------------------------------------------------
    // Feature extractor
    // -----------------------------------------------------------------
    feature_extractor fe (
        .clk(clk),
        .rst(rst),
        .enable(enable_monitor),
        .timebase_10ms(timebase_10ms),
        .adc_voltage(adc_voltage),
        .adc_em(adc_em),
        .temp_sensors(temp_sensors),
        .pcie_activity(pcie_activity),
        .workload_hash(workload_hash),
        .features(features)
    );

    // -----------------------------------------------------------------
    // Tree walker
    // -----------------------------------------------------------------
    tree_walker_unified #(
        .NUM_TREES(30),          // default, can be overridden
        .MAX_DEPTH(6)
    ) tw (
        .clk(clk),
        .rst(rst),
        .enable(enable_monitor && timebase_10ms),  // run on each 10 ms pulse
        .features(features),
        .ml_threshold(ml_threshold),
        .attack_detected(ml_attack_detected),
        .vote_count(vote_count),
        .done(tree_done)
    );

    // -----------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fsm_state <= IDLE;
            enable_monitor <= 0;
            attack_latched <= 0;
            zeroize_cmd <= 0;
            nmi_pulse <= 0;
            alarm_out <= 0;
        end else begin
            // Defaults
            nmi_pulse <= 0;
            zeroize_cmd <= 0;

            case (fsm_state)
                IDLE: begin
                    enable_monitor <= 0;
                    if (calibration_done) begin
                        fsm_state <= MONITOR;
                        enable_monitor <= 1;
                    end
                end

                MONITOR: begin
                    if (ml_attack_detected) begin
                        fsm_state <= THREAT;
                        enable_monitor <= 0;
                        attack_latched <= 1;
                    end
                end

                THREAT: begin
                    // Assert alarm and NMI
                    alarm_out <= 1;
                    nmi_pulse <= 1;
                    if (force_zeroize_pulse || (control_reg[2] && !zeroize_cmd)) begin
                        zeroize_cmd <= 1;   // start zeroize
                    end
                    // Move to next state after one clock (or after zeroize_done)
                    if (zeroize_cmd && zeroize_done) begin
                        fsm_state <= RECOVERY;
                        zeroize_cmd <= 0;
                    end else if (!force_zeroize_pulse && !control_reg[2]) begin
                        fsm_state <= RECOVERY;   // no zeroize required
                    end
                end

                RECOVERY: begin
                    // Keep alarm active until admin reset
                    alarm_out <= 1;
                    if (admin_reset_pulse) begin
                        fsm_state <= IDLE;
                        alarm_out <= 0;
                        attack_latched <= 0;
                    end
                end
            endcase
        end
    end

    // Output assignments
    assign attack_alarm = alarm_out;
    assign trigger_nmi = nmi_pulse;
    assign zeroize_command = zeroize_cmd;

endmodule
