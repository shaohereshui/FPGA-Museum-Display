// Audio visualizer drawn into the existing encoder RGB stage.
// Mode 0: 32-band radial spectrum inside the disc.
// Mode 1: time-domain waveform inside the same disc. Only the bars or the
// waveform are opaque; everything else stays transparent.
//
// Two pipeline stages keep 27 MHz closed: stage 1 registers the angular
// sector, stage 2 registers the block-RAM address and the pixel payload, and
// the drawing decision happens when the captured sample returns. The overlay
// is two pixels late, which is invisible on screen.
module audio_spectrum_overlay (
    input wire clk,rst_n,enable_switch,video_ready,audible,
    input wire [6:0] volume_percent,
    input wire [223:0] levels,
    input wire [1:0] visual_mode,
    input wire sample_tick,
    input wire signed [15:0] sample_left,sample_right,
    input wire [15:0] wave_data,
    input wire wave_pending,wave_pending_bank,
    input wire [9:0] wave_density,
    input wire [7:0] wave_start,
    output reg [7:0] wave_view_start,
    output reg wave_front_bank,
    output wire wave_accept,
    input wire de,
    input wire [9:0] h_count,v_count,
    input wire [23:0] rgb_in,
    output reg [23:0] rgb_out,
    output wire visible
);
    localparam [9:0] CX=10'd592,CY=10'd136;
    localparam [7:0] R_IN=8'd52,R_OUT=8'd124;

    reg switch_meta,switch_sync,show_frame,audible_frame,bars_frame;
    (* ram_style="none" *) reg [6:0] heights[0:31];
    reg [223:0] targets;
    reg updating;
    reg [4:0] update_index;
    wire [6:0] raw_target=targets[update_index*7 +: 7];
    wire [6:0] target=raw_target>72?7'd72:raw_target;
    wire [6:0] next_height=target>=heights[update_index] ?
        heights[update_index]+((target-heights[update_index]+7'd1)>>1) :
        heights[update_index]-((heights[update_index]-target+7'd7)>>3);
    wire frame_start=h_count==0 && v_count==0;
    assign wave_accept=1'b0;
    assign visible=show_frame;

    // 512 display-column samples, pre-converted to a screen row at capture.
    (* ram_style="block" *) reg [7:0] sample_buf[0:511];
    reg [8:0] write_ptr;
    reg [8:0] base_locked;
    reg [8:0] scan_idx;
    reg [8:0] scan_base;
    reg scanning,scan_found,scan_neg;
    reg [8:0] scan_trig;
    reg [7:0] ram_q;
    wire signed [16:0] mix_sum=$signed({sample_left[15],sample_left})+
                              $signed({sample_right[15],sample_right});
    wire signed [15:0] mix=$signed(mix_sum[16:1]);
    reg signed [15:0] hist1,hist2,hist3;
    reg decimate;
    wire signed [17:0] filt_sum=$signed({mix[15],mix[15],mix})+
                                  $signed({hist1[15],hist1[15],hist1})+
                                  $signed({hist2[15],hist2[15],hist2})+
                                  $signed({hist3[15],hist3[15],hist3});
    wire signed [15:0] filt=$signed(filt_sum[17:2]);
    wire signed [9:0] row_signed=10'sd136-(filt>>>8);
    wire [7:0] row_store=row_signed<0?8'd0:row_signed>255?8'd255:row_signed[7:0];

    integer b;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            switch_meta<=0;switch_sync<=0;show_frame<=0;audible_frame<=0;bars_frame<=1;
            wave_view_start<=0;wave_front_bank<=0;
            targets<=0;updating<=0;update_index<=0;write_ptr<=0;base_locked<=0;
            hist1<=0;hist2<=0;hist3<=0;decimate<=0;
            scanning<=0;scan_idx<=0;scan_found<=0;scan_neg<=0;scan_trig<=0;
            for(b=0;b<32;b=b+1)heights[b]<=0;
        end else begin
            switch_meta<=enable_switch;switch_sync<=switch_meta;
            if(sample_tick)begin
                hist3<=hist2;hist2<=hist1;hist1<=mix;
                decimate<=~decimate;
                if(decimate)begin
                    sample_buf[write_ptr]<=row_store;
                    write_ptr<=write_ptr+1'b1;
                end
            end
            if(frame_start)begin
                show_frame<=switch_sync && video_ready;
                audible_frame<=audible && volume_percent!=0;
                bars_frame<=~visual_mode[0];
                targets<=levels;updating<=1;update_index<=0;
                scanning<=1;scan_idx<=0;scan_found<=0;scan_neg<=0;scan_base<=write_ptr-9'd496;
            end
            if(updating)begin
                if(!audible_frame)heights[update_index]<=0;
                else heights[update_index]<=next_height;
                if(update_index==31)updating<=0;
                else update_index<=update_index+1'b1;
            end
            if(scanning)begin
                if(!scan_found)begin
                    if($signed(ram_q)<0)scan_neg<=1;
                    else if(scan_neg && $signed(ram_q)>=0 && scan_idx>9'd2)begin
                        scan_found<=1;scan_trig<=scan_idx-9'd2;
                    end
                end
                if(scan_idx==9'd247)begin
                    scanning<=0;
                    base_locked<=scan_found?(scan_base+scan_trig):(write_ptr-9'd248);
                end else scan_idx<=scan_idx+1'b1;
            end
        end
    end

    function [23:0] bar_color;
        input [4:0] band;
        begin
            case(band)
            5'd0:bar_color=24'h59ffe1;  5'd1:bar_color=24'h59ffef;
            5'd2:bar_color=24'h59fffd;  5'd3:bar_color=24'h59f3ff;
            5'd4:bar_color=24'h59e6ff;  5'd5:bar_color=24'h59d8ff;
            5'd6:bar_color=24'h59caff;  5'd7:bar_color=24'h59bcff;
            5'd8:bar_color=24'h59aeff;  5'd9:bar_color=24'h59a1ff;
            5'd10:bar_color=24'h5993ff; 5'd11:bar_color=24'h5985ff;
            5'd12:bar_color=24'h5977ff; 5'd13:bar_color=24'h596aff;
            5'd14:bar_color=24'h595cff; 5'd15:bar_color=24'h6559ff;
            5'd16:bar_color=24'h7259ff; 5'd17:bar_color=24'h8059ff;
            5'd18:bar_color=24'h8e59ff; 5'd19:bar_color=24'h9c59ff;
            5'd20:bar_color=24'haa59ff; 5'd21:bar_color=24'hb759ff;
            5'd22:bar_color=24'hc559ff; 5'd23:bar_color=24'hd359ff;
            5'd24:bar_color=24'he159ff; 5'd25:bar_color=24'hef59ff;
            5'd26:bar_color=24'hfc59ff; 5'd27:bar_color=24'hff59f4;
            5'd28:bar_color=24'hff59e6; 5'd29:bar_color=24'hff59d8;
            5'd30:bar_color=24'hff59ca; default:bar_color=24'hff59bd;
            endcase
        end
    endfunction

    // Stage 1: angular sector and coordinates.
    wire [9:0] raw_dx=h_count>=CX?h_count-CX:CX-h_count;
    wire [9:0] raw_dy=v_count>=CY?v_count-CY:CY-v_count;
    wire [6:0] dx_now=raw_dx>10'd127 ? 7'd127:raw_dx[6:0];
    wire [6:0] dy_now=raw_dy>10'd127 ? 7'd127:raw_dy[6:0];
    wire [13:0] dx_sq_now=dx_now*dx_now;
    wire [13:0] dy_sq_now=dy_now*dy_now;
    wire [14:0] radius_sq_now={1'b0,dx_sq_now}+{1'b0,dy_sq_now};
    wire sx=h_count>=CX,sy=v_count>=CY;
    wire swap=dy_now>dx_now;
    wire [6:0] major=swap?dy_now:dx_now;
    wire [6:0] minor=swap?dx_now:dy_now;
    reg [1:0] quadrant;
    always @* begin
        case({sx,sy})
            2'b11:quadrant=2'd0;
            2'b01:quadrant=2'd1;
            2'b00:quadrant=2'd2;
            default:quadrant=2'd3;
        endcase
    end
    wire [15:0] minor8={1'b0,minor,8'd0};
    wire [15:0] t1=major*16'd13,t2=major*16'd25,t3=major*16'd38,t4=major*16'd51;
    wire [15:0] t5=major*16'd64,t6=major*16'd78,t7=major*16'd92,t8=major*16'd106;
    wire [15:0] t9=major*16'd121,t10=major*16'd137,t11=major*16'd153,t12=major*16'd171;
    wire [15:0] t13=major*16'd190,t14=major*16'd210,t15=major*16'd232;
    wire [3:0] sub=(minor8>=t1)+(minor8>=t2)+(minor8>=t3)+(minor8>=t4)+
                   (minor8>=t5)+(minor8>=t6)+(minor8>=t7)+(minor8>=t8)+
                   (minor8>=t9)+(minor8>=t10)+(minor8>=t11)+(minor8>=t12)+
                   (minor8>=t13)+(minor8>=t14)+(minor8>=t15);
    wire reverse=swap^quadrant[0];
    wire [3:0] sector=reverse?4'd15-sub:sub;
    wire [6:0] angle_index={quadrant,reverse,sector};
    wire [8:0] local_x_now=h_count-CX+R_OUT;
    wire in_region_now=de && h_count>=CX-R_OUT && h_count<=CX+R_OUT &&
                       v_count>=CY-R_OUT && v_count<=CY+R_OUT;

    reg s1_de,s1_bars;
    reg [23:0] s1_rgb;
    reg [6:0] s1_angle;
    reg [14:0] s1_radius_sq;
    reg [8:0] s1_x,s1_y;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            s1_de<=0;s1_bars<=0;s1_rgb<=0;s1_angle<=0;s1_radius_sq<=0;s1_x<=0;s1_y<=0;
        end else begin
            s1_de<=in_region_now;s1_bars<=bars_frame;s1_rgb<=rgb_in;
            s1_angle<=angle_index;s1_radius_sq<=radius_sq_now;
            s1_x<=local_x_now;s1_y<=v_count[8:0];
        end
    end

    // Stage 2: fetch the precomputed row for this column. A trigger scan runs
    // once per frame during line 0 and picks a rising zero crossing so the
    // trace does not slide sideways.
    wire [8:0] display_addr=base_locked+s1_x;
    wire [8:0] scan_addr=scan_base+scan_idx;
    wire [8:0] ram_addr=scanning?scan_addr:display_addr;
    always @(posedge clk)ram_q<=sample_buf[ram_addr];
    wire [7:0] wave_row_q=ram_q;
    reg [7:0] prev_row_q;
    reg s2_de,s2_bars;
    reg [23:0] s2_rgb;
    reg [6:0] s2_angle;
    reg [14:0] s2_radius_sq;
    reg [8:0] s2_x,s2_y;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            s2_de<=0;s2_bars<=0;s2_rgb<=0;s2_angle<=0;s2_radius_sq<=0;s2_x<=0;s2_y<=0;prev_row_q<=0;
        end else begin
            s2_de<=s1_de;s2_bars<=s1_bars;s2_rgb<=s1_rgb;
            s2_angle<=s1_angle;s2_radius_sq<=s1_radius_sq;
            s2_x<=s1_x;s2_y<=s1_y;prev_row_q<=wave_row_q;
        end
    end

    // Stage 3: drawing decision.
    wire [7:0] row_lo=prev_row_q<wave_row_q?prev_row_q:wave_row_q;
    wire [7:0] row_hi=prev_row_q<wave_row_q?wave_row_q:prev_row_q;
    wire [9:0] sy10={1'b0,s2_y};
    wire wave_in_segment=sy10+10'd1>={2'b00,row_lo} && sy10<= {2'b00,row_hi}+10'd1;
    wire [4:0] band=s2_angle[6:2];
    wire [1:0] fraction=s2_angle[1:0];
    wire [6:0] height=heights[band];
    wire [7:0] bar_limit=8'd52+height;
    wire [15:0] bar_sq=bar_limit*bar_limit;
    wire bars_hit=show_frame && s2_de && audible_frame && s2_bars && height!=0 &&
                  s2_radius_sq>=15'd2704 && s2_radius_sq<=15'd15376 &&
                  s2_radius_sq<=bar_sq && fraction!=2'd0;
    wire wave_hit=show_frame && s2_de && audible_frame && !s2_bars &&
                  s2_radius_sq<=15'd15376 && wave_in_segment;
    always @* begin
        rgb_out=s2_rgb;
        if(bars_hit)rgb_out=bar_color(band);
        if(wave_hit)rgb_out=24'h30f0d0;
    end
endmodule
