`timescale 1ns/1ps
// Independent HSV-generated swatches, including former warm-red failures.
module tb_parts_color_hsv;
 reg clk=0,rst=0;
 reg [23:0] rgb=0;
 reg [7:0] reference=224;
 wire [2:0] colour;
 integer cases=0,h,s,v,r,g,b,i;
 real c,z,m,hp;
 always #5 clk=~clk;
 img_parts_color dut(clk,rst,rgb,reference,colour);
 task check(input [23:0] px,input [7:0] ref_value,input [2:0] expected);
 begin
  @(negedge clk);rgb=px;reference=ref_value;
  repeat(2) @(negedge clk);
  if(colour!==expected) $fatal(1,"HSV classifier RGB%h ref%0d got%0d expected%0d",px,ref_value,colour,expected);
  cases=cases+1;
 end endtask
 // HSV -> RGB uses real arithmetic, independently of RTL comparisons.
 task swatch(input integer hue,saturation,value,input [2:0] expected);
 begin
  c=value*saturation/100.0;hp=hue/60.0;
  z=c*(1.0-((hp-2.0*$floor(hp/2.0))>1.0 ? (hp-2.0*$floor(hp/2.0))-1.0:1.0-(hp-2.0*$floor(hp/2.0))));
  m=value-c;
  if(hue<60) begin r=$rtoi(c+m+0.5);g=$rtoi(z+m+0.5);b=$rtoi(m+0.5);end
  else if(hue<120) begin r=$rtoi(z+m+0.5);g=$rtoi(c+m+0.5);b=$rtoi(m+0.5);end
  else begin r=$rtoi(c+m+0.5);g=$rtoi(m+0.5);b=$rtoi(z+m+0.5);end // 300..360 red wrap
  check({8'(r),8'(g),8'(b)},224,expected);
 end endtask
 initial begin
  repeat(4) @(negedge clk);rst=1;
  check(24'hb45418,224,6); // H23: old R<=2G rule incorrectly labelled RED
  check(24'hc8b098,224,6); // low-saturation brass with neutral reflection
  check(24'h3c332a,224,4); // dark, mildly warm black
  check(24'h060606,224,4);check(24'h000000,224,4);
  for(v=90;v<=240;v=v+30) begin
   for(s=35;s<=95;s=s+15) begin
    for(h=0;h<=12;h=h+3) swatch(h,s,v,1);
    for(h=348;h<=357;h=h+3) swatch(h,s,v,1);
    for(h=24;h<=60;h=h+6) swatch(h,s,v,6);
   end
  end
  // Hue boundaries retain a small reject interval; pink/magenta/green/blue
  // and clipped chromatic pixels must not become brass/red by priority.
  swatch(17,80,200,0);swatch(70,80,200,0);swatch(320,80,200,0);
  check(24'h28a038,224,0);check(24'h3030c0,224,0);
  check(24'hfa3030,224,0);check(24'hffffff,224,0);
  check(24'h484848,224,0); // keep black/silver separation interval
  for(i=0;i<=68;i=i+4) check({8'(i),8'(i),8'(i)},224,4);
  for(i=84;i<250;i=i+8) check({8'(i),8'(i),8'(i)},224,5);
  check(24'h202020,128,4);check(24'h404040,128,5);
  // Exactly two clocks, consecutive pixels; no validity assumptions.
  @(negedge clk);rgb=24'hb45418;reference=224;
  @(negedge clk);rgb=24'h060606;
  @(negedge clk);if(colour!==6) $fatal(1,"brass latency");rgb=24'hc03838;
  @(negedge clk);if(colour!==4) $fatal(1,"black latency");rgb=24'hb8b8b8;
  @(negedge clk);if(colour!==1) $fatal(1,"red latency");
  @(negedge clk);if(colour!==5) $fatal(1,"silver latency");
  $display("ALL PASS HSV colour sectors: %0d independent swatches, dim/zero black, neutral silver, rejection and two-clock stream",cases);
  $finish;
 end
endmodule
