`timescale 1ns / 1ps

// 48 kHz stereo ACR and RGB AVI profile for the selected pixel clock/mode.
// 1 = ACR, 2 = Audio InfoFrame, 3 = AVI InfoFrame; PCM is built separately.
module hdmi_metadata_packets #(
    parameter integer PIXEL_HZ = 25000000,
    parameter integer VIC = 0,
    parameter [7:0] ASPECT = 8'h10
) (
    input  wire [1:0]  packet_kind,
    output reg  [23:0] header,
    output reg  [55:0] subpacket0,
    output reg  [55:0] subpacket1,
    output reg  [55:0] subpacket2,
    output reg  [55:0] subpacket3
);
    localparam [19:0] N = 20'd6144;
    localparam [19:0] CTS = PIXEL_HZ/1000;
    localparam [7:0] AVI_VIC = VIC;
    localparam [55:0] ACR_BODY = {
        N[7:0], N[15:8], 4'd0, N[19:16],
        CTS[7:0], CTS[15:8], 4'd0, CTS[19:16], 8'd0
    };
    localparam [7:0] AUDIO_CHECKSUM = 8'd0 - 8'h84 - 8'h01 - 8'h0A - 8'h01;
    localparam [7:0] AVI_CHECKSUM = 8'd0 - 8'h82 - 8'h02 - 8'h0D - ASPECT - AVI_VIC;

    always @* begin
        subpacket1 = 0;
        subpacket2 = 0;
        subpacket3 = 0;
        case (packet_kind)
            2'd1: begin
                header = 24'h000001;
                subpacket0 = ACR_BODY;
                subpacket1 = ACR_BODY;
                subpacket2 = ACR_BODY;
                subpacket3 = ACR_BODY;
            end
            2'd2: begin
                header = 24'h0A0184;
                // PB1: two channels, coding type follows the stream.
                // PB2: frequency and sample size also follow the stream.
                subpacket0 = {40'd0, 8'h01, AUDIO_CHECKSUM};
            end
            2'd3: begin
                header = 24'h0D0282;
                // RGB, explicit picture aspect/VIC, no pixel repetition.
                subpacket0 = {16'd0, AVI_VIC, 8'd0, ASPECT, 8'h00, AVI_CHECKSUM};
            end
            default: begin
                // No metadata packet is defined for the PCM selector.
                header = 24'hxxxxxx;
                subpacket0 = 56'hxxxxxxxxxxxxxx;
                subpacket1 = 56'hxxxxxxxxxxxxxx;
                subpacket2 = 56'hxxxxxxxxxxxxxx;
                subpacket3 = 56'hxxxxxxxxxxxxxx;
            end
        endcase
    end
endmodule
