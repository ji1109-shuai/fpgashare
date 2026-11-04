`timescale 1ns/1ps
module tb_motor_resume;
    reg clk=0,rst_n=0,menu_switch=1;
    reg [3:0] keys=15;
    reg [223:0] targets=0;
    reg publication=0,detector_fault=0;
    wire opened,ack,clear,inc,dec,done,ng,wait_clear,pwm,in2;
    wire [2:0] speed,motor_level,selected;
    wire [3:0] index,ng_mask;
    wire [47:0] counts,totals,quotas;
    wire stop_motor=done|ng|wait_clear;
    wire buzzer_n;
    integer buzzer_low_cycles=0;
    integer checks=0,on_cycles,n;
    always #5 clk=~clk;
    // Match the production chain: NG gates PWM but never erases menu speed.
    screen_menu_control #(.DEBOUNCE_CYCLES(2)) menu(
        .clk(clk),.rst_n(rst_n),.I_menu_switch(menu_switch),.I_button_n(keys),
        .I_batch_done(done|wait_clear),.O_menu_open(opened),.O_menu_index(index),
        .O_motor_level(speed),.O_fault_ack(ack),.O_count_clear(clear),
        .O_target_type(selected),.O_target_inc(inc),.O_target_dec(dec));
    conveyor_batch_counter #(.DEFAULT_TARGET_BCD(12'h010),.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(10)) counter(
        .clk(clk),.rst_n(rst_n),.I_targets_toggle(publication),.I_targets(targets),
        .I_set_enable(1'b0),.I_key_inc_n(1'b1),.I_key_dec_n(1'b1),.I_key_clear_n(1'b1),
        .I_menu_type(selected),.I_menu_inc(inc),.I_menu_dec(dec),.I_menu_clear(clear),
        .I_menu_ack(ack),.I_detection_fault(detector_fault),.I_count_active(speed!=0),
        .O_counts_bcd(counts),.O_total_counts_bcd(totals),.O_targets_bcd(quotas),
        .O_done(done),.O_overrun(ng),.O_overrun_mask(ng_mask),.O_wait_clear(wait_clear));
    l298n_motor_control #(.CLK_HZ(1000000),.PWM_HZ(10000),.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(20)) motor(
        .clk(clk),.rst_n(rst_n),.key_n(1'b1),.force_stop(stop_motor),
        .I_menu_override(1'b1),.I_menu_level(speed),.in1(pwm),.in2(in2),.level(motor_level));
    // Production alarm source is NG only, independent of selected speed.
    batch_error_buzzer #(.CLK_HZ(100000),.ON_MS(2),.PERIOD_MS(10)) alarm_output(
        .clk(clk),.rst_n(rst_n),.alarm(ng),.buzzer_n(buzzer_n));
    always @(negedge clk) if(!buzzer_n)buzzer_low_cycles=buzzer_low_cycles+1;
    function [55:0] object(input integer id,shape,cx,confirmed);
        object={1'(confirmed),3'(shape),3'd4,1'b1,4'(id),11'(cx-20),11'(cx+20),11'd100,11'd140};
    endfunction
    task ticks(input integer cycles);repeat(cycles) @(negedge clk);endtask
    task check(input logic ok,input string label);
        begin
            checks=checks+1;
            if(!ok) $fatal(1,"motor/recovery %s speed=%0d motor=%0d ng=%b done=%b counts=%h totals=%h",label,speed,motor_level,ng,done,counts,totals);
            if(!ng && buzzer_n!==1'b1)$fatal(1,"Buzzer must be silent after NG clears: %s",label);
        end
    endtask
    task press(input integer k);begin keys[k]=0;ticks(10);keys[k]=1;ticks(10);end endtask
    task select_item(input integer dest);
        begin n=0;while(index!=dest && n<16)begin press(1);n=n+1;end check(index==dest,"menu cursor");end
    endtask
    task publish(input [223:0] value);begin targets=value;publication=~publication;ticks(16);end endtask
    task reset_case;
        begin rst_n=0;keys=15;publication=0;targets=0;detector_fault=0;menu_switch=1;ticks(6);rst_n=1;ticks(20);select_item(1);end
    endtask
    task duty(input integer expected);
        begin
            ticks(205);on_cycles=0;
            repeat(100)begin @(negedge clk);if(pwm)on_cycles=on_cycles+1;if(in2!==0)$fatal(1,"IN2 must remain LOW");end
            check(on_cycles==expected,$sformatf("actual PWM high clocks %0d expected %0d",on_cycles,expected));
        end
    endtask
    initial begin
        reset_case;check(speed==0,"power on STOP");duty(0);
        press(3);check(speed==1,"LOW selection");duty(65);
        press(3);check(speed==2,"MID selection");duty(80);
        press(3);check(speed==3,"HIGH selection");duty(100);
        press(3);check(speed==0,"three speeds then STOP");duty(0);
        press(2);check(speed==3,"reverse STOP to HIGH");duty(100);
        // Wrong class stopped upstream, including when not at the count line.
        publish({168'd0,object(4,2,580,1)});
        check(ng && ng_mask==2 && speed==3,"wrong washer pauses but remembers HIGH");duty(0);
        check(buzzer_low_cycles>0,"wrong class drives buzzer waveform while motor is stopped");
        check(counts==0 && totals==0,"upstream wrong part never counted");
        publish(0);check(ng,"one missing publication cannot resume");
        publish({168'd0,object(4,2,580,0)});check(ng,"unconfirmed but observed wrong part resets clearance");
        publish(0);publish(0);check(ng,"two clean publications cannot resume");
        ticks(500);check(ng,"elapsed clocks without new frames cannot resume");
        publish({168'd0,object(5,1,580,1)});
        check(!ng && speed==3 && !done,"third fresh clear publication resumes despite valid screw in view");duty(100);
        publish({168'd0,object(5,1,680,1)});check(counts[11:0]==1,"valid part counted after resume");
        // Repeat removal at every chosen speed and verify real PWM afterward.
        reset_case;
        for(integer level=1;level<=3;level=level+1)begin
            press(3);publish({168'd0,object(4,3,580,1)});
            check(ng && speed==level,"reject preserves selected LOW/MID/HIGH");duty(0);
            publish(0);publish(0);publish(0);check(!ng && speed==level,"qualified removal restores selected speed");
            duty(level==1 ? 65:level==2 ? 80:100);
        end
        // An explicit STOP made while paused cancels any automatic restart.
        publish({168'd0,object(4,2,580,1)});check(ng,"pause before manual STOP");
        press(3);check(speed==0,"operator STOP while paused");
        publish(0);publish(0);publish(0);check(!ng && speed==0,"removed part cannot override manual STOP");duty(0);
        // Detector faults and ambiguous downstream appearance still need ACK.
        reset_case;press(3);detector_fault=1;publish(0);check(ng,"detector fault pauses");
        publish(0);publish(0);publish(0);check(ng,"ongoing detector fault cannot recover");
        detector_fault=0;publish(0);publish(0);publish(0);check(ng,"ambiguous detector fault stays latched");
        select_item(14);press(3);check(!ng && speed==1,"qualified ACK clears hard fault without erasing speed");duty(65);
        reset_case;press(3);publish({168'd0,object(4,1,700,1)});
        publish(0);publish(0);publish(0);check(ng,"unknown downstream object never silently accepted");
        select_item(14);press(3);check(!ng && counts==0,"downstream audit ACK invents no count");
        // Batch completion stops permanently; subsequent reject removal cannot restart.
        reset_case;select_item(6);repeat(9)press(2);check(quotas[11:0]==1,"one screw quota");
        select_item(1);press(3);publish({168'd0,object(4,1,580,1)});publish({168'd0,object(4,1,680,1)});
        ticks(5);check(done && speed==0,"DONE clears speed");duty(0);
        publish({112'd0,object(5,1,580,1),object(4,1,720,1)});
        publish({112'd0,object(5,1,680,1),object(4,1,740,1)});
        check(ng && counts[11:0]==2 && totals[11:0]==2,"coasting excess remains auditable");
        publish(0);publish(0);check(ng,"excess requires three fresh clear frames");publish(0);ticks(5);
        check(!ng && done && speed==0 && counts[11:0]==1 && totals[11:0]==2,"removed excess trims accepted count only and preserves DONE stop");duty(0);
        $display("ALL PASS motor resume: %0d assertions; measured STOP/65/80/100 PWM, all-speed reject removal, three fresh publications, dropout/reappearance, manual STOP, detector/downstream ACK, DONE and excess audit; NG buzzer, silence after recovery/ACK, silent STOP/DONE/clear-view",checks);$finish;
    end
    initial begin #2000000;$fatal(1,"motor resume watchdog");end
endmodule
