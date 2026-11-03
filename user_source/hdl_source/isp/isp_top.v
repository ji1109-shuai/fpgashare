module isp_top #(
    parameter TIRE_MODE = 1,        // 1: coarse connected-component tire recognition; 0: legacy measurement
    parameter PARTS_MODE = 0,       // 1: screw/washer/hex nut/square nut; independent of preview
    parameter MEAS_FG_IS_WHITE = 0,  // 背光板：测量前景 = 亮背景中的暗工件
    parameter SHOW_BOARD_BOUNDARY = 0, // optional debug outline; internal board mask stays enabled
    parameter DEBUG_CAPTURE = 0,
    parameter VIDEO_MODES = 0,      // wrapper enables new RGB/GRAY/SOBEL/EDGE preview
    parameter COLOR_STABILITY = 0,
    parameter MULTI_TARGETS = 0,
    parameter LATENCY_DIAGNOSTICS = 0,
    parameter AUTO_WHITE_BALANCE = 0 // automatic neutral samples; independent of SW4
)(
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    input 			I_bin_en		,
    input [1:0] 		I_morph_mode	,
    input [1:0] I_enhance_strength,
    input [3:0] I_enhance_noise,
    input I_enhance_compare,
    output reg [2:0] O_display_mode, // 0 RGB,1 GRAY,2 SOBEL,3 EDGE,4 BIN,5 ERODE,6 DILAT,7 ENHANCE
    output [15:0] 		O_proj_span	,  // Valid ring outer diameter in pixels
    output [15:0] 		O_proj_hole	,  // Valid ring hole diameter in pixels
    output 			O_proj_upd		,
    output              O_proj_valid,
    output [2:0]        O_proj_status,
    output [10:0]       O_proj_cx, O_proj_cy,
    output [10:0]       O_proj_hx, O_proj_hy,
    output [7:0] 		O_thresh_val	,  //Otsu自适应阈值（OSD显示）
    output 			O_thresh_upd	,  //阈值更新翻转标志
    output 			O_frame_start	,  // DDR FIFO boundary, ahead of the selected output data
    output [10:0] 		O_bbox_x0	,  //前景外接矩形：最左/最右像素x
    output [10:0] 		O_bbox_x1	,
    output [10:0] 		O_bbox_y0	,  //最上/最下像素y
    output [10:0] 		O_bbox_y1	,
    output [10:0] 		O_bbox_cx	,  //外接矩形中心（仅valid时有意义）
    output [10:0] 		O_bbox_cy	,
    output [10:0] 		O_bbox_w	,  //外接矩形宽/高（像素）
    output [10:0] 		O_bbox_h	,
    output [19:0] 		O_bbox_area	,  //框内前景像素数
    output [2:0] 		O_bbox_type	,  // PARTS: 0NONE 1SCREW 2WASHER 3NUT 4SQNUT 7CANDIDATE
    output [2:0]        O_bbox_color, // 0 unknown, 1 red, 2 green, 3 blue, 4 black, 5 silver, 6 brass
    output 			O_bbox_moving	,  //1=工件运动中（帧间位移超阈值）
    output [23:0] 		O_bbox_cnt	,  //工件计数BCD（中心左→右越过检测线+1）
    output 			O_bbox_valid	,  //本帧存在前景
    output 			O_bbox_upd	,  //外接矩形更新翻转标志
    output [10:0] 		O_roi_x0	,  //背光板白区 ROI（内缩后），测量只在框内进行
    output [10:0] 		O_roi_x1	,
    output [10:0] 		O_roi_y0	,
    output [10:0] 		O_roi_y1	,
    output 			O_roi_valid	,  //1=ROI 有效（屏蔽生效）
    output 			O_roi_upd	,  //ROI 更新翻转标志
    input 			I_awb_freeze	,  //SW4：冻结白平衡增益（消除亮度呼吸）
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready,
    input [28:0] I_camera_status,
    input I_camera_status_upd,
    output [31:0] O_color_reference,
    output O_color_reference_upd,
    output [223:0] O_targets,
    output [2:0] O_target_count,
    output O_target_overflow,
    output [127:0] O_color_diag,
    output [127:0] O_wb_diag,
    output O_wb_diag_upd,
    output [7:0] O_ae_luma,
    output O_ae_valid,O_ae_upd,
    output [15:0] O_latency_bcd,
    output O_latency_valid,O_latency_upd
);
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep

  //二值化模块输出（u_awb 与 u_data_96bit_to_128bit 之间插入）
  wire         bin_O_tlast;  //synthesis keep
  wire         bin_O_tuser;  //synthesis keep
  wire [ 95:0] bin_O_tdata;  //synthesis keep
  wire         bin_O_tvalid;  //synthesis keep

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 

  assign awb_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  // Packed output has 240 valid 128-bit words per 1280-pixel row.
  // The raw AWB tlast has a different beat width and latency.
  reg [7:0] packed_col;
  wire [7:0] packed_col_now = O_tuser ? 8'd0 : packed_col;
  assign O_tlast = O_tvalid && (packed_col_now == 8'd239);
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) packed_col <= 8'd0;
    else if (O_tvalid)
      packed_col <= (packed_col_now == 8'd239) ? 8'd0 : packed_col_now + 8'd1;
  end
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
demosaic #(
    .IMG_HEIGHT          (720),  // 图像高度
    .IMG_WIDTH           (1280),   // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

//SW4 异步开关两级同步后送 awb（直接进时钟域会有增益寄存器亚稳态风险）
reg [1:0] awb_frz_sync;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) awb_frz_sync <= 2'b00;
    else          awb_frz_sync <= {awb_frz_sync[0], I_awb_freeze};
