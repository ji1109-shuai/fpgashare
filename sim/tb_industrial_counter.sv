`timescale 1ns/1ps
module industrial_counter_check;
    reg clk=0,rst_n=0,toggle=0,clear=0,ack=0,fault=0,inc=0,dec=0;
    reg [2:0] selected=1;
    reg [223:0] targets=0;
    wire [47:0] counts,totals,quotas;
    wire done,ng,wait_clear;
    wire [3:0] ng_mask;
    reg count_active=1;
    integer checks=0;
    always #7 clk=~clk;
    conveyor_batch_counter #(.DEFAULT_TARGET_BCD(12'h010),.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(12)) dut(
        .clk(clk),.rst_n(rst_n),.I_targets_toggle(toggle),.I_targets(targets),
        .I_set_enable(1'b0),.I_key_inc_n(1'b1),.I_key_dec_n(1'b1),.I_key_clear_n(1'b1),
        .I_menu_type(selected),.I_menu_inc(inc),.I_menu_dec(dec),.I_menu_clear(clear),
        .I_menu_ack(ack),.I_detection_fault(fault),.I_count_active(count_active),.O_counts_bcd(counts),.O_total_counts_bcd(totals),
        .O_targets_bcd(quotas),.O_done(done),.O_overrun(ng),.O_overrun_mask(ng_mask),.O_wait_clear(wait_clear));
    function [55:0] object(input integer id,shape,cx,confirmed);
        object={1'(confirmed),3'(shape),3'd4,1'b1,4'(id),11'(cx-20),11'(cx+20),11'd100,11'd140};
    endfunction
    task ticks(input integer n);repeat(n) @(negedge clk);endtask
    task reset_case;
        begin rst_n=0;targets=0;toggle=0;clear=0;ack=0;fault=0;inc=0;dec=0;selected=1;count_active=1;ticks(5);rst_n=1;ticks(8);end
    endtask
    task publish(input [223:0] value);
        begin targets=value;toggle=~toggle;ticks(16);end
    endtask
    task expect_count(input [47:0] value);
        begin checks=checks+1;if(counts!==value) $fatal(1,"counter check%0d counts=%h expected=%h",checks,counts,value);end
    endtask
    task minus;
        begin dec=1;ticks(1);dec=0;ticks(2);end
    endtask
    initial begin
        reset_case;
        publish({168'd0,object(4,1,580,0)});expect_count(0);
        publish({168'd0,object(4,1,640,1)});expect_count(0);
        publish({168'd0,object(4,1,680,1)});expect_count(48'h1);
        publish({object(4,1,680,1),168'd0});expect_count(48'h1);
        publish(0);publish(0);publish({168'd0,object(4,1,680,1)});expect_count(48'h1);
        publish({168'd0,object(4,1,600,1)});publish({168'd0,object(4,1,680,1)});expect_count(48'h1);
        $display("PASS ID order, hysteresis, short dropout and reverse/forward never duplicate");

        reset_case;
        publish({112'd0,object(5,1,530,1),object(4,1,600,1)});
        publish({112'd0,object(4,1,640,1),object(5,1,570,1)});expect_count(0);
        publish({112'd0,object(5,1,640,1),object(4,1,680,1)});expect_count(48'h1);
        publish({112'd0,object(4,1,720,1),object(5,1,680,1)});expect_count(48'h2);
        $display("PASS old/new same-class line replacement counts both identities");

        reset_case;
        for(integer n=0;n<9;n=n+1) minus();
        if(quotas[11:0]!=1) $fatal(1,"quota editing failed");
        publish({168'd0,object(4,1,580,1)});publish({168'd0,object(4,1,680,1)});
        if(!done || ng) $fatal(1,"quota completion failed");
        publish({112'd0,object(5,1,580,1),object(4,1,700,1)});
        publish({112'd0,object(5,1,680,1),object(4,1,720,1)});
        if(done || !ng || totals[11:0]!=2 || counts[11:0]!=2) $fatal(1,"coasting arrival after DONE was hidden");
        ack=1;ticks(1);ack=0;ticks(4);if(!ng) $fatal(1,"ACK accepted before offending view cleared");
        publish(0);publish(0);expect_count(48'h2);publish(0);expect_count(48'h1);
        if(ng) $fatal(1,"removed excess part failed automatic recovery");
        ticks(4);
        if(ng || !done || counts[11:0]!=1 || totals[11:0]!=2) $fatal(1,"explicit reject ACK/audit failed");
        $display("PASS done/coast audit, qualified automatic removal recovery, totals retained");

        reset_case;publish({168'd0,object(4,1,600,1)});
        clear=1;ticks(1);clear=0;ticks(4);
        publish({168'd0,object(4,1,680,1)});expect_count(0);
        if(!wait_clear || ng) $fatal(1,"clear-under-object protection failed");
        publish(0);if(wait_clear) $fatal(1,"empty view failed to rearm new batch");
        publish({168'd0,object(8,1,580,1)});publish({168'd0,object(8,1,680,1)});expect_count(48'h1);
        $display("PASS new-batch clear cannot recount existing in-view objects");

        reset_case;count_active=0;publish({168'd0,object(4,1,700,1)});
        publish({168'd0,object(4,1,700,1)});if(ng || counts!=0) $fatal(1,"stationary downstream startup produced NG");
        count_active=1;publish({168'd0,object(4,1,700,1)});if(ng || counts!=0) $fatal(1,"known startup object was recounted");
        reset_case;publish({168'd0,object(4,1,700,1)});
        if(!ng || counts!=0) $fatal(1,"downstream-only appearance was guessed as a count");
        reset_case;fault=1;publish(0);if(!ng) $fatal(1,"detector overflow failed to stop batch");
        reset_case;publish({112'd0,object(4,1,580,1),object(4,2,580,1)});
        if(!ng) $fatal(1,"duplicate slot identity not detected");

        reset_case;
        selected=2;inc=1;ticks(1);inc=0;ticks(2);
        selected=3;inc=1;ticks(1);inc=0;ticks(2);
        selected=4;inc=1;ticks(1);inc=0;ticks(2);
        publish({object(7,4,580,1),object(6,3,580,1),object(5,2,580,1),object(4,1,580,1)});
        publish({object(4,1,680,1),object(7,4,680,1),object(6,3,680,1),object(5,2,680,1)});
        expect_count(48'h001001001001);
        if(totals!==counts || ng) $fatal(1,"simultaneous four-class accounting failed");
        $display("ALL PASS industrial counter: %0d count assertions, four classes, identity continuity, directional band, audit and fault lifecycle",checks);$finish;
    end
    initial begin #2000000;$fatal(1,"industrial counter watchdog");end
endmodule
module tb_industrial_counter;industrial_counter_check test();endmodule
