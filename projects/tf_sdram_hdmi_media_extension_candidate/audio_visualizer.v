// Low-cost audio level meter for the HDMI OSD.
// Samples already live in the pixel-clock domain, so this block adds no CDC
// path to the audio packet boundary. It observes the same 48 kHz sample
// events that feed the HDMI audio packets and decays the displayed level over
// a short sample window.
module audio_visualizer #(
    parameter integer WINDOW_SAMPLES = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_valid,
    input  wire [15:0] left_sample,
    input  wire [15:0] right_sample,
    output wire [7:0]  level_bars,
    output reg  [3:0]  level,
    output reg  [15:0] peak_magnitude,
    output reg         active
);
    reg [15:0] window_peak;
    reg [5:0] sample_count;
    wire [15:0] left_magnitude = left_sample[15] ? (~left_sample + 16'd1) : left_sample;
    wire [15:0] right_magnitude = right_sample[15] ? (~right_sample + 16'd1) : right_sample;
    wire [15:0] sample_magnitude =
        left_magnitude >= right_magnitude ? left_magnitude : right_magnitude;
    wire [15:0] current_window_peak =
        sample_magnitude >= window_peak ? sample_magnitude : window_peak;

    function [3:0] magnitude_level;
        input [15:0] magnitude;
        begin
            if      (magnitude >= 16'h6000) magnitude_level = 4'd8;
            else if (magnitude >= 16'h4800) magnitude_level = 4'd7;
            else if (magnitude >= 16'h3600) magnitude_level = 4'd6;
            else if (magnitude >= 16'h2800) magnitude_level = 4'd5;
            else if (magnitude >= 16'h1C00) magnitude_level = 4'd4;
            else if (magnitude >= 16'h1200) magnitude_level = 4'd3;
            else if (magnitude >= 16'h0800) magnitude_level = 4'd2;
            else if (magnitude >= 16'h0400) magnitude_level = 4'd1;
            else                              magnitude_level = 4'd0;
        end
    endfunction

    function [7:0] level_to_bars;
        input [3:0] n;
        begin
            case (n)
                4'd1: level_to_bars = 8'b00000001;
                4'd2: level_to_bars = 8'b00000011;
                4'd3: level_to_bars = 8'b00000111;
                4'd4: level_to_bars = 8'b00001111;
                4'd5: level_to_bars = 8'b00011111;
                4'd6: level_to_bars = 8'b00111111;
                4'd7: level_to_bars = 8'b01111111;
                4'd8: level_to_bars = 8'b11111111;
                default: level_to_bars = 8'b0;
            endcase
        end
    endfunction

    assign level_bars = level_to_bars(level);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_peak    <= 16'd0;
            sample_count   <= 6'd0;
            level          <= 4'd0;
            peak_magnitude <= 16'd0;
            active         <= 1'b0;
        end else if (sample_valid) begin
            active <= 1'b1;
            if (sample_count == WINDOW_SAMPLES - 1) begin
                peak_magnitude <= current_window_peak;
                if (magnitude_level(current_window_peak) >= level)
                    level <= magnitude_level(current_window_peak);
                else if (level != 0)
                    level <= level - 1'b1;
                window_peak  <= 16'd0;
                sample_count <= 6'd0;
            end else begin
                if (sample_magnitude > window_peak)
                    window_peak <= sample_magnitude;
                sample_count <= sample_count + 1'b1;
            end
        end
    end
endmodule
