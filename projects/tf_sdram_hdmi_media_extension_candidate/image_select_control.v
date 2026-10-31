module image_select_control #(
    parameter integer AUTO_INTERVAL_CYCLES = 250_000_000,
    parameter integer IMAGE_COUNT = 5
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ready,
    input  wire       pause,
    input  wire       prev_press,
    input  wire       next_press,
    input  wire       host_select,
    input  wire [2:0] host_image,
    output reg [2:0]  requested_image,
    output reg        request_manual,
    output reg        request_right,
    output reg        request_toggle
);
    localparam integer COUNTER_WIDTH =
        (AUTO_INTERVAL_CYCLES <= 2) ? 1 : $clog2(AUTO_INTERVAL_CYCLES);

    reg ready_m1, ready_m2;
    reg [COUNTER_WIDTH-1:0] auto_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_m1 <= 1'b0;
            ready_m2 <= 1'b0;
            auto_counter <= 0;
            requested_image <= 0;
            request_manual <= 0;
            request_right <= 0;
            request_toggle <= 0;
        end else begin
            ready_m1 <= ready;
            ready_m2 <= ready_m1;

            if (host_select) begin
                request_manual <= 1;
                request_right <= host_image > requested_image;
                request_toggle <= !request_toggle;
                requested_image <= host_image;
                auto_counter <= 0;
            end else if (prev_press) begin
                request_manual <= 1;
                request_right <= 0;
                request_toggle <= !request_toggle;
                if (requested_image == 0)
                    requested_image <= IMAGE_COUNT-1;
                else
                    requested_image <= requested_image - 1'b1;
                auto_counter <= 0;
            end else if (next_press) begin
                request_manual <= 1;
                request_right <= 1;
                request_toggle <= !request_toggle;
                if (requested_image == IMAGE_COUNT-1)
                    requested_image <= 0;
                else
                    requested_image <= requested_image + 1'b1;
                auto_counter <= 0;
            end else if (!ready_m2 || pause) begin
                // Interaction UI freezes the carousel; manual presses still work.
                auto_counter <= 0;
            end else if (auto_counter == AUTO_INTERVAL_CYCLES - 1) begin
                request_manual <= 0;
                request_toggle <= !request_toggle;
                if (requested_image == IMAGE_COUNT-1)
                    requested_image <= 0;
                else
                    requested_image <= requested_image + 1'b1;
                auto_counter <= 0;
            end else begin
                auto_counter <= auto_counter + 1'b1;
            end
        end
    end
endmodule
