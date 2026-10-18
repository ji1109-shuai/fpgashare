`timescale 1ns/1ps
module tb_colour_ratios;
    reg clk=0,rst=0;
    reg [23:0] rgb=0;
    reg [7:0] reference=224;
    wire [2:0] colour;
    integer scale,n=0;
    always #5 clk=~clk;
    img_parts_color dut(clk,rst,rgb,reference,colour);
    task check(input [23:0] px,input [7:0] ref_value,input [2:0] expected);
        begin
            @(negedge clk);rgb=px;reference=ref_value;
            repeat(2) @(negedge clk);
            if(colour!==expected) $fatal(1,"RGB %h reference%0d got%0d expected%0d",px,ref_value,colour,expected);
            n=n+1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=1;
        for(scale=1;scale<=7;scale=scale+1) begin
            check({8'(scale*32),8'(scale*8),8'(scale*8)},224,1);
            check({8'(scale*28),8'(scale*24),8'(scale*12)},224,6);
        end
        check(24'h484848,224,0); // neutral black/silver uncertainty band
        check(24'h303030,224,4);check(24'h606060,224,5);
        check(24'h202020,128,4);check(24'h404040,128,5);
        check(24'h000000,224,0);check(24'h070707,224,0);
        check(24'hfa3030,224,0);check(24'hffffff,224,0);
        check(24'h28a038,224,0);check(24'h3030c0,224,0);
        // Back-to-back lanes/colours expose accidental third-cycle latency.
        @(negedge clk);rgb=24'hc03030;
        @(negedge clk);rgb=24'hb89848;
        @(negedge clk);if(colour!==1) $fatal(1,"red two-cycle latency");rgb=24'h303030;
        @(negedge clk);if(colour!==6) $fatal(1,"brass two-cycle latency");rgb=24'hb0b0b0;
        @(negedge clk);if(colour!==4) $fatal(1,"black two-cycle latency");
        @(negedge clk);if(colour!==5) $fatal(1,"silver two-cycle latency");
        $display("ALL PASS relative colour ratios: %0d brightness/reference/rejection cases and back-to-back two-clock alignment",n);
        $finish;
    end
endmodule

module tb_wb_reference;
    reg clk=0,rst=0,valid=0,sof=0,freeze=0,invalidate=0;
    reg [95:0] rgb=0;
    wire [31:0] reference;
    wire upd;
    integer x,y,f;
    reg [31:0] held_reference;
    reg [19:0] held_r,held_b;
    always #5 clk=~clk;
    awb #(.IMG_WIDTH(256),.IMG_HEIGHT(16),.REFERENCE_ONLY(1),.REFERENCE_WINDOW(64),.MIN_REFERENCE_SAMPLES(32)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(valid),
        .I_gain_freeze(freeze),.I_cal_reset(invalidate),.O_reference(reference),.O_reference_upd(upd),.O_tready(1'b1));
    task frame(input [23:0] neutral,input integer mixed);
        begin
            @(negedge clk);sof=1;valid=0;
            @(negedge clk);sof=0;repeat(8) @(negedge clk);
            for(y=0;y<16;y=y+1) begin
                for(x=0;x<64;x=x+1) begin
                    @(negedge clk);valid=1;
                    rgb={4{x<24 || x>=40 ? 24'hd0a0c0 : mixed && x%4==1 ? 24'hff2020 : mixed && x%4==2 ? 24'hffffff :
                        mixed && x%4==3 ? 24'h080808 : neutral}};
                end
                @(negedge clk);valid=0;repeat(4) @(negedge clk);
            end
            repeat(300) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=1;
        for(f=0;f<40;f=f+1) frame(24'ha0c080,1);
        if(reference[25:24]!==3 || reference[23:16]<159 || reference[23:16]>160 ||
            reference[15:8]<191 || reference[15:8]>192 || reference[7:0]<127 || reference[7:0]>128)
            $fatal(1,"neutral reference failed %h",reference);
        freeze=1;repeat(4) @(negedge clk);
        held_reference=reference;held_r=dut.in_r_r1;held_b=dut.in_b_r1;
        for(f=0;f<4;f=f+1) frame(24'hc08060,0);
        if(reference!==held_reference || reference[26]!==1 || dut.in_r_r1!==held_r || dut.in_b_r1!==held_b)
            $fatal(1,"locked calibration changed with object");
        invalidate=1;@(negedge clk);invalidate=0;repeat(3) @(negedge clk);
        if(reference[25:24]!==0 || !reference[26]) $fatal(1,"exposure reset failed");
        frame(24'ha0c080,0);
        if(reference[25]!==0) $fatal(1,"invalid lock rearmed itself");
        freeze=0;repeat(3) @(negedge clk);
        for(f=0;f<40;f=f+1) frame(24'ha0c080,1);
        if(reference[25:24]!==3) $fatal(1,"recalibration failed");
        frame(24'hffffff,0);frame(24'hffffff,0);
        if(reference[25:24]!==0) $fatal(1,"clipped reference accepted");
        for(f=0;f<3;f=f+1) frame(24'h080808,0);
        if(reference[25:24]!==0) $fatal(1,"dark reference accepted");
        $display("ALL PASS WB reference: centre ROI excludes differently lit neutral surroundings; neutral-only samples, RGB means, convergence, lock, configuration invalidation, unlock/recalibrate, clipped/dark rejection");
        $finish;
    end
    initial begin #100000000;$fatal(1,"WB reference watchdog");end
endmodule

module tb_colour_diagnostic_osd;
    reg clk=0,rst=0,user=0,ref_upd=0,box_upd=0;
    reg [31:0] reference=0;
    reg [127:0] stats=0;
    always #5 clk=~clk;
    hdmi_mixer #(.COLOR_DIAGNOSTICS(1)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_video_vsync(1'b0),.I_video_hsync(1'b0),.I_video_de(1'b0),
        .I_video_user(user),.I_video_last(1'b0),.I_debug_status(4'd0),.I_video_rd_data(24'd0),
        .I_color_reference(reference),.I_color_reference_upd(ref_upd),.I_color_diag(stats),.I_bbox_upd(box_upd));
    task character(input [2:0] row,input [3:0] index,input [7:0] expected);
        begin
            if(dut.colour_diagnostic_char(row,index)!==expected)
                $fatal(1,"OSD row%0d index%0d got%h expected%h",row,index,dut.colour_diagnostic_char(row,index),expected);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=1;
        reference=32'h07a0c080;
        stats={24'hc03020,16'h1234,16'h5678,16'h9abc,16'hdef0,16'h1357,4'd0,1'b1,1'b1,3'd1,4'd4,11'd0};
        ref_upd=1;box_upd=1;repeat(6) @(negedge clk);
        if(dut.reference_display!==0 || dut.colour_display!==0) $fatal(1,"OSD changed mid frame");
        user=1;@(negedge clk);user=0;
        if(dut.reference_display!==reference || dut.colour_display!==stats) $fatal(1,"OSD packet CDC");
        character(0,3,"L");character(0,13,"K");
        character(1,4,"A");character(1,9,"0");
        character(2,4,"C");character(2,9,"0");
        character(3,2,"1");character(3,5,"4");character(3,9,"5");character(3,12,"8");
        character(4,2,"9");character(4,5,"C");character(4,9,"D");character(4,12,"0");
        character(5,2,"1");character(5,5,"7");character(5,9,"1");character(6,4,"M");
        reference=0;ref_upd=0;stats=0;box_upd=0;repeat(6) @(negedge clk);
        character(1,4,"A"); // still held until next display frame
        user=1;@(negedge clk);user=0;
        character(1,4,"-");character(2,4,"-");
        stats={113'd0,4'd8,11'd0};box_upd=1;repeat(6) @(negedge clk);
        user=1;@(negedge clk);user=0;character(6,4,"S");character(6,9,"M");
        $display("ALL PASS colour diagnostic OSD: two event CDC packets, frame hold, hex RGB/votes/area/fallback/reasons including stream error");
        $finish;
    end
endmodule

module tb_colour_stream_error;
    reg clk=0,rst=0,valid=0,sof=0;
    integer beat;
    wire [127:0] diag;
    wire [2:0] status;
    wire [2:0] colour;
    always #5 clk=~clk;
    img_tire #(.BEATS_PER_LINE(16),.LINES_PER_FRAME(64),.PARTS_MODE(1),.COLOR_MODE(1)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_tdata(96'd0),.I_rgb({4{24'he8e8e8}}),
        .I_tvalid(valid),.I_tuser(sof),.I_tlast(1'b0),.I_roi_valid(1'b0),
        .I_roi_x0(11'd0),.I_roi_x1(11'd63),.I_roi_y0(11'd0),.I_roi_y1(11'd63),
        .I_query_bank(1'b0),.I_query_row(8'd0),.O_color_diag(diag),.O_status(status),.O_color(colour));
    initial begin
        repeat(4) @(negedge clk);rst=1;
        for(beat=0;beat<16;beat=beat+1) begin
            @(negedge clk);valid=1;sof=beat==0;
        end
        @(negedge clk);valid=0;sof=0;repeat(12) @(negedge clk);
        if(status!==5 || colour!==0 || diag!=={113'd0,4'd8,11'd0}) $fatal(1,"stream error retained stale colour/diagnostic");
        $display("ALL PASS malformed colour stream: missing EOL clears colour and diagnostic statistics, publishes STREAM");
        $finish;
    end
endmodule
