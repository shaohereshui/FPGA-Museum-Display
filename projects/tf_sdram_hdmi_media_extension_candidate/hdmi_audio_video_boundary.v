`timescale 1ns / 1ps

// Audio-only HDMI boundary for the accepted SDRAM video pipeline.
// Video TMDS words are produced by the copied integration core; this module
// only schedules PCM metadata/data islands and selects the final channel words.
module hdmi_audio_video_boundary #(
    parameter integer VIDEO_PIPELINE_OFFSET = 0,
    parameter integer H_ACTIVE = 640,
    parameter integer H_TOTAL = 800,
    parameter integer V_ACTIVE = 480,
    parameter integer V_TOTAL = 525,
    parameter integer PIXEL_HZ = 25000000,
    parameter integer VIC = 0,
    parameter [7:0] ASPECT = 8'h10
) (
    input  wire        pixel_clk,
    input  wire        rst,
    input  wire [9:0]  h_count,
    input  wire [9:0]  v_count,
    input  wire        hsync,
    input  wire        vsync,
    input  wire        de,
    input  wire [9:0]  video_tmds_ch0,
    input  wire [9:0]  video_tmds_ch1,
    input  wire [9:0]  video_tmds_ch2,
    input  wire        sample_valid,
    input  wire [15:0] left_sample,
    input  wire [15:0] right_sample,
    output wire [9:0]  tmds_ch0,
    output wire [9:0]  tmds_ch1,
    output wire [9:0]  tmds_ch2,
    output reg  [4:0]  fifo_level,
    output reg         overflow
);
    (* ram_style = "none" *) reg [31:0] pcm_queue [0:15];
    reg [3:0] read_ptr, write_ptr;
    reg [7:0] frame_counter;
    reg [5:0] acr_sample_count;
    reg acr_pending, audio_pending, avi_pending;
    wire island_active;
    wire [1:0] packet_kind = acr_pending ? 2'd1 :
                              audio_pending ? 2'd2 : avi_pending ? 2'd3 : 2'd0;
    wire packet_start = (h_count == H_ACTIVE+20 || h_count == H_ACTIVE+80) && !de && !island_active &&
                        (acr_pending || audio_pending || avi_pending || fifo_level != 0);
    wire pop_sample = packet_start && packet_kind == 0;
    wire push_sample = sample_valid && (fifo_level < 16 || pop_sample);
    wire next_line_active = v_count < V_ACTIVE-1 || v_count == V_TOTAL-1;
    wire signed [10:0] video_h_count = $signed({1'b0, h_count}) - VIDEO_PIPELINE_OFFSET;
    wire video_h_count_valid = (video_h_count >= 11'sd0) &&
                                (video_h_count < H_TOTAL);
    // Window values are the ones used by the board-verified hdmi_audio_tone_nocomp_candidate:
    // eight preamble pixels 790..797 followed by two guard pixels 798..799. The phase
    // reference `h_count` is the same two-stage raster tap that feeds the registered
    // encoders, whose words are one pixel clock later again, so both marker windows must
    // be registered before they are substituted into the encoded words. Registering only
    // the guard leaves the preamble one pixel early with a plain control word on 797,
    // which breaks the preamble-to-guard contiguity the sink looks for.
    wire video_preamble = next_line_active && video_h_count_valid &&
                          video_h_count >= H_TOTAL-10 && video_h_count < H_TOTAL-2;
    wire video_guard_next = next_line_active && video_h_count_valid &&
                            video_h_count >= H_TOTAL-2 && video_h_count < H_TOTAL;
    reg video_preamble_r;
    reg video_guard;
    wire [9:0] island0, island1, island2;

    always @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            read_ptr <= 0;
            write_ptr <= 0;
            fifo_level <= 0;
            overflow <= 0;
            frame_counter <= 0;
            acr_sample_count <= 0;
            acr_pending <= 1;
            audio_pending <= 1;
            avi_pending <= 1;
            video_preamble_r <= 0;
            video_guard <= 0;
        end else begin
            video_preamble_r <= video_preamble;
            video_guard <= video_guard_next;
            if (sample_valid && !push_sample)
                overflow <= 1;
            if (push_sample) begin
                pcm_queue[write_ptr] <= {right_sample, left_sample};
                write_ptr <= write_ptr + 1'b1;
            end
            if (pop_sample) begin
                read_ptr <= read_ptr + 1'b1;
                frame_counter <= frame_counter == 191 ? 0 : frame_counter + 1'b1;
            end
            case ({push_sample, pop_sample})
                2'b10: fifo_level <= fifo_level + 1'b1;
                2'b01: fifo_level <= fifo_level - 1'b1;
                default: begin end
            endcase
            if (packet_start) begin
                case (packet_kind)
                    1: acr_pending <= 0;
                    2: audio_pending <= 0;
                    3: avi_pending <= 0;
                    default: begin end
                endcase
            end
            if (h_count == 0 && v_count == 0) begin
                audio_pending <= 1;
                avi_pending <= 1;
            end
            if (sample_valid) begin
                if (acr_sample_count == 47) begin
                    acr_sample_count <= 0;
                    acr_pending <= 1;
                end else begin
                    acr_sample_count <= acr_sample_count + 1'b1;
                end
            end
        end
    end

    hdmi_data_island_probe #(.PIXEL_HZ(PIXEL_HZ), .VIC(VIC), .ASPECT(ASPECT)) island (
        .pixel_clk(pixel_clk), .rst(rst), .packet_start(packet_start),
        .packet_kind(packet_kind), .sample_present(4'b0001),
        .hsync(hsync), .vsync(vsync),
        .left_sample(pcm_queue[read_ptr][15:0]),
        .right_sample(pcm_queue[read_ptr][31:16]),
        .frame_counter(frame_counter), .island_active(island_active),
        .tmds_ch0(island0), .tmds_ch1(island1), .tmds_ch2(island2),
        .leading_guard(), .preamble(), .packet(), .trailing_guard(),
        .packet_done(), .packet_word_index(), .control_ch0(), .control_ch1(),
        .control_ch2(), .data_nibble_ch0(), .data_nibble_ch1(),
        .data_nibble_ch2(), .packet_data(), .packet_header()
    );

    assign tmds_ch0 = island_active ? island0 : video_guard ? 10'b1011001100 : video_tmds_ch0;
    assign tmds_ch1 = island_active ? island1 : video_guard ? 10'b0100110011 : video_preamble_r ? 10'b0010101011 : video_tmds_ch1;
    assign tmds_ch2 = island_active ? island2 : video_guard ? 10'b1011001100 : video_tmds_ch2;
endmodule
