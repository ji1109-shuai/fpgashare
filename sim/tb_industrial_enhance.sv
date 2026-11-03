`timescale 1ns/1ps
module tb_industrial_enhance;
    localparam W=64,H=24,B=W/4;
    reg clk=0,rst_n=0,valid=0,sof=0,last=0;
    reg [95:0] data=0;
    reg [1:0] amount=2;
    reg [3:0] noise=4;
    reg compare=0;integer compare_case,expected_compare;
    `include "../industrial_tone_reference.vh"
    wire [95:0] out;
    wire ov,os,ol;
    integer pixels=0,x,y,b,p,gain_case,noise_case,expected_gain,expected_noise,changed=0,checks=0;
    reg [23:0] expected;
    always #5 clk=~clk;
    img_video_modes #(.BEATS_PER_LINE(B),.LINES_PER_FRAME(H)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_tdata(data),.I_tvalid(valid),.I_tuser(sof),.I_tlast(last),
        .I_mode(2'd3),.I_enhance(1'b1),.I_enhance_strength(amount),.I_enhance_noise(noise),
        .I_enhance_compare(compare),
        .O_tdata(out),.O_tvalid(ov),.O_tuser(os),.O_tlast(ol));
    function [23:0] pixel(input integer xx,yy);
        integer rr,gg,bb,v;
        begin
            v=(xx<20 ? 60:xx<42 ? 130:210)+((xx+yy)%3)-1;
            if(xx==31 || yy==11) v=v-28;
            rr=v+12;gg=v;bb=v-9;
            if(xx<4) begin rr=255;gg=250;bb=249;end
            if(xx>59) begin rr=5;gg=9;bb=14;end
            pixel={rr[7:0],gg[7:0],bb[7:0]};
        end
    endfunction
    function integer luminance(input integer xx,yy);
        reg [23:0] c;
        begin c=pixel(xx,yy);luminance=(int'(c[23:16])+2*int'(c[15:8])+int'(c[7:0]))/4;end
    endfunction
    function [23:0] reference(input integer xx,yy);
        integer base,detail,delta,minimum,maximum,rr,gg,bb,ix,iy,wx,wy,cy;
        reg [23:0] c;
        begin
            c=pixel(xx,yy);rr=c[23:16];gg=c[15:8];bb=c[7:0];cy=luminance(xx,yy);delta=0;base=0;
            if(xx>0 && xx<W-1 && yy>0 && yy<H-1 && cy>16 && cy<240) begin
                for(iy=-1;iy<=1;iy=iy+1) for(ix=-1;ix<=1;ix=ix+1) begin
                    wx=ix==0 ? 2:1;wy=iy==0 ? 2:1;base=base+luminance(xx+ix,yy+iy)*wx*wy;
                end
                detail=cy-base/16;
                if((detail<0 ? -detail:detail)>expected_noise) begin
                    delta=(detail<0 ? -detail:detail)-expected_noise;
                    case(expected_gain) 0:delta=0;1:delta=delta/2;2:delta=delta;3:delta=delta+delta/2;endcase
                    if(delta>24) delta=24;if(detail<0) delta=-delta;
                end
            end
            minimum=rr<gg ? rr:gg;if(bb<minimum) minimum=bb;
            maximum=rr>gg ? rr:gg;if(bb>maximum) maximum=bb;
            if(delta < -minimum) delta=-minimum;if(delta>255-maximum) delta=255-maximum;
            rr=rr+delta;gg=gg+delta;bb=bb+delta;
            reference=expected_compare && xx<W/2 ? c:tone_reference({rr[7:0],gg[7:0],bb[7:0]},expected_gain);
        end
    endfunction
    always @(negedge clk) if(rst_n && ov) begin
        if(os!==(pixels==0) || ol!==((pixels%(W))==W-4)) $fatal(1,"enhancement markers pixels=%0d",pixels);
        for(integer k=0;k<4;k=k+1) begin
            expected=reference((pixels+k)%W,(pixels+k)/W);
            if(out[k*24+:24]!==expected) $fatal(1,"enhancement pixel %0d,%0d gain=%0d noise=%0d got=%h expected=%h",
                (pixels+k)%W,(pixels+k)/W,expected_gain,expected_noise,out[k*24+:24],expected);
            if(expected!=pixel((pixels+k)%W,(pixels+k)/W)) changed=changed+1;
            checks=checks+1;
        end
        pixels=pixels+4;
    end
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        for(compare_case=0;compare_case<2;compare_case=compare_case+1)
        for(gain_case=0;gain_case<4;gain_case=gain_case+1) for(noise_case=0;noise_case<3;noise_case=noise_case+1) begin
            compare=compare_case;expected_compare=compare_case;
            amount=gain_case;noise=noise_case==0 ? 0:noise_case==1 ? 4:15;
            expected_gain=amount;expected_noise=noise;pixels=0;changed=0;
            for(y=0;y<H;y=y+1) begin
                for(b=0;b<B;b=b+1) begin
                    @(negedge clk);valid=1;sof=(y==0 && b==0);last=(b==B-1);
                    for(p=0;p<4;p=p+1) data[p*24+:24]=pixel(b*4+p,y);
                    if(y==H/2 && b==0) begin amount=3-gain_case;noise=15-expected_noise;compare=!compare_case;end
                    if(b%5==4) begin @(negedge clk);valid=0;sof=0;last=0;repeat(2) @(negedge clk);end
                end
                @(negedge clk);valid=0;sof=0;last=0;repeat(80) @(negedge clk);
            end
            repeat(2*B+30) @(negedge clk);
            if(pixels!=W*H) $fatal(1,"enhancement frame length %0d",pixels);
            if(expected_gain==0 && changed) $fatal(1,"gain0 is not original RGB");
            if(expected_gain==2 && expected_noise==4 && changed==0) $fatal(1,"enhancement has no actual pixel effect");
        end
        $display("ALL PASS industrial enhancement: %0d pixel checks, 24 gain/noise/compare combinations, exact RGB, borders, valid gaps, final-row replay, frame-held settings",checks);$finish;
    end
    initial begin #5000000;$fatal(1,"enhancement watchdog");end
endmodule
