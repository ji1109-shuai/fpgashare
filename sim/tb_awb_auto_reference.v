`timescale 1ns/1ps
// Reproduce a green-cast board with a coloured/occluded centre. No white card,
// forced internal gains or unity-input assumption. Uses real AWB + RAM model.
module tb_awb_auto_reference;
 localparam W=256,H=80;
 reg clk=0,rst=0,valid=0,sof=0,freeze=1,invalidate=0;
 reg [95:0] data=0;
 wire [95:0] out,old_out,unity_out;
 wire ov,ol,ou,old_v,unity_v;
 wire [31:0] reference;
 wire [127:0] diag;
 integer x,y,f,k,mode=0,sent=0,received=0,lines=0;
 reg [95:0] expected[0:1023];
 reg [19:0] held_r,held_b;
 reg [23:0] neutral=24'h80c080;
 reg check_board=0;
 integer checks=0;
 always #5 clk=~clk;
 awb #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.REFERENCE_ONLY(1),.AUTO_REFERENCE(1),
 .MIN_REFERENCE_SAMPLES(128),.DIAGNOSTICS(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(sof),.I_tdata(data),.I_tvalid(valid),
 .I_gain_freeze(freeze),.I_cal_reset(invalidate),.O_tdata(out),.O_tvalid(ov),.O_tlast(ol),.O_tuser(ou),
 .O_tready(1'b1),.O_reference(reference),.O_diagnostics(diag));
 // Old centre-only configuration sees a red part and rejects every sample.
 awb #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.REFERENCE_ONLY(1),.REFERENCE_WINDOW(64)) old(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(sof),.I_tdata(data),.I_tvalid(valid),
 .I_gain_freeze(1'b0),.I_cal_reset(1'b0),.O_tdata(old_out),.O_tvalid(old_v),.O_tready(1'b1));
 // The withdrawn fix holds reset gains forever and leaves green RGB intact.
 awb #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) unity(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(sof),.I_tdata(data),.I_tvalid(valid),
 .I_gain_freeze(1'b1),.I_cal_reset(1'b0),.O_tdata(unity_out),.O_tvalid(unity_v),.O_tready(1'b1));
 function [7:0] gain(input [7:0] value,input [19:0] factor);
  reg [27:0] product;
  begin product=value*factor;gain=|product[27:24] ? 8'hff:product[23:16];end
 endfunction
 always @(posedge clk) begin
  if(rst && valid) begin
   for(integer lane=0;lane<4;lane=lane+1)
    expected[sent%1024][lane*24+:24]={gain(data[lane*24+16+:8],dut.in_r_r1),
     data[lane*24+8+:8],gain(data[lane*24+:8],dut.in_b_r1)};
   sent=sent+1;
  end
  #1;
  if(rst) begin
   if(ou!==sof || ov!==old_v || ov!==unity_v) $fatal(1,"automatic WB changed video markers");
   if(ov) begin
    if(received>=sent || out!==expected[received%1024]) $fatal(1,"RGB pipeline changed beat%0d got%h expected%h",received,out,expected[received%1024]);
    if(check_board && unity_out[23:0]==24'h80c080) begin
     for(integer lane=0;lane<4;lane=lane+1)
      if(out[lane*24+16+:8]<190 || out[lane*24+16+:8]>193 || out[lane*24+:8]<190 || out[lane*24+:8]>193)
       $fatal(1,"green board not corrected across lanes %h",out);
     if(old_out!=={4{24'h80c080}}) $fatal(1,"old centre rejection did not reproduce green");
     checks=checks+1;
    end
    received=received+1;
   end
   if(ol) lines=lines+1;
  end
 end
 task frame;
 reg [23:0] px;
 begin
  @(negedge clk);sof=1;valid=0;@(negedge clk);sof=0;repeat(8) @(negedge clk);
  for(y=0;y<H;y=y+1) begin
   for(x=0;x<W;x=x+4) begin
    @(negedge clk);valid=1;
    for(k=0;k<4;k=k+1) begin
     px=neutral;
     if(x+k<16 || x+k>=W-16) px=24'h080808;
     if(x+k>=96 && x+k<160 && y>=8 && y<72) px=24'hc03838;
     if(mode==1) px=x<64 ? 24'hffffff:x<128 ? 24'hc03838:x<192 ? 24'hb89648:24'h181818;
     data[k*24+:24]=px;
    end
   end
   @(negedge clk);valid=0;repeat(80) @(negedge clk);
  end
  repeat(350) @(negedge clk);
 end endtask
 initial begin
  repeat(5) @(negedge clk);rst=1;
  mode=1;repeat(3) frame();
  if(reference[26:24]!==0 || dut.in_r_r1!==20'h10000 || dut.in_b_r1!==20'h10000)
   $fatal(1,"startup without usable samples fabricated a WB solution");
  mode=0;
  // SW4 is high from boot: automatic correction still works.
  for(f=0;f<32;f=f+1) frame();
  check_board=1;frame();check_board=0;
  if(checks<1000 || reference[26:24]!==7 || diag[19:9]!==1024)
   $fatal(1,"automatic solution/centre observer not established ref%h diag%h",reference,diag);
  // Drain any final smoothing update, then remove all acceptable neutrals.
  mode=1;repeat(3) frame();held_r=dut.in_r_r1;held_b=dut.in_b_r1;
  freeze=0;invalidate=1;frame();freeze=1;frame();invalidate=0;frame();
  if(dut.in_r_r1!==held_r || dut.in_b_r1!==held_b || reference[24] || !reference[26])
   $fatal(1,"sample loss/SW4/setting event discarded last valid correction");
  // Return a differently illuminated board: reacquire without unlock/reset.
  mode=0;neutral=24'ha0c080;for(f=0;f<32;f=f+1) frame();
  if(dut.in_r_r1<20'h13000 || dut.in_r_r1>20'h13600 || dut.in_b_r1<20'h17c00 || dut.in_b_r1>20'h18400)
   $fatal(1,"automatic reacquisition failed R%h B%h",dut.in_r_r1,dut.in_b_r1);
  if(sent!=received || lines!=74*H) $fatal(1,"lost data sent%0d received%0d lines%0d",sent,received,lines);
  $display("ALL PASS auto reference: green-cast board corrected, centre red/black/clipped rejected, old/unity green reproduced, boot SW4 ignored, last valid gains held, changed illumination reacquired, %0d RGB beats/%0d lines, %0d neutral output checks",received,lines,checks);
  $finish;
 end
 initial begin #20000000;$fatal(1,"auto reference watchdog");end
endmodule
