`timescale 1ns/1ps
module tb_batch_buzzer;
    reg clk=0,rst_n=0,alarm=0;
    wire buzzer_n,default_buzzer_n;
    integer age=-1,default_age=-1,checks=0,low_samples=0;
    localparam integer TEST_HZ=100000, HALF=TEST_HZ/4000;
    localparam integer ON=TEST_HZ/5, PERIOD=TEST_HZ;
    always #5 clk=~clk;
    // Scale only the reference clock; keep production tone and burst settings.
    batch_error_buzzer #(.CLK_HZ(TEST_HZ)) dut(
        .clk(clk),.rst_n(rst_n),.alarm(alarm),.buzzer_n(buzzer_n));
    batch_error_buzzer production_defaults(
        .clk(clk),.rst_n(rst_n),.alarm(alarm),.buzzer_n(default_buzzer_n));
    task step(input logic enable,input logic reset_released);
        logic expected,default_expected;
        begin
            alarm=enable;rst_n=reset_released;
            @(posedge clk);#1;
            if(!reset_released || !enable) begin
                age=-1;default_age=-1;expected=1;default_expected=1;
            end else begin
                age=(age+1)%PERIOD;
                default_age=(default_age+1)%50000000;
                expected=(age>=ON || (age/HALF)%2!=0);
                default_expected=(default_age>=10000000 || (default_age/12500)%2!=0);
            end
            checks=checks+1;
            if(buzzer_n!==expected || default_buzzer_n!==default_expected)
                $fatal(1,"buzzer waveform age=%0d default_age=%0d actual=%b/%b expected=%b/%b",
                    age,default_age,buzzer_n,default_buzzer_n,expected,default_expected);
            if(!buzzer_n)low_samples=low_samples+1;
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(20)step(0,0);
        repeat(20)step(0,1);
        repeat(PERIOD*4+123)step(1,1);
        step(0,1); // Removal during an audible burst.
        repeat(9)step(1,1);step(0,1); // New NG starts a fresh burst.
        repeat(ON+100)step(1,1);step(0,1); // Removal during the silent gap.
        repeat(77)step(1,1);step(1,0); // Reset with an active fault.
        repeat(30)step(1,1);step(0,1);
        repeat(5)step(0,0);
        repeat(3)begin
            repeat(PERIOD+HALF+1)step(1,1);
            repeat(17)step(0,1);
        end
        if(low_samples<40000)$fatal(1,"No meaningful audible waveform coverage");
        $display("ALL PASS batch buzzer: %0d waveform samples, 2kHz 200ms-on/800ms-off, repeated NG, removal in burst/gap, immediate retrigger, reset, production-default tone divider",checks);
        $finish;
    end
    initial begin #10000000;$fatal(1,"buzzer watchdog");end
endmodule
