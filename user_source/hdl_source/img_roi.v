`timescale 1ns / 1ps
/*****************************************************************
Module Name: img_roi
Description : 背光板 ROI 两级检测的第一级：先框住白色背光区，再只在
              框内找黑色工件。
              1) 逐帧统计亮像素外接矩形（只计亮像素数 ≥ ROW_MIN 的行，
                 孤立亮噪点所在行不参与）；帧首发布并内缩 MARGIN 像素
                 （避开背光板边缘的模糊过渡带）。
              2) 用上一帧的 ROI 屏蔽本帧：ROI 外像素强制为背景
                 （亮），下游 img_proj/img_bbox 看到的就是"白底黑件"，
                 背光板外的暗区、镜头暗角不再并入工件。
              ROI 无效（亮区过小）时不屏蔽，退化为整帧测量。

插入位置    : isp_top.v 中 img_binarize 之后、img_proj/img_bbox 之前
              （仅测量支路；预览/形态学支路不经过本模块）。

时序        : 输出比输入晚 1 拍，tvalid/tuser/tlast 同步延迟。
              ROI 在 tuser 拍切换（帧内不变）。
坐标约定    : 同 img_bbox：x = 拍序*4 + 拍内像素(0..3)，[23:0]=px0。
*****************************************************************/

module img_roi #(
    parameter BEATS_PER_LINE = 320,
    parameter LINES_PER_FRAME = 720,
    parameter MARGIN   = 11'd8,     // ROI 向内收缩像素
    parameter ROW_MIN  = 11'd64,    // 行内亮像素数 ≥ 此值才算背光行
    parameter SIZE_MIN = 11'd64     // 内缩后宽/高 ≥ 此值 ROI 才有效
)(
    input                   I_clk,
    input                   I_rst_n,
    input  [95:0]           I_tdata,    // 4 像素二值图 24'hFFFFFF/24'h000000
    input                   I_tvalid,
    input                   I_tuser,
    input                   I_tlast,
    output reg [95:0]       O_tdata,    // ROI 外像素已置亮（背景）
    output reg              O_tvalid,
    output reg              O_tuser,
    output reg              O_tlast,
    output reg [10:0]       O_x0,       // 当前生效 ROI（内缩后，含边界）
    output reg [10:0]       O_x1,
    output reg [10:0]       O_y0,
    output reg [10:0]       O_y1,
    output reg              O_valid,    // 1=ROI 有效（屏蔽生效）
    output reg              O_upd       // ROI 更新翻转标志（每帧首）
);

    //---------- 位置 ----------
    reg [8:0]  beat_idx;
    reg [10:0] line_idx;
    wire [8:0]  beat_now = I_tuser ? 9'd0 : beat_idx;
    wire [10:0] line_now = I_tuser ? 11'd0 : line_idx;
    wire [10:0] x_base   = {beat_now, 2'b00};

    wire [3:0] br = {|I_tdata[95:72], |I_tdata[71:48],
                     |I_tdata[47:24], |I_tdata[23:0]};
    wire [2:0] br_cnt = br[0] + br[1] + br[2] + br[3];
    wire [10:0] xl = br[0] ? x_base :
                     br[1] ? x_base + 11'd1 :
                     br[2] ? x_base + 11'd2 : x_base + 11'd3;
    wire [10:0] xr = br[3] ? x_base + 11'd3 :
                     br[2] ? x_base + 11'd2 :
                     br[1] ? x_base + 11'd1 : x_base;

    //---------- 行累加（tuser 拍即新帧首行首拍） ----------
    reg [10:0] row_cnt, row_l, row_r;
    wire [10:0] rc_base = I_tuser ? 11'd0    : row_cnt;
    wire [10:0] rl_base = I_tuser ? 11'h7FF  : row_l;
    wire [10:0] rr_base = I_tuser ? 11'd0    : row_r;
    wire [10:0] rc_n = rc_base + {8'd0, br_cnt};
    wire [10:0] rl_n = (|br && xl < rl_base) ? xl : rl_base;
    wire [10:0] rr_n = (|br && xr > rr_base) ? xr : rr_base;
    wire        row_ok = (rc_n >= ROW_MIN);

    //---------- 帧累加 ----------
    reg        acc_any;
    reg [10:0] acc_x0, acc_x1, acc_y0, acc_y1;
    reg        frame_seen;
    // 内缩：x0+M .. x1-M（需 x1-x0 ≥ 2M+SIZE_MIN-1）
    wire [11:0] fx0 = {1'b0, acc_x0} + MARGIN;
    wire [11:0] fx1 = {1'b0, acc_x1} - MARGIN;
    wire [11:0] fy0 = {1'b0, acc_y0} + MARGIN;
    wire [11:0] fy1 = {1'b0, acc_y1} - MARGIN;
    wire roi_ok = frame_seen && acc_any &&
                  ({1'b0, acc_x1} >= fx0 + {1'b0, MARGIN} + {1'b0, SIZE_MIN} - 12'd1) &&
                  ({1'b0, acc_y1} >= fy0 + {1'b0, MARGIN} + {1'b0, SIZE_MIN} - 12'd1);

    // 生效 ROI（帧首切换）
    reg [10:0] roi_x0, roi_x1, roi_y0, roi_y1;
    reg        roi_on;
    wire [10:0] ax0 = (I_tuser ? roi_ok : roi_on) ? (I_tuser ? fx0[10:0] : roi_x0) : 11'd0;
    wire [10:0] ax1 = (I_tuser ? roi_ok : roi_on) ? (I_tuser ? fx1[10:0] : roi_x1) : 11'h7FF;
    wire [10:0] ay0 = (I_tuser ? roi_ok : roi_on) ? (I_tuser ? fy0[10:0] : roi_y0) : 11'd0;
    wire [10:0] ay1 = (I_tuser ? roi_ok : roi_on) ? (I_tuser ? fy1[10:0] : roi_y1) : 11'h7FF;
    wire        y_in = (line_now >= ay0) && (line_now <= ay1);

    reg [95:0] masked;
    integer p;
    always @* begin
        masked = I_tdata;
        for (p = 0; p < 4; p = p + 1)
            if (!(y_in && (x_base + p >= ax0) && (x_base + p <= ax1)))
                masked[p*24 +: 24] = 24'hFFFFFF;
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            beat_idx <= 9'd0; line_idx <= 11'd0;
            row_cnt <= 11'd0; row_l <= 11'h7FF; row_r <= 11'd0;
            acc_any <= 1'b0; frame_seen <= 1'b0;
            acc_x0 <= 11'd0; acc_x1 <= 11'd0; acc_y0 <= 11'd0; acc_y1 <= 11'd0;
            roi_x0 <= 11'd0; roi_x1 <= 11'h7FF; roi_y0 <= 11'd0; roi_y1 <= 11'h7FF;
            roi_on <= 1'b0;
            O_tdata <= 96'd0; O_tvalid <= 1'b0; O_tuser <= 1'b0; O_tlast <= 1'b0;
            O_x0 <= 11'd0; O_x1 <= 11'd0; O_y0 <= 11'd0; O_y1 <= 11'd0;
            O_valid <= 1'b0; O_upd <= 1'b0;
        end else begin
            O_tdata  <= masked;
            O_tvalid <= I_tvalid;
            O_tuser  <= I_tuser;
            O_tlast  <= I_tlast;
            if (I_tvalid) begin
                if (I_tuser) begin
                    // 发布上一帧亮区并切换生效 ROI
                    roi_on <= roi_ok;
                    roi_x0 <= ax0; roi_x1 <= ax1; roi_y0 <= ay0; roi_y1 <= ay1;
                    O_x0 <= fx0[10:0]; O_x1 <= fx1[10:0];
                    O_y0 <= fy0[10:0]; O_y1 <= fy1[10:0];
                    O_valid <= roi_ok;
                    O_upd <= ~O_upd;
                    frame_seen <= 1'b1;
                    acc_any <= 1'b0;
                end
                if (I_tlast) begin
                    beat_idx <= 9'd0;
                    line_idx <= line_now + 11'd1;
                    row_cnt <= 11'd0; row_l <= 11'h7FF; row_r <= 11'd0;
                    if (row_ok) begin
                        acc_any <= 1'b1;
                        if (!acc_any || I_tuser) begin
                            acc_x0 <= rl_n; acc_x1 <= rr_n;
                            acc_y0 <= line_now; acc_y1 <= line_now;
                        end else begin
                            if (rl_n < acc_x0) acc_x0 <= rl_n;
                            if (rr_n > acc_x1) acc_x1 <= rr_n;
                            acc_y1 <= line_now;
                        end
                    end
                end else begin
                    beat_idx <= beat_now + 9'd1;
                    if (I_tuser) line_idx <= 11'd0;
                    row_cnt <= rc_n; row_l <= rl_n; row_r <= rr_n;
                end
            end
        end
    end

endmodule
