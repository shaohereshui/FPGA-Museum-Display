// CTA 720x480p59.94 timing: VIC 3 selects its 16:9 display aspect ratio.
module hdmi_timing_media (
    input wire pixel_clk, rst_n,
    output wire hsync, vsync, de,
    output wire [23:0] rgb,
    output reg [9:0] h_count, v_count
);
    assign hsync = !(h_count>=736 && h_count<798);
    assign vsync = !(v_count>=490 && v_count<492);
    assign de = h_count<720 && v_count<480;
    assign rgb = 24'd0;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin h_count<=0; v_count<=0; end
        else if (h_count==857) begin
            h_count<=0;
            v_count<=v_count==524 ? 10'd0 : v_count+1'b1;
        end else h_count<=h_count+1'b1;
    end
endmodule
