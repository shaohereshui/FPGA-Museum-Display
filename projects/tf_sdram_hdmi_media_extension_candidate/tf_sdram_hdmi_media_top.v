module tf_sdram_hdmi_media_top (
    input  wire        clk_50,
    input  wire        rst_n,
    input  wire        key_prev_n,
    input  wire        key_next_n,
    input  wire        key_mode_n,
    input  wire        sw_param,
    input  wire        sw_audio,
    input  wire        sw_volume,
    input  wire        sw_lyrics,
    input  wire        ir_rx,
    input  wire        subtitle_rx,
    output wire        subtitle_tx,
    output wire [3:0]  keypad_row,
    input  wire [3:0]  keypad_col,
    input  wire        sd_miso,
    output wire        sd_dclk,
    output wire        sd_mosi,
    output wire        sd_ncs,
    output wire        HDMI_CLK_P,
    output wire        HDMI_D0_P,
    output wire        HDMI_D1_P,
    output wire        HDMI_D2_P,
    output wire        led
);
    wire sdram_clk, sdram_ras_n, sdram_cas_n, sdram_we_n;
    wire [10:0] sdram_addr;
    wire [1:0] sdram_ba;
    wire [3:0] sdram_dm;
    wire [31:0] sdram_dq;

    tf_sdram_hdmi_media_core core (
        .clk_50(clk_50), .rst_n(rst_n),
        .key_prev_n(key_prev_n), .key_next_n(key_next_n),
        .key_mode_n(key_mode_n), .sw_param(sw_param), .sw_audio(sw_audio),
        .sw_volume(sw_volume),
        .sw_lyrics(sw_lyrics), .ir_rx(ir_rx),
        .subtitle_rx(subtitle_rx), .subtitle_tx(subtitle_tx),
        .keypad_row(keypad_row), .keypad_col(keypad_col),
        .sd_miso(sd_miso),
        .sd_dclk(sd_dclk), .sd_mosi(sd_mosi), .sd_ncs(sd_ncs),
        .HDMI_CLK_P(HDMI_CLK_P), .HDMI_D0_P(HDMI_D0_P),
        .HDMI_D1_P(HDMI_D1_P), .HDMI_D2_P(HDMI_D2_P), .led(led),
        .sdram_clk(sdram_clk), .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
        .sdram_addr(sdram_addr), .sdram_ba(sdram_ba),
        .sdram_dm(sdram_dm), .sdram_dq(sdram_dq)
    );

    EG_PHY_SDRAM_2M_32 memory (
        .clk(sdram_clk), .ras_n(sdram_ras_n), .cas_n(sdram_cas_n),
        .we_n(sdram_we_n), .addr(sdram_addr), .ba(sdram_ba),
        .dq(sdram_dq), .cs_n(1'b0), .dm0(sdram_dm[0]),
        .dm1(sdram_dm[1]), .dm2(sdram_dm[2]), .dm3(sdram_dm[3]),
        .cke(1'b1)
    );
endmodule

