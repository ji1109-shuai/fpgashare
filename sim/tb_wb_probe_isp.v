`timescale 1ns/1ps
// Real production ISP and AWB at 1280x720. The camera model supplies
// already demosaiced RGB; this test makes no claim about physical Bayer data.
module tb_wb_probe_isp;
 reg clk=0,rst=0,valid=0,sof=0,eol=0;
 reg [23:0] rgb=24'h80ff80;
 wire [127:0] probe;
 wire [31:0] reference;
 wire update,ov;
 integer x,y,beats=0;
 always #5 clk=~clk;
 isp_top #(.PARTS_MODE(1),.COLOR_STABILITY(1),.MULTI_TARGETS(1),.VIDEO_MODES(1)) dut(
 .axi4s_video_aclk(clk),.I_rst_n(rst),.I_tlast(eol),.I_tuser(sof),.I_tdata({16'd0,rgb}),
 .I_tvalid(valid),.I_tdest(10'd0),.O_tready(1'b1),.I_bin_en(1'b0),.I_morph_mode(2'b00),
 .I_awb_freeze(1'b1),.I_camera_status(29'd0),.I_camera_status_upd(1'b0),
 .O_wb_diag(probe),.O_wb_diag_upd(update),.O_color_reference(reference),.O_tvalid(ov));
 always @(posedge clk) if(rst && ov) beats=beats+1;
 task frame;
 begin
  @(negedge clk);sof=1;valid=0;@(negedge clk);sof=0;repeat(10) @(negedge clk);
  for(y=0;y<720;y=y+1) begin
   for(x=0;x<320;x=x+1) begin @(negedge clk);valid=1;eol=x==319;end
   @(negedge clk);valid=0;eol=0;repeat(100) @(negedge clk);
  end
  repeat(1000) @(negedge clk);
 end endtask
 initial begin
  repeat(4) @(negedge clk);rst=1;
  frame();frame();
  if(probe!=={24'h80ff80,20'h10000,20'h10000,11'd0,11'd1024,11'd0,11'd0,11'd1024,4'd2,5'd0})
   $fatal(1,"production ISP probe not wired/ROI incorrect %h",probe);
  if(reference[25:24]!==0 || !reference[26] || beats<300000)
   $fatal(1,"production BAD lock/video missing %h beats%0d",reference,beats);
  $display("ALL PASS WB probe ISP: actual 1280x720 centre 64x64, raw green/clipped reference, unity correction in BAD lock, %0d packed video beats",beats);
  $finish;
 end
 initial begin #15000000;$fatal(1,"probe ISP watchdog");end
endmodule

module demosaic #(parameter IMG_HEIGHT=720,IMG_WIDTH=1280,data_complete_delay=50,BAYER_MODE="BGGR")(
 input I_clk,I_rst_n,input [39:0] axi4s_video_tdata,input [9:0] axi4s_video_tdest,
 input axi4s_video_tlast,axi4s_video_tvalid,axi4s_video_tuser,
 output axi4s_video_tready,O_tlast,O_tuser,O_tvalid,output [127:0] O_tdata,input O_tready);
 assign axi4s_video_tready=O_tready;
 assign O_tlast=axi4s_video_tlast;assign O_tuser=axi4s_video_tuser;assign O_tvalid=axi4s_video_tvalid;
 assign O_tdata={4{8'd0,axi4s_video_tdata[23:0]}};
endmodule
