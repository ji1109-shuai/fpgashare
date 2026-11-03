`timescale 1ns/1ps
// Four canonical RGB888 pixels/beat (pixel 0 in bits 23:0).
// Modes 0 RGB, 1 gray, 2 Sobel strength, 3 thresholded Sobel.
// I_enhance selects luminance unsharp masking plus S-curve/chroma in mode 3.
// A Gaussian 3x3 base, soft noise threshold and +/-24 detail limit prevent
// quantization, black enhance contours and uncontrolled noise amplification.
// One RGB centre row is buffered; recognition and metering remain upstream.
// Centered 3x3 Sobel: frame border is black, no geometric displacement.
// RGB and gray are one-clock pixel pipelines, with no row replay.
// Sobel replays one row later. Drain its black final row immediately at
// half rate; waiting a whole line gap can exceed the actual frame blank.
// Allow 2*BEATS_PER_LINE+10 idle clocks before the next SOF.
// No backpressure. Valid gaps are supported.
module img_video_modes #(
    parameter BEATS_PER_LINE=320,
    parameter LINES_PER_FRAME=720,
    parameter EDGE_THRESHOLD=16,
    parameter DEBUG_CAPTURE=0
)(
    input I_clk, I_rst_n,
    input [95:0] I_tdata,
    input I_tvalid, I_tuser, I_tlast,
    input [1:0] I_mode,
    input I_enhance,
    input [1:0] I_enhance_strength,
    input [3:0] I_enhance_noise,
    input I_enhance_compare,
    output wire [95:0] O_tdata,
    output wire O_tvalid, O_tuser, O_tlast,
    // DDR boundary for row-delayed modes, before their first output beat.
    // Keep 64 clocks of guard within the previously measured line blank.
    output reg O_frame_start
);
    function [7:0] gray;
        input [23:0] rgb;
        reg [9:0] sum;
        begin
            sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
            gray=sum[9:2];
        end
    endfunction
    function [7:0] add_detail;
        input [7:0] value;
        input signed [5:0] detail;
        begin
            // The common RGB headroom bound is applied before addition.
            // Consequently the exact result is already in 0..255, and a
            // second per-channel saturator would only lengthen this path.
            add_detail=$signed({1'b0,value})+detail;
        end
    endfunction
    wire [31:0] in_gray={gray(I_tdata[95:72]),gray(I_tdata[71:48]),
                         gray(I_tdata[47:24]),gray(I_tdata[23:0])};
    // Pad the 320-beat rows to a native 512-deep memory shape and force the
    // three synchronous read-before-write stores into ERAM.  Without the TD
    // force_ram hint these short rows become hundreds of distributed-RAM LUTs
    // and make the already dense device effectively unroutable.
    (* ram_style="bram" *) reg [31:0] even_row[0:511];
    (* ram_style="bram" *) reg [31:0] odd_row[0:511];
    (* ram_style="bram" *) reg [95:0] rgb_row[0:511];
    reg [9:0] col,flush_col;
    reg [15:0] idle_count,line_gap,flush_wait;
    reg [10:0] row;
    reg flushing;
    reg frame_start_pending;
    reg [15:0] frame_start_wait;
    reg [1:0] mode_r;
    reg enhance_r;
    reg [1:0] enhance_strength_r;
    reg [3:0] enhance_noise_r;
    reg enhance_compare_r;
    wire [9:0] col_now=I_tuser ? 10'd0 : col;
    wire [10:0] row_now=I_tuser ? 11'd0 : row;
    wire [1:0] mode_now=I_tuser ? I_mode : mode_r;
    wire enhance_now=I_tuser ? I_enhance : enhance_r;
    wire last_beat=I_tlast || col_now==BEATS_PER_LINE-1;

    // Synchronous read-before-write RAMs. No RAM reset or asynchronous read.
    reg [31:0] rd_even,rd_odd,rd_bottom;
    reg [95:0] rd_rgb;
    reg rd_valid,rd_last,rd_first,rd_topborder,rd_bottom_border,rd_parity;
    reg [1:0] rd_mode;
    reg rd_enhance;
    // A single read port with its address mux before RAM inference. Two
    // mutually exclusive indexed reads otherwise infer an extra RAM port.
    wire [8:0] rgb_read_addr=I_tvalid ? col_now[8:0]:flush_col[8:0];
    always @(posedge I_clk) begin
        if(I_tvalid || (flushing && flush_wait==0)) rd_rgb<=rgb_row[rgb_read_addr];
        if(I_tvalid) begin
            rd_even<=even_row[col_now[8:0]]; rd_odd<=odd_row[col_now[8:0]];
            rgb_row[col_now[8:0]]<=I_tdata;
            if(row_now[0]) odd_row[col_now[8:0]]<=in_gray;
            else even_row[col_now[8:0]]<=in_gray;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            col<=0;row<=0;flush_col<=0;flushing<=0;mode_r<=0;enhance_r<=0;enhance_strength_r<=2;enhance_noise_r<=4;enhance_compare_r<=0;
            idle_count<=0;line_gap<=0;flush_wait<=0;
            frame_start_pending<=0;frame_start_wait<=0;O_frame_start<=0;
            rd_valid<=0;rd_last<=0;rd_first<=0;rd_topborder<=0;
            rd_bottom_border<=0;rd_parity<=0;rd_bottom<=0;rd_mode<=0;rd_enhance<=0;
        end else begin
            rd_valid<=0;
            O_frame_start<=0;
            if(frame_start_pending) begin
                if(frame_start_wait!=0) frame_start_wait<=frame_start_wait-1'b1;
                else begin O_frame_start<=1;frame_start_pending<=0;end
            end
            if(I_tvalid) begin
                idle_count<=0;
                if(col_now==0 && row_now!=0) line_gap<=idle_count;
                if(I_tuser) begin
                    mode_r<=I_mode;enhance_r<=I_enhance;flushing<=0;frame_start_pending<=0;
                    case(I_enhance_compare) 1'b1:enhance_compare_r<=1;default:enhance_compare_r<=0;endcase
                    // Explicit cases provide defaults for legacy unconnected test ports.
                    case(I_enhance_strength) 0:enhance_strength_r<=0;1:enhance_strength_r<=1;
                        2:enhance_strength_r<=2;3:enhance_strength_r<=3;default:enhance_strength_r<=2;endcase
                    case(I_enhance_noise)
                        0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15:enhance_noise_r<=I_enhance_noise;
                        default:enhance_noise_r<=4;
                    endcase
                end
                rd_valid<=row_now!=0;
                rd_last<=last_beat;rd_first<=col_now==0;
                rd_topborder<=row_now==1;rd_bottom_border<=0;
                rd_parity<=row_now[0];rd_bottom<=in_gray;rd_mode<=mode_now;rd_enhance<=enhance_now;
                if(last_beat) begin
                    col<=0;row<=row_now+1'b1;
                    // The raw sensor SOF is too early to reset the DDR FIFO:
                    // old-frame tail words can still be draining. Use the
                    // first input row plus most of its blank as that slack.
                    if(row_now==0 && mode_now>=2) begin
                        frame_start_pending<=1;
                        frame_start_wait<=line_gap>64 ? line_gap-64 : 0;
                    end
                    if(row_now==LINES_PER_FRAME-1) begin
                        flushing<=1;flush_col<=0;flush_wait<=0;
                    end
                end else begin col<=col_now+1'b1;row<=row_now;end
            end else begin
                if(idle_count!=16'hffff) idle_count<=idle_count+1'b1;
                if(flushing && flush_wait!=0) flush_wait<=flush_wait-1'b1;
                else if(flushing) begin
                rd_valid<=1;rd_last<=flush_col==BEATS_PER_LINE-1;
                rd_first<=flush_col==0;rd_topborder<=0;rd_bottom_border<=1;
                rd_mode<=mode_r;rd_enhance<=enhance_r;
                flush_wait<=1;
                if(flush_col==BEATS_PER_LINE-1) begin flushing<=0;flush_col<=0;end
                else flush_col<=flush_col+1'b1;
                end
            end
        end
    end
    wire [31:0] rd_top=rd_parity ? rd_odd : rd_even;
    wire [31:0] rd_mid=rd_parity ? rd_even : rd_odd;

    // Hold a beat until its right neighbour arrives, or emit its row tail
    // independently. This works across valid gaps and consecutive rows.
    reg [31:0] q_top,q_mid,q_bottom;
    reg [95:0] q_mid_rgb;
    reg [7:0] left_top,left_mid,left_bottom;
    reg q_valid,q_first,q_last,q_border,q_sof;
    reg [1:0] q_mode;
    reg q_enhance;
    wire emit=q_valid && (q_last || rd_valid);
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            q_top<=0;q_mid<=0;q_bottom<=0;
            left_top<=0;left_mid<=0;left_bottom<=0;
            q_valid<=0;q_first<=0;q_last<=0;q_border<=0;q_sof<=0;q_mode<=0;q_enhance<=0;q_mid_rgb<=0;
        end else begin
            if(emit) q_valid<=0;
            if(rd_valid) begin
                q_valid<=1;q_top<=rd_top;q_mid<=rd_mid;q_bottom<=rd_bottom;
                q_first<=rd_first;q_last<=rd_last;
                q_border<=rd_topborder || rd_bottom_border;
                q_sof<=rd_topborder && rd_first;
                q_mode<=rd_mode;q_enhance<=rd_enhance;q_mid_rgb<=rd_rgb;
                left_top<=q_top[31:24];left_mid<=q_mid[31:24];left_bottom<=q_bottom[31:24];
            end
        end
    end

    // Pipeline gradients separately from magnitude/output selection.
    reg signed [11:0] gx[0:3],gy[0:3];
    reg [3:0] s_border;
    reg s_valid,s_sof,s_last;
    reg [1:0] s_mode;
    reg s_enhance;
    reg [95:0] s_mid_rgb;
    reg signed [9:0] s_detail[0:3];
    reg [4:0] s_negative_room[0:3],s_positive_room[0:3];
    reg [3:0] s_luma_safe;
    integer p;
    reg [11:0] gaussian_sum;
    reg [7:0] tl,tm,tr,ml,mr,bl,bm,br;
    reg [23:0] headroom_rgb;
    reg [7:0] headroom_min,headroom_max,headroom_y;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            s_border<=0;s_valid<=0;s_sof<=0;s_last<=0;s_mode<=0;s_enhance<=0;s_mid_rgb<=0;s_luma_safe<=0;
            for(p=0;p<4;p=p+1) begin
                gx[p]<=0;gy[p]<=0;s_detail[p]<=0;
                s_negative_room[p]<=0;s_positive_room[p]<=0;
            end
        end else begin
            s_valid<=emit;s_sof<=emit && q_sof;s_last<=emit && q_last;
            s_mode<=q_mode;s_enhance<=q_enhance;s_mid_rgb<=q_mid_rgb;
            for(p=0;p<4;p=p+1) begin
                // Compute colour headroom alongside the Gaussian/gradient
                // stage, rather than serially with the final detail adder.
                // Only 0..24 is relevant because enhancement is limited to
                // +/-24. These bounds retain the original pixel latency.
                headroom_rgb=q_mid_rgb[p*24+:24];
                headroom_min=headroom_rgb[23:16]<headroom_rgb[15:8] ? headroom_rgb[23:16]:headroom_rgb[15:8];
                if(headroom_rgb[7:0]<headroom_min) headroom_min=headroom_rgb[7:0];
                headroom_max=headroom_rgb[23:16]>headroom_rgb[15:8] ? headroom_rgb[23:16]:headroom_rgb[15:8];
                if(headroom_rgb[7:0]>headroom_max) headroom_max=headroom_rgb[7:0];
                s_negative_room[p]<=headroom_min>=24 ? 5'd24:headroom_min[4:0];
                s_positive_room[p]<=headroom_max<=231 ? 5'd24:8'd255-headroom_max;
                headroom_y=gray(headroom_rgb);
                s_luma_safe[p]<=headroom_y>16 && headroom_y<240;
                tl=(p==0) ? left_top : q_top[(p-1)*8+:8];
                tm=q_top[p*8+:8];
                tr=(p==3) ? rd_top[7:0] : q_top[(p+1)*8+:8];
                ml=(p==0) ? left_mid : q_mid[(p-1)*8+:8];
                mr=(p==3) ? rd_mid[7:0] : q_mid[(p+1)*8+:8];
                bl=(p==0) ? left_bottom : q_bottom[(p-1)*8+:8];
                bm=q_bottom[p*8+:8];
                br=(p==3) ? rd_bottom[7:0] : q_bottom[(p+1)*8+:8];
                gaussian_sum={4'd0,tl}+({4'd0,tm}<<1)+{4'd0,tr}+
                    ({4'd0,ml}<<1)+({4'd0,q_mid[p*8+:8]}<<2)+({4'd0,mr}<<1)+
                    {4'd0,bl}+({4'd0,bm}<<1)+{4'd0,br};
                s_detail[p]<=$signed({2'd0,q_mid[p*8+:8]})-$signed({2'd0,gaussian_sum[11:4]});
                gx[p]<=$signed({4'b0,tr})+($signed({4'b0,mr})<<<1)+$signed({4'b0,br})
                      -$signed({4'b0,tl})-($signed({4'b0,ml})<<<1)-$signed({4'b0,bl});
                gy[p]<=$signed({4'b0,bl})+($signed({4'b0,bm})<<<1)+$signed({4'b0,br})
                      -$signed({4'b0,tl})-($signed({4'b0,tm})<<<1)-$signed({4'b0,tr});
                s_border[p]<=q_border || (q_first && p==0) || (q_last && p==3);
            end
        end
    end
    generate if(DEBUG_CAPTURE) begin : g_debug
        (* MARK_DEBUG="TRUE" *) reg [15:0] DBG_VM_FLAGS;
        (* MARK_DEBUG="TRUE" *) reg [3:0] DBG_VM_ERROR;
        (* MARK_DEBUG="TRUE" *) reg [17:0] DBG_VM_IN_BEATS,DBG_VM_OUT_BEATS,DBG_VM_PREV_OUT;
        (* MARK_DEBUG="TRUE" *) reg [31:0] DBG_VM_POSITION;
        (* MARK_DEBUG="TRUE" *) reg [15:0] DBG_VM_GAP,DBG_VM_FLUSH_WAIT;
        reg out_seen;
        reg [9:0] out_col;
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                DBG_VM_FLAGS<=0;DBG_VM_ERROR<=0;
                DBG_VM_IN_BEATS<=0;DBG_VM_OUT_BEATS<=0;DBG_VM_PREV_OUT<=0;
                DBG_VM_POSITION<=0;DBG_VM_GAP<=0;DBG_VM_FLUSH_WAIT<=0;
                out_seen<=0;out_col<=0;
            end else begin
                DBG_VM_FLAGS<={4'd0,mode_r,s_valid,q_valid,rd_valid,flushing,
                    O_tlast,O_tuser,O_tvalid,I_tlast,I_tuser,I_tvalid};
                DBG_VM_POSITION<={1'b0,row,col,flush_col};
                DBG_VM_GAP<=line_gap;DBG_VM_FLUSH_WAIT<=flush_wait;
                if(I_tuser) DBG_VM_IN_BEATS<=I_tvalid ? 18'd1 : 18'd0;
                else if(I_tvalid && DBG_VM_IN_BEATS!=18'h3ffff)
                    DBG_VM_IN_BEATS<=DBG_VM_IN_BEATS+1'b1;
                if(O_tuser) begin
                    if(out_seen && DBG_VM_OUT_BEATS!=BEATS_PER_LINE*LINES_PER_FRAME) DBG_VM_ERROR[1]<=1;
                    DBG_VM_PREV_OUT<=DBG_VM_OUT_BEATS;
                    DBG_VM_OUT_BEATS<=O_tvalid ? 18'd1 : 18'd0;
                    out_col<=O_tvalid ? (O_tlast ? 10'd0 : 10'd1) : 10'd0;out_seen<=1;
                end else if(O_tvalid && out_seen) begin
                    if(DBG_VM_OUT_BEATS!=18'h3ffff) DBG_VM_OUT_BEATS<=DBG_VM_OUT_BEATS+1'b1;
                    out_col<=O_tlast ? 10'd0 : out_col+1'b1;
                end
                if(I_tuser && flushing) DBG_VM_ERROR[0]<=1;
                if(I_tvalid && I_tlast!=(col_now==BEATS_PER_LINE-1)) DBG_VM_ERROR[2]<=1;
                if(O_tvalid && O_tlast!=((O_tuser ? 10'd0 : out_col)==BEATS_PER_LINE-1)) DBG_VM_ERROR[3]<=1;
            end
        end
    end endgenerate
    integer k;
    reg [11:0] ax,ay,mag;
    reg [7:0] strength,g;
    reg [23:0] centre;
    reg signed [5:0] detail_delta;
    reg [7:0] detail_mag;
    reg [8:0] scaled_detail;
    reg [4:0] detail_room;
    reg [95:0] render_data;
    reg render_valid,render_sof,render_last,render_tone;
    reg [1:0] render_strength;
    reg [9:0] enhance_out_col;
    wire [9:0] enhance_col_now=s_sof ? 10'd0:enhance_out_col;
    wire compare_raw=enhance_compare_r && enhance_col_now<BEATS_PER_LINE/2;
    wire [95:0] toned_data;
    reg toned_valid,toned_sof,toned_last;
    // Only ENHN gains one pipeline clock. Preserve every legacy mode's
    // cadence, including the ISP gray path aligned with AWB's d1 registers.
    wire tone_frame=enhance_r && mode_r==3;
    assign O_tdata=tone_frame ? toned_data:render_data;
    assign O_tvalid=tone_frame ? toned_valid:render_valid;
    assign O_tuser=tone_frame ? toned_sof:render_sof;
    assign O_tlast=tone_frame ? toned_last:render_last;
    industrial_visual_tone u_visual_tone(.I_clk(I_clk),.I_rst_n(I_rst_n),
        .I_data(render_data),.I_enable(render_tone),.I_strength(render_strength),.O_data(toned_data));
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin toned_valid<=0;toned_sof<=0;toned_last<=0;end
        else begin toned_valid<=render_valid;toned_sof<=render_sof;toned_last<=render_last;end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin render_data<=0;render_valid<=0;render_sof<=0;render_last<=0;render_tone<=0;render_strength<=0;enhance_out_col<=0;end
        else begin
            render_valid<=mode_now<2 ? I_tvalid : s_valid;
            render_sof<=mode_now<2 ? I_tuser : s_sof;
            render_last<=mode_now<2 ? I_tlast : s_last;
            render_data<=0;
            render_tone<=mode_now>=2 && s_enhance && s_mode==3 && enhance_strength_r!=0 && !compare_raw;
            render_strength<=enhance_strength_r;
            if(s_valid) enhance_out_col<=s_last ? 10'd0:enhance_col_now+1'b1;
            for(k=0;k<4;k=k+1) begin
                ax=gx[k][11] ? -gx[k] : gx[k];
                ay=gy[k][11] ? -gy[k] : gy[k];
                mag=ax+ay;
                strength=s_border[k] ? 8'd0 : (mag>1020 ? 8'd255 : mag[9:2]);
                g=gray(I_tdata[k*24+:24]);
                if(mode_now<2) begin
                    if(I_tvalid) render_data[k*24+:24]<=mode_now==0 ? I_tdata[k*24+:24] : {g,g,g};
                end else if(s_valid) case(s_mode)
                    2: render_data[k*24+:24]<={strength,strength,strength};
                    3: begin
                        if(s_enhance) begin
                            centre=s_mid_rgb[k*24+:24];
                            detail_mag=s_detail[k]<0 ? -s_detail[k] : s_detail[k];
                            scaled_detail=0;
                            if(!s_border[k] && s_luma_safe[k] && detail_mag>enhance_noise_r) begin
                                detail_mag=detail_mag-enhance_noise_r;
                                case(enhance_strength_r)
                                    0:scaled_detail=0;
                                    1:scaled_detail=detail_mag>>1;
                                    2:scaled_detail=detail_mag;
                                    3:scaled_detail={1'b0,detail_mag}+({1'b0,detail_mag}>>1);
                                endcase
                                if(scaled_detail>24) scaled_detail=24;
                                detail_room=s_detail[k]<0 ? s_negative_room[k]:s_positive_room[k];
                                if(scaled_detail>detail_room) scaled_detail=detail_room;
                            end
                            // Limit the common RGB offset before addition: no channel
                            // clipping, so channel differences/chroma are preserved.
                            detail_delta=s_detail[k]<0 ? -$signed({1'b0,scaled_detail[4:0]}):
                                $signed({1'b0,scaled_detail[4:0]});
                            render_data[k*24+:24]<=compare_raw ? centre:{add_detail(centre[23:16],detail_delta),
                                add_detail(centre[15:8],detail_delta),add_detail(centre[7:0],detail_delta)};
                        end else render_data[k*24+:24]<=strength>=EDGE_THRESHOLD ? 24'hffffff:24'h000000;
                    end
                endcase
            end
        end
    end
endmodule

// Display-only weighted-luma S-curve and 1.25x chroma. Strength 0 bypasses;
// 1/2/3 use middle slopes 1.25/1.625/1.75 and outer slopes .75/.375/.25.
module industrial_visual_tone(
    input I_clk,I_rst_n,
    input [95:0] I_data,
    input I_enable,
    input [1:0] I_strength,
    output reg [95:0] O_data
);
    function [7:0] clip;
        input signed [12:0] v;
        begin if(v<0) clip=0;else if(v>255) clip=255;else clip=v[7:0];end
    endfunction
    function [12:0] high_curve;
        input [7:0] d;input [1:0] amount;
        reg [12:0] w;
        begin
            w={5'd0,d};
            case(amount)
                1:high_curve=w+((w+2)>>2);
                2:high_curve=w+(((w<<2)+w+4)>>3);
                default:high_curve=w+(((w<<1)+w+2)>>2);
            endcase
        end
    endfunction
    function [12:0] low_curve;
        input [7:0] d;input [1:0] amount;
        reg [12:0] w;
        begin
            w={5'd0,d};
            case(amount)
                1:low_curve=((w<<1)+w+2)>>2;
                2:low_curve=((w<<1)+w+4)>>3;
                default:low_curve=(w+2)>>2;
            endcase
        end
    endfunction
    function [7:0] channel;
        input [7:0] c,y,ye;
        reg signed [12:0] chroma,value;
        begin
            chroma=$signed({1'b0,c})-$signed({1'b0,y});
            value=$signed({1'b0,ye})+chroma+(chroma>>>2);
            channel=clip(value);
        end
    endfunction
    reg [95:0] source;
    reg [7:0] stage_y[0:3],stage_ye[0:3];
    reg enabled;
    integer p,q;
    reg [7:0] y;reg signed [12:0] ye;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            source<=0;enabled<=0;
            for(p=0;p<4;p=p+1) begin stage_y[p]<=0;stage_ye[p]<=0;end
        end else begin
            source<=I_data;enabled<=I_enable && I_strength!=0;
            for(p=0;p<4;p=p+1) begin
                y=({2'b0,I_data[p*24+16+:8]}+{1'b0,I_data[p*24+8+:8],1'b0}+{2'b0,I_data[p*24+:8]})>>2;
                if(y<64) ye=low_curve(y,I_strength);
                else if(y<128) ye=13'sd128-high_curve(8'd128-y,I_strength);
                else if(y<192) ye=13'sd128+high_curve(y-8'd128,I_strength);
                else ye=13'sd128+high_curve(8'd64,I_strength)+low_curve(y-8'd192,I_strength);
                stage_y[p]<=y;stage_ye[p]<=clip(ye);
            end
        end
    end
    always @* begin
        O_data=source;
        for(q=0;q<4;q=q+1) if(enabled) begin
            O_data[q*24+16+:8]=channel(source[q*24+16+:8],stage_y[q],stage_ye[q]);
            O_data[q*24+8+:8]=channel(source[q*24+8+:8],stage_y[q],stage_ye[q]);
            O_data[q*24+:8]=channel(source[q*24+:8],stage_y[q],stage_ye[q]);
        end
    end
endmodule
