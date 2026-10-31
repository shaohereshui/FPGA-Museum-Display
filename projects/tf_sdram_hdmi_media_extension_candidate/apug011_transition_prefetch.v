// Two source-row buffers decouple APUG011 four-word reads from arbitrary
// nearest-neighbour output coordinates. All movement changes at frame edges.
// RAM ownership alternates: fill -> ready -> emit -> empty. No frame writes.
module apug011_transition_prefetch #(
    parameter integer FRAME_WORDS=345600,
    parameter integer FRAME_WIDTH=720,
    parameter integer BURST_WORDS=256,
    parameter integer FIFO_ADDR_WIDTH=11,
    parameter integer LOOP_FRAME=1,
    parameter integer SLIDE_STEP=32,
    parameter integer AUTO_STEP=1
) (
    input wire clk,rst,enable,restart,
    input wire [20:0] frame_base,
    input wire slide_request,request_manual,slide_right,
    input wire zoom_mode,
    input wire [9:0] zoom_span_x,
    input wire [9:0] zoom_span_y,
    input wire [9:0] zoom_win_x,
    input wire [9:0] zoom_win_y,
    input wire [20:0] slide_target_base,
    input wire [2:0] slide_target_image,
    output reg slide_active,slide_done,
    output reg [2:0] slide_completed_image,
    output wire [9:0] slide_offset,
    input wire init_done,refresh,busy,
    output reg app_rd_en,
    output reg [20:0] app_rd_addr,
    input wire rd_valid,
    input wire [31:0] rd_data,
    input wire fifo_full,fifo_almost_full,
    input wire [FIFO_ADDR_WIDTH:0] fifo_used_words,
    output wire fifo_wr_en,
    output wire [31:0] fifo_wr_data,
    output reg done,restart_done
);
    localparam integer H=FRAME_WORDS/FRAME_WIDTH;
    localparam integer ROW_READ_WORDS=((FRAME_WIDTH+BURST_WORDS-1)/BURST_WORDS)*BURST_WORDS;
    localparam integer FIFO_DEPTH=1<<FIFO_ADDR_WIDTH;
    localparam [2:0] STILL=0,SLIDE=1,CORNERS=2,CENTRE=3,ZOOM=4;
    reg [2:0] mode;
    reg [5:0] level;
    reg [9:0] offset;
    assign slide_offset=offset;
    reg direction;
    reg [20:0] old_base,target_base;
    reg [2:0] target_image;
    reg begin_frame,wait_commit;
    reg [2:0] commit_delay;
    reg [9:0] gen_y,source_y,y_remainder;

    // Each loop iteration is constant-folded by synthesis. Exact quotient /
    // remainder pairs implement floor(x*source_width/dest_width), without a
    // run-time divider or approximate reciprocal accumulation.
    function [59:0] geometry;
        input split;
        input [5:0] scale;
        integer n,sw,sh,dw,dh,qx,rx,qy,ry;
        begin
            geometry=0;
            for(n=1;n<=32;n=n+1) begin
                sw=FRAME_WIDTH/2;sh=H/2;
                dw=(sw*n)/32; if(dw<1)dw=1;
                dh=(sh*n)/32; if(dh<1)dh=1;
                qx=sw/dw;rx=sw%dw;qy=sh/dh;ry=sh%dh;
                if(scale==n && split)geometry={dw[9:0],dh[9:0],qx[9:0],rx[9:0],qy[9:0],ry[9:0]};
                sw=FRAME_WIDTH;sh=H;
                dw=(sw*n)/32; if(dw<1)dw=1;
                dh=(sh*n)/32; if(dh<1)dh=1;
                qx=sw/dw;rx=sw%dw;qy=sh/dh;ry=sh%dh;
                if(scale==n && !split)geometry={dw[9:0],dh[9:0],qx[9:0],rx[9:0],qy[9:0],ry[9:0]};
            end
        end
    endfunction
    wire [59:0] geom=geometry(mode==CORNERS,level);
    wire [9:0] width=geom[59:50],height=geom[49:40];
    wire [9:0] xq=geom[39:30],xr=geom[29:20],yq=geom[19:10],yr=geom[9:0];
    wire [9:0] y_start=(H-height)/2;
    wire visible_row=mode==CORNERS ? (level!=0 && (gen_y<height || gen_y>=H-height)) :
                     mode==CENTRE ? (level!=0 && gen_y>=y_start && gen_y<y_start+height) : 1'b1;
    wire [10:0] y_sum={1'b0,y_remainder}+{1'b0,yr};
    wire last_effect_frame=(mode==SLIDE && offset==FRAME_WIDTH) || (mode==CENTRE && level==32);

    reg [1:0] ready;
    reg fill_bank,emit_bank;
    reg [2:0] bank_mode[0:1];
    reg bank_blank[0:1],bank_final[0:1],bank_last[0:1];
    reg [9:0] bank_width[0:1],bank_start[0:1],bank_q[0:1],bank_r[0:1];
    reg [5:0] bank_alpha[0:1];
    reg [23:0] row_ram[0:2047];
    reg [23:0] ram_pixel;
    // Zoom window and source coordinates, latched/updated at frame and row edges.
    reg [9:0] zoom_win_x_q, zoom_win_y_q;
    reg [9:0] zoom_span_x_q, zoom_span_y_q;
    reg [9:0] zoom_src_x, zoom_src_y;
    reg [10:0] zoom_rem_x, zoom_rem_y;
    wire [10:0] zoom_sum_x = {1'b0,zoom_rem_x} + {1'b0,zoom_span_x_q};
    wire [10:0] zoom_sum_y = {1'b0,zoom_rem_y} + {1'b0,zoom_span_y_q};
    reg [9:0] emit_x,source_x,x_remainder;
    wire [10:0] x_sum={1'b0,x_remainder}+{1'b0,bank_r[emit_bank]};
    wire visible_pixel=!bank_blank[emit_bank] &&
        (bank_mode[emit_bank]==CORNERS ? (emit_x<bank_width[emit_bank] || emit_x>=FRAME_WIDTH-bank_width[emit_bank]) :
         bank_mode[emit_bank]==CENTRE ? (emit_x>=bank_start[emit_bank] && emit_x<bank_start[emit_bank]+bank_width[emit_bank]) : 1'b1);
    wire [9:0] ram_column = (bank_mode[emit_bank]==STILL || bank_mode[emit_bank]==SLIDE) ? emit_x :
        (bank_mode[emit_bank]==ZOOM ? (zoom_win_x_q+zoom_src_x) : source_x);
    // Leave space for the registered RAM read and the FIFO's write edge.
    wire issue_pixel=enable && !restart && ready[emit_bank] && !fifo_full && fifo_used_words<FIFO_DEPTH-8;
    reg emit_valid;
    reg [5:0] emit_alpha;
    assign fifo_wr_en=emit_valid && !restart && enable && !fifo_full;
    assign fifo_wr_data={2'b00,emit_alpha,(emit_alpha==0?24'd0:ram_pixel)};

    reg fetching,fetch_bank,fetch_start;
    reg [9:0] received;
    reg [20:0] fetch_old_row,fetch_target_row;
    reg fetch_slide,fetch_right;
    reg [9:0] fetch_offset;
    reg engine_running,burst_active;
    reg [9:0] issued,burst_count;
    wire [9:0] fetch_column=issued<FRAME_WIDTH ? issued : FRAME_WIDTH-4;
    wire [10:0] left_column={1'b0,fetch_column}+{1'b0,fetch_offset};
    wire from_target=fetch_right ? fetch_column<fetch_offset : left_column>=FRAME_WIDTH;
    wire [10:0] slide_column=fetch_right ?
        (from_target ? FRAME_WIDTH-fetch_offset+fetch_column : fetch_column-fetch_offset) :
        (from_target ? left_column-FRAME_WIDTH : left_column);
    wire [20:0] fetch_address=fetch_slide ?
        (from_target?fetch_target_row:fetch_old_row)+{10'd0,slide_column[10:2],2'b00} :
        fetch_old_row+{11'd0,fetch_column[9:2],2'b00};

    // APUG011 requests stay on the falling edge, as in the proven reader.
    // Every command is a complete BURST_WORDS run; a restart drains a full
    // source row before acknowledging, so no late response enters a new row.
    always @(negedge clk or posedge rst) begin
        if(rst) begin
            app_rd_en<=0;app_rd_addr<=0;engine_running<=0;
            burst_active<=0;issued<=0;burst_count<=0;
        end else begin
            app_rd_en<=0;
            if(fetch_start) begin engine_running<=1;issued<=0;burst_count<=0;end
            if(engine_running) begin
                if(burst_active) begin
                    app_rd_en<=1;app_rd_addr<=fetch_address;issued<=issued+1'b1;
                    if(burst_count==BURST_WORDS-1) begin
                        burst_active<=0;burst_count<=0;
                        if(issued==ROW_READ_WORDS-1)engine_running<=0;
                    end else burst_count<=burst_count+1'b1;
                end else if(init_done && !refresh && !busy)begin burst_active<=1;burst_count<=0;end
            end
        end
    end

    // Single write port and synchronous read port infer two 1024x24 row banks.
    // Reset only the ownership metadata, never the RAM contents.
    always @(posedge clk) begin
        if(fetching && rd_valid && received<FRAME_WIDTH)
            row_ram[{fetch_bank,received}]<=rd_data[23:0];
        if(issue_pixel)ram_pixel<=row_ram[{emit_bank,ram_column}];
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            mode<=STILL;level<=32;offset<=0;direction<=0;old_base<=0;target_base<=0;target_image<=0;
            slide_active<=0;slide_done<=0;slide_completed_image<=0;
            begin_frame<=1;wait_commit<=0;commit_delay<=0;gen_y<=0;source_y<=0;y_remainder<=0;
            ready<=0;fill_bank<=0;emit_bank<=0;emit_x<=0;source_x<=0;x_remainder<=0;
            fetching<=0;fetch_bank<=0;fetch_start<=0;received<=0;
            fetch_old_row<=0;fetch_target_row<=0;fetch_slide<=0;fetch_right<=0;fetch_offset<=0;
            emit_valid<=0;emit_alpha<=0;done<=0;restart_done<=0;
            bank_mode[0]<=STILL;bank_mode[1]<=STILL;
            bank_blank[0]<=1;bank_blank[1]<=1;bank_final[0]<=0;bank_final[1]<=0;
            bank_last[0]<=0;bank_last[1]<=0;bank_width[0]<=0;bank_width[1]<=0;
            bank_start[0]<=0;bank_start[1]<=0;bank_q[0]<=0;bank_q[1]<=0;
            bank_r[0]<=0;bank_r[1]<=0;bank_alpha[0]<=0;bank_alpha[1]<=0;
        end else begin
            fetch_start<=0;emit_valid<=issue_pixel;slide_done<=0;done<=0;restart_done<=0;
            if(fetching && rd_valid) begin
                received<=received+1'b1;
                if(received==ROW_READ_WORDS-1)begin
                    fetching<=0;
                    if(!restart && enable)ready[fetch_bank]<=1;
                end
            end
            if(restart || !enable)begin
                ready<=0;fill_bank<=0;emit_bank<=0;emit_x<=0;source_x<=0;x_remainder<=0;
                emit_valid<=0;begin_frame<=1;wait_commit<=0;commit_delay<=0;
                gen_y<=0;source_y<=0;y_remainder<=0;mode<=STILL;level<=32;offset<=0;slide_active<=0;
                if(restart && !fetching && !engine_running && !app_rd_en)restart_done<=1;
            end else begin
                if(commit_delay!=0)begin
                    commit_delay<=commit_delay-1'b1;
                    if(commit_delay==1)begin wait_commit<=0;begin_frame<=1;end
                end
                if(begin_frame && !wait_commit)begin
                    begin_frame<=0;old_base<=frame_base;
                    zoom_win_x_q<=zoom_win_x;zoom_win_y_q<=zoom_win_y;
                    zoom_span_x_q<=zoom_span_x;
                    zoom_span_y_q<=zoom_span_y;
                    zoom_src_x<=0;zoom_src_y<=0;zoom_rem_x<=0;zoom_rem_y<=0;
                    if(slide_request)begin
                        slide_active<=1;target_base<=slide_target_base;target_image<=slide_target_image;
                        direction<=slide_right;
                        if(request_manual)begin mode<=SLIDE;offset<=SLIDE_STEP>=FRAME_WIDTH?FRAME_WIDTH:SLIDE_STEP;end
                        else begin mode<=CORNERS;level<=31;offset<=0;end
                    end else begin mode<=(zoom_mode?ZOOM:STILL);level<=32;offset<=0;end
                end else if(!wait_commit && !fetching && !ready[fill_bank])begin
                    bank_mode[fill_bank]<=mode;
                    bank_blank[fill_bank]<=!visible_row;
                    bank_width[fill_bank]<=width;
                    bank_start[fill_bank]<=(FRAME_WIDTH-width)/2;
                    bank_q[fill_bank]<=xq;bank_r[fill_bank]<=xr;
                    bank_alpha[fill_bank]<=(mode==CORNERS || mode==CENTRE)?level:6'd32;
                    bank_final[fill_bank]<=gen_y==H-1 && last_effect_frame;
                    bank_last[fill_bank]<=gen_y==H-1;
                    if(visible_row)begin
                        fetching<=1;fetch_start<=1;fetch_bank<=fill_bank;received<=0;
                        fetch_slide<=mode==SLIDE;fetch_right<=direction;fetch_offset<=offset;
                        fetch_old_row<=(mode==CENTRE?target_base:old_base)+
                            ((mode==STILL || mode==SLIDE)?gen_y:
                             (mode==ZOOM?(zoom_win_y_q+zoom_src_y):source_y))*FRAME_WIDTH;
                        fetch_target_row<=target_base+gen_y*FRAME_WIDTH;
                    end else ready[fill_bank]<=1;
                    fill_bank<=!fill_bank;
                    if(visible_row)begin
                        if(mode==ZOOM)begin
                            if(zoom_sum_y>=H)begin zoom_src_y<=zoom_src_y+1'b1;zoom_rem_y<=zoom_sum_y-H;end
                            else zoom_rem_y<=zoom_sum_y;
                        end else if(mode==CORNERS && gen_y==height-1)begin source_y<=H/2;y_remainder<=0;end
                        else begin
                            source_y<=source_y+yq+(y_sum>=height);
                            y_remainder<=y_sum>=height ? y_sum-height : y_sum;
                        end
                    end
                    if(gen_y==H-1)begin
                        gen_y<=0;source_y<=0;y_remainder<=0;
                        if(last_effect_frame)wait_commit<=1;
                        else if(mode==STILL || mode==ZOOM)begin_frame<=1;
                        else if(mode==SLIDE)offset<=offset+SLIDE_STEP>=FRAME_WIDTH?FRAME_WIDTH:offset+SLIDE_STEP;
                        else if(mode==CORNERS)begin
                            if(level==0)begin mode<=CENTRE;level<=1;end
                            else level<=level>AUTO_STEP ? level-AUTO_STEP : 0;
                        end else if(mode==CENTRE)level<=level+AUTO_STEP>=32 ? 32 : level+AUTO_STEP;
                    end else gen_y<=gen_y+1'b1;
                end
                if(issue_pixel)begin
                    emit_alpha<=visible_pixel?bank_alpha[emit_bank]:6'd0;
                    if(bank_mode[emit_bank]==ZOOM)begin
                        if(zoom_sum_x>=FRAME_WIDTH)begin zoom_src_x<=zoom_src_x+1'b1;zoom_rem_x<=zoom_sum_x-FRAME_WIDTH;end
                        else zoom_rem_x<=zoom_sum_x;
                    end
                    if(visible_pixel)begin
                        if(bank_mode[emit_bank]==CORNERS && emit_x==bank_width[emit_bank]-1)begin
                            source_x<=FRAME_WIDTH/2;x_remainder<=0;
                        end else begin
                            source_x<=source_x+bank_q[emit_bank]+(x_sum>=bank_width[emit_bank]);
                            x_remainder<=x_sum>=bank_width[emit_bank] ? x_sum-bank_width[emit_bank] : x_sum;
                        end
                    end
                    if(emit_x==FRAME_WIDTH-1)begin
                        emit_x<=0;source_x<=0;x_remainder<=0;ready[emit_bank]<=0;emit_bank<=!emit_bank;
                        zoom_src_x<=0;zoom_rem_x<=0;
                        if(bank_last[emit_bank])done<=1;
                        if(bank_final[emit_bank])begin
                            slide_done<=1;slide_completed_image<=target_image;slide_active<=0;
                            mode<=(zoom_mode?ZOOM:STILL);level<=32;offset<=0;commit_delay<=3;
                        end
                    end else emit_x<=emit_x+1'b1;
                end
            end
        end
    end
endmodule
