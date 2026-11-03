`timescale 1ns/1ps
module tb_fps_display;
    reg clk=0,rst=0,sof=0,upd=0;reg [11:0] value=0;
    always #5 clk=~clk;
    hdmi_mixer #(.FPS_DISPLAY(1)) dut(.I_clk(clk),.I_rst_n(rst),
        .I_video_user(sof),.I_video_de(1'b0),.I_video_last(1'b0),
        .I_fps_bcd(value),.I_fps_update(upd));
    task ticks(input integer n);repeat(n) @(negedge clk);endtask
    task frame;begin sof=1;ticks(1);sof=0;ticks(2);end endtask
    task receive(input [11:0] v);begin value=v;upd=~upd;ticks(8);end endtask
    initial begin
        ticks(4);rst=1;ticks(4);frame;
        if(dut.fps_frame_valid) $fatal(1,"FPS must start with unavailable dashes");
        receive(12'h030);
        if(dut.fps_frame_valid) $fatal(1,"FPS changed before frame boundary");
        frame;if(!dut.fps_frame_valid || dut.fps_frame!=12'h030) $fatal(1,"FPS source CDC failed");
        receive(12'h080);if(dut.fps_frame!=12'h030) $fatal(1,"FPS tore during frame");
        frame;if(dut.fps_frame!=12'h080) $fatal(1,"FPS next frame latch failed");
        receive(0);frame;if(!dut.fps_frame_valid || dut.fps_frame!=0) $fatal(1,"stopped camera zero became unavailable");
        $display("ALL PASS FPS display: startup unavailable, held-data CDC, SOF-only update, mid-frame stability, valid zero");$finish;
    end
endmodule
