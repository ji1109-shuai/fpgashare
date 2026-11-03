module tb_batch_counter;
    reg clk=0;
    reg rst_n=0;
    reg targets_toggle=0;
    reg [223:0] targets=0;
    reg set_enable=0;
    reg key_inc_n=1,key_dec_n=1,key_clear_n=1;
    wire [11:0] count_bcd,target_bcd;
    wire [47:0] counts_bcd,targets_bcd;
    wire [2:0] filter_type;
    wire done;
    wire overrun;
    wire [3:0] overrun_mask;

    always #10 clk=~clk;

    conveyor_batch_counter #(
        .LINE_X(11'd640),
        .DEFAULT_TARGET_BCD(12'h004),
        .DEBOUNCE_CYCLES(2),
        // Keep a real gap between short (7 cycles) and long (20 cycles).
        .LONG_PRESS_CYCLES(12)
    ) dut(
        .clk(clk),.rst_n(rst_n),
        .I_targets_toggle(targets_toggle),.I_targets(targets),
        .I_set_enable(set_enable),
        .I_key_inc_n(key_inc_n),.I_key_dec_n(key_dec_n),.I_key_clear_n(key_clear_n),
        .I_menu_type(3'd0),.I_menu_inc(1'b0),.I_menu_dec(1'b0),.I_menu_clear(1'b0),
        .O_count_bcd(count_bcd),.O_target_bcd(target_bcd),
        .O_counts_bcd(counts_bcd),.O_targets_bcd(targets_bcd),
        .O_filter_type(filter_type),.O_done(done),
        .O_overrun(overrun),.O_overrun_mask(overrun_mask)
    );

    function [55:0] packet;
        input [2:0] shape;
        input [10:0] x0,x1,y0,y1;
        reg [55:0] p;
        begin
            p=0;p[55]=1;p[54:52]=shape;p[43:33]=x0;p[32:22]=x1;p[21:11]=y0;p[10:0]=y1;
            packet=p;
        end
    endfunction

    task publish;
        input [223:0] value;
        begin
            @(negedge clk);targets=value;targets_toggle=~targets_toggle;
            repeat(10) @(negedge clk);
        end
    endtask

    task press_inc;
        begin @(negedge clk);key_inc_n=0;repeat(7) @(negedge clk);key_inc_n=1;repeat(10) @(negedge clk);end
    endtask
    task press_dec;
        begin @(negedge clk);key_dec_n=0;repeat(7) @(negedge clk);key_dec_n=1;repeat(10) @(negedge clk);end
    endtask
    task press_clear;
        begin @(negedge clk);key_clear_n=0;repeat(7) @(negedge clk);key_clear_n=1;repeat(10) @(negedge clk);end
    endtask
    task hold_clear;
        begin @(negedge clk);key_clear_n=0;repeat(20) @(negedge clk);key_clear_n=1;repeat(10) @(negedge clk);end
    endtask

    initial begin
        repeat(4) @(negedge clk);rst_n=1;repeat(5) @(negedge clk);
        if(filter_type!==3'd1 || target_bcd!==12'h004) $fatal(1,"default screw quota mismatch type=%d target=%h",filter_type,target_bcd);

        // Two independently detected parts enter the line in one publication.
        publish({112'd0,packet(1,600,680,300,380),packet(1,590,690,100,180)});
        if(count_bcd!==12'h002 || done) $fatal(1,"two-object count failed count=%h done=%b",count_bcd,done);

        // Slot order changes, but both are the same line occupants: no recount.
        publish({112'd0,packet(1,608,688,104,184),packet(1,610,690,304,384)});
        if(count_bcd!==12'h002) $fatal(1,"slot reorder recounted count=%h",count_bcd);

        // The line clears, then another two parts enter together.  Count reaches
        // the setpoint and completion latches.
        publish(224'd0);
        publish({112'd0,packet(1,600,680,420,500),packet(1,600,680,210,290)});
        if(count_bcd!==12'h004 || !done) $fatal(1,"completion failed count=%h done=%b",count_bcd,done);

        set_enable=1;
        press_clear();
        if(count_bcd!==12'h000 || done) $fatal(1,"clear failed count=%h done=%b",count_bcd,done);
        press_inc();
        if(target_bcd!==12'h005) $fatal(1,"increment failed target=%h",target_bcd);
        press_dec();
        if(target_bcd!==12'h004) $fatal(1,"decrement failed target=%h",target_bcd);

        // Configure one screw, one washer, one hex nut and one square nut.
        // Long KEY3 changes only the selected quota; all counters run in parallel.
        press_dec();press_dec();press_dec();
        if(target_bcd!==12'h001) $fatal(1,"screw quota setup failed target=%h",target_bcd);
        hold_clear();
        if(filter_type!==3'd2 || count_bcd!==0 || target_bcd!==0) $fatal(1,"washer selection failed filter=%d",filter_type);
        press_inc();
        if(target_bcd!==12'h001) $fatal(1,"washer quota setup failed target=%h",target_bcd);
        hold_clear();
        if(filter_type!==3'd3 || count_bcd!==0 || target_bcd!==0) $fatal(1,"hex selection failed filter=%d",filter_type);
        press_inc();
        if(target_bcd!==12'h001) $fatal(1,"hex quota setup failed target=%h",target_bcd);
        hold_clear();
        if(filter_type!==3'd4 || count_bcd!==0 || target_bcd!==0) $fatal(1,"square selection failed filter=%d",filter_type);
        press_inc();
        if(target_bcd!==12'h001) $fatal(1,"square quota setup failed target=%h",target_bcd);

        publish(224'd0);
        publish({packet(4,600,680,500,580),packet(3,600,680,360,440),
                 packet(2,600,680,220,300),packet(1,600,680,80,160)});
        if(count_bcd!==12'h001 || !done) $fatal(1,"four-class quotas failed selected_count=%h done=%b",count_bcd,done);
        if(counts_bcd!==48'h001001001001 || targets_bcd!==48'h001001001001)
            $fatal(1,"four-class UI buses failed counts=%h targets=%h",counts_bcd,targets_bcd);

        // Exact-quantity policy: two screws against a quota of one is an NG
        // batch.  Stop/fault must latch immediately even though the other
        // three class quotas have not yet been reached.
        press_clear();
        publish(224'd0);
        publish({112'd0,packet(1,600,680,300,380),packet(1,590,690,100,180)});
        if(counts_bcd[11:0]!==12'h002 || done || !overrun || overrun_mask!==4'b0001)
            $fatal(1,"overrun policy failed counts=%h done=%b overrun=%b mask=%b",
                counts_bcd,done,overrun,overrun_mask);
        publish(224'd0);publish(224'd0);publish(224'd0);
        if(counts_bcd[11:0]!==12'h001 || overrun || overrun_mask!==0 || done)
            $fatal(1,"reject recovery failed counts=%h done=%b overrun=%b mask=%b",
                counts_bcd,done,overrun,overrun_mask);

        $display("PASS: simultaneous counting, overrun stop and reject recovery");
        $finish;
    end
endmodule
