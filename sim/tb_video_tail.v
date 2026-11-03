`timescale 1ns/1ps
// Measured 578/579-clock inter-line idle, but only 771 clocks before
// the next aligned SOF. The real FIFO reset starts from a 55-clock-early SOF.
module video_tail_check #(parameter H=8, MODE=3, FRAMES=3, TAIL_STALL=0, USE_ISP=0, COMPARE=0, COLOUR=0);
    `include "../industrial_tone_reference.vh"
    reg cam=0,ddr=0,rst=0,v=0,sof=0,eol=0,early=0;
    reg [95:0] rgb=0;
    wire [95:0] out;
    wire ov,os,ol,pv,ps,wr;
    wire effect_start;
    wire ddr_boundary;
`ifdef EARLY_DDR_RESET
    assign ddr_boundary=early;
`else
    assign ddr_boundary=MODE>=2 ? effect_start : early;
`endif
`ifdef PRE_TAIL_FIX
    assign effect_start=early;
`endif
    reg busy=0;
    integer stall=0;
    wire [127:0] packed_data,wd;
    wire [11:0] measured_fps;
    wire fps_update;
    video_frame_rate #(.WORDS_PER_FRAME(H*240)) frame_meter(
        .camera_clk(cam),.system_clk(ddr),.rst_n(rst),
        .frame_start(ps),.word_valid(pv),.fps_bcd(measured_fps),.fps_update(fps_update));
    wire [24:0] addr;
    integer f,y,b,p,gap,i,j,output_frame=-1,beats=0,pack_phase=0;
    integer offered=0,written=0,df,dw,reset_overlap=0;
    reg [95:0] reference,previous_reference;
    reg [127:0] expected_words[0:FRAMES*H*240-1];
    always #4.444 cam=~cam;
    always #7.5 ddr=~ddr;
    img_video_modes #(.LINES_PER_FRAME(H),.DEBUG_CAPTURE(1)) fx(
        .I_clk(cam),.I_rst_n(rst),.I_tdata(rgb),.I_tvalid(v),.I_tuser(sof),
        .I_tlast(eol),.I_mode(MODE[1:0]),.I_enhance(MODE==7),.I_enhance_strength(2'd2),.I_enhance_noise(4'd4),.I_enhance_compare(COMPARE!=0),.O_tdata(out),.O_tvalid(ov),.O_tuser(os),.O_tlast(ol)
`ifndef PRE_TAIL_FIX
        ,.O_frame_start(effect_start)