end
wire awb_freeze_s = awb_frz_sync[1];
// Camera settings originate in the configuration clock domain. Transfer the
// held packet after its event synchronizer; changing only EXP/GAIN selection
// is not a photometric change. A real change invalidates a locked calibration.
reg [1:0] color_camera_sync;
reg color_camera_seen,color_freeze_d,color_cal_reset;
reg [27:0] color_camera_values;
reg [7:0] color_epoch;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        color_camera_sync<=0;color_camera_seen<=0;color_camera_values<=0;
        color_freeze_d<=0;color_epoch<=0;color_cal_reset<=0;
    end else if(COLOR_STABILITY && PARTS_MODE) begin
        color_camera_sync<={color_camera_sync[0],I_camera_status_upd};
        color_camera_seen<=color_camera_sync[1];color_freeze_d<=awb_freeze_s;color_cal_reset<=0;
        if(color_freeze_d!=awb_freeze_s) color_epoch<=color_epoch+1'b1;
        if(color_camera_seen!=color_camera_sync[1] && color_camera_values!=I_camera_status[27:0]) begin
            color_camera_values<=I_camera_status[27:0];color_cal_reset<=1;
            color_epoch<=color_epoch+1'b1;
        end
    end
end

awb #(
    .IMG_HEIGHT(720),
    .IMG_WIDTH (1280),
    .REFERENCE_ONLY((COLOR_STABILITY || AUTO_WHITE_BALANCE) && PARTS_MODE),
    .REFERENCE_WINDOW(!AUTO_WHITE_BALANCE && COLOR_STABILITY && PARTS_MODE ? 64:0),
    .MIN_REFERENCE_SAMPLES(AUTO_WHITE_BALANCE ? 1024:128),
    .DIAGNOSTICS((COLOR_STABILITY || AUTO_WHITE_BALANCE) && PARTS_MODE),
    .AUTO_REFERENCE(AUTO_WHITE_BALANCE && PARTS_MODE)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_gain_freeze(awb_freeze_s),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready),
    .I_cal_reset(color_cal_reset),
    .O_reference(O_color_reference),.O_reference_upd(O_color_reference_upd),
    .O_diagnostics(O_wb_diag),.O_diagnostics_upd(O_wb_diag_upd)
);

// Parallel observer only: never inserts a cycle into RGB/marker/DDR paths.
camera_exposure_meter u_ae_meter(
    .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),
    .I_tdata(m_aixs_tdata_96),.I_tvalid(m_aixs_tvalid),
    .I_tuser(m_aixs_tuser),.I_tlast(m_aixs_tlast),
    .O_luma(O_ae_luma),.O_valid(O_ae_valid),.O_upd(O_ae_upd)
);


