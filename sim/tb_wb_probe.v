`timescale 1ns/1ps
module tb_wb_probe;
 reg clk=0,rst=0,valid=0,sof=0,freeze=1,invalidate=0;
 reg [95:0] rgb=0;
 wire [127:0] diag;
 wire [31:0] reference,reference_plain;
 wire [95:0] out,out_plain;
 wire ov,ov_plain,ol,ol_plain,ou,ou_plain,ru,ru_plain,update;
 integer x,y,f,mode,checks=0;
 reg [23:0] pixel;
 reg [127:0] held;
 always #5 clk=~clk;
 awb #(.IMG_WIDTH(256),.IMG_HEIGHT(80),.REFERENCE_ONLY(1),.REFERENCE_WINDOW(64),.DIAGNOSTICS(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(valid),
 .I_gain_freeze(freeze),.I_cal_reset(invalidate),.O_reference(reference),.O_reference_upd(ru),
 .O_tdata(out),.O_tvalid(ov),.O_tlast(ol),.O_tuser(ou),.O_tready(1'b1),
 .O_diagnostics(diag),.O_diagnostics_upd(update));
 awb #(.IMG_WIDTH(256),.IMG_HEIGHT(80),.REFERENCE_ONLY(1),.REFERENCE_WINDOW(64),.DIAGNOSTICS(0)) plain(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(valid),
 .I_gain_freeze(freeze),.I_cal_reset(invalidate),.O_reference(reference_plain),.O_reference_upd(ru_plain),
 .O_tdata(out_plain),.O_tvalid(ov_plain),.O_tlast(ol_plain),.O_tuser(ou_plain),.O_tready(1'b1));
 // Observer must not alter a single output beat or calibration event.
 always @(posedge clk) begin
  #1;
  if(rst) begin
   if({ov,ol,ou,reference,ru}!=={ov_plain,ol_plain,ou_plain,reference_plain,ru_plain})
    $fatal(1,"probe changed video timing/calibration");
   if(ov && out!==out_plain) $fatal(1,"probe changed video pixels");
   if(ov) checks=checks+1;
  end
 end
 task frame(input integer kind);
 begin
  @(negedge clk);sof=1;valid=0;@(negedge clk);sof=0;repeat(8) @(negedge clk);
  for(y=0;y<80;y=y+1) begin
   for(x=0;x<256;x=x+4) begin
    @(negedge clk);valid=1;
    // Outside ROI is strongly coloured and must not affect any statistics.
    pixel=24'hff0000;
    if(x>=96 && x<160 && y>=8 && y<72) begin
     mode=kind;
     if(kind==4) mode=(x<128 ? 0:1)+(y<40 ? 0:2);
     case(mode)
      0:pixel=24'h80c080;1:pixel=24'h80ff80;
      2:pixel=24'h181818;3:pixel=24'h40a040;
     endcase
    end
    rgb={4{pixel}};
   end
   @(negedge clk);valid=0;repeat(4) @(negedge clk);
  end
  repeat(300) @(negedge clk);
 end endtask
 task capture(input integer kind);
 begin frame(kind);frame(kind);end endtask
 task counts(input integer good,hi,lo,col,why,input [23:0] mean);
 begin
  if(diag[127:104]!==mean || diag[63:53]!==good || diag[52:42]!==hi ||
     diag[41:31]!==lo || diag[30:20]!==col || diag[19:9]!==1024 || diag[8:5]!==why)
   $fatal(1,"probe packet mismatch %h mean%h counts%0d/%0d/%0d/%0d reason%0d",diag,mean,good,hi,lo,col,why);
 end endtask
 initial begin
  repeat(4) @(negedge clk);rst=1;
  capture(1);counts(0,1024,0,0,2,24'h80ff80);
  if(reference[25:24]!==0 || diag[103:84]!==20'h10000 || diag[83:64]!==20'h10000)
   $fatal(1,"BAD locked probe did not expose unity correction");
  capture(2);counts(0,0,1024,0,3,24'h181818);
  capture(3);counts(0,0,0,1024,4,24'h40a040);
  capture(0);counts(1024,0,0,0,0,24'h80c080);
  if(reference[25:24]!==0) $fatal(1,"sample usability must not silently calibrate a BAD lock");
  // Four quadrants, independent hand-computed integer RGB averages.
  capture(4);counts(256,256,256,256,0,24'h569d56);
  freeze=0;repeat(4) @(negedge clk);
  for(f=0;f<45;f=f+1) frame(0);
  if(reference[25:24]!==3) $fatal(1,"calibration failed with observer enabled");
  freeze=1;repeat(4) @(negedge clk);capture(0);
  if(diag[103:84]<20'h17f00 || diag[103:84]>20'h18000 ||
     diag[83:64]<20'h17f00 || diag[83:64]>20'h18000)
   $fatal(1,"probe reported target rather than applied green correction %h",diag);
  invalidate=1;@(negedge clk);invalidate=0;capture(0);frame(0);
  if(reference[25:24]!==0 || diag[103:84]!==20'h10000 || diag[83:64]!==20'h10000)
   $fatal(1,"settings invalidation not visible in actual correction");
  held=diag;repeat(30) @(negedge clk);
  if(diag!==held) $fatal(1,"probe packet not frame-held");
  if(checks<100000) $fatal(1,"probe equivalence audit had insufficient video beats %0d",checks);
  $display("ALL PASS WB probe: rejected/usable/mixed raw ROI, BAD lock, actual applied gains, invalidation and %0d unchanged video beats",checks);
  $finish;
 end
 initial begin #20000000;$fatal(1,"probe watchdog");end
endmodule

module tb_wb_probe_overlay;
 tb_multi_overlay #(.WB_PROBE(1)) test();
endmodule
