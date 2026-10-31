module hdmi_osd_5x7 (
    input  wire        de,
    input  wire [9:0]  h_count,
    input  wire [9:0]  v_count,
    input  wire [23:0] video_rgb,
    input  wire [2:0]  image_index,
    input  wire [2:0]  requested_index,
    input  wire [7:0]  status_bits,
    input  wire [3:0]  progress_bits,
    input  wire [2:0]  load_index,
    input  wire [4:0]  error_code,
    input  wire [2:0]  error_source, // 1 SD, 2 FS, 3 BMP, 4 IO, 5 memory
    input  wire [7:0]  cmd0_r1,
    input  wire        audio_playing,
    input  wire        audio_error,
    input  wire        audio_enabled,
    input  wire [4:0]  audio_code,
    input  wire        adjust_mode,
    input  wire        param_select,
    input  wire [3:0]  brightness,
    input  wire [3:0]  contrast,
    input  wire [6:0]  volume,
    input  wire        volume_select,
    input  wire        ui_active,
    input  wire [1:0]  ui_item,
    input  wire        ui_guide,
    input  wire        ui_trans,
    input  wire        ui_display,
    input  wire        zoom_mode,
    input  wire [23:0] accent_color,
    input  wire        fault_held,
    input  wire [2:0]  fault_source,
    input  wire [4:0]  fault_code,
    input  wire [3:0]  fault_count,
    input  wire        self_ok,
    output reg  [23:0] rgb_out
);
    // Picture-control header: only drawn in adjust mode or on a real error.
    localparam integer OSD_X = 296;
    localparam integer OSD_Y = 24;
    // Interaction menu / guide-card geometry.
    localparam integer MENU_X = 296;
    localparam integer MENU_Y = 2;
    localparam integer MENU_WIDTH = 136;
    localparam integer GUIDE_X = 272;
    localparam integer GUIDE_Y = 2;
    localparam integer GUIDE_TEXT_X = 280;
    localparam integer GUIDE_TEXT_Y = 2;
    // P6 diagnostics text rows.
    localparam integer SELF_Y = 52;
    localparam integer FAULT_X = 280;
    localparam integer FAULT_Y = 244;
    localparam [23:0] FAULT_BG_COLOR = 24'h101010;
    localparam [23:0] FAULT_BORDER_COLOR = 24'hFF2020;
    localparam [23:0] FAULT_TEXT_COLOR = 24'hFFE060;
    localparam integer LOG_Y = 146;
    localparam integer DIAG_X = 32;
    localparam [23:0] MENU_BAR_COLOR = 24'hB8DDF2;
    localparam [23:0] MENU_SELECT_COLOR = 24'hFFFF40;
    localparam [23:0] GUIDE_BG_COLOR = 24'hFFFFFF;
    localparam [23:0] OSD_COLOR = 24'hFFFFFF;
    localparam [23:0] ADJUST_COLOR = 24'h000000;
    localparam [23:0] ERROR_COLOR = 24'hFF4040;
    localparam [23:0] SELF_OK_COLOR = 24'h40FF40;
    localparam [23:0] SELF_NG_COLOR = 24'hFF6060;
    localparam [23:0] LOG_COLOR = 24'hFFB000;

    reg [63:0] header_text;
    reg [63:0] ui_menu_text;
    reg [79:0] ui_guide_text;
    reg [6:0] volume_bounded;
    reg [3:0] volume_tens, volume_ones;
    reg [7:0] volume_hundreds_char, volume_tens_char;
    reg [3:0] error_tens, error_ones;
    reg [3:0] fault_tens, fault_ones;
    reg [23:0] text_color;
    reg [23:0] ui_color;
    reg [7:0] ui_text_x;
    reg [3:0] ui_char_index;
    reg [2:0] ui_glyph_col;
    reg [2:0] ui_glyph_row;
    reg [4:0] ui_glyph_bits;
    reg [1:0] ui_line;
    reg [3:0] ui_row_local;
    reg [7:0] osd_char;
    reg header_active;
    // Automatic fault panel: a readable reason plus the latched code/count.
    reg fault_show;
    reg [2:0] show_source;
    reg [4:0] show_code;
    reg [3:0] show_count;
    reg [63:0] fault_line0, fault_line1, fault_code_line, fault_count_line;

    function [4:0] glyph_row;
        input [7:0] ch;
        input [2:0] row;
        reg [34:0] rows;
        begin
            case (ch)
                "%": rows = 35'b11001_11010_00100_00100_01000_10110_00110;
                "A": rows = 35'b01110_10001_10001_11111_10001_10001_10001;
                "B": rows = 35'b11110_10001_10001_11110_10001_10001_11110;
                "C": rows = 35'b01110_10001_10000_10000_10000_10001_01110;
                "D": rows = 35'b11110_10001_10001_10001_10001_10001_11110;
                "E": rows = 35'b11111_10000_10000_11110_10000_10000_11111;
                "F": rows = 35'b11111_10000_10000_11110_10000_10000_10000;
                "G": rows = 35'b01110_10001_10000_10111_10001_10001_01110;
                "H": rows = 35'b10001_10001_10001_11111_10001_10001_10001;
                "I": rows = 35'b11111_00100_00100_00100_00100_00100_11111;
                "K": rows = 35'b10001_10010_10100_11000_10100_10010_10001;
                "L": rows = 35'b10000_10000_10000_10000_10000_10000_11111;
                "M": rows = 35'b10001_11011_10101_10101_10001_10001_10001;
                "N": rows = 35'b10001_11001_10101_10011_10001_10001_10001;
                "O": rows = 35'b01110_10001_10001_10001_10001_10001_01110;
                "P": rows = 35'b11110_10001_10001_11110_10000_10000_10000;
                "Q": rows = 35'b01110_10001_10001_10001_10101_10010_01101;
                "R": rows = 35'b11110_10001_10001_11110_10100_10010_10001;
                "S": rows = 35'b01111_10000_10000_01110_00001_00001_11110;
                "T": rows = 35'b11111_00100_00100_00100_00100_00100_00100;
                "U": rows = 35'b10001_10001_10001_10001_10001_10001_01110;
                "V": rows = 35'b10001_10001_10001_10001_10001_01010_00100;
                "W": rows = 35'b10001_10001_10001_10101_10101_11011_10001;
                "X": rows = 35'b10001_10001_01010_00100_01010_10001_10001;
                "Y": rows = 35'b10001_10001_01010_00100_00100_00100_00100;
                "Z": rows = 35'b11111_00001_00010_00100_01000_10000_11111;
                "0": rows = 35'b01110_10001_10001_10001_10001_10001_01110;
                "1": rows = 35'b00100_01100_00100_00100_00100_00100_11111;
                "2": rows = 35'b01110_10001_00001_00010_00100_01000_11111;
                "3": rows = 35'b11110_00001_00001_01110_00001_00001_11110;
                "4": rows = 35'b10010_10010_10010_11111_00010_00010_00010;
                "5": rows = 35'b11111_10000_10000_11110_00001_00001_11110;
                "6": rows = 35'b01110_10000_10000_11110_10001_10001_01110;
                "7": rows = 35'b11111_00001_00010_00100_01000_01000_01000;
                "8": rows = 35'b01110_10001_10001_01110_10001_10001_01110;
                "9": rows = 35'b01110_10001_10001_01111_00001_00001_01110;
                default: rows = 35'd0;
            endcase
            case (row)
                3'd0: glyph_row = rows[34:30];
                3'd1: glyph_row = rows[29:25];
                3'd2: glyph_row = rows[24:20];
                3'd3: glyph_row = rows[19:15];
                3'd4: glyph_row = rows[14:10];
                3'd5: glyph_row = rows[9:5];
                3'd6: glyph_row = rows[4:0];
                default: glyph_row = 5'd0;
            endcase
        end
    endfunction

    function [7:0] hex_char;
        input [3:0] n;
        begin hex_char = n<10 ? (8'd48+{4'd0,n}) : (8'd65+{4'd0,n}-8'd10); end
    endfunction

    // Header string: brightness / contrast / volume in adjust mode, otherwise
    // the first error code (kept visible so a fault is never hidden).
    always @* begin
        if (adjust_mode) begin
            header_active = !ui_display; // DISPLAY rows show live values while editing.
            text_color = ADJUST_COLOR;
            if (volume_select)
                header_text = {"VOL ", volume_hundreds_char, volume_tens_char, 4'h3, volume_ones, " "};
            else if (param_select)
                header_text = {"CON ", 4'b0011, contrast, "  "};
            else
                header_text = {"BRT ", 4'b0011, brightness, "  "};
        end else if (error_code != 0 || status_bits[3] || status_bits[4] || progress_bits[3]) begin
            header_active = 1'b1;
            text_color = ERROR_COLOR;
            case (error_source)
                3'd1: header_text = {"SD ", 4'h3, error_tens, 4'h3, error_ones, "  "};
                3'd2: header_text = {"FS ", 4'h3, error_tens, 4'h3, error_ones, "  "};
                3'd3: header_text = {"BMP ", 4'h3, error_tens, 4'h3, error_ones, " "};
                3'd4: header_text = {"IO ", 4'h3, error_tens, 4'h3, error_ones, "  "};
                3'd5: header_text = {"MEM ", 4'h3, error_tens, 4'h3, error_ones, " "};
                default: header_text = {"ERR ", 4'h3, error_tens, 4'h3, error_ones, " "};
            endcase
        end else begin
            header_active = 1'b0;
            text_color = OSD_COLOR;
            header_text = 64'd0;
        end
    end

    always @* begin
        rgb_out = video_rgb;
        volume_bounded = volume > 7'd100 ? 7'd100 : volume;
        volume_hundreds_char = volume_bounded == 100 ? "1" : " ";
        if      (volume_bounded == 100) volume_tens = 0;
        else if (volume_bounded >= 90) volume_tens = 9;
        else if (volume_bounded >= 80) volume_tens = 8;
        else if (volume_bounded >= 70) volume_tens = 7;
        else if (volume_bounded >= 60) volume_tens = 6;
        else if (volume_bounded >= 50) volume_tens = 5;
        else if (volume_bounded >= 40) volume_tens = 4;
        else if (volume_bounded >= 30) volume_tens = 3;
        else if (volume_bounded >= 20) volume_tens = 2;
        else if (volume_bounded >= 10) volume_tens = 1;
        else                         volume_tens = 0;
        volume_ones = volume_bounded == 100 ? 0 :
                      volume_bounded - ({3'd0,volume_tens} << 3) - ({3'd0,volume_tens} << 1);
        volume_tens_char = volume_bounded >= 10 ? {4'h3,volume_tens} : " ";
        error_tens = error_code>=30 ? 3 : error_code>=20 ? 2 : error_code>=10 ? 1 : 0;
        error_ones = error_code-({1'b0,error_tens}<<3)-({1'b0,error_tens}<<1);
        fault_tens = fault_code>=30 ? 3 : fault_code>=20 ? 2 : fault_code>=10 ? 1 : 0;
        fault_ones = fault_code-({1'b0,fault_tens}<<3)-({1'b0,fault_tens}<<1);
        ui_line = 2'd0;
        ui_text_x = 8'd0;
        ui_char_index = 4'd0;
        ui_glyph_col = 3'd0;
        ui_glyph_row = 3'd0;
        ui_glyph_bits = 5'd0;
        ui_row_local = 4'd0;
        ui_color = OSD_COLOR;
        ui_menu_text = "GUIDE   ";
        ui_guide_text = "GUIDE MODE";
        osd_char = " ";
        // Fault panel selection: a live error wins, else the latched fault.
        fault_show = (error_code != 0) || status_bits[3] || status_bits[4] ||
                     progress_bits[3] || fault_held;
        if (error_code != 0 || status_bits[3] || status_bits[4] || progress_bits[3]) begin
            show_source = error_source;
            show_code = error_code;
        end else begin
            show_source = fault_source;
            show_code = fault_code;
        end
        show_count = fault_count;
        case (show_source)
            3'd1: begin fault_line0 = "TF CARD "; fault_line1 = "MISSING "; end
            3'd2: begin fault_line0 = "FS FAIL "; fault_line1 = "        "; end
            3'd3: begin fault_line0 = "BMP LOAD"; fault_line1 = "FAILED  "; end
            3'd4: begin fault_line0 = "TF READ "; fault_line1 = "FAILED  "; end
            3'd5: begin fault_line0 = "MEMORY  "; fault_line1 = "ERROR   "; end
            3'd6: begin fault_line0 = "AUDIO TF"; fault_line1 = "ERROR   "; end
            default: begin fault_line0 = "SYSTEM  "; fault_line1 = "FAULT   "; end
        endcase
        fault_code_line = {"CODE", hex_char(show_source),
                           "C", {4'h3, fault_tens}, {4'h3, fault_ones}, " "};
        fault_count_line = {"COUNT ", hex_char(show_count), "  "};

        // 1) Picture-control header (adjust mode or a real error only).
        if (de && header_active &&
            v_count >= OSD_Y && v_count < OSD_Y + 14 &&
            h_count >= OSD_X && h_count < OSD_X + 128) begin
            if (adjust_mode) rgb_out = 24'hFFFFFF;
            ui_text_x = (h_count - OSD_X) >> 1;
            ui_char_index = ui_text_x[6:3];
            ui_glyph_col = ui_text_x[2:0];
            ui_glyph_row = (v_count - OSD_Y) >> 1;
            case (ui_char_index)
                4'd0: osd_char = header_text[63:56];
                4'd1: osd_char = header_text[55:48];
                4'd2: osd_char = header_text[47:40];
                4'd3: osd_char = header_text[39:32];
                4'd4: osd_char = header_text[31:24];
                4'd5: osd_char = header_text[23:16];
                4'd6: osd_char = header_text[15:8];
                4'd7: osd_char = header_text[7:0];
                default: osd_char = " ";
            endcase
            ui_glyph_bits = glyph_row(osd_char, ui_glyph_row);
            if (ui_glyph_col < 3'd5 && ui_glyph_bits[4 - ui_glyph_col])
                rgb_out = text_color;
        end

        // 2) Main menu or DISPLAY submenu.
        if (de && ui_active &&
            v_count >= MENU_Y && v_count < MENU_Y + 48 &&
            h_count >= MENU_X - 8 && h_count < MENU_X + MENU_WIDTH) begin
            ui_line = (v_count - MENU_Y) >> 4;
            ui_row_local = (v_count - MENU_Y) - {ui_line, 4'b0000};
            ui_color = 24'h000000;
            rgb_out = 24'hFFFFFF;
            if (h_count >= MENU_X) begin
                ui_text_x = (h_count - MENU_X) >> 1;
                ui_char_index = ui_text_x[6:3];
                ui_glyph_col = ui_text_x[2:0];
                ui_glyph_row = ui_row_local[3:1];
                if (ui_display) begin
                    case (ui_line)
                        2'd0: ui_menu_text = {"CON   ",4'h3,contrast," "};
                        2'd1: ui_menu_text = {"BRI   ",4'h3,brightness," "};
                        default: ui_menu_text = {"VOL ",volume_hundreds_char,volume_tens_char,4'h3,volume_ones,"%"};
                    endcase
                end else begin
                    case (ui_line)
                        2'd0: ui_menu_text = "GUIDE   ";
                        2'd1: ui_menu_text = "DISPLAY ";
                        default: ui_menu_text = "TRANS   ";
                    endcase
                end
                case (ui_char_index)
                    4'd0: osd_char = ui_menu_text[63:56];
                    4'd1: osd_char = ui_menu_text[55:48];
                    4'd2: osd_char = ui_menu_text[47:40];
                    4'd3: osd_char = ui_menu_text[39:32];
                    4'd4: osd_char = ui_menu_text[31:24];
                    4'd5: osd_char = ui_menu_text[23:16];
                    4'd6: osd_char = ui_menu_text[15:8];
                    4'd7: osd_char = ui_menu_text[7:0];
                    default: osd_char = " ";
                endcase
                ui_glyph_bits = glyph_row(osd_char, ui_glyph_row);
                if (ui_glyph_col < 3'd5 && ui_glyph_bits[4 - ui_glyph_col])
                    rgb_out = ui_color;
                else if (ui_line == ui_item && ui_row_local < 14)
                    rgb_out = MENU_BAR_COLOR;
            end else if (ui_line == ui_item && ui_row_local < 14)
                rgb_out = MENU_BAR_COLOR;
        end

        // 3) Transition sub-menu: CORNERS / SLIDE / FADE.
        if (de && ui_trans &&
            v_count >= MENU_Y && v_count < MENU_Y + 48 &&
            h_count >= MENU_X - 8 && h_count < MENU_X + MENU_WIDTH) begin
            ui_line = (v_count - MENU_Y) >> 4;
            ui_row_local = (v_count - MENU_Y) - {ui_line, 4'b0000};
            ui_color = 24'h000000;
            rgb_out = 24'hFFFFFF;
            if (h_count >= MENU_X) begin
                ui_text_x = (h_count - MENU_X) >> 1;
                ui_char_index = ui_text_x[6:3];
                ui_glyph_col = ui_text_x[2:0];
                ui_glyph_row = ui_row_local[3:1];
                case (ui_line)
                    2'd0: ui_menu_text = "CORNERS ";
                    2'd1: ui_menu_text = "SLIDE   ";
                    default: ui_menu_text = "FADE    ";
                endcase
                case (ui_char_index)
                    4'd0: osd_char = ui_menu_text[63:56];
                    4'd1: osd_char = ui_menu_text[55:48];
                    4'd2: osd_char = ui_menu_text[47:40];
                    4'd3: osd_char = ui_menu_text[39:32];
                    4'd4: osd_char = ui_menu_text[31:24];
                    4'd5: osd_char = ui_menu_text[23:16];
                    4'd6: osd_char = ui_menu_text[15:8];
                    4'd7: osd_char = ui_menu_text[7:0];
                    default: osd_char = " ";
                endcase
                ui_glyph_bits = glyph_row(osd_char, ui_glyph_row);
                if (ui_glyph_col < 3'd5 && ui_glyph_bits[4 - ui_glyph_col])
                    rgb_out = ui_color;
                else if (ui_line == ui_item && ui_row_local < 14)
                    rgb_out = MENU_BAR_COLOR;
            end else if (ui_line == ui_item && ui_row_local < 14)
                rgb_out = MENU_BAR_COLOR;
        end

        // 4) Guide card (title uses the audio-reactive accent colour).
        if (de && ui_guide &&
            v_count >= GUIDE_Y && v_count < GUIDE_Y + 64 &&
            h_count >= GUIDE_X && h_count < GUIDE_X + 176) begin
            rgb_out = GUIDE_BG_COLOR;
            if (v_count >= GUIDE_TEXT_Y && v_count < GUIDE_TEXT_Y + 64 &&
                h_count >= GUIDE_TEXT_X && h_count < GUIDE_TEXT_X + 160) begin
                ui_line = (v_count - GUIDE_TEXT_Y) >> 4;
                ui_row_local = (v_count - GUIDE_TEXT_Y) - {ui_line, 4'b0000};
                ui_text_x = (h_count - GUIDE_TEXT_X) >> 1;
                ui_char_index = ui_text_x[7:3];
                ui_glyph_col = ui_text_x[2:0];
                ui_glyph_row = ui_row_local[3:1];
                case (ui_line)
                    2'd0: ui_guide_text = "GUIDE MODE";
                    2'd1: ui_guide_text = "ZOOM MODE ";
                    2'd2: ui_guide_text = "2 8 SELECT";
                    default: ui_guide_text = "* BACK #OK";
                endcase
                case (ui_char_index)
                    4'd0: osd_char = ui_guide_text[79:72];
                    4'd1: osd_char = ui_guide_text[71:64];
                    4'd2: osd_char = ui_guide_text[63:56];
                    4'd3: osd_char = ui_guide_text[55:48];
                    4'd4: osd_char = ui_guide_text[47:40];
                    4'd5: osd_char = ui_guide_text[39:32];
                    4'd6: osd_char = ui_guide_text[31:24];
                    4'd7: osd_char = ui_guide_text[23:16];
                    4'd8: osd_char = ui_guide_text[15:8];
                    4'd9: osd_char = ui_guide_text[7:0];
                    default: osd_char = " ";
                endcase
                ui_glyph_bits = glyph_row(osd_char, ui_glyph_row);
                if (ui_glyph_col < 3'd5 && ui_glyph_bits[4 - ui_glyph_col])
                    rgb_out = 24'h000000;
                else if (ui_line < 2 && ui_line == ui_item && ui_row_local < 14)
                    rgb_out = MENU_BAR_COLOR;
            end
        end

        // 5) P6 diagnostics: SELF OK/NG (menu only) and a latched fault log.
        if (de && ui_active &&
            v_count >= SELF_Y && v_count < SELF_Y + 14 &&
            h_count >= MENU_X && h_count < MENU_X + 112) begin
            rgb_out = 24'hFFFFFF;
            ui_text_x = (h_count - MENU_X) >> 1;
            ui_char_index = ui_text_x[6:3];
            ui_glyph_col = ui_text_x[2:0];
            ui_glyph_row = (v_count - SELF_Y) >> 1;
            case (ui_char_index)
                4'd0: osd_char = "S";
                4'd1: osd_char = "E";
                4'd2: osd_char = "L";
                4'd3: osd_char = "F";
                4'd4: osd_char = " ";
                4'd5: osd_char = self_ok ? "O" : "N";
                4'd6: osd_char = self_ok ? "K" : "G";
                default: osd_char = " ";
            endcase
            ui_glyph_bits = glyph_row(osd_char, ui_glyph_row);
            if (ui_glyph_col < 3'd5 && ui_glyph_bits[4 - ui_glyph_col])
                rgb_out = 24'h000000;
        end
        if (de && fault_held &&
            v_count >= LOG_Y && v_count < LOG_Y + 14 &&
            h_count >= DIAG_X && h_count < DIAG_X + 208) begin
            ui_text_x = (h_count - DIAG_X) >> 1;
            ui_char_index = ui_text_x[6:3];
            ui_glyph_col = ui_text_x[2:0];
            ui_glyph_row = (v_count - LOG_Y) >> 1;
            case (ui_char_index)
                4'd0: osd_char = "L";
                4'd1: osd_char = "O";
                4'd2: osd_char = "G";
                4'd3: osd_char = " ";
                4'd4: osd_char = "S";
                4'd5: osd_char = {5'b00110, fault_source};
                4'd6: osd_char = " ";
                4'd7: osd_char = "C";
                4'd8: osd_char = {4'h3, fault_tens};
                4'd9: osd_char = {4'h3, fault_ones};
                4'd10: osd_char = " ";
                4'd11: osd_char = "N";
                4'd12: osd_char = hex_char(fault_count);
                default: osd_char = " ";
            endcase
            ui_glyph_bits = glyph_row(osd_char, ui_glyph_row);
            if (ui_glyph_col < 3'd5 && ui_glyph_bits[4 - ui_glyph_col])
                rgb_out = LOG_COLOR;
        end
        // 6) Automatic fault panel: black card with a red border, the
        // readable reason on two rows, then code and episode count.
        if (de && fault_show &&
            v_count >= FAULT_Y && v_count < FAULT_Y + 64 &&
            h_count >= FAULT_X && h_count < FAULT_X + 128) begin
            if (v_count < FAULT_Y + 2 || v_count >= FAULT_Y + 62 ||
                h_count < FAULT_X + 2 || h_count >= FAULT_X + 126)
                rgb_out = FAULT_BORDER_COLOR;
            else
                rgb_out = FAULT_BG_COLOR;
            if (v_count >= FAULT_Y + 2 && v_count < FAULT_Y + 62 &&
                h_count >= FAULT_X + 4 && h_count < FAULT_X + 124) begin
                ui_line = (v_count - (FAULT_Y + 2)) >> 4;
                ui_row_local = (v_count - (FAULT_Y + 2)) - {ui_line, 4'b0000};
                ui_text_x = (h_count - (FAULT_X + 4)) >> 1;
                ui_char_index = ui_text_x[6:3];
                ui_glyph_col = ui_text_x[2:0];
                ui_glyph_row = ui_row_local[3:1];
                case (ui_line)
                    2'd0: case (ui_char_index)
                        4'd0: osd_char = fault_line0[63:56];
                        4'd1: osd_char = fault_line0[55:48];
                        4'd2: osd_char = fault_line0[47:40];
                        4'd3: osd_char = fault_line0[39:32];
                        4'd4: osd_char = fault_line0[31:24];
                        4'd5: osd_char = fault_line0[23:16];
                        4'd6: osd_char = fault_line0[15:8];
                        default: osd_char = fault_line0[7:0];
                    endcase
                    2'd1: case (ui_char_index)
                        4'd0: osd_char = fault_line1[63:56];
                        4'd1: osd_char = fault_line1[55:48];
                        4'd2: osd_char = fault_line1[47:40];
                        4'd3: osd_char = fault_line1[39:32];
                        4'd4: osd_char = fault_line1[31:24];
                        4'd5: osd_char = fault_line1[23:16];
                        4'd6: osd_char = fault_line1[15:8];
                        default: osd_char = fault_line1[7:0];
                    endcase
                    2'd2: case (ui_char_index)
                        4'd0: osd_char = fault_code_line[63:56];
                        4'd1: osd_char = fault_code_line[55:48];
                        4'd2: osd_char = fault_code_line[47:40];
                        4'd3: osd_char = fault_code_line[39:32];
                        4'd4: osd_char = fault_code_line[31:24];
                        4'd5: osd_char = fault_code_line[23:16];
                        4'd6: osd_char = fault_code_line[15:8];
                        default: osd_char = fault_code_line[7:0];
                    endcase
                    default: case (ui_char_index)
                        4'd0: osd_char = fault_count_line[63:56];
                        4'd1: osd_char = fault_count_line[55:48];
                        4'd2: osd_char = fault_count_line[47:40];
                        4'd3: osd_char = fault_count_line[39:32];
                        4'd4: osd_char = fault_count_line[31:24];
                        4'd5: osd_char = fault_count_line[23:16];
                        4'd6: osd_char = fault_count_line[15:8];
                        default: osd_char = fault_count_line[7:0];
                    endcase
                endcase
                ui_glyph_bits = glyph_row(osd_char, ui_glyph_row);
                if (ui_glyph_col < 3'd5 && ui_glyph_bits[4 - ui_glyph_col])
                    rgb_out = (ui_line < 2'd2) ? FAULT_TEXT_COLOR : 24'hFFFFFF;
            end
        end
    end
endmodule