// AWB forwards an early frame pulse. Attach it to the first valid RGB beat
// before any frame-based algorithm. A coincident pulse is consumed directly.
reg awb_pending_sof;
wire awb_sof = awb_O_tvalid && (awb_pending_sof || awb_O_tuser);
reg [8:0] awb_beat;
wire awb_eol = awb_O_tvalid && !awb_sof && (awb_beat == 9'd319);
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        awb_pending_sof <= 1'b0;
        awb_beat <= 9'd0;
    end else begin
        if (awb_sof) awb_pending_sof <= 1'b0;
        else if (awb_O_tuser) awb_pending_sof <= 1'b1;
        if (awb_sof) awb_beat <= 9'd1;
        else if (awb_O_tvalid)
            awb_beat <= awb_eol ? 9'd0 : awb_beat + 1'b1;
    end
end

//Otsu 自适应阈值：统计 AWB 输出灰度直方图，帧末开始计算
wire [7:0] otsu_thresh;
wire       otsu_upd;
img_otsu #(
    .BEATS_PER_LINE  (320),
    .LINES_PER_FRAME (720),
    // 显著性门限：两类均值差 ≥48 级才更新阈值；无目标/单峰场景保持上帧阈值，
    // 修复"盖镜头/暗房间二值画面花屏"。0=关闭门限。
    .MIN_DMU         (48)
) u_img_otsu (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tdata (awb_O_tdata ),
    .I_tvalid(awb_O_tvalid),
    .I_tuser (awb_sof     ),
    .I_tlast (awb_eol     ),
    .O_threshold(otsu_thresh),
    .O_upd      (otsu_upd)
);

// Report the threshold actually applied to this frame, not a pending result.
reg [7:0] applied_threshold;
reg applied_threshold_upd;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        applied_threshold <= 8'd128;
        applied_threshold_upd <= 1'b0;
    end else if (awb_sof) begin
        applied_threshold <= otsu_thresh;
        applied_threshold_upd <= ~applied_threshold_upd;
    end
end
assign O_thresh_val = applied_threshold;
assign O_thresh_upd = applied_threshold_upd;

//二值化（RGB像素域算法）：白平衡之后、转128bit之前，固定1拍延迟的阈值判决
//阈值来自 img_otsu 的自适应输出（帧首锁存）；若需固定阈值，把 I_threshold 改接 8'd128
// Vendor AWB/DDR emits the HIGH 24 bits first; geometry/morph modules
// address pixel 0 in the LOW 24 bits. Convert once into canonical order.
wire [95:0] awb_geometry_data = {awb_O_tdata[23:0], awb_O_tdata[47:24],
                                awb_O_tdata[71:48], awb_O_tdata[95:72]};
// Binarization is one clock. Delay canonical RGB by the same clock so
// component color always comes from the very same pixels/frame as geometry.
reg [95:0] recognition_rgb;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) recognition_rgb<=0;
    else recognition_rgb<=awb_geometry_data;
end
img_binarize #(
    .INIT_THRESHOLD (8'd128)
) u_img_binarize (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_threshold(otsu_thresh),
    .I_tdata (awb_geometry_data),
    .I_tvalid(awb_O_tvalid),
    .I_tuser (awb_sof     ),
    .I_tlast (awb_eol     ),
    .I_tready(1'b1        ),
    .O_tdata (bin_O_tdata ),
    .O_tvalid(bin_O_tvalid),
    .O_tuser (bin_O_tuser ),
    .O_tlast (bin_O_tlast ),
    .O_tready()
);

//---- SW2/SW3 形态学模式处理 ----
//2位模式独立两级同步（勿用位拼接截断——此前 sync[1:0] 只剩 SW3、SW2 被丢弃），
//帧起始锁存完整2位：00=直通(二值原图) 01=腐蚀 10=膨胀
reg [1:0] morph_mode_sync1, morph_mode_sync2;
reg [1:0] morph_mode_r;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) morph_mode_sync1 <= 2'b00;
    else          morph_mode_sync1 <= I_morph_mode;
