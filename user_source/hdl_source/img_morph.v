`timescale 1ns / 1ps
/*****************************************************************
Module Name: img_morph
Description : 二值图像形态学 腐蚀/膨胀（3×3 方形结构元素）
              属于"邻域域"算法：需要上下左右邻居像素，因此需要行缓存。

插入位置    : isp_top.v 中 img_binarize 之后（对二值图做去噪/填孔），
              再经 SW1 的 2选1 与彩色原图切换。

数据格式    : 输入为 img_binarize 的输出：96bit = 4像素 × 24bit，
              每个像素只有 24'h000000(黑) 或 24'hFFFFFF(白)。
              模块内部把每像素压成 1 位处理，输出再展开回 24bit。

算法        : 腐蚀 = 3×3 窗口内全部为白才输出白（AND）——白区域缩小一圈，
              孤立白点/细毛刺被去除；
              膨胀 = 3×3 窗口内任一为白即输出白（OR）——白区域扩大一圈，
              小黑洞被填补。

实现结构    : 数据每拍 4 像素，3×3 窗口会跨拍，故拆成两级降维：
              H级：水平方向 3 像素归约（全时钟移位流水线，输出比输入
                   晚 2 拍，行首/行尾按"复制边界"钳位）；
              V级：垂直方向跨 3 行归约（两片 4bit 行缓存级联，
                   第0/1行缺失的历史行用近邻行复制钳位）。
              另有一条原始位直通管道（与归约管道同延迟），供直通模式使用，
              保证四种模式输出流延迟一致、帧边界切换无缝。
              关键纪律：H级数据/valid/行标志每拍无条件平移（不按 tvalid
              门控），行消隐空泡只是流过若干无效槽——若按 valid 门控，
              行首槽会携带上一行尾拍、本行尾拍丢失（板上表现为每行右端
              4 像素绕到下一行左端），且行计数失步使垂直归约失效。
              总延迟 5 拍，tvalid/tuser/tlast 与数据严格同槽对齐，
              末行输出在帧消隐期间自行涌出，无需下一帧触发。

模式 I_mode : 2'b00/2'b11 = 直通（输出原二值图）
              2'b01 = 腐蚀(AND)   2'b10 = 膨胀(OR)
              上层应在帧边界切换模式（isp_top 已按帧锁存），避免帧内混效。

边界约定    : 边缘外按最近像素复制。垂直窗口取"当前行+上方两行"，
              输出相对严格居中的结果整体下移 1 行；四级累计下移 4 行。
              原始二值测量不受影响，但形态学预览与原始坐标框有偏移。
              行内必须连续输入；本模块未实现跨行内空泡等待右邻像素。

参数        : BEATS_PER_LINE = 每行拍数 = 图像宽/4（1280/4 = 320）
*****************************************************************/

module img_morph #(
    parameter BEATS_PER_LINE = 320
)(
    input                   I_clk,
    input                   I_rst_n,
    input  [1:0]            I_mode,      // 00/11直通 01腐蚀 10膨胀
    input  [95:0]           I_tdata,
    input                   I_tvalid,
    input                   I_tuser,     // 帧起始（每帧第一拍）
    input                   I_tlast,     // 行尾（每行最后一拍）
    output reg  [95:0]      O_tdata,
    output reg              O_tvalid,
    output reg              O_tuser,
    output reg              O_tlast
);

    //---------- 0. 像素压成 1 位：bit=1 表示白 ----------
    // 拍内像素顺序：[23:0]=最左(像素0) ... [95:72]=最右(像素3)
    wire [3:0] in_bits = {|I_tdata[95:72], |I_tdata[71:48],
                          |I_tdata[47:24], |I_tdata[23:0]};

    //---------- 1. H级：水平 3 像素归约（全时钟流水线，输出比输入晚 2 拍） ----------
    // 槽位约定：第 c 拍到来时，s0=输入第 c-1 拍，s1=第 c-2 拍，in=第 c 拍；
    // 本拍寄存的 q_* 全部描述第 c-1 拍（归约中心、原始位、三个标志、有效位），
    // 因此 q_vld 跟踪的是 I_tvalid 的 1 拍延迟 tv1，与数据天然同槽。
    reg [3:0] s1_bits, s0_bits;
    reg       s0_lfirst, s0_ffirst, s0_last;  // 与 s0_bits 同槽的行/帧标志
    reg       last_seen;   // 最近一个有效拍是否行尾（行首检测用，空泡期间保持）
    reg       tv1;         // I_tvalid 延迟 1 拍

    // 行首标志 = 帧首拍 或 最近有效拍是行尾（tuser 只标帧首，行首要自己推）
    wire in_lfirst = I_tuser || last_seen;

    // 水平归约：mode[0]=1 腐蚀用 AND，否则用 OR（直通模式不用 q）
    function hred; input a, b, c;
        hred = I_mode[0] ? (a & b & c) : (a | b | c);
    endfunction

    wire [3:0] q_bits_w = {
        hred(s0_bits[2], s0_bits[3], s0_last  ? s0_bits[3] : in_bits[0]), // 像素3：行尾右钳位
        hred(s0_bits[1], s0_bits[2], s0_bits[3]),                          // 像素2
        hred(s0_bits[0], s0_bits[1], s0_bits[2]),                          // 像素1
        hred(s0_lfirst ? s0_bits[0] : s1_bits[3],
             s0_bits[0], s0_bits[1])                                       // 像素0：行首左钳位
    };

    reg [3:0] q_bits;  reg q_vld, q_lfirst, q_ffirst, q_last;
    reg [3:0] q_raw;   // 与 q_bits 同槽寄存的原始位（供直通模式，保证结构对齐）
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            {s1_bits, s0_bits, s0_lfirst, s0_ffirst, s0_last} <= 'd0;
            {last_seen, tv1} <= 'd0;
            {q_bits, q_raw, q_vld, q_lfirst, q_ffirst, q_last} <= 'd0;
        end else begin
            // 数据与标志每拍无条件平移；空泡槽由 tv1 链标记为无效，
            // 只流过、不驻留——行消隐不会改变任何槽位与数据的相对关系
            s1_bits    <= s0_bits;
            s0_bits    <= in_bits;
            s0_lfirst  <= in_lfirst;
            s0_ffirst  <= I_tuser;
            s0_last    <= I_tlast;
            last_seen  <= I_tvalid ? I_tlast : last_seen;
            tv1        <= I_tvalid;
            q_bits     <= q_bits_w;
            q_raw      <= s0_bits;
            q_vld      <= tv1;
            q_lfirst   <= s0_lfirst;
            q_ffirst   <= s0_ffirst;
            q_last     <= s0_last;
        end
    end

    //---------- 2. V级：跨 3 行归约（级联两片行缓存，各延迟一行） ----------
    // 行号计数（Q流域）：帧首清0，行尾+1 → 行首拍时 row_now 已是本行行号
    reg [10:0] row_now;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            row_now <= 'd0;
        else if (q_vld) begin
            if (q_ffirst)      row_now <= q_last ? 11'd1 : 11'd0;
            else if (q_last)   row_now <= row_now + 1'b1;
        end
    end
    wire cur_row0 = q_ffirst || (row_now == 11'd0);   // 第0行（帧首拍时 row_now 还是旧值，单独用 q_ffirst 判）
    wire cur_row1 = !cur_row0 && (row_now == 11'd1);

    wire re1 = q_vld && !cur_row0;   // 帧首不读取上一帧残留

    // 行缓存寻址：每行/帧首强制地址0，行尾复位，异常短行后可恢复。
    // 同地址"读旧写新"天然读到上一行同位置的旧值；级联两片各多延迟一行
    reg [9:0] wa, w2;
    wire [9:0] addr_now = q_lfirst ? 10'd0 : wa;
    reg       re2_r;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            wa <= 'd0; w2 <= 'd0; re2_r <= 1'b0;
        end else begin
            w2 <= addr_now; // 第二级跟随实际使用的第一片地址
            re2_r <= re1; // 第2级使能跟随第1级，延迟1拍对齐 dout1
            if (q_vld) begin
                wa <= (q_last || addr_now == BEATS_PER_LINE-1) ? 10'd0 : addr_now + 1'b1;
            end
        end
    end

    reg [3:0] ram1 [0:BEATS_PER_LINE-1];
    reg [3:0] ram2 [0:BEATS_PER_LINE-1];
    reg [3:0] dout1, dout2;
    always @(posedge I_clk) begin
        if (q_vld) begin
            ram1[addr_now] <= q_bits;         // 第1级写入当前行
            if (re1) dout1 <= ram1[addr_now]; // 同地址读旧值 = 上一行
        end
        if (re2_r) begin
            ram2[w2] <= dout1;                // 第2级写入 = 第1级读出的上一行
            dout2 <= ram2[w2];                // 读旧值 = 上上行
        end
    end

    //---------- 3. 对齐与合并（再延迟 2 拍，三路数据在同一拍汇合） ----------
    reg [3:0] cur_d1, cur_d2;   reg vld_d1, vld_d2, lf_d1, lf_d2, ff_d1, ff_d2, la_d1, la_d2;
    reg       r0_d1, r0_d2, r1_d1, r1_d2;
    reg [3:0] d1_hold;          // dout1 延迟1拍与 cur_d2/dout2 对齐
    reg [3:0] raw_d1, raw_d2;   // 直通原始位：与 cur_d1/cur_d2 完全相同的延迟级
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            {cur_d1, cur_d2, vld_d1, vld_d2, lf_d1, lf_d2, ff_d1, ff_d2, la_d1, la_d2} <= 'd0;
            {r0_d1, r0_d2, r1_d1, r1_d2, d1_hold} <= 'd0;
            {raw_d1, raw_d2} <= 'd0;
        end else begin
            cur_d1 <= q_bits;  cur_d2 <= cur_d1;
            vld_d1 <= q_vld;   vld_d2 <= vld_d1;
            lf_d1  <= q_lfirst; lf_d2 <= lf_d1;
            ff_d1  <= q_ffirst; ff_d2 <= ff_d1;
            la_d1  <= q_last;   la_d2 <= la_d1;
            r0_d1  <= cur_row0; r0_d2 <= r0_d1;
            r1_d1  <= cur_row1; r1_d2 <= r1_d1;
            d1_hold <= dout1;
            raw_d1 <= q_raw;   raw_d2 <= raw_d1;
        end
    end

    // 第0/1行历史行缺失 → 用近邻行复制钳位
    wire [3:0] d1_eff = r0_d2 ? cur_d2  : d1_hold;
    wire [3:0] d2_eff = r0_d2 ? d1_eff  : (r1_d2 ? d1_hold : dout2);

    // 垂直归约（mode[0] 选 AND/OR）+ 直通
    function vred; input a, b, c;
        vred = I_mode[0] ? (a & b & c) : (a | b | c);
    endfunction
    wire [3:0] out_bits = (I_mode == 2'b01 || I_mode == 2'b10) ?
                          {vred(cur_d2[3], d1_eff[3], d2_eff[3]),
                           vred(cur_d2[2], d1_eff[2], d2_eff[2]),
                           vred(cur_d2[1], d1_eff[1], d2_eff[1]),
                           vred(cur_d2[0], d1_eff[0], d2_eff[0])} :
                          raw_d2;   // 直通：原始二值位

    // 1位展开回 24bit 白/黑
    function [23:0] expand; input b;
        expand = b ? 24'hFFFFFF : 24'h000000;
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            {O_tvalid, O_tuser, O_tlast} <= 3'b0;
            O_tdata <= 96'd0;
        end else begin
            O_tvalid <= vld_d2;
            O_tuser  <= ff_d2;
            O_tlast  <= la_d2;
            O_tdata  <= vld_d2 ? {expand(out_bits[3]), expand(out_bits[2]),
                                  expand(out_bits[1]), expand(out_bits[0])} : 96'd0;
        end
    end

endmodule
