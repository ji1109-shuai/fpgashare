`timescale 1ns/1ps
// Four canonical RGB888 pixels/beat (pixel 0 in bits 23:0).
// Modes 0 RGB, 1 gray, 2 Sobel strength, 3 thresholded Sobel.
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
    output reg [95:0] O_tdata,
    output reg O_tvalid, O_tuser, O_tlast,
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
    wire [31:0] in_gray={gray(I_tdata[95:72]),gray(I_tdata[71:48]),
                         gray(I_tdata[47:24]),gray(I_tdata[23:0])};
    reg [31:0] even_row[0:BEATS_PER_LINE-1];
    reg [31:0] odd_row[0:BEATS_PER_LINE-1];
    reg [9:0] col,flush_col;
    reg [15:0] idle_count,line_gap,flush_wait;
    reg [10:0] row;
    reg flushing;
    reg frame_start_pending;
    reg [15:0] frame_start_wait;
    reg [1:0] mode_r;
    wire [9:0] col_now=I_tuser ? 10'd0 : col;
    wire [10:0] row_now=I_tuser ? 11'd0 : row;
    wire [1:0] mode_now=I_tuser ? I_mode : mode_r;
    wire last_beat=I_tlast || col_now==BEATS_PER_LINE-1;

    // Synchronous read-before-write RAMs. No RAM reset or asynchronous read.
    reg [31:0] rd_even,rd_odd,rd_bottom;
    reg rd_valid,rd_last,rd_first,rd_topborder,rd_bottom_border,rd_parity;
    reg [1:0] rd_mode;
    always @(posedge I_clk) begin
        if(I_tvalid) begin
            rd_even<=even_row[col_now]; rd_odd<=odd_row[col_now];
            if(row_now[0]) odd_row[col_now]<=in_gray;
            else even_row[col_now]<=in_gray;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            col<=0;row<=0;flush_col<=0;flushing<=0;mode_r<=0;
            idle_count<=0;line_gap<=0;flush_wait<=0;
            frame_start_pending<=0;frame_start_wait<=0;O_frame_start<=0;
            rd_valid<=0;rd_last<=0;rd_first<=0;rd_topborder<=0;
            rd_bottom_border<=0;rd_parity<=0;rd_bottom<=0;rd_mode<=0;
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
                if(I_tuser) begin mode_r<=I_mode;flushing<=0;frame_start_pending<=0;end
                rd_valid<=row_now!=0;
                rd_last<=last_beat;rd_first<=col_now==0;
                rd_topborder<=row_now==1;rd_bottom_border<=0;
                rd_parity<=row_now[0];rd_bottom<=in_gray;rd_mode<=mode_now;
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
                rd_mode<=mode_r;
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
    reg [7:0] left_top,left_mid,left_bottom;
    reg q_valid,q_first,q_last,q_border,q_sof;
    reg [1:0] q_mode;
    wire emit=q_valid && (q_last || rd_valid);
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            q_top<=0;q_mid<=0;q_bottom<=0;
            left_top<=0;left_mid<=0;left_bottom<=0;
            q_valid<=0;q_first<=0;q_last<=0;q_border<=0;q_sof<=0;q_mode<=0;
        end else begin
            if(emit) q_valid<=0;
            if(rd_valid) begin
                q_valid<=1;q_top<=rd_top;q_mid<=rd_mid;q_bottom<=rd_bottom;
                q_first<=rd_first;q_last<=rd_last;
                q_border<=rd_topborder || rd_bottom_border;
                q_sof<=rd_topborder && rd_first;
                q_mode<=rd_mode;
                left_top<=q_top[31:24];left_mid<=q_mid[31:24];left_bottom<=q_bottom[31:24];
            end
        end
    end

    // Pipeline gradients separately from magnitude/output selection.
    reg signed [11:0] gx[0:3],gy[0:3];
    reg [3:0] s_border;
    reg s_valid,s_sof,s_last;
    reg [1:0] s_mode;
    integer p;
    reg [7:0] tl,tm,tr,ml,mr,bl,bm,br;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            s_border<=0;s_valid<=0;s_sof<=0;s_last<=0;s_mode<=0;
            for(p=0;p<4;p=p+1) begin gx[p]<=0;gy[p]<=0;end
        end else begin
            s_valid<=emit;s_sof<=emit && q_sof;s_last<=emit && q_last;
            s_mode<=q_mode;
            for(p=0;p<4;p=p+1) begin
                tl=(p==0) ? left_top : q_top[(p-1)*8+:8];
                tm=q_top[p*8+:8];
                tr=(p==3) ? rd_top[7:0] : q_top[(p+1)*8+:8];
                ml=(p==0) ? left_mid : q_mid[(p-1)*8+:8];
                mr=(p==3) ? rd_mid[7:0] : q_mid[(p+1)*8+:8];
                bl=(p==0) ? left_bottom : q_bottom[(p-1)*8+:8];
                bm=q_bottom[p*8+:8];
                br=(p==3) ? rd_bottom[7:0] : q_bottom[(p+1)*8+:8];
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
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;end
        else begin
            O_tvalid<=mode_now<2 ? I_tvalid : s_valid;
            O_tuser<=mode_now<2 ? I_tuser : s_sof;
            O_tlast<=mode_now<2 ? I_tlast : s_last;
            O_tdata<=0;
            for(k=0;k<4;k=k+1) begin
                ax=gx[k][11] ? -gx[k] : gx[k];
                ay=gy[k][11] ? -gy[k] : gy[k];
                mag=ax+ay;
                strength=s_border[k] ? 8'd0 : (mag>1020 ? 8'd255 : mag[9:2]);
                g=gray(I_tdata[k*24+:24]);
                if(mode_now<2) begin
                    if(I_tvalid) O_tdata[k*24+:24]<=mode_now==0 ? I_tdata[k*24+:24] : {g,g,g};
                end else if(s_valid) case(s_mode)
                    2: O_tdata[k*24+:24]<={strength,strength,strength};
                    3: O_tdata[k*24+:24]<=strength>=EDGE_THRESHOLD ? 24'hffffff : 24'h000000;
                endcase
            end
        end
    end
endmodule
