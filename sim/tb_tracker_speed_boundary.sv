`timescale 1ns/1ps
// Characterize the current production association gate; this is a measured
// algorithm limit, not a conveyor-speed or real-image accuracy certification.
module tb_tracker_speed_boundary;
    reg clk=0,rst_n=0,batch=0,publish=0,start=0;
    reg [55:0] packet=0;
    wire done;
    wire [55:0] result;
    integer x,cycle;
    img_parts_multi_tracker dut(.I_clk(clk),.I_rst_n(rst_n),.I_batch(batch),
        .I_publish(publish),.I_start(start),.I_index(2'd0),.I_packet(packet),
        .I_epoch(8'd0),.O_done(done),.O_packet(result));
    always #5 clk=~clk;
    task ticks(input integer n);
        repeat(n) begin @(negedge clk);end
    endtask
    task observe(input integer left,input integer expected_visible);
        begin
            packet={1'b1,3'd2,3'd4,5'd0,11'(left),11'(left+80),11'd100,11'd180};
            batch=1;ticks(1);batch=0;ticks(1);start=1;ticks(1);start=0;
            cycle=0;while(!done && cycle<40) begin ticks(1);cycle=cycle+1;end
            if(!done || result[55]!==expected_visible[0])
                $fatal(1,"tracker gate left=%0d expected%0d result%h",left,expected_visible,result);
            publish=1;ticks(1);publish=0;ticks(1);
        end
    endtask
    initial begin
        ticks(3);rst_n=1;ticks(2);
        observe(100,0);observe(164,0);observe(228,1);observe(292,1);
        observe(357,0);observe(422,0);observe(487,0);
        observe(487,0);observe(487,1);
        $display("ALL PASS current tracker: 64px/batch retains history; 65px/batch loses 3-batch confirmation");
        $finish;
    end
    initial begin #100000;$fatal(1,"tracker watchdog");end
endmodule
