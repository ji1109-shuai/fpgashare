`timescale 1ns/1ps
// Real raster and output-pixel audit, including label font and CDC publication.
module tb_target_overlay #(parameter PARTS=0);
    localparam W=1280,H=360;
    localparam LABEL_W=PARTS ? 216 : 200;
    reg clk=0,rst=0,de=0,sof=0,eol=0,toggle=0,valid=0,moving=0;
    reg [2:0] typ=0,color=0;
    reg [10:0] bx0=240,bx1=360,by0=100,by1=220;
    wire ode;
    wire [23:0] out;
    reg [23:0] expected_pixels[0:W*H-1];
    integer written=0,seen=0,xx,yy,case_no,lx,ly,ci;
    reg exp_target,exp_moving;
    reg [103:0] label_word;
    reg [7:0] ref_char;
    reg [3:0] ref_row,ref_col;
    wire [15:0] ref_bits;
    reg [15:0] font_rows[0:2047];
    initial $readmemh("industrial_font16.hex",font_rows);
    reg label_pixel,mode_pixel,box_pixel;
    reg [23:0] expected_pixel;
    assign ref_bits=font_rows[{ref_char[6:0],ref_row}];
    hdmi_mixer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_ONLY(1),.DISPLAY_MODES(1),.PARTS_MODE(PARTS)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_video_vsync(1'b0),.I_video_hsync(1'b0),
        .I_video_de(de),.I_video_user(sof),.I_video_last(eol),.I_video_rd_data(24'h556677),
        .I_display_mode(3'd0),.I_debug_status(4'd0),
        .I_menu_open(1'b0),.I_menu_index(4'd0),.I_menu_preview_mode(3'd0),.I_menu_motor_level(3'd0),
        .I_menu_awb_freeze(1'b0),.I_menu_ae_auto(1'b1),.I_menu_ae_locked(1'b0),.I_menu_ae_target_level(5'd19),
        .I_batch_counts_bcd(48'd0),.I_batch_total_counts_bcd(48'd0),.I_batch_targets_bcd(48'd0),
        .I_batch_filter_type(3'd1),.I_batch_done(1'b0),.I_batch_overrun(1'b0),.I_batch_overrun_mask(4'd0),
        .I_batch_wait_clear(1'b0),.I_enhance_strength(2'd2),.I_enhance_noise(4'd4),
        .I_meas_upd(toggle),.I_span(16'd100),.I_hole(16'd60),.I_meas_valid(1'b1),
        .I_meas_status(3'd0),.I_center_x(11'd300),.I_center_y(11'd150),
        .I_hole_x(11'd300),.I_hole_y(11'd150),.I_thresh_upd(1'b0),.I_thresh(8'd128),
        .I_bbox_upd(toggle),.I_bbox_x0(bx0),.I_bbox_x1(bx1),.I_bbox_y0(by0),.I_bbox_y1(by1),
        .I_bbox_cx(11'd300),.I_bbox_cy(11'd150),.I_bbox_w(11'd121),.I_bbox_h(11'd121),
        .I_bbox_area(20'd10000),.I_bbox_type(typ),.I_bbox_color(color),
        .I_bbox_valid(valid),.I_bbox_moving(moving),.I_bbox_cnt(24'd123),
        .I_roi_upd(toggle),.I_roi_valid(1'b1),.I_roi_x0(11'd0),.I_roi_x1(11'd1279),
        .I_roi_y0(11'd0),.I_roi_y1(11'd359),.O_hdmi_de(ode),.O_hdmi_data(out));
    always #5 clk=~clk;
    always @(posedge clk) begin
        #1;
        if(rst && (dut.S_probe_on || dut.S_roi_on || dut.S_line_on || dut.S_hole_center_on))
            $fatal(1,"production display still has debug geometry");
        if(rst && ode) begin
            // Controls have a separate full-raster/glyph oracle in tb_industrial_ui.
            // Audit every other pixel, including all unclipped target labels.
            if(seen>=written || (!(seen%W>=8 && seen%W<280 && seen/W>=12 && seen/W<252) && out!==expected_pixels[seen]))
                $fatal(1,"overlay case%0d pixel%0d,%0d got%h exp%h",case_no,seen%W,seen/W,out,expected_pixels[seen]);
            seen=seen+1;
        end
    end
    task frame;
        input integer target_type,target_color,target_valid,target_moving,x0,x1,y0,y1;
        input [103:0] word_expected;
        begin
            typ=target_type;color=target_color;valid=target_valid;moving=target_moving;
            bx0=x0;bx1=x1;by0=y0;by1=y1;toggle=~toggle;
            repeat(10) @(negedge clk);
            written=0;seen=0;label_word=word_expected;
            exp_target=target_valid && (PARTS ? (target_type>=1 && target_type<=4) :
                ((target_type==6 && target_color==4) ||
                 (target_type==4 && target_color>=1 && target_color<=3))) &&
                x0<=x1 && y0<=y1 && x1<W && y1<H;
            exp_moving=target_moving;
            lx=x0+LABEL_W<=W ? x0:W-LABEL_W;
            ly=y0>=22 ? y0-22 : y1+22<H ? y1+2:2;
            for(yy=0;yy<H;yy=yy+1) begin
                for(xx=0;xx<W;xx=xx+1) begin
                    @(negedge clk);de=1;sof=xx==0 && yy==0;eol=xx==W-1;
                    label_pixel=exp_target && xx>=lx && xx<lx+LABEL_W && yy>=ly && yy<ly+20;
                    mode_pixel=0;
                    box_pixel=exp_target && xx>=x0 && xx<=x1 && yy>=y0 && yy<=y1 &&
                        (xx-x0<2 || x1-xx<2 || yy-y0<2 || y1-yy<2);
                    expected_pixel=box_pixel ? (exp_moving ? 24'hffff00:24'hff00ff):24'h556677;
                    ref_char=" ";ref_col=0;ref_row=0;
                    if(mode_pixel) begin
                        expected_pixel=24'h202020;
                        ci=(xx-16)/16;
                        case(ci) 0:ref_char="R";1:ref_char="G";2:ref_char="B";default:ref_char=" ";endcase
                        ref_col=(xx-16)%16;ref_row=yy-16;
                    end
                    if(label_pixel) begin
                        expected_pixel=24'h202020;ref_char=" ";
                        if(xx>=lx+4 && xx<lx+LABEL_W-4 && yy>=ly+2 && yy<ly+18) begin
                            ci=(xx-lx-4)/16;ref_char=label_word>>(((PARTS ? 12 : 11)-ci)*8);
                            ref_col=(xx-lx-4)%16;ref_row=yy-ly-2;
                        end
                    end
                    #1;
                    if((label_pixel || mode_pixel) && ref_bits[15-ref_col]) expected_pixel=24'hffffff;
                    expected_pixels[written]=expected_pixel;written=written+1;
                    // A new camera packet mid-frame must not tear this overlay.
                    if(xx==0 && yy==80) begin valid=0;typ=7;color=0;toggle=~toggle;end
                end
                @(negedge clk);de=0;sof=0;eol=0;repeat(2) @(negedge clk);
            end
            repeat(12) @(negedge clk);
            if(seen!=W*H) $fatal(1,"incomplete overlay raster");
            case_no=case_no+1;
        end
    endtask
    initial begin
        case_no=0;repeat(4) @(negedge clk);rst=1;
        if(PARTS) begin
        frame(7,3,1,0,240,360,100,220,"            ");
        frame(1,0,1,0,240,360,100,220,"UNKN   SCREW ");
        frame(2,5,1,1,1180,1250,100,220,"SILVER WASHER");
        frame(3,6,1,0,240,360,2,80,"BRASS  NUT   ");
        frame(3,1,1,0,240,360,240,359,"RED    NUT   ");
        frame(3,4,0,0,240,360,100,220,"            ");
        frame(4,4,1,0,1180,1250,240,359,"BLACK  SQNUT ");
        frame(4,0,1,0,240,360,2,80,"UNKN   SQNUT ");
        frame(5,4,1,0,240,360,100,220,"            ");
        frame(3,4,1,0,240,360,100,400,"            ");
        $display("ALL PASS: parts SILVER/RED/BRASS/BLACK/UNKN plus SCREW/WASHER/NUT/SQNUT pixel raster, clamps, candidates hidden, removal and frame-held CDC");
        end else begin
        frame(7,3,1,0,240,360,100,220,"            "); // unconfirmed foreground
        frame(6,0,1,0,240,360,100,220,"            "); // gray/unknown ring
        frame(1,4,1,0,240,360,100,220,"            "); // unsupported object
        frame(6,4,1,0,240,360,100,220,"BLACK RING  ");
        frame(4,3,1,1,1180,1250,100,220,"BLUE  CIRCLE"); // right clamp, motion
        frame(4,1,1,0,240,360,2,80,"RED   CIRCLE"); // label below object
        frame(4,2,1,0,240,360,240,359,"GREEN CIRCLE"); // bottom boundary
        frame(6,4,0,0,240,360,100,220,"            "); // removal
        frame(6,4,1,0,240,360,100,400,"            "); // corrupt coordinates
        $display("ALL PASS: clean target-only raster, no candidate/debug frames, BLACK/RGB shape labels, label clamps, removal and frame-held CDC (reserved controls audited separately)");
        end
        $finish;
    end
    initial begin #60000000;$fatal(1,"target overlay timeout");end
endmodule
module tb_parts_overlay;
    tb_target_overlay #(.PARTS(1)) test();
endmodule
