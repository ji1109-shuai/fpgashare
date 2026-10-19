/*****************************************************************
Module Name : awb（灰度世界自动白平衡）
Description : 基于米联客参考 awb 改写（2026-10-11 架构优化）。

原设计问题：
  1. 每个像素拍都把"本帧到目前为止的部分累加和"送入两个 50 级流水
     除法器，增益在帧内逐拍变化——帧顶几十行增益由极少像素决定，
     造成帧顶/帧底色温不一致与亮度"呼吸"；
  2. 两个 48/32 位全流水除法器约占 5.5k LUT + 5.5k 寄存器（全片 1/4），
     而增益本质上每帧只需算一次。

现结构：
  - 帧统计：每拍取像素0（1/4 抽样），排除近白像素（R+G+B≥720），
    累加 ΣR/ΣG/ΣB；帧起始沿快照上一帧统计并清零；
  - 帧间串行除法：一个 48 次迭代恢复余数除法器，先算 G/R 再算 G/B
    （共约 100 拍，远小于一帧），结果钳位到 [0.25, 4.0]；
  - 增益平滑：1/4 步长 IIR（约 10 帧收敛），I_gain_freeze=1 时保持；
  - 增益生效：仅在帧起始沿拷贝到工作寄存器，整帧恒定；
  - 数据延迟通路（signal_delay）与输出时序与原设计完全一致：
    O_tuser 组合直通、数据延迟约 53 拍——DDR 写侧依赖此帧头提前量。
增益格式：20 位无符号定点，16 位小数（0x10000 = 1.0）。
*****************************************************************/
module awb  #(
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920,
    parameter REFERENCE_ONLY = 0,
    parameter REFERENCE_WINDOW = 0,
    parameter MIN_REFERENCE_SAMPLES = 128,
    parameter DIAGNOSTICS = 0, // central power-of-two ROI, at most 1024 samples
    parameter AUTO_REFERENCE = 0 // use with REFERENCE_ONLY=1; no card/lock prerequisite
)
(
    input                   I_clk  ,
    input                   I_rst_n,

    input                   I_tlast  ,
    input                   I_tuser  ,
    input [95:0]            I_tdata  ,
    input                   I_tvalid ,
    input                   I_gain_freeze, // manual mode freeze; ignored by AUTO_REFERENCE
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output                  O_tvalid ,
    input                   O_tready,
    input                   I_cal_reset,
    output reg [31:0]       O_reference, // {5'b0,locked/auto_has_solution,ready,sample_valid,raw_R,raw_G,raw_B}
    output reg              O_reference_upd,
    output [127:0]           O_diagnostics,
    output                  O_diagnostics_upd
);

    localparam [19:0] GAIN_UNITY = 20'h10000;   // 1.0
    localparam [47:0] GAIN_MIN   = 48'h04000;   // 0.25
    localparam [47:0] GAIN_MAX   = 48'h40000;   // 4.0

