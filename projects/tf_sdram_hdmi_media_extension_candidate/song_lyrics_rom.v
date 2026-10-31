// Generated from user-provided audio and locally editable captions.
module song_lyrics_rom(
    input wire clk,
    input wire [6:0] cue_address,
    output reg [228:0] cue_data,
    input wire [11:0] glyph_address,
    output reg [15:0] glyph_row,
    output wire [7:0] cue_count,
    output wire [31:0] track_samples
);
    (* ram_style = "block" *) reg [228:0] cues [0:127];
    (* ram_style = "block" *) reg [15:0] glyphs [0:4095];
    initial begin
        $readmemh("lyric_cues.hex",cues);
        $readmemh("lyric_font.hex",glyphs);
    end
    assign cue_count=8'd51;
    assign track_samples=32'd10906240;
    always @(posedge clk) begin
        cue_data<=cues[cue_address];
        glyph_row<=glyphs[glyph_address];
    end
endmodule
