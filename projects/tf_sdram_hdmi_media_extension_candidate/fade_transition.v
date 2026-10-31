// Fade-to-black transition (selected by the TRANS menu).
// Modes: 0 = CORNERS, 1 = SLIDE, 2 = FADE.
// Only FADE drives this module; for the other modes level stays 0 and
// switch_enable is 1 so the original geometric transition runs normally.
// FADE mode: request -> level 0..6 (black) -> switch_enable=1 lets the frame
// switch run hidden behind the black -> level 6..0 -> idle.
// Outputs are pixel-domain; switch_enable is synchronised to mem_clk in the core.
module fade_transition #(
    parameter integer STEP_FRAMES = 3,
    parameter integer START_TIMEOUT_FRAMES = 30
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       frame_tick,
    input  wire       request_toggle,
    input  wire [1:0] mode,
    input  wire       slide_active,
    output reg  [2:0] level,
    output wire       switch_enable
);
    localparam [2:0] IDLE       = 3'd0;
    localparam [2:0] FADE_OUT   = 3'd1;
    localparam [2:0] WAIT_START = 3'd2;
    localparam [2:0] BLACK_HOLD = 3'd3;
    localparam [2:0] FADE_IN    = 3'd4;

    reg [2:0] state;
    reg [7:0] step_count;
    reg [7:0] timeout_count;
    reg request_seen;
    reg slide_m1, slide_m2;

    // Gate the frame switch only while the picture is still fading out; in
    // every other state (including the timeout recovery) the switch may run.
    assign switch_enable = (mode != 2'd2) || (state != FADE_OUT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            level <= 3'd0;
            step_count <= 8'd0;
            timeout_count <= 8'd0;
            request_seen <= 1'b0;
            slide_m1 <= 1'b0;
            slide_m2 <= 1'b0;
        end else begin
            slide_m1 <= slide_active;
            slide_m2 <= slide_m1;
            request_seen <= request_toggle;
            if (mode != 2'd2) begin
                // Only the FADE mode fades the picture.
                state <= IDLE;
                level <= 3'd0;
                step_count <= 8'd0;
                timeout_count <= 8'd0;
            end else begin
                case (state)
                    IDLE: begin
                        level <= 3'd0;
                        step_count <= 8'd0;
                        timeout_count <= 8'd0;
                        if (request_toggle != request_seen) begin
                            state <= FADE_OUT;
                            step_count <= 8'd0;
                        end
                    end
                    FADE_OUT: begin
                        if (frame_tick) begin
                            if (step_count == STEP_FRAMES - 1) begin
                                step_count <= 8'd0;
                                if (level == 3'd6) begin
                                    state <= WAIT_START;
                                    timeout_count <= 8'd0;
                                end else begin
                                    level <= level + 1'b1;
                                end
                            end else begin
                                step_count <= step_count + 1'b1;
                            end
                        end
                    end
                    WAIT_START: begin
                        if (frame_tick) begin
                            if (slide_m2) begin
                                state <= BLACK_HOLD;
                                timeout_count <= 8'd0;
                            end else if (timeout_count == START_TIMEOUT_FRAMES - 1) begin
                                state <= FADE_IN;
                                step_count <= 8'd0;
                                level <= 3'd6;
                            end else begin
                                timeout_count <= timeout_count + 1'b1;
                            end
                        end
                    end
                    BLACK_HOLD: begin
                        if (frame_tick && !slide_m2) begin
                            state <= FADE_IN;
                            step_count <= 8'd0;
                        end
                    end
                    FADE_IN: begin
                        if (frame_tick) begin
                            if (level == 3'd0) begin
                                state <= IDLE;
                            end else if (step_count == STEP_FRAMES - 1) begin
                                step_count <= 8'd0;
                                level <= level - 1'b1;
                            end else begin
                                step_count <= step_count + 1'b1;
                            end
                        end
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
