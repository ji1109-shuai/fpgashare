`timescale 1ns/1ps
module industrial_ui_check #(parameter READ_LATENCY=0);
    reg clk=0,rst_n=0,de=0,sof=0,last=0,menu=1,upd=0;
    reg [3:0] selection=0;
    reg compare=0;
    reg batch_ng=0,batch_done=0,wait_clear=0;
    reg [2:0] motor=2;
    reg [3:0] ng_mask=0;
    reg [23:0] raw=0,d1=0,d2=0;
    wire [23:0] out;
    wire ov;
    integer x,y,scenario,pixels=0,fd=0,text_checks=0,background_checks=0;
    reg [127:0] expected_line;
    integer item;
    integer hx,hy,hrow,hcol,glyph_checks=0,transparent_checks=0,status_checks=0;
    reg [15:0] font_rows[0:2047];
    reg [127:0] hud_line;
    reg [7:0] hud_char;
    reg [23:0] expected_pixel,hud_color;
    reg light_bg;
    initial $readmemh("industrial_font16.hex",font_rows);
    always #5 clk=~clk;
    always @(posedge clk) begin d1<=raw;d2<=d1;end
    function automatic [23:0] background(input integer xx,yy,sc);
        background=sc>=5 && sc<9 ? 24'he2e6ea : sc==9 ? 24'h18202a : {8'(xx),8'(yy),8'(xx^yy)};
    endfunction
    hdmi_mixer #(.VIDEO_READ_LATENCY(READ_LATENCY),.TARGET_ONLY(1),.PARTS_MODE(1),
        .CAMERA_CONTROL(1),.AE_DIAGNOSTICS(1),.DISPLAY_MODES(1),.SHOW_LOGO(1),.MULTI_TARGETS(1),.LATENCY_DIAGNOSTICS(1),.FPS_DISPLAY(1)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(1'b0),.I_video_hsync(1'b0),
        .I_video_de(de),.I_video_user(sof),.I_video_last(last),.I_video_rd_data(READ_LATENCY==2 ? d2:raw),
        .I_debug_status(4'd0),.I_meas_upd(1'b0),.I_span(16'd0),.I_hole(16'd0),.I_meas_valid(1'b0),
        .I_meas_status(3'd0),.I_center_x(11'd0),.I_center_y(11'd0),.I_hole_x(11'd0),.I_hole_y(11'd0),
        .I_thresh_upd(1'b0),.I_thresh(8'd128),.I_bbox_upd(1'b0),.I_bbox_valid(1'b0),.I_bbox_moving(1'b0),
        .I_bbox_cnt(24'd0),.I_bbox_type(3'd0),.I_bbox_color(3'd0),.I_roi_upd(1'b0),.I_roi_valid(1'b0),
        .I_display_mode(3'd7),.I_camera_status({1'b0,16'h1142,12'h112}),.I_camera_status_upd(upd),
        .I_ae_diagnostics({8'd152,1'b1,1'b1,1'b1,5'd16,8'd3,1'b0}),.I_ae_diagnostics_upd(upd),
        .I_color_reference(32'd0),.I_color_reference_upd(1'b0),.I_color_diag(128'd0),.I_wb_diag(128'd0),.I_wb_diag_upd(1'b0),
        .I_targets(224'd0),.I_target_count(3'd0),.I_target_overflow(1'b0),
        .I_batch_counts_bcd(48'h001003005008),.I_batch_total_counts_bcd(48'h003004007009),
        .I_batch_targets_bcd(48'h002004006010),.I_batch_filter_type(3'd1),.I_batch_done(batch_done),
        .I_batch_overrun(batch_ng),.I_batch_overrun_mask(ng_mask),.I_batch_wait_clear(wait_clear),
        .I_enhance_strength(2'd2),.I_enhance_noise(4'd4),
        .I_enhance_compare(compare),
        .I_menu_open(menu),.I_menu_index(selection),.I_menu_preview_mode(3'd7),.I_menu_motor_level(motor),
        .I_menu_awb_freeze(1'b0),.I_menu_ae_auto(1'b1),.I_menu_ae_locked(1'b1),.I_menu_ae_target_level(5'd19),
        .I_fps_bcd(12'h030),.I_fps_update(upd),.I_latency_bcd(16'h0195),.I_latency_valid(1'b1),.I_latency_upd(upd),.O_hdmi_data(out),.O_hdmi_de(ov));
    function [127:0] option_line(input integer n);
        case(n)
            0:option_line=compare ? " VIEW    SPLIT  ":" VIEW    ENHN   ";
            1:case(motor) 1:option_line=" MOTOR   LOW 65%";2:option_line=" MOTOR   MID 80%";3:option_line=" MOTOR   HI 100%";default:option_line=" MOTOR   STOP   ";endcase
            2:option_line=" AWB     AUTO   ";3:option_line=" AE      LOCK   ";
            4:option_line=" EXP     1142   ";5:option_line=" GAIN    112    ";
            6:option_line=" SCR SET 010    ";7:option_line=" WAS SET 006    ";
            8:option_line=" HEX SET 004    ";9:option_line=" SQU SET 002    ";
            10:option_line=" NEW BATCH RESET";11:option_line=" AE Y    152    ";
            12:option_line=" DETAIL  2      ";13:option_line=" NOISE   04     ";
            14:option_line=" ACK NG  CONFIRM";default:option_line="                ";
        endcase
    endfunction
    always @(posedge clk) if(rst_n && dut.p1_is_menu && dut.c_ok && dut.c_col==0 && dut.c_row==8) begin
        if(dut.p1_diag_row==0) expected_line=selection>=8 ? "CONTROLS    2/2 ":"CONTROLS    1/2 ";
        else if(dut.p1_diag_row==9) expected_line="K1 UP  K2 DOWN  ";
        else if(dut.p1_diag_row==10) expected_line="K3 -   K4 +/ACK ";
        else begin
            item=(selection>=8 ? 8:0)+dut.p1_diag_row-1;expected_line=option_line(item);
            if(item==selection) expected_line[127:120]=">";
        end
        if(dut.c_char!==expected_line[127-dut.p1_dx[7:4]*8-:8])
            $fatal(1,"UI option mismatch scenario=%0d row=%0d col=%0d got=%c expected=%c",scenario,dut.p1_diag_row,dut.p1_dx[7:4],dut.c_char,expected_line[127-dut.p1_dx[7:4]*8-:8]);
        text_checks=text_checks+1;
    end
    always @(negedge clk) if(rst_n && ov && fd) begin
        if(pixels>=1280*720) $fatal(1,"extra UI pixels");
        if(READ_LATENCY==0) $fwrite(fd,"%c%c%c",out[23:16],out[15:8],out[7:0]);
        if((pixels%1280)>470 && (pixels%1280)<950 && (pixels/1280)>300) begin
            if(out!==background(pixels%1280,pixels/1280,scenario)) begin
                $display("UI diagnostic raw=%h d1=%h d2=%h aligned=%h p1=%h p4=%h text=%b ovl=%b logo=%b",raw,d1,d2,dut.S_aligned_video_data,dut.p1_base,dut.p4_base,dut.p4_txt_on,dut.p4_ovl,dut.p4_logo_on);
                $fatal(1,"UI changed camera payload outside overlays pixel=%0d got=%h",pixels,out);
            end
            background_checks=background_checks+1;
        end
        // Independent font/pixel oracle covers the whole old panel, all spaces,
        // row gaps, former border and removed AE rows at both DDR read latencies.
        hx=pixels%1280;hy=pixels/1280;
        if(hx>=168 && hx<440 && hy>=12 && hy<252) begin
            expected_pixel=background(hx,hy,scenario);hud_line="                ";hrow=-1;
            light_bg=(expected_pixel[23] && expected_pixel[15]) ||
                (expected_pixel[23] && expected_pixel[7]) || (expected_pixel[15] && expected_pixel[7]);
            hud_color=light_bg ? 24'h18212b:24'he6edf5;
            if(hx>=176 && hx<432 && hy>=20 && hy<216 && ((hy-20)%20)<16) begin
                hrow=(hy-20)/20;hcol=(hx-176)/16;
                case(hrow)
                    0:begin hud_line=compare ? "VIEW    SPLIT   ":"VIEW    ENHN    ";hud_color=light_bg ? 24'h005a86:24'h63c5ff;end
                    1:hud_line="EXP     1142    ";
                    2:hud_line="GAIN    112     ";
                    3:begin hud_line="PART OK/SET PASS";hud_color=light_bg ? 24'h005a86:24'h9bc5e4;end
                    4:hud_line="SCR:008/010 009 ";
                    5:hud_line="WAS:005/006 007 ";
                    6:hud_line="HEX:003/004 004 ";
                    7:hud_line="SQU:001/002 003 ";
                    8:begin
                        hud_line=motor!=0 ? "BATCH: RUN      ":"BATCH: READY    ";
                        if(batch_ng) begin hud_line="BATCH: NG STOP  ";hud_color=light_bg ? 24'hb71c1c:24'hff7b72;end
                        else if(wait_clear) begin hud_line="BATCH:CLEAR VIEW";hud_color=light_bg ? 24'h805000:24'hfff200;end
                        else if(batch_done) begin hud_line="BATCH: COMPLETE ";hud_color=light_bg ? 24'h00662f:24'h72dca2;end
                    end
                    9:hud_line="FPS     030     ";
                endcase
                if(hrow>=4 && hrow<=7) begin
                    if(batch_ng && ng_mask[hrow-4]) hud_color=light_bg ? 24'hb71c1c:24'hff7b72;
                    else if(batch_done) hud_color=light_bg ? 24'h00662f:24'h40ff80;
                    else if(hrow==4) hud_color=light_bg ? 24'h805000:24'hfff200;
                end
                hud_char=hud_line[127-hcol*8-:8];
                if(font_rows[{hud_char[6:0],4'((hy-20)%20)}][15-((hx-176)%16)]) begin
                    expected_pixel=hud_color;glyph_checks=glyph_checks+1;
                    if(hrow==8) status_checks=status_checks+1;
                end else transparent_checks=transparent_checks+1;
            end else transparent_checks=transparent_checks+1;
            if(out!==expected_pixel)
                $fatal(1,"HUD RD=%0d scenario=%0d x=%0d y=%0d row=%0d got=%h expected=%h",READ_LATENCY,scenario,hx,hy,hrow,out,expected_pixel);
        end
        pixels=pixels+1;
    end
    initial begin
        repeat(4) @(negedge clk);rst_n=1;repeat(12) @(negedge clk);upd=1;repeat(30) @(negedge clk);
        for(scenario=0;scenario<10;scenario=scenario+1) begin
            compare=scenario==4;
            menu=scenario<5 && scenario!=3;selection=scenario==1 ? 12:0;pixels=0;
            batch_ng=scenario==5 || scenario==9;ng_mask=batch_ng ? 1:0;
            batch_done=scenario==6;wait_clear=scenario==7 || scenario==9;motor=scenario==0 ? 1:scenario==2 ? 3:scenario==4 || scenario==8 ? 0:2;
            repeat(30) @(negedge clk);
            fd=$fopen($sformatf("ui_%0d_rd%0d.ppm",scenario,READ_LATENCY),"wb");
            if(!fd) $fatal(1,"UI raster output failed");
            if(READ_LATENCY==0) $fwrite(fd,"P6\n1280 720\n255\n");
            for(y=0;y<720;y=y+1) begin
                for(x=0;x<1280;x=x+1) begin
                    @(negedge clk);de=1;sof=(x==0 && y==0);last=(x==1279);raw=background(x,y,scenario);
                end
                @(negedge clk);de=0;sof=0;last=0;repeat(10) @(negedge clk);
            end
            repeat(30) @(negedge clk);$fclose(fd);fd=0;
            if(pixels!=1280*720) $fatal(1,"UI raster incomplete %0d",pixels);
        end
        if(text_checks!=704 || background_checks==0 || glyph_checks==0 || transparent_checks==0 || status_checks==0)
            $fatal(1,"UI coverage text=%0d background=%0d glyph=%0d transparent=%0d status=%0d",text_checks,background_checks,glyph_checks,transparent_checks,status_checks);
        $display("ALL PASS industrial UI: RD=%0d ten full 720p rasters, %0d menu glyphs, %0d camera pixels, %0d HUD glyph pixels, %0d transparent pixels, %0d status pixels; AE debug rows removed; NG/COMPLETE/CLEAR/RUN/READY, bright/dark contrast",READ_LATENCY,text_checks,background_checks,glyph_checks,transparent_checks,status_checks);$finish;
    end
    initial begin #200000000;$fatal(1,"UI watchdog");end
endmodule
module tb_industrial_ui;industrial_ui_check test();endmodule
module tb_industrial_ui_rd2;industrial_ui_check #(.READ_LATENCY(2)) test();endmodule
