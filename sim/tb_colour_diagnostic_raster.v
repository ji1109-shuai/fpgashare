`timescale 1ns/1ps
module tb_colour_diagnostic_raster;
    localparam W=320,H=224;
    reg clk=0,rst=0,de=0,sof=0,eol=0,toggle=0;
    wire ode;
    wire [23:0] data;
    reg [23:0] expected[0:W*H-1];
    reg [7:0] font_char;
    reg [3:0] font_row;
    wire [15:0] font_bits;
    reg [127:0] line_text;
    reg [23:0] pixel;
    integer x,y,row,column,written=0,seen=0;
    always #7 clk=~clk;
    osd_char_lib font(.I_char(font_char),.I_row(font_row),.O_row_bits(font_bits));
    hdmi_mixer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_ONLY(1),.COLOR_DIAGNOSTICS(1)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_video_vsync(1'b0),.I_video_hsync(1'b0),
        .I_video_de(de),.I_video_user(sof),.I_video_last(eol),.I_video_rd_data(24'h556677),
        .I_color_reference(32'h07a0c080),.I_color_reference_upd(toggle),
        .I_color_diag({24'hc03020,16'h1234,16'h5678,16'h9abc,16'hdef0,16'h1357,4'd0,1'b1,1'b1,3'd1,4'd4,11'd0}),
        .I_bbox_upd(toggle),.I_bbox_valid(1'b0),.I_meas_upd(1'b0),.I_thresh_upd(1'b0),
        .I_roi_upd(1'b0),.I_roi_valid(1'b0),.I_display_mode(3'd0),.I_debug_status(4'd0),
        .O_hdmi_de(ode),.O_hdmi_data(data));
    always @(posedge clk) begin
        #1;
        if(rst && ode) begin
            if(seen>=written || data!==expected[seen])
                $fatal(1,"diagnostic raster %0d,%0d got%h expected%h",seen%W,seen/W,data,expected[seen]);
            seen=seen+1;
        end
    end
    initial begin
        repeat(4) @(negedge clk);rst=1;toggle=1;repeat(12) @(negedge clk);
        for(y=0;y<H;y=y+1) begin
            for(x=0;x<W;x=x+1) begin
                @(negedge clk);de=1;sof=x==0 && y==0;eol=x==W-1;
                pixel=24'h556677;font_char=" ";font_row=0;column=0;
                if(x>=16 && x<272 && y>=84 && y<220 && (y-84)%20<16) begin
                    row=(y-84)/20;column=(x-16)%16;
                    case(row)
                        0:line_text="WB:LOCK REF:OK  ";1:line_text="REF:A0C080      ";
                        2:line_text="RGB:C03020      ";3:line_text="R:1234 S:5678   ";
                        4:line_text="Y:9ABC K:DEF0   ";5:line_text="N:1357 F:1      ";
                        default:line_text="WHY:MIXED       ";
                    endcase
                    font_char=line_text>>((15-(x-16)/16)*8);font_row=(y-84)%20;
                    #1;pixel=font_bits[15-column] ? 24'hffffff:24'h202020;
                end
                expected[written]=pixel;written=written+1;
            end
            @(negedge clk);de=0;sof=0;eol=0;repeat(5) @(negedge clk);
        end
        repeat(30) @(negedge clk);
        if(seen!=W*H) $fatal(1,"diagnostic raster length");
        $display("ALL PASS diagnostic raster: 71680 pixels, 7 rows of independent expected text, hex numbers, unchanged background and output timing");
        $finish;
    end
    initial begin #10000000;$fatal(1,"diagnostic raster timeout");end
endmodule