end
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) morph_mode_sync2 <= 2'b00;
    else          morph_mode_sync2 <= morph_mode_sync1;
end
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n)
        morph_mode_r <= 2'b00;
    else if (awb_O_tuser)
        morph_mode_r <= morph_mode_sync2;
end

// Frame/line markers were aligned before binarization and follow its data.
wire bin_tuser_synth = bin_O_tuser;
wire bin_tlast_synth = bin_O_tlast;

// The reset must follow the selected path's frame latency, while retaining
// enough advance to finish the video_in FIFO reset before new payload.
// RGB/gray/binary keep their verified raw early SOF. Row-delayed Sobel/EDGE
// use the algorithm's advance pulse; the raw pulse would erase the old tail.

//形态学腐蚀/膨胀（邻域域算法）：MORPH_ITER 级级联，效果随级数累积
//（每级边缘 ±1 像素，4 级 = 每侧 ±4 像素）；SW2/SW3 选模式，级间
//tuser/tlast 用上一级输出的（与该级数据天然对齐）
localparam MORPH_ITER = 4;
wire [95:0] morph_dc [0:MORPH_ITER];
wire        morph_vc [0:MORPH_ITER];
wire        morph_uc [0:MORPH_ITER];
wire        morph_lc [0:MORPH_ITER];
assign morph_dc[0] = bin_O_tdata;
assign morph_vc[0] = bin_O_tvalid;
assign morph_uc[0] = bin_tuser_synth;
assign morph_lc[0] = bin_tlast_synth;

genvar gi;
generate
    for (gi = 0; gi < MORPH_ITER; gi = gi + 1) begin : g_morph
        img_morph #(
            .BEATS_PER_LINE (320)   // 1280/4
        ) u_img_morph (
            .I_clk   (axi4s_video_aclk),
            .I_rst_n (I_rst_n),
            .I_mode  (morph_mode_r  ),
            .I_tdata (morph_dc[gi]  ),
            .I_tvalid(morph_vc[gi]  ),
            .I_tuser (morph_uc[gi]  ),
            .I_tlast (morph_lc[gi]  ),
            .O_tdata (morph_dc[gi+1]),
            .O_tvalid(morph_vc[gi+1]),
            .O_tuser (morph_uc[gi+1]),
            .O_tlast (morph_lc[gi+1])
        );
    end
endgenerate

//---- SW1 二值化开关处理 ----
//异步开关信号两级同步，并在帧起始(tuser)拍采样生效，避免拨动瞬间帧内切换产生撕裂
reg [1:0] bin_en_sync;
reg       bin_en_r;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n)
        bin_en_sync <= 2'b00;
    else
        bin_en_sync <= {bin_en_sync[0], I_bin_en};
end
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n)
        bin_en_r <= 1'b0;                       //上电默认彩色原图
    else if (awb_O_tuser)
        bin_en_r <= bin_en_sync[1];
end

// 彩色路径延迟一拍；二值路径另有四级形态学延迟。
// 帧间切换要求消隐足以让两条路径排空。
reg [95:0] awb_tdata_d1;
reg        awb_tvalid_d1, awb_tuser_d1;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        awb_tdata_d1  <= 96'd0;
        awb_tvalid_d1 <= 1'b0;
        awb_tuser_d1  <= 1'b0;
    end else begin
        awb_tdata_d1  <= awb_O_tdata;
        awb_tvalid_d1 <= awb_O_tvalid;
        awb_tuser_d1  <= awb_O_tuser;
    end
end

//2选1：bin_en_r=1 送二值化图像，0 送彩色原图
// Return canonical pixel 0 to the high bits for the existing DDR packer.
wire [95:0] morph_display_data = {morph_dc[MORPH_ITER][23:0],
                                  morph_dc[MORPH_ITER][47:24],
                                  morph_dc[MORPH_ITER][71:48],
                                  morph_dc[MORPH_ITER][95:72]};
wire [95:0] effects_data;
wire effects_valid,effects_sof,effects_last;
wire effects_frame_start;
reg [5:0] enhance_control_meta,enhance_control_sync;
reg [1:0] enhance_compare_sync;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) enhance_compare_sync<=0;
    else enhance_compare_sync<={enhance_compare_sync[0],I_enhance_compare};
