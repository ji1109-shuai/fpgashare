`timescale 1ns/1ps
module tb_industrial_tracker;
    reg clk=0,sys_clk=0,rst_n=0,batch=0,start=0,publish=0,toggle=0;
    reg [55:0] packet=0;
    reg [1:0] index=0;
    reg [15:0] stamp=0;
    reg [223:0] reported=0,build=0;
    wire done,capacity;
    wire [55:0] result;
    wire [47:0] counts,totals;
    wire ng;
    reg [3:0] saved_id,other_id;
    integer cycles,observations=0;
    always #5 clk=~clk;
    always #7 sys_clk=~sys_clk;
    img_parts_multi_tracker dut(.I_clk(clk),.I_rst_n(rst_n),.I_batch(batch),.I_start(start),
        .I_publish(publish),.I_index(index),.I_packet(packet),.I_epoch(8'd0),
        .O_done(done),.O_packet(result),.O_capacity_fault(capacity));
    conveyor_batch_counter #(.DEFAULT_TARGET_BCD(12'h020),.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(12)) counter(
        .clk(sys_clk),.rst_n(rst_n),.I_targets_toggle(toggle),.I_targets(reported),
        .I_set_enable(1'b0),.I_key_inc_n(1'b1),.I_key_dec_n(1'b1),.I_key_clear_n(1'b1),
        .I_menu_type(3'd1),.I_menu_inc(1'b0),.I_menu_dec(1'b0),.I_menu_clear(1'b0),
        .I_menu_ack(1'b0),.I_detection_fault(capacity),.I_count_active(1'b1),
        .O_counts_bcd(counts),.O_total_counts_bcd(totals),.O_overrun(ng));
    function [55:0] raw(input integer shape,left,top);
        raw={1'b1,3'(shape),3'd4,5'd0,11'(left),11'(left+40),11'(top),11'(top+40)};
    endfunction
    task ticks(input integer n);repeat(n) @(negedge clk);endtask
    task reset_case;
        begin rst_n=0;batch=0;start=0;publish=0;toggle=0;reported=0;stamp=0;ticks(5);rst_n=1;ticks(8);end
    endtask
    task observe(input [223:0] candidates,input integer delta_ms);
        begin
            stamp=stamp+delta_ms;batch=1;ticks(1);batch=0;ticks(1);build=0;
            for(integer j=0;j<4;j=j+1) if(candidates[j*56+55]) begin
                packet=candidates[j*56+:56];index=j;start=1;ticks(1);start=0;
                cycles=0;while(!done && cycles<80) begin ticks(1);cycles=cycles+1;end
                if(!done) $fatal(1,"serial tracker did not finish");
                build[j*56+:56]=result;ticks(1);
            end
            reported=build;toggle=~toggle;publish=1;ticks(1);publish=0;ticks(25);observations=observations+1;
        end
    endtask
    initial begin
        force dut.now_ms=stamp;
        reset_case;
        observe({168'd0,raw(1,100,100)},20);saved_id=reported[47:44];
        if(reported[55] || !reported[48]) $fatal(1,"probation identity was not exposed without a display box");
        observe({168'd0,raw(1,165,100)},20);
        observe({168'd0,raw(1,230,100)},20);
        if(!reported[55] || reported[47:44]!=saved_id) $fatal(1,"65px association/three-observation confirmation failed");
        for(integer left=295;left<=685;left=left+65) observe({168'd0,raw(1,left,100)},20);
        if(counts[11:0]!=1 || ng) $fatal(1,"65px motion did not produce one actual count counts=%h ng=%b",counts,ng);
        observe(0,20);observe(0,20);observe({168'd0,raw(1,685,100)},20);
        if(reported[47:44]!=saved_id || !reported[55] || counts[11:0]!=1) $fatal(1,"missed publications broke identity");
        $display("PASS 65px motion, probation upstream history, two missed publications and real counter CDC");

        reset_case;
        observe({168'd0,raw(1,100,100)},20);saved_id=reported[47:44];
        observe({168'd0,raw(1,180,100)},20);observe({168'd0,raw(1,260,100)},20);
        observe({168'd0,raw(1,420,100)},40);
        if(!reported[55] || reported[47:44]!=saved_id) $fatal(1,"elapsed-time 160px prediction failed");
        observe({168'd0,raw(1,580,100)},40);observe({168'd0,raw(1,660,100)},20);
        if(counts[11:0]!=1 || ng) $fatal(1,"variable-interval counter failed");
        observe({168'd0,raw(2,740,100)},20);
        if(reported[47:44]!=saved_id || reported[55]) $fatal(1,"one class glitch changed identity or emitted wrong class");
        observe({168'd0,raw(1,820,100)},20);
        if(!reported[55] || reported[54:52]!=1 || reported[47:44]!=saved_id || counts[23:12]!=0 || counts[11:0]!=1)
            $fatal(1,"shape vote did not recover without duplicate class counts");
        $display("PASS unequal 20/40ms observations, 160px predicted association and classification glitch isolation");

        reset_case;
        observe({168'd0,raw(1,100,100)},120);saved_id=reported[47:44];
        observe({168'd0,raw(1,140,100)},120);observe({168'd0,raw(1,180,100)},120);
        observe(0,120);observe(0,120);observe({168'd0,raw(1,300,100)},120);
        if(!reported[55] || reported[47:44]!=saved_id) $fatal(1,"360ms two-miss interval broke promised ID lifetime");
        $display("PASS 120ms observations and 360ms two-miss recovery retain identity");

        reset_case;
        observe({112'd0,raw(2,280,240),raw(1,100,100)},20);saved_id=reported[47:44];other_id=reported[103:100];
        observe({112'd0,raw(1,160,100),raw(2,340,240)},20);
        observe({112'd0,raw(2,400,240),raw(1,220,100)},20);
        if(reported[47:44]!=saved_id || reported[103:100]!=other_id || !reported[55] || !reported[111])
            $fatal(1,"raster slot reorder transferred identity/votes");
        observe(0,20);observe(0,20);observe(0,20);
        observe({168'd0,raw(1,220,100)},20);
        if(reported[55] || reported[47:44]==saved_id) $fatal(1,"expired track reused stale confirmation or generation got=%h saved=%h ages=%d/%d prev=%h/%h",reported[55:0],saved_id,dut.previous_age[0],dut.previous_age[1],dut.previous[0],dut.previous[1]);
        $display("ALL PASS industrial tracker: %0d observations, stable IDs, timed prediction, missed-track lifetime, class hysteresis, slot reorder, counter integration",observations);$finish;
    end
    initial begin #3000000;$fatal(1,"industrial tracker watchdog");end
endmodule
