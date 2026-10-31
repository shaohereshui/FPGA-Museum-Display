// Buffered SD-domain PCM frames cross into the HDMI pixel clock domain.
// A missing sample after initial prefill is a latched fault, not silent audio.
module wav_audio_player #(
    parameter integer PIXEL_HZ = 27000000,
    parameter integer PREFILL = 1024
) (
    input wire sd_clk, pixel_clk, rst_n,
    input wire play_enable,
    input wire start,
    input wire [31:0] file_size,
    input wire file_valid,
    input wire [31:0] file_offset,
    input wire [7:0] file_data,
    input wire file_done, file_error,
    output wire input_ready, done, error,
    output wire [7:0] error_code,
    output wire playing, fault,
    output reg sample_valid,
    output reg sample_slot,
    output wire [15:0] left_sample, right_sample
);
    wire pcm_valid, pcm_ready, wav_error;
    wire [31:0] pcm_data, fifo_data;
    wire [7:0] wav_error_code;
    wire full, empty, almost_full;
    wire [11:0] used_words;
    wire tick;
    reg prefilled, prefilled_p1, prefilled_p2;
    reg error_p1, error_p2;
    reg underflow, underflow_s1, underflow_s2;
    wire fifo_read = tick && playing && play_enable && !empty;

    assign pcm_ready = !almost_full && !error;
    assign error = wav_error || underflow_s2;
    assign error_code = wav_error ? wav_error_code : underflow_s2 ? 8'd9 : 8'd0;
    assign playing = prefilled_p2 && !error_p2 && !underflow;
    assign fault = error_p2 || underflow;
    assign left_sample = fifo_data[15:0];
    assign right_sample = fifo_data[31:16];

    wav_pcm_stream parser (
        .clk(sd_clk), .rst_n(rst_n), .start(start), .file_size(file_size),
        .file_valid(file_valid), .file_offset(file_offset), .file_data(file_data),
        .file_done(file_done), .file_error(file_error), .input_ready(input_ready),
        .pcm_ready(pcm_ready), .pcm_valid(pcm_valid), .pcm_data(pcm_data),
        .done(done), .error(wav_error), .error_code(wav_error_code)
    );
    video_async_fifo #(.ADDR_WIDTH(11), .ALMOST_FULL_MARGIN(256)) fifo (
        .wr_clk(sd_clk), .rd_clk(pixel_clk), .rst_n(rst_n),
        .wr_en(pcm_valid && pcm_ready), .wr_data(pcm_data), .full(full),
        .rd_en(fifo_read), .rd_data(fifo_data), .empty(empty),
        .almost_full(almost_full), .used_words(used_words)
    );
    pcm_48khz_tick #(.PIXEL_HZ(PIXEL_HZ)) clock_tick (
        .clk(pixel_clk), .rst(!rst_n), .sample_tick(tick)
    );

    always @(posedge sd_clk or negedge rst_n) begin
        if (!rst_n) begin prefilled<=0; underflow_s1<=0; underflow_s2<=0; end
        else begin
            if (used_words>=PREFILL) prefilled<=1;
            underflow_s1<=underflow; underflow_s2<=underflow_s1;
        end
    end
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            prefilled_p1<=0; prefilled_p2<=0; error_p1<=0; error_p2<=0;
            sample_valid<=0; sample_slot<=0; underflow<=0;
        end else begin
            prefilled_p1<=prefilled; prefilled_p2<=prefilled_p1;
            error_p1<=error; error_p2<=error_p1;
            sample_valid<=fifo_read;
            // Keep the HDMI transport cadence while paused, but consume no
            // buffered song samples. The core fills these slots with silence.
            sample_slot<=tick;
            if (tick && playing && play_enable && empty) underflow<=1;
        end
    end
endmodule
