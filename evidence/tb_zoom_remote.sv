`timescale 1ns/1ps
module tb_zoom_remote;
reg clk=0;always #5 clk=~clk;
reg rst=0;reg [15:0] ir=0,matrix=0;reg emergency=0,sw2=0;
wire [15:0] keys;wire active,pause_audio,shared_zoom,emerg,zoom,exit_zoom;
wire [3:0] brightness,contrast;wire [6:0] volume;
wire adj,ui,guide,trans,display;wire [1:0] item;
wire [9:0] sx,sy,wx,wy;wire prev,next,menu_zoom;
media_input_router #(.DEBOUNCE_CYCLES(3)) router(
 .clk(clk),.rst_n(rst),.matrix_keys(matrix),.ir_keys(ir),.ir_activity(|ir),.ir_emergency(emergency),
 .audio_clear(1'b0),.zoom_context(zoom),.zoom_exit(exit_zoom),.keys_down(keys),.user_active(active),
 .audio_pause(pause_audio),.zoom_enable(shared_zoom),.emergency_enable(emerg));
media_control #(.DEBOUNCE_CYCLES(3),.HOLD_DELAY_CYCLES(1000),.REPEAT_CYCLES(100),
 .VIS_HOLD_CYCLES(1000),.IDLE_TIMEOUT_CYCLES(100000),.AUTO_LIGHT_CYCLES(100000),
 .MANUAL_IDLE_CYCLES(200000),.ZOOM_RAMP_CYCLES(1000)) ctrl(
 .host_valid(1'b0),.host_command(8'd0),.host_value(8'd0),
 .clk(clk),.rst_n(rst),.key_prev_n(!keys[1]),.key_next_n(!keys[9]),.key_mode_n(1'b1),
 .volume_down_n(!keys[4]),.volume_up_n(!keys[6]),.key_menu_n(!keys[5]),
 .key_confirm_n(!keys[14]),.key_back_n(!keys[12]),.key_zoom_in_n(!keys[3]),
 .key_zoom_out_n(!keys[11]),.key_visual_n(!keys[7]),.ambient_level(4'd5),.ambient_valid(1'b0),
 .board_zoom_off(1'b0),.external_activity(active),.sw_param(sw2|shared_zoom),.sw_audio(pause_audio),.sw_volume(1'b0),
 .prev_image_press(prev),.next_image_press(next),.brightness(brightness),.contrast(contrast),.volume(volume),
 .adjust_mode(adj),.ui_active(ui),.ui_item(item),.ui_guide(guide),.ui_trans(trans),.ui_display(display),
 .zoom_menu_active(menu_zoom),.zoom_on(zoom),.zoom_exit_req(exit_zoom),
 .zoom_span_x(sx),.zoom_span_y(sy),.zoom_win_x(wx),.zoom_win_y(wy));
integer i,oldx,oldy,oldstep,prev_count=0,next_count=0;
always @(posedge clk)begin
 if(prev)prev_count=prev_count+1;if(next)next_count=next_count+1;
 #1;if(rst && zoom && (wx+sx>720 || wy+sy>480))$fatal(1,"viewport outside frame: %d %d %d %d",wx,wy,sx,sy);
end
task press(input integer bitno);
begin @(negedge clk);ir=16'h1<<bitno;repeat(25)@(negedge clk);ir=0;repeat(15)@(negedge clk);end
endtask
initial begin
 repeat(3)@(negedge clk);rst=1;repeat(10)@(negedge clk);
 // Existing ordinary-mode direction functions remain image previous/next.
 press(1);press(9);if(prev_count!=1||next_count!=1)$fatal(1,"normal image keys");
 // A long IR3 starts zoom exactly once; mapping must not switch during hold.
 ir=16'h0004;repeat(200)@(negedge clk);
 if(!zoom || !shared_zoom || keys!==16'h0004 || ctrl.zoom_step!=0)$fatal(1,"entry key remapped mid-hold");
 ir=0;repeat(15)@(negedge clk);
 press(3);if(sx!=640)$fatal(1,"IR1 zoom in");
 oldx=wx;oldy=wy;press(1);if(wy>=oldy || wx!=oldx)$fatal(1,"up pan");
 press(9);if(wy!=oldy)$fatal(1,"down pan");
 press(4);if(wx>=oldx)$fatal(1,"left pan");press(6);if(wx!=oldx)$fatal(1,"right pan");
 if(prev_count!=1 || next_count!=1 || volume!=50 || brightness!=5 || contrast!=5)$fatal(1,"pan leaked to other action");
 // IR3 shrinks without clearing the mode latch.
 press(2);if(sx!=720 || !zoom || !shared_zoom)$fatal(1,"IR3 must shrink, not toggle");
 press(2);if(sx!=720 || !zoom)$fatal(1,"1x lower limit");
 // Exercise max zoom and pan all the way into both edges, then shrink to 1x.
 for(i=0;i<10;i=i+1)press(3);
 if(sx!=360 || sy!=240)$fatal(1,"2x upper limit");
 for(i=0;i<20;i=i+1)begin press(6);press(9);end
 if(wx!=360 || wy!=240)$fatal(1,"bottom-right pan limit");
 for(i=0;i<8;i=i+1)press(2);
 if(sx!=720 || wx!=0 || wy!=0)$fatal(1,"shrink must clamp viewport");
 for(i=0;i<8;i=i+1)press(3);
 for(i=0;i<20;i=i+1)begin press(4);press(1);end
 for(i=0;i<8;i=i+1)press(2);
 if(wx!=0 || wy!=0)$fatal(1,"top-left shrink clamp");
 // Menus take precedence over panning/scaling while the zoom view remains.
 press(5);if(!ui)$fatal(1,"menu from zoom");
 oldstep=ctrl.zoom_step;oldx=wx;oldy=wy;press(9);
 if(item!=1 || wx!=oldx || wy!=oldy)$fatal(1,"menu navigation should not pan");
 press(2);press(3);if(!shared_zoom || ctrl.zoom_step!=oldstep)$fatal(1,"menu scaling collision");
 press(12);if(ui || !zoom)$fatal(1,"first back closes menu only");
 press(12);if(zoom || shared_zoom || menu_zoom)$fatal(1,"back exits remote zoom");
 // GUIDE -> ZOOM entry uses the same remote pan/scale mapping and * exit.
 press(5);press(14);if(!guide)$fatal(1,"GUIDE entry");press(9);press(14);
 if(!zoom || !menu_zoom)$fatal(1,"menu ZOOM entry");press(3);press(2);
 if(!zoom || sx!=720)$fatal(1,"menu ZOOM scaling");press(12);
 if(zoom || menu_zoom)$fatal(1,"menu ZOOM exit");
 // Matrix 3 still toggles independently; original IR7 still shrinks.
 matrix=16'h0004;repeat(25)@(negedge clk);matrix=0;repeat(15)@(negedge clk);
 if(!zoom)$fatal(1,"matrix toggle");press(3);press(11);if(sx!=720)$fatal(1,"legacy IR7 alias");press(12);
 press(13);if(!pause_audio)$fatal(1,"pause regression");press(13);if(pause_audio)$fatal(1,"resume regression");
 emergency=1;#1;if(!emerg)$fatal(1,"emergency regression");emergency=0;
 // Physical SW2 remains authoritative, as before.
 sw2=1;repeat(15)@(negedge clk);press(12);if(!zoom)$fatal(1,"SW2 priority");sw2=0;repeat(15)@(negedge clk);
 if(zoom)$fatal(1,"SW2 release");
 $display("PASS: IR3 held-entry/context, 1/3 scale, 4 directions, no action leakage, bounds/edge shrink, menu priority, * exit for remote and GUIDE zoom, matrix/IR7/pause/emergency/SW2 regression");$finish;
end
endmodule
