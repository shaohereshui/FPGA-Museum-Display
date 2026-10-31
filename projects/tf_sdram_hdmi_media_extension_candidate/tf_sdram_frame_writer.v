// Writes one display-sized frame of 32-bit pixels into the SDRAM through the
// APUG011 application interface.
//
// APUG011 transfers data in groups of four words: the controller latches the address at
// the first beat of a group and derives the next three addresses itself, and the guide
// (section 2.3.4 and note 5 of section 7) states that the user address must therefore be
// a multiple of 4 and that an address may only change once every four clocks. It also
// states that the user should check the refresh flag before starting an operation and
// then run the whole operation, and that Sdr_busy is not used.
//
// A writer that just streams one word per clock and stops whenever the refresh flag
// rises, or whenever the source FIFO is momentarily empty, therefore restarts a group
// at the wrong phase and every following word lands at the wrong address. To keep the
// groups intact, four words are staged in registers first and then presented as one
// uninterrupted group of four beats at a constant group-base address.
module tf_sdram_frame_writer #(
    parameter integer FRAME_WORDS = 307200,
    parameter integer FRAME_WIDTH = 640
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        frame_started,
    input  wire [20:0] frame_base,
    input  wire        top_down,
    input  wire        image_done,
    input  wire        image_error,
    input  wire        fifo_empty,
    output reg         fifo_rd_en,
    input  wire [31:0] fifo_rd_data,
    input  wire        init_done,
    input  wire        refresh,
    input  wire        busy,
    output wire        app_wr_en,
    output wire [20:0] app_wr_addr,
    output wire [31:0] app_wr_data,
    output reg         frame_done,
    output reg         failed,
    output reg  [18:0] write_count
);
    localparam S_IDLE   = 2'd0;
    localparam S_PRIME  = 2'd1;
    localparam S_STREAM = 2'd2;
    localparam S_DONE   = 2'd3;

    reg [1:0]  state;
    reg [20:0] write_addr;
    reg [31:0] grp [0:3];
    reg [1:0]  beat;
    reg [2:0]  fill;
    reg        grp_full;
    reg        emitting;
    reg        rd_capture;

    reg [8:0]  grow;      // row in file/scaler emission order
    reg [9:0]  gx;        // column of the four-word group being emitted

    // Each display row is a multiple of four words. Normalize BMP row orientation
    // without disturbing the APUG011 group alignment.
    wire [20:0] row_offset = grow * FRAME_WIDTH;
    wire [20:0] dest_base = frame_base + gx +
                           (top_down ? row_offset : FRAME_WORDS-FRAME_WIDTH-row_offset);

    // Refresh is checked before a group is started, never during it: once the four beats
    // are running the transfer is completed, exactly as the guide prescribes. Sdr_busy is
    // deliberately not used (the APUG011 guide marks it as unused).
    wire start_ok = init_done && !refresh;

    assign app_wr_en   = emitting;
    assign app_wr_addr = dest_base;
    assign app_wr_data = grp[beat];

    always @(*) begin
        fifo_rd_en = 1'b0;
        if (state == S_STREAM && !grp_full && !rd_capture && !fifo_empty)
            fifo_rd_en = 1'b1;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= S_IDLE;
            write_addr  <= 0;
            beat        <= 0;
            fill        <= 0;
            grow        <= 0;
            gx          <= 0;
            grp_full    <= 0;
            emitting    <= 0;
            rd_capture  <= 0;
            frame_done  <= 0;
            failed      <= 0;
            write_count <= 0;
            grp[0]      <= 0;
            grp[1]      <= 0;
            grp[2]      <= 0;
            grp[3]      <= 0;
        end else begin
            rd_capture <= fifo_rd_en;

            if (image_error) begin
                failed <= 1;
                state <= S_DONE;
                emitting <= 0;
            end

            case (state)
                S_IDLE: begin
                    if (frame_started) begin
                        state       <= S_PRIME;
                        write_addr  <= 0;
                        beat        <= 0;
                        fill        <= 0;
                        grow        <= 0;
                        gx          <= 0;
                        grp_full    <= 0;
                        emitting    <= 0;
                        write_count <= 0;
                        frame_done  <= 0;
                        failed      <= 0;
                    end
                end

                // Wait for the memory controller and the first staged word before
                // starting the frame, then stream whole groups.
                S_PRIME: begin
                    if (start_ok && !fifo_empty)
                        state <= S_STREAM;
                end

                S_STREAM: begin
                    if (rd_capture) begin
                        grp[fill] <= fifo_rd_data;
                        if (fill == 3'd3)
                            grp_full <= 1;
                        else
                            fill <= fill + 3'd1;
                    end

                    if (emitting) begin
                        if (beat == 2'd3) begin
                            emitting   <= 0;
                            beat       <= 0;
                            grp_full   <= 0;
                            fill       <= 0;
                            write_addr <= write_addr + 21'd4;
                            if (gx == FRAME_WIDTH-4) begin
                                gx   <= 0;
                                grow <= grow + 9'd1;
                            end else begin
                                gx <= gx + 10'd4;
                            end
                            if (write_count >= FRAME_WORDS - 4)
                                write_count <= FRAME_WORDS;
                            else
                                write_count <= write_count + 19'd4;
                        end else begin
                            beat <= beat + 2'd1;
                        end
                    end else if (grp_full && start_ok) begin
                        emitting <= 1;
                    end

                    if (image_done && !grp_full && !emitting && fifo_empty &&
                        write_count == FRAME_WORDS[18:0]) begin
                        frame_done <= 1;
                        state      <= S_DONE;
                    end
                end

                S_DONE: begin
                    if (image_error)
                        failed <= 1;
                    else if (frame_started) begin
                        state       <= S_PRIME;
                        write_addr  <= 0;
                        beat        <= 0;
                        fill        <= 0;
                        grow        <= 0;
                        gx          <= 0;
                        grp_full    <= 0;
                        emitting    <= 0;
                        write_count <= 0;
                        frame_done  <= 0;
                        failed      <= 0;
                    end
                end

                default: begin
                    failed <= 1;
                    state  <= S_DONE;
                end
            endcase
        end
    end
endmodule
