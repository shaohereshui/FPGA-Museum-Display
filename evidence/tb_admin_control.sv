`timescale 1ns/1ps
module tb_admin_control;
 reg clk=0,rst_n=0,rx=1;
 always #5 clk=~clk;
 wire [7:0] rx_data,tx_data,host_rx;
 wire rx_valid,rx_error,tx_valid,tx_busy,tx,host_rx_valid,host_rx_error;
 wire command_valid;
 wire [7:0] command,value;
 wire [3:0] brightness,contrast;
 wire [6:0] volume;
 wire manual,audio;
 wire [1:0] transition,visual;
 wire [2:0] requested;
 reg carousel=1,audio_pause=0;
 reg [3:0] ambient=7;
 reg ambient_valid=1,physical_audio_pause=0;
 reg [9:0] h=1,v=1;
 wire [7:0] flags={ambient_valid,audio_pause,1'b0,1'b0,1'b1,audio,carousel,manual};
 wire [95:0] status={8'd2,8'd0,{5'd0,requested},{1'b0,volume},
  {4'd0,brightness},{4'd0,contrast},flags,16'h0c34,{6'd0,transition},{6'd0,visual},8'd0};
 subtitle_uart #(.CLOCK_HZ(1000000),.BAUD(100000)) uart(
  .clk(clk),.rst_n(rst_n),.rx(rx),.rx_data(rx_data),.rx_valid(rx_valid),.rx_error(rx_error),
  .tx_data(tx_data),.tx_valid(tx_valid),.tx(tx),.tx_busy(tx_busy));
 subtitle_uart #(.CLOCK_HZ(1000000),.BAUD(100000)) host(
  .clk(clk),.rst_n(rst_n),.rx(tx),.rx_data(host_rx),.rx_valid(host_rx_valid),
  .rx_error(host_rx_error),.tx_data(8'd0),.tx_valid(1'b0),.tx(),.tx_busy());
 museum_subtitle #(.RX_TIMEOUT(2000)) parser(
  .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.rx_error(rx_error),
  .tx_data(tx_data),.tx_valid(tx_valid),.tx_busy(tx_busy),.control_status(status),
  .control_valid(command_valid),.control_command(command),.control_value(value),
  .show(1'b1),.de(1'b0),.h_count(h),.v_count(v),.rgb_in(24'd0),.rgb_out());
 media_control #(.DEBOUNCE_CYCLES(3),.AUTO_LIGHT_CYCLES(10000),
  .MANUAL_IDLE_CYCLES(50000)) controls(
  .clk(clk),.rst_n(rst_n),.host_valid(command_valid),.host_command(command),.host_value(value),
  .key_prev_n(1'b1),.key_next_n(1'b1),.key_mode_n(1'b1),.volume_down_n(1'b1),
  .volume_up_n(1'b1),.key_menu_n(1'b1),.key_confirm_n(1'b1),.key_back_n(1'b1),
  .key_zoom_in_n(1'b1),.key_zoom_out_n(1'b1),.key_visual_n(1'b1),
  .ambient_level(ambient),.ambient_valid(ambient_valid),.external_activity(1'b0),
  .board_zoom_off(1'b0),.sw_param(1'b0),.sw_audio(physical_audio_pause|audio_pause),
  .sw_volume(1'b0),.brightness(brightness),.brightness_manual(manual),
  .contrast(contrast),.volume(volume),.audio_enable(audio),.trans_mode(transition),.visual_mode(visual),
  .prev_image_press(),.next_image_press(),.adjust_mode(),.param_select(),.volume_select(),
  .ui_active(),.ui_item(),.ui_guide(),.ui_trans(),.ui_display(),.zoom_menu_active(),
  .zoom_on(),.zoom_exit_req(),.zoom_span_x(),.zoom_span_y(),.zoom_win_x(),.zoom_win_y(),.pan_axis());
 image_select_control #(.AUTO_INTERVAL_CYCLES(10000)) images(
  .clk(clk),.rst_n(rst_n),.ready(1'b1),.pause(!carousel),
  .prev_press(command_valid && command==8'h25),.next_press(command_valid && command==8'h26),
  .host_select(command_valid && command==8'h20),.host_image(value[2:0]),
  .requested_image(requested),.request_manual(),.request_right(),.request_toggle());
 always @(posedge clk) if(!rst_n)begin carousel<=1;audio_pause<=0;end
 else if(command_valid)begin
  if(command==8'h24)carousel<=value[0];
  if(command==8'h29)audio_pause<=value[0];
 end
 reg [7:0] replies[0:255];
 integer received=0,commands=0;
 always @(posedge clk)begin
  if(host_rx_error)$fatal(1,"UART reply framing error");
  if(host_rx_valid)begin replies[received]=host_rx;received=received+1;end
  if(command_valid)commands=commands+1;
 end
 function [15:0] crc_byte(input [15:0] c,input [7:0] b);
  reg [15:0] t;integer j;
  begin t=c^{b,8'd0};for(j=0;j<8;j=j+1)t=t[15]?(t<<1)^16'h1021:t<<1;crc_byte=t;end
 endfunction
 task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
 task byte_out(input [7:0] b);
  integer j;
  begin rx=0;tick(10);for(j=0;j<8;j=j+1)begin rx=b[j];tick(10);end rx=1;tick(10);end
 endtask
 task wait_reply(input integer count);
  integer limit;
  begin
   limit=0;while(received<count && limit<5000)begin tick(1);limit=limit+1;end
   if(received!=count)$fatal(1,"reply length %0d expected %0d",received,count);
   tick(30);
  end
 endtask
 task control(input [7:0] cmd,input [7:0] val,input bit corrupt,input bit accepted);
  reg [15:0] c;integer j;
  begin
   received=0;c=crc_byte(crc_byte(16'hffff,cmd),val);
   byte_out(8'ha5);byte_out(8'h5a);byte_out(cmd);byte_out(val);
   byte_out(c[15:8]);byte_out(c[7:0]^{7'd0,corrupt});
   wait_reply(accepted?15:1);
   if(replies[0] !== (accepted?8'h06:8'h15))$fatal(1,"wrong ACK/NAK");
   if(accepted)begin
    c=16'hffff;for(j=1;j<=12;j=j+1)c=crc_byte(c,replies[j]);
    if({replies[13],replies[14]}!==c || replies[1]!==2)$fatal(1,"bad status CRC/version");
   end
  end
 endtask
 integer before_commands,j;
 reg [15:0] c;
 initial begin
  tick(5);rst_n=1;tick(10);
  control(8'h24,0,0,1);
  control(8'h20,4,0,1);if(requested!==4 || replies[3]!==4)$fatal(1,"direct image 5");
  control(8'h26,0,0,1);if(requested!==0)$fatal(1,"next wrap");
  control(8'h25,0,0,1);if(requested!==4)$fatal(1,"previous wrap");
  control(8'h21,73,0,1);if(volume!==73 || replies[4]!==73)$fatal(1,"volume");
  control(8'h22,6,0,1);if(brightness!==6 || !manual || !replies[7][0])$fatal(1,"manual brightness");
  control(8'h23,4,0,1);if(contrast!==4)$fatal(1,"contrast");
  control(8'h27,1,0,1);if(transition!==1)$fatal(1,"transition");
  control(8'h28,1,0,1);if(visual!==1)$fatal(1,"visual");
  control(8'h29,1,0,1);if(audio || replies[7][2] || !replies[7][6])$fatal(1,"pause audio");
  control(8'h29,0,0,1);if(!audio || !replies[7][2])$fatal(1,"resume audio");
  physical_audio_pause=1;tick(10);control(8'h29,0,0,1);
  if(audio || replies[7][2])$fatal(1,"physical audio switch must remain authoritative");
  physical_audio_pause=0;tick(10);
  before_commands=commands;
  control(8'h21,9,1,0);if(volume!==73 || commands!=before_commands)$fatal(1,"bad CRC applied");
  control(8'h20,5,0,0);if(requested!==4)$fatal(1,"invalid image applied");
  control(8'h21,101,0,0);control(8'h22,10,0,0);control(8'h23,10,0,0);
  control(8'h24,2,0,0);control(8'h27,3,0,0);control(8'h28,2,0,0);control(8'h29,2,0,0);
  received=0;byte_out(8'ha5);byte_out(8'h5a);byte_out(8'h21);byte_out(8'd8);
  wait_reply(1);if(replies[0]!==8'h15 || volume!==73)$fatal(1,"partial control applied");
  // Polling must not refresh the existing manual brightness idle timer.
  control(8'h22,6,0,1);before_commands=commands;
  for(j=0;j<26;j=j+1)control(8'h02,0,0,1);
  if(commands!=before_commands || manual || brightness!==ambient)$fatal(1,"polling delayed auto light");
  control(8'h22,3,0,1);control(8'h22,8'hff,0,1);
  if(manual || brightness!==7)$fatal(1,"explicit auto light");
  control(8'h24,1,0,1);tick(11000);
  if(requested!==0)$fatal(1,"carousel did not resume");
  control(8'h24,0,0,1);before_commands=requested;tick(12000);
  if(requested!==before_commands)$fatal(1,"carousel pause");
  // Existing subtitle upload remains atomic at a video frame boundary.
  received=0;c=crc_byte(16'hffff,8'd1);
  byte_out(8'ha5);byte_out(8'h5a);byte_out(8'h01);byte_out(8'd1);
  for(j=0;j<32;j=j+1)begin byte_out(j);c=crc_byte(c,j);end
  byte_out(c[15:8]);byte_out(c[7:0]);tick(20);
  if(received!=0 || !parser.pending || parser.custom_active)$fatal(1,"subtitle activated early");
  h=0;v=0;tick(1);h=1;v=1;wait_reply(1);
  if(replies[0]!==8'h06 || !parser.custom_active || parser.text_length!==1)$fatal(1,"subtitle commit");
  received=0;byte_out(8'ha5);byte_out(8'h5a);byte_out(8'h01);byte_out(0);
  byte_out(0);byte_out(0);wait_reply(1);
  if(replies[0]!==8'h15 || !parser.custom_active)$fatal(1,"bad subtitle replaced text");
  received=0;byte_out(8'ha5);byte_out(8'h5a);byte_out(8'h01);byte_out(0);
  byte_out(8'he1);byte_out(8'hf0);h=0;v=0;tick(1);h=1;v=1;wait_reply(1);
  if(replies[0]!==8'h06 || parser.custom_active)$fatal(1,"clear subtitle");
  $display("PASS: real UART control/status CRC, five images, wrap, carousel, controls, audio priority, invalid/partial rejection, polling/manual timeout and atomic subtitle preservation");
  $finish;
 end
 initial begin #10000000;$fatal(1,"admin control test hung");end
endmodule
