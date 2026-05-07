// timebase.v – generates 10 ms pulse from 100 MHz clock
module timebase (
    input wire clk,
    input wire rst,
    input wire enable,          // from FSM: only count when in MONITOR
    output reg pulse_10ms
);

    localparam COUNT_MAX = 1_000_000; // 100 MHz -> 10 ms = 1e6 cycles
    reg [19:0] counter;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 0;
            pulse_10ms <= 0;
        end else if (enable) begin
            if (counter == COUNT_MAX - 1) begin
                counter <= 0;
                pulse_10ms <= 1;
            end else begin
                counter <= counter + 1;
                pulse_10ms <= 0;
            end
        end else begin
            counter <= 0;
            pulse_10ms <= 0;
        end
    end
endmodule
