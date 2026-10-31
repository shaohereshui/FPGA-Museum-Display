// Small synthesizable CDC FIFO for SDRAM read returns and the pixel clock.
// The read data is registered in the pixel-clock domain.
module video_async_fifo #(
    parameter integer ADDR_WIDTH = 10,
    parameter integer ALMOST_FULL_MARGIN = 16
) (
    input wire wr_clk,
    input wire rd_clk,
    input wire rst_n,
    input wire wr_en,
    input wire [31:0] wr_data,
    output wire full,
    input wire rd_en,
    output reg [31:0] rd_data,
    output wire empty,
    output wire almost_full,
    output wire [ADDR_WIDTH:0] used_words
);
    localparam integer DEPTH = 1 << ADDR_WIDTH;
    reg [31:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wr_ptr, rd_ptr;
    reg [ADDR_WIDTH:0] rd_gray_wr1, rd_gray_wr2;
    reg [ADDR_WIDTH:0] wr_gray_rd1, wr_gray_rd2;
    reg full_reg, empty_reg;
    wire [ADDR_WIDTH:0] wr_gray = (wr_ptr >> 1) ^ wr_ptr;
    wire [ADDR_WIDTH:0] rd_gray = (rd_ptr >> 1) ^ rd_ptr;
    wire [ADDR_WIDTH:0] wr_ptr_next = wr_ptr + (wr_en && !full_reg);
    wire [ADDR_WIDTH:0] rd_ptr_next = rd_ptr + (rd_en && !empty_reg);
    wire [ADDR_WIDTH:0] wr_gray_next = (wr_ptr_next >> 1) ^ wr_ptr_next;
    wire [ADDR_WIDTH:0] rd_gray_next = (rd_ptr_next >> 1) ^ rd_ptr_next;
    wire [ADDR_WIDTH:0] full_compare = {
        ~rd_gray_wr2[ADDR_WIDTH:ADDR_WIDTH-1],
        rd_gray_wr2[ADDR_WIDTH-2:0]
    };
    reg [ADDR_WIDTH:0] fifo_used_words;

    assign full = full_reg;
    assign empty = empty_reg;
    assign almost_full = fifo_used_words >= (DEPTH - ALMOST_FULL_MARGIN);
    assign used_words = fifo_used_words;

    function [ADDR_WIDTH:0] gray_to_bin;
        input [ADDR_WIDTH:0] gray;
        integer bit_index;
        begin
            gray_to_bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
            for (bit_index = ADDR_WIDTH - 1; bit_index >= 0; bit_index = bit_index - 1)
                gray_to_bin[bit_index] = gray_to_bin[bit_index + 1] ^ gray[bit_index];
        end
    endfunction

    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_gray_wr1 <= 0;
            rd_gray_wr2 <= 0;
            full_reg <= 0;
            fifo_used_words <= 0;
        end else begin
            rd_gray_wr1 <= rd_gray;
            rd_gray_wr2 <= rd_gray_wr1;
            fifo_used_words <= wr_ptr_next - gray_to_bin(rd_gray_wr1);
            if (wr_en && !full_reg) begin
                memory[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            end
            wr_ptr <= wr_ptr_next;
            full_reg <= wr_gray_next == full_compare;
        end
    end

    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            wr_gray_rd1 <= 0;
            wr_gray_rd2 <= 0;
            rd_data <= 0;
            empty_reg <= 1;
        end else begin
            wr_gray_rd1 <= wr_gray;
            wr_gray_rd2 <= wr_gray_rd1;
            if (rd_en && !empty_reg) begin
                rd_data <= memory[rd_ptr[ADDR_WIDTH-1:0]];
            end
            rd_ptr <= rd_ptr_next;
            empty_reg <= rd_gray_next == wr_gray_rd2;
        end
    end
endmodule
