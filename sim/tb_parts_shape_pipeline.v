`timescale 1ns/1ps
// Check the timing repair independently of rendered test silhouettes:
// exhaustive signed coordinates, back-to-back points, bubbles and finish
// next to the final point, plus start/reset cancellation of in-flight data.
module tb_parts_shape_pipeline;
    reg clk=0,rst=0,start=0,point=0,finish=0;
    reg signed [8:0] dx=0,dy=0;
    wire done,elongated,round_shape,hex_shape,circle_shape,head,square_shape;
    always #5 clk=~clk;
    img_parts_shape dut(clk,rst,start,point,finish,dx,dy,
        done,elongated,round_shape,hex_shape,circle_shape,head,square_shape);
    integer expected_bins[0:299999],radii[0:299999];
    integer wr=0,rd=0,total_checked=0,checks=0;
    reg [15:0] expected_radial[0:23];
    reg [31:0] expected_x,expected_y;
    reg signed [31:0] expected_xy;
    reg signed [23:0] expected_sum_x,expected_sum_y;
    reg [15:0] expected_points;
    reg [5:0] expected_flags;
    longint unsigned norm_x,norm_y,rad_total,ref_anis,ref_trace,ref_six,ref_rad_sq;
    longint signed norm_xy,rad_cos,rad_sin,abs_sum_x,abs_sum_y;
    longint signed rad_four_cos,rad_four_sin;
    longint unsigned ref_four;
    integer j,x,y,r,b,cycles;
    // Integer reference deliberately does not share the RTL pipeline logic.
    function integer reference_bin(input integer px,input integer py);
        integer a,c,q,s;
        begin
            if(px>=0 && py>=0) begin a=px;c=py;q=0;end
            else if(px<0 && py>=0) begin a=py;c=-px;q=1;end
            else if(px<0 && py<0) begin a=-px;c=-py;q=2;end
            else begin a=-py;c=px;q=3;end
            if(c*256<a*69) s=0;
            else if(c*256<a*148) s=1;
            else if(c<a) s=2;
            else if(c*148<a*256) s=3;
            else if(c*69<a*256) s=4;
            else s=5;
            reference_bin=q*6+s;
            if(py==0) reference_bin=px<0 ? 12 : 0;
            else if(px==0) reference_bin=py<0 ? 18 : 6;
        end
    endfunction
    always @(posedge clk) begin
        if(!rst || start) begin
            wr=0;rd=0;expected_x=0;expected_y=0;expected_xy=0;
            expected_sum_x=0;expected_sum_y=0;expected_points=0;
            for(j=0;j<24;j=j+1) expected_radial[j]=0;
        end else begin
            if(point && dut.state==0) begin
                x=$signed(dx);y=$signed(dy);
                expected_bins[wr]=reference_bin(x,y);radii[wr]=x*x+y*y;wr=wr+1;
                expected_x=expected_x+x*x;expected_y=expected_y+y*y;
                expected_xy=expected_xy+x*y;
                expected_sum_x=expected_sum_x+x;expected_sum_y=expected_sum_y+y;
                expected_points=expected_points+1'b1;
            end
            if(dut.point_valid[4]) begin
                if(rd>=wr || dut.point_bin!==expected_bins[rd] || dut.point_r2!==radii[rd])
                    $fatal(1,"point mismatch rd%0d bin%0d/%0d radius%0d/%0d",rd,dut.point_bin,expected_bins[rd],dut.point_r2,radii[rd]);
                b=expected_bins[rd];r=radii[rd];
                if(r>expected_radial[b]) expected_radial[b]=r;
                rd=rd+1;total_checked=total_checked+1;
            end
            // No normalization has happened at this drain boundary.
            if(dut.state==9 && dut.point_valid==0) begin
                if(rd!=wr || dut.moment_x!==expected_x || dut.moment_y!==expected_y ||
                    dut.moment_xy!==expected_xy || dut.sum_x!==expected_sum_x ||
                    dut.sum_y!==expected_sum_y || dut.points!==expected_points)
                    $fatal(1,"drain lost/misaligned moments or points rd%0d wr%0d",rd,wr);
                for(j=0;j<24;j=j+1) if(dut.radial[j]!==expected_radial[j])
                    $fatal(1,"radial mismatch bin%0d value%0d expected%0d",j,dut.radial[j],expected_radial[j]);
                // Reference the pre-normalized point totals, independently
                // of the RTL multiplier scheduling and final result stages.
                norm_x=expected_x;norm_y=expected_y;norm_xy=expected_xy;
                while(norm_x+norm_y>65535) begin
                    norm_x=norm_x>>1;norm_y=norm_y>>1;norm_xy=norm_xy>>>1;
                end
                rad_total=0;rad_cos=0;rad_sin=0;rad_four_cos=0;rad_four_sin=0;
                for(j=0;j<24;j=j+1) begin
                    rad_total=rad_total+expected_radial[j];
                    case(j%4)
                        0:rad_cos=rad_cos+expected_radial[j];
                        1:rad_sin=rad_sin+expected_radial[j];
                        2:rad_cos=rad_cos-expected_radial[j];
                        3:rad_sin=rad_sin-expected_radial[j];
                    endcase
                    case(j%6)
                        0:rad_four_cos=rad_four_cos+8*expected_radial[j];
                        1:begin rad_four_cos=rad_four_cos+4*expected_radial[j];rad_four_sin=rad_four_sin+7*expected_radial[j];end
                        2:begin rad_four_cos=rad_four_cos-4*expected_radial[j];rad_four_sin=rad_four_sin+7*expected_radial[j];end
                        3:rad_four_cos=rad_four_cos-8*expected_radial[j];
                        4:begin rad_four_cos=rad_four_cos-4*expected_radial[j];rad_four_sin=rad_four_sin-7*expected_radial[j];end
                        5:begin rad_four_cos=rad_four_cos+4*expected_radial[j];rad_four_sin=rad_four_sin-7*expected_radial[j];end
                    endcase
                end
                rad_four_cos=rad_four_cos>>>3;rad_four_sin=rad_four_sin>>>3;
                while(rad_total>65535) begin
                    rad_total=rad_total>>1;rad_cos=rad_cos>>>1;rad_sin=rad_sin>>>1;
                    rad_four_cos=rad_four_cos>>>1;rad_four_sin=rad_four_sin>>>1;
                end
                ref_anis=((norm_x-norm_y)*(norm_x-norm_y)+4*norm_xy*norm_xy)&64'h1ffffffff;
                ref_trace=(norm_x+norm_y)*(norm_x+norm_y);
                ref_six=rad_cos*rad_cos+rad_sin*rad_sin;ref_rad_sq=rad_total*rad_total;
                ref_four=rad_four_cos*rad_four_cos+rad_four_sin*rad_four_sin;
                abs_sum_x=expected_sum_x;abs_sum_y=expected_sum_y;
                if(abs_sum_x<0) abs_sum_x=-abs_sum_x;
                if(abs_sum_y<0) abs_sum_y=-abs_sum_y;
                expected_flags={ref_trace!=0 && ref_anis*5>=ref_trace,
                    ref_trace!=0 && ref_anis*16<=ref_trace,
                    ref_rad_sq!=0 && ref_six*1024>=ref_rad_sq && ref_six*64<=ref_rad_sq && ref_four*256<ref_rad_sq,
                    ref_rad_sq!=0 && ref_six*2048<=ref_rad_sq && ref_four*512<=ref_rad_sq,
                    abs_sum_x+abs_sum_y>=expected_points,
                    ref_rad_sq!=0 && ref_four*256>=ref_rad_sq && ref_four*16<=ref_rad_sq};
                checks=checks+1;
            end
        end
    end
    task begin_object;
        begin
            @(negedge clk);start=1;point=0;finish=0;
            @(negedge clk);start=0;
        end
    endtask
    task send_point(input integer px,input integer py,input integer bubbles,input integer last);
        begin
            repeat(bubbles) begin @(negedge clk);point=0;finish=0;end
            @(negedge clk);dx=px;dy=py;point=1;finish=last;
        end
    endtask
    task await_done;
        begin
            @(negedge clk);point=0;finish=0;cycles=0;
            while(!done && cycles<160) begin @(negedge clk);cycles=cycles+1;end
            if(!done) $fatal(1,"completion timeout");
            if(dut.four_num!=ref_four || dut.six_num!=ref_six || dut.radial_total_sq!=ref_rad_sq)
                $fatal(1,"harmonic arithmetic mismatch four %0d/%0d six %0d/%0d total %0d/%0d",
                    dut.four_num,ref_four,dut.six_num,ref_six,dut.radial_total_sq,ref_rad_sq);
            if({elongated,round_shape,hex_shape,circle_shape,head,square_shape}!==expected_flags)
                $fatal(1,"final invariant result alignment");
            @(negedge clk);if(done) $fatal(1,"done must pulse for one cycle");
        end
    endtask
    integer a,c;
    initial begin
        repeat(3) @(negedge clk);rst=1;
        begin_object();
        for(a=-256;a<256;a=a+1) for(c=-256;c<256;c=c+1)
            send_point(a,c,0,a==255 && c==255);
        await_done();
        begin_object();
        for(a=0;a<120;a=a+1) send_point((a*79)%319-159,(a*31)%179-89,a%4,0);
        // Finish on the clock immediately following the final point.
        @(negedge clk);point=0;finish=1;await_done();
        // A start aborts pending points; new results cannot retain them.
        begin_object();send_point(99,-87,0,0);send_point(-12,19,0,0);
        begin_object();send_point(0,0,0,1);await_done();
        // Reset abort, then an empty object with no points to drain.
        begin_object();send_point(-159,89,0,0);
        @(negedge clk);rst=0;point=0;repeat(2) @(negedge clk);rst=1;
        begin_object();@(negedge clk);finish=1;await_done();
        // Restart while the post-frame multiplier is active.
        begin_object();send_point(17,23,0,1);
        @(negedge clk);point=0;finish=0;repeat(35) @(negedge clk);
        begin_object();send_point(-3,-4,0,1);await_done();
        if(checks!=6 || total_checked<262266) $fatal(1,"coverage checks%0d points%0d",checks,total_checked);
        $display("ALL PASS shape pipeline: 262144 signed coordinate pairs, bubbles, finish drain, start/reset abort, completion alignment; checks%0d points%0d",checks,total_checked);
        $finish;
    end
    initial begin #10000000;$fatal(1,"global timeout");end
endmodule
