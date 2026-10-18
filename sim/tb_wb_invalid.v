`timescale 1ns/1ps
// Reproduce: calibrated attenuation -> empty/clipped reference -> invalid lock
// must not keep attenuating red and blue in a subsequently neutral scene.
module tb_wb_invalid;
 reg clk=0,rst=0,valid=0,sof=0,freeze=0,invalidate=0;
 reg [95:0] rgb=0;
 wire [95:0] out;wire ov;wire [31:0] reference;
 integer x,y,f,checks=0;
 reg [19:0] held_r,held_b;
 reg [31:0] held_reference;
 reg audit=0,audit_balanced=0;reg [23:0] expected;
 integer lane,channel,sample_value;
 always #5 clk=~clk;
 awb #(.IMG_WIDTH(256),.IMG_HEIGHT(16),.REFERENCE_ONLY(1),.REFERENCE_WINDOW(64),.MIN_REFERENCE_SAMPLES(32)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(valid),
 .I_gain_freeze(freeze),.I_cal_reset(invalidate),.O_reference(reference),.O_tdata(out),.O_tvalid(ov),.O_tready(1'b1));
 always @(posedge clk) if(rst && ov && audit) begin
  if(out!=={4{expected}}) $fatal(1,"invalid calibration applied old gains output%h expected%h gainR%h gainB%h",out,{4{expected}},dut.in_r_r1,dut.in_b_r1);
  checks=checks+1;
 end
 always @(posedge clk) if(rst && ov && audit_balanced) begin
  for(lane=0;lane<4;lane=lane+1) for(channel=0;channel<3;channel=channel+1) begin
   sample_value=out[lane*24+channel*8+:8];
   if(sample_value<190 || sample_value>193) $fatal(1,"green reference not neutralized output%h",out);
  end
 end
 task frame(input [23:0] px);
 begin
  @(negedge clk);sof=1;valid=0;
  @(negedge clk);sof=0;repeat(8) @(negedge clk);
  for(y=0;y<16;y=y+1) begin
   for(x=0;x<64;x=x+1) begin @(negedge clk);valid=1;rgb={4{px}};end
   @(negedge clk);valid=0;repeat(4) @(negedge clk);
  end
  repeat(300) @(negedge clk);
 end endtask
 task calibrate;
 begin
  freeze=0;repeat(4) @(negedge clk);
  for(f=0;f<40;f=f+1) frame(24'hc080c0);
  if(reference[25:24]!==3 || dut.in_r_r1>=20'h0b000 || dut.in_b_r1>=20'h0b000)
   $fatal(1,"test did not establish non-unity calibration");
 end endtask
 task raw_neutral;
 begin
  // Allow a complete frame boundary and the unchanged pixel latency to drain.
  frame(24'h808080);expected=24'h808080;audit=1;frame(expected);audit=0;
  if(dut.in_r_r1!==20'h10000 || dut.in_b_r1!==20'h10000) $fatal(1,"invalid reference did not bypass WB");
 end endtask
 initial begin
  repeat(4) @(negedge clk);rst=1;
  calibrate();
  frame(24'hffffff);frame(24'hffffff);
  if(reference[25:24]!==0) $fatal(1,"clipped reference accepted");
  freeze=1;repeat(4) @(negedge clk);
  if(!reference[26] || reference[25:24]!==0) $fatal(1,"invalid lock status");
  raw_neutral();
  $display("PASS rejected reference then lock: neutral RGB remains neutral");
  calibrate();freeze=1;repeat(4) @(negedge clk);
  held_reference=reference;held_r=dut.in_r_r1;held_b=dut.in_b_r1;
  frame(24'h40c040);frame(24'h40c040);
  if(reference!==held_reference || dut.in_r_r1!==held_r || dut.in_b_r1!==held_b) $fatal(1,"valid lock changed with green object");
  invalidate=1;@(negedge clk);invalidate=0;repeat(4) @(negedge clk);
  if(reference[25:24]!==0 || !reference[26]) $fatal(1,"settings invalidation status");
  raw_neutral();
  $display("PASS setting change while locked: old gains removed at next frame");
  calibrate();freeze=1;repeat(4) @(negedge clk);frame(24'h808080);
  freeze=0;repeat(4) @(negedge clk);
  if(reference[25:24]!==0) $fatal(1,"unlock reference not cleared");
  // Exclude all new samples; obsolete divider results must not rearm validity.
  frame(24'hffffff);frame(24'hffffff);
  if(reference[25:24]!==0) $fatal(1,"obsolete result rearmed reference");
  freeze=1;repeat(4) @(negedge clk);raw_neutral();
  // Actual correction, not a forced gain: a green-cast neutral card must
  // converge to neutral pixels in every output lane before a valid lock.
  freeze=0;repeat(4) @(negedge clk);
  for(f=0;f<40;f=f+1) frame(24'h80c080);
  if(reference[25:24]!==3) $fatal(1,"green-cast card did not converge");
  freeze=1;repeat(4) @(negedge clk);audit_balanced=1;frame(24'h80c080);audit_balanced=0;
  $display("PASS green-cast neutral reference: corrected RGB is neutral in all four lanes");
  // Invalidate during the serial division. No result from that job may
  // publish a ready reference after the setting has changed.
  freeze=0;repeat(4) @(negedge clk);frame(24'h80c080);
  @(negedge clk);sof=1;@(negedge clk);sof=0;repeat(12) @(negedge clk);
  if(!dut.div_busy) $fatal(1,"test missed active divider");
  invalidate=1;@(negedge clk);invalidate=0;repeat(300) @(negedge clk);
  if(reference[25:24]!==0 || dut.div_busy || dut.done_v) $fatal(1,"obsolete divider survived invalidation");
  freeze=1;repeat(4) @(negedge clk);raw_neutral();
  $display("ALL PASS invalid WB: rejected/invalid locks, setting changes, unlock abort, valid-lock hold, unity fallback RGB and frame timing; audited%0d",checks);$finish;
 end
 initial begin #20000000;$fatal(1,"WB invalid watchdog");end
endmodule
