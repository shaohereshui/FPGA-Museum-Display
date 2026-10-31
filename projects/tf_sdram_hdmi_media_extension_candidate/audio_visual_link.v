// P2 audio-visual link (OSD accent only).
// Smoothed low-band energy selects one of four OSD accent colours used by the
// interaction menu highlight and the guide-card title. Shift/add/compare only.
module audio_visual_link (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,
    input  wire        active,
    input  wire [223:0] levels,
    output reg  [23:0] accent_color
);
    localparam [23:0] ACCENT_0 = 24'hFFFF40;
    localparam [23:0] ACCENT_1 = 24'hFFC830;
    localparam [23:0] ACCENT_2 = 24'hFF9020;
    localparam [23:0] ACCENT_3 = 24'hFF5060;

    // Sum the eight lowest bands. Each height is 0..72, so the sum is 0..576.
    wire [6:0] band0 = levels[6:0];
    wire [6:0] band1 = levels[13:7];
    wire [6:0] band2 = levels[20:14];
    wire [6:0] band3 = levels[27:21];
    wire [6:0] band4 = levels[34:28];
    wire [6:0] band5 = levels[41:35];
    wire [6:0] band6 = levels[48:42];
    wire [6:0] band7 = levels[55:49];
    wire [9:0] bass_sum = band0 + band1 + band2 + band3 +
                          band4 + band5 + band6 + band7;

    reg [9:0] smooth;
    reg [1:0] level;

    always @* begin
        // 0..3 accent levels over a smoothed bass energy of 0..576.
        if (smooth >= 10'd384)
            level = 2'd3;
        else
            level = smooth[8:7];
        case (level)
            2'd0: accent_color = ACCENT_0;
            2'd1: accent_color = ACCENT_1;
            2'd2: accent_color = ACCENT_2;
            default: accent_color = ACCENT_3;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            smooth <= 10'd0;
        end else if (sample_tick) begin
            if (!active)
                smooth <= 10'd0;
            else if (bass_sum > smooth)
                // One-pole smoothing, shift only: about 8-sample time constant.
                smooth <= smooth + ((bass_sum - smooth + 10'd7) >> 3);
            else if (smooth > bass_sum)
                smooth <= smooth - ((smooth - bass_sum + 10'd7) >> 3);
        end
    end
endmodule