/*****************************************************************
                          输入寄存
*****************************************************************/
    reg         I_tvalid_r0, I_tvalid_r1;
    reg  [95:0] I_tdata_d0, I_tdata_d1;
    reg         I_tuser_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            I_tdata_d0 <= 0;
            I_tdata_d1 <= 0;
            {I_tvalid_r0, I_tvalid_r1} <= 0;
            I_tuser_d <= 1'b0;
        end else begin
            I_tdata_d0  <= I_tdata;
            I_tdata_d1  <= I_tdata_d0;
            I_tvalid_r0 <= I_tvalid;
            I_tvalid_r1 <= I_tvalid_r0;
            I_tuser_d   <= I_tuser;
        end
    end
    // 帧起始沿：I_tuser 若为多拍电平也只触发一次快照/生效
    wire sof_edge = I_tuser && !I_tuser_d;
    // Known central card/board patch. Only statistics use this window; pixel
    // data, latency and early frame pulse retain the working video timing.
    localparam REF_W=REFERENCE_WINDOW>0 && REFERENCE_WINDOW<IMG_WIDTH ? REFERENCE_WINDOW:IMG_WIDTH;
    localparam REF_H=REFERENCE_WINDOW>0 && REFERENCE_WINDOW<IMG_HEIGHT ? REFERENCE_WINDOW:IMG_HEIGHT;
    reg [10:0] reference_x,reference_y;
    reg reference_roi_d0;
    wire [10:0] reference_cx=I_tuser ? 11'd0:reference_x;
    wire [10:0] reference_cy=I_tuser ? 11'd0:reference_y;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin reference_x<=0;reference_y<=0;reference_roi_d0<=0;end
        else begin
            reference_roi_d0<=I_tvalid && reference_cx>=(IMG_WIDTH-REF_W)/2 &&
                reference_cx<(IMG_WIDTH+REF_W)/2 && reference_cy>=(IMG_HEIGHT-REF_H)/2 &&
                reference_cy<(IMG_HEIGHT+REF_H)/2;
            if(I_tuser) begin reference_x<=0;reference_y<=0;end
            if(I_tvalid) begin
                if(reference_cx>=IMG_WIDTH-4) begin reference_x<=0;reference_y<=reference_cy+1'b1;end
                else begin reference_x<=reference_cx+4;reference_y<=reference_cy;end
            end
        end
    end
    reg freeze_d;
    wire gain_frozen=!AUTO_REFERENCE && I_gain_freeze;
    wire calibration_reset=REFERENCE_ONLY && !AUTO_REFERENCE && I_cal_reset;
    wire unlock_edge=freeze_d && !gain_frozen;
    wire calibration_abort=REFERENCE_ONLY && (calibration_reset || unlock_edge);
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n) freeze_d<=0; else freeze_d<=gain_frozen;