end
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) begin enhance_control_meta<={2'd2,4'd4};enhance_control_sync<={2'd2,4'd4};end
    else begin enhance_control_meta<={I_enhance_strength,I_enhance_noise};enhance_control_sync<=enhance_control_meta;end
end
wire enhance_mode=VIDEO_MODES && bin_en_r && morph_mode_r==2'b11;
wire next_frame_enhance=VIDEO_MODES && bin_en_sync[1] && morph_mode_sync2==2'b11;
wire next_frame_has_row_delay=VIDEO_MODES &&
    ((!bin_en_sync[1] && morph_mode_sync2[1]) || next_frame_enhance);
assign O_frame_start=(m_aixs_tuser && !next_frame_has_row_delay) ||
                     (effects_frame_start && (!bin_en_r || enhance_mode));
generate if(VIDEO_MODES) begin : g_video_modes
    img_video_modes #(.DEBUG_CAPTURE(DEBUG_CAPTURE)) u_video_modes (
        .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),
        .I_tdata(awb_geometry_data),.I_tvalid(awb_O_tvalid),
        .I_tuser(awb_sof),.I_tlast(awb_eol),.I_mode(morph_mode_r),.I_enhance(enhance_mode),
        .I_enhance_strength(enhance_control_sync[5:4]),.I_enhance_noise(enhance_control_sync[3:0]),
        .I_enhance_compare(enhance_compare_sync[1]),
        .O_tdata(effects_data),.O_tvalid(effects_valid),
        .O_tuser(effects_sof),.O_tlast(effects_last),.O_frame_start(effects_frame_start));
end else begin : g_original_preview
    assign effects_data=96'd0;
    assign effects_valid=1'b0;assign effects_sof=1'b0;assign effects_last=1'b0;
    assign effects_frame_start=1'b0;
end endgenerate
wire [95:0] effects_display_data={effects_data[23:0],effects_data[47:24],
                                 effects_data[71:48],effects_data[95:72]};
// RGB keeps the physically verified one-clock AWB preview path. Do not
// force the original image through a neighbourhood algorithm or row replay.
wire use_effects=VIDEO_MODES && ((!bin_en_r && morph_mode_r!=0) || enhance_mode);
wire [95:0] mux_base_data = enhance_mode ? effects_display_data :
                           bin_en_r ? morph_display_data :
                           use_effects ? effects_display_data : awb_tdata_d1;
wire        mux_tvalid = enhance_mode ? effects_valid :
                        bin_en_r ? morph_vc[MORPH_ITER] :
                        use_effects ? effects_valid : awb_tvalid_d1;
