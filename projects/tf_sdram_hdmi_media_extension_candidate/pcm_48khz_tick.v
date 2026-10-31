`timescale 1ns / 1ps

module pcm_48khz_tick #(
    parameter integer PIXEL_HZ = 25000000,
    parameter integer AUDIO_HZ = 48000
) (
    input  wire clk,
    input  wire rst,
    output reg  sample_tick
);
    reg [31:0] phase;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            phase       <= 32'd0;
            sample_tick <= 1'b0;
        end else if (phase >= PIXEL_HZ - AUDIO_HZ) begin
            phase       <= phase + AUDIO_HZ - PIXEL_HZ;
            sample_tick <= 1'b1;
        end else begin
            phase       <= phase + AUDIO_HZ;
            sample_tick <= 1'b0;
        end
    end
endmodule
