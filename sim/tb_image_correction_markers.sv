`timescale 1ns/1ps
// Exercise the actual native RAW -> AXIS -> correction stages. Blanking is
// deliberately longer than the old correction module's 8-bit idle counter.
module tb_image_correction_markers;
    reg clk=0,rst_n=0,native_valid=0,native_sof=0;
    reg [39:0] native_data=0;
    always #5 clk=~clk;
    wire av,au,al,ov,ou,ol;
    wire [39:0] ad,od;
    uial2axis #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.INPUT_DATA_WIDTH(40)) axis(
        .I_native_clk(clk),.I_rst_n(rst_n),.I_data(native_data),
        .I_data_valid(native_valid),.I_data_start(native_sof),.I_data_end(1'b0),
        .axis_tvalid(av),.axis_tuser(au),.axis_tlast(al),.axis_tdata(ad));
    image_correction #(.DATA_WIDTH(40)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_raw_data(ad),.I_raw_valid(av),
        .I_raw_frame_start(au),.I_raw_frame_end(al),.O_raw_tdata(od),
        .O_raw_tvalid(ov),.O_raw_tuser(ou),.O_raw_tlast(ol),.O_raw_tready(1'b1));
    integer checks=0,frame_id=0,row=0,col=0,received=0;
    reg ev,eu,el;
    reg [39:0] ed;
    always @(posedge clk) begin
        if(rst_n) begin
            ev=av;eu=au;el=al;ed=ad;
            #1;
            if(ov!==ev || (ev && (ou!==eu || ol!==el || od!==ed)))
                $fatal(1,"correction drops/retags RAW frame=%0d row=%0d col=%0d in=%b/%b/%b out=%b/%b/%b",frame_id,row,col,ev,eu,el,ov,ou,ol);
            if(ov) received=received+1;
            checks=checks+1;
        end
    end
    task idle(input integer cycles);
        begin
            @(negedge clk);native_valid=0;native_sof=0;
            repeat(cycles) @(negedge clk);
        end
    endtask
    task frame(input integer blank_cycles);
        integer before_count;
        begin
            before_count=received;
            @(negedge clk);native_sof=1;native_valid=0;
            @(negedge clk);native_sof=0;
            for(row=0;row<720;row=row+1) begin
                for(col=0;col<320;col=col+1) begin
                    @(negedge clk);native_valid=1;native_data={8'(frame_id),16'(row),16'(col)};
                    @(negedge clk);native_valid=0;
                end
                idle(blank_cycles);
            end
            idle(32);
            if(received-before_count!=720*320)
                $fatal(1,"incomplete corrected frame received=%0d",received-before_count);
            frame_id=frame_id+1;
        end
    endtask
    initial begin
        idle(8);rst_n=1;idle(1024);
        frame(16);idle(4096);frame(600);idle(4096);frame(1024);
        $display("ALL PASS native RAW/AXIS/correction: three complete 720p frames, short/long blanking, unchanged data and one-cycle markers (%0d checks)",checks);
        $finish;
    end
    initial begin #100000000;$fatal(1,"correction marker watchdog");end
endmodule
