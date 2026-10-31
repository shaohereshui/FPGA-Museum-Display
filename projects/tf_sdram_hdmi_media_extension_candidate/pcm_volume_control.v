// Exact 0..100 percent scaling for signed 16-bit stereo PCM.
// Input rate is 48 kHz in the 27 MHz pixel domain. A restoring divide by 100
// uses 23 clocks per sample, comfortably below the 562/563-clock interval.
// Truncation is toward zero; 0 is silent and 100 preserves every input bit.
module pcm_volume_control (
    input wire clk, rst_n,
    input wire sample_valid,
    input wire [15:0] left_sample, right_sample,
    input wire [6:0] volume_percent,
    output reg sample_valid_out,
    output reg [15:0] left_out, right_out,
    output reg busy, overrun
);
    wire [6:0] gain = volume_percent > 7'd100 ? 7'd100 : volume_percent;
    wire [15:0] left_abs = left_sample[15] ? (~left_sample + 16'd1) : left_sample;
    wire [15:0] right_abs = right_sample[15] ? (~right_sample + 16'd1) : right_sample;
    reg left_negative, right_negative;
    reg [22:0] left_dividend, right_dividend;
    reg [22:0] left_quotient, right_quotient;
    reg [6:0] left_remainder, right_remainder;
    reg [4:0] bits_left;
    wire [7:0] left_trial = {left_remainder, left_dividend[22]};
    wire [7:0] right_trial = {right_remainder, right_dividend[22]};
    wire left_bit = left_trial >= 8'd100;
    wire right_bit = right_trial >= 8'd100;
    wire [22:0] left_next = {left_quotient[21:0], left_bit};
    wire [22:0] right_next = {right_quotient[21:0], right_bit};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_valid_out <= 0;
            left_out <= 0; right_out <= 0;
            busy <= 0; overrun <= 0; bits_left <= 0;
            left_negative <= 0; right_negative <= 0;
            left_dividend <= 0; right_dividend <= 0;
            left_quotient <= 0; right_quotient <= 0;
            left_remainder <= 0; right_remainder <= 0;
        end else begin
            sample_valid_out <= 0;
            if (sample_valid && busy)
                overrun <= 1;
            if (sample_valid && !busy) begin
                left_dividend <= left_abs * gain;
                right_dividend <= right_abs * gain;
                left_negative <= left_sample[15];
                right_negative <= right_sample[15];
                left_quotient <= 0; right_quotient <= 0;
                left_remainder <= 0; right_remainder <= 0;
                bits_left <= 5'd22;
                busy <= 1;
            end else if (busy) begin
                left_dividend <= {left_dividend[21:0], 1'b0};
                right_dividend <= {right_dividend[21:0], 1'b0};
                left_remainder <= left_bit ? left_trial - 8'd100 : left_trial[6:0];
                right_remainder <= right_bit ? right_trial - 8'd100 : right_trial[6:0];
                left_quotient <= left_next;
                right_quotient <= right_next;
                bits_left <= bits_left - 1'b1;
                if (bits_left == 0) begin
                    left_out <= left_negative ? (16'd0 - left_next[15:0]) : left_next[15:0];
                    right_out <= right_negative ? (16'd0 - right_next[15:0]) : right_next[15:0];
                    sample_valid_out <= 1;
                    busy <= 0;
                end
            end
        end
    end
endmodule
