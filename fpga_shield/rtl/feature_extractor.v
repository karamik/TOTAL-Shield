// feature_extractor.v
module feature_extractor (
    input wire clk,
    input wire rst,
    input wire enable,               // from FSM (MONITOR state)
    input wire [11:0] adc_voltage,   // high-speed ADC, 200 MSps (sample rate)
    input wire [11:0] adc_em,
    input wire [15:0] temp_sensors,  // 16 temperature sensors (8-bit each? adjust)
    input wire [31:0] pcie_activity, // from PCIe sniffer
    input wire [7:0]  workload_hash, // from debug bus
    input wire timebase_10ms,        // pulse every 10 ms
    
    output reg [15:0] features [0:16] // 17 fixed-point features (Q10.5)
);

    // Internal storage for sliding window
    reg [11:0] voltage_buffer [0:1023]; // circular buffer (adjustable)
    reg [11:0] em_buffer [0:1023];
    reg [31:0] sample_cnt;
    reg [15:0] v_min, v_max, v_std_accum, v_slope_max;
    reg [15:0] v_high_freq_energy;
    reg [15:0] em_power_max, em_band_ratio;
    reg [15:0] t_delta_max, t_gradient, t_rate, t_ambient;
    reg [15:0] corr_v_em, glitch_width_estimate, repetition_rate;
    reg [15:0] v_min_baseline_ma, time_since_last_alarm;
    
    // Local variables for computation (combinational)
    integer i;
    reg [31:0] sum_v, sum_v_sq;
    reg [31:0] sum_em;
    
    always @(posedge clk) begin
        if (rst) begin
            sample_cnt <= 0;
            // reset all accumulators
        end else if (enable && timebase_10ms) begin
            // Compute features over the last 10 ms window
            // Example: v_min = min(voltage_buffer) over last N samples
            // v_std = sqrt(mean(sq) - mean^2) but we avoid sqrt → use variance
            // For simplicity, we implement a few representative features.
            
            // 1. v_min: minimum voltage
            v_min = 16'hFFF;
            for (i=0; i<1024; i=i+1) if (voltage_buffer[i] < v_min) v_min = voltage_buffer[i];
            
            // 2. v_slope_max: max negative slope (difference between consecutive samples)
            v_slope_max = 0;
            for (i=1; i<1024; i=i+1) begin
                if (voltage_buffer[i-1] > voltage_buffer[i]) begin
                    slope = voltage_buffer[i-1] - voltage_buffer[i];
                    if (slope > v_slope_max) v_slope_max = slope;
                end
            end
            
            // 3. v_std: estimate using variance (sum of squares)
            sum_v = 0; sum_v_sq = 0;
            for (i=0; i<1024; i=i+1) begin
                sum_v = sum_v + voltage_buffer[i];
                sum_v_sq = sum_v_sq + voltage_buffer[i] * voltage_buffer[i];
            end
            v_std = (sum_v_sq / 1024) - ((sum_v / 1024) * (sum_v / 1024));
            
            // 4. em_power_max
            em_power_max = 0;
            for (i=0; i<1024; i=i+1) if (em_buffer[i] > em_power_max) em_power_max = em_buffer[i];
            
            // 5. t_delta_max: max difference between two temperature sensors
            // Assume temp_sensors is 16 x 8-bit values packed
            // Implement accordingly...
            
            // ... other features similar
            
            // Pack into output vector
            features[0]  = v_min;
            features[1]  = v_slope_max;
            features[2]  = v_std;
            features[3]  = v_high_freq_energy;
            features[4]  = em_power_max;
            features[5]  = em_band_ratio;
            features[6]  = t_delta_max;
            features[7]  = t_gradient;
            features[8]  = t_rate;
            features[9]  = t_ambient;
            features[10] = corr_v_em;
            features[11] = glitch_width_estimate;
            features[12] = repetition_rate;
            features[13] = pcie_activity[15:0];
            features[14] = {8'b0, workload_hash};
            features[15] = v_min_baseline_ma;
            features[16] = time_since_last_alarm;
        end
    end
    
    // Buffer update every clock (sample rate adaptation may be needed)
    always @(posedge clk) begin
        if (enable) begin
            voltage_buffer[sample_cnt[9:0]] <= adc_voltage;
            em_buffer[sample_cnt[9:0]] <= adc_em;
            sample_cnt <= sample_cnt + 1;
        end
    end
endmodule
