// 115200 baud, 8N1, 3.3V UART. Both ports run in the 27MHz pixel domain.
module subtitle_uart #(
 parameter integer CLOCK_HZ=27000000,
 parameter integer BAUD=115200
)(
 input wire clk,rst_n,rx,
 output reg [7:0] rx_data,
 output reg rx_valid,rx_error,
 input wire [7:0] tx_data,
 input wire tx_valid,
 output wire tx,
 output reg tx_busy
);
 localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
 localparam integer CW=$clog2(DIV+1);
 reg rx_meta,rx_sync;
 reg [1:0] state;
 reg [CW-1:0] count,tx_count;
 reg [2:0] bit_index;
 reg [7:0] shift;
 reg [9:0] tx_shift;
 reg [3:0] tx_bits;
 assign tx=tx_busy ? tx_shift[0] : 1'b1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin rx_meta<=1;rx_sync<=1;end
  else begin rx_meta<=rx;rx_sync<=rx_meta;end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin state<=0;count<=0;bit_index<=0;shift<=0;rx_data<=0;rx_valid<=0;rx_error<=0;end
  else begin
   rx_valid<=0;rx_error<=0;
   case(state)
    0: if(!rx_sync) begin count<=DIV/2-1;state<=1;end
    1: if(count!=0)count<=count-1'b1;
       else if(!rx_sync)begin count<=DIV-1;bit_index<=0;state<=2;end
       else state<=0;
    2: if(count!=0)count<=count-1'b1;
       else begin
        shift[bit_index]<=rx_sync;count<=DIV-1;
        if(bit_index==7)state<=3;else bit_index<=bit_index+1'b1;
       end
    3: if(count!=0)count<=count-1'b1;
       else begin
        state<=0;
        if(rx_sync)begin rx_data<=shift;rx_valid<=1;end
        else rx_error<=1;
       end
   endcase
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin tx_busy<=0;tx_shift<=10'h3ff;tx_count<=0;tx_bits<=0;end
  else if(!tx_busy)begin
   if(tx_valid)begin tx_shift<={1'b1,tx_data,1'b0};tx_busy<=1;tx_count<=DIV-1;tx_bits<=0;end
  end else if(tx_count!=0)tx_count<=tx_count-1'b1;
  else begin
   tx_count<=DIV-1;tx_shift<={1'b1,tx_shift[9:1]};
   if(tx_bits==9)tx_busy<=0;else tx_bits<=tx_bits+1'b1;
  end
 end
endmodule
