module tmds_serializer_core (
    input  wire       serial_clk,
    input  wire       rst_n,
    input  wire [9:0] tmds_word,
    output reg  [2:0] phase,
    output reg        serial_d0,
    output reg        serial_d1
);

    always @(posedge serial_clk or negedge rst_n) begin
        if (!rst_n)
            phase <= 3'd4;
        else if (phase == 3'd4)
            phase <= 3'd0;
        else
            phase <= phase + 3'd1;
    end

    always @(*) begin
        case (phase)
            3'd0: begin serial_d0 = tmds_word[0]; serial_d1 = tmds_word[1]; end
            3'd1: begin serial_d0 = tmds_word[2]; serial_d1 = tmds_word[3]; end
            3'd2: begin serial_d0 = tmds_word[4]; serial_d1 = tmds_word[5]; end
            3'd3: begin serial_d0 = tmds_word[6]; serial_d1 = tmds_word[7]; end
            default: begin serial_d0 = tmds_word[8]; serial_d1 = tmds_word[9]; end
        endcase
    end

endmodule

// 5x TMDS serializer.
//
// The encoded pixel word is produced in the pixel clock domain at one fifth of the
// serial clock rate. Driving the ODDR straight from that combinational path leaves the
// word transition time undetermined at the ODDR sampling edges, and the vendor ODDR
// samples d0 on the rising edge and d1 on the falling edge with different latency, so a
// word that changes near an edge can be captured as a mix of two words. Here the word
// is captured once per word window into a serial-domain register and the two ODDR data
// inputs are registered on the falling edge, so both ODDR sampling edges of a serial
// cycle see data that is stable across the whole cycle:
//
//   * `word_r` is loaded on the falling edge at the last phase of a word, so every bit
//     of one window comes from one single word;
//   * `d0_r`/`d1_r` are loaded on every falling edge, so the ODDR inputs cannot change
//     between the rising and falling edges that sample them;
//   * the pixel-domain path therefore has a full serial clock period to settle.
//
// The core's reset is released synchronously in the serial domain so that all serializer
// instances fed by the same reset leave reset on the same edge and share one boundary.
module tmds_serializer_5x (
    input  wire       serial_clk,
    input  wire       rst_n,
    input  wire [9:0] tmds_word,
    output wire       tmds_p
);

    wire [2:0] phase;
    wire       serial_d0;
    wire       serial_d1;

    reg  [9:0] word_r;
    reg        d0_r, d1_r;
    reg  [1:0] rst_sync;

    always @(posedge serial_clk or negedge rst_n) begin
        if (!rst_n)
            rst_sync <= 2'b00;
        else
            rst_sync <= {rst_sync[0], 1'b1};
    end

    tmds_serializer_core core_inst (
        .serial_clk(serial_clk),
        .rst_n(rst_sync[1]),
        .tmds_word(word_r),
        .phase(phase),
        .serial_d0(serial_d0),
        .serial_d1(serial_d1)
    );

    always @(negedge serial_clk or negedge rst_n) begin
        if (!rst_n) begin
            word_r <= 10'b1101010100;
            d0_r <= 1'b0;
            d1_r <= 1'b0;
        end else begin
            d0_r <= serial_d0;
            d1_r <= serial_d1;
            if (phase == 3'd4)
                word_r <= tmds_word;
        end
    end

    EG_LOGIC_ODDR #(
        .ASYNCRST("ENABLE")
    ) oddr_inst (
        .q(tmds_p),
        .clk(serial_clk),
        .d1(d1_r),
        .d0(d0_r),
        .rst(~rst_n)
    );

endmodule
