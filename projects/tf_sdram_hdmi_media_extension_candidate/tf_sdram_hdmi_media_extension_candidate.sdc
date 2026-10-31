create_clock -name clk_50 -period 20 -waveform {0 10} [get_ports {clk_50}]
derive_pll_clocks
rename_clock -name sd_clk -source [get_ports {clk_50}] -master_clock {clk_50} [get_pins {core/tf_clock/pll_inst.clkc[0]}]
rename_clock -name mem_clk -source [get_ports {clk_50}] -master_clock {clk_50} [get_pins {core/clocks/pll_inst.clkc[1]}]
rename_clock -name mem_clk_sft -source [get_ports {clk_50}] -master_clock {clk_50} [get_pins {core/clocks/pll_inst.clkc[2]}]
rename_clock -name pixel_clk -source [get_ports {clk_50}] -master_clock {clk_50} [get_pins {core/video_pll/pll_inst.clkc[0]}]
rename_clock -name serial_clk_5x -source [get_ports {clk_50}] -master_clock {clk_50} [get_pins {core/video_pll/pll_inst.clkc[1]}]
create_generated_clock -name adc_clk -source [get_pins {core/video_pll/pll_inst.clkc[0]}] -divide_by 2 [get_pins {core/light_sensor/light_adc.clk}]
set_clock_groups -asynchronous -group {sd_clk} -group {mem_clk} -group {pixel_clk adc_clk}

