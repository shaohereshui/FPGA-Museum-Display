`timescale 1ns / 1ps

// BCH-8 extension and the nine packet bits carried by one data-island pixel.
// The bit ordering follows the packet assembler used by the reference HDMI
// implementation: channel 0 carries one header BCH bit and channels 1/2 carry
// even/odd BCH bits from the four 64-bit subpackets.
module hdmi_audio_packet_assembler (
    input  wire [23:0] header,
    input  wire [55:0] subpacket0,
    input  wire [55:0] subpacket1,
    input  wire [55:0] subpacket2,
    input  wire [55:0] subpacket3,
    input  wire [4:0]  word_index,
    output reg  [8:0]  packet_data
);
    reg [31:0] header_bch;
    reg [63:0] subpacket0_bch;
    reg [63:0] subpacket1_bch;
    reg [63:0] subpacket2_bch;
    reg [63:0] subpacket3_bch;
    reg [7:0] header_ecc;
    reg [7:0] subpacket0_ecc;
    reg [7:0] subpacket1_ecc;
    reg [7:0] subpacket2_ecc;
    reg [7:0] subpacket3_ecc;
    reg [5:0] bit_index;

    function [7:0] bch_next;
        input [7:0] ecc;
        input       data_bit;
        begin
            bch_next = (ecc >> 1) ^ ((ecc[0] ^ data_bit) ? 8'h83 : 8'h00);
        end
    endfunction

    function [7:0] bch24;
        input [23:0] data;
        integer i;
        reg [7:0] ecc;
        begin
            ecc = 8'h00;
            for (i = 0; i < 24; i = i + 1)
                ecc = bch_next(ecc, data[i]);
            bch24 = ecc;
        end
    endfunction

    function [7:0] bch56;
        input [55:0] data;
        integer i;
        reg [7:0] ecc;
        begin
            ecc = 8'h00;
            for (i = 0; i < 56; i = i + 1)
                ecc = bch_next(ecc, data[i]);
            bch56 = ecc;
        end
    endfunction

    always @* begin
        header_ecc    = bch24(header);
        subpacket0_ecc = bch56(subpacket0);
        subpacket1_ecc = bch56(subpacket1);
        subpacket2_ecc = bch56(subpacket2);
        subpacket3_ecc = bch56(subpacket3);

        header_bch    = {header_ecc, header};
        subpacket0_bch = {subpacket0_ecc, subpacket0};
        subpacket1_bch = {subpacket1_ecc, subpacket1};
        subpacket2_bch = {subpacket2_ecc, subpacket2};
        subpacket3_bch = {subpacket3_ecc, subpacket3};

        bit_index = {word_index, 1'b0};
        packet_data[8] = subpacket3_bch[bit_index + 6'd1];
        packet_data[7] = subpacket2_bch[bit_index + 6'd1];
        packet_data[6] = subpacket1_bch[bit_index + 6'd1];
        packet_data[5] = subpacket0_bch[bit_index + 6'd1];
        packet_data[4] = subpacket3_bch[bit_index];
        packet_data[3] = subpacket2_bch[bit_index];
        packet_data[2] = subpacket1_bch[bit_index];
        packet_data[1] = subpacket0_bch[bit_index];
        packet_data[0] = header_bch[word_index];
    end
endmodule
