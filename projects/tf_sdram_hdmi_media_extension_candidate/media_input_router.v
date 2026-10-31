// Both devices feed the SAME virtual keypad and shared pause/zoom latches.
// This allows an IR press to undo a matrix toggle, and vice versa.
module media_input_router #(
    parameter integer DEBOUNCE_CYCLES = 540_000
) (
    input wire clk, rst_n,
    input wire [15:0] matrix_keys, ir_keys,
    input wire ir_activity,
    input wire ir_emergency,
    input wire zoom_context, zoom_exit,
    input wire audio_clear,
    output wire [15:0] keys_down,
    output wire user_active,
    output reg audio_pause, zoom_enable,
    output wire emergency_enable
);
    wire pause_press, zoom_press;
    // Capture the mapping once per IR key press. A held 3 that ENTERS zoom
    // must not turn into a shrink event when zoom_context changes mid-press.
    reg [15:0] last_ir_keys, routed_ir_keys;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin last_ir_keys<=0; routed_ir_keys<=0; end
        else if (ir_keys==0) begin last_ir_keys<=0; routed_ir_keys<=0; end
        else if (ir_keys!=last_ir_keys) begin
            last_ir_keys<=ir_keys;
            routed_ir_keys <= (zoom_context && ir_keys[2]) ?
                              ((ir_keys & 16'hFFFB) | 16'h0800) : ir_keys;
        end
    end
    assign keys_down = matrix_keys | routed_ir_keys;
    assign user_active = (|keys_down) | ir_activity;
    // Deliberately no matrix key or SW4 in the emergency path.
    assign emergency_enable = ir_emergency;
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) pause_key (
        .clk(clk), .rst_n(rst_n), .key_n(!keys_down[13]),
        .press(pause_press), .held()
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) zoom_key (
        .clk(clk), .rst_n(rst_n), .key_n(!keys_down[2]),
        .press(zoom_press), .held()
    );
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            audio_pause <= 1'b0;
            zoom_enable <= 1'b0;
        end else begin
            if (audio_clear) audio_pause <= 0;
            else if (pause_press) audio_pause <= !audio_pause;
            if (zoom_exit) zoom_enable <= 0;
            else if (zoom_press) zoom_enable <= !zoom_enable;
        end
    end
endmodule
