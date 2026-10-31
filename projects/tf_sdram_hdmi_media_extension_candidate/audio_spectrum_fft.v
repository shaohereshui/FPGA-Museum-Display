// Read-only observer of the same volume-scaled PCM sent to HDMI.
// Capture 512 stereo samples, select the stronger channel (no phase cancellation),
// apply a Hann window, and run an in-place radix-2 FFT normalized by 512.
// Capture pauses during the ~1 ms transform; audio playback never waits for it.
module audio_spectrum_fft (
    input wire clk,rst_n,sample_valid,
    input wire [15:0] left_sample,right_sample,
    output reg [223:0] levels,
    output reg [511:0] magnitudes,
    output reg result_valid,
    output wire analyzing,
    input wire wave_front_bank,wave_accept,
    input wire [7:0] wave_read_address,
    output reg [15:0] wave_read_data,
    output reg wave_pending,wave_pending_bank,
    output reg [9:0] wave_density,
    output reg [7:0] wave_start
);
    localparam CAPTURE=0,WIN_ADDR=1,WIN_WAIT=2,WIN_MUL=3,WIN_WRITE=4,
               FFT_ADDR=5,FFT_WAIT_A=6,FFT_GET_A=7,FFT_WAIT_B=8,FFT_MUL=9,
               FFT_ROTATE=10,FFT_SUM=11,FFT_WRITE_A=12,FFT_WRITE_B=13,
               BIN_ADDR=14,BIN_WAIT=15,BIN_PEAK=16,PUBLISH=17,WIN_SMOOTH1=18,WIN_SMOOTH2=19;
    reg [4:0] state;
    assign analyzing=state!=CAPTURE;
    reg [31:0] ram[0:511];
    reg [31:0] twiddle_rom[0:255];
    reg [15:0] window_rom[0:511];
    initial begin
        $readmemh("spectrum_twiddle.hex",twiddle_rom);
        $readmemh("spectrum_window.hex",window_rom);
    end
    reg [8:0] read_address,write_address,window_address;
    reg [7:0] twiddle_address;
    reg write_enable;
    reg [31:0] write_data,read_data,twiddle_data;
    reg [15:0] window_data;
    always @(posedge clk) begin
        if(write_enable)ram[write_address]<=write_data;
        read_data<=ram[read_address];
        twiddle_data<=twiddle_rom[twiddle_address];
        window_data<=window_rom[window_address];
    end
    function [8:0] reverse9;
        input [8:0] x;
        begin reverse9={x[0],x[1],x[2],x[3],x[4],x[5],x[6],x[7],x[8]};end
    endfunction
    function [15:0] absolute16;
        input [15:0] x;
        begin absolute16=x[15] ? (16'd0-x) : x;end
    endfunction
    function [15:0] butterfly;
        input signed [15:0] a;
        input signed [17:0] b;
        input subtract;
        reg signed [18:0] sum,half;
        begin
            sum=subtract ? $signed({{3{a[15]}},a})-$signed({b[17],b}) :
                           $signed({{3{a[15]}},a})+$signed({b[17],b});
            half=sum>>>1;
            if(half>32767)butterfly=16'h7fff;
            else if(half< -32768)butterfly=16'h8000;
            else butterfly=half[15:0];
        end
    endfunction
    function [8:0] band_end;
        input [4:0] band;
        begin case(band)
            5'd0:band_end=9'd2;
            5'd1:band_end=9'd3;
            5'd2:band_end=9'd4;
            5'd3:band_end=9'd5;
            5'd4:band_end=9'd6;
            5'd5:band_end=9'd7;
            5'd6:band_end=9'd8;
            5'd7:band_end=9'd9;
            5'd8:band_end=9'd10;
            5'd9:band_end=9'd11;
            5'd10:band_end=9'd12;
            5'd11:band_end=9'd13;
            5'd12:band_end=9'd14;
            5'd13:band_end=9'd15;
            5'd14:band_end=9'd16;
            5'd15:band_end=9'd17;
            5'd16:band_end=9'd18;
            5'd17:band_end=9'd20;
            5'd18:band_end=9'd24;
            5'd19:band_end=9'd29;
            5'd20:band_end=9'd34;
            5'd21:band_end=9'd40;
            5'd22:band_end=9'd47;
            5'd23:band_end=9'd56;
            5'd24:band_end=9'd66;
            5'd25:band_end=9'd78;
            5'd26:band_end=9'd93;
            5'd27:band_end=9'd109;
            5'd28:band_end=9'd129;
            5'd29:band_end=9'd153;
            5'd30:band_end=9'd181;
            5'd31:band_end=9'd214;
            default:band_end=214;
        endcase end
    endfunction
`include "magnitude_height.vh"
    reg [8:0] capture_index,window_index,half_size,twiddle_step;
    reg [9:0] group_base;
    reg [7:0] butterfly_index,twiddle_index;
    reg [3:0] fft_stage;
    reg [4:0] band;
    reg [8:0] scan_bin;
    reg [24:0] left_energy,right_energy;
    reg use_right;
    reg signed [31:0] window_product,prod_rr,prod_ii,prod_ri,prod_ir;
    reg signed [15:0] a_real,a_imag;
    reg signed [17:0] rotated_real,rotated_imag;
    reg [31:0] out_a,out_b;
    reg [15:0] band_peak;
    reg [223:0] next_levels;
    reg [511:0] next_magnitudes;
    wire [16:0] bin_sum={1'b0,absolute16(read_data[15:0])}+{1'b0,absolute16(read_data[31:16])};
    wire [15:0] bin_magnitude=bin_sum[16] ? 16'hffff : bin_sum[15:0];
    wire [15:0] next_peak=bin_magnitude>band_peak ? bin_magnitude : band_peak;
    wire signed [32:0] real_difference=$signed({prod_rr[31],prod_rr})-$signed({prod_ii[31],prod_ii});
    wire signed [32:0] imag_sum=$signed({prod_ri[31],prod_ri})+$signed({prod_ir[31],prod_ir});
    // Two 256-column waveform banks. A pending bank is immutable until
    // accepted by the renderer at a frame boundary. Skip waveform publication
    // for a block if both banks are occupied; FFT/audio continue independently.
    reg [15:0] wave_ram[0:511];
    reg wave_capture_block,wave_write_bank;
    reg signed [15:0] wave_hist1,wave_hist2;
    reg signed [15:0] wave_target_q8,wave_smooth1,wave_smooth2;
    wire signed [16:0] smooth_diff1=$signed({wave_target_q8[15],wave_target_q8})-$signed({wave_smooth1[15],wave_smooth1});
    wire signed [16:0] smooth_next1=$signed({wave_smooth1[15],wave_smooth1})+(smooth_diff1>>>4);
    wire signed [16:0] smooth_diff2=$signed({wave_smooth1[15],wave_smooth1})-$signed({wave_smooth2[15],wave_smooth2});
    wire signed [16:0] smooth_next2=$signed({wave_smooth2[15],wave_smooth2})+(smooth_diff2>>>4);
    wire signed [15:0] smooth_point_q8=window_index==0?wave_target_q8:smooth_next2[15:0];
    function [7:0] rounded_point;
        input [15:0] q8;
        reg [15:0] magnitude;
        reg [7:0] pixels;
        begin
            magnitude=q8[15]?(16'd0-q8):q8;
            pixels=(magnitude+16'd128)>>8;
            rounded_point=q8[15]?(8'd0-pixels):pixels;
        end
    endfunction
    reg signed [7:0] previous_point,point_from,point_to;
    reg trigger_armed,trigger_found;
    reg [7:0] trigger_start;
    reg [9:0] crossings_left,crossings_right;
    reg sign_left,sign_right,sign_valid_left,sign_valid_right;
    wire signed [15:0] selected_pcm=use_right?read_data[31:16]:read_data[15:0];
    // Display-only [1 2 1]/4 smoothing. FFT/windowed audio use selected_pcm
    // unchanged. Seed both history taps from the first point of each block.
    wire signed [17:0] wave_sum=$signed({{2{selected_pcm[15]}},selected_pcm})+
        $signed({wave_hist1[15],wave_hist1,1'b0})+$signed({{2{wave_hist2[15]}},wave_hist2});
    wire signed [15:0] wave_filtered=window_index==0?selected_pcm:(wave_sum>>>2);
    // Fixed monotonic display compression makes weak signals readable and
    // leaves headroom at full scale. It never feeds the audio or FFT path.
    function [7:0] wave_map;
        input [15:0] pcm;
        reg [15:0] magnitude;
        reg [7:0] displacement;
        begin
            magnitude=pcm[15]?(16'd0-pcm):pcm;
            if(magnitude<512)displacement=magnitude>>5;
            else if(magnitude<2048)displacement=16+((magnitude-512)>>7);
            else if(magnitude<8192)displacement=28+((magnitude-2048)>>8);
            else displacement=52+((magnitude-8192)>>10);
            wave_map=pcm[15]?(8'd0-displacement):displacement;
        end
    endfunction
    always @(posedge clk)begin
        if(state==WIN_WRITE && window_index[0] && wave_capture_block)
            wave_ram[{wave_write_bank,window_index[8:1]}]<={point_to,point_from};
        wave_read_data<=wave_ram[{wave_front_bank,wave_read_address}];
    end
    always @* begin
        write_enable=0;write_address=0;write_data=0;
        if(rst_n)case(state)
            CAPTURE:begin
                write_enable=sample_valid;write_address=reverse9(capture_index);
                write_data={right_sample,left_sample};
            end
            WIN_WRITE:begin
                write_enable=1;write_address=reverse9(window_index);
                write_data={16'd0,window_product[30:15]};
            end
            FFT_WRITE_A:begin write_enable=1;write_address=group_base+butterfly_index;write_data=out_a;end
            FFT_WRITE_B:begin write_enable=1;write_address=group_base+butterfly_index+half_size;write_data=out_b;end
            default:begin end
        endcase
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=CAPTURE;levels<=0;magnitudes<=0;result_valid<=0;
            wave_pending<=0;wave_pending_bank<=0;wave_density<=0;wave_start<=64;
            wave_capture_block<=0;wave_write_bank<=1;wave_hist1<=0;wave_hist2<=0;
            wave_target_q8<=0;wave_smooth1<=0;wave_smooth2<=0;
            previous_point<=0;point_from<=0;point_to<=0;trigger_start<=64;trigger_armed<=0;trigger_found<=0;
            crossings_left<=0;crossings_right<=0;sign_left<=0;sign_right<=0;sign_valid_left<=0;sign_valid_right<=0;
            capture_index<=0;window_index<=0;left_energy<=0;right_energy<=0;use_right<=0;
            read_address<=0;window_address<=0;twiddle_address<=0;
            group_base<=0;half_size<=1;twiddle_step<=256;butterfly_index<=0;twiddle_index<=0;fft_stage<=1;
            window_product<=0;prod_rr<=0;prod_ii<=0;prod_ri<=0;prod_ir<=0;
            a_real<=0;a_imag<=0;rotated_real<=0;rotated_imag<=0;out_a<=0;out_b<=0;
            scan_bin<=1;band<=0;band_peak<=0;next_levels<=0;next_magnitudes<=0;
        end else begin
            result_valid<=0;
            if(wave_accept)wave_pending<=0;
            case(state)
                CAPTURE:if(sample_valid)begin
                    // Schmitt crossing counter ignores small near-zero noise.
                    if($signed(left_sample)>128 || $signed(left_sample)< -128)begin
                        if(sign_valid_left && left_sample[15]!=sign_left)crossings_left<=crossings_left+1'b1;
                        sign_left<=left_sample[15];sign_valid_left<=1;
                    end
                    if($signed(right_sample)>128 || $signed(right_sample)< -128)begin
                        if(sign_valid_right && right_sample[15]!=sign_right)crossings_right<=crossings_right+1'b1;
                        sign_right<=right_sample[15];sign_valid_right<=1;
                    end
                    left_energy<=left_energy+absolute16(left_sample);
                    right_energy<=right_energy+absolute16(right_sample);
                    capture_index<=capture_index+1'b1;
                    if(capture_index==511)begin
                        use_right<=(right_energy+absolute16(right_sample))>(left_energy+absolute16(left_sample));
                        window_index<=0;state<=WIN_ADDR;
                    end
                end
                WIN_ADDR:begin
                    read_address<=reverse9(window_index);window_address<=window_index;state<=WIN_WAIT;
                    if(window_index==0)begin wave_capture_block<=!wave_pending;wave_write_bank<=!wave_front_bank;end
                end
                WIN_WAIT:state<=WIN_MUL;
                WIN_MUL:begin
                    wave_hist1<=selected_pcm;
                    wave_hist2<=window_index==0?selected_pcm:wave_hist1;
                    wave_target_q8<={wave_map(wave_filtered),8'b0};
                    window_product<=$signed(use_right?read_data[31:16]:read_data[15:0])*$signed(window_data);
                    state<=WIN_SMOOTH1;
                end
                // Two display-only 1/16 low-pass stages round the waveform.
                // Separate cycles keep arithmetic out of the FFT timing path.
                WIN_SMOOTH1:begin
                    wave_smooth1<=window_index==0?wave_target_q8:smooth_next1[15:0];
                    state<=WIN_SMOOTH2;
                end
                WIN_SMOOTH2:begin
                    wave_smooth2<=smooth_point_q8;
                    if(window_index==0)begin
                        previous_point<=rounded_point(smooth_point_q8);
                        trigger_start<=64;trigger_found<=0;trigger_armed<=smooth_point_q8< -512;
                    end else if(window_index<=256 && !trigger_found)begin
                        if(smooth_point_q8< -512)trigger_armed<=1;
                        else if(smooth_point_q8>512 && trigger_armed)begin
                            trigger_start<=window_index[8:1];trigger_found<=1;
                        end
                    end
                    if(window_index[0])begin
                        point_from<=previous_point;point_to<=rounded_point(smooth_point_q8);
                        previous_point<=rounded_point(smooth_point_q8);
                    end
                    state<=WIN_WRITE;
                end
                WIN_WRITE:begin
                    if(window_index==511)begin
                        fft_stage<=1;half_size<=1;twiddle_step<=256;
                        group_base<=0;butterfly_index<=0;twiddle_index<=0;state<=FFT_ADDR;
                    end else begin window_index<=window_index+1'b1;state<=WIN_ADDR;end
                end
                FFT_ADDR:begin
                    read_address<=group_base+butterfly_index;twiddle_address<=twiddle_index;state<=FFT_WAIT_A;
                end
                FFT_WAIT_A:state<=FFT_GET_A;
                FFT_GET_A:begin
                    a_real<=read_data[15:0];a_imag<=read_data[31:16];
                    read_address<=group_base+butterfly_index+half_size;state<=FFT_WAIT_B;
                end
                FFT_WAIT_B:state<=FFT_MUL;
                FFT_MUL:begin
                    prod_rr<=$signed(read_data[15:0])*$signed(twiddle_data[15:0]);
                    prod_ii<=$signed(read_data[31:16])*$signed(twiddle_data[31:16]);
                    prod_ri<=$signed(read_data[15:0])*$signed(twiddle_data[31:16]);
                    prod_ir<=$signed(read_data[31:16])*$signed(twiddle_data[15:0]);
                    state<=FFT_ROTATE;
                end
                FFT_ROTATE:begin rotated_real<=real_difference>>>15;rotated_imag<=imag_sum>>>15;state<=FFT_SUM;end
                FFT_SUM:begin
                    out_a<={butterfly(a_imag,rotated_imag,1'b0),butterfly(a_real,rotated_real,1'b0)};
                    out_b<={butterfly(a_imag,rotated_imag,1'b1),butterfly(a_real,rotated_real,1'b1)};
                    state<=FFT_WRITE_A;
                end
                FFT_WRITE_A:state<=FFT_WRITE_B;
                FFT_WRITE_B:begin
                    state<=FFT_ADDR;
                    if({1'b0,butterfly_index}+9'd1==half_size)begin
                        butterfly_index<=0;twiddle_index<=0;
                        if(group_base+{half_size,1'b0}==512)begin
                            group_base<=0;
                            if(fft_stage==9)begin
                                scan_bin<=1;band<=0;band_peak<=0;next_levels<=0;next_magnitudes<=0;state<=BIN_ADDR;
                            end else begin fft_stage<=fft_stage+1'b1;half_size<=half_size<<1;twiddle_step<=twiddle_step>>1;end
                        end else group_base<=group_base+{half_size,1'b0};
                    end else begin butterfly_index<=butterfly_index+1'b1;twiddle_index<=twiddle_index+twiddle_step;end
                end
                BIN_ADDR:begin read_address<=scan_bin;state<=BIN_WAIT;end
                BIN_WAIT:state<=BIN_PEAK;
                BIN_PEAK:begin
                    if(scan_bin==band_end(band)-1'b1)begin
                        next_levels[band*7 +: 7]<=magnitude_height(next_peak);
                        next_magnitudes[band*16 +: 16]<=next_peak;
                        band_peak<=0;band<=band+1'b1;
                    end else band_peak<=next_peak;
                    scan_bin<=scan_bin+1'b1;
                    state<=scan_bin==213 ? PUBLISH : BIN_ADDR;
                end
                PUBLISH:begin
                    if(wave_capture_block)begin
                        wave_pending<=1;wave_pending_bank<=wave_write_bank;
                        wave_density<=use_right?crossings_right:crossings_left;wave_start<=trigger_start;
                    end
                    crossings_left<=0;crossings_right<=0;sign_valid_left<=0;sign_valid_right<=0;
                    levels<=next_levels;magnitudes<=next_magnitudes;result_valid<=1;
                    capture_index<=0;left_energy<=0;right_energy<=0;state<=CAPTURE;
                end
                default:state<=CAPTURE;
            endcase
        end
    end
endmodule
