// EG4 internal 12-bit SAR ADC reader.  ADC channel 1 is exposed on the board
// GPIOB30/ADC_CH_1 path described by the board schematics.
module eg4_light_sensor #(
    parameter integer SAMPLE_PERIOD_CYCLES = 27_000
) (
    input  wire       clk,
    input  wire       rst_n,
    output reg [11:0] sample,
    output reg        sample_valid
);
    wire adc_eoc;
    wire [11:0] adc_data;
    reg adc_soc;
    reg [15:0] sample_counter;
    reg adc_clk;
    reg adc_eoc_q;

    EG_PHY_ADC #(
        .CH0("DISABLE"), .CH1("ENABLE"), .CH2("DISABLE"), .CH3("DISABLE"),
        .CH4("DISABLE"), .CH5("DISABLE"), .CH6("DISABLE"), .CH7("DISABLE"),
        .VREF("DISABLE")
    ) light_adc (
        .clk(adc_clk), .pd(1'b0), .s(3'd1), .soc(adc_soc),
        .eoc(adc_eoc), .dout(adc_data)
    );

    // The 27 MHz pixel clock exceeds the ADC's 16 MHz limit. Divide by two;
    // update SOC only when that divided clock falls, giving 37 ns of margin.
    // The counter still measures a 27000-pixel-clock (1 ms) sample interval.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_clk <= 1'b0;
            adc_soc <= 1'b0;
            sample_counter <= 16'd0;
        end else begin
            adc_clk <= ~adc_clk;
            if (adc_clk) begin
                adc_soc <= 1'b0;
                if (sample_counter == SAMPLE_PERIOD_CYCLES / 2 - 1) begin
                    sample_counter <= 16'd0;
                    adc_soc <= 1'b1;
                end else begin
                    sample_counter <= sample_counter + 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample <= 12'd2048;
            sample_valid <= 1'b0;
            adc_eoc_q <= 1'b0;
        end else begin
            adc_eoc_q <= adc_eoc;
            sample_valid <= 1'b0;
            // EOC now spans two pixel cycles; publish each conversion once.
            if (adc_eoc && !adc_eoc_q) begin
                sample <= adc_data;
                sample_valid <= 1'b1;
            end
        end
    end
endmodule