wire        mux_tuser = enhance_mode ? effects_sof :
                       bin_en_r ? morph_uc[MORPH_ITER] :
                       use_effects ? effects_sof : awb_tuser_d1;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) O_display_mode<=0;
    else if(mux_tuser) O_display_mode<=bin_en_r ? {1'b1,morph_mode_r} :
                                              VIDEO_MODES ? {1'b0,morph_mode_r} : 3'd0;
end

// Draw the per-row white-board boundary on RGB and binary preview. Boundary
// banks are latched at preview SOF. The overlay never feeds recognition.
wire board_bank;
wire [16:0] board_row,board_prev,board_next;
reg preview_bank,preview_board_valid;
reg [8:0] preview_beat;
reg [10:0] preview_line;
wire [8:0] preview_b=mux_tuser ? 9'd0 : preview_beat;
wire [10:0] preview_y=mux_tuser ? 11'd0 : preview_line;
wire query_bank=mux_tuser ? board_bank : preview_bank;
wire boundary_valid=mux_tuser ? O_roi_valid : preview_board_valid;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        preview_bank<=0;preview_board_valid<=0;preview_beat<=0;preview_line<=0;
    end else begin
        if(mux_tuser) begin
            preview_bank<=board_bank;preview_board_valid<=O_roi_valid;
            preview_beat<=0;preview_line<=0;
        end
        if(mux_tvalid) begin
            if(preview_b==319) begin preview_beat<=0;preview_line<=preview_y+1'b1;end
            else begin preview_beat<=preview_b+1'b1;preview_line<=preview_y;end
        end
    end
end
reg [95:0] mux_tdata;
integer outline_p;
reg [10:0] outline_x;
reg [7:0] outline_cell;
reg outline_on;
always @* begin
    mux_tdata=mux_base_data;outline_x=0;outline_cell=0;outline_on=0;
    for(outline_p=0;outline_p<4;outline_p=outline_p+1) begin
        outline_x={preview_b,2'b00}+outline_p;
        outline_cell=outline_x[10:3];
        outline_on=SHOW_BOARD_BOUNDARY && TIRE_MODE && boundary_valid && board_row[16] &&
            outline_cell>=board_row[15:8] && outline_cell<=board_row[7:0] &&
            (outline_x=={board_row[15:8],3'b000} || outline_x=={board_row[7:0],3'b111} ||
             (preview_y[2:0]==0 && (!board_prev[16] || outline_cell<board_prev[15:8] || outline_cell>board_prev[7:0])) ||
             (preview_y[2:0]==7 && (!board_next[16] || outline_cell<board_next[15:8] || outline_cell>board_next[7:0])));
        if(outline_on) mux_tdata[(3-outline_p)*24+:24]=24'h0080ff;
    end
end

// 两级检测第一级：先框住背光板白区，框外强制为背景（亮），
// 测量支路只在白区内找黑色工件；预览/形态学支路不受影响。
wire [95:0] roi_O_tdata;
wire        roi_O_tvalid, roi_O_tuser, roi_O_tlast;
generate if (!TIRE_MODE) begin : g_roi_legacy
img_roi #(
    .BEATS_PER_LINE (320),
    .LINES_PER_FRAME (720)
) u_img_roi (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tdata (bin_O_tdata),
    .I_tvalid(bin_O_tvalid),
    .I_tuser (bin_O_tuser),
    .I_tlast (bin_O_tlast),
    .O_tdata (roi_O_tdata),
    .O_tvalid(roi_O_tvalid),
    .O_tuser (roi_O_tuser),
    .O_tlast (roi_O_tlast),
    .O_x0(O_roi_x0), .O_x1(O_roi_x1),
    .O_y0(O_roi_y0), .O_y1(O_roi_y1),
    .O_valid(O_roi_valid),
    .O_upd  (O_roi_upd)
);
assign board_bank=1'b0;
assign board_row=17'd0;
assign board_prev=17'd0;
assign board_next=17'd0;
end endgenerate

generate if (TIRE_MODE) begin : g_tire
    img_tire #(.BEATS_PER_LINE(320), .LINES_PER_FRAME(720),
        .FG_IS_WHITE(MEAS_FG_IS_WHITE),.WHITE_BOARD(1),.COLOR_MODE(1),.PARTS_MODE(PARTS_MODE),
        .COLOR_CALIBRATION(COLOR_STABILITY),.MULTI_TARGETS(MULTI_TARGETS),
        .LATENCY_DIAGNOSTICS(LATENCY_DIAGNOSTICS)) u_tire (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
        .I_tdata(bin_O_tdata), .I_tvalid(bin_O_tvalid),
        .I_rgb(recognition_rgb), .O_color(O_bbox_color),
        .I_tuser(bin_O_tuser), .I_tlast(bin_O_tlast),
        .I_roi_valid(1'b0), .I_roi_x0(11'd0), .I_roi_x1(11'd1279),
        .I_roi_y0(11'd0), .I_roi_y1(11'd719),
        .O_board_x0(O_roi_x0),.O_board_x1(O_roi_x1),
        .O_board_y0(O_roi_y0),.O_board_y1(O_roi_y1),
        .O_board_valid(O_roi_valid),.O_board_bank(board_bank),
        .I_query_bank(query_bank),.I_query_row({1'b0,preview_y[9:3]}),
        .O_query_row(board_row),.O_query_prev(board_prev),.O_query_next(board_next),
        .O_x0(O_bbox_x0), .O_x1(O_bbox_x1), .O_y0(O_bbox_y0), .O_y1(O_bbox_y1),
        .O_cx(O_bbox_cx), .O_cy(O_bbox_cy), .O_w(O_bbox_w), .O_h(O_bbox_h),
        .O_area(O_bbox_area), .O_type(O_bbox_type), .O_valid(O_bbox_valid),
        .O_upd(O_bbox_upd), .O_moving(O_bbox_moving), .O_cnt(O_bbox_cnt),
        .O_span(O_proj_span), .O_hole(O_proj_hole),
        .O_hx(O_proj_hx), .O_hy(O_proj_hy),
        .O_ring_valid(O_proj_valid), .O_status(O_proj_status),
        .I_color_reference(O_color_reference[15:8]),.I_color_epoch(color_epoch),
        .I_color_ready(awb_freeze_s && O_color_reference[26:24]==3'b111),
        .O_color_diag(O_color_diag),.O_targets(O_targets),.O_target_count(O_target_count),.O_target_overflow(O_target_overflow),
        .O_latency_bcd(O_latency_bcd),.O_latency_valid(O_latency_valid),.O_latency_upd(O_latency_upd));
    assign O_roi_upd=O_bbox_upd;
    assign O_proj_upd=O_bbox_upd;
    assign O_proj_cx=O_proj_valid ? O_bbox_cx : 11'd0;
    assign O_proj_cy=O_proj_valid ? O_bbox_cy : 11'd0;
end else begin : g_legacy_measurement
assign O_latency_bcd=0;assign O_latency_valid=0;assign O_latency_upd=0;
assign O_bbox_color=3'd0;
assign O_color_diag=128'd0;
assign O_targets=0;assign O_target_count=0;assign O_target_overflow=0;
// Measure raw binary geometry. SW2/SW3 affect the preview, not dimensions.
img_proj #(
    .BEATS_PER_LINE (320),
    .LINES_PER_FRAME (720),
    .FG_IS_WHITE (MEAS_FG_IS_WHITE)
) u_img_proj (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tdata (roi_O_tdata),
    .I_tvalid(roi_O_tvalid),
    .I_tuser (roi_O_tuser),
    .I_tlast (roi_O_tlast),
    .O_span  (O_proj_span),
    .O_hole  (O_proj_hole),
    .O_valid (O_proj_valid),
    .O_status(O_proj_status),
    .O_center_x(O_proj_cx), .O_center_y(O_proj_cy),
    .O_hole_x(O_proj_hx), .O_hole_y(O_proj_hy),
    .O_upd   (O_proj_upd)
);

// 前景最小外接矩形：任意形状工件通用（与 img_proj 同源，形态学之前的
// 原始二值几何；多目标/噪点也会并入同一个框，预览形态学不会清理此框）。
// 附带运动检测、虚拟检测线越线计数（LINE_X 需与 mixer 的竖线画位一致）
// 和几何分类（孔径特征取 img_proj 同帧测量：proj 帧尾发布、保持到下帧尾，
// bbox 下一帧 SOF 发布时读到的正是同一帧的孔径）
img_bbox #(
    .BEATS_PER_LINE (320),
    .LINES_PER_FRAME (720),
    .FG_IS_WHITE (MEAS_FG_IS_WHITE),
    .LINE_X        (11'd640),
    .LINE_HYST     (11'd32 ),
    .MOTION_THRESH (11'd4  ),
    .HOLE_MIN      (16'd6  )
) u_img_bbox (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tdata (roi_O_tdata),
    .I_tvalid(roi_O_tvalid),
    .I_tuser (roi_O_tuser),
    .I_tlast (roi_O_tlast),
    .I_hole      (O_proj_hole  ),
    .I_hole_valid(O_proj_valid ),
    .O_x0(O_bbox_x0), .O_x1(O_bbox_x1),
    .O_y0(O_bbox_y0), .O_y1(O_bbox_y1),
    .O_cx(O_bbox_cx), .O_cy(O_bbox_cy),
    .O_w (O_bbox_w),  .O_h (O_bbox_h),
    .O_area(O_bbox_area), .O_type(O_bbox_type),
    .O_moving(O_bbox_moving),
    .O_cnt_bcd(O_bbox_cnt),
    .O_valid(O_bbox_valid),
    .O_upd  (O_bbox_upd)
);

end endgenerate

    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( mux_tuser	    ),
        .I_96b_valid        ( mux_tvalid 		),
        .I_96b_data         ( mux_tdata		),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule

// 75th-percentile, 16-bin pre-AWB luminance. One pixel every 8x8 cell,
// excluding a 1/16 border, prevents a small central part from owning AE.
// Dark/clipped pixels remain measurements; malformed/incomplete frames do not.
module camera_exposure_meter #(
    parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720
)(input wire I_clk,I_rst_n,input wire [95:0] I_tdata,
  input wire I_tvalid,I_tuser,I_tlast,
  output reg [7:0] O_luma,output reg O_valid,O_upd);
    localparam integer XLO=IMG_WIDTH/16,XHI=IMG_WIDTH-IMG_WIDTH/16;
    localparam integer YLO=IMG_HEIGHT/16,YHI=IMG_HEIGHT-IMG_HEIGHT/16;
    localparam integer NX=(XHI+7)/8-(XLO+7)/8;
    localparam integer NY=(YHI+7)/8-(YLO+7)/8;
    localparam integer EXPECTED=NX*NY;
    reg [10:0] x,y;
    reg seen,bad,complete,user_d;
    reg [15:0] histogram[0:15];
    reg [15:0] count,rank,prefix;
    reg scanning,snapshot_valid,chosen_valid;
    reg [3:0] bin_index,chosen;
    wire sof=I_tuser && !user_d;
    wire [10:0] cx=sof ? 11'd0:x;
    wire [10:0] cy=sof ? 11'd0:y;
    // Pixel 0 is the high 24-bit lane in the canonical RGB packet.
    wire [9:0] luma_sum={2'd0,I_tdata[95:88]}+
        {1'd0,I_tdata[87:80],1'b0}+{2'd0,I_tdata[79:72]};
    wire sample=I_tvalid && seen && !bad && cx>=XLO && cx<XHI &&
        cy>=YLO && cy<YHI && cx[2:0]==0 && cy[2:0]==0;
    wire [16:0] next_prefix={1'b0,prefix}+histogram[bin_index];
    wire hit=!chosen_valid && next_prefix>=rank;
    integer i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x<=0;y<=0;seen<=0;bad<=0;complete<=0;user_d<=0;count<=0;
            rank<=0;prefix<=0;scanning<=0;snapshot_valid<=0;
            chosen_valid<=0;bin_index<=0;chosen<=0;
            O_luma<=0;O_valid<=0;O_upd<=0;
            for(i=0;i<16;i=i+1) histogram[i]<=0;
        end else begin
            user_d<=I_tuser;
            if(sof) begin
                snapshot_valid<=seen && !bad && complete && count==EXPECTED && EXPECTED>0;
                rank<=count-(count>>2);prefix<=0;chosen_valid<=0;
                scanning<=1;bin_index<=0;count<=0;
                x<=0;y<=0;seen<=1;bad<=0;complete<=0;
            end else if(scanning) begin
                histogram[bin_index]<=0;
                prefix<=next_prefix[15:0];
                if(hit) begin chosen<=bin_index;chosen_valid<=1;end
                if(bin_index==15) begin
                    scanning<=0;O_valid<=snapshot_valid && rank!=0 && (chosen_valid || hit);
                    if(snapshot_valid && rank!=0)
                        O_luma<=hit ? {bin_index,4'h8}:{chosen,4'h8};
                    O_upd<=~O_upd;
                end else bin_index<=bin_index+1'b1;
            end
            if(I_tvalid && (seen || sof)) begin
                if(cx>=IMG_WIDTH || cy>=IMG_HEIGHT || I_tlast!=(cx==IMG_WIDTH-4)) bad<=1;
                if(cx==IMG_WIDTH-4) begin
                    x<=0;y<=cy+1'b1;
                    if(cy==IMG_HEIGHT-1) complete<=1;
                end else x<=cx+11'd4;
            end
            if(sample && !sof) begin
                if(scanning) bad<=1;
                else begin histogram[luma_sum[9:6]]<=histogram[luma_sum[9:6]]+1'b1;count<=count+1'b1;end
            end
        end
    end
endmodule
