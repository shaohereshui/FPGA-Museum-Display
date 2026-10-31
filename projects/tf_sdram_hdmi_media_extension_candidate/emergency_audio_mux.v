// 48kHz PCM source/mux; no SD-card audio file is needed for emergency alerts.
// Emergency overrides music play/pause; the existing volume stage still applies.
module emergency_audio_mux (
 input wire clk, rst_n, enable, sample_slot, music_valid,
 input wire [15:0] music_left, music_right,
 output wire [15:0] left_out, right_out
);
 reg [16:0] position;
 reg [5:0] phase;
 wire beep = position < 17'd9600 ||
             (position >= 17'd16800 && position < 17'd26400) ||
             (position >= 17'd33600 && position < 17'd43200);
 reg [15:0] tone;
 always @* begin
  case (phase)
   6'd0: tone = 16'h0000;
   6'd1: tone = 16'h01f4;
   6'd2: tone = 16'h03e8;
   6'd3: tone = 16'h05dc;
   6'd4: tone = 16'h07d0;
   6'd5: tone = 16'h09c4;
   6'd6: tone = 16'h0bb8;
   6'd7: tone = 16'h0dac;
   6'd8: tone = 16'h0fa0;
   6'd9: tone = 16'h1194;
   6'd10: tone = 16'h1388;
   6'd11: tone = 16'h157c;
   6'd12: tone = 16'h1770;
   6'd13: tone = 16'h157c;
   6'd14: tone = 16'h1388;
   6'd15: tone = 16'h1194;
   6'd16: tone = 16'h0fa0;
   6'd17: tone = 16'h0dac;
   6'd18: tone = 16'h0bb8;
   6'd19: tone = 16'h09c4;
   6'd20: tone = 16'h07d0;
   6'd21: tone = 16'h05dc;
   6'd22: tone = 16'h03e8;
   6'd23: tone = 16'h01f4;
   6'd24: tone = 16'h0000;
   6'd25: tone = 16'hfe0c;
   6'd26: tone = 16'hfc18;
   6'd27: tone = 16'hfa24;
   6'd28: tone = 16'hf830;
   6'd29: tone = 16'hf63c;
   6'd30: tone = 16'hf448;
   6'd31: tone = 16'hf254;
   6'd32: tone = 16'hf060;
   6'd33: tone = 16'hee6c;
   6'd34: tone = 16'hec78;
   6'd35: tone = 16'hea84;
   6'd36: tone = 16'he890;
   6'd37: tone = 16'hea84;
   6'd38: tone = 16'hec78;
   6'd39: tone = 16'hee6c;
   6'd40: tone = 16'hf060;
   6'd41: tone = 16'hf254;
   6'd42: tone = 16'hf448;
   6'd43: tone = 16'hf63c;
   6'd44: tone = 16'hf830;
   6'd45: tone = 16'hfa24;
   6'd46: tone = 16'hfc18;
   6'd47: tone = 16'hfe0c;
   default: tone = 16'd0;
  endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin position<=0; phase<=0; end
  else if (!enable) begin position<=0; phase<=0; end
  else if (sample_slot) begin
   position <= position == 17'd91199 ? 17'd0 : position + 1'b1;
   phase <= phase == 6'd47 ? 6'd0 : phase + 1'b1;
  end
 end
 wire [15:0] alarm_sample = beep ? tone : 16'd0;
 assign left_out = enable ? alarm_sample : music_valid ? music_left : 16'd0;
 assign right_out = enable ? alarm_sample : music_valid ? music_right : 16'd0;
endmodule
