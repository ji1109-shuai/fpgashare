`timescale 1ns/1ps
// Real video_in controller with bounded asynchronous FIFO fixture.
// The display-read arbitration stall is chosen so a line-paced stream fits,
// while the old immediate last-row replay overflows the 510-word capacity.
module video_modes_ddr_check #(parameter H=8,MODE=2,BLANK=160);
    reg cam=0,ddr=0,rst=0,v=0,sof=0,eol=0,early=0,busy=0;
    reg [95:0] rgb=0;
    wire [95:0] out;
    wire ov,os,ol,pv,ps,wr;
    wire [127:0] packed_data,wd;
    wire [24:0] addr;
    integer y,b,p,emitted=0,written=0,stall=0;
    always #4.444 cam=~cam;
    always #7.5 ddr=~ddr;
    img_video_modes #(.LINES_PER_FRAME(H)) fx(.I_clk(cam),.I_rst_n(rst),
        .I_tdata(rgb),.I_tvalid(v),.I_tuser(sof),.I_tlast(eol),.I_mode(MODE[1:0]),
        .O_tdata(out),.O_tvalid(ov),.O_tuser(os),.O_tlast(ol));
    data_96bit_to_128bit pack(.I_clk(cam),.I_rst_n(rst),
        .I_96b_frame_start(os),.I_96b_valid(ov),.I_96b_data({out[23:0],out[47:24],out[71:48],out[95:72]}),
        .O_128b_frame_start(ps),.O_128b_valid(pv),.O_128b_data(packed_data));
    video_in vi(.I_rst_n(rst),.I_camera_clk(cam),.I_camera_frame_start(early),
        .I_camera_valid(pv),.I_camera_data(packed_data),.I_mipi_rx_error(1'b0),
        .I_ddr_clk(ddr),.I_display_pause(1'b0),.I_video_out_rd_busy(busy),
        .O_ddr_user_wr_en(wr),.O_ddr_user_addr(addr),.O_ddr_user_wr_data(wd),.I_ddr_user_ready(!busy));
    reg [127:0] expected[0:H*240-1];
    integer accepted=0;
    always @(posedge cam) if(rst) begin
        if(pv) begin expected[accepted]=packed_data;accepted=accepted+1;end
        if(ov) begin
            if(emitted==(H-2)*320) begin busy=1;stall=500;$display("STALL start t=%0t fifo=%0d",$time,vi.U_w128_d512_fifo.wp-vi.U_w128_d512_fifo.rp);end
            emitted=emitted+1;
        end
        if(stall>0) begin stall=stall-1;if(stall==0) busy=0;end
    end
    always @(posedge ddr) if(rst && wr) begin
        if(wd!==expected[written]) $fatal(1,"DDR payload mismatch word%0d",written);
        if(addr!==written*8) $fatal(1,"DDR address discontinuity word%0d addr%0d",written,addr);
        written=written+1;
    end
    initial begin
        repeat(5) @(negedge cam);rst=1;
        repeat(5) @(negedge cam);early=1;
        @(negedge cam);early=0;repeat(55) @(negedge cam);
        for(y=0;y<H;y=y+1) begin
            for(b=0;b<320;b=b+1) begin
                @(negedge cam);v=1;sof=y==0 && b==0;eol=b==319;
                for(p=0;p<4;p=p+1) rgb[p*24+:24]=24'h010101*((y*31+b*7+p*19)%256);
            end
            @(negedge cam);v=0;sof=0;eol=0;repeat(BLANK-1) @(negedge cam);
        end
        repeat(5000) @(negedge cam);
        if(written!=H*240 || accepted!=H*240) $fatal(1,"DDR missing frame words %0d/%0d",written,accepted);
        $display("ALL PASS: mode%0d H%0d real video_in, 112.5/66.7MHz clocks, 510-word FIFO, read arbitration stall, ordered complete DDR writes, peak FIFO=%0d",MODE,H,vi.U_w128_d512_fifo.peak);$finish;
    end
    initial begin #10000000;$fatal(1,"DDR timeout");end
endmodule
module tb_video_modes_ddr;
    video_modes_ddr_check test();
endmodule
module tb_video_modes_ddr_rgb;
    video_modes_ddr_check #(.MODE(0)) test();
endmodule
module tb_video_modes_ddr_gray;
    video_modes_ddr_check #(.MODE(1)) test();
endmodule
module tb_video_modes_ddr_edge;
    video_modes_ddr_check #(.MODE(3)) test();
endmodule
module tb_video_modes_ddr_720p;
    video_modes_ddr_check #(.H(720)) test();
endmodule

module w128_d512_fifo(input rst,clkw,clkr,we,input [127:0] di,input re,
    output reg [127:0] dout=0,output valid,full_flag,empty_flag,afull,aempty,
    output [8:0] wrusedw,rdusedw);
    reg [127:0] mem[0:511];
    integer wp=0,rp=0,rs1=0,rs2=0,ws1=0,ws2=0,peak=0;
    assign valid=re;
    assign full_flag=wp-rs2>=510;assign empty_flag=ws2==rp;
    assign afull=wp-rs2>=480;assign aempty=ws2-rp<2;
    assign wrusedw=wp-rs2;assign rdusedw=ws2-rp;
    always @(posedge clkw) begin
        if(rst) begin wp=0;rs1<=0;rs2<=0;end
        else begin
            rs1<=rp;rs2<=rs1;
            if(we) begin
                if(wp-rp>=510) $fatal(1,"BOUNDED FIFO OVERFLOW at %0t: used=%0d (old tail replay burst)",$time,wp-rp);
                mem[wp%512]=di;wp=wp+1;
                if(wp-rp>peak) peak=wp-rp;
            end
        end
    end
    always @(posedge clkr) begin
        if(rst) begin rp=0;ws1<=0;ws2<=0;dout<=0;end
        else begin
            ws1<=wp;ws2<=ws1;
            if(re) begin
                if(rp>=wp) $fatal(1,"FIFO UNDERFLOW");
                dout<=mem[rp%512];rp=rp+1;
            end
        end
    end
endmodule

