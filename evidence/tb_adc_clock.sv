`timescale 1ns/1ps
module tb_adc_clock;
    reg clk = 0;
    always #18.519 clk = ~clk;
    reg rst_n = 0;
    wire [11:0] sample;
    wire sample_valid;
    wire [3:0] brightness;
    wire valid;
    integer samples = 0;
    reg previous_valid = 0;

    eg4_light_sensor #(.SAMPLE_PERIOD_CYCLES(64)) dut (
        .clk(clk), .rst_n(rst_n), .sample(sample), .sample_valid(sample_valid)
    );
    ambient_brightness filter (
        .clk(clk), .rst_n(rst_n), .sample(sample), .sample_valid(sample_valid),
        .brightness(brightness), .valid(valid)
    );

    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            if (sample_valid && previous_valid) $fatal(1, "duplicate valid pulse");
            if (sample_valid) begin
                if (sample !== dut.light_adc.dout) $fatal(1, "captured stale ADC data");
                samples = samples + 1;
            end
            previous_valid = sample_valid;
        end
    end

    task settle(input [11:0] code, input [3:0] expected_level);
        integer before_count;
        begin
            dut.light_adc.test_code = code;
            before_count = samples;
            repeat (64 * 160) @(negedge clk);
            if (samples - before_count < 159 || samples - before_count > 161)
                $fatal(1, "sample cadence mismatch: %0d", samples - before_count);
            if (!valid || brightness !== expected_level || sample !== code)
                $fatal(1, "code %0d: raw=%0d brightness=%0d valid=%b", code, sample, brightness, valid);
        end
    endtask

    initial begin
        #200; rst_n = 1;
        settle(12'd2300, 4'd6);
        settle(12'd0, 4'd0);
        settle(12'd3900, 4'd9);
        $display("PASS: ADC <=16 MHz, SOC timing, one valid per conversion, 1 ms-equivalent cadence, raw codes and 6/0/9 mapping");
        $finish;
    end
    initial begin #2000000; $fatal(1, "ADC simulation timeout"); end
endmodule

// Protocol model with injected digital codes, not an analog sensor model.
module EG_PHY_ADC #(
    parameter CH0="DISABLE", CH1="DISABLE", CH2="DISABLE", CH3="DISABLE",
    parameter CH4="DISABLE", CH5="DISABLE", CH6="DISABLE", CH7="DISABLE",
    parameter VREF="DISABLE"
) (
    input clk, pd, input [2:0] s, input soc,
    output reg eoc=0, output reg [11:0] dout=0
);
    reg [11:0] test_code = 2300;
    reg [11:0] converting_code;
    integer remaining = 0;
    realtime last_rise = 0;
    realtime last_soc_change = -1000;
    always @(soc) last_soc_change = $realtime;
    always @(posedge clk) begin
        if (last_rise != 0 && $realtime-last_rise < 62.5)
            $fatal(1, "ADC clock exceeds 16 MHz: period %0.3f ns", $realtime-last_rise);
        if (soc && $realtime-last_soc_change < 10)
            $fatal(1, "SOC setup below 10 ns");
        last_rise = $realtime;
        eoc <= #13.5 0;
        if (pd) remaining <= 0;
        else if (remaining != 0) begin
            remaining <= remaining - 1;
            if (remaining == 1) begin
                eoc <= #13.5 1;
                dout <= #16 converting_code;
            end
        end else if (soc) begin
            if (s !== 1 || CH1 != "ENABLE") $fatal(1, "incorrect ADC channel");
            remaining <= 16;
            converting_code <= test_code;
        end
    end
endmodule
