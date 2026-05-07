// axi_slave.v
// AXI4-Lite slave for TOTAL Shield Sentinel IP Core
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
    // External signals
    input wire [63:0] security_token,   // from physical pin / eFUSE
    input wire [1:0] fsm_state,         // from FSM (0=IDLE,1=MONITOR,2=THREAT,3=RECOVERY)
    input wire [31:0] alarm_vector,
    input wire [31:0] snapshot_ptr,
    input wire [63:0] timestamp,
    input wire [15:0] sensor_snapshot [0:16],  // 17 features (each 16-bit)
    output reg [31:0] control_reg,      // SHIELD_CONTROL
    output reg [15:0] ml_threshold,     // ML_THRESHOLD
    output reg admin_reset,             // pulse to FSM
    output reg start_calibration,
    output reg force_zeroize
);

    // Register addresses
    localparam ADDR_CTRL       = 8'h00;
    localparam ADDR_STATUS     = 8'h04;
    localparam ADDR_THRESHOLD  = 8'h08;
    localparam ADDR_ALARM_VEC  = 8'h0C;
    localparam ADDR_SNAP_PTR   = 8'h10;
    localparam ADDR_TS_LOW     = 8'h14;
    localparam ADDR_TS_HIGH    = 8'h18;
    localparam ADDR_SNAP_BASE  = 8'h1C;   // + 17*4 = 0x58

    // Internal registers
    reg [31:0] reg_control;
    reg [15:0] reg_ml_threshold;
    reg [63:0] presented_token;
    reg token_valid;
    reg token_timer;  // 1-second timeout after successful token

    // AXI write state machine
    typedef enum reg [1:0] { W_IDLE, W_RESP } w_state_t;
    w_state_t w_state, w_next;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_control <= 0;
            reg_ml_threshold <= 15;
            presented_token <= 0;
            token_valid <= 0;
            token_timer <= 0;
            admin_reset <= 0;
            start_calibration <= 0;
            force_zeroize <= 0;
            s_axi_awready <= 0;
            s_axi_wready <= 0;
            s_axi_bvalid <= 0;
            s_axi_bresp <= 0;
            w_state <= W_IDLE;
        end else begin
            // Defaults
            admin_reset <= 0;
            start_calibration <= 0;
            force_zeroize <= 0;

            // Token timeout
            if (token_timer) token_timer <= token_timer + 1;
            if (token_timer == 100_000_000) begin  // 1 sec at 100 MHz
                token_valid <= 0;
                token_timer <= 0;
            end

            // Write address channel
            if (!s_axi_awready && s_axi_awvalid) begin
                s_axi_awready <= 1;
            end else begin
                s_axi_awready <= 0;
            end

            // Write data channel
            if (!s_axi_wready && s_axi_wvalid) begin
                s_axi_wready <= 1;
                // Capture token
                if (s_axi_awaddr[7:0] == 8'h20) begin
                    presented_token[31:0] <= s_axi_wdata;
                end else if (s_axi_awaddr[7:0] == 8'h24) begin
                    presented_token[63:32] <= s_axi_wdata;
                    if (presented_token[63:32] == security_token[63:32]) begin
                        token_valid <= 1;
                        token_timer <= 1;  // start timeout
                    end else begin
                        token_valid <= 0;
                    end
                end
            end else begin
                s_axi_wready <= 0;
            end

            // Write response FSM
            case (w_state)
                W_IDLE: begin
                    if (s_axi_awready && s_axi_wready) begin
                        w_state <= W_RESP;
                        // Perform write to register if token valid or to non-protected addresses
                        if ((s_axi_awaddr[7:0] == ADDR_CTRL || s_axi_awaddr[7:0] == ADDR_THRESHOLD) && !token_valid) begin
                            s_axi_bresp <= 2'b11; // DECERR (access denied)
                        end else begin
                            s_axi_bresp <= 2'b00;
                            case (s_axi_awaddr[7:0])
                                ADDR_CTRL: begin
                                    reg_control <= s_axi_wdata;
                                    if (s_axi_wdata[0]) start_calibration <= 1;
                                    if (s_axi_wdata[1]) admin_reset <= 1;
                                    if (s_axi_wdata[2]) force_zeroize <= 1;
                                end
                                ADDR_THRESHOLD: reg_ml_threshold <= s_axi_wdata[15:0];
                                default: ; // ignore others
                            endcase
                        end
                    end
                end
                W_RESP: begin
                    s_axi_bvalid <= 1;
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 0;
                        w_state <= W_IDLE;
                    end
                end
            endcase

            // Output registers
            control_reg <= reg_control;
            ml_threshold <= reg_ml_threshold;
        end
    end

    // Read channel (combinational + register)
    reg [31:0] rdata;
    reg arready_reg, rvalid_reg;

    always @(*) begin
        rdata = 32'h0;
        case (s_axi_araddr[7:0])
            ADDR_CTRL:       rdata = reg_control;
            ADDR_STATUS:     rdata = {30'b0, fsm_state};
            ADDR_THRESHOLD:  rdata = {16'b0, reg_ml_threshold};
            ADDR_ALARM_VEC:  rdata = alarm_vector;
            ADDR_SNAP_PTR:   rdata = snapshot_ptr;
            ADDR_TS_LOW:     rdata = timestamp[31:0];
            ADDR_TS_HIGH:    rdata = timestamp[63:32];
            default: begin
                if (s_axi_araddr[7:0] >= 8'h1C && s_axi_araddr[7:0] <= 8'h58) begin
                    int idx = (s_axi_araddr[7:0] - 8'h1C) / 4;
                    if (idx < 17)
                        rdata = {16'b0, sensor_snapshot[idx]};
                end else begin
                    rdata = 32'hDEADBEEF;
                end
            end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            arready_reg <= 0;
            rvalid_reg <= 0;
        end else begin
            if (!arready_reg && s_axi_arvalid) begin
                arready_reg <= 1;
                rvalid_reg <= 1;
            end else begin
                arready_reg <= 0;
                if (rvalid_reg && s_axi_rready) rvalid_reg <= 0;
            end
        end
    end

    assign s_axi_arready = arready_reg;
    assign s_axi_rvalid = rvalid_reg;
    assign s_axi_rdata = rdata;
    assign s_axi_rresp = 2'b00;

endmodule
