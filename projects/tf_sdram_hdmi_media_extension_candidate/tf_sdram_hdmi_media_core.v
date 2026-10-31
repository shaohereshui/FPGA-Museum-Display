module tf_sdram_hdmi_media_core (
    input  wire        clk_50,
    input  wire        rst_n,
    input  wire        key_prev_n,
    input  wire        key_next_n,
    input  wire        key_mode_n,
    input  wire        sw_param,
    input  wire        sw_audio,
    input  wire        sw_volume,
    input  wire        sw_lyrics,
    input  wire        ir_rx,
    input  wire        subtitle_rx,
    output wire        subtitle_tx,
    output wire [3:0]  keypad_row,
    input  wire [3:0]  keypad_col,
    input  wire        sd_miso,
    output wire        sd_dclk,
    output wire        sd_mosi,
    output wire        sd_ncs,
    output wire        HDMI_CLK_P,
    output wire        HDMI_D0_P,
    output wire        HDMI_D1_P,
    output wire        HDMI_D2_P,
    output wire        led,
    output wire        sdram_clk,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    output wire [10:0] sdram_addr,
    output wire [1:0]  sdram_ba,
    output wire [3:0]  sdram_dm,
    inout  wire [31:0] sdram_dq
);
    localparam integer FRAME_WORDS = 720*480;
    localparam integer VIDEO_PREFILL_WORDS = 1792;
    localparam [20:0] FRAME_BASE_0 = 21'd0;
    localparam [20:0] FRAME_BASE_1 = 21'd345600;
    localparam [20:0] FRAME_BASE_2 = 21'd691200;
    localparam [20:0] FRAME_BASE_3 = 21'd1036800;
    localparam [20:0] FRAME_BASE_4 = 21'd1382400;
    // Five 720x480 32-bit buffers occupy 1,728,000 words, below 2^21.
    function [20:0] image_frame_base;
        input [2:0] index;
        begin
            case(index)
                3'd1: image_frame_base=FRAME_BASE_1;
                3'd2: image_frame_base=FRAME_BASE_2;
                3'd3: image_frame_base=FRAME_BASE_3;
                3'd4: image_frame_base=FRAME_BASE_4;
                default: image_frame_base=FRAME_BASE_0;
            endcase
        end
    endfunction

    wire sd_clk;
    wire sd_clk_locked;
    wire mem_clk;
    wire mem_clk_sft;
    wire core_rst_n = rst_n && sd_clk_locked;
    wire mem_rst = !core_rst_n;

    wire mounted, complete, found, lookup_error;
    wire [4:0] mount_error_code;
    wire [7:0] sd_cmd0_r1;
    wire [31:0] file_cluster, file_size, file_offset;
    wire [7:0] file_data;
    wire file_ready, file_start, file_valid, file_done, file_error;
    wire locator_restart;
    wire [63:0] current_stem;
    wire pixel_valid, image_done, image_error;
    wire [18:0] pixel_addr;
    wire [23:0] pixel_rgb;
    wire bmp_input_ready, bmp_top_down;
    wire [7:0] bmp_error_code;
    reg bmp_top_down_m1, bmp_top_down_mem;
    reg music_mode, music_started, music_failed;
    reg music_session_started;
    reg [7:0] music_failure_code;
    wire music_input_ready, music_done, music_error, music_playing, music_fault;
    wire [7:0] music_error_code;
    reg music_failed_p1, music_failed_p2;
    reg [4:0] music_code_p1, music_code_p2;
    wire prev_image_press, next_image_press;
    wire [3:0] brightness_reg, contrast_reg;
    wire brightness_manual;
    wire host_valid;
    wire [7:0] host_command, host_value;
    reg host_carousel, host_audio_pause;
    wire [3:0] ambient_brightness;
    wire ambient_brightness_valid;
    wire [11:0] light_sample;
    wire light_sample_valid;
    wire [6:0] volume_reg;
    wire [1:0] visual_mode;
    wire adjust_mode, param_select, audio_enable, volume_select;
    wire ui_active, ui_guide, ui_display;
    wire [1:0] ui_item;
    wire ui_trans;
    wire [1:0] trans_mode_ui;
    wire zoom_on;
    wire pan_axis;
    wire [9:0] zoom_span_x, zoom_span_y, zoom_win_x, zoom_win_y;
    wire [23:0] accent_color;
    wire [15:0] matrix_keys, ir_key_bits, control_keys, board_keys, routed_keys;
    assign control_keys = routed_keys | board_keys;
    wire board_activity, board_sw1, board_sw2, board_sw4;
    wire board_zoom_off, board_audio_changed, board_emergency_off;
    wire ir_activity, ir_emergency, user_activity;
    wire shared_audio_pause, shared_zoom_enable;
    wire zoom_exit_req;
    wire control_prev_n = ~control_keys[1];
    wire control_next_n = ~control_keys[9];
    wire control_mode_n = 1'b1; // K4 gestures decoded once in board_controls.
    wire control_volume_down_n = ~control_keys[4];
    wire control_volume_up_n = ~control_keys[6];
    wire effective_sw_audio = board_sw1 | shared_audio_pause | host_audio_pause;
    wire effective_sw_param = board_sw2 | shared_zoom_enable;
    wire effective_sw_volume = 1'b0; // SW3 selects the board pan axis, never auto-zooms.
    wire ir_emergency_enable;
    wire effective_sw_lyrics = board_sw4 | ir_emergency_enable;
    wire [3:0] effective_brightness = brightness_reg;
    // P6 maintainability: latched fault record + self-check summary.
    wire fault_active, fault_held, self_ok;
    wire [2:0] fault_source;
    wire [4:0] fault_code;
    wire [3:0] fault_count;
    reg audio_enable_sd1, audio_enable_sd2;
    wire file_pause = music_mode ? !music_input_ready : !bmp_input_ready;

    reg [2:0] load_index;
    reg load_started;
    reg preload_done_sd;
    reg locator_restart_reg;
    reg frame_started_sd;
    reg image_done_sd;
    reg image_error_sd;
    reg file_stream_error_sd;
    reg [20:0] frame_base_sd;
    reg frame_done_sd_m1, frame_done_sd_m2, frame_done_sd_seen;
    wire load_fifo_full, load_fifo_empty;
    wire load_fifo_rd_en;
    wire [31:0] load_fifo_data;
    wire load_fifo_wr_en = pixel_valid && !load_fifo_full;

    reg frame_started_m1, frame_started_mem;
    reg [20:0] frame_base_m1, frame_base_mem;
    reg image_done_m1, image_done_mem;
    reg image_error_m1, image_error_mem;
    reg preload_done_m1, preload_done_mem;

    wire init_done;
    wire refresh;
    wire sdram_busy;
    wire app_wr_en;
    wire [20:0] app_wr_addr;
    wire [31:0] app_wr_data;
    wire frame_done;
    wire writer_failed;
    wire [18:0] write_count;

    wire app_rd_en;
    wire [20:0] app_rd_addr;
    wire sdram_rd_valid;
    wire [31:0] sdram_rd_data;
    wire video_fifo_full, video_fifo_empty, video_fifo_almost_full;
    wire [11:0] video_fifo_used_words;
    wire video_fifo_wr_en;
    wire [31:0] video_fifo_wr_data;
    wire prefetch_done;
    wire prefetch_restart_done;
    reg [10:0] video_prefill_count;
    reg video_prefill_ready;
    reg [2:0] requested_image_m1, requested_image_m2, requested_image_mem;
    reg request_manual_m1, request_manual_m2, request_manual_mem;
    reg request_right_m1, request_right_m2, request_right_mem;
    reg request_toggle_m1, request_toggle_m2, request_toggle_m3, request_toggle_seen;
    wire slide_active_mem, slide_done_mem;
    wire [2:0] slide_completed_image_mem;
    wire [20:0] requested_frame_base_mem = image_frame_base(requested_image_mem);
    reg [2:0] selected_image_mem;
    reg video_fifo_flush;
    reg video_switch_toggle;
    reg video_switch_pending;
    reg video_switch_ack_m1, video_switch_ack_mem;
    // Transition-mode handshake: fade_switch_enable gates the frame switch in
    // FADE mode; trans_mode_m2 selects CORNERS / SLIDE / FADE.
    reg fade_en_m1, fade_en_m2;
    reg [1:0] trans_mode_m1, trans_mode_m2;
    wire [20:0] selected_frame_base_mem = image_frame_base(selected_image_mem);
    wire video_fifo_rst_n = rst_n && !video_fifo_flush;
    wire video_prefetch_enable = preload_done_mem;
    wire video_prefetch_restart = video_fifo_flush;
    wire video_ready_mem = preload_done_mem && video_prefill_ready;
    wire transition_request = preload_done_mem && video_prefill_ready &&
        requested_image_mem!=selected_image_mem && fade_en_m2 &&
        !video_fifo_flush && !video_switch_pending;

    wire pixel_clk;
    wire serial_clk_5x;
    wire video_pll_locked;
    reg [1:0] video_reset_sync;
    reg video_display_active;
    wire video_rst_n;
    wire hsync, vsync, de;
    wire [23:0] timing_rgb;
    wire [9:0] h_count, v_count;
    wire video_fifo_rd_en = video_rst_n && video_display_active && de;
    wire [31:0] video_fifo_data;
    reg video_app_rd_seen;
    reg video_rd_valid_seen;
    reg video_fifo_wr_seen;
    reg video_fifo_full_seen;
    reg video_app_rd_after_full_seen;
    reg video_rd_valid_after_full_seen;
    reg video_fifo_wr_after_full_seen;
    reg video_fifo_nonempty_seen;
    reg video_fifo_empty_seen;
    reg video_app_rd_p1, video_app_rd_p2;
    reg video_rd_valid_p1, video_rd_valid_p2;
    reg video_fifo_wr_p1, video_fifo_wr_p2;
    reg video_fifo_full_p1, video_fifo_full_p2;
    reg video_app_rd_after_full_p1, video_app_rd_after_full_p2;
    reg video_rd_valid_after_full_p1, video_rd_valid_after_full_p2;
    reg video_fifo_wr_after_full_p1, video_fifo_wr_after_full_p2;
    wire [23:0] video_fallback_rgb =
        !video_app_rd_p2          ? 24'hFF0000 :
        !video_rd_valid_p2        ? 24'hFFFF00 :
        !video_fifo_wr_p2         ? 24'h00FF00 :
        !video_fifo_nonempty_seen ? 24'hFF00FF :
        !video_fifo_empty_seen    ? 24'hFFFFFF :
        24'h0000FF;
    // Until preload/prefill complete, only status is shown over a black background.
    wire [23:0] video_source_rgb = video_display_active ? video_fifo_data[23:0] : 24'd0;
    wire [23:0] video_adjusted_rgb;

    // Independent picture controls: contrast expands/contracts about fixed
    // mid-gray BEFORE adding brightness.  This keeps a brightness step at
    // eight codes regardless of contrast, until the final 0..255 clamp.
    // Ten distinct gains span 1/4..2 with unity at level 5.  Signed shift/add
    // numerators retain fractional precision without a variable multiplier.
    function [7:0] adjust_channel;
        input [7:0] c;
        input [3:0] br;
        input [3:0] co;
        reg signed [11:0] value;
        reg signed [11:0] brightness_offset;
        reg signed [12:0] contrast_input;
        reg signed [12:0] contrast_numerator;
        begin
            case (br)
                4'd0: brightness_offset = -12'sd64;
                4'd1: brightness_offset = -12'sd32;
                4'd2: brightness_offset = -12'sd24;
                4'd3: brightness_offset = -12'sd16;
                4'd4: brightness_offset = -12'sd8;
                4'd6: brightness_offset = 12'sd8;
                4'd7: brightness_offset = 12'sd16;
                4'd8: brightness_offset = 12'sd32;
                4'd9: brightness_offset = 12'sd64;
                default: brightness_offset = 12'sd0;
            endcase
            contrast_input = {5'b00000, c} - 13'sd128;
            case (co)
                4'd0: contrast_numerator = contrast_input <<< 1; // 2/8 = 0.25
                4'd1: contrast_numerator = (contrast_input <<< 1) + contrast_input; // 3/8
                4'd2: contrast_numerator = contrast_input <<< 2; // 4/8
                4'd3: contrast_numerator = (contrast_input <<< 2) + contrast_input; // 5/8
                4'd4: contrast_numerator = (contrast_input <<< 2) + (contrast_input <<< 1); // 6/8
                4'd5: contrast_numerator = contrast_input <<< 3; // 8
                4'd6: contrast_numerator = (contrast_input <<< 3) + (contrast_input <<< 1); // 10/8
                4'd7: contrast_numerator = (contrast_input <<< 3) + (contrast_input <<< 2); // 12/8
                4'd8: contrast_numerator = (contrast_input <<< 4) - (contrast_input <<< 1); // 14/8
                4'd9: contrast_numerator = contrast_input <<< 4; // 16/8 = 2
                default: contrast_numerator = contrast_input <<< 3;
            endcase
            value = 13'sd128 + (contrast_numerator >>> 3) + brightness_offset;
            if (value < 0)
                adjust_channel = 8'd0;
            else if (value > 12'sd255)
                adjust_channel = 8'd255;
            else
                adjust_channel = value[7:0];
        end
    endfunction

    assign video_adjusted_rgb = video_display_active ? {
        adjust_channel(video_source_rgb[23:16], osd_brightness_p2, osd_contrast_p2),
        adjust_channel(video_source_rgb[15:8],  osd_brightness_p2, osd_contrast_p2),
        adjust_channel(video_source_rgb[7:0],   osd_brightness_p2, osd_contrast_p2)
    } : video_source_rgb;
    // FIFO alpha travels with each scaled pixel. Fade AFTER the independent
    // brightness/contrast controls, so an empty transition region stays black.
    // 32 is exactly opaque, zero exactly black; OSD and lyrics remain on top.
    function [7:0] fade_channel;
        input [7:0] channel;
        input [5:0] alpha;
        reg [13:0] product;
        begin product=channel*alpha;fade_channel=product[12:5];end
    endfunction
    // Fade-to-black stage: shift the picture down while the frame switch runs.
    // OSD/lyrics are applied after this point and stay readable.
    function [7:0] dim_channel;
        input [7:0] channel;
        input [2:0] shift;
        begin
            case (shift)
                3'd0: dim_channel = channel;
                3'd1: dim_channel = {1'b0, channel[7:1]};
                3'd2: dim_channel = {2'b00, channel[7:2]};
                3'd3: dim_channel = {3'b000, channel[7:3]};
                3'd4: dim_channel = {4'b0000, channel[7:4]};
                3'd5: dim_channel = {5'b00000, channel[7:5]};
                default: dim_channel = 8'd0;
            endcase
        end
    endfunction
    wire [23:0] video_faded_rgb=video_display_active ? {
        fade_channel(video_adjusted_rgb[23:16],video_fifo_data[29:24]),
        fade_channel(video_adjusted_rgb[15:8],video_fifo_data[29:24]),
        fade_channel(video_adjusted_rgb[7:0],video_fifo_data[29:24])
    } : 24'd0;
    wire [2:0] fade_level;
    wire fade_switch_enable;
    wire [23:0] video_dimmed_rgb = {
        dim_channel(video_faded_rgb[23:16], fade_level),
        dim_channel(video_faded_rgb[15:8],  fade_level),
        dim_channel(video_faded_rgb[7:0],   fade_level)
    };
    wire [23:0] video_osd_rgb;
    wire [23:0] video_osd_rgb_p1;
    reg [23:0] encoder_rgb;
    reg encoder_de_p1, encoder_de_p2, encoder_de_p3;
    reg encoder_hsync_p1, encoder_hsync_p2, encoder_hsync_p3;
    reg encoder_vsync_p1, encoder_vsync_p2, encoder_vsync_p3;
    wire [9:0] tmds_blue, tmds_green, tmds_red;
    reg [9:0] boundary_h_count_p1, boundary_v_count_p1;
    reg [9:0] boundary_h_count_p2, boundary_v_count_p2;
    reg [9:0] boundary_h_count_p3, boundary_v_count_p3;
    reg boundary_hsync_p1, boundary_vsync_p1, boundary_de_p1;
    reg boundary_hsync_p2, boundary_vsync_p2, boundary_de_p2;
    reg boundary_hsync_p3, boundary_vsync_p3, boundary_de_p3;
    wire sample_tick;
    wire audio_frame_slot;
    // SW1 pauses consumption of song samples. The HDMI transport clock
    // continues; unused slots contain silence, while volume zero is mute.
    wire audio_sample_tick;
    wire [15:0] left_sample, right_sample;
    wire [15:0] volume_left_sample, volume_right_sample;
    wire volume_overrun;
    wire [15:0] hdmi_left_sample = volume_left_sample;
    wire [15:0] hdmi_right_sample = volume_right_sample;
    wire [7:0] audio_level_bars;
    wire [3:0] audio_level;
    wire [15:0] audio_peak_magnitude;
    wire audio_meter_active;
    wire audio_overflow;
    wire [9:0] audio_tmds_blue, audio_tmds_green, audio_tmds_red;
    reg [9:0] serial_blue, serial_green, serial_red;
    reg [25:0] hdmi_heartbeat;
    reg video_ready_p1, video_ready_p2;
    reg video_switch_toggle_p1, video_switch_toggle_p2, video_switch_toggle_seen;
    reg [2:0] osd_image_p1, osd_image_p2;
    reg [2:0] osd_request_p1, osd_request_p2;
    reg [7:0] diag_status_p1, diag_status_p2;
    reg [3:0] diag_progress_p1, diag_progress_p2;
    reg [2:0] diag_load_index_p1, diag_load_index_p2;
    reg [4:0] diag_error_code_p1, diag_error_code_p2;
    reg [2:0] diag_error_source_p1, diag_error_source_p2;
    reg [7:0] diag_cmd0_r1_p1, diag_cmd0_r1_p2;
    reg [3:0] osd_brightness_p1, osd_brightness_p2;
    reg [3:0] osd_contrast_p1, osd_contrast_p2;
    reg [6:0] osd_volume_p1, osd_volume_p2;
    reg osd_volume_select_p1, osd_volume_select_p2;
    reg osd_adjust_mode_p1, osd_adjust_mode_p2;
    reg osd_param_select_p1, osd_param_select_p2;
    reg osd_audio_enable_p1, osd_audio_enable_p2;
    reg emergency_p1, emergency_p2;
    reg osd_ui_active_p1, osd_ui_active_p2;
    reg [1:0] osd_ui_item_p1, osd_ui_item_p2;
    reg osd_ui_guide_p1, osd_ui_guide_p2;
    reg osd_ui_trans_p1, osd_ui_trans_p2;
    reg osd_ui_display_p1, osd_ui_display_p2;

    wire [7:0] diag_status_raw = {
        video_display_active, video_prefill_ready, preload_done_sd,
        image_error_sd, (lookup_error && !music_mode),
        (found || preload_done_sd), (complete || preload_done_sd), mounted
    };
    wire [3:0] diag_progress_raw = {writer_failed, image_done_sd, load_started, init_done};

    wire [2:0] requested_image_control;
    wire request_manual_control, request_right_control;
    wire request_toggle_control;
    // Keep the complete control word in the pixel domain.  This avoids sampling
    // a multi-bit brightness/contrast update across clk_50 -> pixel_clk.
    // At the nominal 27 MHz pixel clock these retain 20 ms debounce and 5 s
    // carousel intervals.  Physical keys/switches retain their synchronizers.
    localparam integer AUTO_INTERVAL_CYCLES = 135_000_000;

    matrix_keypad keypad (
        .clk(pixel_clk), .rst_n(video_rst_n), .row_drive(keypad_row),
        .col_in(keypad_col), .keys_down(matrix_keys),
        .key_prev_n(), .key_next_n(), .key_menu_n(),
        .key_volume_down_n(), .key_volume_up_n(), .key_confirm_n(), .key_back_n(),
        .key_zoom_in_n(), .key_zoom_out_n(), .key_visual_n(),
        .sw_audio_pause(), .sw_zoom_enable()
    );
    ir_nec_keys ir_keys (
        .clk(pixel_clk), .rst_n(video_rst_n), .ir_rx(ir_rx),
        .keys_down(ir_key_bits), .activity(ir_activity), .emergency_active(ir_emergency),
        .emergency_clear(board_emergency_off)
    );
    board_controls board_keys_router (
        .clk(pixel_clk), .rst_n(video_rst_n),
        .k2_n(key_prev_n), .k3_n(key_next_n), .k4_n(key_mode_n),
        .sw1(sw_audio), .sw2(sw_param), .sw3(sw_volume), .sw4(sw_lyrics),
        .zoom_on(zoom_on), .ui_busy(ui_active || ui_guide || ui_trans || adjust_mode),
        .zoom_exit(zoom_exit_req), .keys_down(board_keys), .user_active(board_activity),
        .audio_switch(board_sw1), .zoom_switch(board_sw2), .emergency_switch(board_sw4),
        .zoom_off(board_zoom_off), .audio_changed(board_audio_changed),
        .emergency_off(board_emergency_off)
    );
    media_input_router input_router (
        .clk(pixel_clk), .rst_n(video_rst_n), .matrix_keys(matrix_keys),
        .ir_keys(ir_key_bits), .ir_activity(ir_activity), .ir_emergency(ir_emergency),
        .zoom_context(zoom_on), .zoom_exit(zoom_exit_req | board_zoom_off),
        .audio_clear(board_audio_changed),
        .keys_down(routed_keys), .user_active(user_activity),
        .audio_pause(shared_audio_pause), .zoom_enable(shared_zoom_enable),
        .emergency_enable(ir_emergency_enable)
    );
    eg4_light_sensor light_sensor (
        .clk(pixel_clk), .rst_n(video_rst_n), .sample(light_sample),
        .sample_valid(light_sample_valid)
    );
    ambient_brightness light_control (
        .clk(pixel_clk), .rst_n(video_rst_n), .sample(light_sample),
        .sample_valid(light_sample_valid), .brightness(ambient_brightness),
        .valid(ambient_brightness_valid)
    );

    media_control #(.DEBOUNCE_CYCLES(540_000)) controls (
        .host_valid(host_valid), .host_command(host_command), .host_value(host_value),
        .clk(pixel_clk), .rst_n(video_rst_n),
        .key_prev_n(control_prev_n), .key_next_n(control_next_n), .key_mode_n(control_mode_n),
        .volume_down_n(control_volume_down_n), .volume_up_n(control_volume_up_n),
        .key_menu_n(~control_keys[5]), .key_confirm_n(~control_keys[14]),
        .key_back_n(~control_keys[12]), .key_zoom_in_n(~control_keys[3]),
        .key_zoom_out_n(~control_keys[11]), .key_visual_n(~control_keys[7]),
        .ambient_level(ambient_brightness), .ambient_valid(ambient_brightness_valid),
        .external_activity(user_activity | board_activity),
        .board_zoom_off(board_zoom_off),
        .sw_param(effective_sw_param), .sw_audio(effective_sw_audio),
        .sw_volume(effective_sw_volume),
        .prev_image_press(prev_image_press), .next_image_press(next_image_press),
        .brightness(brightness_reg), .contrast(contrast_reg),
        .brightness_manual(brightness_manual),
        .volume(volume_reg), .volume_select(volume_select), .visual_mode(visual_mode),
        .adjust_mode(adjust_mode), .param_select(param_select),
        .audio_enable(audio_enable),
        .ui_active(ui_active), .ui_item(ui_item), .ui_guide(ui_guide),
        .ui_trans(ui_trans), .ui_display(ui_display), .trans_mode(trans_mode_ui),
        .zoom_menu_active(), .zoom_on(zoom_on), .zoom_exit_req(zoom_exit_req),
        .zoom_span_x(zoom_span_x), .zoom_span_y(zoom_span_y),
        .zoom_win_x(zoom_win_x), .zoom_win_y(zoom_win_y), .pan_axis(pan_axis)
    );

    image_select_control #(
        .AUTO_INTERVAL_CYCLES(AUTO_INTERVAL_CYCLES)
    ) image_selector (
        .clk(pixel_clk), .rst_n(video_rst_n), .ready(video_ready_mem),
        .pause(!host_carousel || ui_active || ui_guide || ui_trans || adjust_mode || zoom_on),
        .prev_press(prev_image_press || (host_valid && host_command == 8'h25)),
        .next_press(next_image_press || (host_valid && host_command == 8'h26)),
        .host_select(host_valid && host_command == 8'h20), .host_image(host_value[2:0]),
        .requested_image(requested_image_control),
        .request_manual(request_manual_control), .request_right(request_right_control),
        .request_toggle(request_toggle_control)
    );

    // The supplied TF media set contains a silent MUSIC.WAV and the actual
    // non-silent 48 kHz program as MUSIC_ON.WAV. Select the latter so the
    // audio path exercises real samples on the board.
    assign current_stem = music_mode ? 64'h4D555349435F4F4E :
                          load_index == 3'd1 ? 64'h4650474130303032 :
                          load_index == 3'd2 ? 64'h4650474130303033 :
                          load_index == 3'd3 ? 64'h4650474130303034 :
                          load_index == 3'd4 ? 64'h4650474130303035 :
                          64'h4650474130303031;
    wire [20:0] current_frame_base_sd = image_frame_base(load_index);

    sys_pll clocks (
        .refclk(clk_50), .reset(!rst_n),
        .clk0_out(), .clk1_out(mem_clk), .clk2_out(mem_clk_sft)
    );

    sd_tf_pll tf_clock (
        .refclk(clk_50), .reset(!rst_n),
        .locked(sd_clk_locked), .clk_40(sd_clk)
    );

    fat32_media_locator #(
        .TARGET_STEM(64'h4650474130303031), .DYNAMIC_TARGET(1),
        .INIT_HALF(250), .READ_HALF(4)
    ) card (
        .clk(sd_clk), .rst_n(core_rst_n), .sd_miso(sd_miso),
        .restart(locator_restart_reg), .runtime_target(current_stem),
        .runtime_extension(music_mode ? 24'h574156 : 24'h424D50),
        .file_pause(file_pause),
        .sd_clk(sd_dclk), .sd_mosi(sd_mosi), .sd_ncs(sd_ncs),
        .mounted(mounted), .complete(complete), .found(found),
        .end_of_dir(), .need_chain(), .error(lookup_error),
        .mount_error_code(mount_error_code), .sd_cmd0_r1(sd_cmd0_r1), .file_cluster(file_cluster),
        .file_size(file_size), .file_start(file_start),
        .file_ready(file_ready), .file_valid(file_valid),
        .file_done(file_done), .file_error(file_error),
        .file_offset(file_offset), .file_data(file_data)
    );

    assign file_start = !locator_restart_reg && complete && found &&
                        !lookup_error && file_ready &&
                        (music_mode ? (audio_enable_sd2 || music_session_started) && !music_started &&
                                      !music_failed && !music_error :
                         !preload_done_sd && !load_started);
    assign locator_restart = locator_restart_reg;

    always @(posedge sd_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            load_index <= 0;
            load_started <= 0;
            preload_done_sd <= 0;
            locator_restart_reg <= 0;
            frame_started_sd <= 0;
            image_done_sd <= 0;
            image_error_sd <= 0;
            file_stream_error_sd <= 0;
            frame_base_sd <= 0;
            frame_done_sd_m1 <= 0;
            frame_done_sd_m2 <= 0;
            frame_done_sd_seen <= 0;
            music_mode <= 0;
            music_started <= 0;
            music_session_started <= 0;
            music_failed <= 0;
            music_failure_code <= 0;
            audio_enable_sd1 <= 0;
            audio_enable_sd2 <= 0;
        end else begin
            frame_started_sd <= 0;
            locator_restart_reg <= 0;
            audio_enable_sd1 <= audio_enable;
            audio_enable_sd2 <= audio_enable_sd1;
            frame_done_sd_m1 <= frame_done;
            frame_done_sd_m2 <= frame_done_sd_m1;
            if (music_mode && (audio_enable_sd2 || music_session_started) && !music_failed) begin
                if (lookup_error) begin music_failed<=1; music_failure_code<=10; end
                else if (complete && !found && !locator_restart_reg) begin
                    music_failed<=1; music_failure_code<=11;
                end else if (music_error) begin
                    music_failed<=1; music_failure_code<=music_error_code;
                end
            end
            if (file_start && music_mode) begin
                music_started <= 1;
                // Preserve the current file/session during pause. Buffered
                // read-ahead may continue until the PCM FIFO applies pressure.
                music_session_started <= 1;
            end
            if (music_done && !music_error) music_started <= 0;
            if (file_start && !music_mode) begin
                load_started <= 1;
                frame_started_sd <= 1;
                frame_base_sd <= current_frame_base_sd;
                image_done_sd <= 0;
                image_error_sd <= 0;
                file_stream_error_sd <= 0;
            end
            if (frame_done_sd_m2 && !frame_done_sd_seen && !preload_done_sd) begin
                frame_done_sd_seen <= 1;
                load_started <= 0;
                image_done_sd <= 0;
                if (load_index == 3'd4) begin
                    preload_done_sd <= 1;
                    music_mode <= 1;
                    locator_restart_reg <= 1;
                end else begin
                    load_index <= load_index + 1'b1;
                    locator_restart_reg <= 1;
                end
            end else if (!frame_done_sd_m2) begin
                frame_done_sd_seen <= 0;
            end
            if (image_done)
                image_done_sd <= 1;
            if (!music_mode && file_error)
                file_stream_error_sd <= 1;
            if (image_error || (!music_mode && file_error))
                image_error_sd <= 1;
        end
    end

    bmp_stream_scaler #(.OUT_WIDTH(720), .OUT_HEIGHT(480)) loader (
        .clk(sd_clk), .rst_n(core_rst_n), .start(file_start && !music_mode),
        .file_size(file_size), .file_valid(file_valid && !music_mode),
        .file_offset(file_offset), .file_data(file_data),
        .file_done(file_done && !music_mode), .file_error(file_error && !music_mode),
        .input_ready(bmp_input_ready), .write_ready(!load_fifo_full),
        .write_en(pixel_valid), .write_addr(pixel_addr),
        .write_rgb(pixel_rgb), .top_down(bmp_top_down),
        .done(image_done), .error(image_error), .error_code(bmp_error_code)
    );

    video_async_fifo #(.ADDR_WIDTH(11), .ALMOST_FULL_MARGIN(1024)) load_fifo (
        .wr_clk(sd_clk), .rd_clk(mem_clk), .rst_n(core_rst_n),
        .wr_en(load_fifo_wr_en), .wr_data({8'b0, pixel_rgb}),
        .full(load_fifo_full), .rd_en(load_fifo_rd_en),
        .rd_data(load_fifo_data), .empty(load_fifo_empty), .almost_full(),
        .used_words()
    );

    always @(posedge mem_clk or posedge mem_rst) begin
        if (mem_rst) begin
            frame_started_m1 <= 0;
            frame_started_mem <= 0;
            frame_base_m1 <= 0;
            frame_base_mem <= 0;
            image_done_m1 <= 0;
            image_done_mem <= 0;
            image_error_m1 <= 0;
            image_error_mem <= 0;
            preload_done_m1 <= 0;
            preload_done_mem <= 0;
            bmp_top_down_m1 <= 0;
            bmp_top_down_mem <= 0;
            requested_image_m1 <= 0;
            requested_image_m2 <= 0;
            requested_image_mem <= 0;
            request_manual_m1<=0;request_manual_m2<=0;request_manual_mem<=0;
            request_right_m1<=0;request_right_m2<=0;request_right_mem<=0;
            request_toggle_m1<=0;request_toggle_m2<=0;request_toggle_m3<=0;request_toggle_seen<=0;
            selected_image_mem <= 0;
            video_fifo_flush <= 0;
            video_switch_toggle <= 0;
            video_switch_pending <= 0;
            video_switch_ack_m1 <= 0;
            video_switch_ack_mem <= 0;
            video_app_rd_seen <= 0;
            video_rd_valid_seen <= 0;
            video_fifo_wr_seen <= 0;
            video_fifo_full_seen <= 0;
            video_app_rd_after_full_seen <= 0;
            video_rd_valid_after_full_seen <= 0;
            video_fifo_wr_after_full_seen <= 0;
            video_prefill_count <= 0;
            video_prefill_ready <= 0;
        end else begin
            frame_started_m1 <= frame_started_sd;
            frame_started_mem <= frame_started_m1;
            frame_base_m1 <= frame_base_sd;
            frame_base_mem <= frame_base_m1;
            image_done_m1 <= image_done_sd;
            image_done_mem <= frame_started_mem ? 1'b0 : image_done_m1;
            image_error_m1 <= image_error_sd;
            image_error_mem <= frame_started_mem ? 1'b0 : image_error_m1;
            preload_done_m1 <= preload_done_sd;
            preload_done_mem <= preload_done_m1;
            bmp_top_down_m1 <= bmp_top_down;
            bmp_top_down_mem <= bmp_top_down_m1;
            requested_image_m1 <= requested_image_control;
            requested_image_m2 <= requested_image_m1;
            request_manual_m1<=request_manual_control;request_manual_m2<=request_manual_m1;
            request_right_m1<=request_right_control;request_right_m2<=request_right_m1;
            request_toggle_m1<=request_toggle_control;
            request_toggle_m2<=request_toggle_m1;
            request_toggle_m3<=request_toggle_m2;
            // Key events are separated by debounce milliseconds. Delay the
            // event one stage beyond the payload, then commit target + kind +
            // direction together, avoiding a transient hard cut on a key press.
            if(request_toggle_m3!=request_toggle_seen) begin
                request_toggle_seen<=request_toggle_m3;
                requested_image_mem<=requested_image_m2;
                request_manual_mem<=request_manual_m2;
                request_right_mem<=request_right_m2;
            end
            video_switch_ack_m1 <= video_switch_toggle_seen;
            video_switch_ack_mem <= video_switch_ack_m1;
            if(slide_done_mem)
                selected_image_mem<=slide_completed_image_mem;
            if (video_fifo_flush && prefetch_restart_done) begin
                // Keep the old base through the final in-flight burst. The new
                // base becomes visible only after all old SDRAM returns drained.
                selected_image_mem <= requested_image_mem;
                video_fifo_flush <= 0;
            end
            if (preload_done_mem && requested_image_mem != selected_image_mem &&
                !video_fifo_flush && !video_switch_pending && !slide_active_mem &&
                !video_prefill_ready) begin
                video_switch_pending <= 1;
                video_switch_toggle <= ~video_switch_toggle;
                video_prefill_count <= 0;
                video_prefill_ready <= 0;
            end
            // The pixel-domain acknowledgement is sent only after display reads stop.
            if (video_switch_pending && video_switch_ack_mem == video_switch_toggle) begin
                video_switch_pending <= 0;
                video_fifo_flush <= 1;
                video_prefill_count <= 0;
            end
            if (frame_done) begin
                if (app_rd_en)
                    video_app_rd_seen <= 1;
                if (sdram_rd_valid)
                    video_rd_valid_seen <= 1;
                if (video_fifo_wr_en)
                    video_fifo_wr_seen <= 1;
                if (video_fifo_full)
                    video_fifo_full_seen <= 1;
                if (video_fifo_full_seen && app_rd_en)
                    video_app_rd_after_full_seen <= 1;
                if (video_fifo_full_seen && sdram_rd_valid)
                    video_rd_valid_after_full_seen <= 1;
                if (video_fifo_full_seen && video_fifo_wr_en)
                    video_fifo_wr_after_full_seen <= 1;
                if (preload_done_mem && requested_image_mem == selected_image_mem &&
                    !video_switch_pending && !video_fifo_flush &&
                    !video_prefill_ready && video_fifo_wr_en) begin
                    if (video_prefill_count == VIDEO_PREFILL_WORDS - 1) begin
                        video_prefill_ready <= 1;
                    end else begin
                        video_prefill_count <= video_prefill_count + 1'b1;
                    end
                end
            end
        end
    end

    tf_sdram_frame_writer #(.FRAME_WORDS(FRAME_WORDS), .FRAME_WIDTH(720)) writer (
        .clk(mem_clk), .rst(mem_rst),
        .frame_started(frame_started_mem), .image_done(image_done_mem),
        .frame_base(frame_base_mem), .top_down(bmp_top_down_mem),
        .image_error(image_error_mem), .fifo_empty(load_fifo_empty),
        .fifo_rd_en(load_fifo_rd_en), .fifo_rd_data(load_fifo_data),
        .init_done(init_done), .refresh(refresh), .busy(sdram_busy),
        .app_wr_en(app_wr_en), .app_wr_addr(app_wr_addr),
        .app_wr_data(app_wr_data), .frame_done(frame_done),
        .failed(writer_failed), .write_count(write_count)
    );

    apug011_transition_prefetch #(
        .FRAME_WORDS(FRAME_WORDS), .FRAME_WIDTH(720), .BURST_WORDS(256), .LOOP_FRAME(1), .SLIDE_STEP(32)
    ) prefetch (
        .clk(mem_clk), .rst(mem_rst), .enable(video_prefetch_enable),
        .restart(video_prefetch_restart),
        .frame_base(selected_frame_base_mem),
        // CORNERS mode keeps the auto corner/centre geometry; SLIDE and FADE
        // use the short horizontal slide (hidden behind the black for FADE).
        .slide_request(transition_request),
        .request_manual(trans_mode_m2 == 2'd0 ? 1'b0 : 1'b1),
        .slide_right(request_right_mem),
        // SW2/SW3 full-screen zoom view; the minimap shows its viewport.
        .zoom_mode(zoom_on), .zoom_span_x(zoom_span_x), .zoom_span_y(zoom_span_y),
        .zoom_win_x(zoom_win_x), .zoom_win_y(zoom_win_y),
        .slide_target_base(requested_frame_base_mem), .slide_target_image(requested_image_mem),
        .slide_active(slide_active_mem), .slide_done(slide_done_mem),
        .slide_completed_image(slide_completed_image_mem), .slide_offset(),
        .init_done(init_done), .refresh(refresh), .busy(sdram_busy),
        .app_rd_en(app_rd_en), .app_rd_addr(app_rd_addr),
        .rd_valid(sdram_rd_valid), .rd_data(sdram_rd_data),
        .fifo_full(video_fifo_full), .fifo_almost_full(video_fifo_almost_full),
        .fifo_used_words(video_fifo_used_words),
        .fifo_wr_en(video_fifo_wr_en), .fifo_wr_data(video_fifo_wr_data),
        .done(prefetch_done), .restart_done(prefetch_restart_done)
    );

    video_async_fifo #(.ADDR_WIDTH(11), .ALMOST_FULL_MARGIN(256)) video_fifo (
        .wr_clk(mem_clk), .rd_clk(pixel_clk), .rst_n(video_fifo_rst_n),
        .wr_en(video_fifo_wr_en), .wr_data(video_fifo_wr_data),
        .full(video_fifo_full), .rd_en(video_fifo_rd_en),
        .rd_data(video_fifo_data), .empty(video_fifo_empty),
        .almost_full(video_fifo_almost_full), .used_words(video_fifo_used_words)
    );

    sdr_as_ram #(.self_refresh_open(1'b1)) sdram_controller (
        .Sdr_clk(mem_clk), .Sdr_clk_sft(mem_clk_sft), .Rst(mem_rst),
        .Sdr_init_done(init_done), .Sdr_init_ref_vld(refresh),
        .Sdr_busy(sdram_busy), .App_ref_req(1'b0),
        .App_wr_en(app_wr_en), .App_wr_addr(app_wr_addr),
        .App_wr_dm(4'b0000), .App_wr_din(app_wr_data),
        .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdram_rd_valid), .Sdr_rd_dout(sdram_rd_data),
        .SDRAM_CLK(sdram_clk), .SDR_RAS(sdram_ras_n),
        .SDR_CAS(sdram_cas_n), .SDR_WE(sdram_we_n),
        .SDR_BA(sdram_ba), .SDR_ADDR(sdram_addr), .SDR_DM(sdram_dm),
        .SDR_DQ(sdram_dq)
    );

    hdmi_video_pll27 video_pll (
        .refclk(clk_50), .reset(!rst_n), .extlock(video_pll_locked),
        .clk0_out(pixel_clk), .clk1_out(serial_clk_5x)
    );

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n || !video_pll_locked) begin
            video_ready_p1 <= 1'b0;
            video_ready_p2 <= 1'b0;
            video_switch_toggle_p1 <= 1'b0;
            video_switch_toggle_p2 <= 1'b0;
            video_switch_toggle_seen <= 1'b0;
            osd_image_p1 <= 2'd0;
            osd_image_p2 <= 2'd0;
            osd_request_p1 <= 2'd0;
            osd_request_p2 <= 2'd0;
            diag_status_p1 <= 8'd0;
            diag_status_p2 <= 8'd0;
            diag_progress_p1 <= 4'd0;
            diag_progress_p2 <= 4'd0;
            diag_load_index_p1 <= 2'd0;
            diag_load_index_p2 <= 2'd0;
            diag_error_code_p1 <= 5'd0;
            diag_error_code_p2 <= 5'd0;
            diag_error_source_p1 <= 3'd0;
            diag_error_source_p2 <= 3'd0;
            diag_cmd0_r1_p1 <= 8'hff;
            diag_cmd0_r1_p2 <= 8'hff;
            osd_brightness_p1 <= 4'd5;
            osd_brightness_p2 <= 4'd5;
            osd_contrast_p1 <= 4'd5;
            osd_contrast_p2 <= 4'd5;
            osd_volume_p1 <= 7'd50;
            osd_volume_p2 <= 7'd50;
            osd_volume_select_p1 <= 1'b0;
            osd_volume_select_p2 <= 1'b0;
            osd_adjust_mode_p1 <= 1'b0;
            osd_adjust_mode_p2 <= 1'b0;
            osd_param_select_p1 <= 1'b0;
            osd_param_select_p2 <= 1'b0;
            osd_audio_enable_p1 <= 1'b0;
            osd_audio_enable_p2 <= 1'b0;
            emergency_p1 <= 1'b0;
            emergency_p2 <= 1'b0;
            osd_ui_active_p1 <= 1'b0;
            osd_ui_active_p2 <= 1'b0;
            osd_ui_item_p1 <= 2'd0;
            osd_ui_item_p2 <= 2'd0;
            osd_ui_guide_p1 <= 1'b0;
            osd_ui_guide_p2 <= 1'b0;
            osd_ui_trans_p1 <= 1'b0;
            osd_ui_trans_p2 <= 1'b0;
            osd_ui_display_p1 <= 1'b0;
            osd_ui_display_p2 <= 1'b0;
            fade_en_m1 <= 1'b0;
            fade_en_m2 <= 1'b0;
            trans_mode_m1 <= 2'd2;
            trans_mode_m2 <= 2'd2;
            music_failed_p1 <= 0;
            music_failed_p2 <= 0;
            music_code_p1 <= 0;
            music_code_p2 <= 0;
            video_reset_sync <= 0;
            video_display_active <= 0;
            video_app_rd_p1 <= 0;
            video_app_rd_p2 <= 0;
            video_rd_valid_p1 <= 0;
            video_rd_valid_p2 <= 0;
            video_fifo_wr_p1 <= 0;
            video_fifo_wr_p2 <= 0;
            video_fifo_full_p1 <= 0;
            video_fifo_full_p2 <= 0;
            video_app_rd_after_full_p1 <= 0;
            video_app_rd_after_full_p2 <= 0;
            video_rd_valid_after_full_p1 <= 0;
            video_rd_valid_after_full_p2 <= 0;
            video_fifo_wr_after_full_p1 <= 0;
            video_fifo_wr_after_full_p2 <= 0;
            video_fifo_nonempty_seen <= 0;
            video_fifo_empty_seen <= 0;
        end else begin
            video_ready_p1 <= video_ready_mem;
            video_ready_p2 <= video_ready_p1;
            video_switch_toggle_p1 <= video_switch_toggle;
            video_switch_toggle_p2 <= video_switch_toggle_p1;
            osd_image_p1 <= selected_image_mem;
            osd_image_p2 <= osd_image_p1;
            osd_request_p1 <= requested_image_mem;
            osd_request_p2 <= osd_request_p1;
            diag_status_p1 <= diag_status_raw;
            diag_status_p2 <= diag_status_p1;
            diag_progress_p1 <= diag_progress_raw;
            diag_progress_p2 <= diag_progress_p1;
            diag_load_index_p1 <= load_index;
            diag_load_index_p2 <= diag_load_index_p1;
            diag_error_code_p1 <= mount_error_code != 0 ? mount_error_code :
                                  file_stream_error_sd ? 5'd6 :
                                  image_error_sd ? bmp_error_code[4:0] :
                                  music_failed_p2 ? music_code_p2 : 5'd0;
            diag_error_code_p2 <= diag_error_code_p1;
            diag_error_source_p1 <= mount_error_code != 0 ? (mount_error_code<16 ? 3'd1 : 3'd2) :
                                    file_stream_error_sd ? 3'd4 :
                                    image_error_sd ? 3'd3 :
                                    music_failed_p2 ? 3'd6 :
                                    (lookup_error && !music_mode) ? 3'd2 :
                                    writer_failed ? 3'd5 : 3'd0;
            diag_error_source_p2 <= diag_error_source_p1;
            diag_cmd0_r1_p1 <= sd_cmd0_r1;
            diag_cmd0_r1_p2 <= diag_cmd0_r1_p1;
            osd_brightness_p1 <= effective_brightness;
            osd_brightness_p2 <= osd_brightness_p1;
            osd_contrast_p1 <= contrast_reg;
            osd_contrast_p2 <= osd_contrast_p1;
            osd_volume_p1 <= volume_reg;
            osd_volume_p2 <= osd_volume_p1;
            osd_volume_select_p1 <= volume_select;
            osd_volume_select_p2 <= osd_volume_select_p1;
            osd_adjust_mode_p1 <= adjust_mode;
            osd_adjust_mode_p2 <= osd_adjust_mode_p1;
            osd_param_select_p1 <= param_select;
            osd_param_select_p2 <= osd_param_select_p1;
            osd_audio_enable_p1 <= audio_enable;
            osd_audio_enable_p2 <= osd_audio_enable_p1;
            emergency_p1 <= effective_sw_lyrics;
            emergency_p2 <= emergency_p1;
            osd_ui_active_p1 <= ui_active;
            osd_ui_active_p2 <= osd_ui_active_p1;
            osd_ui_item_p1 <= ui_item;
            osd_ui_item_p2 <= osd_ui_item_p1;
            osd_ui_guide_p1 <= ui_guide;
            osd_ui_guide_p2 <= osd_ui_guide_p1;
            osd_ui_trans_p1 <= ui_trans;
            osd_ui_trans_p2 <= osd_ui_trans_p1;
            osd_ui_display_p1 <= ui_display;
            osd_ui_display_p2 <= osd_ui_display_p1;
            fade_en_m1 <= fade_switch_enable;
            fade_en_m2 <= fade_en_m1;
            trans_mode_m1 <= trans_mode_ui;
            trans_mode_m2 <= trans_mode_m1;
            music_failed_p1 <= music_failed;
            music_failed_p2 <= music_failed_p1;
            music_code_p1 <= music_failure_code[4:0];
            music_code_p2 <= music_code_p1;
            video_app_rd_p1 <= video_app_rd_seen;
            video_app_rd_p2 <= video_app_rd_p1;
            video_rd_valid_p1 <= video_rd_valid_seen;
            video_rd_valid_p2 <= video_rd_valid_p1;
            video_fifo_wr_p1 <= video_fifo_wr_seen;
            video_fifo_wr_p2 <= video_fifo_wr_p1;
            video_fifo_full_p1 <= video_fifo_full_seen;
            video_fifo_full_p2 <= video_fifo_full_p1;
            video_app_rd_after_full_p1 <= video_app_rd_after_full_seen;
            video_app_rd_after_full_p2 <= video_app_rd_after_full_p1;
            video_rd_valid_after_full_p1 <= video_rd_valid_after_full_seen;
            video_rd_valid_after_full_p2 <= video_rd_valid_after_full_p1;
            video_fifo_wr_after_full_p1 <= video_fifo_wr_after_full_seen;
            video_fifo_wr_after_full_p2 <= video_fifo_wr_after_full_p1;
            if (video_rst_n && video_display_active && de) begin
                if (video_fifo_empty)
                    video_fifo_empty_seen <= 1;
                else
                    video_fifo_nonempty_seen <= 1;
            end
            video_reset_sync <= {video_reset_sync[0], 1'b1};
            if (video_switch_toggle_p2 != video_switch_toggle_seen) begin
                video_switch_toggle_seen <= video_switch_toggle_p2;
                video_display_active <= 0;
            end else if (video_ready_p2 && h_count == 10'd857 && v_count == 10'd524)
                video_display_active <= 1;
        end
    end
    assign video_rst_n = video_reset_sync[1];

    // Fade-to-black transition (FADE mode only); CORNERS/SLIDE leave level at 0
    // and let the geometric transition run. switch_enable holds the frame
    // switch until the fade-out is fully black.
    wire fade_frame_tick = (h_count == 10'd0) && (v_count == 10'd0);
    fade_transition #(.STEP_FRAMES(3), .START_TIMEOUT_FRAMES(30)) fade (
        .clk(pixel_clk), .rst_n(video_rst_n),
        .frame_tick(fade_frame_tick),
        .request_toggle(request_toggle_control),
        .mode(trans_mode_ui),
        .slide_active(slide_active_mem),
        .level(fade_level),
        .switch_enable(fade_switch_enable)
    );

    hdmi_timing_media timing (
        .pixel_clk(pixel_clk), .rst_n(video_rst_n),
        .hsync(hsync), .vsync(vsync), .de(de), .rgb(timing_rgb),
        .h_count(h_count), .v_count(v_count)
    );

    // P6 maintainability: explicit self-check summary and a latched fault log.
    // fault_active mirrors the existing error bits; nothing here retries or
    // hides the fault.
    assign fault_active = (diag_error_code_p2 != 0) || diag_status_p2[3] ||
                          diag_status_p2[4] || diag_progress_p2[3];
    assign self_ok = mounted && found && complete && preload_done_sd &&
                     video_prefill_ready && video_display_active &&
                     !lookup_error && !image_error_sd && !writer_failed &&
                     !fault_active;
    fault_log fault_record (
        .clk(pixel_clk), .rst_n(video_rst_n),
        .fault_active(fault_active),
        .fault_source(diag_error_source_p2), .fault_code(diag_error_code_p2),
        .held(fault_held), .held_source(fault_source),
        .held_code(fault_code), .count(fault_count)
    );

    wire [23:0] video_zoom_rgb;
    // Show the viewport indicator only after SW3 has actually magnified
    // (1.0x = zoom_span 720 means "SW2 on but no magnification yet").
    wire zoom_minimap_en = zoom_on && (zoom_span_x != 10'd720);
    zoom_minimap zoom_view (
        .clk(pixel_clk), .rst_n(video_rst_n),
        .enable(zoom_minimap_en), .win_x(zoom_win_x), .win_y(zoom_win_y),
        .span_x(zoom_span_x), .span_y(zoom_span_y),
        .de(de), .h_count(h_count), .v_count(v_count),
        .rgb_in(video_dimmed_rgb), .rgb_out(video_zoom_rgb)
    );

    hdmi_osd_5x7 osd (
        .de(de), .h_count(h_count), .v_count(v_count),
        .video_rgb(video_zoom_rgb), .image_index(osd_image_p2),
        .requested_index(osd_request_p2), .progress_bits(diag_progress_p2),
        .status_bits(diag_status_p2), .load_index(diag_load_index_p2),
        .error_code(diag_error_code_p2),
        .error_source(diag_error_source_p2), .cmd0_r1(diag_cmd0_r1_p2),
        .audio_playing(osd_audio_enable_p2 && music_playing),
        .audio_error(osd_audio_enable_p2 && (music_fault || music_failed_p2)),
        .audio_enabled(osd_audio_enable_p2),
        .audio_code(music_code_p2),
        .adjust_mode(osd_adjust_mode_p2), .param_select(osd_param_select_p2),
        .brightness(osd_brightness_p2), .contrast(osd_contrast_p2),
        .volume(osd_volume_p2), .volume_select(osd_volume_select_p2),
        .ui_active(osd_ui_active_p2), .ui_item(osd_ui_item_p2),
        .ui_guide(osd_ui_guide_p2), .ui_trans(osd_ui_trans_p2),
        .ui_display(osd_ui_display_p2),
        .zoom_mode(zoom_on),
        .accent_color(accent_color),
        .fault_held(fault_held), .fault_source(fault_source),
        .fault_code(fault_code), .fault_count(fault_count),
        .self_ok(self_ok),
        .rgb_out(video_osd_rgb)
    );

    wire [7:0] subtitle_byte, subtitle_ack;
    wire subtitle_byte_valid, subtitle_rx_error, subtitle_ack_valid;
    wire subtitle_tx_busy;
    always @(posedge pixel_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin host_carousel <= 1; host_audio_pause <= 0; end
        else if (host_valid) begin
            if (host_command == 8'h24) host_carousel <= host_value[0];
            if (host_command == 8'h29) host_audio_pause <= host_value[0];
        end
    end
    wire [7:0] host_flags = {ambient_brightness_valid, host_audio_pause, zoom_on,
        fault_active, video_ready_p2, audio_enable, host_carousel, brightness_manual};
    wire [95:0] host_status = {8'd2, {5'd0,osd_image_p2},
        {5'd0,requested_image_control}, {1'b0,volume_reg}, {4'd0,brightness_reg},
        {4'd0,contrast_reg}, host_flags, {4'd0,light_sample[11:8]}, light_sample[7:0],
        {6'd0,trans_mode_ui}, {6'd0,visual_mode}, {3'd0,fault_code}};
    subtitle_uart subtitle_port (
        .clk(pixel_clk), .rst_n(video_rst_n), .rx(subtitle_rx),
        .rx_data(subtitle_byte), .rx_valid(subtitle_byte_valid), .rx_error(subtitle_rx_error),
        .tx_data(subtitle_ack), .tx_valid(subtitle_ack_valid), .tx(subtitle_tx), .tx_busy(subtitle_tx_busy)
    );
    museum_subtitle subtitle (
        .tx_busy(subtitle_tx_busy), .control_status(host_status),
        .control_valid(host_valid), .control_command(host_command), .control_value(host_value),
        .clk(pixel_clk), .rst_n(video_rst_n),
        .rx_data(subtitle_byte), .rx_valid(subtitle_byte_valid), .rx_error(subtitle_rx_error),
        .tx_data(subtitle_ack), .tx_valid(subtitle_ack_valid),
        .show(video_display_active && !zoom_on && !fault_active),
        .de(de), .h_count(h_count), .v_count(v_count),
        .rgb_in(video_osd_rgb), .rgb_out(video_osd_rgb_p1)
    );

    // Observe volume-scaled HDMI PCM without controlling its sample flow.
    wire [223:0] spectrum_levels;
    wire wave_front_bank,wave_accept,wave_pending,wave_pending_bank;
    wire [9:0] wave_density;
    wire [15:0] wave_data;
    wire [7:0] wave_start,wave_view_start;
    wire [9:0] wave_x_ahead=boundary_h_count_p1-10'd296;
    wire [7:0] wave_column_ahead=wave_x_ahead/10'd3;
    wire [23:0] spectrum_rgb;
    audio_spectrum_fft spectrum_analyzer (
        .clk(pixel_clk), .rst_n(video_rst_n), .sample_valid(audio_sample_tick),
        .left_sample(hdmi_left_sample), .right_sample(hdmi_right_sample),
        .levels(spectrum_levels), .magnitudes(), .result_valid(), .analyzing(),
        .wave_front_bank(wave_front_bank), .wave_accept(wave_accept), .wave_read_address(wave_view_start+wave_column_ahead),
        .wave_read_data(wave_data), .wave_pending(wave_pending), .wave_pending_bank(wave_pending_bank), .wave_density(wave_density), .wave_start(wave_start)
    );
    // P2 audio-visual link: band energy drives the OSD accent colour only.
    // Picture brightness is NOT coupled to audio (SW1 keeps play/pause only).
    audio_visual_link visual_link (
        .clk(pixel_clk), .rst_n(video_rst_n),
        .sample_tick(audio_sample_tick),
        .active(osd_audio_enable_p2 && music_playing && !music_fault && !music_failed_p2),
        .levels(spectrum_levels),
        .accent_color(accent_color)
    );
    // Audio enable controls the spectrum panel; SW4 controls emergency only.
    // Framebuffer read + lyric RGB register delay the picture by two clocks.
    // Match that RGB to boundary_*_p2 before the existing encoder register.
    audio_spectrum_overlay spectrum_panel (
        .clk(pixel_clk), .rst_n(video_rst_n), .enable_switch(audio_enable),
        .video_ready(video_display_active),
        .audible(osd_audio_enable_p2 && music_playing && !music_fault && !music_failed_p2),
        .volume_percent(osd_volume_p2), .levels(spectrum_levels), .visual_mode(visual_mode),
        .sample_tick(audio_sample_tick), .sample_left(hdmi_left_sample), .sample_right(hdmi_right_sample),
        .wave_data(wave_data), .wave_pending(wave_pending), .wave_pending_bank(wave_pending_bank),
        .wave_density(wave_density), .wave_start(wave_start), .wave_view_start(wave_view_start), .wave_front_bank(wave_front_bank), .wave_accept(wave_accept),
        .de(boundary_de_p2), .h_count(boundary_h_count_p2), .v_count(boundary_v_count_p2),
        .rgb_in(video_osd_rgb_p1), .rgb_out(spectrum_rgb), .visible()
    );

    // Startup artwork is independent of TF media. Preserve readable errors
    // and remove it on the first visible image frame; never re-arm on a slide.
    wire [23:0] startup_rgb;
    wire startup_load_error = fault_active;
    startup_ai_overlay startup_logo (
        .clk(pixel_clk), .rst_n(video_rst_n),
        .media_visible(video_display_active), .load_error(startup_load_error),
        .de(boundary_de_p2), .h_count(boundary_h_count_p2), .v_count(boundary_v_count_p2),
        .rgb_in(spectrum_rgb), .rgb_out(startup_rgb), .active()
    );

    // Emergency exit sign (SW4 high): highest-priority overlay. It replaces
    // every active pixel after all other overlays, so menus, zoom, lyrics,
    // spectrum, fault cards and startup art are all hidden.
    wire [23:0] emergency_rgb;
    emergency_picture emergency (
        .clk(pixel_clk), .rst_n(video_rst_n), .enable(emergency_p2),
        .de(boundary_de_p2), .h_count(boundary_h_count_p2), .v_count(boundary_v_count_p2),
        .rgb_in(startup_rgb), .rgb_out(emergency_rgb)
    );

    // FIFO data becomes valid after its read edge, so delay timing controls
    // by two pixel clocks before the TMDS encoder captures that RGB word.
    always @(posedge pixel_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            encoder_rgb <= 0;
            encoder_de_p1 <= 0;
            encoder_de_p2 <= 0;
            encoder_de_p3 <= 0;
            encoder_hsync_p1 <= 1;
            encoder_hsync_p2 <= 1;
            encoder_hsync_p3 <= 1;
            encoder_vsync_p1 <= 1;
            encoder_vsync_p2 <= 1;
            encoder_vsync_p3 <= 1;
            boundary_h_count_p1 <= 0;
            boundary_h_count_p2 <= 0;
            boundary_h_count_p3 <= 0;
            boundary_v_count_p2 <= 0;
            boundary_v_count_p1 <= 0;
            boundary_hsync_p1 <= 1;
            boundary_vsync_p1 <= 1;
            boundary_de_p1 <= 0;
            boundary_hsync_p2 <= 1;
            boundary_vsync_p2 <= 1;
            boundary_de_p2 <= 0;
            boundary_hsync_p3 <= 1;
            boundary_vsync_p3 <= 1;
            boundary_de_p3 <= 0;
        end else begin
            encoder_rgb <= emergency_p2 ? emergency_rgb : startup_rgb;
            encoder_de_p1 <= de;
            encoder_de_p2 <= encoder_de_p1;
            encoder_de_p3 <= encoder_de_p2;
            encoder_hsync_p1 <= hsync;
            encoder_hsync_p2 <= encoder_hsync_p1;
            encoder_hsync_p3 <= encoder_hsync_p2;
            encoder_vsync_p1 <= vsync;
            encoder_vsync_p2 <= encoder_vsync_p1;
            encoder_vsync_p3 <= encoder_vsync_p2;
            boundary_h_count_p1 <= h_count;
            boundary_h_count_p2 <= boundary_h_count_p1;
            boundary_h_count_p3 <= boundary_h_count_p2;
            boundary_v_count_p1 <= v_count;
            boundary_v_count_p2 <= boundary_v_count_p1;
            boundary_v_count_p3 <= boundary_v_count_p2;
            boundary_hsync_p1 <= hsync;
            boundary_vsync_p1 <= vsync;
            boundary_de_p1 <= de;
            boundary_hsync_p2 <= boundary_hsync_p1;
            boundary_vsync_p2 <= boundary_vsync_p1;
            boundary_de_p2 <= boundary_de_p1;
            boundary_hsync_p3 <= boundary_hsync_p2;
            boundary_vsync_p3 <= boundary_vsync_p2;
            boundary_de_p3 <= boundary_de_p2;
        end
    end

    tmds_encoder blue_encoder (
        .pixel_clk(pixel_clk), .rst_n(video_rst_n), .de(encoder_de_p3),
        .c0(encoder_hsync_p3), .c1(encoder_vsync_p3),
        .data_in(encoder_rgb[7:0]), .tmds_out(tmds_blue)
    );
    tmds_encoder green_encoder (
        .pixel_clk(pixel_clk), .rst_n(video_rst_n), .de(encoder_de_p3),
        .c0(1'b0), .c1(1'b0), .data_in(encoder_rgb[15:8]), .tmds_out(tmds_green)
    );
    tmds_encoder red_encoder (
        .pixel_clk(pixel_clk), .rst_n(video_rst_n), .de(encoder_de_p3),
        .c0(1'b0), .c1(1'b0), .data_in(encoder_rgb[23:16]), .tmds_out(tmds_red)
    );

    wav_audio_player music (
        .sd_clk(sd_clk), .pixel_clk(pixel_clk), .rst_n(core_rst_n && video_rst_n),
        .play_enable(osd_audio_enable_p2 && !emergency_p2),
        .start(file_start && music_mode), .file_size(file_size),
        .file_valid(file_valid && music_mode), .file_offset(file_offset),
        .file_data(file_data), .file_done(file_done && music_mode),
        .file_error(file_error && music_mode), .input_ready(music_input_ready),
        .done(music_done), .error(music_error), .error_code(music_error_code),
        .playing(music_playing), .fault(music_fault), .sample_valid(sample_tick),
        .sample_slot(audio_frame_slot),
        .left_sample(left_sample), .right_sample(right_sample)
    );
    wire [15:0] selected_left_sample, selected_right_sample;
    emergency_audio_mux emergency_sound (
        .clk(pixel_clk), .rst_n(video_rst_n), .enable(emergency_p2),
        .sample_slot(audio_frame_slot), .music_valid(sample_tick),
        .music_left(left_sample), .music_right(right_sample),
        .left_out(selected_left_sample), .right_out(selected_right_sample)
    );
    pcm_volume_control volume_scaler (
        .clk(pixel_clk), .rst_n(video_rst_n),
        .sample_valid(audio_frame_slot),
        .left_sample(selected_left_sample),
        .right_sample(selected_right_sample),
        .volume_percent(osd_volume_p2), .sample_valid_out(audio_sample_tick),
        .left_out(volume_left_sample), .right_out(volume_right_sample),
        .busy(), .overrun(volume_overrun)
    );
    // The boundary is fed from the same two-stage raster taps that feed the registered
    // TMDS encoders (boundary_*_p2 and the encoder_*_p2 control signals), so both share
    // one phase reference and no pipeline offset is needed. The boundary registers the
    // preamble and the guard before substituting them, which is what puts them on the
    // wire immediately before the next active line.
    hdmi_audio_video_boundary #(
        .VIDEO_PIPELINE_OFFSET(0), .H_ACTIVE(720), .H_TOTAL(858),
        .V_ACTIVE(480), .V_TOTAL(525), .PIXEL_HZ(27000000), .VIC(3), .ASPECT(8'h20)
    ) audio_boundary (
        .pixel_clk(pixel_clk), .rst(!video_rst_n),
        .h_count(boundary_h_count_p3), .v_count(boundary_v_count_p3),
        .hsync(encoder_hsync_p3), .vsync(encoder_vsync_p3),
        .de(encoder_de_p3),
        .video_tmds_ch0(tmds_blue), .video_tmds_ch1(tmds_green),
        .video_tmds_ch2(tmds_red),
        .sample_valid(audio_sample_tick), .left_sample(hdmi_left_sample),
        .right_sample(hdmi_right_sample),
        .tmds_ch0(audio_tmds_blue), .tmds_ch1(audio_tmds_green),
        .tmds_ch2(audio_tmds_red), .fifo_level(),
        .overflow(audio_overflow)
    );

    // Stage the data-island mux result in the pixel domain before the 135 MHz
    // serializer captures it on its falling edge.
    always @(posedge pixel_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            serial_blue <= 10'b1101010100;
            serial_green <= 10'b1101010100;
            serial_red <= 10'b1101010100;
        end else begin
            serial_blue <= audio_tmds_blue;
            serial_green <= audio_tmds_green;
            serial_red <= audio_tmds_red;
        end
    end

    tmds_serializer_5x clock_serializer (
        .serial_clk(serial_clk_5x), .rst_n(rst_n && video_pll_locked),
        .tmds_word(10'b0000011111), .tmds_p(HDMI_CLK_P)
    );
    tmds_serializer_5x blue_serializer (
        .serial_clk(serial_clk_5x), .rst_n(rst_n && video_pll_locked),
        .tmds_word(serial_blue), .tmds_p(HDMI_D0_P)
    );
    tmds_serializer_5x green_serializer (
        .serial_clk(serial_clk_5x), .rst_n(rst_n && video_pll_locked),
        .tmds_word(serial_green), .tmds_p(HDMI_D1_P)
    );
    tmds_serializer_5x red_serializer (
        .serial_clk(serial_clk_5x), .rst_n(rst_n && video_pll_locked),
        .tmds_word(serial_red), .tmds_p(HDMI_D2_P)
    );

    always @(posedge serial_clk_5x or negedge rst_n) begin
        if (!rst_n) begin
            hdmi_heartbeat <= 0;
        end else begin
            hdmi_heartbeat <= hdmi_heartbeat + 1'b1;
        end
    end

    // Blink requires the actual HDMI serial clock, not only its PLL lock flag.
    assign led = !sd_clk_locked || !video_pll_locked || lookup_error || image_error_sd || writer_failed || audio_overflow || volume_overrun || music_failed ?
                 1'b1 :
                 !frame_done ? 1'b0 :
                 hdmi_heartbeat[25];
endmodule
