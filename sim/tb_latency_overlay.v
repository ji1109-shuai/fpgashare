`timescale 1ns/1ps
module tb_latency_overlay;
 localparam W=480,H=48,X0=W-192;
 reg clk=0,source_clk=0,rst=0,de=0,sof=0,eol=0;
 reg [15:0] bcd=0;reg valid=0,toggle=0;
 wire ode;wire [23:0] data;
 reg [23:0] expected[0:W*H-1];
 reg [7:0] font_char;reg [3:0] font_row;wire [15:0] font_bits;
 reg [87:0] word_bits;reg [23:0] pixel;
 integer x,y,column,ci,written=0,seen=0,frames=0;
 always #5 clk=~clk;
 always #7 source_clk=~source_clk;
 osd_char_lib font(.I_char(font_char),.I_row(font_row),.O_row_bits(font_bits));
 hdmi_mixer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_ONLY(1),.LATENCY_DIAGNOSTICS(1),
  .LATENCY_DISPLAY_TICK_CYCLES(100)) dut(
  .I_clk(clk),.I_rst_n(rst),.I_video_vsync(1'b0),.I_video_hsync(1'b0),
  .I_video_de(de),.I_video_user(sof),.I_video_last(eol),.I_video_rd_data(24'h556677),
  .I_bbox_upd(1'b0),.I_bbox_valid(1'b0),.I_meas_upd(1'b0),.I_thresh_upd(1'b0),
  .I_roi_upd(1'b0),.I_roi_valid(1'b0),.I_display_mode(3'd0),.I_debug_status(4'd0),
  .I_latency_bcd(bcd),.I_latency_valid(valid),.I_latency_upd(toggle),
  .O_hdmi_de(ode),.O_hdmi_data(data));
 always @(posedge clk) begin
  #1;
  if(rst && ode) begin
   if(seen>=written || data!==expected[seen])
    $fatal(1,"latency raster frame%0d pixel%0d,%0d got%h expected%h",frames,seen%W,seen/W,data,expected[seen]);
   seen=seen+1;
  end
 end
 task send_packet(input [15:0] value,input good);
  begin @(negedge source_clk);bcd=value;valid=good;toggle=~toggle;repeat(12) @(negedge clk);end
 endtask
 task frame(input [87:0] text_bits,input change_midframe);
 begin
  written=0;seen=0;word_bits=text_bits;
  for(y=0;y<H;y=y+1) begin
   for(x=0;x<W;x=x+1) begin
    @(negedge clk);de=1;sof=x==0 && y==0;eol=x==W-1;
    pixel=24'h556677;font_char=" ";font_row=0;column=0;
    if(x>=X0 && x<X0+176 && y>=16 && y<32) begin
     ci=(x-X0)/16;font_char=word_bits[87-ci*8-:8];font_row=y-16;column=(x-X0)%16;
     #1;pixel=font_bits[15-column] ? 24'hffffff:24'h202020;
    end
    expected[written]=pixel;written=written+1;
    if(change_midframe && x==0 && y==20) begin
     // Deliberately change the source packet during the numeric raster.
     // Data settles several asynchronous clocks before its event is observed.
     fork
      begin @(negedge source_clk);bcd=16'h9876;valid=1;toggle=~toggle;end
     join_none
    end
   end
   @(negedge clk);de=0;sof=0;eol=0;repeat(3) @(negedge clk);
  end
  repeat(15) @(negedge clk);
  if(seen!=W*H) $fatal(1,"latency raster lost pixels");
  frames=frames+1;
 end endtask
 initial begin
  repeat(5) @(negedge clk);rst=1;
  // Glyphs introduced for ms, fractional digits and invalid status must exist.
  font_row=11;font_char=".";#1;if(font_bits!==16'h0180) $fatal(1,"missing decimal point");
  font_row=7;font_char="-";#1;if(font_bits!==16'h0ff0) $fatal(1,"missing invalid dash");
  font_row=7;font_char="m";#1;if(font_bits!==16'h4990) $fatal(1,"missing m");
  font_row=10;font_char="s";#1;if(font_bits!==16'h0018) $fatal(1,"missing s");
  frame("DET:---.-ms",0);
  send_packet(16'h0123,1);frame("DET:012.3ms",1);
  frame("DET:987.6ms",0);
  send_packet(16'h0000,0);frame("DET:---.-ms",0);
  send_packet(16'h0000,1);frame("DET:000.0ms",0);
  // Accelerated 1 s stale timeout, then recovery on a fresh source event.
  repeat(1000010) @(negedge clk);frame("DET:---.-ms",0);
  send_packet(16'h1000,1);frame("DET:100.0ms",0);
  rst=0;repeat(4) @(negedge clk);rst=1;bcd=16'h8888;valid=1;toggle=0;
  frame("DET:---.-ms",0);
  $display("ALL PASS latency OSD: 8 frames, asynchronous event, atomic mid-raster update, valid zero, invalid/reset/stale/recovery and exact pixels");$finish;
 end
 initial begin #20000000;$fatal(1,"latency raster timeout");end
endmodule