`endif
    );
    generate if(USE_ISP) begin : g_isp
        wire [95:0] awb_rgb={rgb[23:0],rgb[47:24],rgb[71:48],rgb[95:72]};
        wire isp_boundary;
        isp_top #(.VIDEO_MODES(1),.DEBUG_CAPTURE(1)) dut(
            .axi4s_video_aclk(cam),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(1'b0),
            .I_tdata(40'd0),.I_tvalid(1'b0),.I_tdest(10'd0),.O_tready(1'b1),
            .I_bin_en(MODE>=4),.I_morph_mode(MODE[1:0]),.I_enhance_strength(2'd2),.I_enhance_noise(4'd4),.I_awb_freeze(1'b1),
            .I_enhance_compare(COMPARE!=0),
            .O_tdata(packed_data),.O_tvalid(pv),.O_tuser(ps),.O_frame_start(isp_boundary));
        initial begin
            force dut.awb_O_tdata=awb_rgb;force dut.awb_O_tvalid=v;
            force dut.awb_O_tuser=early;force dut.awb_O_tlast=1'b0;
            force dut.m_aixs_tuser=early;force dut.otsu_thresh=8'd128;
        end
        always @(posedge cam) if(rst) begin
            if(isp_boundary!==effect_start) $fatal(1,"ISP selected wrong DDR boundary");
            if(dut.effects_valid!==ov || (ov && {dut.effects_data,dut.effects_sof,dut.effects_last}!=={out,os,ol}))
                $fatal(1,"ISP frame/data alignment differs from mathematical-reference path");
        end
    end else begin : g_pack
    data_96bit_to_128bit pack(.I_clk(cam),.I_rst_n(rst),
        .I_96b_frame_start(os),.I_96b_valid(ov),
        .I_96b_data({out[23:0],out[47:24],out[71:48],out[95:72]}),
        .O_128b_frame_start(ps),.O_128b_valid(pv),.O_128b_data(packed_data));
    end endgenerate
    video_in #(.DEBUG_CAPTURE(1),.FRAME_WORDS(H*240)) vi(
        .I_rst_n(rst),.I_camera_clk(cam),.I_camera_frame_start(ddr_boundary),
        .I_camera_valid(pv),.I_camera_data(packed_data),.I_mipi_rx_error(1'b0),
        .I_ddr_clk(ddr),.I_display_pause(1'b0),.I_video_out_rd_busy(busy),
        .O_ddr_user_wr_en(wr),.O_ddr_user_addr(addr),.O_ddr_user_wr_data(wd),.I_ddr_user_ready(!busy));
    function integer lum;
        input integer x,y,frame;
        reg [23:0] c;
        begin c=source_pixel(x,y,frame);lum=(int'(c[23:16])+2*int'(c[15:8])+int'(c[7:0]))/4;end
    endfunction
    function [23:0] source_pixel(input integer x,y,frame);
        integer v,r,g,b;
        begin
            v=(x*11+y*19+frame*43)%256;r=v;g=v;b=v;
            if(COLOUR) begin r=(v+x*3+29)%256;g=(v+y*7+53)%256;b=(v+frame*37+97)%256;end
            source_pixel={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    function [23:0] ref_pixel;
        input integer x,y,frame;
        integer dx,dy,g,base,detail,delta,ix,iy,r,b,minimum,maximum;
        reg [23:0] c;
        begin
            g=0;
            if(MODE==7) begin
                g=lum(x,y,frame);base=0;delta=0;
                if(x>0 && x<1279 && y>0 && y<H-1 && g>16 && g<240) begin
                    for(iy=-1;iy<=1;iy=iy+1) for(ix=-1;ix<=1;ix=ix+1)
                        base=base+lum(x+ix,y+iy,frame)*(ix==0 ? 2:1)*(iy==0 ? 2:1);
                    detail=g-base/16;
                    if((detail<0 ? -detail:detail)>4) begin
                        delta=(detail<0 ? -detail:detail)-4;
                        if(delta>24) delta=24;if(detail<0) delta=-delta;
                    end
                end
                c=source_pixel(x,y,frame);r=c[23:16];g=c[15:8];b=c[7:0];
                minimum=r<g ? r:g;if(b<minimum) minimum=b;maximum=r>g ? r:g;if(b>maximum) maximum=b;
                if(delta < -minimum) delta=-minimum;if(delta>255-maximum) delta=255-maximum;
                r=r+delta;g=g+delta;b=b+delta;
            end else if(MODE<2) g=lum(x,y,frame);
            else if(x>0 && x<1279 && y>0 && y<H-1) begin
                dx=lum(x+1,y-1,frame)+2*lum(x+1,y,frame)+lum(x+1,y+1,frame)
                  -lum(x-1,y-1,frame)-2*lum(x-1,y,frame)-lum(x-1,y+1,frame);
                dy=lum(x-1,y+1,frame)+2*lum(x,y+1,frame)+lum(x+1,y+1,frame)
                  -lum(x-1,y-1,frame)-2*lum(x,y-1,frame)-lum(x+1,y-1,frame);
                g=((dx<0 ? -dx:dx)+(dy<0 ? -dy:dy))/4;
                if(g>255) g=255;
            end
            if(MODE==3) g=g>=16 ? 255:0;
            ref_pixel=MODE==7 ? ((COMPARE && x<640) ? source_pixel(x,y,frame):tone_reference({r[7:0],g[7:0],b[7:0]},2)):{g[7:0],g[7:0],g[7:0]};
        end
    endfunction
    // Build DDR expectations from the mathematical reference, never DUT data.
    always @(posedge cam) if(rst) begin
        if(v && sof && f>0 && MODE>=2 && beats!=H*320)
            $fatal(1,"TAIL TRUNCATION: frame%0d beats=%0d expected=%0d flush_col=%0d DDR=%0d expectedDDR=%0d",
                f-1,beats,H*320,fx.flush_col,written-(f-1)*H*240,H*240);
`ifndef PRE_TAIL_FIX
        if(MODE>=2 && effect_start && written!=(output_frame+1)*H*240)
            $fatal(1,"FIFO boundary precedes complete old DDR frame: written=%0d expected=%0d",written,(output_frame+1)*H*240);
