`timescale 1ns/1ps
module tb_industrial_menu;
    reg clk=0,rst_n=0,sw=0,stop=0;
    reg [3:0] keys=15;
    wire opened,auto_ae,armed,update_target,ack,clear;
    wire [3:0] index,noise;
    wire [2:0] view,motor;
    wire [4:0] target;
    wire [1:0] detail;
    integer checks=0,ack_count=0,clear_count=0;
    always #5 clk=~clk;
    always @(posedge clk) if(rst_n) begin
        if(ack) ack_count=ack_count+1;
        if(clear) clear_count=clear_count+1;
    end
    screen_menu_control #(.DEBOUNCE_CYCLES(3)) dut(
        .clk(clk),.rst_n(rst_n),.I_menu_switch(sw),.I_button_n(keys),.I_batch_done(stop),
        .O_menu_open(opened),.O_menu_index(index),.O_preview_mode(view),.O_motor_level(motor),
        .O_ae_auto(auto_ae),.O_camera_keys_armed(armed),.O_ae_target_level(target),
        .O_ae_target_upd(update_target),.O_enhance_strength(detail),.O_enhance_noise(noise),
        .O_fault_ack(ack),.O_count_clear(clear));
    task ticks(input integer n);repeat(n) @(negedge clk);endtask
    task press(input integer k);
        begin keys[k]=0;ticks(12);keys[k]=1;ticks(12);end
    endtask
    task select_item(input integer n);
        integer limit;
        begin
            limit=0;while(index!=n && limit<15) begin press(1);limit=limit+1;end
            if(index!=n) $fatal(1,"menu navigation failed target=%0d got=%0d",n,index);
        end
    endtask
    task check(input logic valid,input string label);
        begin checks=checks+1;if(!valid) $fatal(1,"menu %s",label);end
    endtask
    initial begin
        ticks(5);rst_n=1;ticks(15);
        check(auto_ae && armed && view==7 && motor==0 && target==19 && detail==2 && noise==4,"industrial power-on defaults");
        sw=1;ticks(10);check(opened && index==0,"open at VIEW");
        press(0);check(index==14,"wrap up to ACK");press(1);check(index==0,"wrap down to VIEW");
        select_item(11);press(2);check(target==18 && update_target,"lower AE target to144");
        press(3);check(target==19 && !update_target,"raise AE target to152");
        repeat(20) press(3);check(target==24,"AE target upper clamp192");
        repeat(20) press(2);check(target==8,"AE target lower clamp64");
        repeat(11) press(3);check(target==19 && auto_ae,"target edits preserve AUTO");
        select_item(12);repeat(5) press(3);check(detail==3,"detail upper clamp");
        repeat(5) press(2);check(detail==0,"detail bypass clamp");repeat(2) press(3);
        select_item(13);repeat(20) press(3);check(noise==15,"noise upper clamp");
        repeat(20) press(2);check(noise==0,"noise lower clamp");repeat(4) press(3);
        select_item(14);keys[3]=0;ticks(80);keys[3]=1;ticks(12);
        check(ack_count==1 && clear_count==0,"held ACK emits one ACK and no RESET");
        select_item(1);press(3);check(motor==1,"explicit motor start");
        press(3);check(motor==2,"MID 80 level");press(3);check(motor==3,"HIGH 100 level");
        press(3);check(motor==0,"HIGH wraps to STOP");press(2);check(motor==3,"STOP reverse to HIGH");
        press(2);check(motor==2,"HIGH reverse to MID");press(2);check(motor==1,"MID reverse to LOW");
        stop=1;ticks(5);check(motor==0,"DONE clears remembered speed");
        stop=0;ticks(5);check(motor==0,"DONE release cannot restart motor");
        select_item(10);press(3);check(clear_count==1 && motor==0,"new batch reset pulse with belt stopped");
        select_item(4);press(3);check(!auto_ae,"EXP edit selects MAN");
        select_item(11);press(2);check(!auto_ae,"target edit preserves explicit MAN");
        select_item(3);press(3);check(auto_ae,"explicit AUTO restart");
        sw=0;ticks(10);check(!opened && target==18 && detail==2 && noise==4,"settings persist on menu close");
        $display("ALL PASS industrial menu: %0d assertions, 15 entries, AE bounds, detail/noise, ACK, safe stop, reset and MAN/AUTO",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"menu watchdog");end
endmodule
