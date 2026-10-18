`timescale 1ns / 1ps
/*****************************************************************
Module Name: img_bbox
Description : 前景最小外接矩形（Bounding Box）+ 运动检测 + 工件计数。
              属于"像素域统计 + 帧间量"算法：逐拍检查 4 个像素是否为
              前景（FG_IS_WHITE 选择黑/白），维护 xmin/xmax/ymin/ymax；
              帧发布时计算中心/宽高，与上一帧中心比较得运动标志，
              并检测中心是否左→右越过虚拟检测线（带回滞防抖）计数。

插入位置    : isp_top.v 中与 img_proj 并联，同取 img_binarize 输出
              （bin_O_*，形态学之前的原始二值几何——SW2/SW3 只影响
              预览不影响测量，与 W/I 读数同一数据源）。

坐标约定    : x = 拍内像素序(0..3) + 行内拍序*4，0..1279；
              y = 行序 0..719。tuser 拍即帧首行首拍。

运动检测    : moving = |Δcx| + |Δcy| >= MOTION_THRESH（曼哈顿距离，
              免乘法）。仅相邻两帧均完整且有前景时比较；空帧或
              异常帧打断历史，下一有效目标的首次出现不报运动。

工件计数    : 计数事件 = 前帧有效 && 本帧有效 && 中心从 LINE_X 左侧
              越到右侧。armed 回滞：计数后需退回 LINE_X-LINE_HYST
              左侧才重新武装，防止工件停在线上时阈值抖动重复计数。
              空帧/异常帧重新武装；假设画面中至多一个连续工件。
              BCD 六位直接输出（mixer 的 CNT 数字直读，免译码）。

发布时序    : 下一帧有效 tuser 拍发布上一帧并翻转 O_upd；与 img_proj
              的帧尾发布不同。保留下一帧发布以检查帧尾后的多余数据。
              每行必须恰好 BEATS_PER_LINE 拍且有 tlast，恰好
              LINES_PER_FRAME 行。空帧/异常帧 valid=0、几何清零。
*****************************************************************/

module img_bbox #(
    parameter BEATS_PER_LINE = 320,
    parameter LINES_PER_FRAME = 720,
    parameter FG_IS_WHITE = 1,
    parameter LINE_X        = 11'd640,  // 虚拟检测线 x（mixer 的竖线画在同处，两处需一致）
    parameter LINE_HYST     = 11'd32,   // 越线回滞（像素）
    parameter MOTION_THRESH = 11'd4,    // 帧间中心位移≥此值判"运动中"（曼哈顿距离）
    parameter HOLE_MIN      = 16'd6,    // img_proj 孔径≥此值才算"有孔"（防噪）
    parameter AREA_MIN      = 20'd2     // 目标门控：面积小于此视为噪声（单像素噪点被拒；主力防噪是填充率门控）
)(
    input                   I_clk,
    input                   I_rst_n,
    input  [95:0]           I_tdata,    // 4 像素二值图 24'hFFFFFF/24'h000000
    input                   I_tvalid,
    input                   I_tuser,    // 帧起始（帧首行首拍）
    input                   I_tlast,    // 行尾
    input  [15:0]           I_hole,     // img_proj 的孔径测量（同帧一致）
    input                   I_hole_valid,
    output reg [10:0]       O_x0,       // 外接矩形最左像素 x
    output reg [10:0]       O_x1,       // 最右像素 x
    output reg [10:0]       O_y0,       // 最上像素 y
    output reg [10:0]       O_y1,       // 最下像素 y
    output reg [10:0]       O_cx,       // 外接矩形中心 x（仅 valid 时有意义）
    output reg [10:0]       O_cy,       // 中心 y
    output reg [10:0]       O_w,        // 外接矩形宽（像素）
    output reg [10:0]       O_h,        // 高
    output reg [19:0]       O_area,     // 框内前景像素数（二值；分类用原始量）
    output reg [2:0]        O_type,     // 几何分类：0NONE 1BAR 2RING 3NUT 4DISC 5BLOCK
    output reg              O_moving,   // 1=工件运动中（帧间位移超阈值）
    output wire [23:0]      O_cnt_bcd,  // 工件计数 BCD {d5,d4,d3,d2,d1,d0}
    output reg              O_valid,    // 本帧存在前景
    output reg              O_upd       // 结果更新翻转标志
);

    localparam T_NONE = 3'd0, T_BAR = 3'd1, T_RING = 3'd2,
               T_NUT  = 3'd3, T_DISC = 3'd4, T_BLOCK = 3'd5;

    //---------- 位置跟踪 ----------
    // beat_idx = 当前拍在行内的序号（tuser 拍 = 0；行间空泡不推进）
    reg [8:0]  beat_idx;
    reg [10:0] line_idx;
    wire [8:0]  beat_now = I_tuser ? 9'd0 : beat_idx;
    wire [10:0] line_now = I_tuser ? 11'd0 : line_idx;
    wire [10:0] x_base   = {beat_now, 2'b00};          // 本拍像素0的x = 拍序*4

    //---------- 前景判定：拍内 4 像素，[23:0]=最左(px0) ... [95:72]=最右(px3) ----------
    wire [3:0] white_bits = {|I_tdata[95:72], |I_tdata[71:48],
                            |I_tdata[47:24], |I_tdata[23:0]};
    wire [3:0] fg = FG_IS_WHITE ? white_bits : ~white_bits;
    wire       beat_fg = I_tvalid && (|fg);
    wire [2:0] fg_cnt = fg[0] + fg[1] + fg[2] + fg[3];   // 本拍前景像素数 0..4

    // 本拍最左/最右前景像素的 x（仅 beat_fg 时有效）
    wire [10:0] xl = fg[0] ? x_base :
                     fg[1] ? x_base + 11'd1 :
                     fg[2] ? x_base + 11'd2 : x_base + 11'd3;
    wire [10:0] xr = fg[3] ? x_base + 11'd3 :
                     fg[2] ? x_base + 11'd2 :
                     fg[1] ? x_base + 11'd1 : x_base;
    // 对角坐标：u=x+y、v=x−y 的极值都落在本拍最左/最右前景像素上
    localparam [11:0] V_OFS = LINES_PER_FRAME - 1;
    wire [11:0] ul = {1'b0, xl} + {1'b0, line_now};
    wire [11:0] ur = {1'b0, xr} + {1'b0, line_now};
    wire [11:0] vl = {1'b0, xl} + V_OFS - {1'b0, line_now};
    wire [11:0] vr = {1'b0, xr} + V_OFS - {1'b0, line_now};

    //---------- 累加器 ----------
    reg        frame_run;    // 本帧已出现过前景（acc 内容有效）
    reg        frame_seen;   // 只表示见过帧头，完整性另由 complete/bad 决定
    reg        frame_complete, frame_bad;
    wire frame_good = frame_seen && frame_complete && !frame_bad;
    reg [10:0] acc_x0, acc_x1, acc_y0, acc_y1;
    reg [19:0] area_r;         // 本帧前景像素累计（≤ 921600）
    // 对角极值（D1）：u = x+y，v = x−y+(LINES−1)，均非负 12 位
    reg [11:0] acc_u0, acc_u1, acc_v0, acc_v1;

    //---------- 帧间量：运动检测 + 越线计数 ----------
    reg        prev_valid;   // 上一发布帧存在前景
    reg [10:0] prev_cx, prev_cy;
    reg        armed;        // 越线计数已武装（退回线左侧 LINE_HYST 后置位）
    reg [3:0]  cnt_d0, cnt_d1, cnt_d2, cnt_d3, cnt_d4, cnt_d5;

    // BCD 状态落在本模块寄存器，进位链读寄存器而非直接驱动输出
    // （曾踩坑：进位结果写输出、状态寄存器从不更新 → 第二次计数又从 0 数起）
    assign O_cnt_bcd = {cnt_d5, cnt_d4, cnt_d3, cnt_d2, cnt_d1, cnt_d0};

    // 中心/尺寸：加法必须先扩位再移位！11 位上下文里 (x0+x1) 在 x0+x1≥2048
    // （工件位于画面右半）时回绕，cx 从 ~1189 跳到 ~165——假 MOVE + 计数误触发。
    // 与 img_proj 的 cx_sum 12 位写法对齐。
    wire [11:0] cx_sum  = {1'b0, acc_x0} + {1'b0, acc_x1};
    wire [11:0] cy_sum  = {1'b0, acc_y0} + {1'b0, acc_y1};
    wire [10:0] cur_cx  = cx_sum[11:1];
    wire [10:0] cur_cy  = cy_sum[11:1];
    wire [10:0] cur_w   = acc_x1 - acc_x0 + 11'd1;
    wire [10:0] cur_h   = acc_y1 - acc_y0 + 11'd1;
    wire [10:0] dcx     = (cur_cx >= prev_cx) ? (cur_cx - prev_cx) : (prev_cx - cur_cx);
    wire [10:0] dcy     = (cur_cy >= prev_cy) ? (cur_cy - prev_cy) : (prev_cy - cur_cy);
    wire [11:0] dsum    = {1'b0, dcx} + {1'b0, dcy};   // 同理：曼哈顿距离和先扩位
    wire        crossed = prev_valid && (prev_cx < LINE_X) && (cur_cx >= LINE_X);
    wire        rearm   = (cur_cx < (LINE_X - LINE_HYST));

    //---------- 几何分类（发布拍组合判决，全部移位/加减，无除法） ----------
    // 特征：宽高比（≥3:1 → BAR）、有无孔（img_proj 孔径≥HOLE_MIN）、
    //       填充率 fill = area/(w·h)，用亏量 deficit = w·h − area 比较：
    //       fill ≥ 7/8 ⇔ deficit<<3 ≤ wh（BLOCK）
    //       有孔时按四向宽度比区分六角 NUT / 圆环 RING（见 is_hex，D1）
    // wh 每拍由 11×11 乘法寄存（DSP 一拍，不在发布沿堆组合路径）。
    reg  [21:0] cls_wh;
    always @(posedge I_clk) cls_wh <= cur_w * cur_h;
    wire [21:0] deficit   = cls_wh - area_r;                  // area ≤ wh 恒成立
    wire [24:0] deficit8  = {3'b0, deficit} << 3;
    wire [12:0] w3        = {2'b0, cur_w} + {1'b0, cur_w, 1'b0};   // 3·w ≤ 3840
    wire [12:0] h3        = {2'b0, cur_h} + {1'b0, cur_h, 1'b0};
    wire        wide_bar  = (cur_w >= h3) || (cur_h >= w3);
    wire        has_hole  = I_hole_valid && (I_hole >= HOLE_MIN);

    //---------- 六角/圆形判别（D1：对角极值） ----------
    // 四个方向的投影宽度：0°/90° 为 w、h；45°/135° 为 (Δu+2)/√2、(Δv+2)/√2
    // （+2 = 单像素在对角方向的投影宽）。统一乘 128√2 免开方：
    //   轴向 w·181，对角 (Δu+2)·128。圆的四宽近似相等；正六边形对边宽与
    //   对角宽之比 2/√3，任意转角下四宽 max/min ≥ ~1.07（建模 d≥40px）。
    // 判据 max·16 ≥ min·17（1.0625）→ 六角。圆在 d≥40px 时 ≤1.052。
    // 三级寄存流水（输入累加器在帧尾消隐期稳定，发布沿取到的是稳定值；
    // 要求末个前景拍到下一帧 tuser 间至少 3 拍，实际帧消隐远大于此）。
    reg  [19:0] dw_a, dw_b, dw_c, dw_d;
    reg  [19:0] dw_max, dw_min;
    reg         is_hex;
    wire [11:0] du = acc_u1 - acc_u0 + 12'd2;
    wire [11:0] dv = acc_v1 - acc_v0 + 12'd2;
    wire [19:0] mx_ab = (dw_a > dw_b) ? dw_a : dw_b;
    wire [19:0] mx_cd = (dw_c > dw_d) ? dw_c : dw_d;
    wire [19:0] mn_ab = (dw_a < dw_b) ? dw_a : dw_b;
    wire [19:0] mn_cd = (dw_c < dw_d) ? dw_c : dw_d;
    always @(posedge I_clk) begin
        // 181 = 128+32+16+4+1
        dw_a <= ({9'd0, cur_w} << 7) + ({9'd0, cur_w} << 5) + ({9'd0, cur_w} << 4)
              + ({9'd0, cur_w} << 2) + {9'd0, cur_w};
        dw_b <= ({9'd0, cur_h} << 7) + ({9'd0, cur_h} << 5) + ({9'd0, cur_h} << 4)
              + ({9'd0, cur_h} << 2) + {9'd0, cur_h};
        dw_c <= {1'b0, du, 7'd0};
        dw_d <= {1'b0, dv, 7'd0};
        dw_max <= (mx_ab > mx_cd) ? mx_ab : mx_cd;
        dw_min <= (mn_ab < mn_cd) ? mn_ab : mn_cd;
        is_hex <= ({dw_max, 4'd0} >= ({dw_min, 4'd0} + {4'd0, dw_min}));
    end

    //---------- 有效目标门控（2026-10-04 绿屏/计数疯涨事件的修复） ----------
    // 暗场高增益下噪声自身构成"前景框"：框巨大、填充率趋近 0，中心在线附近
    // 抖动 → 越线计数把噪声当工件反复计数、MOVE 常亮、分类误报。
    // 门控 = 面积 ≥ AREA_MIN 且 填充率 ≥ 1/8（8·area ≥ w·h ⇔ deficit<<3 ≤ 7·wh）。
    // 不满足时：框隐藏、CNT 冻结、MOVE=0、TYPE=NONE、连续性打断（同空帧语义）。
    wire [24:0] wh7       = ({3'b0, cls_wh} << 3) - {3'b0, cls_wh};  // 7·wh
    wire        tgt = frame_good && frame_run &&
                      (area_r >= AREA_MIN) && (deficit8 <= wh7);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            beat_idx <= 9'd0;  line_idx <= 11'd0;
            frame_run <= 1'b0; frame_seen <= 1'b0;
            frame_complete <= 1'b0; frame_bad <= 1'b0;
            acc_x0 <= 11'd0; acc_x1 <= 11'd0;
            acc_y0 <= 11'd0; acc_y1 <= 11'd0;
            area_r <= 20'd0;
            acc_u0 <= 12'd0; acc_u1 <= 12'd0;
            acc_v0 <= 12'd0; acc_v1 <= 12'd0;
            O_x0 <= 11'd0; O_x1 <= 11'd0;
            O_y0 <= 11'd0; O_y1 <= 11'd0;
            O_cx <= 11'd0; O_cy <= 11'd0;
            O_w  <= 11'd0; O_h  <= 11'd0;
            O_area <= 20'd0; O_type <= T_NONE;
            O_moving <= 1'b0;
            O_valid <= 1'b0; O_upd <= 1'b0;
            prev_valid <= 1'b0;
            prev_cx <= 11'd0; prev_cy <= 11'd0;
            armed <= 1'b1;
            cnt_d0 <= 4'd0; cnt_d1 <= 4'd0; cnt_d2 <= 4'd0;
            cnt_d3 <= 4'd0; cnt_d4 <= 4'd0; cnt_d5 <= 4'd0;
        end else if (I_tvalid) begin
            // 1) 帧起始：发布上一帧结果并复位（先执行，本拍前景归属新帧；
            //    累加器一并清零，空帧发布确定性的 0 而非旧帧残留）
            if (I_tuser) begin
                O_x0 <= tgt ? acc_x0 : 11'd0;
                O_x1 <= tgt ? acc_x1 : 11'd0;
                O_y0 <= tgt ? acc_y0 : 11'd0;
                O_y1 <= tgt ? acc_y1 : 11'd0;
                O_valid <= tgt;
                O_upd   <= ~O_upd;
                acc_x0 <= 11'd0; acc_x1 <= 11'd0;
                acc_y0 <= 11'd0; acc_y1 <= 11'd0;
                frame_run  <= 1'b0;
                frame_seen <= 1'b1;
                frame_complete <= 1'b0;
                frame_bad <= 1'b0;
                // 面积与几何分类（判决量均为本帧的边沿前稳定值）
                O_area <= tgt ? area_r : 20'd0;
                if (tgt) begin
                    if (wide_bar)                  O_type <= T_BAR;
                    else if (has_hole)             O_type <= is_hex ? T_NUT : T_RING;
                    else if (deficit8 <= cls_wh)   O_type <= T_BLOCK;
                    else                           O_type <= T_DISC;
                end else begin
                    O_type <= T_NONE;
                end
                // 帧间量：运动/计数/中心尺寸，仅前后帧都是有效目标才判定
                if (tgt) begin
                    O_cx <= cur_cx; O_cy <= cur_cy;
                    O_w  <= cur_w;  O_h  <= cur_h;
                    O_moving <= prev_valid && (dsum >= MOTION_THRESH);
                    prev_cx <= cur_cx; prev_cy <= cur_cy;
                    if (crossed && armed) begin
                        armed <= 1'b0;
                        cnt_d0 <= (cnt_d0 == 4'd9) ? 4'd0 : cnt_d0 + 4'd1;
                        if (cnt_d0 == 4'd9) begin
                            cnt_d1 <= (cnt_d1 == 4'd9) ? 4'd0 : cnt_d1 + 4'd1;
                            if (cnt_d1 == 4'd9) begin
                                cnt_d2 <= (cnt_d2 == 4'd9) ? 4'd0 : cnt_d2 + 4'd1;
                                if (cnt_d2 == 4'd9) begin
                                    cnt_d3 <= (cnt_d3 == 4'd9) ? 4'd0 : cnt_d3 + 4'd1;
                                    if (cnt_d3 == 4'd9) begin
                                        cnt_d4 <= (cnt_d4 == 4'd9) ? 4'd0 : cnt_d4 + 4'd1;
                                        if (cnt_d4 == 4'd9)
                                            cnt_d5 <= (cnt_d5 == 4'd9) ? 4'd0 : cnt_d5 + 4'd1;
                                    end
                                end
                            end
                        end
                    end else if (rearm) begin
                        armed <= 1'b1;
                    end
                end else begin
                    // 无目标/噪声框：连续性打断，计数不冻结但也不增长
                    O_moving <= 1'b0;
                    O_cx <= 11'd0; O_cy <= 11'd0;
                    O_w <= 11'd0; O_h <= 11'd0;
                    armed <= 1'b1;
                end
                prev_valid <= tgt;
            end
            // Validate every row length and the exact number of rows.
            // Extra data after EOF invalidates the frame until the next SOF.
            if (I_tuser || frame_seen) begin
                if ((!I_tuser && frame_complete) ||
                    line_now >= LINES_PER_FRAME ||
                    (I_tlast != (beat_now == BEATS_PER_LINE-1)))
                    frame_bad <= 1'b1;
                if (I_tlast && beat_now == BEATS_PER_LINE-1 &&
                    line_now == LINES_PER_FRAME-1)
                    frame_complete <= 1'b1;
            end
            // 2) 本拍前景并入外接矩形（tuser 拍强制重新起算：该拍属于新帧，
            //    不得与已发布的旧帧累加器比较）
            if (beat_fg && (I_tuser || (frame_seen && !frame_complete))) begin
                if (I_tuser || !frame_run) begin
                    acc_x0 <= xl; acc_x1 <= xr;
                    acc_y0 <= line_now; acc_y1 <= line_now;
                    area_r <= {17'd0, fg_cnt};   // 新帧面积从本拍重新起算
                    acc_u0 <= ul; acc_u1 <= ur;
                    acc_v0 <= vl; acc_v1 <= vr;
                    frame_run <= 1'b1;
                end else begin
                    if (xl < acc_x0) acc_x0 <= xl;
                    if (xr > acc_x1) acc_x1 <= xr;
                    acc_y1 <= line_now;   // y 单调增：最后含前景的行即 y1
                    area_r <= area_r + {17'd0, fg_cnt};
                    if (ul < acc_u0) acc_u0 <= ul;
                    if (ur > acc_u1) acc_u1 <= ur;
                    if (vl < acc_v0) acc_v0 <= vl;
                    if (vr > acc_v1) acc_v1 <= vr;
                end
            end
            // 3) 位置计数（行首/行尾均以标志为准，与空泡无关）
            beat_idx <= I_tlast ? 9'd0 : (beat_now + 9'd1);
            line_idx <= I_tlast ? (line_now + 11'd1) : line_now;
        end
    end

endmodule
