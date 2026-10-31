// v47: physical K2/K3/K4 and SW3 are routed by board_controls.v.
// Legacy key_mode_n and sw_volume paths remain available to unit tests only.
// Board control mapping for the final media image.
// KEY2/KEY3 are image previous/next in standby and menu/vertical-pan controls
// in the other modes. Matrix key 5 opens the main menu with highest priority;
// # confirms, * backs out, and physical K4 remains a legacy confirm action.
// SW1 is low-active audio enable. SW2 high enables the zoom view and low stops
// it immediately. SW3 selects the zoom magnification (low 1.5x, high 2.0x,
// never above 2x).
//
// UI states:
//   Standby  : carousel; KEY2/KEY3 switch images; KEY4 opens the menu.
//   Menu     : GUIDE / DISPLAY / TRANS; 2/8 select, # confirms, * backs out.
//   Adjust   : select CON/BRI/VOL; 2 increases, 8 decreases, #/* exits.
//   Zoom     : SW2 high. 2/8 pan up/down, 4/6 pan left/right, A/C change
//              magnification. Matrix key 5 can still open the menu.
module media_control #(
    parameter integer DEBOUNCE_CYCLES = 1_000_000,
    parameter integer HOLD_DELAY_CYCLES = 13_500_000,
    parameter integer REPEAT_CYCLES = 1_350_000,
    parameter integer VIS_HOLD_CYCLES = 27_000_000,
    parameter integer IDLE_TIMEOUT_CYCLES = 405_000_000,
    parameter integer AUTO_LIGHT_CYCLES = 405_000_000, // 15 s at 27 MHz
    parameter integer MANUAL_IDLE_CYCLES = 810_000_000, // 30 s
    parameter integer PAN_STEP = 16,
    parameter integer ZOOM_RAMP_CYCLES = 13_500_000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        host_valid,
    input  wire [7:0]  host_command,
    input  wire [7:0]  host_value,
    input  wire        key_prev_n,
    input  wire        key_next_n,
    input  wire        key_mode_n,
    input  wire        volume_down_n,
    input  wire        volume_up_n,
    input  wire        key_menu_n,
    input  wire        key_confirm_n,
    input  wire        key_back_n,
    input  wire        key_zoom_in_n,
    input  wire        key_zoom_out_n,
    input  wire        key_visual_n,
    input  wire [3:0]  ambient_level,
    input  wire        ambient_valid,
    input  wire        external_activity,
    input  wire        board_zoom_off,
    input  wire        sw_param,   // SW2: zoom enable
    input  wire        sw_audio,   // SW1: low-active audio enable
    input  wire        sw_volume,  // SW3: zoom magnification select
    output wire        prev_image_press,
    output wire        next_image_press,
    output reg  [3:0]  brightness,
    output reg         brightness_manual,
    output reg  [3:0]  contrast,
    output reg  [6:0]  volume,
    output reg         adjust_mode,
    output wire        param_select,
    output wire        audio_enable,
    output wire        volume_select,
    output reg  [1:0]  visual_mode,
    output reg         ui_active,
    output reg [1:0]   ui_item,
    output reg         ui_guide,
    output reg         ui_trans,
    output reg         ui_display,
    output reg  [1:0]  trans_mode,
    output reg         zoom_menu_active,
    output wire        zoom_on,
    output wire        zoom_exit_req,
    output wire [9:0]  zoom_span_x,
    output wire [9:0]  zoom_span_y,
    output reg  [9:0]  zoom_win_x,
    output reg  [9:0]  zoom_win_y,
    output reg         pan_axis
);
    // Frame and zoom-viewport geometry (720x480 output).
    localparam integer FRAME_W = 720;
    localparam integer FRAME_H = 480;

    wire prev_press;
    wire next_press;
    wire mode_press, mode_held;
    wire menu_press, menu_held;
    wire confirm_press, confirm_held;
    wire back_press, back_held;
    wire zoom_in_press, zoom_in_held;
    wire zoom_out_press, zoom_out_held;
    wire visual_toggle_press, visual_toggle_held;
    reg mode_short_press, mode_down_seen, mode_long_done;
    reg [24:0] mode_hold_count;
    reg audio_meta, audio_sync;
    reg zoom_meta, zoom_sync;
    reg scale_meta, scale_sync;
    wire zoom_request = sw_param | zoom_menu_active;
    reg [1:0] adjust_param; // 0 contrast, 1 brightness, 2 volume
    wire prev_held, next_held;
    wire volume_down_press_local, volume_up_press_local;
    wire volume_down_held_local, volume_up_held_local;
    wire volume_down_press = volume_down_press_local;
    wire volume_up_press = volume_up_press_local;
    wire volume_down_held = volume_down_held_local;
    wire volume_up_held = volume_up_held_local;
    reg [23:0] repeat_count;
    reg repeat_active, repeat_direction;
    reg prev_repeat, next_repeat;
    reg [28:0] idle_count;
    reg [3:0] zoom_step;
    reg [24:0] ramp_count;
    reg [9:0] zoom_span_x_q, zoom_span_y_q;
    reg signed [10:0] pan_dx, pan_dy;
    reg zoom_on_q;
    wire signed [10:0] pan_max_x = $signed({1'b0, (10'd720 - span_x_for(zoom_step)) >> 1});
    wire signed [10:0] pan_max_y = $signed({1'b0, (10'd480 - span_y_for(zoom_step)) >> 1});

    // Shrinking increases the viewport: constrain offsets to the NEW span
    // before publishing coordinates, so panning near an edge cannot read out
    // of the frame when zooming back toward 1x.
    wire signed [10:0] pan_x_safe = pan_dx < -pan_max_x ? -pan_max_x :
                                   pan_dx > pan_max_x ? pan_max_x : pan_dx;
    wire signed [10:0] pan_y_safe = pan_dy < -pan_max_y ? -pan_max_y :
                                   pan_dy > pan_max_y ? pan_max_y : pan_dy;

    wire any_press = prev_press || next_press || mode_press || menu_press ||
                     confirm_press || back_press || zoom_in_press ||
                     zoom_out_press || visual_toggle_press ||
                     volume_down_press_local || volume_up_press_local ||
                     prev_repeat || next_repeat;
    // Hold-aware activity includes ALL matrix keys (even unassigned ones),
    // validated IR holds/repeats and physical control-switch transitions.
    wire any_held = prev_held || next_held || mode_held || menu_held ||
                    confirm_held || back_held || zoom_in_held || zoom_out_held ||
                    visual_toggle_held || volume_down_held || volume_up_held;
    reg audio_sync_q, zoom_sync_q, scale_sync_q;
    wire switch_activity = (audio_sync != audio_sync_q) ||
                           (zoom_sync != zoom_sync_q) || (scale_sync != scale_sync_q);
    wire user_activity = any_press || any_held || external_activity || switch_activity || host_valid;
    localparam integer LIGHT_COUNT_WIDTH = $clog2(MANUAL_IDLE_CYCLES + 1);
    reg [LIGHT_COUNT_WIDTH-1:0] light_idle_count;
    wire auto_light_due = !brightness_manual &&
                          light_idle_count >= AUTO_LIGHT_CYCLES - 1;
    wire manual_light_due = brightness_manual &&
                            light_idle_count >= MANUAL_IDLE_CYCLES - 1;
    wire apply_ambient = !user_activity && ambient_valid &&
                         (auto_light_due || manual_light_due);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            light_idle_count <= 0;
            audio_sync_q <= 0; zoom_sync_q <= 0; scale_sync_q <= 0;
        end else begin
            audio_sync_q <= audio_sync; zoom_sync_q <= zoom_sync;
            scale_sync_q <= scale_sync;
            if (user_activity || apply_ambient) light_idle_count <= 0;
            else if (light_idle_count < MANUAL_IDLE_CYCLES - 1)
                light_idle_count <= light_idle_count + 1'b1;
        end
    end
    wire confirm_event = confirm_press || mode_short_press;
    wire interactive = ui_active || ui_guide || ui_trans || adjust_mode;
    wire idle_expired = interactive && !any_press &&
                        (idle_count == IDLE_TIMEOUT_CYCLES - 1);

    assign zoom_exit_req = zoom_sync && !interactive && back_press;
    assign zoom_on = zoom_sync;
    assign zoom_span_x = zoom_span_x_q;
    assign zoom_span_y = zoom_span_y_q;

    // 1.0x (full frame) down to 2.0x (half-size span) in nine steps.
    function [9:0] span_x_for;
        input [3:0] step;
        begin
            case (step)
                4'd0: span_x_for = 10'd720;
                4'd1: span_x_for = 10'd640;
                4'd2: span_x_for = 10'd576;
                4'd3: span_x_for = 10'd524;
                4'd4: span_x_for = 10'd480;
                4'd5: span_x_for = 10'd443;
                4'd6: span_x_for = 10'd411;
                4'd7: span_x_for = 10'd384;
                default: span_x_for = 10'd360;
            endcase
        end
    endfunction

    function [9:0] span_y_for;
        input [3:0] step;
        begin
            case (step)
                4'd0: span_y_for = 10'd480;
                4'd1: span_y_for = 10'd427;
                4'd2: span_y_for = 10'd384;
                4'd3: span_y_for = 10'd349;
                4'd4: span_y_for = 10'd320;
                4'd5: span_y_for = 10'd295;
                4'd6: span_y_for = 10'd274;
                4'd7: span_y_for = 10'd256;
                default: span_y_for = 10'd240;
            endcase
        end
    endfunction

    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) prev_key (
        .clk(clk), .rst_n(rst_n), .key_n(key_prev_n), .press(prev_press), .held(prev_held)
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) next_key (
        .clk(clk), .rst_n(rst_n), .key_n(key_next_n), .press(next_press), .held(next_held)
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) mode_key (
        .clk(clk), .rst_n(rst_n), .key_n(key_mode_n), .press(mode_press), .held(mode_held)
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) volume_down_key (
        .clk(clk), .rst_n(rst_n), .key_n(volume_down_n),
        .press(volume_down_press_local), .held(volume_down_held_local)
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) volume_up_key (
        .clk(clk), .rst_n(rst_n), .key_n(volume_up_n),
        .press(volume_up_press_local), .held(volume_up_held_local)
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) menu_key (
        .clk(clk), .rst_n(rst_n), .key_n(key_menu_n),
        .press(menu_press), .held(menu_held)
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) confirm_key (
        .clk(clk), .rst_n(rst_n), .key_n(key_confirm_n),
        .press(confirm_press), .held(confirm_held)
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) back_key (
        .clk(clk), .rst_n(rst_n), .key_n(key_back_n),
        .press(back_press), .held(back_held)
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) zoom_in_key (
        .clk(clk), .rst_n(rst_n), .key_n(key_zoom_in_n),
        .press(zoom_in_press), .held(zoom_in_held)
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) zoom_out_key (
        .clk(clk), .rst_n(rst_n), .key_n(key_zoom_out_n),
        .press(zoom_out_press), .held(zoom_out_held)
    );
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) visual_toggle_key (
        .clk(clk), .rst_n(rst_n), .key_n(key_visual_n),
        .press(visual_toggle_press), .held(visual_toggle_held)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            audio_meta <= 1'b0;
            audio_sync <= 1'b0;
            zoom_meta <= 1'b0;
            zoom_sync <= 1'b0;
            scale_meta <= 1'b0;
            scale_sync <= 1'b0;
        end else begin
            audio_meta <= sw_audio;
            audio_sync <= audio_meta;
            zoom_meta <= zoom_request;
            zoom_sync <= zoom_meta;
            scale_meta <= sw_volume;
            scale_sync <= scale_meta;
        end
    end

    // DISPLAY submenu order: CON, BRI, VOL.
    assign param_select = (adjust_param == 2'd0);
    assign audio_enable = !audio_sync;
    assign volume_select = (adjust_param == 2'd2);
    // KEY2/KEY3 only switch images in standby, never while zooming or in UI.
    assign prev_image_press = prev_press && !adjust_mode && !ui_active &&
                              !ui_guide && !ui_trans && !zoom_sync;
    assign next_image_press = next_press && !adjust_mode && !ui_active &&
                              !ui_guide && !ui_trans && !zoom_sync;

    // K4 short click is generated on release; a held K4 toggles the visual mode
    // once and does not produce a short click.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            visual_mode <= 0; mode_short_press <= 0; mode_down_seen <= 0;
            mode_long_done <= 0; mode_hold_count <= 0;
        end else begin
            mode_short_press <= 0;
            if (host_valid && host_command == 8'h28) begin
                visual_mode <= host_value[1:0];
            end else if (visual_toggle_press) begin
                visual_mode <= visual_mode == 0 ? 1 : 0;
            end else if (mode_press) begin
                mode_down_seen <= 1; mode_long_done <= 0; mode_hold_count <= 0;
            end else if (mode_down_seen) begin
                if (mode_held) begin
                    if (!mode_long_done) begin
                        if (mode_hold_count == VIS_HOLD_CYCLES-1) begin
                            visual_mode <= visual_mode == 0 ? 1 : 0;
                            mode_long_done <= 1;
                        end else begin
                            mode_hold_count <= mode_hold_count + 1'b1;
                        end
                    end
                end else begin
                    if (!mode_long_done) mode_short_press <= 1;
                    mode_down_seen <= 0; mode_hold_count <= 0;
                end
            end
        end
    end

    // Volume repeat only in adjust mode.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            repeat_count <= 0; repeat_active <= 0; repeat_direction <= 0;
            prev_repeat <= 0; next_repeat <= 0;
        end else begin
            prev_repeat <= 0; next_repeat <= 0;
            if (!adjust_mode || !volume_select || !(prev_held ^ next_held)) begin
                repeat_count <= 0; repeat_active <= 0;
                repeat_direction <= next_held;
            end else if (repeat_direction != next_held) begin
                repeat_count <= 0; repeat_active <= 0;
                repeat_direction <= next_held;
            end else if (repeat_count == (repeat_active ? REPEAT_CYCLES : HOLD_DELAY_CYCLES)-1) begin
                repeat_count <= 0; repeat_active <= 1;
                prev_repeat <= prev_held; next_repeat <= next_held;
            end else begin
                repeat_count <= repeat_count + 1'b1;
            end
        end
    end

    // Interaction state: main menu, GUIDE mode selector, DISPLAY submenu,
    // TRANS submenu and idle fallback. Matrix key 5 always returns to the
    // main menu; # confirms and * backs out one level.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ui_active <= 1'b0;
            ui_item <= 2'd0;
            ui_guide <= 1'b0;
            ui_trans <= 1'b0;
            ui_display <= 1'b0;
            zoom_menu_active <= 1'b0;
            trans_mode <= 2'd2; // FADE by default
            idle_count <= 0;
        end else if (host_valid && host_command == 8'h27) begin
            trans_mode <= host_value[1:0];
            idle_count <= 0;
        end else if (board_zoom_off) begin
            zoom_menu_active <= 1'b0;
            ui_active <= 1'b0; ui_guide <= 1'b0;
            ui_trans <= 1'b0; ui_display <= 1'b0; idle_count <= 0;
        end else if (menu_press) begin
            // Highest-priority menu entry. Keep the zoom request itself intact
            // so the user can return to the active zoom view with *.
            ui_active <= 1'b1;
            ui_item <= 2'd0;
            ui_guide <= 1'b0;
            ui_trans <= 1'b0;
            ui_display <= 1'b0;
            idle_count <= 0;
        end else if (zoom_sync && !ui_active && !ui_guide && !ui_trans && !adjust_mode) begin
            // * exits menu/remote zoom; the input router clears its shared
            // toggle simultaneously. Physical SW2 retains its original priority.
            if (back_press) zoom_menu_active <= 1'b0;
            // Zoom takes over only while no menu/page is being displayed.
            ui_active <= 1'b0;
            ui_guide <= 1'b0;
            ui_trans <= 1'b0;
            idle_count <= 0;
        end else begin
            if (interactive) begin
                if (any_press) idle_count <= 0;
                else if (idle_count == IDLE_TIMEOUT_CYCLES - 1) idle_count <= 0;
                else idle_count <= idle_count + 1'b1;
            end else idle_count <= 0;

            if (idle_expired) begin
                ui_active <= 1'b0;
                ui_guide <= 1'b0;
                ui_trans <= 1'b0;
                ui_display <= 1'b0;
            end else if (back_press) begin
                if (adjust_mode) begin
                    ui_active <= 1'b1;
                    ui_display <= 1'b1;
                end else if (ui_display) begin
                    ui_display <= 1'b0;
                    ui_active <= 1'b1;
                    ui_item <= 2'd1;
                end else if (ui_trans) begin
                    ui_trans <= 1'b0;
                    ui_active <= 1'b1;
                    ui_item <= 2'd2;
                end else if (ui_guide) begin
                    ui_guide <= 1'b0;
                    ui_active <= 1'b1;
                    ui_item <= 2'd0;
                end else if (ui_active) begin
                    ui_active <= 1'b0;
                end
            end else if (confirm_event) begin
                if (adjust_mode) begin
                    // # confirms the currently selected DISPLAY value and
                    // returns to the CON/BRI/VOL list.
                    ui_display <= 1'b1;
                end else if (ui_display) begin
                    // The picture-control block enters adjust_mode for the
                    // selected CON/BRI/VOL item.
                    ui_display <= 1'b1;
                end else if (ui_trans) begin
                    trans_mode <= ui_item;
                    ui_trans <= 1'b0;
                    ui_active <= 1'b1;
                    ui_item <= 2'd2;
                end else if (ui_active) begin
                    case (ui_item)
                        2'd0: begin ui_active <= 1'b0; ui_guide <= 1'b1; end
                        2'd1: begin ui_active <= 1'b1; ui_display <= 1'b1; ui_item <= 2'd0; end
                        default: begin
                            // TRANS: open the transition sub-menu.
                            ui_active <= 1'b0;
                            ui_trans <= 1'b1;
                            ui_item <= trans_mode;
                        end
                    endcase
                end else if (ui_guide) begin
                    if (ui_item == 2'd1) begin
                        zoom_menu_active <= 1'b1;
                        ui_guide <= 1'b0;
                        ui_active <= 1'b0;
                        ui_display <= 1'b0;
                    end else begin
                        zoom_menu_active <= 1'b0;
                        ui_guide <= 1'b0;
                        ui_active <= 1'b1;
                        ui_item <= 2'd0;
                    end
                end else begin
                    ui_active <= 1'b1;
                    ui_item <= 2'd0;
                end
            end else if (ui_guide && (prev_press || next_press)) begin
                if (prev_press)
                    ui_item <= ui_item == 2'd0 ? 2'd1 : 2'd0;
                else
                    ui_item <= ui_item == 2'd1 ? 2'd0 : 2'd1;
            end else if (ui_display && !adjust_mode && (prev_press || next_press)) begin
                if (prev_press)
                    ui_item <= ui_item == 2'd0 ? 2'd2 : ui_item - 1'b1;
                else
                    ui_item <= ui_item == 2'd2 ? 2'd0 : ui_item + 1'b1;
            end else if (ui_trans && (prev_press || next_press)) begin
                if (prev_press) begin
                    ui_item <= ui_item == 2'd0 ? 2'd2 : ui_item - 1'b1;
                end else begin
                    ui_item <= ui_item == 2'd2 ? 2'd0 : ui_item + 1'b1;
                end
            end else if (ui_active && !adjust_mode && (prev_press || next_press)) begin
                if (prev_press) begin
                    ui_item <= ui_item == 2'd0 ? 2'd2 : ui_item - 1'b1;
                end else begin
                    ui_item <= ui_item == 2'd2 ? 2'd0 : ui_item + 1'b1;
                end
            end
        end
    end

    // Picture controls and DISPLAY adjust cycling.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            brightness <= 4'd5;
            brightness_manual <= 1'b0;
            contrast <= 4'd5;
            volume <= 7'd50;
            adjust_mode <= 1'b0;
            adjust_param <= 2'd0;
        end else begin
            // One brightness register for display AND editing prevents jumps
            // back to a stale manual value when the BRI menu is entered.
            if (apply_ambient) begin
                brightness <= ambient_level > 4'd9 ? 4'd9 : ambient_level;
                brightness_manual <= 1'b0;
            end
            if (board_zoom_off || menu_press || back_press || idle_expired) begin
                adjust_mode <= 1'b0;
                adjust_param <= 2'd0;
            end else if (confirm_event) begin
                if (adjust_mode) begin
                    adjust_mode <= 1'b0;
                    adjust_param <= 2'd0;
                end else if (ui_display) begin
                    adjust_mode <= 1'b1;
                    adjust_param <= ui_item;
                end
            end

            if (host_valid && host_command == 8'h21) begin
                volume <= host_value[6:0];
            end else if (host_valid && host_command == 8'h22) begin
                brightness_manual <= host_value != 8'hff;
                if (host_value != 8'hff)
                    brightness <= host_value[3:0];
                else if (ambient_valid)
                    brightness <= ambient_level > 4'd9 ? 4'd9 : ambient_level;
            end else if (host_valid && host_command == 8'h23) begin
                contrast <= host_value[3:0];
            end else if (adjust_mode) begin
                if (volume_select) begin
                    case ({(prev_press || prev_repeat), (next_press || next_repeat)})
                        2'b10: if (volume != 100) volume <= volume + 1'b1;
                        2'b01: if (volume != 0) volume <= volume - 1'b1;
                        default: begin end
                    endcase
                end else if (param_select) begin
                    if (prev_press) begin
                        if (contrast != 4'd9) contrast <= contrast + 1'b1;
                    end else if (next_press) begin
                        if (contrast != 4'd0) contrast <= contrast - 1'b1;
                    end
                end else begin
                    // An adjustment at the limit is still a manual choice.
                    if (prev_press && !next_press) begin
                        if (brightness != 4'd9) brightness <= brightness + 1'b1;
                        brightness_manual <= 1'b1;
                    end else if (next_press && !prev_press) begin
                        if (brightness != 4'd0) brightness <= brightness - 1'b1;
                        brightness_manual <= 1'b1;
                    end
                end
            end
        end
    end

    // Zoom view: SW2 high enables the magnified view and low disables it.
    // A/C change magnification, 2/8 pan up/down, and 4/6 pan left/right.
    // Physical SW3 remains a slow magnification ramp for compatibility.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zoom_step <= 4'd0;
            ramp_count <= 0;
            zoom_on_q <= 1'b0;
            zoom_span_x_q <= 10'd720;
            zoom_span_y_q <= 10'd480;
            pan_dx <= 11'sd0;
            pan_dy <= 11'sd0;
            zoom_win_x <= 10'd0;
            zoom_win_y <= 10'd0;
            pan_axis <= 1'b0;
        end else begin
            zoom_on_q <= zoom_sync;
            zoom_span_x_q <= span_x_for(zoom_step);
            zoom_span_y_q <= span_y_for(zoom_step);
            if (!zoom_sync) begin
                zoom_step <= 4'd0;
                ramp_count <= 0;
                pan_axis <= 1'b0;
                pan_dx <= 11'sd0;
                pan_dy <= 11'sd0;
                zoom_win_x <= 10'd0;
                zoom_win_y <= 10'd0;
            end else if (!zoom_on_q) begin
                zoom_step <= 4'd0;
                ramp_count <= 0;
                pan_axis <= 1'b0;
                pan_dx <= 11'sd0;
                pan_dy <= 11'sd0;
                zoom_win_x <= 10'd0;
                zoom_win_y <= 10'd0;
            end else begin
                pan_axis <= 1'b0;
                pan_dx <= pan_x_safe;
                pan_dy <= pan_y_safe;
                if (!ui_active && !ui_guide && !ui_trans && !adjust_mode) begin
                    if (zoom_in_press && zoom_step != 4'd8) begin
                        zoom_step <= zoom_step + 1'b1;
                        ramp_count <= 0;
                    end else if (zoom_out_press && zoom_step != 4'd0) begin
                        zoom_step <= zoom_step - 1'b1;
                        ramp_count <= 0;
                    end else if (scale_sync) begin
                        if (ramp_count == ZOOM_RAMP_CYCLES - 1) begin
                            ramp_count <= 0;
                            if (zoom_step != 4'd8) zoom_step <= zoom_step + 1'b1;
                        end else begin
                            ramp_count <= ramp_count + 1'b1;
                        end
                    end else begin
                        ramp_count <= 0;
                    end

                    // 2 = up, 8 = down.
                    if (prev_press) begin
                        if (pan_y_safe - 11'sd16 < -pan_max_y)
                            pan_dy <= -pan_max_y;
                        else pan_dy <= pan_y_safe - 11'sd16;
                    end else if (next_press) begin
                        if (pan_y_safe + 11'sd16 > pan_max_y)
                            pan_dy <= pan_max_y;
                        else pan_dy <= pan_y_safe + 11'sd16;
                    end
                    // 4 = left, 6 = right.
                    if (volume_down_press_local) begin
                        if (pan_x_safe - 11'sd16 < -pan_max_x)
                            pan_dx <= -pan_max_x;
                        else pan_dx <= pan_x_safe - 11'sd16;
                    end else if (volume_up_press_local) begin
                        if (pan_x_safe + 11'sd16 > pan_max_x)
                            pan_dx <= pan_max_x;
                        else pan_dx <= pan_x_safe + 11'sd16;
                    end
                end else begin
                    ramp_count <= 0;
                end

                zoom_win_x <= pan_max_x + pan_x_safe;
                zoom_win_y <= pan_max_y + pan_y_safe;
            end
        end
    end
endmodule
