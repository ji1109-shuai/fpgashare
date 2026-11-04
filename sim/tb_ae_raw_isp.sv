`timescale 1ns/1ps
// Production RAW10 unpack, line assembly, Bayer interpolation, ISP and AE
// observer. Only vendor dual-port memory primitives have behavioural models.
module tb_ae_raw_isp;
    reg clk=0,rst_n=0,valid=0,sof=0,last=0;
    reg [39:0] raw=0;
    wire [7:0] luma;
    wire good,upd,video_valid;
    integer frame_id,x,y,p,checks=0,packets=0,video_beats=0;
    reg seen=0;
    reg [7:0] value;
    always #5 clk=~clk;
    isp_top #(.TIRE_MODE(1),.PARTS_MODE(1),.VIDEO_MODES(1),
        .AUTO_WHITE_BALANCE(1),.MULTI_TARGETS(1)) dut(
        .axi4s_video_aclk(clk),.I_rst_n(rst_n),.I_tlast(last),.I_tuser(sof),
        .I_tdata(raw),.I_tvalid(valid),.I_tdest(10'd0),.O_tready(1'b1),
        .I_bin_en(1'b0),.I_morph_mode(2'd0),.I_awb_freeze(1'b0),
        .I_camera_status(29'd0),.I_camera_status_upd(1'b0),
        .O_ae_luma(luma),.O_ae_valid(good),.O_ae_upd(upd),.O_tvalid(video_valid));
    function [7:0] expected(input integer n);
        case(n) 0:expected=72;1:expected=200;2:expected=248;default:expected=0;endcase
    endfunction
    always @(posedge clk) begin
        #1;
        if(rst_n && video_valid) video_beats=video_beats+1;
        if(rst_n && seen!=upd) begin
            seen=upd;packets=packets+1;
            if(packets>1) begin
                if(!good || luma!==expected(checks))
                    $fatal(1,"actual RAW/ISP AE packet=%0d valid=%b luma=%0d expected=%0d bad=%b xy=%0d/%0d count=%0d",
                        packets,good,luma,expected(checks),dut.u_ae_meter.bad,
                        dut.u_ae_meter.x,dut.u_ae_meter.y,dut.u_ae_meter.count);
                checks=checks+1;
            end
        end
    end
    initial begin
        repeat(8) @(negedge clk);rst_n=1;repeat(10) @(negedge clk);
        for(frame_id=0;frame_id<4;frame_id=frame_id+1) begin
            case(frame_id) 0:value=64;1:value=192;2:value=255;3:value=128;endcase
            @(negedge clk);sof=1;valid=0;last=0;
            repeat(3) @(negedge clk);sof=0;
            repeat(12) @(negedge clk);
            for(y=0;y<720;y=y+1) begin
                for(x=0;x<320;x=x+1) begin
                    @(negedge clk);valid=1;last=x==319;
                    for(p=0;p<4;p=p+1) raw[p*10+:10]={value,2'b00};
                end
                @(negedge clk);valid=0;last=0;
                repeat(100) @(negedge clk);
            end
            repeat(2000) @(negedge clk);
        end
        if(checks!=3 || packets!=4 || video_beats!=4*720*240)
            $fatal(1,"RAW/ISP output incomplete checks=%0d packets=%0d packed=%0d",checks,packets,video_beats);
        $display("ALL PASS actual RAW10 -> production demosaic -> ISP AE meter: 3 complete 720p measurements and %0d packed video beats",video_beats);
        $finish;
    end
    initial begin #30000000;$fatal(1,"RAW/ISP AE watchdog");end
endmodule

module blk_mem_gen_zhenghe(input clka,wea,input [10:0] addra,input [31:0] dia,
    input clkb,input [10:0] addrb,output reg [31:0] dob);
    reg [31:0] mem[0:2047];
    always @(posedge clka) if(wea) mem[addra]<=dia;
    always @(posedge clkb) dob<=mem[addrb];
endmodule
module blk_mem_gen_demosaic(input clka,wea,input [10:0] addra,input [32:0] dia,
    input clkb,input [10:0] addrb,output reg [32:0] dob);
    reg [32:0] mem[0:2047];
    always @(posedge clka) if(wea) mem[addra]<=dia;
    always @(posedge clkb) dob<=mem[addrb];
endmodule
