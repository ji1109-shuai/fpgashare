`timescale 1ns/1ps
module tb_parts_multi #(parameter CALIBRATION=1,LATENCY_TEST=0);
 localparam W=640,H=448;
 reg clk=0,rst=0,valid=0,user=0,last=0;
 reg [95:0] bin=0,rgb=0;
 wire [223:0] targets;wire [2:0] count;wire overflow,upd;
 wire [15:0] latency_bcd;wire latency_valid,latency_upd;
 integer monitor_cycle=0,start_cycle=-1,latency_checks=0,skipped_starts=0,expected_ticks;
 reg previous_upd=0,previous_latency_upd=0;
 integer owner[0:W*H-1];integer kind[0:4],ox[0:4],oy[0:4];
 reg [23:0] colours[0:4];
 integer x,y,k,j,cx,cy,angle=0,radius=64,damage=0,cycles,frames=0,active=4;
 integer expected_shape[0:4],expected_colour[0:4],hits[0:4],n,centre;
 reg change_context_mid_batch=0;
 reg old_upd,no_board=0;reg ready=CALIBRATION;reg [7:0] epoch=0;
 reg [55:0] item;
 img_tire #(.BEATS_PER_LINE(W/4),.LINES_PER_FRAME(H),.FG_IS_WHITE(0),.WHITE_BOARD(1),
 .COLOR_MODE(1),.PARTS_MODE(1),.COLOR_CALIBRATION(CALIBRATION),.MULTI_TARGETS(1),
 .LATENCY_DIAGNOSTICS(LATENCY_TEST)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tdata(bin),.I_rgb(rgb),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),
 .I_roi_valid(1'b0),.I_roi_x0(11'd0),.I_roi_x1(11'd639),.I_roi_y0(11'd0),.I_roi_y1(11'd447),
 .I_color_reference(CALIBRATION ? 8'd232:8'd0),.I_color_epoch(epoch),.I_color_ready(ready),.I_query_bank(1'b0),.I_query_row(8'd0),
 .O_targets(targets),.O_target_count(count),.O_target_overflow(overflow),.O_upd(upd),
 .O_latency_bcd(latency_bcd),.O_latency_valid(latency_valid),.O_latency_upd(latency_upd));
 always #5 clk=~clk;
 always @(posedge clk) if(rst && LATENCY_TEST) begin
  monitor_cycle=monitor_cycle+1;
  if(dut.capture_valid && dut.capture_user) begin
   if(dut.take) start_cycle=monitor_cycle;else skipped_starts=skipped_starts+1;
  end
  #1;
  if(upd!=previous_upd) begin
   expected_ticks=(monitor_cycle-start_cycle)/11251;
   if(start_cycle<0 || !latency_valid || latency_upd==previous_latency_upd ||
      latency_bcd[15:12]*1000+latency_bcd[11:8]*100+latency_bcd[7:4]*10+latency_bcd[3:0]!=expected_ticks)
    $fatal(1,"batch latency got%h valid%0d expected ticks%0d cycles%0d",latency_bcd,latency_valid,expected_ticks,monitor_cycle-start_cycle);
   latency_checks=latency_checks+1;
  end else if(latency_upd!=previous_latency_upd) $fatal(1,"latency publication without result");
  previous_upd=upd;previous_latency_upd=latency_upd;
 end
  function automatic part_pixel(input integer px,py,pk);
    real ux,uy,a,t,qx,qy;
    integer dx,dy,j;
    begin
      dx=px-cx;dy=py-cy;
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

 task image;
 begin
  for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+1) owner[y*W+x]=0;
  for(j=0;j<active;j=j+1) begin
   cx=ox[j];cy=oy[j];
   for(y=cy-72;y<=cy+72;y=y+1) for(x=cx-72;x<=cx+72;x=x+1)
    if(part_pixel(x,y,kind[j])) owner[y*W+x]=j+1;
  end
 end endtask
 task observe(input integer confirmed,expected_count,expected_overflow);
 begin
  image();old_upd=upd;
  for(y=0;y<H;y=y+1) begin
   for(x=0;x<W;x=x+4) begin
    @(negedge clk);valid=1;user=x==0 && y==0;last=x==W-4;
    for(k=0;k<4;k=k+1) begin
     rgb[k*24+:24]=no_board || x+k<16 || x+k>=W-16 || y<16 || y>=H-16 ? 24'h080808:
       owner[y*W+x+k]!=0 ? colours[owner[y*W+x+k]-1]:24'he8e8e8;
    end
   end
   @(negedge clk);valid=0;user=0;last=0;repeat(2) @(negedge clk);
  end
  if(LATENCY_TEST) begin
   // Camera keeps streaming while the single shared engine is busy. This SOF
   // is intentionally not accepted and must not restart the batch timer.
   repeat(12) @(negedge clk);valid=1;user=1;last=0;
   @(negedge clk);valid=0;user=0;
  end
  cycles=0;
  while(upd===old_upd && cycles<2000000) begin
   @(negedge clk);cycles=cycles+1;
   if(change_context_mid_batch && dut.multi_index==1 && dut.state==28) begin
    epoch=epoch+1'b1;change_context_mid_batch=0;
   end
  end
  if(upd===old_upd) $fatal(1,"multi timeout state%0d phase%0d index%0d",dut.state,dut.phase,dut.multi_index);
  if(overflow!==expected_overflow) $fatal(1,"overflow got%0d expected%0d",overflow,expected_overflow);
  n=0;for(j=0;j<5;j=j+1) hits[j]=0;
  for(j=0;j<4;j=j+1) begin
   item=targets[j*56+:56];
   if(item[55]) begin
    n=n+1;
    // Associate expected object using independent screen quadrants/centre.
    centre=(item[43:33]+item[32:22])/2;
    if(centre>260 && centre<380) k=4;
    else k=(centre>320 ? 1:0)+((item[21:11]+item[10:0])/2>224 ? 2:0);
    if(hits[k]) $fatal(1,"duplicate object box");hits[k]=1;
    if(item[54:52]!==expected_shape[k] || item[51:49]!==expected_colour[k])
      $fatal(1,"frame%0d object%0d shape%0d colour%0d expected%0d/%0d raw%h",frames,k,item[54:52],item[51:49],expected_shape[k],expected_colour[k],item);
    if(item[43:33]<ox[k]-80 || item[32:22]>ox[k]+80 || item[21:11]<oy[k]-80 || item[10:0]>oy[k]+80)
      $fatal(1,"wrong component bounds");
   end
  end
  if(n!=expected_count || count!=expected_count) $fatal(1,"frame%0d boxes%0d count%0d expected%0d candidates%0d",frames,n,count,expected_count,dut.multi_count);
  $display("PASS multi frame%0d boxes%0d overflow%0d cycles%0d",frames,n,overflow,cycles);frames=frames+1;
  repeat(10) @(negedge clk);
 end endtask
 initial begin
  ox[0]=160;oy[0]=112;kind[0]=1;colours[0]=24'hb8b8b8;expected_shape[0]=2;expected_colour[0]=5;
  ox[1]=480;oy[1]=112;kind[1]=2;colours[1]=24'hc03838;expected_shape[1]=3;expected_colour[1]=1;
  ox[2]=160;oy[2]=336;kind[2]=7;colours[2]=24'h303030;expected_shape[2]=4;expected_colour[2]=4;
  ox[3]=480;oy[3]=336;kind[3]=3;colours[3]=24'hb89648;expected_shape[3]=1;expected_colour[3]=6;
  ox[4]=320;oy[4]=224;kind[4]=1;colours[4]=24'hb8b8b8;expected_shape[4]=2;expected_colour[4]=5;
  repeat(5) @(negedge clk);rst=1;
  observe(0,0,0);observe(0,0,0);observe(1,4,0);
  colours[1]=24'hb89648;expected_colour[1]=0;observe(1,4,0);
  expected_colour[1]=6;observe(1,4,0);
  kind[0]=0;observe(1,3,0); // slot indices change; surviving histories must follow positions.
  kind[0]=1;observe(1,3,0);observe(1,3,0);observe(1,4,0);
  if(CALIBRATION) begin
  // Historical opt-in calibration mode still has independent shape confirmation.
  ready=0;epoch=1;for(j=0;j<4;j=j+1) expected_colour[j]=0;
  observe(1,4,0);ready=1;observe(1,4,0);
  expected_colour[0]=5;expected_colour[1]=6;expected_colour[2]=4;expected_colour[3]=6;observe(1,4,0);
  change_context_mid_batch=1;for(j=0;j<4;j=j+1) expected_colour[j]=0;
  observe(1,4,0);observe(1,4,0);
  expected_colour[0]=5;expected_colour[1]=6;expected_colour[2]=4;expected_colour[3]=6;observe(1,4,0);
  end else begin
   // Production: no reference, no ready/lock since reset, all four colours work.
   // Neither a control toggle nor an epoch change, even mid-analysis, blanks them.
   epoch=1;observe(1,4,0);ready=1;epoch=2;observe(1,4,0);
   ready=0;change_context_mid_batch=1;observe(1,4,0);observe(1,4,0);
  end
  active=5;observe(1,3,1);observe(1,3,1);observe(1,4,1);
  active=0;observe(0,0,0);active=4;no_board=1;observe(0,0,0);
  no_board=0;active=1;kind[0]=5;observe(0,0,0);observe(0,0,0);observe(0,0,0);
  if(LATENCY_TEST && (latency_checks!=frames || skipped_starts!=frames)) $fatal(1,"missing batch latency/skipped-frame checks");
  $display("ALL PASS multi: four shapes/colours, independent confirmation, hue change, removal/reorder, calibration epoch, overflow, empty/no board, unsupported silhouette; latency checks%0d",latency_checks);$finish;
 end
 initial begin #500000000;$fatal(1,"multi global timeout");end
endmodule

module tb_parts_multi_no_calibration;
 tb_parts_multi #(.CALIBRATION(0)) test();
endmodule

module tb_parts_multi_latency;
 tb_parts_multi #(.CALIBRATION(0),.LATENCY_TEST(1)) test();
endmodule
