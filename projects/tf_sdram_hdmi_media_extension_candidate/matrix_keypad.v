// 4x4 matrix keypad scanner.
// The rows are driven one-at-a-time low; columns are pulled high externally
// or by the FPGA input pull-ups.  The current media UI uses 0 for audio
// pause/play, B for waveform/bar switching, 5 for menu, # for confirm, * for
// back, A/C for zoom in/out, and 3 as the zoom-mode toggle.
module matrix_keypad #(
    parameter integer ROW_TICK_CYCLES = 27_000,
    parameter integer DEBOUNCE_SCANS = 3
) (
    input  wire       clk,
    input  wire       rst_n,
    output reg [3:0]  row_drive,
    input  wire [3:0] col_in,
    output wire [15:0] keys_down,
    output wire       key_prev_n,
    output wire       key_next_n,
    output wire       key_menu_n,
    output wire       key_volume_down_n,
    output wire       key_volume_up_n,
    output wire       key_confirm_n,
    output wire       key_back_n,
    output wire       key_zoom_in_n,
    output wire       key_zoom_out_n,
    output wire       key_visual_n,
    output reg        sw_audio_pause,
    output reg        sw_zoom_enable
);
    reg [15:0] stable_keys;
    assign keys_down = stable_keys;
    reg [1:0] debounce_count [0:15];
    reg [1:0] row_index;
    reg [15:0] row_counter;
    reg [3:0] col_meta, col_sync;
    integer i;
    integer key_index;

    always @* begin
        row_drive = 4'b1111;
        row_drive[row_index] = 1'b0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_meta <= 4'b1111;
            col_sync <= 4'b1111;
        end else begin
            col_meta <= col_in;
            col_sync <= col_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stable_keys <= 16'd0;
            sw_audio_pause <= 1'b0;
            sw_zoom_enable <= 1'b0;
            row_index <= 2'd0;
            row_counter <= 16'd0;
            for (i = 0; i < 16; i = i + 1)
                debounce_count[i] <= 2'd0;
        end else if (row_counter == ROW_TICK_CYCLES - 1) begin
            row_counter <= 16'd0;
            for (i = 0; i < 4; i = i + 1) begin
                key_index = (row_index * 4) + i;
                if ((!col_sync[i]) == stable_keys[key_index]) begin
                    debounce_count[key_index] <= 2'd0;
                end else if (debounce_count[key_index] == DEBOUNCE_SCANS - 1) begin
                    stable_keys[key_index] <= !col_sync[i];
                    if (!col_sync[i]) begin
                        case (key_index)
                            13: sw_audio_pause <= !sw_audio_pause;
                            2: sw_zoom_enable <= !sw_zoom_enable;
                            default: begin end
                        endcase
                    end
                    debounce_count[key_index] <= 2'd0;
                end else begin
                    debounce_count[key_index] <= debounce_count[key_index] + 1'b1;
                end
            end
            row_index <= row_index + 1'b1;
        end else begin
            row_counter <= row_counter + 1'b1;
        end
    end

    // Key layout used by the media UI:
    //   1 2 3 A
    //   4 5 6 B
    //   7 8 9 C
    //   * 0 # D
    assign key_prev_n = stable_keys[1] ? 1'b0 : 1'b1;          // 2
    assign key_next_n = stable_keys[9] ? 1'b0 : 1'b1;          // 8
    assign key_menu_n = stable_keys[5] ? 1'b0 : 1'b1;          // 5
    assign key_volume_down_n = stable_keys[4] ? 1'b0 : 1'b1;   // 4
    assign key_volume_up_n = stable_keys[6] ? 1'b0 : 1'b1;    // 6
    assign key_confirm_n = stable_keys[14] ? 1'b0 : 1'b1;      // #
    assign key_back_n = stable_keys[12] ? 1'b0 : 1'b1;         // *
    assign key_zoom_in_n = stable_keys[3] ? 1'b0 : 1'b1;       // A
    assign key_zoom_out_n = stable_keys[11] ? 1'b0 : 1'b1;    // C
    assign key_visual_n = stable_keys[7] ? 1'b0 : 1'b1;        // B
endmodule
