/************************************************************\
 **  All Right Reserved.
\************************************************************/
/************************************************************\
 ** Memory (system) PLL for the integrated SDRAM interface.
 ** Rewritten to mirror the board-proven sdram_probe_pll settings.
 **
 **	Input frequency:               50.000000MHz
 **	Clock information:
 **		Clock name	| Frequency 	| Phase shift
 **		C0        	|  40.000000MHZ	| 0.0000  DEG   (feedback, unused)
 **		C1        	|  40.000000MHZ	| 0.0000  DEG   -> mem_clk (launch)
 **		C2        	|  40.000000MHZ	| 180.0000 DEG  -> mem_clk_sft (SDRAM clock)
\************************************************************/
`timescale 1 ns / 100 fs

module sys_pll (
  refclk,
  reset,
  clk0_out,
  clk1_out,
  clk2_out 
);

  input refclk;
  input reset;
  output clk0_out;
  output clk1_out;
  output clk2_out;

  wire clk0_buf;
  wire clk2_pll;

  EG_LOGIC_BUFG bufg_feedback (
    .i(clk0_buf),
    .o(clk0_out) 
  );

  // The 180-degree output clocks the integrated SDRAM hard macro. It drives a single
  // hard-macro input, so without an explicit buffer it is placed on local routing
  // (TD reports "Marked 1 clock net(s) utilize the local routing resources" for this
  // net), which leaves the macro's sampling phase uncontrolled. Every board-proven
  // SDRAM design in this workspace drives its SDRAM clock through EG_LOGIC_BUFG
  // (see sdram_probe_pll), so do the same here.
  EG_LOGIC_BUFG bufg_sdram_clk (
    .i(clk2_pll),
    .o(clk2_out) 
  );

  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),
    .DYNCFG("DISABLE"),
    .FIN("50.000000"),
    .FEEDBK_MODE("NORMAL"),
    .FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),
    .PLLRST_ENA("ENABLE"),
    .SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(2),
    .ICP_CURRENT(9),
    .KVCO(2),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(8),
    .REFCLK_DIV(5),
    .FBCLK_DIV(4),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(20),
    .CLKC0_CPHASE(19),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(20),
    .CLKC1_CPHASE(19),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"),
    .CLKC2_DIV(20),
    .CLKC2_CPHASE(9),
    .CLKC2_FPHASE(0) 
  ) pll_inst (
    .refclk(refclk),
    .reset(reset),
    .stdby(1'b0),
    .extlock(open),
    .load_reg(1'b0),
    .psclk(1'b0),
    .psdown(1'b0),
    .psstep(1'b0),
    .psclksel(3'b000),
    .psdone(open),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .do({open, open, open, open, open, open, open, open}),
    .fbclk(clk0_out),
    .clkc({open, open, clk2_pll, clk1_out, clk0_buf}) 
  );

endmodule
