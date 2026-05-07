// axi_slave.v
module axi_slave (
    input wire clk,
    input wire rst,
    // AXI4-Lite inputs
    input wire [31:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output reg s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output reg s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [31:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output reg s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,
    // External interface to FSM and other blocks
    output reg [31:0] control_reg,   // SHIELD_CONTROL
    output reg [15:0] ml_threshold,  // ML_THRESHOLD
    input wire [1:0]  fsm_state,
    input wire [31:0] alarm_vector,
    input wire [31:0] snapshot_ptr,
    input wire [63:0] timestamp,
    input wire [15:0] sensor_snapshot [0:16],
    // Security token (physical pin)
    input wire [63:0] physical_token
);

    // Internal registers
    reg [63:0] presented_token;
    reg token_valid;
    reg [31:0] regs [0:7]; // 8 registers (0x00 to 0x1C)
    
    // Token comparison
    always @(posedge clk) begin
        if (rst) begin
            presented_token <= 0;
            token_valid <= 0;
        end else begin
            if (s_axi_wvalid && s_axi_awready && (s_axi_awaddr == 32'h20)) begin
                presented_token[31:0] <= s_axi_wdata;
                token_valid <= 0;
            end else if (s_axi_wvalid && s_axi_awready && (s_axi_awaddr == 32'h24)) begin
                presented_token[63:32] <= s_axi_wdata;
                token_valid <= (presented_token == physical_token);
            end
        end
    end
    
    // Register write
    always @(posedge clk) begin
        if (rst) begin
            control_reg <= 0;
            ml_threshold <= 15;
        end else if (s_axi_wvalid && s_axi_awready && token_valid) begin
            case (s_axi_awaddr[3:0])
                4'h0: control_reg <= s_axi_wdata;
                4'h8: ml_threshold <= s_axi_wdata[15:0];
                default: ;
            endcase
        end
    end
    
    // Register read
    always @(*) begin
        s_axi_rdata = 32'h0;
        case (s_axi_araddr[3:0])
            4'h0: s_axi_rdata = control_reg;
            4'h4: s_axi_rdata = {30'b0, fsm_state};
            4'h8: s_axi_rdata = {16'b0, ml_threshold};
            4'hC: s_axi_rdata = alarm_vector;
            4'h10: s_axi_rdata = snapshot_ptr;
            4'h14: s_axi_rdata = timestamp[31:0];
            4'h18: s_axi_rdata = timestamp[63:32];
            // additional for sensor snapshot could be burst
            default: s_axi_rdata = 32'hDEADBEEF;
        endcase
    end
    
    // AXI handshake (simplified)
    always @(posedge clk) begin
        s_axi_awready <= s_axi_awvalid;
        s_axi_wready <= s_axi_wvalid;
        s_axi_bresp <= 2'b00;
        s_axi_bvalid <= s_axi_wvalid && s_axi_awready;
        s_axi_arready <= s_axi_arvalid;
        s_axi_rresp <= 2'b00;
        s_axi_rvalid <= s_axi_arvalid;
    end
endmodule
