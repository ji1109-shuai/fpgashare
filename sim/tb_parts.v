`timescale 1ns/1ps
// Capture -> close -> white-board traversal -> single-component features ->
// three-observation confirmation. Display binary deliberately differs from RGB.
module tb_parts #(parameter COLOUR_TEST=0);
  localparam W=384,H=256;
  reg clk=0,rst=0,valid=0,user=0,last=0;
  reg [95:0] bin=0,rgb=0;
  reg mask[0:W*H-1];
  wire [10:0] x0,x1,y0,y1,w,h;
  wire [2:0] typ,color,status;
  wire ok,upd,board;
  wire [127:0] diagnostic;
  reg calibration_ready=1;reg [7:0] calibration_epoch=0;
  integer x,y,k,wait_cycles,frames=0,angle=0,radius=64,offset=0,damage=0;
  reg [23:0] part_rgb=24'h303030,board_rgb=24'he8e8e8;
  reg old_upd;
  integer surface_mode=0;
  function [23:0] surface_pixel(input integer px,py);
    begin
      surface_pixel=part_rgb;
      if(surface_mode==1) begin
        if(px%8==1 || py%8==1) surface_pixel=24'hffffff;
        else if(px%8==2) surface_pixel=24'h202020;
      end else if(surface_mode==2) begin
        // Warm and neutral material cells split evenly: reject ambiguous hue.
        surface_pixel=(px/8)%2 ? 24'hb89648:24'hc03838;
      end else if(surface_mode==3) begin
        surface_pixel=px%8==0 ? part_rgb:24'h202020;
      end else if(surface_mode==4) begin
        // Equal red/black within each cell must not win by ternary priority.
        surface_pixel=px%8<4 ? 24'hc03838:24'h303030;
      end else if(surface_mode==5) begin
        // Reflective black: 5/8 black, 3/8 silver, within EVERY cell.
        surface_pixel=px%8<5 ? 24'h3c332a:24'hb8b8b8;
      end else if(surface_mode==6) begin
        // Same material fraction spread across whole coarse cells.
        surface_pixel=(px/8)%8<5 ? 24'h060606:24'hb8b8b8;
      end else if(surface_mode==7) begin
        // Black/silver at equal strength is intentionally ambiguous.
        surface_pixel=(px/8)%2 ? 24'h303030:24'hb8b8b8;
      end
    end
  endfunction
  img_tire #(.BEATS_PER_LINE(W/4),.LINES_PER_FRAME(H),.FG_IS_WHITE(0),
             .WHITE_BOARD(1),.COLOR_MODE(1),.PARTS_MODE(1),.COLOR_CALIBRATION(COLOUR_TEST==2)) dut(
    .I_clk(clk),.I_rst_n(rst),.I_tdata(bin),.I_rgb(rgb),.I_tvalid(valid),
    .I_tuser(user),.I_tlast(last),.I_roi_valid(1'b0),.I_roi_x0(11'd0),.I_roi_x1(11'd383),
    .I_roi_y0(11'd0),.I_roi_y1(11'd255),.O_x0(x0),.O_x1(x1),.O_y0(y0),.O_y1(y1),
    .O_w(w),.O_h(h),.O_type(typ),.O_color(color),.O_valid(ok),.O_upd(upd),.O_status(status),
    .O_board_valid(board),.I_color_reference(8'd232),.I_color_epoch(calibration_epoch),
    .I_color_ready(calibration_ready),.O_color_diag(diagnostic),.I_query_bank(1'b0),.I_query_row(8'd0));
  always #5 clk=~clk;
  always @(posedge clk) if(rst && dut.tail>W/8*(H/8)) $fatal(1,"parts queue overflow");

  function automatic part_pixel(input integer px,py,pk);
    real ux,uy,a,t,qx,qy;
    integer dx,dy,j;
    begin
      dx=px-W/2-offset;dy=py-H/2-offset;
      a=angle*3.141592653589793/180;
      ux=dx*$cos(a)+dy*$sin(a);uy=-dx*$sin(a)+dy*$cos(a);
      case(pk)
        0:part_pixel=0;
        1:part_pixel=(dx*dx+dy*dy<=radius*radius && dx*dx+dy*dy>=radius*radius*0.36*0.36);
        2:begin
          part_pixel=dx*dx+dy*dy>=radius*radius*0.5*0.5;
          for(j=0;j<6;j=j+1) begin
            t=(60*j+30)*3.141592653589793/180;
            if(ux*$cos(t)+uy*$sin(t)>radius*$cos(3.141592653589793/6)) part_pixel=0;
          end
        end
        3:part_pixel=((ux>=-radius && ux<=radius && uy>=-radius*0.23 && uy<=radius*0.23) ||
                      (ux>=radius*0.65 && ux<=radius*1.12 && uy>=-radius*0.50 && uy<=radius*0.50));
        4:part_pixel=(ux>=-radius && ux<=radius && uy>=-radius*0.23 && uy<=radius*0.23);
        5:part_pixel=dx*dx+dy*dy<=radius*radius;
        6:part_pixel=(ux>=-radius*0.8 && ux<=radius*0.8 && uy>=-radius*0.8 && uy<=radius*0.8 &&
                      dx*dx+dy*dy>radius*radius*0.25);
        7,8:begin
          qx=(ux<0 ? -ux:ux)-radius*0.64;if(qx<0) qx=0;
          qy=(uy<0 ? -uy:uy)-radius*0.64;if(qy<0) qy=0;
          part_pixel=qx*qx+qy*qy<=radius*radius*0.16*0.16 &&
            (pk==8 || dx*dx+dy*dy>=radius*radius*0.4*0.4);
        end
        9:part_pixel=(ux>=-radius && ux<=radius && uy>=-radius*0.5 && uy<=radius*0.5 &&
                      dx*dx+dy*dy>radius*radius*0.25);
        default:part_pixel=0;
      endcase
      if(damage && ((px%23==1 && py%17<3) || (dx==radius/2 && dy>0))) part_pixel=0;
    end
  endfunction
  task make_image(input integer pk);
    begin
      for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+1) mask[y*W+x]=part_pixel(x,y,pk);
    end
  endtask
  task send_frame(input integer corrupt);
    begin
      for(y=0;y<H;y=y+1) begin
        for(x=0;x<W;x=x+4) begin
          @(negedge clk);valid=1;user=(x==0 && y==0);last=(x==W-4 && !(corrupt && y==H/2));
          for(k=0;k<4;k=k+1) begin
            rgb[k*24+:24]=(x+k<16 || x+k>=W-16 || y<16 || y>=H-16) ?
              24'h080808 : mask[y*W+x+k] ? surface_pixel(x+k,y) : board_rgb;
            bin[k*24+:24]=0;
          end
        end
        @(negedge clk);valid=0;user=0;last=0;repeat(2) @(negedge clk);
      end
    end
  endtask
  task check(input integer pk,expected,corrupt);
    begin
      make_image(pk);old_upd=upd;send_frame(corrupt);wait_cycles=0;
      while(upd===old_upd && wait_cycles<300000) begin @(negedge clk);wait_cycles=wait_cycles+1;end
      if(upd===old_upd) $fatal(1,"parts timeout state%0d scan%0d phase%0d",dut.state,dut.scan,dut.phase);
      if(typ!==expected) $fatal(1,"kind%0d angle%0d radius%0d offset%0d type%0d expected%0d status%0d area%0d hole%0d box%0d,%0d compact%0d holeok%0d round%0d hex%0d circle%0d head%0d six%0d/%0d",
        pk,angle,radius,offset,typ,expected,status,dut.ba,dut.ha,w,h,dut.parts_compact,dut.parts_hole,dut.parts_round,dut.parts_hex,dut.parts_circle,dut.parts_head,dut.g_parts_shape.shape.six_num,dut.g_parts_shape.shape.product);
      if(corrupt && status!==5) $fatal(1,"parts malformed stream not rejected");
      if(expected>=1 && expected<=4) begin
        if(!board || !ok || x0<16 || x1>=W-16 || y0<16 || y1>=H-16) $fatal(1,"external black background polluted target");
        if((w<80 && h<80) || w<16 || h<16) $fatal(1,"partial target bounds");
      end
      frames=frames+1;
      $display("PASS parts kind%0d angle%0d r%0d phase%0d type%0d status%0d cycles%0d",pk,angle,radius,offset,typ,status,wait_cycles);
      repeat(8) @(negedge clk);
    end
  endtask
  task confirm(input integer pk,expected);
    begin check(pk,7,0);check(pk,7,0);check(pk,expected,0);end
  endtask
  task check_colour(input integer pk,expected_shape,expected_colour);
    begin
      check(pk,expected_shape,0);
      if(color!==expected_colour) $fatal(1,"colour surface%0d rgb%h got%0d expected%0d votes%0d/%0d/%0d total%0d raw%0d streak%0d",
        surface_mode,part_rgb,color,expected_colour,dut.bred,dut.bgreen,dut.bblue,dut.parts_vote_total,dut.parts_color_choice,dut.color_streak);
    end
  endtask
  initial begin
    repeat(5) @(negedge clk);rst=1;
    if(COLOUR_TEST==2) begin
      calibration_ready=0;part_rgb=24'hc03838;
      check_colour(1,7,0);check_colour(1,7,0);check_colour(1,2,0);
      if(diagnostic[14:11]!==1) $fatal(1,"unlocked colour not inhibited");
      calibration_ready=1;calibration_epoch=1;
      check_colour(1,2,0);check_colour(1,2,1);
      part_rgb=24'h300c0c;check_colour(1,2,1);
      if(diagnostic[127:104]!==24'h300c0c || !diagnostic[19]) $fatal(1,"target RGB diagnostic not aligned %h",diagnostic);
      part_rgb=24'h383018;check_colour(1,2,0);check_colour(1,2,6);
      part_rgb=24'h606060;check_colour(1,2,0);check_colour(1,2,5);
      // Reference232: black ends at72, silver begins at87; test the gap.
      part_rgb=24'h4c4c4c;check_colour(1,2,0);
      part_rgb=24'h303030;check_colour(1,2,0);check_colour(1,2,4);
      part_rgb=24'h000000;check_colour(1,2,4);
      part_rgb=24'hfa2020;check_colour(1,2,0);
      if(diagnostic[14:11]!==7) $fatal(1,"clipped diagnostic %h",diagnostic);
      part_rgb=24'hc03838;surface_mode=1;check_colour(1,2,0);check_colour(1,2,1);
      if(!diagnostic[18]) $fatal(1,"thin/fragmented fallback missing");
      surface_mode=2;check_colour(1,2,0);
      if(diagnostic[14:11]!==4) $fatal(1,"mixed diagnostic missing");
      surface_mode=0;part_rgb=24'hb89648;check_colour(1,2,0);check_colour(1,2,6);
      make_image(1);old_upd=upd;send_frame(0);
      calibration_epoch=2;calibration_ready=0;
      repeat(10) @(negedge clk);
      if(color!==0) $fatal(1,"old colour survived calibration epoch");
      wait_cycles=0;
      while(upd===old_upd && wait_cycles<300000) begin @(negedge clk);wait_cycles=wait_cycles+1;end
      if(upd===old_upd || diagnostic[14:11]!==1) $fatal(1,"analysis published stale calibration");
      calibration_ready=1;calibration_epoch=3;
      check_colour(1,2,0);check_colour(1,2,6);
      check_colour(0,0,0);
      if(diagnostic[14:11]!==2) $fatal(1,"empty diagnostic missing");
      $display("ALL PASS colour stability parts: calibration gate/epoch, dim red/brass, neutral dead band, zero-black/clipped/mixed, inner fallback, target RGB, independent shape");
    end else if(COLOUR_TEST) begin
      // Shape confirmation and colour confirmation run independently.
      part_rgb=24'hb8b8b8;
      check_colour(1,7,0);check_colour(1,7,5);check_colour(1,2,5);
      surface_mode=1;check_colour(1,2,5);
      part_rgb=24'hb89648;
      check_colour(1,2,0);check_colour(1,2,6);
      surface_mode=0;part_rgb=24'h706030;check_colour(1,2,6);
      part_rgb=24'hc03838;surface_mode=1;
      check_colour(1,2,0);check_colour(1,2,1);
      surface_mode=0;part_rgb=24'h802020;check_colour(1,2,1);
      // Black confirms independently; unsupported green/blue stay unknown.
      part_rgb=24'h303030;check_colour(1,2,0);
      check_colour(1,2,4);
      part_rgb=24'h28a038;check_colour(1,2,0);
      part_rgb=24'h3030c0;check_colour(1,2,0);
      surface_mode=2;check_colour(1,2,0);
      surface_mode=3;part_rgb=24'hb8b8b8;check_colour(1,2,0);check_colour(1,2,4);
      surface_mode=0;part_rgb=24'hc03838;
      check_colour(2,7,0);check_colour(2,7,1);check_colour(2,3,1);
      part_rgb=24'hb89648;
      check_colour(3,7,0);check_colour(3,7,6);check_colour(3,1,6);
      part_rgb=24'h303030;
      check_colour(7,7,0);check_colour(7,7,4);check_colour(7,4,4);
      surface_mode=1;check_colour(7,4,4);
      surface_mode=0;part_rgb=24'hb8b8b8;
      check_colour(7,4,0);check_colour(7,4,5);
      part_rgb=24'hc03838;check_colour(7,4,0);check_colour(7,4,1);
      part_rgb=24'hb89648;check_colour(7,4,0);check_colour(7,4,6);
      surface_mode=4;check_colour(7,4,0);check_colour(7,4,0);
      surface_mode=0;part_rgb=24'hb45418;check_colour(7,4,0);check_colour(7,4,6);
      part_rgb=24'hc8b098;check_colour(7,4,6);
      part_rgb=24'h3c332a;check_colour(7,4,0);check_colour(7,4,4);
      surface_mode=5;check_colour(7,4,4);check_colour(7,4,4);
      surface_mode=6;check_colour(7,4,4);check_colour(7,4,4);
      surface_mode=7;check_colour(7,4,0);check_colour(7,4,0);
      surface_mode=0;part_rgb=24'h000000;check_colour(7,4,0);check_colour(7,4,4);
      check_colour(0,0,0);
      $display("ALL PASS parts colours frames%0d: silver/brass/red/black, highlights/shadows, hue changes, unsupported/mixed rejection, all 4 shapes, independent confirmation and removal",frames);
    end else begin
    check(0,0,0);
    confirm(1,2);
    damage=1;part_rgb=24'hb89648;check(1,2,0);
    damage=0;part_rgb=24'hb8b8b8;offset=3;radius=80;check(1,2,0);
    radius=64;offset=0;
    confirm(2,3);
    for(angle=5;angle<60;angle=angle+5) begin offset=angle%8;check(2,3,0);end
    angle=0;offset=0;damage=1;part_rgb=24'hc03838;check(2,3,0);
    damage=0;part_rgb=24'h303030;
    confirm(3,1);
    for(angle=15;angle<180;angle=angle+15) begin offset=angle%8;check(3,1,0);end
    angle=0;offset=0;
    check(4,7,0);check(4,7,0);check(4,7,0);
    check(5,7,0);
    confirm(7,4);
    for(angle=5;angle<90;angle=angle+5) begin offset=angle%8;check(7,4,0);end
    angle=0;offset=0;check(6,4,0);
    radius=80;angle=45;offset=3;damage=1;check(7,4,0);
    // Keep >2 coarse cells of white margin after rotating large parts;
    // otherwise closing joins the artificial outside-black border.
    damage=0;radius=96;angle=0;offset=-3;check(7,4,0);
    radius=64;angle=0;offset=0;
    check(8,7,0);check(9,7,0);
    check(0,0,0);
    check(2,0,1);confirm(2,3);
    $display("ALL PASS parts frames%0d",frames);$finish;
    end
    $finish;
  end
  initial begin #1000000000;$fatal(1,"parts watchdog");end
endmodule
module tb_parts_colours;
  tb_parts #(.COLOUR_TEST(1)) test();
endmodule

module tb_parts_colour_stability;
  tb_parts #(.COLOUR_TEST(2)) test();
endmodule
