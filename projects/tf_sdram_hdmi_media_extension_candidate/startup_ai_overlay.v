// Museum release: supplied tenth-anniversary artwork, aspect-preserving 720x250.
// Keep v39 startup lifetime and fade/breath animation. One-pixel ROM lookahead
// preserves the existing zero-extra-cycle overlay pipeline.
module startup_ai_overlay (
    input wire clk,rst_n,
    input wire media_visible,load_error,
    input wire de,
    input wire [9:0] h_count,v_count,
    input wire [23:0] rgb_in,
    output wire [23:0] rgb_out,
    output wire active
);
    localparam integer TOP=115, BOTTOM=365;
    reg [1:0] logo_rom[0:65535];
    initial $readmemh("startup_anniversary.hex",logo_rom);
    reg [1:0] ink;
    // During blanking prime x=0 of the NEXT line, including the first row.
    wire blank=h_count>=720;
    wire [9:0] next_y=v_count==524?10'd0:v_count+1'b1;
    wire [9:0] read_y=blank?next_y:v_count;
    wire read_inside=read_y>=TOP && read_y<BOTTOM;
    wire [9:0] local_read_y=read_y-TOP;
    wire [6:0] row=local_read_y[7:1];
    wire [10:0] next_x={1'b0,h_count}+1'b1;
    wire [8:0] column=blank?9'd0:next_x[9:1];
    wire [15:0] row_wide={9'd0,row};
    // row*360 = row*256+row*64+row*32+row*8; no DSP.
    wire [15:0] address=read_inside ?
        (row_wide<<8)+(row_wide<<6)+(row_wide<<5)+(row_wide<<3)+column : 16'd0;
    always @(posedge clk) ink<=logo_rom[address];
`include "startup_anniversary_palette.vh"
    reg finished,error_frame,frame_start_prev;
    reg [4:0] fade_age;
    reg [5:0] breath_phase;
    wire [4:0] breath=breath_phase[5]?~breath_phase[4:0]:breath_phase[4:0];
    wire [5:0] phase=fade_age<31?{1'b0,fade_age}:{1'b1,breath};
    wire frame_start=h_count==0 && v_count==0;
    wire logo_inside=de && h_count<720 && v_count>=TOP && v_count<BOTTOM;
    assign active=!finished && !media_visible && !error_frame;
    assign rgb_out=active ? (logo_inside ? anniversary_color(ink,phase) : 24'd0) : rgb_in;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            finished<=0;error_frame<=0;frame_start_prev<=0;fade_age<=0;breath_phase<=0;
        end else begin
            frame_start_prev<=frame_start;
            if(frame_start && !frame_start_prev) begin
                if(media_visible) finished<=1;
                error_frame<=load_error;
                if(!finished && !media_visible) begin
                    if(fade_age!=31) fade_age<=fade_age+1'b1;
                    else breath_phase<=breath_phase+1'b1;
                end
            end
        end
    end
endmodule
