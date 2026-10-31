`timescale 1ns / 1ps

// 16-bit stereo LPCM packet builder. Selected subpackets repeat one sample;
// the continuous source uses only subpacket 0, once per queued stereo sample.
module hdmi_audio_sample_packet (
    input  wire [15:0] left_sample,
    input  wire [15:0] right_sample,
    input  wire [7:0]  frame_counter,
    input  wire [3:0]  sample_present,
    output reg  [23:0] header,
    output reg  [55:0] subpacket0,
    output reg  [55:0] subpacket1,
    output reg  [55:0] subpacket2,
    output reg  [55:0] subpacket3
);
    localparam [191:0] CHANNEL_STATUS_LEFT = {
        152'd0,
        4'b0000,
        4'b0010,
        2'b00,
        2'b00,
        4'b0010,
        4'd1,
        4'd0,
        8'h00,
        2'b00,
        3'b000,
        1'b1,
        1'b0,
        1'b0
    };
    localparam [191:0] CHANNEL_STATUS_RIGHT = {
        152'd0,
        4'b0000,
        4'b0010,
        2'b00,
        2'b00,
        4'b0010,
        4'd2,
        4'd0,
        8'h00,
        2'b00,
        3'b000,
        1'b1,
        1'b0,
        1'b0
    };

    function [55:0] make_subpacket;
        input [23:0] left_word;
        input [23:0] right_word;
        input [7:0]  status_index;
        reg left_status;
        reg right_status;
        reg left_parity;
        reg right_parity;
        begin
            left_status  = CHANNEL_STATUS_LEFT[status_index];
            right_status = CHANNEL_STATUS_RIGHT[status_index];
            left_parity  = ^{left_status, 1'b0, 1'b0, left_word};
            right_parity = ^{right_status, 1'b0, 1'b0, right_word};
            make_subpacket = {
                right_parity, right_status, 1'b0, 1'b0,
                left_parity,  left_status,  1'b0, 1'b0,
                right_word, left_word
            };
        end
    endfunction

    function [7:0] wrap_frame;
        input [8:0] count;
        begin
            wrap_frame = count >= 9'd192 ? count - 9'd192 : count;
        end
    endfunction

    // The caller supplies the first subpacket's frame index in 0..191.
    wire [7:0] index0 = frame_counter;
    wire [7:0] index1 = wrap_frame({1'b0, frame_counter} + 9'd1);
    wire [7:0] index2 = wrap_frame({1'b0, frame_counter} + 9'd2);
    wire [7:0] index3 = wrap_frame({1'b0, frame_counter} + 9'd3);

    always @* begin
        header = 24'h000002;
        header[11:8] = sample_present;
        header[23:20] = {index3 == 0, index2 == 0, index1 == 0, index0 == 0} & sample_present;

        subpacket0 = sample_present[0] ? make_subpacket(
            {left_sample, 8'h00}, {right_sample, 8'h00}, index0
        ) : 56'd0;
        subpacket1 = sample_present[1] ? make_subpacket(
            {left_sample, 8'h00}, {right_sample, 8'h00}, index1
        ) : 56'd0;
        subpacket2 = sample_present[2] ? make_subpacket(
            {left_sample, 8'h00}, {right_sample, 8'h00}, index2
        ) : 56'd0;
        subpacket3 = sample_present[3] ? make_subpacket(
            {left_sample, 8'h00}, {right_sample, 8'h00}, index3
        ) : 56'd0;
    end
endmodule
