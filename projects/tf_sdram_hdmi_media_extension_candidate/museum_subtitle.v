// Atomic, CRC-checked 16x16 glyph upload; PC renders arbitrary BMP Unicode.
// Packet: A5 5A 01 LEN [LEN*32 glyph bytes] CRC_H CRC_L.
// CRC16-CCITT-FALSE covers LEN and glyph bytes. LEN 0 restores welcome text.
// ACK 06 is emitted only at frame-boundary activation; NAK 15 on bad packets.
// Missing/partial/invalid packets never replace the currently displayed text.
// Control: A5 5A CMD VALUE CRC_H CRC_L, CRC covers CMD and VALUE.
// Reply: 06, twelve status bytes, CRC_H CRC_L over those status bytes.
module museum_subtitle #(
 parameter integer RX_TIMEOUT=2700000
)(
 input wire clk,rst_n,
 input wire [7:0] rx_data,
 input wire rx_valid,rx_error,
 output reg [7:0] tx_data,
 output reg tx_valid,
 input wire show,
 input wire de,
 input wire [9:0] h_count,v_count,
 input wire [23:0] rgb_in,
 output wire [23:0] rgb_out,
 input wire tx_busy,
 input wire [95:0] control_status,
 output reg control_valid,
 output wire [7:0] control_command,control_value
);
 localparam integer X=24,Y=418,WIDTH=396;
 reg [7:0] glyph_mem[0:4095]; // synthesis ram_style=bram
 reg [7:0] glyph_q;
 reg active_bank,custom_active,pending;
 reg [6:0] text_length;
 reg [7:0] packet_length;
 reg [3:0] state;
 reg [10:0] payload_index;
 reg [15:0] crc;
 reg [3:0] crc_steps;
 reg [7:0] crc_high;
 reg [$clog2(RX_TIMEOUT+1)-1:0] timeout_count;
 reg [10:0] scroll;
 reg slow_frame;
 reg [7:0] command;
 reg [2:0] reply_delay;
 reg reply_active;
 reg [3:0] reply_index;
 reg [95:0] reply_shift;
 assign control_command=command;
 assign control_value=packet_length;
 wire frame_start=(h_count==0 && v_count==0);
 wire [10:0] text_width={text_length,4'b0000};
 wire [10:0] custom_period=text_width+11'd64;
 wire [10:0] period=(custom_active && custom_period>WIDTH) ? custom_period : 11'd396;
 wire [11:0] raw_x={2'b0,h_count}-12'd24+{1'b0,scroll};
 wire [11:0] source_x=raw_x>={1'b0,period} ? raw_x-{1'b0,period} : raw_x;
 wire [9:0] relative_y=v_count-10'd418;
 wire band=show && de && h_count>=X && h_count<X+WIDTH && v_count>=Y && v_count<Y+16;
 wire in_text=band && source_x < (custom_active ? {1'b0,text_width} : 12'd144);
 wire [11:0] read_address={active_bank,source_x[9:4],relative_y[3:0],source_x[3]};
 wire [7:0] default_address={source_x[7:4],relative_y[3:0]};
 `include "welcome_font.vh"
 wire [15:0] default_row=welcome_row(default_address);
 reg [23:0] rgb_pipe;
 reg text_pipe,custom_pipe,default_pixel;
 reg [2:0] column_pipe;
 // Synchronous read matches the single RGB register formerly in museum core.
 always @(posedge clk) begin
  glyph_q<=glyph_mem[read_address];
  if(rx_valid && !pending && state==4)
   glyph_mem[{!active_bank,payload_index}]<=rx_data;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin rgb_pipe<=0;text_pipe<=0;custom_pipe<=0;default_pixel<=0;column_pipe<=0;end
  else begin
   rgb_pipe<=rgb_in;text_pipe<=in_text;custom_pipe<=custom_active;
   default_pixel<=default_row[15-source_x[3:0]];column_pipe<=source_x[2:0];
  end
 end
 assign rgb_out=text_pipe && (custom_pipe ? glyph_q[7-column_pipe] : default_pixel) ? 24'h000000 : rgb_pipe;
 // One CRC bit per clock fits within the UART inter-byte interval.
 wire [15:0] receive_crc=((state==2 || state==3) ? 16'hffff : crc)^{rx_data,8'd0};
 function control_value_ok;
  input [7:0] cmd,value;
  begin
   case(cmd)
    8'h02,8'h25,8'h26: control_value_ok=value==0;
    8'h20: control_value_ok=value<5;
    8'h21: control_value_ok=value<=100;
    8'h22: control_value_ok=value<=9 || value==8'hff;
    8'h23: control_value_ok=value<=9;
    8'h24,8'h28,8'h29: control_value_ok=value<=1;
    8'h27: control_value_ok=value<=2;
    default: control_value_ok=0;
   endcase
  end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   active_bank<=0;custom_active<=0;pending<=0;text_length<=9;packet_length<=0;
   state<=0;payload_index<=0;crc<=16'hffff;crc_steps<=0;crc_high<=0;timeout_count<=0;
   tx_data<=0;tx_valid<=0;scroll<=0;slow_frame<=0;
   command<=0;control_valid<=0;
   reply_delay<=0;reply_active<=0;reply_index<=0;reply_shift<=0;
  end else begin
   tx_valid<=0;
   control_valid<=0;
   if(crc_steps!=0)begin
    crc<=crc[15] ? (crc<<1)^16'h1021 : crc<<1;
    crc_steps<=crc_steps-1'b1;
   end
   // Snapshot after the command pulse has reached the control registers.
   if(reply_delay!=0)begin
    reply_delay<=reply_delay-1'b1;
    if(reply_delay==1)begin
     reply_shift<=control_status;reply_active<=1;reply_index<=0;crc<=16'hffff;
    end
   end
   if(reply_active && !tx_busy && !tx_valid)begin
    tx_valid<=1;
    if(reply_index==0)tx_data<=8'h06;
    else if(reply_index<=12)begin
     tx_data<=reply_shift[95:88];reply_shift<={reply_shift[87:0],8'd0};
     crc<=crc^{reply_shift[95:88],8'd0};crc_steps<=8;
    end else if(reply_index==13)tx_data<=crc[15:8];
    else begin tx_data<=crc[7:0];reply_active<=0;end
    reply_index<=reply_index+1'b1;
   end
   if(frame_start)begin
    if(pending)begin
     active_bank<=!active_bank;custom_active<=packet_length!=0;
     text_length<=packet_length[6:0];pending<=0;scroll<=0;slow_frame<=0;
     tx_data<=8'h06;tx_valid<=1;
    end else begin
     slow_frame<=!slow_frame;
     if(slow_frame)scroll<=scroll==period-1'b1 ? 11'd0 : scroll+1'b1;
    end
   end
   if(!pending && !reply_active && reply_delay==0)begin
    if(rx_error || (state!=0 && timeout_count==RX_TIMEOUT-1))begin
     state<=0;timeout_count<=0;tx_data<=8'h15;tx_valid<=1;
    end else if(rx_valid)begin
     timeout_count<=0;
     case(state)
      0: if(rx_data==8'ha5)state<=1;
      1: if(rx_data==8'h5a)state<=2;else state<=rx_data==8'ha5 ? 1:0;
      2: if(rx_data==1)state<=3;
         else if(rx_data==8'h02 || (rx_data>=8'h20 && rx_data<=8'h29))begin
          command<=rx_data;crc<=receive_crc;crc_steps<=8;state<=7;
         end else begin state<=0;tx_data<=8'h15;tx_valid<=1;end
      3: if(rx_data<=64)begin
          packet_length<=rx_data;payload_index<=0;crc<=receive_crc;crc_steps<=8;
          state<=rx_data==0 ? 5:4;
         end else begin state<=0;tx_data<=8'h15;tx_valid<=1;end
      4: begin
          crc<=receive_crc;crc_steps<=8;
          if({1'b0,payload_index}+12'd1=={packet_length,5'b0})state<=5;
          else payload_index<=payload_index+1'b1;
         end
      5: begin crc_high<=rx_data;state<=6;end
      6: begin
          state<=0;
          if({crc_high,rx_data}==crc)pending<=1;
          else begin tx_data<=8'h15;tx_valid<=1;end
         end
      7: if(control_value_ok(command,rx_data))begin
          packet_length<=rx_data;crc<=receive_crc;crc_steps<=8;state<=8;
         end else begin state<=0;tx_data<=8'h15;tx_valid<=1;end
      8: begin crc_high<=rx_data;state<=9;end
      9: begin
          state<=0;
          if({crc_high,rx_data}==crc)begin
           control_valid<=command!=8'h02;reply_delay<=5;
          end else begin tx_data<=8'h15;tx_valid<=1;end
         end
      default:state<=0;
     endcase
    end else if(state!=0)timeout_count<=timeout_count+1'b1;
    else timeout_count<=0;
   end
  end
 end
endmodule
