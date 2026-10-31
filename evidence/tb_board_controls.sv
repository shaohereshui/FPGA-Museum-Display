`timescale 1ns/1ps
module tb_board_controls;
reg clk=0;always #5 clk=~clk;
reg rst=0,k2=1,k3=1,k4=1,sw1=0,sw2=0,sw3=0,sw4=0;
reg [15:0] ir=0,matrix=0;
wire [15:0] board_keys,routed,keys;
assign keys=board_keys|routed;
wire active,board_active,bs1,bs2,bs4,off2,change1,off4;
wire shared_zoom,pause_audio,zoom,exit_zoom,adj,ui,guide,trans,display;
wire [1:0] item,visual,transition;wire [3:0] br,co;wire [6:0] vol;
wire [9:0] sx,sy,wx,wy;wire prev,next,menu_zoom,audio_enable,manual;
board_controls #(.DEBOUNCE_CYCLES(3),.LONG_CYCLES(100),.PULSE_CYCLES(12)) board(
 .clk(clk),.rst_n(rst),.k2_n(k2),.k3_n(k3),.k4_n(k4),.sw1(sw1),.sw2(sw2),.sw3(sw3),.sw4(sw4),
 .zoom_on(zoom),.ui_busy(ui|guide|trans|adj),.zoom_exit(exit_zoom),.keys_down(board_keys),
 .user_active(board_active),.audio_switch(bs1),.zoom_switch(bs2),.emergency_switch(bs4),
 .zoom_off(off2),.audio_changed(change1),.emergency_off(off4));
media_input_router #(.DEBOUNCE_CYCLES(3)) router(
 .clk(clk),.rst_n(rst),.matrix_keys(matrix),.ir_keys(ir),.ir_activity(|ir),.ir_emergency(1'b0),
 .zoom_context(zoom),.zoom_exit(exit_zoom|off2),.audio_clear(change1),.keys_down(routed),.user_active(active),
 .audio_pause(pause_audio),.zoom_enable(shared_zoom),.emergency_enable());
media_control #(.DEBOUNCE_CYCLES(3),.HOLD_DELAY_CYCLES(100),.REPEAT_CYCLES(20),
 .VIS_HOLD_CYCLES(100),.IDLE_TIMEOUT_CYCLES(100000),.AUTO_LIGHT_CYCLES(2000),
 .MANUAL_IDLE_CYCLES(4000),.ZOOM_RAMP_CYCLES(100)) ctrl(
 .host_valid(1'b0),.host_command(8'd0),.host_value(8'd0),
 .clk(clk),.rst_n(rst),.key_prev_n(!keys[1]),.key_next_n(!keys[9]),.key_mode_n(1'b1),
 .volume_down_n(!keys[4]),.volume_up_n(!keys[6]),.key_menu_n(!keys[5]),
 .key_confirm_n(!keys[14]),.key_back_n(!keys[12]),.key_zoom_in_n(!keys[3]),
 .key_zoom_out_n(!keys[11]),.key_visual_n(!keys[7]),.ambient_level(4'd4),.ambient_valid(1'b1),
 .external_activity(active|board_active),.board_zoom_off(off2),
 .sw_param(bs2|shared_zoom),.sw_audio(bs1|pause_audio),.sw_volume(1'b0),
 .prev_image_press(prev),.next_image_press(next),.brightness(br),.brightness_manual(manual),.contrast(co),.volume(vol),
 .adjust_mode(adj),.ui_active(ui),.ui_item(item),.ui_guide(guide),.ui_trans(trans),.ui_display(display),
 .visual_mode(visual),.trans_mode(transition),.audio_enable(audio_enable),
 .zoom_menu_active(menu_zoom),.zoom_on(zoom),.zoom_exit_req(exit_zoom),
 .zoom_span_x(sx),.zoom_span_y(sy),.zoom_win_x(wx),.zoom_win_y(wy));
// Real decoder emergency latch; tests inject validated frame events below.
wire ir_emergency;
ir_nec_keys #(.CLK_HZ(1000000),.HOLD_CYCLES(150000)) ir_receiver(
 .clk(clk),.rst_n(rst),.ir_rx(1'b1),.emergency_clear(off4),.emergency_active(ir_emergency));
integer pc=0,nc=0,oldx,oldy,oldstep,i,backs=0,oldbacks,oldvol;
always @(posedge clk) begin
 if(prev)pc=pc+1;if(next)nc=nc+1;if(ctrl.back_press)backs=backs+1;
 #1;if(rst && zoom && (wx+sx>720 || wy+sy>480))$fatal(1,"viewport out of bounds");
end
task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
task tap(input integer k);begin
 case(k)2:k2=0;3:k3=0;4:k4=0;endcase tick(20);
 case(k)2:k2=1;3:k3=1;4:k4=1;endcase tick(40);
end endtask
task back;begin k4=0;tick(140);k4=1;tick(40);end endtask
task chord(input integer k);begin
 k4=0;tick(12);if(k==2)k2=0;else k3=0;tick(20);
 if(k==2)k2=1;else k3=1;tick(12);k4=1;tick(40);
end endtask
task remote(input integer k);begin ir=16'h1<<k;tick(25);ir=0;tick(20);end endtask
initial begin
 tick(3);rst=1;tick(20);
 // Mechanical glitches must never become a click/menu/switch operation.
 k2=0;tick(1);k2=1;k4=0;tick(1);k4=1;sw3=1;tick(1);sw3=0;tick(40);
 if(pc||ui||visual)$fatal(1,"bounce created action");
 tap(2);tap(3);if(pc!=1||nc!=1)$fatal(1,"image previous/next");
 tap(4);if(!ui||item!=0)$fatal(1,"K4 menu");
 tap(4);if(!guide)$fatal(1,"GUIDE entry");
 back();if(guide||!ui)$fatal(1,"GUIDE back");
 // DISPLAY: contrast, brightness, volume, confirm and every BACK level.
 tap(3);tap(4);if(!display||item!=0)$fatal(1,"DISPLAY entry");
 tap(4);tap(2);if(co!=6||!adj)$fatal(1,"contrast increment");tap(3);if(co!=5)$fatal(1,"contrast decrement");
 tap(4);if(adj||!display)$fatal(1,"confirm adjustment");
 tap(3);tap(4);oldvol=br;tap(2);if(br!=oldvol+1||!manual)$fatal(1,"manual brightness");
 back();if(adj||!display)$fatal(1,"back from brightness");
 tap(3);tap(4);if(!adj||!ctrl.volume_select)$fatal(1,"VOL entry");
 k2=0;tick(180);k2=1;tick(40);if(vol<=51)$fatal(1,"volume hold repeat");
 oldvol=vol;tap(3);if(vol!=oldvol-1)$fatal(1,"volume decrement");
 back();back();if(display||!ui||item!=1)$fatal(1,"DISPLAY back chain");
 // Each transition is selectable using only physical buttons.
 tap(3);tap(4);if(!trans)$fatal(1,"TRANS entry");
 tap(3);tap(4);if(trans||transition!=0)$fatal(1,"CORNERS selection");
 tap(4);tap(3);tap(4);if(transition!=1)$fatal(1,"SLIDE selection");
 tap(4);tap(3);tap(4);if(transition!=2)$fatal(1,"FADE selection");
 oldbacks=backs;k4=0;tick(400);k4=1;tick(50);
 if(ui||backs!=oldbacks+1)$fatal(1,"long K4 must BACK once and no release menu");
 // SW3 changes the visualizer only outside menus and zoom.
 sw3=1;tick(40);if(visual!=1)$fatal(1,"visual waveform");
 sw3=0;tick(40);if(visual!=0)$fatal(1,"visual bars");
 // Board SW1 can resume a prior remote/matrix pause.
 remote(13);if(audio_enable)$fatal(1,"remote pause");
 sw1=1;tick(40);if(audio_enable||pause_audio)$fatal(1,"SW1 high and clear pause");
 sw1=0;tick(40);if(!audio_enable)$fatal(1,"SW1 resume");
 // Physical SW2, directional axes and K4 modifier scaling.
 sw2=1;tick(40);if(!zoom)$fatal(1,"SW2 entry");
 chord(2);if(sx!=640||ui)$fatal(1,"K4+K2 magnify");
 oldx=wx;oldy=wy;tap(2);if(wy>=oldy||wx!=oldx)$fatal(1,"vertical up");
 tap(3);if(wy!=oldy)$fatal(1,"vertical down");
 sw3=1;tick(50);oldx=wx;oldy=wy;oldstep=ctrl.zoom_step;
 tick(300);if(ctrl.zoom_step!=oldstep||visual!=0)$fatal(1,"SW3 must not auto-zoom or toggle visual in zoom");
 tap(2);if(wx>=oldx||wy!=oldy)$fatal(1,"horizontal left");tap(3);if(wx!=oldx)$fatal(1,"horizontal right");
 // Releasing K4 first must not convert a held scaling key to panning.
 k4=0;tick(12);k2=0;tick(20);oldx=wx;oldy=wy;k4=1;tick(180);
 if(ui||!zoom||wx!=oldx||wy!=oldy||ctrl.zoom_step!=2)$fatal(1,"chord release leaked");k2=1;tick(40);
 // Press K4 first and keep it down across multiple scaling clicks.
 k4=0;tick(12);for(i=0;i<8;i=i+1)tap(2);k4=1;tick(40);
 if(sx!=360||ui||!zoom)$fatal(1,"held modifier scale limit or unwanted BACK");
 for(i=0;i<25;i=i+1)tap(3);if(wx!=360)$fatal(1,"right boundary");
 for(i=0;i<10;i=i+1)chord(3);if(sx!=720||wx!=0)$fatal(1,"shrink bounds");
 // Menus have precedence over physical pan and modifier scaling.
 tap(4);if(!ui)$fatal(1,"K4 menu while zooming");
 oldstep=ctrl.zoom_step;tap(3);if(item!=1||ctrl.zoom_step!=oldstep)$fatal(1,"menu navigation precedence");
 back();if(ui||!zoom)$fatal(1,"first back closes menu");back();if(zoom||bs2)$fatal(1,"back overrides held SW2");
 tick(200);if(zoom)$fatal(1,"SW2 cannot immediately reenter");
 sw2=0;tick(40);sw2=1;tick(40);if(!zoom)$fatal(1,"SW2 rearm");sw2=0;tick(40);if(zoom)$fatal(1,"SW2 exit");
 // GUIDE zoom entry/exit with physical buttons only, SW2 low.
 tap(4);tap(4);tap(3);tap(4);if(!zoom||!menu_zoom)$fatal(1,"board GUIDE zoom entry");
 back();if(zoom||menu_zoom)$fatal(1,"board GUIDE zoom exit");
 remote(2);if(!shared_zoom)$fatal(1,"remote zoom entry");sw2=1;tick(40);sw2=0;tick(40);
 if(zoom||shared_zoom||menu_zoom)$fatal(1,"SW2 off clears remote zoom");
 // SW4 off clears the real decoder's previously latched emergency.
 force ir_receiver.command=8'h5A;force ir_receiver.frame_valid=1;tick(1);
 release ir_receiver.command;release ir_receiver.frame_valid;tick(10);
 if(!ir_emergency)$fatal(1,"IR emergency injection");
 sw4=1;tick(40);if(!bs4)$fatal(1,"SW4 emergency entry");sw4=0;tick(40);
 if(bs4||ir_emergency)$fatal(1,"SW4 exit remote emergency");
 // Manual brightness hold and subsequent auto recovery still function.
 tap(4);tap(3);tap(4);tap(3);tap(4);tap(2);oldvol=br;
 k4=0;tick(3000);if(br!=oldvol||!manual)$fatal(1,"held board input must hold manual brightness");
 k4=1;tick(4050);if(manual||br!=4)$fatal(1,"manual idle auto-light recovery");
 rst=0;tick(5);rst=1;tick(30);if(ui||guide||zoom||co!=5||vol!=50||manual)$fatal(1,"K1 reset");
 $display("PASS: board-only complete menu tree, DISPLAY values/repeat, GUIDE/TRANS, long-back/no-tap, two-axis pan, chord scaling/release/bounds, SW3 visual/context, switch override of remote pause/zoom/emergency, ambient/manual idle, bounce and reset");$finish;
end
initial begin tick(100000);$fatal(1,"timeout");end
endmodule
