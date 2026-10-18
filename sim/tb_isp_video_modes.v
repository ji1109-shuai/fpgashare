`timescale 1ns/1ps
// Full 720p ISP, vendor camera/AWB substitutes from tb_isp_threshold.
module tb_isp_video_modes;
    reg clk=0,rst=0,v=0,sof=0,bin=0;
    reg [1:0] mode=0;
    reg [95:0] rgb=0;
    integer m,y,b,p,px,py,j,g,dx,dy,s,preview_pixels=0,bytes=0,updates=0;
    integer packed_rows=0,packed_col=0,frame_starts=0;
    reg prev_upd=0;
    reg [23:0] c,expected;
    reg [7:0] fifo[0:2764799];
    reg [2:0] active_mode;
    isp_top #(.VIDEO_MODES(1),.DEBUG_CAPTURE(1)) dut(.axi4s_video_aclk(clk),.I_rst_n(rst),
        .I_tlast(1'b0),.I_tuser(1'b0),.I_tdata(40'd0),.I_tvalid(1'b0),.I_tdest(10'd0),
        .O_tready(1'b1),.I_bin_en(bin),.I_morph_mode(mode),.I_awb_freeze(1'b1),.O_display_mode(active_mode));
    always #5 clk=~clk;
    function [23:0] pixel;
        input integer x,y;
        integer xx,yy;
        begin
            xx=x-400;yy=y-200;
            pixel=(x<256 || x>543 || y<64 || y>335 || (xx*xx+yy*yy<=3600 && xx*xx+yy*yy>1764)) ?
                   24'h181818:24'hdddddd;
        end
    endfunction
    function integer lum;
        input integer x,y;
        reg [23:0] cc;
        begin cc=pixel(x,y);lum=cc[7:0];end
    endfunction
    always @(posedge clk) begin
        if(rst && dut.O_frame_start) begin
            frame_starts=frame_starts+1;
            if((m==2 || m==3) && sof) $fatal(1,"row-delayed mode reset on raw SOF");
            if((m<2 || m>=4) && !sof) $fatal(1,"direct path lost raw early boundary");
        end
        if(rst && m<2 && dut.mux_tvalid!==dut.awb_tvalid_d1)
            $fatal(1,"RGB/gray preview changed the physically verified AWB valid cadence");
        // Observe the pre-packer stream at its sampling edge.
        if(rst && dut.mux_tvalid) begin
            // Verified RGB path retains its early SOF, other effects align it.
            if(m>0 && dut.mux_tuser !== (preview_pixels==0)) $fatal(1,"preview SOF");
            for(j=0;j<4;j=j+1) begin
                px=(preview_pixels+j)%1280;py=(preview_pixels+j)/1280;
                if(m<4) begin
                    if(m==0) expected=pixel(px,py);
                    else begin
                        g=lum(px,py);
                        if(m>=2) begin
                            g=0;
                            if(px>0 && px<1279 && py>0 && py<719) begin
                                dx=lum(px+1,py-1)+2*lum(px+1,py)+lum(px+1,py+1)-lum(px-1,py-1)-2*lum(px-1,py)-lum(px-1,py+1);
                                dy=lum(px-1,py+1)+2*lum(px,py+1)+lum(px+1,py+1)-lum(px-1,py-1)-2*lum(px,py-1)-lum(px+1,py-1);
                                s=((dx<0 ? -dx:dx)+(dy<0 ? -dy:dy))/4;g=s>255 ? 255:s;
                            end
                            if(m==3) g=g>=16 ? 255:0;
                        end
                        expected={g[7:0],g[7:0],g[7:0]};
                    end
                    if(dut.mux_base_data[(3-j)*24+:24]!==expected)
                        $fatal(1,"ISP mode%0d pixel %0d,%0d got %h exp %h",m,px,py,dut.mux_base_data[(3-j)*24+:24],expected);
                end
                if(dut.mux_tdata!==dut.mux_base_data) $fatal(1,"hidden board boundary still alters preview pixels");
                c=dut.mux_tdata[(3-j)*24+:24];
                fifo[(preview_pixels+j)*3]=c[23:16];
                fifo[(preview_pixels+j)*3+1]=c[15:8];
                fifo[(preview_pixels+j)*3+2]=c[7:0];
            end
            preview_pixels=preview_pixels+4;
        end
        #1;
        if(rst && dut.O_tvalid) begin
            if(dut.O_tuser !== (bytes==0)) $fatal(1,"packed SOF");
            if(dut.O_tlast !== (packed_col==239)) $fatal(1,"packed EOL");
            for(j=0;j<16;j=j+1)
                if(dut.O_tdata[127-j*8-:8]!==fifo[bytes+j]) $fatal(1,"packed pixel order mode%0d byte%0d",m,bytes+j);
            bytes=bytes+16;
            if(packed_col==239) begin packed_col=0;packed_rows=packed_rows+1;end
            else packed_col=packed_col+1;
        end
        if(rst && dut.O_bbox_upd!=prev_upd) begin
            prev_upd=dut.O_bbox_upd;updates=updates+1;
            if(dut.O_bbox_color!==4) $fatal(1,"ISP BLACK color lost across mode changes");
            if(dut.O_proj_status!==0 || dut.O_proj_valid!==(updates>=3) ||
                (updates>=3 && dut.O_bbox_type!==6)) $fatal(1,"preview modes changed tire recognition");
        end
    end
    initial begin
        force dut.awb_O_tdata=rgb;force dut.awb_O_tvalid=v;
        force dut.m_aixs_tuser=sof;
        force dut.awb_O_tuser=sof;force dut.awb_O_tlast=1'b0;force dut.otsu_thresh=8'd128;
        repeat(3) @(negedge clk);rst=1;
        for(m=0;m<8;m=m+1) begin
            mode=m%4;bin=m>=4;bytes=0;preview_pixels=0;packed_rows=0;packed_col=0;frame_starts=0;
            repeat(8) @(negedge clk);sof=1;@(negedge clk);sof=0;repeat(7) @(negedge clk);
            for(y=0;y<720;y=y+1) begin
                for(b=0;b<320;b=b+1) begin
                    @(negedge clk);v=1;
                    for(p=0;p<4;p=p+1) rgb[(3-p)*24+:24]=pixel(b*4+p,y);
                    // Change both switches mid-frame; only next frame may apply.
                    if(y==360 && b==0) begin mode=(m+1)%4;bin=!(m>=4);end
                end
                @(negedge clk);v=0;
            end
            repeat(400000) @(negedge clk);
            if(bytes!=2764800 || preview_pixels!=921600 || packed_rows!=720 || packed_col!=0)
                $fatal(1,"incomplete frame mode%0d",m);
            if(active_mode!==m || updates!=m+1) $fatal(1,"mode latch/update mode%0d applied%0d",m,active_mode);
            if(frame_starts!=1) $fatal(1,"missing/duplicate DDR boundary mode%0d pulses%0d",m,frame_starts);
            if(dut.g_video_modes.u_video_modes.g_debug.DBG_VM_ERROR!==0 ||
               dut.g_video_modes.u_video_modes.g_debug.DBG_VM_IN_BEATS!==230400 ||
               dut.g_video_modes.u_video_modes.g_debug.DBG_VM_OUT_BEATS!==230400)
                $fatal(1,"full ISP debug monitor counts/cadence mode%0d err%h in%0d out%0d",m,
                    dut.g_video_modes.u_video_modes.g_debug.DBG_VM_ERROR,
                    dut.g_video_modes.u_video_modes.g_debug.DBG_VM_IN_BEATS,
                    dut.g_video_modes.u_video_modes.g_debug.DBG_VM_OUT_BEATS);
        end
        $display("ALL PASS: 8 full 720p ISP modes, reference Sobel/gray, RGB packing, final row, frame-held switches, unchanged tire recognition");$finish;
    end
    initial begin #80000000;$fatal(1,"ISP modes timeout");end
endmodule
