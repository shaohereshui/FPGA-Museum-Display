// Board-tested 40 MHz clock for the TF/FAT32/BMP control domain.
module sd_tf_pll (
    input  wire refclk,
    input  wire reset,
    output wire locked,
    output wire clk_40
);
    wire feedback;
    wire shifted;
    wire [4:0] pll_clocks;

    assign {shifted, feedback} = pll_clocks[1:0];

    EG_LOGIC_BUFG feedback_buffer (.i(feedback), .o(clk_40));

    EG_PHY_PLL #(
        .DPHASE_SOURCE("DISABLE"), .DYNCFG("DISABLE"),
        .FIN("50.000000"), .FEEDBK_MODE("NORMAL"),
        .FEEDBK_PATH("CLKC0_EXT"), .STDBY_ENABLE("DISABLE"),
        .PLLRST_ENA("ENABLE"), .SYNC_ENABLE("DISABLE"),
        .GMC_GAIN(2), .ICP_CURRENT(9), .KVCO(2),
        .LPF_CAPACITOR(1), .LPF_RESISTOR(8),
        .REFCLK_DIV(5), .FBCLK_DIV(4),
        .CLKC0_ENABLE("ENABLE"), .CLKC0_DIV(20),
        .CLKC0_CPHASE(19), .CLKC0_FPHASE(0),
        .CLKC1_ENABLE("ENABLE"), .CLKC1_DIV(20),
        .CLKC1_CPHASE(9), .CLKC1_FPHASE(0)
    ) pll_inst (
        .refclk(refclk), .reset(reset), .stdby(1'b0),
        .extlock(locked), .load_reg(1'b0),
        .psclk(1'b0), .psdown(1'b0), .psstep(1'b0),
        .psclksel(3'b000), .psdone(),
        .dclk(1'b0), .dcs(1'b0), .dwe(1'b0),
        .di(8'b0), .daddr(6'b0), .do(),
        .fbclk(clk_40), .clkc(pll_clocks)
    );
endmodule
