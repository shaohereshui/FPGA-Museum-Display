// SD v2 high-capacity cards only. CMD17 emits a 512-byte sector stream.
module sd_spi_media_reader #(
    parameter integer INIT_HALF = 125,
    parameter integer READ_HALF = 4,
    parameter integer TIMEOUT = 65535,
    parameter integer STARTUP_CYCLES = 4_000_000,
    parameter integer DRAIN_BYTES = 1024,
    parameter integer CMD0_RESPONSE_BYTES = 32
) (
    input wire clk, rst_n, start, sd_miso,
    input wire pause,
    input wire [31:0] sector,
    output reg sd_clk, sd_mosi, sd_ncs, ready, busy,
    output wire idle,
    output reg valid, done,
    output reg [8:0] index,
    output reg [7:0] data,
    output reg [3:0] error,
    output reg [7:0] cmd0_r1,
    output reg [7:0] cmd8_r1,
    output reg [31:0] cmd8_r7,
    output reg [7:0] cmd17_r1,
    output reg start_ack,
    output wire [7:0] debug_phase
);
    localparam POWER=0, SEND=1, RESPONSE=2, EXTRA=3,
               IDLE=4, TOKEN=5, PAYLOAD=6, CRC=7, FAIL=8, ADVANCE=9,
               GAP=10, DRAIN=11, DRAIN_GAP=12, SETTLE=13;
    reg [3:0] state;
    reg [2:0] command; // 0 CMD0, 1 CMD8, 2 CMD55, 3 ACMD41, 4 CMD58, 5 CMD17
    reg [47:0] packet;
    reg [2:0] sent;
    reg [7:0] power_count;
    reg [2:0] remaining;
    reg [1:0] crc_count;
    reg [15:0] wait_count, init_attempts;
    reg [3:0] cmd0_attempts;
    reg [31:0] settle_count;
    reg [15:0] drain_count;
    reg [31:0] extra_value;
    reg ocr_gap, read_gap;

    reg launch, xfer, completed;
    reg [7:0] tx, rx, sample;
    reg [2:0] bit_no;
    reg [15:0] divider;
    wire [31:0] extra_next = {extra_value[23:0], rx};
    wire [15:0] half_period = ready ? READ_HALF : INIT_HALF;

    // High nibble is the FSM state; low three bits are the command number.
    assign debug_phase = {state, 1'b0, command};
    assign idle = state == IDLE;

    // Clock idle low; sample input on rising edges, update output on falling edges.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sd_clk <= 0; sd_mosi <= 1; xfer <= 0; completed <= 0;
            rx <= 0; sample <= 0; bit_no <= 0; divider <= 0;
        end else begin
            completed <= 0;
            if (launch && !xfer) begin
                xfer <= 1; bit_no <= 7; sample <= 0;
                sd_mosi <= tx[7]; divider <= half_period - 1'b1;
            end else if (xfer && divider != 0) begin
                divider <= divider - 1'b1;
            end else if (xfer && !sd_clk) begin
                sd_clk <= 1; sample <= {sample[6:0], sd_miso};
                divider <= half_period - 1'b1;
            end else if (xfer) begin
                sd_clk <= 0;
                if (bit_no == 0) begin
                    xfer <= 0; completed <= 1; rx <= sample; sd_mosi <= 1;
                end else begin
                    bit_no <= bit_no - 1'b1;
                    sd_mosi <= tx[bit_no - 1'b1];
                    divider <= half_period - 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= SETTLE; command <= 0; packet <= 0; sent <= 0;
            power_count <= 0; remaining <= 0; crc_count <= 0;
            wait_count <= 0; init_attempts <= 0; extra_value <= 0;
            cmd0_attempts <= 0;
            settle_count <= 0; drain_count <= 0;
            ocr_gap <= 0; read_gap <= 0;
            sd_ncs <= 1; ready <= 0; busy <= 0; valid <= 0;
            done <= 0; index <= 0; data <= 0; error <= 0; start_ack <= 0;
            cmd0_r1 <= 8'hff; cmd8_r1 <= 8'hff; cmd8_r7 <= 0; cmd17_r1 <= 0;
            launch <= 0; tx <= 8'hff;
        end else begin
            launch <= 0; valid <= 0; done <= 0; start_ack <= 0;
            case (state)
                // FPGA reconfiguration does not power-cycle the SD card.
                // Allow rails/clock/pins to settle, then finish clocking any
                // previous single-sector response before sending a new CMD0.
                SETTLE: begin
                    sd_ncs <= 1;
                    if (settle_count == STARTUP_CYCLES-1) begin
                        power_count <= 0; state <= POWER;
                    end else settle_count <= settle_count + 1'b1;
                end
                POWER: if (completed) begin
                    power_count <= power_count + 1'b1;
                end else if (!xfer && !launch) begin
                    if (power_count == 10) begin
                        sd_ncs <= 0; drain_count <= 0; state <= DRAIN;
                    end else begin tx <= 8'hff; launch <= 1; end
                end
                DRAIN: if (completed) begin
                    drain_count <= drain_count + 1'b1;
                end else if (!xfer && !launch) begin
                    if (drain_count == DRAIN_BYTES) begin
                        sd_ncs <= 1; power_count <= 0; state <= DRAIN_GAP;
                    end else begin tx <= 8'hff; launch <= 1; end
                end
                DRAIN_GAP: if (completed) begin
                    power_count <= power_count + 1'b1;
                end else if (!xfer && !launch) begin
                    if (power_count == 10) begin
                        sd_ncs <= 0; command <= 0;
                        packet <= 48'h400000000095; sent <= 0; state <= SEND;
                    end else begin tx <= 8'hff; launch <= 1; end
                end
                SEND: if (completed) begin
                    sent <= sent + 1'b1;
                end else if (!xfer && !launch) begin
                    if (sent == 6) begin wait_count <= 0; state <= RESPONSE; end
                    else begin
                        tx <= packet[47:40]; packet <= {packet[39:0],8'hff};
                        sd_ncs <= 0; launch <= 1;
                    end
                end
                RESPONSE: if (completed) begin
                    if (rx[7]) begin
                        if (command == 0 && wait_count == CMD0_RESPONSE_BYTES-1) begin
                            cmd0_r1 <= rx;
                            if (cmd0_attempts != 4'd7) begin
                                cmd0_attempts <= cmd0_attempts + 1'b1;
                                sd_ncs <= 1; power_count <= 0; state <= POWER;
                            end else begin error <= 1; state <= FAIL; end
                        end else if (wait_count == TIMEOUT) begin error <= 1; state <= FAIL; end
                        else wait_count <= wait_count + 1'b1;
                    end else case (command)
                        0: begin
                            cmd0_r1 <= rx;
                            if (rx == 8'h01) begin
                                command <= 1; packet <= 48'h48000001aa87;
                                sent <= 0; sd_ncs <= 1; state <= GAP;
                            end else if (cmd0_attempts != 4'd7) begin
                                // Retry only after a full deselect/drain cycle;
                                // an old read payload can resemble an R1 byte.
                                cmd0_attempts <= cmd0_attempts + 1'b1;
                                command <= 0; packet <= 48'h400000000095;
                                sent <= 0; sd_ncs <= 1; power_count <= 0; state <= POWER;
                            end else begin error <= 2; state <= FAIL; end
                        end
                        1: begin
                            cmd8_r1 <= rx;
                            // Capture R7 even when R1 is unexpected so the board
                            // diagnostic can distinguish a bad status from a
                            // missing or misaligned response.
                            extra_value <= 0; remaining <= 4; state <= EXTRA;
                        end
                        2: if (rx == 8'h01 || rx == 8'h00) begin
                            command <= 3; packet <= 48'h694000000001;
                            sent <= 0; sd_ncs <= 1; state <= GAP;
                        end else begin error <= 4; state <= FAIL; end
                        3: if (rx == 8'h01) begin
                            if (init_attempts == TIMEOUT) begin error <= 5; state <= FAIL; end
                            else begin
                                init_attempts <= init_attempts + 1'b1;
                                command <= 2; packet <= 48'h770000000001;
                                sent <= 0; sd_ncs <= 1; state <= GAP;
                            end
                        end else if (rx == 8'h00) begin
                            command <= 4; packet <= 48'h7a0000000001;
                            sent <= 0; ocr_gap <= 0; sd_ncs <= 1; state <= GAP;
                        end else begin error <= 5; state <= FAIL; end
                        4: if (rx == 8'h00) begin
                            extra_value <= 0; remaining <= 4; state <= EXTRA;
                        end else begin error <= 6; state <= FAIL; end
                        5: begin
                            cmd17_r1 <= rx;
                            if (rx == 8'h00) begin
                                wait_count <= 0; state <= TOKEN;
                            end else begin error <= 8; state <= FAIL; end
                        end
                        default: begin error <= 15; state <= FAIL; end
                    endcase
                end else if (!xfer && !launch) begin
                    tx <= 8'hff; launch <= 1;
                end
                EXTRA: if (completed) begin
                    extra_value <= {extra_value[23:0],rx};
                    remaining <= remaining - 1'b1;
                    if (remaining == 1) begin
                            if (command == 1) begin
                                cmd8_r7 <= extra_next;
                            if (cmd8_r1 != 8'h01 || extra_next != 32'h000001aa) begin
                                error <= 3; state <= FAIL;
                            end else begin
                                command <= 2; packet <= 48'h770000000001;
                                sent <= 0; sd_ncs <= 1; state <= GAP;
                            end
                        end else if (!extra_next[31] || !extra_next[30]) begin
                            error <= 7; state <= FAIL; // OCR power-up bit 31 and CCS bit 30
                        end else begin ocr_gap <= 1; sd_ncs <= 1; state <= GAP; end
                    end
                end else if (!xfer && !launch) begin tx <= 8'hff; launch <= 1; end
                GAP: begin
                    sd_ncs <= 1;
                    if (completed) begin
                        if (read_gap) begin
                            read_gap <= 0;
                            state <= IDLE;
                        end else if (ocr_gap) begin
                            ready <= 1;
                            ocr_gap <= 0;
                            state <= IDLE;
                        end else begin
                            state <= SEND;
                        end
                    end else if (!xfer && !launch) begin
                        tx <= 8'hff; launch <= 1;
                    end
                end
                IDLE: if (start) begin
                    start_ack <= 1;
                    busy <= 1; index <= 0; command <= 5;
                    packet <= {8'h51,sector,8'h01}; sent <= 0; state <= SEND;
                end
                TOKEN: if (completed) begin
                    if (rx == 8'hfe) begin index <= 0; state <= PAYLOAD; end
                    else if (rx != 8'hff) begin error <= 9; state <= FAIL; end
                    else if (wait_count == TIMEOUT) begin error <= 10; state <= FAIL; end
                    else wait_count <= wait_count + 1'b1;
                end else if (!xfer && !launch) begin tx <= 8'hff; launch <= 1; end
                PAYLOAD: if (completed) begin
                    data <= rx; valid <= 1;
                    if (index == 511) begin crc_count <= 0; state <= CRC; end
                    else state <= ADVANCE;
                end else if (!xfer && !launch && !pause) begin tx <= 8'hff; launch <= 1; end
                ADVANCE: begin index <= index + 1'b1; state <= PAYLOAD; end
                CRC: if (completed) begin
                    if (crc_count == 1) begin
                        busy <= 0; done <= 1; read_gap <= 1; sd_ncs <= 1; state <= GAP;
                    end
                    else crc_count <= 1;
                end else if (!xfer && !launch) begin tx <= 8'hff; launch <= 1; end
                FAIL: begin busy <= 0; sd_ncs <= 1; end
                default: begin error <= 15; state <= FAIL; end
            endcase
        end
    end
endmodule
