// Emergency exit sign, drawn like the startup badge: a run-length (span) table
// is stored in a small ROM, fetched during horizontal blanking and compared
// against the pixel position. No TF card, no frame buffer, no image scaling.
//
// The artwork is rendered at 720x480 from clean vector shapes (door frame,
// running figure, arrow, 安全出口 and EXIT), then stored as a 360x240 binary
// mask; each source pixel is displayed as a 2x2 block.
module emergency_picture (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        de,
    input  wire [9:0]  h_count,
    input  wire [9:0]  v_count,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);
    localparam [23:0] GREEN = 24'h005A32;
    localparam [23:0] WHITE = 24'hFFFFFF;

    // LUT case tables generated from the emergency span/row data.
`include "emergency_rom.vh"

    reg [9:0] span_addr;
    reg [7:0] row_addr;
    wire [17:0] span_data = span_word(span_addr);
    wire [15:0] row_data  = row_word(row_addr);

    // Per-line prefetch during horizontal blanking (h_count == 720).
    reg [1:0] fetch_state;
    reg [3:0] span_count, fetch_index;
    reg [9:0] span_start [0:15];
    reg [9:0] span_end   [0:15];

    wire [9:0] sy = v_count >> 1;
    wire [9:0] sy_next = (v_count == 10'd479) ? 10'd0 : ((v_count + 10'd1) >> 1);

    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_state <= 0; span_count <= 0; fetch_index <= 0;
            span_addr <= 0; row_addr <= 0;
            for (j = 0; j < 16; j = j + 1) begin
                span_start[j] <= 0; span_end[j] <= 0;
            end
        end else if (h_count == 10'd720) begin
            row_addr <= sy_next[7:0];
            fetch_state <= 2'd1;
        end else if (fetch_state == 2'd1) begin
            // row_data is asynchronous for the registered row_addr.
            span_count <= row_data[15:12];
            span_addr <= row_data[11:0];
            fetch_index <= 0;
            fetch_state <= (row_data[15:12] != 0) ? 2'd2 : 2'd0;
        end else if (fetch_state == 2'd2) begin
            span_start[fetch_index] <= span_data[17:9];
            span_end[fetch_index] <= span_data[8:0];
            if (fetch_index + 1'b1 == span_count) begin
                fetch_state <= 2'd0;
            end else begin
                fetch_index <= fetch_index + 1'b1;
                span_addr <= span_addr + 1'b1;
            end
        end
    end

    wire [9:0] sx = h_count >> 1;
    reg hit;
    integer k;
    always @* begin
        hit = 1'b0;
        for (k = 0; k < 16; k = k + 1)
            if (k < span_count && sx >= span_start[k] && sx < span_end[k])
                hit = 1'b1;
    end

    assign rgb_out = !(enable && de) ? rgb_in :
                     hit ? WHITE : GREEN;
endmodule
