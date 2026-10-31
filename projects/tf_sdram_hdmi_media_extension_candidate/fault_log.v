// P6 maintainability: latch the first fault (stage + code) and count later
// fault episodes so a transient error cannot disappear from the screen without
// a trace. Nothing here retries or hides the fault; the latch clears only on
// reset.
module fault_log (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       fault_active,
    input  wire [2:0] fault_source,
    input  wire [4:0] fault_code,
    output reg        held,
    output reg  [2:0] held_source,
    output reg  [4:0] held_code,
    output reg  [3:0] count
);
    reg fault_seen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            held <= 1'b0;
            held_source <= 3'd0;
            held_code <= 5'd0;
            count <= 4'd0;
            fault_seen <= 1'b0;
        end else if (!fault_active) begin
            fault_seen <= 1'b0;
        end else if (!fault_seen) begin
            // Rising edge of a fault episode: record the first one, count the rest.
            fault_seen <= 1'b1;
            if (!held) begin
                held <= 1'b1;
                held_source <= fault_source;
                held_code <= fault_code;
                count <= 4'd1;
            end else if (count != 4'hF) begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
