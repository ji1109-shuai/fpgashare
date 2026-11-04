`timescale 1ns/1ps
module tb_industrial_tone;
    reg clk=0,rst_n=0,enable=0;
    reg [1:0] amount=0;
    reg [95:0] data=0;wire [95:0] out;
    integer checks=0,s,n,k,rr,gg,bb,previous;reg [23:0] expect_pixel;
    `include "../industrial_tone_reference.vh"
    always #5 clk=~clk;
    industrial_visual_tone dut(.I_clk(clk),.I_rst_n(rst_n),.I_data(data),
        .I_enable(enable),.I_strength(amount),.O_data(out));
    task check;
        begin
            @(posedge clk);#1;
            for(k=0;k<4;k=k+1) begin
                expect_pixel=enable ? tone_reference(data[k*24+:24],amount):data[k*24+:24];
                if(out[k*24+:24]!==expect_pixel) $fatal(1,"tone mismatch s%0d lane%0d in%h got%h expected%h",amount,k,data[k*24+:24],out[k*24+:24],expect_pixel);
                checks=checks+1;
            end
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(s=0;s<4;s=s+1) begin
            previous=0;
            for(n=0;n<256;n=n+1) begin
                @(negedge clk);enable=1;amount=s;
                for(k=0;k<4;k=k+1) data[k*24+:24]={8'(n),8'(n),8'(n)};
                check();
                if(out[7:0]<previous || out[7:0]!==out[15:8] || out[7:0]!==out[23:16])
                    $fatal(1,"tone nonmonotone or grey tint s%0d y%0d",s,n);
                previous=out[7:0];
            end
            for(n=0;n<4913;n=n+1) begin
                @(negedge clk);amount=s;enable=(n%19)!=0;
                for(k=0;k<4;k=k+1) begin
                    rr=((n+k*47)%17)*16;gg=(((n+k*47)/17)%17)*16;bb=(((n+k*47)/289)%17)*16;
                    if(rr>255) rr=255;if(gg>255) gg=255;if(bb>255) bb=255;
                    data[k*24+:24]={rr[7:0],gg[7:0],bb[7:0]};
                end
                check();
            end
        end
        $display("ALL PASS industrial tone: %0d lane checks, all grey levels/strengths, colour cube, clipping, bypass, changing controls",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"tone watchdog");end
endmodule
