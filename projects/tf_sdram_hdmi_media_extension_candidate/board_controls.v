// On-board controls -> existing virtual keypad. All inputs are debounced.
// K4 tap: menu/confirm. K4 >=1s: BACK, exactly once, never a trailing tap.
// ZOOM: K2/K3 pan Y (SW3=0) or X (SW3=1). Hold K4 first, then K2/K3
// for zoom +/-; this consumes K4 and never emits menu/BACK on release.
// A direction's mapping is latched until its release: changing axis, UI or
// modifier while holding it cannot trigger another, unrelated operation.
module board_controls #(
    parameter integer DEBOUNCE_CYCLES = 540_000,
    parameter integer LONG_CYCLES = 27_000_000,
    parameter integer PULSE_CYCLES = 1_080_000
) (
    input wire clk, rst_n,
    input wire k2_n, k3_n, k4_n,
    input wire sw1, sw2, sw3, sw4,
    input wire zoom_on, ui_busy, zoom_exit,
    output wire [15:0] keys_down,
    output wire user_active,
    output wire audio_switch, zoom_switch, emergency_switch,
    output wire zoom_off, audio_changed, emergency_off
);
    wire p2,p3,p4,h2,h3,h4;
    wire s1,s2,s3,s4;
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) b2
        (.clk(clk),.rst_n(rst_n),.key_n(k2_n),.press(p2),.held(h2));
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) b3
        (.clk(clk),.rst_n(rst_n),.key_n(k3_n),.press(p3),.held(h3));
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) b4
        (.clk(clk),.rst_n(rst_n),.key_n(k4_n),.press(p4),.held(h4));
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) sdb1
        (.clk(clk),.rst_n(rst_n),.key_n(~sw1),.press(),.held(s1));
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) sdb2
        (.clk(clk),.rst_n(rst_n),.key_n(~sw2),.press(),.held(s2));
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) sdb3
        (.clk(clk),.rst_n(rst_n),.key_n(~sw3),.press(),.held(s3));
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) sdb4
        (.clk(clk),.rst_n(rst_n),.key_n(~sw4),.press(),.held(s4));
    reg q1,q2,q3,q4;
    reg zoom_blocked;
    assign audio_switch=s1;
    assign zoom_switch=s2 && !zoom_blocked;
    assign emergency_switch=s4;
    assign audio_changed=s1!=q1;
    assign zoom_off=q2 && !s2;
    assign emergency_off=q4 && !s4;
    wire switch_event=(s1!=q1)||(s2!=q2)||(s3!=q3)||(s4!=q4);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin q1<=0;q2<=0;q3<=0;q4<=0;zoom_blocked<=0; end
        else begin
            q1<=s1;q2<=s2;q3<=s3;q4<=s4;
            // BACK also exits physical-SW2 zoom. Re-arm by switching OFF/ON.
            if (!s2) zoom_blocked<=0;
            else if (zoom_exit) zoom_blocked<=1;
        end
    end
    localparam integer LW=(LONG_CYCLES<2)?1:$clog2(LONG_CYCLES+1);
    localparam integer PW=(PULSE_CYCLES<2)?1:$clog2(PULSE_CYCLES+1);
    reg [LW-1:0] hold_count;
    reg [PW-1:0] pulse_count;
    reg k4_pending,k4_consumed,k4_long_done;
    reg [15:0] key2_route,key3_route,event_keys;
    wire chord=zoom_on && !ui_busy && h4 && !k4_long_done;
    wire modifier_used=h4 && (h2 || h3);
    wire long_event=k4_pending && h4 && !k4_consumed && !k4_long_done &&
                    !modifier_used && hold_count==LONG_CYCLES-1;
    wire short_event=k4_pending && !h4 && !k4_consumed && !k4_long_done;
    wire visual_event=(s3!=q3) && !zoom_on && !ui_busy;
    wire [15:0] new_events=(long_event ? 16'h1000 : 16'h0000) |
                         (short_event ? (ui_busy ? 16'h4000 : 16'h0020) : 16'h0000) |
                         (visual_event ? 16'h0080 : 16'h0000);
    assign keys_down=key2_route | key3_route | event_keys;
    assign user_active=h2||h3||h4||(|keys_down)||switch_event;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_count<=0;pulse_count<=0;k4_pending<=0;k4_consumed<=0;k4_long_done<=0;
            key2_route<=0;key3_route<=0;event_keys<=0;
        end else begin
            if (!h2) key2_route<=0;
            else if (p2) begin
                if (h4 && k4_long_done) key2_route<=0;
                else if (chord) key2_route<=16'h0008;
                else if (zoom_on && !ui_busy && s3) key2_route<=16'h0010;
                else key2_route<=16'h0002;
            end
            if (!h3) key3_route<=0;
            else if (p3) begin
                if (h4 && k4_long_done) key3_route<=0;
                else if (chord) key3_route<=16'h0800;
                else if (zoom_on && !ui_busy && s3) key3_route<=16'h0040;
                else key3_route<=16'h0200;
            end
            if (p4) begin
                k4_pending<=1;k4_consumed<=modifier_used;k4_long_done<=0;hold_count<=0;
            end else if (k4_pending) begin
                if (!h4) begin k4_pending<=0;hold_count<=0; end
                else if (modifier_used) k4_consumed<=1;
                else if (!k4_consumed && !k4_long_done) begin
                    if (long_event) k4_long_done<=1;
                    else hold_count<=hold_count+1'b1;
                end
            end
            // Stretch events across the downstream 20ms keypad debouncer.
            if (|new_events) begin event_keys<=new_events;pulse_count<=PULSE_CYCLES; end
            else if (pulse_count!=0) begin
                pulse_count<=pulse_count-1'b1;
                if (pulse_count==1) event_keys<=0;
            end
        end
    end
endmodule
