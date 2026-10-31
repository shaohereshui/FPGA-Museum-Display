    function [23:0] gradient;
        input [4:0] band;
        input [6:0] distance;
        reg [23:0] base_color;
        reg [7:0] factor;
        reg [15:0] red_product,green_product,blue_product;
        begin
            case(band)
                5'd0:base_color=24'h59ffe1;
                5'd1:base_color=24'h59ffef;
                5'd2:base_color=24'h59fffd;
                5'd3:base_color=24'h59f3ff;
                5'd4:base_color=24'h59e6ff;
                5'd5:base_color=24'h59d8ff;
                5'd6:base_color=24'h59caff;
                5'd7:base_color=24'h59bcff;
                5'd8:base_color=24'h59aeff;
                5'd9:base_color=24'h59a1ff;
                5'd10:base_color=24'h5993ff;
                5'd11:base_color=24'h5985ff;
                5'd12:base_color=24'h5977ff;
                5'd13:base_color=24'h596aff;
                5'd14:base_color=24'h595cff;
                5'd15:base_color=24'h6559ff;
                5'd16:base_color=24'h7259ff;
                5'd17:base_color=24'h8059ff;
                5'd18:base_color=24'h8e59ff;
                5'd19:base_color=24'h9c59ff;
                5'd20:base_color=24'haa59ff;
                5'd21:base_color=24'hb759ff;
                5'd22:base_color=24'hc559ff;
                5'd23:base_color=24'hd359ff;
                5'd24:base_color=24'he159ff;
                5'd25:base_color=24'hef59ff;
                5'd26:base_color=24'hfc59ff;
                5'd27:base_color=24'hff59f4;
                5'd28:base_color=24'hff59e6;
                5'd29:base_color=24'hff59d8;
                5'd30:base_color=24'hff59ca;
                5'd31:base_color=24'hff59bd;
                default:base_color=24'h60cfff;
            endcase
            factor=distance>=64 ? 8'd128 : 8'd64+distance;
            red_product=base_color[23:16]*factor;
            green_product=base_color[15:8]*factor;
            blue_product=base_color[7:0]*factor;
            gradient={red_product[14:7],green_product[14:7],blue_product[14:7]};
        end
    endfunction
