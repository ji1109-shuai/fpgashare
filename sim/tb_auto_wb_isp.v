`timescale 1ns/1ps
// Actual ISP/AWB at production frame size; RGB camera substitute is explicit.
module tb_auto_wb_isp;
 reg clk=0,rst=0,valid=0,sof=0,eol=0,sw4=1,status_update=0;
 reg [23:0] rgb=0;
 reg [28:0] settings=29'h02244112;
 wire ov,ol;wire [127:0] diag;
 wire [31:0] reference;
 integer x,y,f,beats=0,lines=0;
 reg [19:0] held_r,held_b;
 reg [95:0] expected[0:1023];
 integer sent=0,received=0;
 always #5 clk=~clk;
 isp_top #(.PARTS_MODE(1),.COLOR_STABILITY(0),.AUTO_WHITE_BALANCE(1),.MULTI_TARGETS(1),.VIDEO_MODES(1)) dut(
 .axi4s_video_aclk(clk),.I_rst_n(rst),.I_tlast(eol),.I_tuser(sof),.I_tdata({16'd0,rgb}),
 .I_tvalid(valid),.I_tdest(10'd0),.O_tready(1'b1),.I_bin_en(1'b0),.I_morph_mode(2'b00),
 .I_awb_freeze(sw4),.I_camera_status(settings),.I_camera_status_upd(status_update),
 .O_wb_diag(diag),.O_color_reference(reference),.O_tvalid(ov),.O_tlast(ol));
 function [7:0] gain(input [7:0] value,input [19:0] factor);
 reg [27:0] product;
 begin product=value*factor;gain=|product[27:24] ? 8'hff:product[23:16];end
 endfunction
 always @(posedge clk) begin
  if(rst && dut.m_aixs_tvalid) begin
   for(integer lane=0;lane<4;lane=lane+1)
    expected[sent%1024][lane*24+:24]={gain(rgb[23:16],dut.u_awb.in_r_r1),rgb[15:8],gain(rgb[7:0],dut.u_awb.in_b_r1)};
   sent=sent+1;
  end
  #1;
  if(rst) begin
   if(dut.u_awb.gain_frozen!==0 || dut.g_tire.u_tire.COLOR_CALIBRATION!=0)
    $fatal(1,"production auto mode still depends on SW4/calibration");
   if(dut.awb_O_tvalid) begin
    if(received>=sent || dut.awb_O_tdata!==expected[received%1024]) $fatal(1,"ISP RGB beat order/value changed");
    received=received+1;
   end
   if(ov) beats=beats+1;
   if(ol) lines=lines+1;
  end
 end
 initial begin
  repeat(4) @(negedge clk);rst=1;
  for(f=0;f<6;f=f+1) begin
   @(negedge clk);sof=1;valid=0;
   @(negedge clk);sof=0;repeat(10) @(negedge clk);
   if(f==4) begin
    held_r=dut.u_awb.in_r_r1;held_b=dut.u_awb.in_b_r1;
    sw4=0;settings=settings+1'b1;status_update=~status_update;
   end
   for(y=0;y<720;y=y+1) begin
    for(x=0;x<320;x=x+1) begin
     @(negedge clk);valid=1;eol=x==319;
     rgb=f>=3 ? 24'hffffff:24'h80c080;
     if(f<3 && x>=152 && x<168 && y>=328 && y<392) rgb=24'hc03838;
    end
    @(negedge clk);valid=0;eol=0;repeat(100) @(negedge clk);
   end
   repeat(1000) @(negedge clk);
  end
  if(dut.u_awb.in_r_r1!==held_r || dut.u_awb.in_b_r1!==held_b || held_r<=20'h13000 || reference[26:24]!==4)
   $fatal(1,"ISP did not acquire/hold automatic gains R%h B%h ref%h",dut.u_awb.in_r_r1,dut.u_awb.in_b_r1,reference);
  if(beats!=6*720*240 || lines!=6*720 || sent!=received || diag[19:9]!==1024 || diag[8:5]!==2)
   $fatal(1,"ISP lost stream or centre diagnostic: beats%0d lines%0d sent%0d received%0d diag%h",beats,lines,sent,received,diag);
  $display("ALL PASS automatic WB ISP: acquired despite red centre and SW4 high, HOLD after clipping/EXP event/SW4, %0d audited RGB beats, %0d packed words/%0d lines, centre diagnostic not overflowed",received,beats,lines);
  $finish;
 end
 initial begin #25000000;$fatal(1,"auto WB ISP watchdog");end
endmodule