/*****************************************************************
                          帧统计（像素0抽样）
*****************************************************************/
    reg  [9:0]  rgb_sum0;   // 像素0的 R+G+B，用于排除近白像素
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            rgb_sum0 <= 10'd0;
        else if (I_tvalid)
            rgb_sum0 <= I_tdata[16+:8] + I_tdata[8+:8] + I_tdata[0+:8];
    end

    // 累加和初值为 1：空帧/全白帧时除数不为 0（G/R 退化为 1.0）
    reg  [31:0] sum_r, sum_g, sum_b;
    reg  [31:0] snap_r, snap_g, snap_b;
    reg         frame_seen;   // 第一次帧头之前的统计属于不完整帧，丢弃
    reg         div_req;
    reg [19:0] ref_count,snap_count;
    reg snap_good;
    wire [7:0] ref_r=I_tdata_d0[23:16],ref_g=I_tdata_d0[15:8],ref_b=I_tdata_d0[7:0];
    wire [7:0] ref_max_rg=ref_r>ref_g ? ref_r:ref_g;
    wire [7:0] ref_max=ref_max_rg>ref_b ? ref_max_rg:ref_b;
    wire [7:0] ref_min_rg=ref_r<ref_g ? ref_r:ref_g;
    wire [7:0] ref_min=ref_min_rg<ref_b ? ref_min_rg:ref_b;
    // Manual mode samples a neutral card ROI. Automatic mode searches the
    // scene for candidate neutral pixels. Both reject outside-black, strongly
    // coloured samples and clipped channels; neither can recover blown highlights.
    wire reference_sample=reference_roi_d0 && ref_min>=64 && ref_max<=240 && {1'b0,ref_max}<={ref_min,1'b0};
    wire rejected_reference=REFERENCE_ONLY && !AUTO_REFERENCE && sof_edge && frame_seen &&
        ref_count<MIN_REFERENCE_SAMPLES && !gain_frozen;
    wire invalid_lock=REFERENCE_ONLY && !freeze_d && gain_frozen && O_reference[25:24]!=2'b11;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sum_r <= REFERENCE_ONLY ? 32'd0:32'd1;
            sum_g <= REFERENCE_ONLY ? 32'd0:32'd1;
            sum_b <= REFERENCE_ONLY ? 32'd0:32'd1;
            snap_r <= 32'd1; snap_g <= 32'd1; snap_b <= 32'd1;
            frame_seen <= 1'b0;
            div_req    <= 1'b0;
            ref_count<=0;snap_count<=1;snap_good<=0;
        end else begin
            div_req <= 1'b0;
            if (sof_edge) begin
                snap_r <= sum_r; snap_g <= sum_g; snap_b <= sum_b;
                snap_count<=ref_count;
                snap_good<=ref_count>=MIN_REFERENCE_SAMPLES;
                div_req <= frame_seen && (!REFERENCE_ONLY || ref_count>=MIN_REFERENCE_SAMPLES) && !calibration_reset;
                frame_seen <= 1'b1;
            end
            if (I_tuser) begin
                sum_r <= REFERENCE_ONLY ? 32'd0:32'd1;
                sum_g <= REFERENCE_ONLY ? 32'd0:32'd1;
                sum_b <= REFERENCE_ONLY ? 32'd0:32'd1;
                ref_count<=0;
            end else if (I_tvalid_r0 && (REFERENCE_ONLY ? reference_sample : rgb_sum0 < 10'd720)) begin
                sum_r <= sum_r + I_tdata_d0[16+:8];
                sum_g <= sum_g + I_tdata_d0[8+:8];
                sum_b <= sum_b + I_tdata_d0[0+:8];
                ref_count<=ref_count+1'b1;
            end
            // Statistics and their divider request belong to the old light
            // setting. A new calibration must start with a complete frame.
            if(calibration_abort) begin
                sum_r<=0;sum_g<=0;sum_b<=0;ref_count<=0;
                snap_good<=0;frame_seen<=0;div_req<=0;
            end
        end
    end

/*****************************************************************
                帧间串行除法：G/R、G/B（恢复余数法）
*****************************************************************/
    // quotient = {sum_g, 16'd0} / den，48 次迭代，每次 33 位比较减
    reg         div_busy;
    reg [2:0]   div_sel;        // 0=G/R,1=G/B,2..4=reference mean R/G/B
    reg  [5:0]  div_cnt;
    reg  [47:0] div_num;        // 被除数移位寄存器，逐位移出到余数
    reg  [31:0] div_den;
    reg  [32:0] div_rem;
    reg  [47:0] div_quo;
    reg         div_done;       // 单拍：div_quo 有效，div_sel 指示通道
    wire [32:0] div_trial = {div_rem[31:0], div_num[47]};
    wire        div_ge    = (div_trial >= {1'b0, div_den});

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            div_busy <= 1'b0; div_sel <= 1'b0; div_cnt <= 6'd0;
            div_num <= 48'd0; div_den <= 32'd1;
            div_rem <= 33'd0; div_quo <= 48'd0;
            div_done <= 1'b0;
        end else begin
            div_done <= 1'b0;
            if(calibration_abort) begin
                div_busy<=0;div_cnt<=0;
            end else if (div_req) begin
                // 新帧统计到达：从 G/R 开始（上次未完成的计算直接放弃）
                div_busy <= 1'b1; div_sel <= 1'b0; div_cnt <= 6'd0;
                div_num  <= {snap_g, 16'd0};
                div_den  <= snap_r;
                div_rem  <= 33'd0;
            end else if (div_busy) begin
                div_rem <= div_ge ? (div_trial - {1'b0, div_den}) : div_trial;
                div_quo <= {div_quo[46:0], div_ge};
                div_num <= {div_num[46:0], 1'b0};
                if (div_cnt == 6'd47) begin
                    div_done <= 1'b1;
                    div_cnt  <= 6'd0;
                    if (div_sel==0) begin
                        // G/R 完成，接着算 G/B
                        div_sel <= 1'b1;
                        div_num <= {snap_g, 16'd0};
                        div_den <= snap_b;
                        div_rem <= 33'd0;
                    end else if(REFERENCE_ONLY && div_sel<4) begin
                        div_sel<=div_sel+1'b1;
                        div_num<=div_sel==1 ? {16'd0,snap_r} : div_sel==2 ? {16'd0,snap_g} : {16'd0,snap_b};
                        div_den<={12'd0,snap_count};div_rem<=0;
                    end else begin
                        div_busy <= 1'b0;
                    end
                end else begin
                    div_cnt <= div_cnt + 6'd1;
                end
            end
        end
    end

    // div_done 拍：div_quo 是刚完成的商，div_sel 仍指示其通道
    // （G/R 完成拍 div_sel 才在同拍翻到 1，故此处取寄存前的值）
    reg [2:0]   done_sel;
    reg  [47:0] done_quo;
    reg         done_v;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            done_sel <= 1'b0; done_quo <= 48'd0; done_v <= 1'b0;
        end else begin
            done_v   <= div_busy && (div_cnt == 6'd47) && !div_req && !calibration_abort;
            done_sel <= div_sel;
            done_quo <= {div_quo[46:0], div_ge};
        end
    end

    // 钳位到 [0.25, 4.0]：防止单色场景/遮挡镜头时增益失控
    wire [19:0] quo_clamped = (done_quo > GAIN_MAX) ? GAIN_MAX[19:0] :
                              (done_quo < GAIN_MIN) ? GAIN_MIN[19:0] :
                                                      done_quo[19:0];

/*****************************************************************
                增益平滑（IIR 1/4 步长）与帧起始生效
*****************************************************************/
    reg  [19:0] gain_r_tgt, gain_b_tgt;   // 平滑后的目标增益（帧间更新）
    reg  [19:0] in_r_r1, in_b_r1;         // 工作增益（仅帧起始沿更新）
    wire [19:0] cur_tgt   = done_sel ? gain_b_tgt : gain_r_tgt;
    // gain + (target - gain)/4，有符号差值（21 位），算术右移
    wire signed [20:0] g_diff = $signed({1'b0, quo_clamped}) - $signed({1'b0, cur_tgt});
    wire signed [20:0] g_step = g_diff >>> 2;
    wire        [20:0] g_next = {1'b0, cur_tgt} + g_step;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            gain_r_tgt <= GAIN_UNITY;
            gain_b_tgt <= GAIN_UNITY;
        end else if(calibration_abort || rejected_reference || invalid_lock) begin
            gain_r_tgt<=GAIN_UNITY;gain_b_tgt<=GAIN_UNITY;
        end else if (done_v && done_sel<2 && !gain_frozen && !calibration_reset) begin
            if (done_sel==1) gain_b_tgt <= g_next[19:0];
            else          gain_r_tgt <= g_next[19:0];
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            in_r_r1 <= GAIN_UNITY;
            in_b_r1 <= GAIN_UNITY;
        end else if(sof_edge) begin
            // Invalid reference used to clear only the colour label while
            // leaving obsolete R/B gains active in the RGB picture. Bypass
            // that correction at SOF; keep every pixel of a frame consistent.
            if(REFERENCE_ONLY && !AUTO_REFERENCE && (calibration_reset ||
                (gain_frozen ? O_reference[25:24]!=2'b11:!O_reference[24]))) begin
                in_r_r1<=GAIN_UNITY;in_b_r1<=GAIN_UNITY;
            end else if(!REFERENCE_ONLY || !gain_frozen) begin
                in_r_r1 <= gain_r_tgt;
                in_b_r1 <= gain_b_tgt;
            end
        end
    end

    // Independent observer: includes rejected pixels and remains live while
    // calibration is BAD or locked. No divider or change to the video path.
    // Packet: raw RGB[127:104], applied Q16 R[103:84], B[83:64],
    // accepted[63:53], clipped[52:42], dark[41:31], cast[30:20],
    // total[19:9], reason[8:5], reserved[4:0]. Gains belong to the
    // frame just measured, not to the next calibration target.
    // AUTO_REFERENCE searches the image, but the readable RAW observer stays
    // at the original centre 64x64: keep its counters/packet widths unchanged.
    localparam DIAG_W=AUTO_REFERENCE && IMG_WIDTH>64 ? 64:REF_W;
    localparam DIAG_H=AUTO_REFERENCE && IMG_HEIGHT>64 ? 64:REF_H;
    localparam DIAG_SAMPLES=DIAG_W*DIAG_H/4;
    localparam DIAG_SHIFT=$clog2(DIAG_SAMPLES);
    generate if(DIAGNOSTICS && REFERENCE_ONLY) begin : g_diagnostics
        reg [127:0] packet;
        reg update;
        assign O_diagnostics=packet;
        assign O_diagnostics_upd=update;
        reg [17:0] raw_sum_r,raw_sum_g,raw_sum_b;
        reg [10:0] total,accepted,clipped,dark,cast;
        reg seen;
        reg diag_roi_d0;
        wire too_bright=ref_max>240;
        wire too_dark=ref_min<64;
        wire too_coloured={1'b0,ref_max}>{ref_min,1'b0};
        wire [7:0] raw_mean_r=raw_sum_r>>DIAG_SHIFT;
        wire [7:0] raw_mean_g=raw_sum_g>>DIAG_SHIFT;
        wire [7:0] raw_mean_b=raw_sum_b>>DIAG_SHIFT;
        // The reason describes SAMPLE suitability, not WB lock readiness.
        // If insufficient, report the largest mutually exclusive reject bin.
        wire [3:0] reason=total==0 ? 4'd1 : total!=DIAG_SAMPLES ? 4'd6 :
            accepted>=(AUTO_REFERENCE ? 128:MIN_REFERENCE_SAMPLES) ? 4'd0 :
            clipped>=dark && clipped>=cast && clipped!=0 ? 4'd2 :
            dark>=cast && dark!=0 ? 4'd3 : cast!=0 ? 4'd4 : 4'd5;
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                raw_sum_r<=0;raw_sum_g<=0;raw_sum_b<=0;
                total<=0;accepted<=0;clipped<=0;dark<=0;cast<=0;seen<=0;
                packet<=0;update<=0;diag_roi_d0<=0;
            end else begin
                diag_roi_d0<=I_tvalid && reference_cx>=(IMG_WIDTH-DIAG_W)/2 &&
                    reference_cx<(IMG_WIDTH+DIAG_W)/2 && reference_cy>=(IMG_HEIGHT-DIAG_H)/2 &&
                    reference_cy<(IMG_HEIGHT+DIAG_H)/2;
                if(sof_edge) begin
                    if(seen) begin
                        packet<={raw_mean_r,raw_mean_g,raw_mean_b,
                            in_r_r1,in_b_r1,accepted,clipped,dark,cast,total,reason,5'd0};
                        update<=~update;
                    end
                    seen<=1;
                end
                if(I_tuser) begin
                    raw_sum_r<=0;raw_sum_g<=0;raw_sum_b<=0;
                    total<=0;accepted<=0;clipped<=0;dark<=0;cast<=0;
                end else if(I_tvalid_r0 && diag_roi_d0) begin
                    raw_sum_r<=raw_sum_r+ref_r;
                    raw_sum_g<=raw_sum_g+ref_g;
                    raw_sum_b<=raw_sum_b+ref_b;
                    total<=total+1'b1;
                    if(too_bright) clipped<=clipped+1'b1;
                    else if(too_dark) dark<=dark+1'b1;
                    else if(too_coloured) cast<=cast+1'b1;
                    else accepted<=accepted+1'b1;
                end
            end
        end
    end else begin : g_no_diagnostics
        assign O_diagnostics=128'd0;
        assign O_diagnostics_upd=1'b0;
    end endgenerate

    reg [7:0] mean_r,mean_g;
    reg [3:0] reference_streak;
    reg red_converged;
    wire gain_converged=(g_diff>=-21'sd1024 && g_diff<=21'sd1024);
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            mean_r<=0;mean_g<=0;reference_streak<=0;red_converged<=0;
            O_reference<=0;O_reference_upd<=0;
        end else if(REFERENCE_ONLY && AUTO_REFERENCE) begin
            // A missing/occluded/clipped neutral region is not evidence that
            // unity is correct. Keep the last usable gains and report HOLD.
            // EXP/GAIN events and SW4 cannot discard an automatic solution.
            if(sof_edge && frame_seen) begin
                O_reference[24]<=ref_count>=MIN_REFERENCE_SAMPLES;
                O_reference_upd<=~O_reference_upd;
            end
            if(done_v) begin
                case(done_sel)
                    0:red_converged<=gain_converged;
                    1:begin
                        reference_streak<=red_converged && gain_converged ?
                            (reference_streak==15 ? reference_streak:reference_streak+1'b1) : 0;
                        O_reference[26]<=1'b1; // at least one usable automatic solution
                    end
                    2:mean_r<=done_quo[7:0];
                    3:mean_g<=done_quo[7:0];
                    4:begin
                        O_reference[25:0]<={reference_streak>=3,snap_good,mean_r,mean_g,done_quo[7:0]};
                        O_reference_upd<=~O_reference_upd;
                    end
                endcase
            end
        end else if(REFERENCE_ONLY) begin
            if(done_v && !I_gain_freeze && !calibration_abort) begin
                case(done_sel)
                    0:red_converged<=gain_converged;
                    1:reference_streak<=red_converged && gain_converged ?
                        (reference_streak==15 ? reference_streak:reference_streak+1'b1) : 0;
                    2:mean_r<=done_quo[7:0];
                    3:mean_g<=done_quo[7:0];
                    4:begin
                        O_reference<={5'd0,1'b0,reference_streak>=3,snap_good,mean_r,mean_g,done_quo[7:0]};
                        O_reference_upd<=~O_reference_upd;
                    end
                endcase
            end
            if(rejected_reference) begin
                reference_streak<=0;O_reference<=0;O_reference_upd<=~O_reference_upd;
            end
            if(freeze_d!=I_gain_freeze) begin
                O_reference[26]<=I_gain_freeze;O_reference_upd<=~O_reference_upd;
            end
            if(invalid_lock) begin
                reference_streak<=0;red_converged<=0;
                O_reference<={5'd0,1'b1,26'd0};O_reference_upd<=~O_reference_upd;
            end
            if(unlock_edge || calibration_reset) begin
                reference_streak<=0;red_converged<=0;
                O_reference<={5'd0,I_gain_freeze,26'd0};O_reference_upd<=~O_reference_upd;
            end
        end
    end

/*****************************************************************
                数据延迟（与原设计一致，约 50 拍）
*****************************************************************/
    wire  [95:0]  data_d0;
    wire          valid_d0;
    wire          I_tuser_r0;
    signal_delay #(
        .IMG_HEIGHT   (IMG_HEIGHT),
        .IMG_WIDTH    (IMG_WIDTH ),
        .DATA_WIDTH   (96  ),
        .DELAY_CYCLE  (50)
    ) signal_delay_d (
        .I_clk  (I_clk      ),
        .I_rst_n(I_rst_n    ),
        .I_tuser(I_tuser    ),
        .I_valid(I_tvalid_r1),
        .I_data (I_tdata_d1 ),
        .O_valid(valid_d0   ),
        .O_data (data_d0    ),
        .O_tuser(I_tuser_r0 )
    );

    reg  [95:0] data_d1;
    reg         valid_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_d1 <= 1'b0;
            data_d1  <= 96'd0;
        end else begin
            valid_d1 <= valid_d0;
            data_d1  <= data_d0;
        end
    end

/*****************************************************************
                增益应用（G 通道直通）
*****************************************************************/
    // 拍内 4 像素，每像素 24 位 {R,G,B}，像素 k 位于 [24k +: 24]
    reg  [27:0] R_new [0:3];
    reg  [7:0]  G_new [0:3];
    reg  [27:0] B_new [0:3];
    integer k;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (k = 0; k < 4; k = k + 1) begin
                R_new[k] <= 28'd0; G_new[k] <= 8'd0; B_new[k] <= 28'd0;
            end
        end else if (valid_d1) begin
            for (k = 0; k < 4; k = k + 1) begin
                R_new[k] <= in_r_r1 * data_d1[24*k+16 +: 8];
                G_new[k] <=           data_d1[24*k+8  +: 8];
                B_new[k] <= in_b_r1 * data_d1[24*k    +: 8];
            end
        end
    end

    // 16 位小数定点：取 [23:16]，[27:24] 非零即饱和到 255
    wire [95:0] gained;
    genvar gk;
    generate
        for (gk = 0; gk < 4; gk = gk + 1) begin : g_sat
            assign gained[24*gk+16 +: 8] = (|R_new[gk][27:24]) ? 8'd255 : R_new[gk][23:16];
            assign gained[24*gk+8  +: 8] = G_new[gk];
            assign gained[24*gk    +: 8] = (|B_new[gk][27:24]) ? 8'd255 : B_new[gk][23:16];
        end
    endgenerate

/*****************************************************************
                输出（时序与原设计一致）
*****************************************************************/
    reg valid_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) valid_d2 <= 1'b0;
        else          valid_d2 <= valid_d1;
    end

    assign O_tlast  = (valid_d1 == 1'b0) && (valid_d2 == 1'b1);
    assign O_tuser  = I_tuser;
    assign O_tvalid = valid_d2;
    assign O_tdata  = O_tvalid ? gained : 96'd0;
    assign I_tready = O_tready;

endmodule
