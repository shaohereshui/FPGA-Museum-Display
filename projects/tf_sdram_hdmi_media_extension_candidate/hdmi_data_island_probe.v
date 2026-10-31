`timescale 1ns / 1ps

// Isolated 25 MHz data-island timing probe.
// A transaction has eight preamble pixels, two leading guard pixels,
// thirty-two packet pixels, and two trailing guard pixels.
// The caller schedules it inside blanking, away from horizontal position 0.
module hdmi_data_island_probe #(
    parameter integer PIXEL_HZ = 25000000,
    parameter integer VIC = 0,
    parameter [7:0] ASPECT = 8'h10
) (
    input  wire       pixel_clk,
    input  wire       rst,
    input  wire       packet_start,
    input  wire [1:0] packet_kind,
    input  wire [3:0] sample_present,
    input  wire       hsync,
    input  wire       vsync,
    input  wire [15:0] left_sample,
    input  wire [15:0] right_sample,
    input  wire [7:0] frame_counter,
    output reg        island_active,
    output reg        leading_guard,
    output reg        preamble,
    output reg        packet,
    output reg        trailing_guard,
    output reg        packet_done,
    output reg [5:0]  packet_word_index,
    output reg [1:0]  control_ch0,
    output reg [1:0]  control_ch1,
    output reg [1:0]  control_ch2,
    output reg [3:0]  data_nibble_ch0,
    output reg [3:0]  data_nibble_ch1,
    output reg [3:0]  data_nibble_ch2,
    output reg [9:0]  tmds_ch0,
    output reg [9:0]  tmds_ch1,
    output reg [9:0]  tmds_ch2,
    output wire [8:0] packet_data,
    output wire [23:0] packet_header
);
    localparam [2:0] S_IDLE  = 3'd0;
    localparam [2:0] S_LEAD  = 3'd1;
    localparam [2:0] S_PRE   = 3'd2;
    localparam [2:0] S_DATA  = 3'd3;
    localparam [2:0] S_TRAIL = 3'd4;

    reg [2:0] state;
    reg [5:0] state_count;
    reg       hsync_latched;
    reg       vsync_latched;
    reg [15:0] left_latched;
    reg [15:0] right_latched;
    reg [7:0] frame_counter_latched;
    reg [1:0] packet_kind_latched;
    reg [3:0] sample_present_latched;
    wire [23:0] sample_header, metadata_header;
    wire [55:0] sample_sub0, sample_sub1, sample_sub2, sample_sub3;
    wire [55:0] metadata_sub0, metadata_sub1, metadata_sub2, metadata_sub3;
    wire [55:0] packet_subpacket0;
    wire [55:0] packet_subpacket1;
    wire [55:0] packet_subpacket2;
    wire [55:0] packet_subpacket3;
    wire [3:0] guard_nibble_ch0 = {
        2'b11, vsync_latched, hsync_latched
    };
    wire [3:0] packet_nibble_ch0 = {
        1'b1, packet_data[0],
        vsync_latched, hsync_latched
    };
    wire [9:0] terc4_ch0_data;
    wire [9:0] terc4_ch1_data;
    wire [9:0] terc4_ch2_data;
    wire [9:0] terc4_guard_ch0;

    hdmi_audio_sample_packet sample_packet (
        .left_sample(left_latched),
        .right_sample(right_latched),
        .frame_counter(frame_counter_latched),
        .sample_present(sample_present_latched),
        .header(sample_header),
        .subpacket0(sample_sub0), .subpacket1(sample_sub1),
        .subpacket2(sample_sub2), .subpacket3(sample_sub3)
    );

    hdmi_metadata_packets #(.PIXEL_HZ(PIXEL_HZ), .VIC(VIC), .ASPECT(ASPECT)) metadata_packet (
        .packet_kind(packet_kind_latched), .header(metadata_header),
        .subpacket0(metadata_sub0), .subpacket1(metadata_sub1),
        .subpacket2(metadata_sub2), .subpacket3(metadata_sub3)
    );
    assign packet_header = packet_kind_latched == 0 ? sample_header : metadata_header;
    assign packet_subpacket0 = packet_kind_latched == 0 ? sample_sub0 : metadata_sub0;
    assign packet_subpacket1 = packet_kind_latched == 0 ? sample_sub1 : metadata_sub1;
    assign packet_subpacket2 = packet_kind_latched == 0 ? sample_sub2 : metadata_sub2;
    assign packet_subpacket3 = packet_kind_latched == 0 ? sample_sub3 : metadata_sub3;

    hdmi_audio_packet_assembler packet_assembler (
        .header(packet_header),
        .subpacket0(packet_subpacket0),
        .subpacket1(packet_subpacket1),
        .subpacket2(packet_subpacket2),
        .subpacket3(packet_subpacket3),
        .word_index(state_count[4:0]),
        .packet_data(packet_data)
    );

    hdmi_terc4_encoder terc4_ch0 (
        .data(data_nibble_ch0), .code(terc4_ch0_data)
    );
    hdmi_terc4_encoder terc4_ch1 (
        .data(data_nibble_ch1), .code(terc4_ch1_data)
    );
    hdmi_terc4_encoder terc4_ch2 (
        .data(data_nibble_ch2), .code(terc4_ch2_data)
    );
    hdmi_terc4_encoder terc4_guard_ch0_inst (
        .data(guard_nibble_ch0), .code(terc4_guard_ch0)
    );

    function [9:0] control_code;
        input [1:0] control;
        begin
            case (control)
                2'b00: control_code = 10'b1101010100;
                2'b01: control_code = 10'b0010101011;
                2'b10: control_code = 10'b0101010100;
                default: control_code = 10'b1010101011;
            endcase
        end
    endfunction

    always @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            state                  <= S_IDLE;
            state_count            <= 6'd0;
            hsync_latched          <= 1'b0;
            vsync_latched           <= 1'b0;
            left_latched            <= 16'd0;
            right_latched           <= 16'd0;
            frame_counter_latched   <= 8'd0;
            packet_kind_latched     <= 2'd0;
            sample_present_latched  <= 4'd0;
        end else begin
            hsync_latched <= hsync;
            vsync_latched <= vsync;
            case (state)
                S_IDLE: begin
                    if (packet_start) begin
                        state                <= S_PRE;
                        state_count          <= 6'd0;
                        packet_kind_latched   <= packet_kind;
                        sample_present_latched <= sample_present;
                        left_latched          <= left_sample;
                        right_latched         <= right_sample;
                        frame_counter_latched <= frame_counter;
                    end
                end
                S_LEAD: begin
                    if (state_count == 6'd1) begin
                        state       <= S_DATA;
                        state_count <= 6'd0;
                    end else begin
                        state_count <= state_count + 6'd1;
                    end
                end
                S_PRE: begin
                    if (state_count == 6'd7) begin
                        state       <= S_LEAD;
                        state_count <= 6'd0;
                    end else begin
                        state_count <= state_count + 6'd1;
                    end
                end
                S_DATA: begin
                    if (state_count == 6'd31) begin
                        state       <= S_TRAIL;
                        state_count <= 6'd0;
                    end else begin
                        state_count <= state_count + 6'd1;
                    end
                end
                default: begin
                    if (state_count == 6'd1) begin
                        state       <= S_IDLE;
                        state_count <= 6'd0;
                    end else begin
                        state_count <= state_count + 6'd1;
                    end
                end
            endcase
        end
    end

    always @* begin
        island_active     = state != S_IDLE;
        leading_guard     = state == S_LEAD;
        preamble          = state == S_PRE;
        packet            = state == S_DATA;
        trailing_guard    = state == S_TRAIL;
        packet_done       = state == S_TRAIL && state_count == 6'd1;
        packet_word_index = state == S_DATA ? state_count : 6'd0;

        control_ch0 = {vsync_latched, hsync_latched};
        control_ch1 = state == S_PRE ? 2'b01 : 2'b00;
        control_ch2 = state == S_PRE ? 2'b01 : 2'b00;
        data_nibble_ch0 = packet_nibble_ch0;
        data_nibble_ch1 = packet_data[4:1];
        data_nibble_ch2 = packet_data[8:5];

        if (state == S_LEAD || state == S_TRAIL) begin
            tmds_ch0 = terc4_guard_ch0;
            tmds_ch1 = 10'b0100110011;
            tmds_ch2 = 10'b0100110011;
        end else if (state == S_DATA) begin
            tmds_ch0 = terc4_ch0_data;
            tmds_ch1 = terc4_ch1_data;
            tmds_ch2 = terc4_ch2_data;
        end else begin
            tmds_ch0 = control_code(control_ch0);
            tmds_ch1 = control_code(control_ch1);
            tmds_ch2 = control_code(control_ch2);
        end
    end
endmodule
