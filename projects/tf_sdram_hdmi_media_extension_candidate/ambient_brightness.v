// Seven light bands with 32-code hysteresis and low-pass filtering.
// Higher ADC readings preserve the previously verified brighter-picture direction.
module ambient_brightness (
 input wire clk,rst_n,
 input wire [11:0] sample,
 input wire sample_valid,
 output reg [3:0] brightness,
 output reg valid
);
 reg [11:0] filtered;
 reg [4:0] valid_samples;
 reg [2:0] band;
 reg [11:0] lower,upper;
 always @* begin
  case(band)
   0: begin lower=0; upper=384; end
   1: begin lower=384; upper=1024; end
   2: begin lower=1024; upper=1536; end
   3: begin lower=1536; upper=2048; end
   4: begin lower=2048; upper=3072; end
   5: begin lower=3072; upper=3712; end
   default: begin lower=3712; upper=4095; end
  endcase
  case(band)
   0: brightness=0;
   1: brightness=1;
   2: brightness=4;
   3: brightness=5;
   4: brightness=6;
   5: brightness=8;
   default: brightness=9;
  endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin filtered<=1792;valid_samples<=0;valid<=0;band<=3;end
  else if(sample_valid) begin
   // Rounded update avoids sticking 15 counts away from the target.
   if(sample>=filtered)filtered<=filtered+(({1'b0,sample}-{1'b0,filtered}+13'd8)>>4);
   else filtered<=filtered-(({1'b0,filtered}-{1'b0,sample}+13'd8)>>4);
   if(valid_samples!=16)valid_samples<=valid_samples+1'b1;
   if(valid_samples>=15)valid<=1;
   if(band!=6 && {1'b0,filtered}>={1'b0,upper}+13'd32)band<=band+1'b1;
   else if(band!=0 && {1'b0,filtered}+13'd32<{1'b0,lower})band<=band-1'b1;
  end
 end
endmodule
