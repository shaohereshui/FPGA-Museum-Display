`timescale 1ns / 1ps

module hdmi_terc4_encoder (
    input  wire [3:0] data,
    output reg  [9:0] code
);
    always @* begin
        case (data)
            4'h0: code = 10'b1010011100;
            4'h1: code = 10'b1001100011;
            4'h2: code = 10'b1011100100;
            4'h3: code = 10'b1011100010;
            4'h4: code = 10'b0101110001;
            4'h5: code = 10'b0100011110;
            4'h6: code = 10'b0110001110;
            4'h7: code = 10'b0100111100;
            4'h8: code = 10'b1011001100;
            4'h9: code = 10'b0100111001;
            4'hA: code = 10'b0110011100;
            4'hB: code = 10'b1011000110;
            4'hC: code = 10'b1010001110;
            4'hD: code = 10'b1001110001;
            4'hE: code = 10'b0101100011;
            default: code = 10'b1011000011;
        endcase
    end
endmodule
