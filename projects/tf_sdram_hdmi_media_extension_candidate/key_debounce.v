// Active-low push-button synchronizer, debounce filter and one-shot press event.
module key_debounce #(
    parameter integer DEBOUNCE_CYCLES = 1_000_000
) (
    input wire clk,
    input wire rst_n,
    input wire key_n,
    output reg press,
    output wire held
);
    localparam integer COUNT_WIDTH = 20;
    reg sync_m1, sync_m2;
    reg stable_n;
    reg [COUNT_WIDTH-1:0] count;
    assign held = !stable_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_m1 <= 1'b1;
            sync_m2 <= 1'b1;
            stable_n <= 1'b1;
            count <= 0;
            press <= 1'b0;
        end else begin
            sync_m1 <= key_n;
            sync_m2 <= sync_m1;
            press <= 1'b0;
            if (sync_m2 == stable_n) begin
                count <= 0;
            end else if (count == DEBOUNCE_CYCLES - 1) begin
                stable_n <= sync_m2;
                count <= 0;
                if (stable_n && !sync_m2)
                    press <= 1'b1;
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
