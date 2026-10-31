// Top-left zoom viewport indicator (minimap).
//
// A hollow black rectangle represents the whole picture (720x480 scaled 1:8 ->
// 90x60 at 8,8) and a hollow red rectangle shows the region currently magnified
// by the full-screen zoom view. Both are 1-pixel outlines; the picture inside
// stays visible. The indicator is enabled only after the magnification has
// actually increased above 1.0x (handled by the parent).
module zoom_minimap (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [9:0]  win_x,
    input  wire [9:0]  win_y,
    input  wire [9:0]  span_x,
    input  wire [9:0]  span_y,
    input  wire        de,
    input  wire [9:0]  h_count,
    input  wire [9:0]  v_count,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);
    localparam integer BOX_X = 8;
    localparam integer BOX_Y = 8;
    localparam integer BOX_W = 90; // 720 / 8
    localparam integer BOX_H = 60; // 480 / 8

    // Viewport rectangle: source coordinates scaled by 1/8, minimum 2 px.
    wire [9:0] vp_x = BOX_X + (win_x >> 3);
    wire [9:0] vp_y = BOX_Y + (win_y >> 3);
    wire [9:0] vp_w = (span_x >> 3) < 2 ? 10'd2 : (span_x >> 3);
    wire [9:0] vp_h = (span_y >> 3) < 2 ? 10'd2 : (span_y >> 3);

    // 1-pixel outlines only (no filled background).
    wire box_border = de &&
        (((h_count == BOX_X) || (h_count == BOX_X + BOX_W - 1)) &&
         (v_count >= BOX_Y) && (v_count < BOX_Y + BOX_H)) ||
        (((v_count == BOX_Y) || (v_count == BOX_Y + BOX_H - 1)) &&
         (h_count >= BOX_X) && (h_count < BOX_X + BOX_W));

    wire vp_border = de &&
        (((h_count == vp_x) || (h_count == vp_x + vp_w - 1)) &&
         (v_count >= vp_y) && (v_count < vp_y + vp_h)) ||
        (((v_count == vp_y) || (v_count == vp_y + vp_h - 1)) &&
         (h_count >= vp_x) && (h_count < vp_x + vp_w));

    assign rgb_out = !enable ? rgb_in :
                     vp_border ? 24'hFF0000 :
                     box_border ? 24'h000000 : rgb_in;
endmodule