`endif
        if(ov) begin
            if(TAIL_STALL && beats==(H-1)*320) begin busy=1;stall=500;end
            if(os) begin
                if(output_frame>=0 && beats!=H*320) $fatal(1,"incomplete output frame");
                output_frame=output_frame+1;beats=0;pack_phase=0;
            end
            if(output_frame<0 || output_frame>=FRAMES || beats>=H*320) $fatal(1,"extra output");
            if(os!==(beats==0) || ol!==(beats%320==319)) $fatal(1,"marker mismatch");
            for(j=0;j<4;j=j+1) begin
                reference[(3-j)*24+:24]=ref_pixel((beats%320)*4+j,beats/320,output_frame);
                if(out[j*24+:24]!==reference[(3-j)*24+:24]) $fatal(1,"reference mismatch frame%0d beat%0d pixel%0d",output_frame,beats,j);
            end
            case(pack_phase)
                1: begin expected_words[offered]={previous_reference,reference[95:64]};offered=offered+1;end
                2: begin expected_words[offered]={previous_reference[63:0],reference[95:32]};offered=offered+1;end
                3: begin expected_words[offered]={previous_reference[31:0],reference};offered=offered+1;end
            endcase
            previous_reference=reference;pack_phase=(pack_phase+1)%4;beats=beats+1;
        end
        if(pv && vi.S_fifo_rst) reset_overlap=reset_overlap+1;
        if(stall>0) begin stall=stall-1;if(stall==0) busy=0;end
    end
    always @(posedge ddr) if(rst && wr) begin
        df=written/(H*240);dw=written%(H*240);
        if(addr!==(df%4)*7000000+dw*8) $fatal(1,"DDR frame/address discontinuity word%0d addr%0d expected%0d",written,addr,(df%4)*7000000+dw*8);
        if(written>=offered || wd!==expected_words[written]) $fatal(1,"DDR independent reference mismatch word%0d",written);
        written=written+1;
    end
    task frame;
        begin
            early=1;@(negedge cam);early=0;repeat(54) @(negedge cam);
            for(y=0;y<H;y=y+1) begin
                for(b=0;b<320;b=b+1) begin
                    @(negedge cam);v=1;sof=y==0 && b==0;eol=b==319;
                    for(p=0;p<4;p=p+1) rgb[p*24+:24]=source_pixel(b*4+p,y,f);
                end
                @(negedge cam);v=0;sof=0;eol=0;
                if(y<H-1) begin gap=578+(y%2);repeat(gap-1) @(negedge cam);end
            end
            // 715 remaining idle clocks, followed by 55 early-marker clocks.
            repeat(715) @(negedge cam);
            $display("RAW SOF imminent frame%0d beats=%0d DDR=%0d flush=%0d fifo=%0d",f,beats,written-f*H*240,fx.flush_col,vi.S_fifo_wr_num);
        end
    endtask
    initial begin
        repeat(5) @(negedge cam);rst=1;repeat(10) @(negedge cam);
        for(f=0;f<FRAMES;f=f+1) frame();
        repeat(3000) @(negedge cam);
        if(reset_overlap!=0) $fatal(1,"camera payload during actual FIFO reset, words=%0d",reset_overlap);
        if(frame_meter.frame_count!==12'h003)
            $fatal(1,"FPS did not observe three complete packed ISP frames: %h",frame_meter.frame_count);
        if(written!=FRAMES*H*240 || offered!=FRAMES*H*240 || beats!=H*320) $fatal(1,"missing complete frame DDR=%0d ref=%0d beats=%0d",written,offered,beats);
        if(fx.g_debug.DBG_VM_ERROR!==0 || vi.g_debug.DBG_CAM_ERROR!==0 || vi.g_debug.DBG_DDR_ERROR!==0)
            $fatal(1,"sticky errors VM=%h CAM=%h DDR=%h",fx.g_debug.DBG_VM_ERROR,vi.g_debug.DBG_CAM_ERROR,vi.g_debug.DBG_DDR_ERROR);
        $display("ALL PASS: tight blank mode%0d H%0d, %0d frames, compare=%0d colour=%0d, independent pixels/DDR addresses, peak=%0d",MODE,H,FRAMES,COMPARE,COLOUR,vi.U_w128_d512_fifo.peak);$finish;
    end
    initial begin #30000000;$fatal(1,"tail timeout");end
endmodule
module tb_video_tail; video_tail_check test(); endmodule
module tb_video_tail_sobel; video_tail_check #(.MODE(2)) test(); endmodule
module tb_video_tail_720p; video_tail_check #(.H(720)) test(); endmodule
module tb_video_tail_stall; video_tail_check #(.TAIL_STALL(1)) test(); endmodule
module tb_video_tail_isp; video_tail_check #(.H(720),.USE_ISP(1),.TAIL_STALL(1)) test(); endmodule
module tb_video_tail_isp_sobel; video_tail_check #(.H(720),.MODE(2),.USE_ISP(1),.TAIL_STALL(1)) test(); endmodule

module tb_video_tail_isp_enhance; video_tail_check #(.H(720),.MODE(7),.USE_ISP(1),.TAIL_STALL(1)) test(); endmodule
module tb_video_tail_isp_compare; video_tail_check #(.H(720),.MODE(7),.USE_ISP(1),.TAIL_STALL(1),.COMPARE(1),.COLOUR(1)) test(); endmodule
