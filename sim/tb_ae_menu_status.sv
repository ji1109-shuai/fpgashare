`timescale 1ns/1ps
module tb_ae_menu_status # (parameter integer READ_LATENCY=0,AE_DIAG=0,TARGET_SWEEP=0);
    reg clk=0,rst_n=0,de=0,sof=0,last=0;
    reg ae_auto=0,ae_lock=0;
    reg [2:0] motor=0;
    integer x,y,scenario,checked=0,diag_checked=0,target_checked=0;
    reg [4:0] target_level=16;
    wire [7:0] target_value={target_level,3'b000};
    wire [7:0] th=8'd48+target_value/100,tt=8'd48+(target_value/10)%10,to=8'd48+target_value%10;
    reg [31:0] expected;
    wire [127:0] diag_row0={"AE4:",expected," Y:C8 V1"};
    wire [127:0] diag_row1="I:11 W:03       ";
    wire [127:0] diag_row2={"T:",th,tt,to," S:",ae_lock ? "16":"07","/16   "};
    wire [127:0] target_row={TARGET_SWEEP ? ">":" ","AE Y:",th,tt,to,"       "};
    hdmi_mixer #(.VIDEO_READ_LATENCY(READ_LATENCY),.TARGET_ONLY(1),.PARTS_MODE(1),.AE_DIAGNOSTICS(AE_DIAG)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(1'b0),.I_video_hsync(1'b0),
        .I_video_de(de),.I_video_user(sof),.I_video_last(last),
        .I_video_rd_data(24'h102030),.I_debug_status(4'd0),
        .I_menu_open(1'b1),.I_menu_index(TARGET_SWEEP?4'd11:4'd3),.I_menu_preview_mode(3'd0),
        .I_menu_motor_level(motor),.I_menu_awb_freeze(1'b0),
        .I_menu_ae_auto(ae_auto),.I_menu_ae_locked(ae_lock),.I_menu_ae_target_level(target_level),
        .I_ae_diagnostics({8'hc8,1'b1,1'b1,1'b1,5'd7,8'd3,1'b1}),.I_ae_diagnostics_upd(1'b1),
        .I_meas_upd(1'b0),.I_thresh_upd(1'b0),.I_bbox_upd(1'b0),
        .I_roi_upd(1'b0),.I_camera_status_upd(1'b0),.I_color_reference_upd(1'b0),
        .I_wb_diag_upd(1'b0),.I_latency_upd(1'b0),.I_targets(224'd0),
        .I_bbox_valid(1'b0),.I_roi_valid(1'b0),.I_target_count(3'd0),
        .I_target_overflow(1'b0),.I_batch_overrun(1'b0),.I_batch_done(1'b0)
    );
    always #5 clk=~clk;
    always @(posedge clk) begin
        #1;
        if(rst_n && dut.p1_band==dut.BAND_COLOUR_DIAG &&
           dut.p1_diag_row==4 && dut.p1_ly==8 && dut.p1_dx[3:0]==0 &&
           dut.p1_dx[7:4]>=4 && dut.p1_dx[7:4]<=7) begin
            if(dut.c_char!==expected[(7-dut.p1_dx[7:4])*8+:8])
                $fatal(1,"AE menu scenario%0d char%0d got%h expected%h",scenario,
                    dut.p1_dx[7:4],dut.c_char,expected);
            checked=checked+1;
        end
        if(AE_DIAG && rst_n && dut.p1_band==dut.BAND_COLOUR_DIAG &&
           dut.p1_diag_row>=13 && dut.p1_ly==8 && dut.p1_dx[3:0]==0 && dut.p1_dx<256) begin
            if(!dut.c_ok || dut.c_char!==(dut.p1_diag_row==13 ?
                diag_row0[(15-dut.p1_dx[7:4])*8+:8]:dut.p1_diag_row==14 ? diag_row1[(15-dut.p1_dx[7:4])*8+:8]:diag_row2[(15-dut.p1_dx[7:4])*8+:8]))
                $fatal(1,"live AE diagnostic char mismatch row=%0d col=%0d char=%h",dut.p1_diag_row,dut.p1_dx[7:4],dut.c_char);
            diag_checked=diag_checked+1;
        end
        if(TARGET_SWEEP && rst_n && dut.p1_band==dut.BAND_COLOUR_DIAG && dut.p1_diag_row==12 &&
           dut.p1_ly==8 && dut.p1_dx[3:0]==0 && dut.p1_dx<224) begin
            if(!dut.c_ok || dut.c_char!==target_row[(15-dut.p1_dx[7:4])*8+:8])
                $fatal(1,"AE target menu mismatch level=%0d col=%0d char=%h",target_level,dut.p1_dx[7:4],dut.c_char);
            target_checked=target_checked+1;
        end
    end
    task ticks(input integer n);
        repeat(n) begin @(negedge clk);end
    endtask
    task scan_frame;
        begin
            ticks(6);
            for(y=0;y<(AE_DIAG?256:136);y=y+1) begin
                for(x=0;x<1280;x=x+1) begin
                    @(negedge clk);de=1;sof=(x==0 && y==0);last=(x==1279);
                end
                @(negedge clk);de=0;sof=0;last=0;ticks(6);
            end
            ticks(10);
        end
    endtask
    initial begin
        ticks(4);rst_n=1;
        for(scenario=0;scenario<(TARGET_SWEEP?17:5);scenario=scenario+1) begin
            case(scenario%5)
                0:begin ae_auto=0;ae_lock=0;motor=0;expected="MAN ";end
                1:begin ae_auto=1;ae_lock=0;motor=0;expected="AUTO";end
                2:begin ae_auto=1;ae_lock=1;motor=0;expected="LOCK";end
                3:begin ae_auto=1;ae_lock=1;motor=2;expected="LOCK";end
                4:begin ae_auto=1;ae_lock=0;motor=2;expected="AUTO";end
            endcase
            if(TARGET_SWEEP) target_level=8+scenario;
            checked=0;diag_checked=0;target_checked=0;scan_frame;
            if(checked!=4) $fatal(1,"AE row not fully scanned got%0d",checked);
            if(AE_DIAG && diag_checked!=48) $fatal(1,"live AE diagnostic rows incomplete got%0d",diag_checked);
            if(TARGET_SWEEP && target_checked!=14) $fatal(1,"AE target row incomplete got%0d",target_checked);
        end
        $display("ALL PASS AE menu MAN/AUTO/LOCK with motor independent, frame CDC latency=%0d",READ_LATENCY);
        $finish;
    end
    initial begin #100000000;$fatal(1,"AE menu watchdog");end
endmodule
module tb_ae_live_status;
    tb_ae_menu_status #(.AE_DIAG(1)) test();
endmodule
module tb_ae_live_status_rd2;
    tb_ae_menu_status #(.AE_DIAG(1),.READ_LATENCY(2)) test();
endmodule
module tb_ae_menu_status_rd2;
    tb_ae_menu_status #(.READ_LATENCY(2)) test();
endmodule

module tb_ae_target_status; tb_ae_menu_status #(.AE_DIAG(1),.TARGET_SWEEP(1)) test(); endmodule
module tb_ae_target_status_rd2; tb_ae_menu_status #(.AE_DIAG(1),.TARGET_SWEEP(1),.READ_LATENCY(2)) test(); endmodule
