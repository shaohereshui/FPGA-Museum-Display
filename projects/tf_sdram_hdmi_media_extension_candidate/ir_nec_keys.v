// Standard NEC receiver, synchronized input, validated full/short-repeat frames.
// A shared hold timer keeps virtual keys down across NEC repeat frames. Toggle
// actions fire once per press, including remotes that repeat full NEC frames.
module ir_nec_keys #(
    parameter integer CLK_HZ = 27_000_000,
    parameter integer HOLD_CYCLES = 4_050_000, // release after 150 ms silence
    parameter integer FILTER_US = 5
) (
    input wire clk, rst_n, ir_rx,
    input wire emergency_clear,
    output wire [15:0] keys_down,
    output wire activity,
    output reg emergency_active,
    output wire diag_line,
    output reg [15:0] diag_raw_edges, diag_drops,
    output reg [15:0] diag_edges, diag_frames, diag_valid, diag_keys,
    output reg [31:0] diag_raw,
    output reg [15:0] diag_header_high, diag_first_low, diag_first_high, diag_fail_us,
    output reg [3:0] diag_fail,
    output reg [5:0] diag_fail_bit,
    output reg [31:0] diag_partial,
    output reg [15:0] diag_lead_us
);
`include "ir_remote_map.vh"
    localparam integer US = CLK_HZ / 1_000_000;
    localparam integer TIMER_WIDTH = $clog2(12000 * US + 1);
    localparam integer HOLD_WIDTH = $clog2(HOLD_CYCLES + 1);
    localparam [2:0] IDLE=0, LEAD_LOW=1, LEAD_HIGH=2,
                     BIT_LOW=3, BIT_HIGH=4, STOP_LOW=5, REPEAT_LOW=6;
    reg ir_meta, ir_raw;
    reg ir_filtered, raw_prev;
    wire ir_sync=ir_filtered;
    localparam integer FILTER_CYCLES=FILTER_US*US;
    localparam integer FILTER_WIDTH=(FILTER_CYCLES<2)?1:$clog2(FILTER_CYCLES+1);
    reg [FILTER_WIDTH-1:0] filter_count;
    reg [2:0] state;
    reg [TIMER_WIDTH-1:0] timer;
    // Receive pulse stretching can move a rising edge by hundreds of us.
    // Classify falling-to-falling bit periods, while bounding both levels.
    localparam integer MARK_MIN=120*US, MARK_MAX=1400*US;
    localparam integer SPACE_MIN=80*US, SPACE_MAX=2500*US;
    localparam integer ZERO_MIN=850*US, ZERO_MAX=1450*US;
    localparam integer ONE_MIN=1700*US, ONE_MAX=2700*US;
    reg [TIMER_WIDTH-1:0] mark_ticks;
    wire [TIMER_WIDTH:0] bit_ticks={1'b0,mark_ticks}+{1'b0,timer};
    wire zero_period=(bit_ticks>=ZERO_MIN && bit_ticks<=ZERO_MAX);
    wire one_period=(bit_ticks>=ONE_MIN && bit_ticks<=ONE_MAX);
    wire data_period_valid=(timer>=SPACE_MIN && timer<=SPACE_MAX && (zero_period || one_period));
    reg [5:0] bit_index;
    reg [31:0] frame;
    reg frame_valid, repeat_valid;
    reg [7:0] command;
    reg [7:0] last_command;
    reg [16:0] active_mask;
    reg [HOLD_WIDTH-1:0] hold_count;

    // Low 16 bits use the physical 4x4 keypad's row-major numbering;
    // bit 16 is exclusively the IR emergency toggle, never a matrix key.
    function [16:0] decode;
        input [7:0] cmd;
        begin
            decode=0;
            case(cmd)
                CMD_UP, CMD_2: decode[1]=1;       // matrix 2
                CMD_DOWN, CMD_8: decode[9]=1;     // matrix 8
                CMD_LEFT, CMD_4: decode[4]=1;     // matrix 4
                CMD_RIGHT, CMD_6: decode[6]=1;    // matrix 6
                CMD_OK: decode[14]=1;             // matrix #
                CMD_5: decode[5]=1;               // menu
                CMD_STAR: decode[12]=1;           // back
                CMD_0: decode[13]=1;              // shared play/pause
                CMD_3: decode[2]=1;               // shared zoom enable
                CMD_1: decode[3]=1;               // matrix A: zoom in
                CMD_7: decode[11]=1;              // matrix C: zoom out
                CMD_HASH: decode[7]=1;            // matrix B: visualizer
                CMD_9: decode[16]=1;              // IR-only emergency
                default: decode=0;
            endcase
        end
    endfunction
    wire [16:0] decoded_mask = decode(command);
    assign keys_down = (hold_count != 0) ? active_mask[15:0] : 16'd0;
    assign activity = (hold_count != 0) || frame_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ir_meta<=1; ir_raw<=1; end
        else begin ir_meta<=ir_rx; ir_raw<=ir_meta; end
    end

    // Stable-level filter after the two-stage synchronizer. Both polarities
    // have equal delay. Only brief excursions are suppressed; protocol timing
    // windows, address and complement validation remain unchanged.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir_filtered<=1; filter_count<=0; raw_prev<=1;
            diag_raw_edges<=0; diag_drops<=0;
        end else begin
            raw_prev<=ir_raw;
            if (ir_raw!=raw_prev) diag_raw_edges<=diag_raw_edges+1'b1;
            if (ir_raw==ir_filtered) begin
                if (filter_count!=0) diag_drops<=diag_drops+1'b1;
                filter_count<=0;
            end else if (filter_count==FILTER_CYCLES-1) begin
                ir_filtered<=ir_raw; filter_count<=0;
            end else filter_count<=filter_count+1'b1;
        end
    end

    // Standard NEC ends with an extra 560 us low mark. Wait for it to finish:
    // never accept an unterminated last bit merely because the line stays high.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; timer<=0; bit_index<=0; frame<=0; mark_ticks<=0;
            command<=0; frame_valid<=0; repeat_valid<=0;
        end else begin
            frame_valid<=0; repeat_valid<=0;
            case(state)
                IDLE: begin
                    timer<=0;
                    if (!ir_sync) begin state<=LEAD_LOW; timer<=1; end
                end
                LEAD_LOW: begin
                    if (ir_sync) begin
                        timer<=1;
                        if (timer>=7000*US && timer<=11000*US) state<=LEAD_HIGH;
                        else state<=IDLE;
                    end else if (timer>=11000*US) state<=IDLE;
                    else timer<=timer+1'b1;
                end
                LEAD_HIGH: begin
                    if (!ir_sync) begin
                        timer<=1;
                        if (timer>=3500*US && timer<=5500*US) begin
                            state<=BIT_LOW; bit_index<=0; frame<=0;
                        end else if (timer>=1800*US && timer<=2800*US)
                            state<=REPEAT_LOW;
                        else state<=IDLE;
                    end else if (timer>=5500*US) state<=IDLE;
                    else timer<=timer+1'b1;
                end
                BIT_LOW: begin
                    if (ir_sync) begin
                        timer<=1;
                        mark_ticks<=timer;
                        if (timer>=MARK_MIN && timer<=MARK_MAX) state<=BIT_HIGH;
                        else state<=IDLE;
                    end else if (timer>=MARK_MAX) state<=IDLE;
                    else timer<=timer+1'b1;
                end
                BIT_HIGH: begin
                    if (!ir_sync) begin
                        timer<=1;
                        if (data_period_valid) begin
                            frame[bit_index] <= one_period;
                            if (bit_index==31) state<=STOP_LOW;
                            else begin bit_index<=bit_index+1'b1; state<=BIT_LOW; end
                        end else state<=IDLE;
                    end else if ((timer>=SPACE_MAX || bit_ticks>=ONE_MAX)) state<=IDLE;
                    else timer<=timer+1'b1;
                end
                STOP_LOW: begin
                    if (ir_sync) begin
                        if (timer>=MARK_MIN && timer<=MARK_MAX &&
                            frame[7:0]==REMOTE_ADDRESS &&
                            frame[7:0]==~frame[15:8] && frame[23:16]==~frame[31:24]) begin
                            command<=frame[23:16]; frame_valid<=1;
                        end
                        state<=IDLE;
                    end else if (timer>=MARK_MAX) state<=IDLE;
                    else timer<=timer+1'b1;
                end
                REPEAT_LOW: begin
                    if (ir_sync) begin
                        if (timer>=MARK_MIN && timer<=MARK_MAX) repeat_valid<=1;
                        state<=IDLE;
                    end else if (timer>=MARK_MAX) state<=IDLE;
                    else timer<=timer+1'b1;
                end
                default: state<=IDLE;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_count<=0; active_mask<=0; last_command<=0; emergency_active<=0;
        end else begin
            if (hold_count!=0) hold_count<=hold_count-1'b1;
            if (frame_valid) begin
                active_mask<=decoded_mask;
                last_command<=command;
                if (decoded_mask!=0) begin
                    hold_count<=HOLD_CYCLES;
                    if (decoded_mask[16] && (hold_count==0 || command!=last_command))
                        emergency_active<=!emergency_active;
                end else hold_count<=0;
            end else if (repeat_valid && hold_count!=0) begin
                hold_count<=HOLD_CYCLES;
            end
            if (emergency_clear) emergency_active <= 1'b0;
        end
    end

    assign diag_line = ir_sync;
    reg prev_line;
    reg [7:0] us_div;
    reg [15:0] low_us;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_line<=1; diag_edges<=0; diag_frames<=0; diag_valid<=0;
            diag_keys<=0; diag_raw<=0; diag_lead_us<=0; us_div<=0; low_us<=0;
        end else begin
            prev_line<=ir_sync;
            if (ir_sync != prev_line) diag_edges<=diag_edges+1'b1;
            if (ir_sync) begin
                if (!prev_line && low_us>=2000) diag_lead_us<=low_us;
                us_div<=0; low_us<=0;
            end else if (us_div==US-1) begin
                us_div<=0;
                if (low_us!=16'hffff) low_us<=low_us+1'b1;
            end else us_div<=us_div+1'b1;
            // Count complete timing-valid frames even if address/checksum fail.
            if (state==STOP_LOW && ir_sync && timer>=MARK_MIN && timer<=MARK_MAX) begin
                diag_frames<=diag_frames+1'b1; diag_raw<=frame;
            end
            if (frame_valid) begin
                diag_valid<=diag_valid+1'b1;
                diag_keys<=decoded_mask[15:0];
            end
        end
    end

    // Observe the released state machine without changing acceptance or keys.
    // Latch its FIRST timing failure until reset; later noise cannot overwrite it.
    reg [3:0] fail_now;
    always @* begin
        fail_now=0;
        case(state)
            LEAD_HIGH: if (!ir_sync) begin
                if (!((timer>=3500*US && timer<=5500*US) ||
                      (timer>=1800*US && timer<=2800*US))) fail_now=1;
            end else if (timer>=5500*US) fail_now=2;
            BIT_LOW: if (ir_sync) begin
                if (!(timer>=MARK_MIN && timer<=MARK_MAX)) fail_now=3;
            end else if (timer>=MARK_MAX) fail_now=4;
            BIT_HIGH: if (!ir_sync) begin
                if (!data_period_valid) fail_now=5;
            end else if ((timer>=SPACE_MAX || bit_ticks>=ONE_MAX)) fail_now=6;
            STOP_LOW: if (ir_sync) begin
                if (!(timer>=MARK_MIN && timer<=MARK_MAX)) fail_now=7;
            end else if (timer>=MARK_MAX) fail_now=8;
            REPEAT_LOW: if (ir_sync) begin
                if (!(timer>=MARK_MIN && timer<=MARK_MAX)) fail_now=9;
            end else if (timer>=MARK_MAX) fail_now=10;
            default: fail_now=0;
        endcase
    end
    // Independent pulse measurement continues even after the decoder times out.
    // First leader's following high, first data low/high are captured once.
    reg [2:0] pulse_phase;
    reg [7:0] high_div;
    reg [15:0] high_us;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diag_fail<=0; diag_fail_bit<=0; diag_fail_us<=0; diag_partial<=0;
            diag_header_high<=0; diag_first_low<=0; diag_first_high<=0;
            pulse_phase<=0; high_div<=0; high_us<=0;
        end else begin
            if (diag_fail==0 && fail_now!=0) begin
                diag_fail<=fail_now; diag_fail_us<=timer/US;
                diag_fail_bit<=(state==LEAD_HIGH)?6'd0:bit_index;
                diag_partial<=frame;
            end
            if (!ir_sync) begin high_div<=0; high_us<=0; end
            else if (high_div==US-1) begin
                high_div<=0;
                if (high_us!=16'hffff) high_us<=high_us+1'b1;
            end else high_div<=high_div+1'b1;
            case(pulse_phase)
                0: if (ir_sync && !prev_line && low_us>=7000 && low_us<=11000)
                    pulse_phase<=1;
                1: if (!ir_sync && prev_line) begin
                    diag_header_high<=high_us; pulse_phase<=2;
                end
                2: if (ir_sync && !prev_line) begin
                    diag_first_low<=low_us; pulse_phase<=3;
                end
                3: if (!ir_sync && prev_line) begin
                    diag_first_high<=high_us; pulse_phase<=4;
                end
                default: pulse_phase<=pulse_phase;
            endcase
        end
    end
endmodule
