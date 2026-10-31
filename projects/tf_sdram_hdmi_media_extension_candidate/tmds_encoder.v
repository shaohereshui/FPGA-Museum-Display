module tmds_encoder (
    input  wire       pixel_clk,
    input  wire       rst_n,
    input  wire       de,
    input  wire       c0,
    input  wire       c1,
    input  wire [7:0] data_in,
    output reg  [9:0] tmds_out
);

    reg signed [4:0] disparity;
    reg [8:0] q_m;
    integer i;

    function [3:0] count_ones8;
        input [7:0] value;
        integer bit_index;
        begin
            count_ones8 = 4'd0;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                count_ones8 = count_ones8 + value[bit_index];
        end
    endfunction

    wire [3:0] n1_data = count_ones8(data_in);
    wire use_xnor = (n1_data > 4) || ((n1_data == 4) && !data_in[0]);
    wire [3:0] n1_qm = count_ones8(q_m[7:0]);
    wire signed [4:0] qm_balance = $signed({1'b0, n1_qm}) -
                                   $signed({1'b0, (4'd8 - n1_qm)});

    always @(*) begin
        q_m[0] = data_in[0];
        for (i = 1; i < 8; i = i + 1) begin
            if (use_xnor)
                q_m[i] = q_m[i - 1] ~^ data_in[i];
            else
                q_m[i] = q_m[i - 1] ^ data_in[i];
        end
        q_m[8] = !use_xnor;
    end

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            tmds_out <= 10'b1101010100;
            disparity <= 5'sd0;
        end else if (!de) begin
            case ({c1, c0})
                2'b00: tmds_out <= 10'b1101010100;
                2'b01: tmds_out <= 10'b0010101011;
                2'b10: tmds_out <= 10'b0101010100;
                default: tmds_out <= 10'b1010101011;
            endcase
            disparity <= 5'sd0;
        end else if ((n1_qm == 4) || (disparity == 0)) begin
            if (q_m[8]) begin
                tmds_out <= {~q_m[8], q_m[8], q_m[7:0]};
                disparity <= disparity + qm_balance;
            end else begin
                tmds_out <= {~q_m[8], q_m[8], ~q_m[7:0]};
                disparity <= disparity - qm_balance;
            end
        end else if (((disparity > 0) && (n1_qm > 4)) ||
                     ((disparity < 0) && (n1_qm < 4))) begin
            tmds_out <= {1'b1, q_m[8], ~q_m[7:0]};
            disparity <= disparity - qm_balance + (q_m[8] ? 5'sd2 : 5'sd0);
        end else begin
            tmds_out <= {1'b0, q_m[8], q_m[7:0]};
            disparity <= disparity + qm_balance - (q_m[8] ? 5'sd0 : 5'sd2);
        end
    end

endmodule
