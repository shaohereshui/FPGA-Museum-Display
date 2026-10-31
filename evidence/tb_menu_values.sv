`timescale 1ns/1ps
module tb_menu_values;
reg clk=0;always #5 clk=~clk;
reg rst=0,de=0,menu=1,guide=0,trans=0;
reg editing=0;reg [3:0] br=5,co=5;reg [6:0] vol=50;
reg [9:0] h=1,v=1;reg [23:0] bg=0;
reg [23:0] background[0:345599];
wire [23:0] osd_rgb,out;wire [7:0] ack;wire av;
hdmi_osd_5x7 osd(
 .de(de),.h_count(h),.v_count(v),.video_rgb(bg),
 .image_index(3'd0),.requested_index(3'd0),.status_bits(8'd0),.progress_bits(4'd0),.load_index(3'd0),
 .error_code(5'd0),.error_source(3'd0),.cmd0_r1(8'd0),
 .audio_playing(1'b0),.audio_error(1'b0),.audio_enabled(1'b0),.audio_code(5'd0),
 .adjust_mode(editing),.param_select(1'b0),.brightness(br),.contrast(co),.volume(vol),.volume_select(1'b0),
 .ui_active(menu),.ui_item(2'd0),.ui_guide(guide),.ui_trans(trans),.ui_display(1'b1),.zoom_mode(1'b0),
 .accent_color(24'hff6000),.fault_held(1'b0),.fault_source(3'd0),.fault_code(5'd0),.fault_count(4'd0),.self_ok(1'b1),
 .rgb_out(osd_rgb)
);
museum_subtitle sub(.clk(clk),.rst_n(rst),.rx_data(8'd0),.rx_valid(1'b0),.rx_error(1'b0),
 .tx_data(ack),.tx_valid(av),.show(1'b1),.de(de),.h_count(h),.v_count(v),
 .rgb_in(osd_rgb),.rgb_out(out),.tx_busy(1'b0),.control_status(96'd0),
 .control_valid(),.control_command(),.control_value());
integer x,y,fd,n;
task render(input [255:0] name);
begin
 fd=$fopen(name,"w");$fwrite(fd,"P3\n720 480\n255\n");
 for(y=0;y<480;y=y+1)for(x=0;x<720;x=x+1)begin
  @(negedge clk);h=x;v=y;de=1;bg=background[y*720+x];
  @(posedge clk);#1;$fwrite(fd,"%d %d %d\n",out[23:16],out[15:8],out[7:0]);
 end
 $fclose(fd);
end
endtask
task expect_row(input integer row,input [63:0] text);
begin
 @(negedge clk);h=300;v=2+row*16;de=1;#1;
 if(osd.ui_menu_text!==text)$fatal(1,"row %d expected %s got %s",row,text,osd.ui_menu_text);
 if(osd.ui_color!==24'h000000)$fatal(1,"menu text must remain black");
end
endtask
initial begin
 $readmemh("background.hex",background);
 repeat(3)@(negedge clk);rst=1;
 de=1;
 for(y=72;y<86;y=y+1)for(x=16;x<272;x=x+1)begin
  h=x;v=y;bg=(y*720+x)^24'h123456;#1;
  if(osd_rgb!==bg)$fatal(1,"former ADC diagnostic region overwrites video at %0d,%0d",x,y);
 end
 $display("PASS: all 3584 pixels of former ADC diagnostic row preserve video");
 expect_row(0,"CON   5 ");expect_row(1,"BRI   5 ");expect_row(2,"VOL  50%");
 vol=0;br=0;co=0;
 expect_row(0,"CON   0 ");expect_row(1,"BRI   0 ");expect_row(2,"VOL   0%");
 vol=9;expect_row(2,"VOL   9%");vol=10;expect_row(2,"VOL  10%");
 vol=99;expect_row(2,"VOL  99%");vol=100;br=9;co=9;
 expect_row(0,"CON   9 ");expect_row(1,"BRI   9 ");expect_row(2,"VOL 100%");
 vol=127;expect_row(2,"VOL 100%");
 editing=1;#1;if(osd.header_active)$fatal(1,"adjust header must not overwrite DISPLAY rows");
 vol=73;br=6;co=4;
 expect_row(0,"CON   4 ");expect_row(1,"BRI   6 ");expect_row(2,"VOL  73%");
 render("menu_values_edit.ppm");
 editing=0;vol=100;br=9;co=0;render("menu_values_limits.ppm");
 $display("PASS: live CON/BRI values, VOL 0/9/10/50/73/99/100 and clamp, black text, edit header suppression, RTL render");$finish;
end
endmodule
