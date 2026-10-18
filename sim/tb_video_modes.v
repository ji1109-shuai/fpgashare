`timescale 1ns/1ps
module video_modes_check #(parameter W=20,H=9,FULL=0);
    reg clk=0,rst=0,v=0,sof=0,eol=0;
    reg [95:0] data=0;
    reg [1:0] mode=0;
    reg checking=1;
    wire [95:0] out;
    wire ov,os,ol;
    integer edge_pixels=0;
    integer seen=0,pat=0,expected_mode=0,frame_no,x,y,b,p,n,j,px,py,g;
    reg [23:0] expect_rgb;
    img_video_modes #(.BEATS_PER_LINE(W/4),.LINES_PER_FRAME(H)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_tdata(data),.I_tvalid(v),
        .I_tuser(sof),.I_tlast(eol),.I_mode(mode),
        .O_tdata(out),.O_tvalid(ov),.O_tuser(os),.O_tlast(ol));
    always #5 clk=~clk;
    function [23:0] pixel;
        input integer xx,yy,pattern;
        integer r,gg,bb;
        begin
            case(pattern)
                0: begin r=40;gg=110;bb=230;end
                1: begin r=xx<W/2 ? 0:255;gg=r;bb=r;end
                2: begin r=yy<H/2 ? 0:255;gg=r;bb=r;end
                3: begin r=xx*H>yy*W ? 0:255;gg=r;bb=r;end
                5: begin r=xx<W/2 ? 96:128;gg=r;bb=r;end // 32-level low-contrast step
                6: begin r=96+((xx-W/2+2)<0 ? 0 : (xx-W/2+2)>4 ? 4 : (xx-W/2+2))*8;gg=r;bb=r;end // blurred 32-level edge
                default: begin r=(xx*37+yy*71)%256;gg=(xx*11+yy*19)%256;bb=(xx*7+yy*29)%256;end
            endcase
            pixel={r[7:0],gg[7:0],bb[7:0]};
        end
    endfunction
    function integer luminance;
        input integer xx,yy;
        reg [23:0] c;
        begin c=pixel(xx,yy,pat);luminance=(c[23:16]+2*c[15:8]+c[7:0])/4;end
    endfunction
    function integer edge_value;
        input integer xx,yy;
        integer dx,dy,s;
        begin
            if(xx==0 || xx==W-1 || yy==0 || yy==H-1) edge_value=0;
            else begin
                dx=luminance(xx+1,yy-1)+2*luminance(xx+1,yy)+luminance(xx+1,yy+1)
                   -luminance(xx-1,yy-1)-2*luminance(xx-1,yy)-luminance(xx-1,yy+1);
                dy=luminance(xx-1,yy+1)+2*luminance(xx,yy+1)+luminance(xx+1,yy+1)
                   -luminance(xx-1,yy-1)-2*luminance(xx,yy-1)-luminance(xx+1,yy-1);
                s=((dx<0 ? -dx:dx)+(dy<0 ? -dy:dy))/4;
                edge_value=s>255 ? 255:s;
            end
        end
    endfunction
    always @(posedge clk) begin
        #1;
        if(rst && ov && checking) begin
            if(seen>=W*H) $fatal(1,"extra pixels");
            if(os !== (seen==0)) $fatal(1,"SOF at %0d",seen);
            if(ol !== (seen%W==W-4)) $fatal(1,"EOL at %0d",seen);
            for(j=0;j<4;j=j+1) begin
                px=(seen+j)%W;py=(seen+j)/W;
                case(expected_mode)
                    0: expect_rgb=pixel(px,py,pat);
                    1: begin g=luminance(px,py);expect_rgb={g[7:0],g[7:0],g[7:0]};end
                    2: begin g=edge_value(px,py);expect_rgb={g[7:0],g[7:0],g[7:0]};end
                    3: expect_rgb=edge_value(px,py)>=16 ? 24'hffffff:0;
                endcase
                if(out[j*24+:24]!==expect_rgb)
                    $fatal(1,"mode%0d pattern%0d pixel %0d,%0d got %h expected %h",expected_mode,pat,px,py,out[j*24+:24],expect_rgb);
            end
            for(j=0;j<4;j=j+1) if(expected_mode==3 && out[j*24+:24]==24'hffffff) edge_pixels=edge_pixels+1;
            seen=seen+4;
        end
    end
    task run_frame;
        input integer md,pattern,gaps;
        begin
            seen=0;edge_pixels=0;pat=pattern;expected_mode=md;mode=md;
            for(y=0;y<H;y=y+1) begin
                for(b=0;b<W/4;b=b+1) begin
                    if(gaps && (b+y)%3==1) begin
                        @(negedge clk);v=0;sof=0;eol=0;
                        repeat(2) @(negedge clk);
                    end
                    @(negedge clk);v=1;sof=y==0 && b==0;eol=b==W/4-1;
                    for(p=0;p<4;p=p+1) data[p*24+:24]=pixel(b*4+p,y,pat);
                    if(y==2 && b==0) mode=(md+1)%4; // must not affect this frame
                end
                if(gaps) begin @(negedge clk);v=0;sof=0;eol=0;repeat(3) @(negedge clk);end
            end
            @(negedge clk);v=0;sof=0;eol=0;
            repeat(2*(W/4)+20) @(negedge clk);
            if(seen!=W*H) $fatal(1,"missing final row/pixels %0d",seen);
            if(md==3 && pattern>=5 && edge_pixels==0) $fatal(1,"low-contrast boundary disappeared");
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=1;
        // Mode, pattern and blank/gap combinations, with no reset between frames.
        for(n=0;n<(FULL ? 4:20);n=n+1) run_frame(n%4,FULL ? n+1:n/4,n%2);
        if(!FULL) begin
            run_frame(2,5,1);run_frame(3,5,1);
            run_frame(2,6,1);run_frame(3,6,1);
        end
        // Reset during a partial frame; RAM is intentionally not reset.
        checking=0;
        @(negedge clk);v=1;sof=1;eol=0;data=96'h123456abcdefabcdef123456;
        @(negedge clk);v=0;sof=0;rst=0;
        repeat(3) @(negedge clk);rst=1;
        checking=1;run_frame(2,4,1);
        $display("ALL PASS: %0dx%0d RGB/gray/Sobel/edge, pixel reference, gaps, borders, final-row drain, frame-held mode and reset",W,H);
        $finish;
    end
    initial begin #30000000;$fatal(1,"video modes timeout");end
endmodule
module tb_video_modes;
    video_modes_check test();
endmodule
module tb_video_modes_720p;
    video_modes_check #(.W(1280),.H(720),.FULL(1)) test();
endmodule
module tb_video_modes_onebeat;
    video_modes_check #(.W(4),.H(3)) test();
endmodule
