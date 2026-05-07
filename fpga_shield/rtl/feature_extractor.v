// feature_extractor.v
// Computes 17 fixed-point features from voltage, EM, temperature every 10 ms.
module feature_extractor #(
    parameter SAMPLE_WINDOW = 1024,   // number of samples per 10 ms (adjust to ADC rate)
    parameter FEATURE_WIDTH = 16      // Q10.5 fixed-point
)(
    input wire clk,
    input wire rst,
    input wire enable,                // from FSM
    input wire timebase_10ms,         // pulse every 10 ms
    input wire [11:0] adc_voltage,    // high‑speed ADC
    input wire [11:0] adc_em,
    input wire [15:0] temp_sensors,   // 16 x 8‑bit (packed)
    input wire [31:0] pcie_activity,
    input wire [7:0] workload_hash,
    output reg [FEATURE_WIDTH-1:0] features [0:16] // 17 features
);

    // Memory for sliding window (BRAM inferred)
    reg [11:0] voltage_buf [0:SAMPLE_WINDOW-1];
    reg [11:0] em_buf [0:SAMPLE_WINDOW-1];
    reg [$clog2(SAMPLE_WINDOW)-1:0] wr_ptr;
    reg [$clog2(SAMPLE_WINDOW)-1:0] sample_cnt;
    reg window_filled;

    // Accumulators (use wide registers, then downscale)
    reg [31:0] sum_v, sum_v_sq;
    reg [31:0] sum_em;
    reg [11:0] v_min, v_max;
    reg [11:0] em_max;
    reg [15:0] v_slope_max;
    reg [31:0] v_high_freq_energy;
    reg [31:0] corr_acc;

    // Internal storage for computed features (before output)
    reg [FEATURE_WIDTH-1:0] feat [0:16];

    integer i;

    // Write to circular buffers on every clock (if enabled)
    always @(posedge clk) begin
        if (enable) begin
            voltage_buf[wr_ptr] <= adc_voltage;
            em_buf[wr_ptr] <= adc_em;
            if (wr_ptr == SAMPLE_WINDOW-1) begin
                wr_ptr <= 0;
                window_filled <= 1;
            end else begin
                wr_ptr <= wr_ptr + 1;
            end
            if (!window_filled) sample_cnt <= sample_cnt + 1;
        end
    end

    // Feature computation on timebase pulse (with window_filled check)
    always @(posedge clk) begin
        if (rst) begin
            features[0] <= 0; // etc. – reset all
        end else if (enable && timebase_10ms && window_filled) begin
            // Reset accumulators
            sum_v = 0; sum_v_sq = 0; sum_em = 0;
            v_min = 12'hFFF; v_max = 0; em_max = 0;
            v_slope_max = 0;
            v_high_freq_energy = 0;
            corr_acc = 0;

            // Process the entire window (sequential, but combinational – OK for synthesis with small window?)
            // For large windows, this would take many clocks; but we are at timebase pulse, so we can use a loop
            // that consumes multiple clocks; but to keep it simple, we assume SAMPLE_WINDOW is small enough (<=1024)
            // and we do it in one clock using *blocking* assignments inside loop – may cause timing issues for large windows.
            // Better to pipeline, but for now let's assume it's acceptable for demo.
            for (i=0; i<SAMPLE_WINDOW; i=i+1) begin
                // voltage stats
                sum_v = sum_v + voltage_buf[i];
                sum_v_sq = sum_v_sq + voltage_buf[i] * voltage_buf[i];
                if (voltage_buf[i] < v_min) v_min = voltage_buf[i];
                if (voltage_buf[i] > v_max) v_max = voltage_buf[i];
                // slope
                if (i>0 && voltage_buf[i-1] > voltage_buf[i]) begin
                    slope = voltage_buf[i-1] - voltage_buf[i];
                    if (slope > v_slope_max) v_slope_max = slope;
                end
                // EM
                sum_em = sum_em + em_buf[i];
                if (em_buf[i] > em_max) em_max = em_buf[i];
                // cross-correlation (simplified)
                corr_acc = corr_acc + voltage_buf[i] * em_buf[i];
                // high freq energy: would need filtered data – placeholder
                v_high_freq_energy = v_high_freq_energy + (voltage_buf[i] * voltage_buf[i] >> 4);
            end

            // Compute mean and variance as fixed-point (Q10.5)
            reg [31:0] mean_v = sum_v / SAMPLE_WINDOW;
            reg [31:0] mean_v_sq = sum_v_sq / SAMPLE_WINDOW;
            reg [31:0] variance = mean_v_sq - (mean_v * mean_v);
            // Avoid sqrt, keep variance as energy metric

            // Temperature features: unpack temp_sensors (16x8-bit)
            reg [7:0] temps[0:15];
            for (i=0; i<16; i=i+1) temps[i] = temp_sensors[8*i +: 8];
            reg [7:0] t_min, t_max;
            reg [15:0] t_sum;
            t_min = 8'hFF; t_max = 0; t_sum = 0;
            for (i=0; i<16; i=i+1) begin
                if (temps[i] < t_min) t_min = temps[i];
                if (temps[i] > t_max) t_max = temps[i];
                t_sum = t_sum + temps[i];
            end
            reg [15:0] t_avg = t_sum / 16;
            reg [7:0] t_delta = t_max - t_min;
            // gradient: max difference between adjacent sensors (simple ring)
            reg [7:0] t_grad = 0;
            for (i=0; i<16; i=i+1) begin
                diff = (temps[i] > temps[(i+1)%16]) ? temps[i] - temps[(i+1)%16] : temps[(i+1)%16] - temps[i];
                if (diff > t_grad) t_grad = diff;
            end
            // t_rate – requires previous value, we can store last snapshot (omitted for brevity)
            reg [7:0] last_t_avg;
            reg [7:0] t_rate = (t_avg > last_t_avg) ? t_avg - last_t_avg : last_t_avg - t_avg;
            last_t_avg <= t_avg;

            // Pack features into Q10.5 format (scale down to 16-bit)
            features[0]  = v_min * 16;   // v_min
            features[1]  = v_slope_max;
            features[2]  = variance >> 4; // v_std (approx)
            features[3]  = v_high_freq_energy >> 8;
            features[4]  = em_max * 16;
            features[5]  = (sum_em / SAMPLE_WINDOW) * 16; // em_band_ratio placeholder
            features[6]  = t_delta * 256;
            features[7]  = t_grad * 256;
            features[8]  = t_rate * 256;
            features[9]  = temps[15] * 256; // t_ambient (last sensor as ambient)
            features[10] = (corr_acc / SAMPLE_WINDOW) >> 4;
            features[11] = 0; // glitch_width_estimate placeholder
            features[12] = 0; // repetition_rate placeholder
            features[13] = pcie_activity[15:0];
            features[14] = {8'b0, workload_hash};
            features[15] = v_min * 16; // v_min_baseline_ma placeholder
            features[16] = 0; // time_since_last_alarm placeholder
        end
    end
endmodule
