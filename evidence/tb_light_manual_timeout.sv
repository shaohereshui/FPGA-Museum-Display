`timescale 1ns/1ps
module tb_light_manual_timeout;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,prev_n=1,next_n=1,menu_n=1,confirm_n=1;
    wire [3:0] brightness;
    wire manual,adjust_mode,ui_display;
    media_control #(
        .DEBOUNCE_CYCLES(3), .HOLD_DELAY_CYCLES(100), .REPEAT_CYCLES(20),
        .AUTO_LIGHT_CYCLES(1000), .MANUAL_IDLE_CYCLES(2000),
        .IDLE_TIMEOUT_CYCLES(100000)
    ) dut (
        .host_valid(1'b0),.host_command(8'd0),.host_value(8'd0),
        .clk(clk),.rst_n(rst_n),.key_prev_n(prev_n),.key_next_n(next_n),
        .key_mode_n(1'b1),.volume_down_n(1'b1),.volume_up_n(1'b1),
        .key_menu_n(menu_n),.key_confirm_n(confirm_n),.key_back_n(1'b1),
        .key_zoom_in_n(1'b1),.key_zoom_out_n(1'b1),.key_visual_n(1'b1),
        .ambient_level(4'd0),.ambient_valid(1'b1),.external_activity(1'b0),
        .board_zoom_off(1'b0),.sw_param(1'b0),.sw_audio(1'b0),.sw_volume(1'b0),
        .brightness(brightness),.brightness_manual(manual),
        .adjust_mode(adjust_mode),.ui_display(ui_display)
    );
    task tick(input integer n); begin repeat(n) @(negedge clk); end endtask
    task tap(input integer key);
        begin
            case(key) 0:menu_n=0;1:next_n=0;2:confirm_n=0;3:prev_n=0;endcase
            tick(20);
            case(key) 0:menu_n=1;1:next_n=1;2:confirm_n=1;3:prev_n=1;endcase
            tick(20);
        end
    endtask
    initial begin
        tick(3);rst_n=1;tick(10);
        tap(0);tap(1);tap(2);tap(1);tap(2);
        if(!ui_display || !adjust_mode)$fatal(1,"brightness editor not entered");
        tap(3);tap(1);
        if(brightness!==5 || !manual)$fatal(1,"manual brightness 5 not latched");
        tick(1950);
        if(brightness!==5 || !manual)$fatal(1,"manual brightness expired early");
        tick(80);
        if(brightness!==0 || manual)$fatal(1,"automatic zero not restored after manual idle timeout");
        $display("PASS: manual brightness 5 remains until manual idle deadline; ambient zero restores afterward");
        $finish;
    end
    initial begin #100000; $fatal(1,"manual timeout test hung"); end
endmodule
