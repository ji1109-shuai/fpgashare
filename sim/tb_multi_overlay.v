`timescale 1ns/1ps
// Independent output-pixel oracle: four different labels, original logo,
// compact controls, removal, candidates and atomic camera/display publication.
module tb_multi_overlay #(parameter WB_PROBE=0);
 localparam W=960,H=384;
 reg clk=0,rst=0,de=0,sof=0,eol=0,toggle=0;
 reg [223:0] targets=0,expected_targets=0;
 reg [23:0] expected_pixels[0:W*H-1];
 reg [9:0] logo_index[0:16383];reg [24:0] logo_palette[0:1023];
 wire ode;wire [23:0] out;
 reg [7:0] ch;reg [3:0] row,col;wire [15:0] bits;
 integer x,y,j,ci,lx,ly,x0,x1,y0,y1,written=0,seen=0,frames=0,chosen;
 reg label_hit,box_hit;reg [55:0] item;reg [103:0] word_bits;
 reg [127:0] control_word;
 reg [127:0] probe={24'h80c080,20'h18000,20'h18000,11'd1024,11'd0,11'd0,11'd0,11'd1024,4'd0,5'd0};
 reg [127:0] expected_probe;
 reg [23:0] expected;reg [24:0] logo;
 osd_char_lib reference_font(.I_char(ch),.I_row(row),.O_row_bits(bits));
 hdmi_mixer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_ONLY(1),.PARTS_MODE(1),.MULTI_TARGETS(1),
 .SHOW_LOGO(1),.DISPLAY_MODES(1),.CAMERA_CONTROL(1),.COLOR_DIAGNOSTICS(1),.COMPACT_DIAGNOSTICS(1),.WB_DIAGNOSTICS(WB_PROBE)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_video_vsync(1'b0),.I_video_hsync(1'b0),
 .I_video_de(de),.I_video_user(sof),.I_video_last(eol),.I_video_rd_data(24'h556677),
 .I_display_mode(3'd0),.I_debug_status(4'd0),.I_bbox_upd(toggle),.I_bbox_valid(1'b0),.I_bbox_moving(1'b1),
 .I_targets(targets),.I_target_count(3'd4),.I_target_overflow(1'b0),
 .I_camera_status(29'h02244112),.I_camera_status_upd(toggle),
 .I_color_reference(32'h07e8e8e8),.I_color_reference_upd(toggle),.I_color_diag(128'hffff),
 .I_wb_diag(probe),.I_wb_diag_upd(toggle),
 .I_meas_upd(1'b0),.I_meas_valid(1'b0),.I_thresh_upd(1'b0),.I_roi_upd(1'b0),.I_roi_valid(1'b0),
 .O_hdmi_de(ode),.O_hdmi_data(out));
 always #5 clk=~clk;
 always @(posedge clk) begin
  #1;
  if(rst && ode) begin
   if(seen>=written || out!==expected_pixels[seen])
    $fatal(1,"multi overlay frame%0d pixel%0d,%0d got%h expected%h",frames,seen%W,seen/W,out,expected_pixels[seen]);
   seen=seen+1;
  end
 end
 function [55:0] packet(input integer valid,shape,colour,x0,x1,y0,y1);
  begin packet={valid[0],shape[2:0],colour[2:0],5'd0,x0[10:0],x1[10:0],y0[10:0],y1[10:0]};end
 endfunction
 task frame;
 begin
  toggle=~toggle;repeat(12) @(negedge clk);expected_targets=targets;expected_probe=probe;written=0;seen=0;
  for(y=0;y<H;y=y+1) begin
   for(x=0;x<W;x=x+1) begin
    @(negedge clk);de=1;sof=x==0 && y==0;eol=x==W-1;
    expected=24'h556677;ch=32;row=0;col=0;label_hit=0;box_hit=0;chosen=-1;
    for(j=0;j<4;j=j+1) begin
     item=expected_targets[j*56+:56];x0=item[43:33];x1=item[32:22];y0=item[21:11];y1=item[10:0];
     lx=x0+216<=W ? x0:W-216;ly=y0>=22 ? y0-22:y1+22<H ? y1+2:2;
     if(item[55] && item[54:52]>=1 && item[54:52]<=4 && x0<=x1 && y0<=y1 && x1<W && y1<H) begin
      if(x>=x0 && x<=x1 && y>=y0 && y<=y1 && (x-x0<2 || x1-x<2 || y-y0<2 || y1-y<2)) box_hit=1;
      if(chosen<0 && x>=lx && x<lx+216 && y>=ly && y<ly+20) chosen=j;
     end
    end
    if(box_hit) expected=24'hff00ff;
    if(chosen>=0) begin
     label_hit=1;item=expected_targets[chosen*56+:56];x0=item[43:33];y0=item[21:11];y1=item[10:0];
     lx=x0+216<=W ? x0:W-216;ly=y0>=22 ? y0-22:y1+22<H ? y1+2:2;
     expected=box_hit ? 24'hff00ff:24'h202020;
     case(item[54:52])
      1:word_bits="BRASS  SCREW ";2:word_bits="SILVER WASHER";3:word_bits="RED    NUT   ";4:word_bits="BLACK  SQNUT ";
     endcase
     if(x>=lx+4 && x<lx+212 && y>=ly+2 && y<ly+18) begin
      ci=(x-lx-4)/16;ch=word_bits[103-ci*8-:8];col=(x-lx-4)%16;row=y-ly-2;
     end
    end
    if(WB_PROBE && x>=176 && x<432 && y>=104 && y<220 && (y-104)%20<16) begin
     case((y-104)/20)
      0:control_word=expected_probe[127:104]==24'h80c080 ? "RAW:80C080      ":"RAW:80FF80      ";
      1:control_word=expected_probe[127:104]==24'h80c080 ? "R:1800 B:1800   ":"R:1000 B:1000   ";
      2:control_word=expected_probe[127:104]==24'h80c080 ? "OK:0400 N:0400  ":"OK:0000 N:0400  ";
      3:control_word=expected_probe[127:104]==24'h80c080 ? "HI:0000 LO:0000 ":"HI:0400 LO:0000 ";
      4:control_word="CAST:0000       ";
      default:control_word=expected_probe[127:104]==24'h80c080 ? "SMP:OK          ":"SMP:CLIP        ";
     endcase
     ci=(x-176)/16;ch=control_word[127-ci*8-:8];row=(y-104)%20;col=(x-176)%16;
     expected=box_hit ? 24'hff00ff:24'h202020;
    end else if(x>=176 && x<432 && y>=84 && y<100) begin
     control_word="WB:LOCK REF:OK  ";ci=(x-176)/16;ch=control_word[127-ci*8-:8];row=y-84;col=(x-176)%16;expected=24'h202020;
    end else if(x>=176 && x<304 && y>=40 && y<56) begin
     control_word="EXP:2244        ";ci=(x-176)/16;ch=control_word[127-ci*8-:8];row=y-40;col=(x-176)%16;expected=24'h202020;
    end else if(x>=176 && x<304 && y>=60 && y<76) begin
     control_word="GAIN:112        ";ci=(x-176)/16;ch=control_word[127-ci*8-:8];row=y-60;col=(x-176)%16;expected=24'h202020;
    end else if(x>=176 && x<256 && y>=16 && y<32) begin
     control_word="RGB             ";ci=(x-176)/16;ch=control_word[127-ci*8-:8];row=y-16;col=(x-176)%16;expected=24'h202020;
    end
    #1;
    if(bits[15-col]) expected=(x>=176 && x<304 && y>=40 && y<56) ? 24'hfff200:24'hffffff;
    if(x>=7 && x<153 && y>=34 && y<128) begin
     logo=logo_palette[logo_index[(y-34)*146+x-7]];
     if(logo[24]) expected=logo[23:0];
    end
    expected_pixels[written]=expected;written=written+1;
    if(x==0 && y==170) begin
     targets=0;
     if(WB_PROBE) probe={24'h80ff80,20'h10000,20'h10000,11'd0,11'd1024,11'd0,11'd0,11'd1024,4'd2,5'd0};
     toggle=~toggle;
    end
   end
   @(negedge clk);de=0;sof=0;eol=0;repeat(2) @(negedge clk);
  end
  repeat(12) @(negedge clk);
  if(seen!=W*H) $fatal(1,"multi raster missing pixels");
  frames=frames+1;$display("PASS multi overlay frame%0d pixels%0d",frames,seen);
 end endtask
 initial begin
  $readmemh("logo_idx.hex",logo_index);$readmemh("logo_pal.hex",logo_palette);
  repeat(5) @(negedge clk);rst=1;
  targets={packet(1,4,4,752,852,200,300),packet(1,3,1,512,612,200,300),
           packet(1,1,6,272,372,200,300),packet(1,2,5,32,132,200,300)};
  frame();frame(); // removal was queued mid-frame; must appear next frame.
  targets={packet(1,7,4,752,852,200,300),packet(1,3,1,512,612,200,500),
           packet(0,1,6,272,372,200,300),packet(1,2,5,32,132,200,300)};
  frame();
  $display("ALL PASS multi overlay: four independent labels, logo pixels, EXP/GAIN/WB, probe%0d frame-held CDC, removal, candidate/invalid bounds hidden",WB_PROBE);$finish;
 end
 initial begin #50000000;$fatal(1,"multi overlay watchdog");end
endmodule
