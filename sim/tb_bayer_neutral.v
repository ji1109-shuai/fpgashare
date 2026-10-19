`timescale 1ns/1ps
// Real production BGGR interpolation; no RGB-only demosaic replacement.
// Uniform colour Bayer patches must preserve all four reconstructed lanes.
module tb_bayer_neutral;
 reg clk=0,rst=0,valid=0,user=0,last=0,parity=0;
 reg [95:0] above=0,centre=0,below=0;
 wire [127:0] out;wire ov;
 reg [23:0] expected[0:1023];
 integer sent=0,received=0,n,c,r,g,b;
 reg [7:0] current_value,adjacent_value;
 always #5 clk=~clk;
 bilinear_interpolation #(.BAYER_MODE("BGGR")) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tvalid(valid),.O_tready(1'b1),
 .bayer_ypos(parity),.matrix_last_line(above),.matrix_cur_line(centre),.matrix_next_line(below),
 .O_tdata(out),.O_tvalid(ov));
 always @(posedge clk) begin
  #1;
  if(rst && ov) begin
   for(integer lane=0;lane<4;lane=lane+1)
    if(out[lane*32+:32]!=={8'd0,expected[received]})
     $fatal(1,"BGGR lane%0d case%0d got%h expected%h",lane,received,out[lane*32+:32],expected[received]);
   received=received+1;
  end
 end
 initial begin
  repeat(4) @(negedge clk);rst=1;
  for(n=0;n<512;n=n+1) begin
   @(negedge clk);valid=1;parity=n%2;
   r=(n*31)%256;g=(n*73)%256;b=(n*19)%256;
   if(n<256) begin r=n;g=n;b=n;end
   expected[sent]={8'(r),8'(g),8'(b)};sent=sent+1;
   for(c=0;c<6;c=c+1) begin
    current_value=parity ? (c%2 ? g:r):(c%2 ? b:g);
    adjacent_value=parity ? (c%2 ? b:g):(c%2 ? g:r);
    centre[71-c*8-:8]=current_value;
    above[71-c*8-:8]=adjacent_value;below[71-c*8-:8]=adjacent_value;
   end
   if(n%7==0) begin @(negedge clk);valid=0;parity=~parity;end
  end
  @(negedge clk);valid=0;repeat(10) @(negedge clk);
  if(received!=sent) $fatal(1,"BGGR lost pixels");
  $display("ALL PASS production BGGR interpolation: 256 neutral levels, 256 colour patches, both row parities, bubbles, four lanes; %0d reconstructed pixels",received*4);
  $finish;
 end
endmodule
