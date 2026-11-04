`timescale 1ns/1ps
module tb_industrial_photo;
    localparam W=608,H=288,B=W/4;
    reg clk=0,rst_n=0,v=0,sof=0,last=0,compare=0;
    reg [1:0] amount=0;reg [95:0] data=0;wire [95:0] out;wire ov,os,ol;
    reg [23:0] source_pixels[0:W*H-1],expected_pixels[0:W*H-1];
    integer s,y,b,p,pixels=0,fd=0,checks=0;
    always #5 clk=~clk;
    img_video_modes #(.BEATS_PER_LINE(B),.LINES_PER_FRAME(H)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_tdata(data),.I_tvalid(v),.I_tuser(sof),.I_tlast(last),
        .I_mode(2'd3),.I_enhance(1'b1),.I_enhance_strength(amount),.I_enhance_noise(4'd4),
        .I_enhance_compare(compare),.O_tdata(out),.O_tvalid(ov),.O_tuser(os),.O_tlast(ol));
    always @(negedge clk) if(rst_n && ov) begin
        if(os!==(pixels==0) || ol!==((pixels%W)==W-4)) $fatal(1,"photo markers");
        for(integer k=0;k<4;k=k+1) begin
            if(out[k*24+:24]!==expected_pixels[pixels+k]) $fatal(1,"photo mismatch s%0d pixel%0d got%h expected%h",s,pixels+k,out[k*24+:24],expected_pixels[pixels+k]);
            $fwrite(fd,"%c%c%c",out[k*24+16+:8],out[k*24+8+:8],out[k*24+:8]);checks=checks+1;
        end
        pixels=pixels+4;
    end
    initial begin
        $readmemh("../visual_upgrade_20261102_validation/photo_input.hex",source_pixels);
        repeat(4) @(negedge clk);rst_n=1;
        for(s=0;s<5;s=s+1) begin
            amount=s==4 ? 2:s;compare=s==4;pixels=0;
            $readmemh($sformatf("../visual_upgrade_20261102_validation/photo_expected_%0d.hex",s),expected_pixels);
            fd=$fopen($sformatf("photo_rtl_%0d.ppm",s),"wb");if(!fd) $fatal(1,"photo output");
            $fwrite(fd,"P6\n608 288\n255\n");
            for(y=0;y<H;y=y+1) begin
                for(b=0;b<B;b=b+1) begin
                    @(negedge clk);v=1;sof=y==0 && b==0;last=b==B-1;
                    for(p=0;p<4;p=p+1) data[p*24+:24]=source_pixels[y*W+b*4+p];
                end
                @(negedge clk);v=0;sof=0;last=0;repeat(80) @(negedge clk);
            end
            repeat(2*B+30) @(negedge clk);$fclose(fd);fd=0;
            if(pixels!=W*H) $fatal(1,"photo length");
        end
        $display("ALL PASS photo RTL: %0d independently checked colour pixels, four strengths and split, actual RTL rasters exported",checks);$finish;
    end
    initial begin #10000000;$fatal(1,"photo watchdog");end
endmodule
