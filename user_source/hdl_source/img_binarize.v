`timescale 1ns / 1ps
/*****************************************************************
Company : 用户自研
Module Name: img_binarize
Description : RGB888 图像二值化（灰度化 + 阈值判决）
              属于"RGB 像素域"算法：只看当前单像素颜色，不需要邻居像素，
              因此无需行缓存，逻辑开销极小。

插入位置    : isp_top.v 中 u_awb 与 u_data_96bit_to_128bit 之间，
              处理的是 AWB 白平衡之后的 RGB 数据。

数据格式    : 96bit = 4 像素 x 24bit
              每个 24bit 内部为 {R[23:16], G[15:8], B[7:0]}

算法        : 1) 灰度化 gray = (R + 2G + B) >> 2
                 （亮度 Y≈0.299R+0.587G+0.114B 的移位近似，R/4+G/2+B/4）
              2) 阈值判决 pixel = gray >= 帧锁存阈值 ? 白 : 黑

握手纪律    : 纯像素域变换、固定 1 拍延迟——tdata/tvalid/tuser/tlast
              同步打一拍，相互对齐关系不变。
              本链路为推模式（tready 直通无反压），模块内部无缓冲，
              故 I_tready/O_tready 仅做直通，不参与数据流控制。

参数        : INIT_THRESHOLD 复位阈值，默认 128。
              画面全黑 = 阈值过高，调小；画面全白 = 阈值过低，调大。
*****************************************************************/

module img_binarize #(
    parameter INIT_THRESHOLD = 8'd128   // 复位初值；正常运行时阈值由 img_otsu 提供
)(
    input                   I_clk,
    input                   I_rst_n,
    input  [7:0]            I_threshold,    // 自适应阈值（img_otsu 输出，帧首锁存）

    input  [95:0]           I_tdata,    // 4 像素 RGB888
    input                   I_tvalid,
    input                   I_tuser,    // 帧起始
    input                   I_tlast,    // 行尾
    input                   I_tready,   // 本链路无反压，直通保留
    output reg  [95:0]      O_tdata,
    output reg              O_tvalid,
    output reg              O_tuser,
    output reg              O_tlast,
    output wire             O_tready
);

    // 阈值帧首锁存：整帧用同一阈值，避免帧内阈值变化造成撕裂
    reg [7:0] thresh_r;
    wire [7:0] threshold_now = I_tuser ? I_threshold : thresh_r;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)    thresh_r <= INIT_THRESHOLD;
        else if (I_tuser) thresh_r <= I_threshold;
    end

    // 单像素灰度化 + 阈值判决（组合逻辑，4 像素并行各调一次）
    function [23:0] bin_pixel;
        input [23:0] rgb;               // {R[7:0], G[7:0], B[7:0]}
        reg [9:0] gray;                 // 最大 (255+510+255)=1020，10bit 足够
        begin
            gray      = {2'b0, rgb[23:16]} + {1'b0, rgb[15:8], 1'b0} + {2'b0, rgb[7:0]};
            bin_pixel = (gray[9:2] >= threshold_now) ? 24'hFFFFFF : 24'h000000;
        end
    endfunction

    assign O_tready = I_tready;         // 无内部缓冲，ready 直通

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tdata  <= 96'd0;
            O_tvalid <= 1'b0;
            O_tuser  <= 1'b0;
            O_tlast  <= 1'b0;
        end else begin
            // 数据与三个握手信号同步打一拍，对齐关系保持不变
            O_tvalid <= I_tvalid;
            O_tuser  <= I_tuser;
            O_tlast  <= I_tlast;
            O_tdata  <= I_tvalid ? {bin_pixel(I_tdata[95:72]),   // 像素3
                                    bin_pixel(I_tdata[71:48]),   // 像素2
                                    bin_pixel(I_tdata[47:24]),   // 像素1
                                    bin_pixel(I_tdata[23: 0])}   // 像素0
                                 : 96'd0;
        end
    end

endmodule
