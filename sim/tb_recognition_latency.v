`timescale 1ns/1ps
module tb_recognition_latency;
 reg clk=0,rst=0,start=0,finish=0,abort=0;
 wire [15:0] bcd;wire valid,upd;
 reg old_upd;
 integer cycles;
 recognition_latency_meter #(.TICK_CYCLES(3)) dut(
  .I_clk(clk),.I_rst_n(rst),.I_start(start),.I_finish(finish),.I_abort(abort),
  .O_bcd(bcd),.O_valid(valid),.O_upd(upd));
 always #5 clk=~clk;
 task begin_batch;
  begin @(negedge clk);start=1;@(negedge clk);start=0;old_upd=upd;end
 endtask
 task measure(input integer clocks,input [15:0] expected);
  begin
   begin_batch();repeat(clocks-1) @(negedge clk);finish=1;
   @(negedge clk);finish=0;
   if(!valid || upd==old_upd || bcd!==expected) $fatal(1,"latency clocks%0d got%h expected%h valid%0d",clocks,bcd,expected,valid);
  end
 endtask
 initial begin
  repeat(3) @(negedge clk);rst=1;
  if(valid) $fatal(1,"reset must be invalid");
  finish=1;repeat(2) @(negedge clk);finish=0;
  if(upd || valid) $fatal(1,"unsolicited finish");
  measure(1,16'h0000);measure(2,16'h0000);measure(3,16'h0001);
  measure(29,16'h0009);measure(30,16'h0010);measure(300,16'h0100);
  measure(3000,16'h1000);measure(29999,16'h9999);
  begin_batch();repeat(10) @(negedge clk);abort=1;
  @(negedge clk);abort=0;if(valid || upd==old_upd) $fatal(1,"abort retained a measurement");
  old_upd=upd;finish=1;repeat(3) @(negedge clk);finish=0;
  if(upd!=old_upd) $fatal(1,"late finish after abort");
  measure(15,16'h0005); // recovery
  begin_batch();repeat(30000) @(negedge clk);
  if(valid || upd==old_upd) $fatal(1,"counter wrapped instead of timing out");
  measure(30,16'h0010);
  // Expire exactly on finish: valid must be false rather than wrapping to zero.
  begin_batch();repeat(29999) @(negedge clk);finish=1;@(negedge clk);finish=0;
  if(valid || upd==old_upd) $fatal(1,"finish overflow");
  measure(300,16'h0100);
  $display("ALL PASS latency timer: boundaries, decimal carry, idle finish, abort, recovery, timeout, saturation");$finish;
 end
 initial begin #2000000;$fatal(1,"latency timer timeout");end
endmodule
