// Song-specific timed Chinese subtitles drawn inside one full-width white bar at
// the very bottom of the screen. The ROM is generated on the PC from the user's
// audio/LRC; the FPGA displays it using consumed PCM sample time.
// The RGB register replaces the original OSD p1 register, preserving latency.
module lyrics_overlay (
    input wire clk, rst_n,
    input wire sample_tick, playback_active,
    input wire enable_switch,
    input wire de,
    input wire [9:0] h_count, v_count,
    input wire [23:0] rgb_in,
    output wire [23:0] rgb_out,
    output reg [31:0] sample_position,
    output wire enabled,
    output wire text_active
);
    localparam integer BAND_Y = 448;   // white subtitle bar: exactly the lyric row, bottom aligned
    localparam integer BAND_H = 32;
    localparam integer TEXT_Y = 448;   // 32 px Chinese glyph row fills the bar
    localparam integer TEXT_H = 32;
    localparam [23:0] BAND_COLOR = 24'hFFFFFF;
    localparam [23:0] TEXT_COLOR = 24'h000000;

    reg enable_meta, enable_sync;
    reg [6:0] cue_index, cue_index_q;
    wire [7:0] cue_count;
    wire [31:0] track_samples;
    wire [228:0] cue_data;
    wire [31:0] cue_start = cue_data[228:197];
    wire [31:0] cue_end = cue_data[196:165];
    wire [4:0] cue_length = cue_data[164:160];
    wire [159:0] cue_codes = cue_data[159:0];
    wire cue_ready = cue_index_q == cue_index;
    reg line_valid;
    reg [4:0] line_length;
    reg [159:0] line_codes;
    reg [9:0] line_left;
    wire [9:0] line_width = {line_length,5'd0};
    wire [9:0] relative_x = h_count-line_left;
    wire [9:0] relative_y = v_count-TEXT_Y;
    // The bar replaces the old dimmed box: full width, white, black glyphs.
    wire lyric_on = line_valid && enable_sync && playback_active;
    wire text_inside = de && lyric_on &&
                       h_count>=line_left && h_count<line_left+line_width &&
                       v_count>=TEXT_Y && v_count<TEXT_Y+TEXT_H;
    wire band_inside = de && lyric_on &&
                       v_count>=BAND_Y && v_count<BAND_Y+BAND_H;
    wire [4:0] character_index = relative_x[9:5];
    wire [7:0] glyph_id = text_inside ? line_codes[159-(character_index<<3) -: 8] : 8'd0;
    wire [11:0] glyph_address = {glyph_id,relative_y[4:1]};
    wire [15:0] glyph_row;
    reg [23:0] rgb_pipe;
    reg text_pipe, band_pipe;
    reg [3:0] glyph_column_pipe;
    assign enabled = enable_sync;
    assign text_active = lyric_on;
    assign rgb_out = text_pipe && glyph_row[15-glyph_column_pipe] ? TEXT_COLOR :
                     band_pipe ? BAND_COLOR : rgb_pipe;

    song_lyrics_rom rom (
        .clk(clk), .cue_address(cue_index), .cue_data(cue_data),
        .glyph_address(glyph_address), .glyph_row(glyph_row),
        .cue_count(cue_count), .track_samples(track_samples)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_meta<=0; enable_sync<=0;
            sample_position<=0; cue_index<=0; cue_index_q<=0;
            line_valid<=0; line_length<=0; line_codes<=0; line_left<=360;
            rgb_pipe<=0; text_pipe<=0; band_pipe<=0; glyph_column_pipe<=0;
        end else begin
            enable_meta<=enable_switch; enable_sync<=enable_meta;
            cue_index_q<=cue_index;
            // Only consumed song samples advance time. Volume zero and SW4
            // do not affect these events; SW1 pause stops them in the player.
            if (sample_tick) begin
                if (sample_position==track_samples-1'b1) begin
                    sample_position<=0;
                    cue_index<=0;
                end else sample_position<=sample_position+1'b1;
            end
            if (!(sample_tick && sample_position==track_samples-1'b1) &&
                cue_ready && sample_position>=cue_end &&
                {1'b0,cue_index}+8'd1<cue_count)
                cue_index<=cue_index+1'b1;
            // Freeze a complete line for a frame, avoiding partially changed text.
            if (h_count==0 && v_count==0) begin
                line_valid<=playback_active && cue_ready && cue_count!=0 &&
                            cue_length!=0 && cue_length<=20 &&
                            sample_position>=cue_start && sample_position<cue_end;
                line_length<=cue_length;
                line_codes<=cue_codes;
                line_left<=(10'd720-{cue_length,5'd0})>>1;
            end
            rgb_pipe<=rgb_in;
            text_pipe<=text_inside;
            band_pipe<=band_inside;
            glyph_column_pipe<=relative_x[4:1];
        end
    end
endmodule
