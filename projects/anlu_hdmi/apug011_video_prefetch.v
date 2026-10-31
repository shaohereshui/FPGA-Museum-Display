// APUG011 reader: issue bounded bursts without interruption.
// The FIFO admission threshold must reserve room for one burst plus pending returns.
// done means at least one frame of requests was issued, not that returns were received.
module apug011_video_prefetch #(
    parameter integer FRAME_WORDS = 307200,
    parameter integer BURST_WORDS = 256,
    parameter integer FIFO_ADDR_WIDTH = 11,
    parameter integer LOOP_FRAME = 0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        restart,
    input  wire [20:0] frame_base,
    input  wire        init_done,
    input  wire        refresh,
    input  wire        busy,
    output reg         app_rd_en,
    output reg  [20:0] app_rd_addr,
    input  wire        rd_valid,
    input  wire [31:0] rd_data,
    input  wire        fifo_full,
    input  wire        fifo_almost_full,
    input  wire [FIFO_ADDR_WIDTH:0] fifo_used_words,
    output wire        fifo_wr_en,
    output wire [31:0] fifo_wr_data,
    output reg         done,
    output reg         restart_done
);
    reg active;
    reg [9:0] issued_in_burst;
    reg [20:0] next_addr;
    reg [FIFO_ADDR_WIDTH:0] pending_reads;
    localparam integer FIFO_DEPTH = 1 << FIFO_ADDR_WIDTH;
    wire burst_has_room =
        (fifo_used_words + pending_reads + BURST_WORDS) <= FIFO_DEPTH;
    wire [FIFO_ADDR_WIDTH:0] pending_reads_next =
        (app_rd_en && !rd_valid) ? pending_reads + 1'b1 :
        (!app_rd_en && rd_valid && pending_reads != 0) ? pending_reads - 1'b1 :
        pending_reads;

    assign fifo_wr_en = rd_valid && !restart && !fifo_full;
    assign fifo_wr_data = rd_data;

    always @(negedge clk or posedge rst) begin
        if (rst) begin
            active <= 0;
            issued_in_burst <= 0;
            next_addr <= 0;
            pending_reads <= 0;
            app_rd_en <= 0;
            app_rd_addr <= 0;
            done <= 0;
            restart_done <= 0;
        end else begin
            app_rd_en <= 0;
            restart_done <= 0;

            if (restart) begin
                // Finish the current burst, then wait for every controller return
                // before rewinding the address. No new burst may start here.
                done <= 0;
                if (active) begin
                    app_rd_en <= 1;
                    app_rd_addr <= frame_base + {next_addr[20:2], 2'b00};
                    if (LOOP_FRAME && next_addr == FRAME_WORDS - 1) begin
                        next_addr <= 0;
                        done <= 1;
                        active <= 0;
                        issued_in_burst <= 0;
                    end else begin
                        next_addr <= next_addr + 1'b1;
                        if (issued_in_burst == BURST_WORDS - 1) begin
                            active <= 0;
                            issued_in_burst <= 0;
                        end else begin
                            issued_in_burst <= issued_in_burst + 1'b1;
                        end
                    end
                end else if (pending_reads_next == 0) begin
                    next_addr <= 0;
                    restart_done <= 1;
                end
            end else if (!enable) begin
                active <= 0;
                issued_in_burst <= 0;
                next_addr <= 0;
                done <= 0;
                restart_done <= 0;
            end else if (next_addr >= FRAME_WORDS) begin
                active <= 0;
                done <= 1;
                restart_done <= 0;
            end else if (active) begin
                restart_done <= 0;
                app_rd_en <= 1;
                // APUG011 requires the address to be a multiple of 4 (note 5, section 7 of
                // the APUG011 guide): the controller accumulates the four addresses of a
                // group itself, so only the group base may be presented.
                app_rd_addr <= frame_base + {next_addr[20:2], 2'b00};
                if (LOOP_FRAME && next_addr == FRAME_WORDS - 1) begin
                    next_addr <= 0;
                    done <= 1;
                end else begin
                    next_addr <= next_addr + 1'b1;
                end
                if (issued_in_burst == BURST_WORDS - 1) begin
                    active <= 0;
                    issued_in_burst <= 0;
                end else begin
                    issued_in_burst <= issued_in_burst + 1'b1;
                end
            end else if (init_done && !refresh && !busy && !fifo_almost_full && burst_has_room) begin
                restart_done <= 0;
                active <= 1;
                issued_in_burst <= 0;
            end

            case ({app_rd_en, rd_valid})
                2'b10: pending_reads <= pending_reads + 1'b1;
                2'b01: begin
                    if (pending_reads != 0)
                        pending_reads <= pending_reads - 1'b1;
                end
                default: pending_reads <= pending_reads;
            endcase
        end
    end
endmodule
