// sentinel_ip_core.v
module sentinel_ip_core (
    input wire clk,
    input wire rst,
    // AXI4-Lite
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
    // Physical sensors
    input wire [11:0] adc_voltage,
    input wire [11:0] adc_em,
    input wire [15:0] temp_sensors,
    input wire [31:0] pcie_activity,
    input wire [7:0] workload_hash,
    input wire [63:0] physical_token, // from physical pin
    // Outputs
    output reg attack_alarm,
    output reg trigger_nmi,
    output reg zeroize_command,
    input wire zeroize_done
);

    // Internal signals
    reg enable_feature;
    reg [15:0] features [0:16];
    reg ml_attack_detected;
    reg [4:0] vote_count;
    reg [31:0] control_reg;
    reg [15:0] ml_threshold;
    reg [1:0] fsm_state;
    reg [31:0] alarm_vector;
    reg [31:0] snapshot_ptr;
    reg [63:0] timestamp;
    reg [15:0] sensor_snapshot [0:16];
    reg admin_reset;
    reg start_calibration;
    reg calibration_done;
    
    // Instantiate FSM (previously described)
    // ...
    
    // Instantiate feature extractor
    feature_extractor fe (
        .clk(clk),
        .rst(rst),
        .enable(enable_feature),
        .adc_voltage(adc_voltage),
        .adc_em(adc_em),
        .temp_sensors(temp_sensors),
        .pcie_activity(pcie_activity),
        .workload_hash(workload_hash),
        .timebase_10ms(timebase_10ms_pulse),
        .features(features)
    );
    
    // Instantiate tree walker
    tree_walker tw (
        .clk(clk),
        .rst(rst),
        .enable(enable_feature),
        .features(features),
        .attack_detected(ml_attack_detected),
        .vote_count(vote_count)
    );
    
    // Instantiate AXI slave
    axi_slave ax (
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
        .control_reg(control_reg),
        .ml_threshold(ml_threshold),
        .fsm_state(fsm_state),
        .alarm_vector(alarm_vector),
        .snapshot_ptr(snapshot_ptr),
        .timestamp(timestamp),
        .sensor_snapshot(sensor_snapshot),
        .physical_token(physical_token)
    );
    
    // FSM logic (see previous description)
    // ...
    
endmodule
