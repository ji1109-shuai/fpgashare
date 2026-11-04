`timescale 1ns/1ps
module tb_video_mode_osd;
    reg clk=0,rst=0,frame=0;
    reg [2:0] mode=0;
    integer m,i;
    reg [39:0] word_expected;
    hdmi_mixer #(.DISPLAY_MODES(1)) dut(.I_clk(clk),.I_rst_n(rst),
        .I_video_vsync(1'b0),.I_video_hsync(1'b0),.I_video_de(1'b0),
        .I_video_user(frame),.I_video_last(1'b0),.I_video_rd_data(24'd0),
        .I_display_mode(mode),.I_debug_status(4'd0),.I_meas_upd(1'b0),
        .I_thresh_upd(1'b0),.I_bbox_upd(1'b0),.I_roi_upd(1'b0));
    always #7 clk=~clk;
    initial begin
        repeat(3) @(negedge clk);rst=1;
        force dut.S_video_de_2d=1;
        force dut.S_y_2d=12'd360;
        for(m=0;m<8;m=m+1) begin
            mode=m;
            repeat(8) @(negedge clk);
            if(m>0 && dut.display_mode!==m-1) $fatal(1,"OSD midframe mode change");
            frame=1;@(negedge clk);frame=0;
            case(m)
                0:word_expected="RGB  ";1:word_expected="GRAY ";
                2:word_expected="SOBEL";3:word_expected="EDGE ";
                5:word_expected="ERODE";6:word_expected="DILAT";7:word_expected="ENHN ";
                default:word_expected="BIN  ";
            endcase
            for(i=0;i<5;i=i+1) begin
                force dut.S_x_2d=375+i*16;
                repeat(4) @(posedge clk);#1;
                if(dut.S_pf_char!==(word_expected>>((4-i)*8) & 8'hff)) $fatal(1,"OSD mode%0d glyph%0d",m,i);
            end
        end
        $display("ALL PASS: frame-held mode CDC and all 8 mode OSD words");$finish;
    end
    initial begin #100000;$fatal(1,"OSD timeout");end
endmodule
