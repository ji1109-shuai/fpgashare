module hdmi_mixer #(
    parameter H_OFFSET = 128,
    parameter V_OFFSET = 60,
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer DEBUG_MODE = 0,
    // 0: data accompanies I_video_de; 2: video_out returns data two
    // request clocks later, already aligned with S_video_de_2d.
    parameter integer VIDEO_READ_LATENCY = 0,
    parameter integer DISPLAY_MODES = 0,
    parameter integer TARGET_ONLY = 0, // wrapper enables clean, confirmed-target display
    parameter integer PARTS_MODE = 0,   // same classification vocabulary as isp_top
    parameter integer CAMERA_CONTROL = 0,
    parameter integer AE_DIAGNOSTICS = 0,
    parameter integer COLOR_DIAGNOSTICS = 0,
    parameter integer SHOW_LOGO = 0,
    parameter integer COMPACT_DIAGNOSTICS = 0,
    parameter integer MULTI_TARGETS = 0,
    // Display-domain box interpolation.  Detection packets arrive more slowly
    // than HDMI frames, so advancing a confirmed box a few pixels per display
    // frame makes conveyor motion look continuous without touching recognition.
    parameter integer BOX_TRACKING = 0,
    parameter integer BOX_TRACK_STEP = 8,
    parameter integer BOX_TRACK_SNAP = 96,
    parameter integer WB_DIAGNOSTICS = 0,
    parameter integer AUTO_WHITE_BALANCE = 0,
    parameter integer LATENCY_DIAGNOSTICS = 0,
    parameter integer FPS_DISPLAY = 0,
    parameter integer LATENCY_DISPLAY_TICK_CYCLES = 7500
)(
    input wire        I_clk,
    input wire        I_rst_n,

    input wire        I_video_vsync,
    input wire        I_video_hsync,
    input wire        I_video_de,
    input wire        I_video_user,
    input wire        I_video_last,

    input wire[3:0]   I_debug_status,

    output wire       O_video_rd_en,
    input wire[23:0]  I_video_rd_data,

    input wire        I_meas_upd,        // 测量值更新翻转标志（摄像头域，2级同步后锁存）
    input wire [15:0] I_span,            // Outer diameter, pixels; see I_meas_valid
    input wire [15:0] I_hole,            // Hole diameter, pixels; see I_meas_valid
    input wire        I_meas_valid,
    input wire [2:0]  I_meas_status,
    input wire [10:0] I_center_x, I_center_y,
    input wire [10:0] I_hole_x, I_hole_y,
    input wire        I_thresh_upd,      // 自适应阈值更新翻转标志
    input wire [7:0]  I_thresh,          // 自适应阈值（Otsu）

    input wire        I_bbox_upd,        // 外接矩形更新翻转标志（摄像头域）
    input wire [10:0] I_bbox_x0,         // 前景外接矩形：最左/最右像素x
    input wire [10:0] I_bbox_x1,
    input wire [10:0] I_bbox_y0,         // 最上/最下像素y
    input wire [10:0] I_bbox_y1,
    input wire [10:0] I_bbox_cx,         // 外接矩形中心/宽高（测量侧算好）
    input wire [10:0] I_bbox_cy,
    input wire [10:0] I_bbox_w,
    input wire [10:0] I_bbox_h,
    input wire [19:0] I_bbox_area,      // 框内前景像素数
    input wire [2:0]  I_bbox_type,      // 几何分类 0NONE 1BAR 2RING 3NUT 4DISC 5BLOCK
    input wire [2:0]  I_bbox_color,
    input wire [2:0]  I_display_mode,
    input wire [28:0] I_camera_status,
    input wire I_camera_status_upd,
    input wire [24:0] I_ae_diagnostics,
    input wire I_ae_diagnostics_upd,
    input wire [31:0] I_color_reference,
    input wire I_color_reference_upd,
    input wire [127:0] I_color_diag,
    input wire [127:0] I_wb_diag,
    input wire I_wb_diag_upd,
    input wire [223:0] I_targets,
    input wire [2:0] I_target_count,
    input wire I_target_overflow,
    input wire [47:0] I_batch_counts_bcd,
    input wire [47:0] I_batch_total_counts_bcd,
    input wire I_batch_wait_clear,
    input wire [1:0] I_enhance_strength,
    input wire [3:0] I_enhance_noise,
    input wire I_enhance_compare,
    input wire [47:0] I_batch_targets_bcd,
    input wire [2:0] I_batch_filter_type,
    input wire I_batch_done,
    input wire I_batch_overrun,
    input wire [3:0] I_batch_overrun_mask,
    input wire I_menu_open,
    input wire [3:0] I_menu_index,
    input wire [2:0] I_menu_preview_mode,
    input wire [2:0] I_menu_motor_level,
    input wire I_menu_awb_freeze,
    input wire I_menu_ae_auto,
    input wire I_menu_ae_locked,
    input wire [4:0] I_menu_ae_target_level,
    input wire [15:0] I_latency_bcd,
    input wire I_latency_valid,I_latency_upd,
    input wire [11:0] I_fps_bcd,
    input wire I_fps_update,
    input wire        I_bbox_moving,     // 1=工件运动中（帧间位移超阈值）
    input wire [23:0] I_bbox_cnt,        // 工件计数 BCD {d5..d0}
    input wire        I_bbox_valid,      // 本帧存在前景
    input wire        I_roi_upd,         // 背光板白区 ROI 更新翻转标志（摄像头域）
    input wire [10:0] I_roi_x0, I_roi_x1, I_roi_y0, I_roi_y1,
    input wire        I_roi_valid,

    output reg        O_hdmi_vsync,
    output reg        O_hdmi_hsync,
    output reg        O_hdmi_de,
    output reg[23:0]  O_hdmi_data
);

    reg        S_video_vsync_1d;
    reg        S_video_vsync_2d;
    reg        S_video_hsync_1d;
    reg        S_video_hsync_2d;
    reg        S_video_de_1d;
    reg        S_video_de_2d;
    reg [23:0] S_video_data_1d;
    reg [23:0] S_video_data_2d;
    wire [23:0] S_aligned_video_data = (VIDEO_READ_LATENCY == 2) ?
                                      I_video_rd_data : S_video_data_2d;
    reg [11:0] S_x;
    reg [11:0] S_y;
    reg [11:0] S_x_1d;
    reg [11:0] S_x_2d;
    reg [11:0] S_y_1d;
    reg [11:0] S_y_2d;

    localparam [11:0] CONTROL_X=SHOW_LOGO ? 12'd176:12'd16;
    localparam [11:0] LATENCY_X=IMG_WIDTH-192;
    localparam [11:0] MENU_X=12'd976;
    localparam [11:0] MENU_Y=12'd48;
    localparam [11:0] MENU_W=12'd288;
    localparam [11:0] MENU_H=12'd368;
    localparam LOGO_X = 12'd0;
    localparam LOGO_Y = 12'd0;
    localparam LOGO_W = 12'd160;
    localparam LOGO_H = 12'd160;

    localparam COLOR_LOGO_BLUE   = 24'h1f315c;
    localparam COLOR_LOGO_RED    = 24'hec1c2d;
    localparam COLOR_TEXT        = 24'h00e6ff;
    localparam DYN_OSD_X         = 12'd375;
    localparam DYN_OSD_Y         = 12'd120;
    localparam DYN_OSD_W         = 12'd200;
    localparam DYN_OSD_H         = 12'd24;
    localparam CN_Y_OFFSET       = 12'd2;
    localparam COLOR_DYN_TEXT    = 24'hfff200;
    localparam CHAR_AN           = 8'h80;
    localparam CHAR_LU           = 8'h81;
    localparam CHAR_C            = 8'h43;
    localparam CHAR_N            = 8'h4e;
    localparam CHAR_T            = 8'h54;
    localparam CHAR_0            = 8'h30;
    localparam CHAR_COLON        = 8'h3a;
    localparam CHAR_SLASH        = 8'h2f;
    localparam CHAR_W            = 8'h57;
    localparam CHAR_I            = 8'h49;

    // Measurement display positions and colors.
    localparam W2_X        = 12'd375;
    localparam W2_Y        = 12'd152;
    localparam W2_W        = 12'd96;
    localparam STATUS_Y    = 12'd248;
    localparam W3_X        = 12'd375;
    localparam W3_Y        = 12'd184;
    localparam W4_X        = 12'd375;
    localparam W4_Y        = 12'd216;
    localparam COLOR_WIDTH = 24'h00ff00;
    localparam COLOR_HOLE  = 24'h00ffff;
    localparam COLOR_THRESH = 24'hffffff;
    localparam COLOR_BOX    = 24'hff00ff;   // 外接矩形边框（品红=锁定/静止）
    localparam COLOR_MOVE   = 24'hffff00;   // 运动中的边框/状态字（黄色）
    localparam COLOR_PROBE  = 24'h808080;   // 虚拟检测线（中灰竖线）
    localparam COLOR_ROI    = 24'h0080ff;   // 背光板白区 ROI 框（蓝色，测量只在框内）
    localparam MOTION_Y     = 12'd280;      // M:MOVE/LOCK 状态行
    localparam TYPE_Y       = 12'd312;      // 几何分类行（RING/NUT/…）
    localparam COLOR_Y      = 12'd336;
    localparam MODE_Y       = 12'd360;
    localparam PROBE_X      = 12'd640;      // 虚拟检测线 x（与 img_bbox.LINE_X 一致！）

    // Slow, frame-held camera-domain mode. Synchronize, require a stable
    // sample and only publish at a display frame boundary.
    reg [2:0] mode_sync1,mode_sync2,mode_sample,display_mode;
    // Source BCD packet is held long before the next toggle. Capture after
    // the two-stage event synchronizer and publish only at a frame boundary.
    reg [1:0] camera_sync;
    reg camera_seen;
    reg [28:0] camera_pending,camera_display;
    reg [1:0] ae_diag_sync;
    reg ae_diag_seen;
    reg [24:0] ae_diag_pending,ae_diag_frame;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            ae_diag_sync<=0;ae_diag_seen<=0;ae_diag_pending<=0;ae_diag_frame<=0;
        end else if(AE_DIAGNOSTICS) begin
            ae_diag_sync<={ae_diag_sync[0],I_ae_diagnostics_upd};
            ae_diag_seen<=ae_diag_sync[1];
            if(ae_diag_seen!=ae_diag_sync[1]) ae_diag_pending<=I_ae_diagnostics;
            if(I_video_user) ae_diag_frame<=ae_diag_pending;
        end
    end
    reg [1:0] reference_sync,colour_sync;
    reg reference_seen,colour_seen;
    reg [31:0] reference_pending,reference_display;
    reg [127:0] colour_pending,colour_display;
    reg [1:0] wb_sync;
    reg wb_seen;
    reg [127:0] wb_pending,wb_display;
    // The source holds {valid,BCD} until the next analysed batch (many ms).
    // Synchronize its event, capture the held packet, publish only at SOF.
    (* ASYNC_REG="TRUE" *) reg [1:0] latency_sync;
    reg latency_seen;
    reg [16:0] latency_pending,latency_display;
    localparam LATENCY_DIV_BITS=$clog2(LATENCY_DISPLAY_TICK_CYCLES+1);
    reg [LATENCY_DIV_BITS-1:0] latency_age_div;
    reg [13:0] latency_age;
    (* ASYNC_REG="TRUE" *) reg [1:0] fps_sync;
    reg fps_seen,fps_received,fps_frame_valid;
    reg [11:0] fps_pending,fps_frame;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            fps_sync<=0;fps_seen<=0;fps_pending<=0;fps_frame<=0;
            fps_received<=0;fps_frame_valid<=0;
        end else if(FPS_DISPLAY) begin
            fps_sync<={fps_sync[0],I_fps_update};fps_seen<=fps_sync[1];
            if(fps_seen!=fps_sync[1]) begin fps_pending<=I_fps_bcd;fps_received<=1;end
            if(I_video_user) begin fps_frame<=fps_pending;fps_frame_valid<=fps_received;end
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            latency_sync<=0;latency_seen<=0;latency_pending<=0;latency_display<=0;
            latency_age_div<=0;latency_age<=14'd10000;
        end else if(LATENCY_DIAGNOSTICS) begin
            latency_sync<={latency_sync[0],I_latency_upd};latency_seen<=latency_sync[1];
            if(latency_seen!=latency_sync[1]) begin
                latency_pending<={I_latency_valid,I_latency_bcd};latency_age<=0;latency_age_div<=0;
            end else if(latency_age<10000) begin
                if(latency_age_div==LATENCY_DISPLAY_TICK_CYCLES-1) begin
                    latency_age_div<=0;latency_age<=latency_age+1'b1;
                end else latency_age_div<=latency_age_div+1'b1;
            end
            if(I_video_user) latency_display<={latency_pending[16] && latency_age<10000,latency_pending[15:0]};
        end
    end
    function [7:0] latency_char;
        input [3:0] index;
        begin
            case(index)
                0:latency_char="D";1:latency_char="E";2:latency_char="T";3:latency_char=":";
                4:latency_char=latency_display[16] ? {4'h3,latency_display[15:12]}:"-";
                5:latency_char=latency_display[16] ? {4'h3,latency_display[11:8]}:"-";
                6:latency_char=latency_display[16] ? {4'h3,latency_display[7:4]}:"-";
                7:latency_char=".";
                8:latency_char=latency_display[16] ? {4'h3,latency_display[3:0]}:"-";
                9:latency_char="m";10:latency_char="s";default:latency_char=" ";
            endcase
        end
    endfunction
    // One frame-held source packet, independent of reference validity.
    // Capture after the event synchronizer; publish only at display SOF.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            wb_sync<=0;wb_seen<=0;wb_pending<=0;wb_display<=0;
        end else if(WB_DIAGNOSTICS) begin
            wb_sync<={wb_sync[0],I_wb_diag_upd};wb_seen<=wb_sync[1];
            if(wb_seen!=wb_sync[1]) wb_pending<=I_wb_diag;
            if(I_video_user) wb_display<=wb_pending;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            reference_sync<=0;colour_sync<=0;reference_seen<=0;colour_seen<=0;
            reference_pending<=0;reference_display<=0;colour_pending<=0;colour_display<=0;
        end else if(COLOR_DIAGNOSTICS) begin
            reference_sync<={reference_sync[0],I_color_reference_upd};reference_seen<=reference_sync[1];
            colour_sync<={colour_sync[0],I_bbox_upd};colour_seen<=colour_sync[1];
            if(reference_seen!=reference_sync[1]) reference_pending<=I_color_reference;
            if(colour_seen!=colour_sync[1]) colour_pending<=I_color_diag;
            if(I_video_user) begin reference_display<=reference_pending;colour_display<=colour_pending;end
        end
    end
    function [7:0] colour_hex;
        input [3:0] nibble;
        begin colour_hex=nibble<10 ? 8'h30+{4'd0,nibble}:8'h41+{4'd0,nibble}-8'd10;end
    endfunction
    function [7:0] wb_diagnostic_char;
        input [2:0] row;
        input [3:0] index;
        reg [127:0] text_bits;
        reg [15:0] first,second;
        reg [7:0] selected_char;
        reg selected;
        begin
            text_bits="                ";first=0;second=0;selected=0;selected_char=32;
            case(row)
                1:begin
                    text_bits="RAW:------      ";
                    if(wb_display[19:9]!=0 && wb_display[8:5]!=6 && index>=4 && index<10) begin
                        selected_char=colour_hex(wb_display[104+(9-index)*4+:4]);selected=1;
                    end
                end
                2,3,4:begin
                    case(row)
                        2:begin text_bits="R:0000 B:0000   ";first=wb_display[103:88];second=wb_display[83:68];end
                        3:begin text_bits="OK:0000 N:0000  ";first={5'd0,wb_display[63:53]};second={5'd0,wb_display[19:9]};end
                        default:begin text_bits="HI:0000 LO:0000 ";first={5'd0,wb_display[52:42]};second={5'd0,wb_display[41:31]};end
                    endcase
                    if(row==2) begin
                        if(index>=2 && index<6) begin selected_char=colour_hex(first[(5-index)*4+:4]);selected=1;end
                        if(index>=9 && index<13) begin selected_char=colour_hex(second[(12-index)*4+:4]);selected=1;end
                    end else begin
                        if(index>=3 && index<7) begin selected_char=colour_hex(first[(6-index)*4+:4]);selected=1;end
                        if(row==3 && index>=10 && index<14) begin selected_char=colour_hex(second[(13-index)*4+:4]);selected=1;end
                        if(row==4 && index>=11 && index<15) begin selected_char=colour_hex(second[(14-index)*4+:4]);selected=1;end
                    end
                end
                5:begin
                    text_bits="CAST:0000       ";
                    first={5'd0,wb_display[30:20]};
                    if(index>=5 && index<9) begin selected_char=colour_hex(first[(8-index)*4+:4]);selected=1;end
                end
                6:begin
                    case(wb_display[8:5])
                        0:text_bits=wb_display[19:9]!=0 ? "SMP:OK          ":"SMP:WAIT        ";
                        1:text_bits="SMP:EMPTY       ";2:text_bits="SMP:CLIP        ";
                        3:text_bits="SMP:DARK        ";4:text_bits="SMP:CAST        ";
                        5:text_bits="SMP:FEW         ";default:text_bits="SMP:STREAM      ";
                    endcase
                end
            endcase
            wb_diagnostic_char=selected ? selected_char:text_bits[127-index*8-:8];
        end
    endfunction
    function [7:0] colour_diagnostic_char;
        input [2:0] row;
        input [3:0] index;
        reg [127:0] text_bits;
        reg [15:0] number;
        reg [7:0] selected_char;
        reg selected;
        begin
            text_bits="                ";number=0;selected_char=32;selected=0;
            case(row)
                0:begin
                    text_bits=reference_display[26] ? "WB:LOCK REF:WAIT":"WB:CAL  REF:WAIT";
                    if(reference_display[25:24]==3) text_bits=reference_display[26] ? "WB:LOCK REF:OK  ":"WB:CAL  REF:OK  ";
                    else if(!reference_display[24]) text_bits=reference_display[26] ? "WB:LOCK REF:BAD ":"WB:CAL  REF:BAD ";
                    if(AUTO_WHITE_BALANCE) text_bits=!reference_display[26] ? "WB:WAIT         ":
                        reference_display[24] ? "WB:AUTO         ":"WB:HOLD         ";
                end
                1:begin
                    text_bits="REF:------      ";
                    if(reference_display[24] && index>=4 && index<10)
                        begin selected_char=colour_hex(reference_display[(9-index)*4+:4]);selected=1;end
                end
                2:begin
                    text_bits="RGB:------      ";
                    if(colour_display[19] && index>=4 && index<10)
                        begin selected_char=colour_hex(colour_display[104+(9-index)*4+:4]);selected=1;end
                end
                3,4:begin
                    text_bits=row==3 ? "R:0000 S:0000   ":"Y:0000 K:0000   ";
                    number=row==3 ? (index<7 ? colour_display[103:88]:colour_display[87:72]):
                        (index<7 ? colour_display[71:56]:colour_display[55:40]);
                    if(index>=2 && index<6) begin selected_char=colour_hex(number[(5-index)*4+:4]);selected=1;end
                    if(index>=9 && index<13) begin selected_char=colour_hex(number[(12-index)*4+:4]);selected=1;end
                end
                5:begin
                    text_bits="N:0000 CL:0 F:0 ";
                    if(index>=2 && index<6) begin selected_char=colour_hex(colour_display[24+(5-index)*4+:4]);selected=1;end
                    if(index==10) begin selected_char=colour_display[21] ? "1":"0";selected=1;end
                    if(index==14) begin selected_char=colour_display[18] ? "1":"0";selected=1;end
                end
                6:begin
                    case(colour_display[14:11])
                        0:text_bits="WHY:OK          ";1:text_bits="WHY:CAL         ";
                        2:text_bits="WHY:EMPTY       ";3:text_bits="WHY:SAMPLE      ";
                        4:text_bits="WHY:MIXED       ";5:text_bits="WHY:CONFIRM     ";
                        6:text_bits="WHY:DARK        ";7:text_bits="WHY:CLIP        ";
                        8:text_bits="WHY:STREAM      ";
                        default:text_bits="WHY:WAIT        ";
                    endcase
                end
            endcase
            colour_diagnostic_char=selected ? selected_char:text_bits[127-index*8-:8];
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            camera_sync<=0;camera_seen<=0;camera_pending<=0;camera_display<=0;
        end else if(CAMERA_CONTROL) begin
            camera_sync<={camera_sync[0],I_camera_status_upd};camera_seen<=camera_sync[1];
            if(camera_seen!=camera_sync[1]) camera_pending<=I_camera_status;
            if(I_video_user) camera_display<=camera_pending;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin mode_sync1<=0;mode_sync2<=0;mode_sample<=0;display_mode<=0;end
        else begin
            mode_sync1<=I_display_mode;mode_sync2<=mode_sync1;mode_sample<=mode_sync2;
            if(I_video_user && mode_sample==mode_sync2) display_mode<=mode_sample;
        end
    end
    reg [1:0] visual_compare_sync;
    reg visual_compare_frame;
    function [7:0] display_mode_char;
        input [2:0] mode;
        input [2:0] index;
        reg [39:0] word_bits;
        begin
            case(mode)
                0: word_bits="RGB  ";1: word_bits="GRAY ";
                2: word_bits="SOBEL";3: word_bits="EDGE ";
                5: word_bits="ERODE";6: word_bits="DILAT";
                7: word_bits=visual_compare_frame ? "SPLIT":"ENHN ";
                default: word_bits="BIN  ";
            endcase
            display_mode_char=word_bits>>((4-index)*8);
        end
    endfunction

    //---- 测量值 CDC：翻转标志2级同步，检测到翻转后锁存（数据保持整帧稳定，采样安全）----
    reg  [1:0]  S_wtog_sync;
    reg         S_wtog_d;
    reg  [15:0] S_span_r, S_hole_r;
    reg S_meas_valid;
    reg [2:0] S_meas_status;
    reg [10:0] S_center_x, S_center_y, S_hole_x, S_hole_y;
    reg [79:0] S_meas_pending;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_wtog_sync <= 2'b00;
            S_wtog_d    <= 1'b0;
            S_span_r    <= 16'd0;
            S_hole_r    <= 16'd0;
            S_meas_valid <= 1'b0;
            S_meas_status <= 3'd5;
            S_center_x <= 0; S_center_y <= 0; S_hole_x <= 0; S_hole_y <= 0;
            S_meas_pending <= {76'd0,1'b0,3'd5};
        end else begin
            S_wtog_sync <= {S_wtog_sync[0], I_meas_upd};
            S_wtog_d    <= S_wtog_sync[1];
            if(S_wtog_d != S_wtog_sync[1]) begin
                S_meas_pending <= {I_span,I_hole,I_center_x,I_center_y,
                                   I_hole_x,I_hole_y,I_meas_valid,I_meas_status};
            end
            // Hold one complete measurement packet throughout a display frame.
            if (I_video_user)
                {S_span_r,S_hole_r,S_center_x,S_center_y,S_hole_x,S_hole_y,
                 S_meas_valid,S_meas_status} <= S_meas_pending;
        end
    end

    //---- 阈值 CDC ----
    reg  [1:0]  S_ttog_sync;
    reg         S_ttog_d;
    reg  [7:0]  S_thresh_r;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_ttog_sync <= 2'b00; S_ttog_d <= 1'b0; S_thresh_r <= 8'd128;
        end else begin
            S_ttog_sync <= {S_ttog_sync[0], I_thresh_upd};
            S_ttog_d    <= S_ttog_sync[1];
            if(S_ttog_d != S_ttog_sync[1]) S_thresh_r <= I_thresh;
        end
    end

    //---- 外接矩形 CDC（与测量值同款：翻转同步→边沿锁存→帧边界拷贝，
    //      整个显示帧期间坐标稳定，静态场景下边框不闪烁）----
    reg  [1:0]  S_btog_sync;
    reg         S_btog_d;
    reg  [10:0] S_bbox_x0_p, S_bbox_x1_p, S_bbox_y0_p, S_bbox_y1_p;
    reg  [10:0] S_bbox_cx_p, S_bbox_cy_p, S_bbox_w_p, S_bbox_h_p;
    reg  [19:0] S_bbox_area_p;
    reg  [2:0]  S_bbox_type_p;
    reg [2:0] S_bbox_color_p,S_bbox_color_r;
    reg  [23:0] S_bbox_cnt_p;
    reg         S_bbox_valid_p, S_bbox_moving_p;
    reg  [10:0] S_bbox_x0_r, S_bbox_x1_r, S_bbox_y0_r, S_bbox_y1_r;
    reg  [10:0] S_bbox_cx_r, S_bbox_cy_r, S_bbox_w_r, S_bbox_h_r;
    reg  [19:0] S_bbox_area_r;
    reg  [2:0]  S_bbox_type_r;
    reg  [23:0] S_bbox_cnt_r;
    reg         S_bbox_valid, S_bbox_moving;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_btog_sync <= 2'b00; S_btog_d <= 1'b0;
            S_bbox_x0_p <= 11'd0; S_bbox_x1_p <= 11'd0;
            S_bbox_y0_p <= 11'd0; S_bbox_y1_p <= 11'd0;
            S_bbox_cx_p <= 11'd0; S_bbox_cy_p <= 11'd0;
            S_bbox_w_p  <= 11'd0; S_bbox_h_p  <= 11'd0;
            S_bbox_area_p <= 20'd0; S_bbox_type_p <= 3'd0;
            S_bbox_color_p<=0;S_bbox_color_r<=0;
            S_bbox_cnt_p <= 24'd0;
            S_bbox_valid_p <= 1'b0; S_bbox_moving_p <= 1'b0;
            S_bbox_x0_r <= 11'd0; S_bbox_x1_r <= 11'd0;
            S_bbox_y0_r <= 11'd0; S_bbox_y1_r <= 11'd0;
            S_bbox_cx_r <= 11'd0; S_bbox_cy_r <= 11'd0;
            S_bbox_w_r  <= 11'd0; S_bbox_h_r  <= 11'd0;
            S_bbox_area_r <= 20'd0; S_bbox_type_r <= 3'd0;
            S_bbox_cnt_r <= 24'd0;
            S_bbox_valid   <= 1'b0; S_bbox_moving   <= 1'b0;
        end else begin
            S_btog_sync <= {S_btog_sync[0], I_bbox_upd};
            S_btog_d    <= S_btog_sync[1];
            if(S_btog_d != S_btog_sync[1]) begin
                S_bbox_x0_p <= I_bbox_x0; S_bbox_x1_p <= I_bbox_x1;
                S_bbox_y0_p <= I_bbox_y0; S_bbox_y1_p <= I_bbox_y1;
                S_bbox_cx_p <= I_bbox_cx; S_bbox_cy_p <= I_bbox_cy;
                S_bbox_w_p  <= I_bbox_w;  S_bbox_h_p  <= I_bbox_h;
                S_bbox_area_p <= I_bbox_area; S_bbox_type_p <= I_bbox_type;
                S_bbox_color_p<=I_bbox_color;
                S_bbox_cnt_p <= I_bbox_cnt;
                S_bbox_valid_p <= I_bbox_valid;
                S_bbox_moving_p <= I_bbox_moving;
            end
            if (I_video_user) begin
                S_bbox_x0_r <= S_bbox_x0_p; S_bbox_x1_r <= S_bbox_x1_p;
                S_bbox_y0_r <= S_bbox_y0_p; S_bbox_y1_r <= S_bbox_y1_p;
                S_bbox_cx_r <= S_bbox_cx_p; S_bbox_cy_r <= S_bbox_cy_p;
                S_bbox_w_r  <= S_bbox_w_p;  S_bbox_h_r  <= S_bbox_h_p;
                S_bbox_area_r <= S_bbox_area_p; S_bbox_type_r <= S_bbox_type_p;
                S_bbox_color_r<=S_bbox_color_p;
                S_bbox_cnt_r <= S_bbox_cnt_p;
                S_bbox_valid   <= S_bbox_valid_p;
                S_bbox_moving   <= S_bbox_moving_p;
            end
        end
    end

    //---- 背光板 ROI CDC（同外接矩形：翻转同步→锁存→帧边界拷贝）----
    reg  [1:0]  S_rtog_sync;
    reg         S_rtog_d;
    reg  [10:0] S_roi_x0_p, S_roi_x1_p, S_roi_y0_p, S_roi_y1_p;
    reg         S_roi_valid_p;
    reg  [10:0] S_roi_x0_r, S_roi_x1_r, S_roi_y0_r, S_roi_y1_r;
    reg         S_roi_valid;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_rtog_sync <= 2'b00; S_rtog_d <= 1'b0;
            S_roi_x0_p <= 11'd0; S_roi_x1_p <= 11'd0; S_roi_y0_p <= 11'd0; S_roi_y1_p <= 11'd0;
            S_roi_valid_p <= 1'b0;
            S_roi_x0_r <= 11'd0; S_roi_x1_r <= 11'd0; S_roi_y0_r <= 11'd0; S_roi_y1_r <= 11'd0;
            S_roi_valid <= 1'b0;
        end else begin
            S_rtog_sync <= {S_rtog_sync[0], I_roi_upd};
            S_rtog_d    <= S_rtog_sync[1];
            if(S_rtog_d != S_rtog_sync[1]) begin
                S_roi_x0_p <= I_roi_x0; S_roi_x1_p <= I_roi_x1;
                S_roi_y0_p <= I_roi_y0; S_roi_y1_p <= I_roi_y1;
                S_roi_valid_p <= I_roi_valid;
            end
            if (I_video_user) begin
                S_roi_x0_r <= S_roi_x0_p; S_roi_x1_r <= S_roi_x1_p;
                S_roi_y0_r <= S_roi_y0_p; S_roi_y1_r <= S_roi_y1_p;
                S_roi_valid <= S_roi_valid_p;
            end
        end
    end
    wire [11:0] S_rx0 = {1'b0, S_roi_x0_r};
    wire [11:0] S_rx1 = {1'b0, S_roi_x1_r};
    wire [11:0] S_ry0 = {1'b0, S_roi_y0_r};
    wire [11:0] S_ry1 = {1'b0, S_roi_y1_r};
    wire S_roi_inside = !TARGET_ONLY && S_video_de_2d && S_roi_valid &&
        (S_x_2d >= S_rx0) && (S_x_2d <= S_rx1) &&
        (S_y_2d >= S_ry0) && (S_y_2d <= S_ry1);
    wire S_roi_on = S_roi_inside &&
        ((S_x_2d - S_rx0) < 12'd2 || (S_rx1 - S_x_2d) < 12'd2 ||
         (S_y_2d - S_ry0) < 12'd2 || (S_ry1 - S_y_2d) < 12'd2);

    //---- 外接矩形边框命中：2px 边框带（框内坐标差非负，减法安全）----
    wire [11:0] S_bx0 = {1'b0, S_bbox_x0_r};
    wire [11:0] S_bx1 = {1'b0, S_bbox_x1_r};
    wire [11:0] S_by0 = {1'b0, S_bbox_y0_r};
    wire [11:0] S_by1 = {1'b0, S_bbox_y1_r};
    // Class codes are published only after temporal confirmation. Candidates
    // and unsupported silhouettes stay hidden in the production display.
    wire S_target_valid = S_bbox_valid &&
        (PARTS_MODE ? (S_bbox_type_r>=1 && S_bbox_type_r<=4) :
         ((S_bbox_type_r==6 && S_bbox_color_r==4) ||
          (S_bbox_type_r==4 && S_bbox_color_r>=1 && S_bbox_color_r<=3))) &&
        S_bx0<=S_bx1 && S_by0<=S_by1 && S_bx1<IMG_WIDTH && S_by1<IMG_HEIGHT;
    wire S_box_inside = S_video_de_2d && (TARGET_ONLY ? S_target_valid : S_bbox_valid) &&
        (S_x_2d >= S_bx0) && (S_x_2d <= S_bx1) &&
        (S_y_2d >= S_by0) && (S_y_2d <= S_by1);
    wire S_single_box_on = S_box_inside &&
        ((S_x_2d - S_bx0) < 12'd2 || (S_bx1 - S_x_2d) < 12'd2 ||
         (S_y_2d - S_by0) < 12'd2 || (S_by1 - S_y_2d) < 12'd2);

    //---- 虚拟检测线：x=PROBE_X 全高竖线（img_bbox 越线计数以它为基准，
    //      工件中心从左到右穿过此线时顶部 CNT+1）----
    wire S_probe_on = !TARGET_ONLY && S_video_de_2d && (S_x_2d == PROBE_X);

    // Parts labels need 13 glyphs (SILVER WASHER), legacy labels need 12.
    localparam [11:0] TARGET_LABEL_W=PARTS_MODE ? 12'd216 : 12'd200, TARGET_LABEL_H=12'd20;
    wire [11:0] S_single_label_x = S_bx0+TARGET_LABEL_W<=IMG_WIDTH ? S_bx0 : IMG_WIDTH-TARGET_LABEL_W;
    wire [11:0] S_single_label_y = S_by0>=22 ? S_by0-12'd22 :
        S_by1+12'd22<IMG_HEIGHT ? S_by1+12'd2 : 12'd2;
    wire S_single_label_on = TARGET_ONLY && S_video_de_2d && S_target_valid &&
        S_x_2d>=S_single_label_x && S_x_2d<S_single_label_x+TARGET_LABEL_W &&
        S_y_2d>=S_single_label_y && S_y_2d<S_single_label_y+TARGET_LABEL_H;
    // Source list is held across the synchronized update event. Publish at
    // display SOF so the four boxes, labels and removals change together.
    // In production, interpolate only the four coordinates in this HDMI clock
    // domain.  Shape/colour remain the latest confirmed recognition result.
    reg [223:0] targets_pending,targets_display;
    reg [2:0] target_count_pending,target_count_display;
    reg target_overflow_pending,target_overflow_display;
    reg [2:0] box_track_slot;
    reg targets_update_deferred;
    reg [55:0] box_track_current,box_track_target;
    localparam [10:0] BOX_TRACK_STEP_W = BOX_TRACK_STEP;
    localparam [10:0] BOX_TRACK_SNAP_W = BOX_TRACK_SNAP;

    function [10:0] track_box_coord;
        input [10:0] current_coord;
        input [10:0] target_coord;
        begin
            if(target_coord > current_coord + BOX_TRACK_STEP_W)
                track_box_coord = current_coord + BOX_TRACK_STEP_W;
            else if(current_coord > target_coord + BOX_TRACK_STEP_W)
                track_box_coord = current_coord - BOX_TRACK_STEP_W;
            else
                track_box_coord = target_coord;
        end
    endfunction

    function [55:0] track_box_packet;
        input [55:0] current_item;
        input [55:0] target_item;
        reg far_jump;
        begin
            far_jump =
                (target_item[43:33] > current_item[43:33] + BOX_TRACK_SNAP_W) ||
                (current_item[43:33] > target_item[43:33] + BOX_TRACK_SNAP_W) ||
                (target_item[21:11] > current_item[21:11] + BOX_TRACK_SNAP_W) ||
                (current_item[21:11] > target_item[21:11] + BOX_TRACK_SNAP_W);
            if(!target_item[55])
                track_box_packet = 56'd0;
            else if(!current_item[55] || current_item[54:52] != target_item[54:52] || far_jump)
                track_box_packet = target_item;
            else begin
                track_box_packet = target_item;
                track_box_packet[43:33] = track_box_coord(current_item[43:33],target_item[43:33]);
                track_box_packet[32:22] = track_box_coord(current_item[32:22],target_item[32:22]);
                track_box_packet[21:11] = track_box_coord(current_item[21:11],target_item[21:11]);
                track_box_packet[10:0]  = track_box_coord(current_item[10:0], target_item[10:0]);
            end
        end
    endfunction

    // Share one interpolation datapath across four target slots.  The four
    // updates finish in the first four pixel clocks of a display frame.
    always @(*) begin
        case(box_track_slot[1:0])
            2'd0: begin box_track_current=targets_display[55:0];    box_track_target=targets_pending[55:0];    end
            2'd1: begin box_track_current=targets_display[111:56];  box_track_target=targets_pending[111:56];  end
            2'd2: begin box_track_current=targets_display[167:112]; box_track_target=targets_pending[167:112]; end
            default: begin box_track_current=targets_display[223:168];box_track_target=targets_pending[223:168];end
        endcase
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            targets_pending<=0;targets_display<=0;target_count_pending<=0;target_count_display<=0;
            target_overflow_pending<=0;target_overflow_display<=0;
            box_track_slot<=3'd4;targets_update_deferred<=1'b0;
        end else if(MULTI_TARGETS) begin
            if(S_btog_d!=S_btog_sync[1]) begin
                // Do not replace the four-slot source packet while the shared
                // interpolator is consuming it.  The source packet is held
                // until the next update, so deferring four clocks is safe.
                if(BOX_TRACKING && !box_track_slot[2])
                    targets_update_deferred<=1'b1;
                else begin
                    targets_pending<=I_targets;target_count_pending<=I_target_count;target_overflow_pending<=I_target_overflow;
                    targets_update_deferred<=1'b0;
                end
            end
            if(I_video_user) begin
                if(BOX_TRACKING)
                    box_track_slot<=3'd0;
                else begin
                    targets_display<=targets_pending;
                    box_track_slot<=3'd4;
                end
                target_count_display<=target_count_pending;target_overflow_display<=target_overflow_pending;
            end else if(BOX_TRACKING && !box_track_slot[2]) begin
                case(box_track_slot[1:0])
                    2'd0: targets_display[55:0]    <= track_box_packet(box_track_current,box_track_target);
                    2'd1: targets_display[111:56]  <= track_box_packet(box_track_current,box_track_target);
                    2'd2: targets_display[167:112] <= track_box_packet(box_track_current,box_track_target);
                    default: targets_display[223:168] <= track_box_packet(box_track_current,box_track_target);
                endcase
                box_track_slot <= box_track_slot==3'd3 ? 3'd4:box_track_slot+1'b1;
            end
            if(BOX_TRACKING && targets_update_deferred && box_track_slot[2] && !I_video_user) begin
                targets_pending<=I_targets;target_count_pending<=I_target_count;target_overflow_pending<=I_target_overflow;
                targets_update_deferred<=1'b0;
            end
        end
    end
    wire [3:0] multi_box_hits,multi_label_hits;
    wire [11:0] multi_lx[0:3],multi_ly[0:3];
    wire [2:0] multi_shape[0:3],multi_colour[0:3];
    genvar target_slot;
    generate for(target_slot=0;target_slot<4;target_slot=target_slot+1) begin:g_multi_overlay
        wire [55:0] item=targets_display[target_slot*56+:56];
        wire [11:0] x0={1'b0,item[43:33]},x1={1'b0,item[32:22]};
        wire [11:0] y0={1'b0,item[21:11]},y1={1'b0,item[10:0]};
        wire active=MULTI_TARGETS && item[55] && item[54:52]>=1 && item[54:52]<=4 &&
            x0<=x1 && y0<=y1 && x1<IMG_WIDTH && y1<IMG_HEIGHT;
        assign multi_lx[target_slot]=x0+TARGET_LABEL_W<=IMG_WIDTH ? x0:IMG_WIDTH-TARGET_LABEL_W;
        assign multi_ly[target_slot]=y0>=22 ? y0-12'd22:y1+12'd22<IMG_HEIGHT ? y1+12'd2:12'd2;
        assign multi_shape[target_slot]=item[54:52];
        assign multi_colour[target_slot]=COLOR_DIAGNOSTICS && !AUTO_WHITE_BALANCE && reference_display[26:24]!=3'b111 ? 3'd0:item[51:49];
        assign multi_box_hits[target_slot]=active && S_video_de_2d && S_x_2d>=x0 && S_x_2d<=x1 && S_y_2d>=y0 && S_y_2d<=y1 &&
            (S_x_2d-x0<2 || x1-S_x_2d<2 || S_y_2d-y0<2 || y1-S_y_2d<2);
        assign multi_label_hits[target_slot]=active && TARGET_ONLY && S_video_de_2d &&
            S_x_2d>=multi_lx[target_slot] && S_x_2d<multi_lx[target_slot]+TARGET_LABEL_W &&
            S_y_2d>=multi_ly[target_slot] && S_y_2d<multi_ly[target_slot]+TARGET_LABEL_H;
    end endgenerate
    wire [1:0] label_slot=multi_label_hits[0] ? 2'd0:multi_label_hits[1] ? 2'd1:multi_label_hits[2] ? 2'd2:2'd3;
    wire S_box_on=MULTI_TARGETS ? |multi_box_hits:S_single_box_on;
    wire S_label_on=MULTI_TARGETS ? |multi_label_hits:S_single_label_on;
    wire [11:0] S_label_x=MULTI_TARGETS ? multi_lx[label_slot]:S_single_label_x;
    wire [11:0] S_label_y=MULTI_TARGETS ? multi_ly[label_slot]:S_single_label_y;
    wire [2:0] label_shape=MULTI_TARGETS ? multi_shape[label_slot]:S_bbox_type_r;
    wire [2:0] label_colour=MULTI_TARGETS ? multi_colour[label_slot]:S_bbox_color_r;
    function [7:0] target_label_char;
        input [2:0] shape,color;
        input [3:0] index;
        reg [103:0] word_bits;
        reg [47:0] colour_word,shape_word;
        begin
            if(PARTS_MODE) begin
                case(color)
                    1:colour_word="RED   ";
                    4:colour_word="BLACK ";
                    5:colour_word="SILVER";
                    6:colour_word="BRASS ";
                    default:colour_word="UNKN  ";
                endcase
                case(shape)
                    1:shape_word="SCREW ";
                    2:shape_word="WASHER";
                    3:shape_word="NUT   ";
                    4:shape_word="SQNUT ";
                    default:shape_word="      ";
                endcase
                word_bits={colour_word,8'h20,shape_word};
            end else if(shape==6 && color==4) word_bits="BLACK RING  ";
            else case(color)
                1: word_bits="RED   CIRCLE";
                2: word_bits="GREEN CIRCLE";
                3: word_bits="BLUE  CIRCLE";
                default: word_bits="            ";
            endcase
            target_label_char=word_bits>>(((PARTS_MODE ? 12 : 11)-index)*8);
        end
    endfunction

    function [7:0] measurement_char;
        input [2:0] status_code;
        input [2:0] char_index;
        reg [39:0] word_bits;
        begin
            case (status_code)
                0: word_bits = "VALID";
                1: word_bits = "EMPTY";
                2: word_bits = "EDGE ";
                3: word_bits = "TOPO ";
                4: word_bits = "SIZE ";
                6: word_bits = "NHOLE";
                7: word_bits = "MULTI";
                default: word_bits = "FRAME";
            endcase
            measurement_char = word_bits >> ((4-char_index)*8);
        end
    endfunction

    function [7:0] motion_char;
        input valid;
        input moving;
        input [2:0] char_index;
        reg [39:0] word_bits;
        begin
            if (!valid) word_bits = "EMPTY";
            else if (moving) word_bits = "MOVE ";
            else word_bits = "LOCK ";
            motion_char = word_bits >> ((4-char_index)*8);
        end
    endfunction

    function [7:0] color_char;
        input valid;
        input [2:0] color;
        input [2:0] char_index;
        reg [39:0] word_bits;
        begin
            if(!valid) word_bits="NONE ";
            else case(color)
                1: word_bits="RED  ";
                2: word_bits="GREEN";
                3: word_bits="BLUE ";
                4: word_bits="BLACK";
                default: word_bits="UNKN ";
            endcase
            color_char=word_bits >> ((4-char_index)*8);
        end
    endfunction
    function [7:0] type_char;
        input [2:0] type_code;   // 0NONE 1BAR 2RING 3NUT 4DISC 5BLOCK
        input [2:0] char_index;
        reg [39:0] word_bits;
        begin
            case (type_code)
                3'd1: word_bits = "BAR  ";
                3'd2: word_bits = "RING ";
                3'd3: word_bits = "NUT  ";
                3'd4: word_bits = "DISC ";
                3'd5: word_bits = "BLOCK";
                3'd6: word_bits = "TIRE ";
                3'd7: word_bits = "UNKN ";
                default: word_bits = "NONE ";
            endcase
            type_char = word_bits >> ((4-char_index)*8);
        end
    endfunction

    // 24 像素 → 16 点阵缩放：floor(v*16/24) = floor(2v/3)
    function [3:0] f_s24;
        input [4:0] v;
        begin
            case (v)
                5'd0, 5'd1:   f_s24 = 4'd0;
                5'd2:         f_s24 = 4'd1;
                5'd3, 5'd4:   f_s24 = 4'd2;
                5'd5:         f_s24 = 4'd3;
                5'd6, 5'd7:   f_s24 = 4'd4;
                5'd8:         f_s24 = 4'd5;
                5'd9, 5'd10:  f_s24 = 4'd6;
                5'd11:        f_s24 = 4'd7;
                5'd12, 5'd13: f_s24 = 4'd8;
                5'd14:        f_s24 = 4'd9;
                5'd15, 5'd16: f_s24 = 4'd10;
                5'd17:        f_s24 = 4'd11;
                5'd18, 5'd19: f_s24 = 4'd12;
                5'd20:        f_s24 = 4'd13;
                5'd21, 5'd22: f_s24 = 4'd14;
                default:      f_s24 = 4'd15;
            endcase
        end
    endfunction

    // 常数比较链求商（避免综合除法器）
    function [3:0] f_q100;   // v < 1024
        input [9:0] v;
        begin
            f_q100 = (v >= 10'd900) ? 4'd9 : (v >= 10'd800) ? 4'd8 :
                     (v >= 10'd700) ? 4'd7 : (v >= 10'd600) ? 4'd6 :
                     (v >= 10'd500) ? 4'd5 : (v >= 10'd400) ? 4'd4 :
                     (v >= 10'd300) ? 4'd3 : (v >= 10'd200) ? 4'd2 :
                     (v >= 10'd100) ? 4'd1 : 4'd0;
        end
    endfunction
    function [3:0] f_q10;    // v < 128
        input [6:0] v;
        begin
            f_q10 = (v >= 7'd90) ? 4'd9 : (v >= 7'd80) ? 4'd8 :
                    (v >= 7'd70) ? 4'd7 : (v >= 7'd60) ? 4'd6 :
                    (v >= 7'd50) ? 4'd5 : (v >= 7'd40) ? 4'd4 :
                    (v >= 7'd30) ? 4'd3 : (v >= 7'd20) ? 4'd2 :
                    (v >= 7'd10) ? 4'd1 : 4'd0;
        end
    endfunction

    assign O_video_rd_en = I_video_de;

    //---- 光栅计数 ----
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_user) begin
            S_x <= (I_video_de && !I_video_last) ? 12'd1 : 12'd0;
            S_y <= (I_video_de && I_video_last) ? 12'd1 : 12'd0;
        end
        else if(I_video_de) begin
            if(I_video_last) begin
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end
            else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x_1d <= 12'd0;
            S_x_2d <= 12'd0;
            S_y_1d <= 12'd0;
            S_y_2d <= 12'd0;
        end
        else begin
            S_x_1d <= I_video_user ? 12'd0 : S_x;
            S_x_2d <= S_x_1d;
            S_y_1d <= I_video_user ? 12'd0 : S_y;
            S_y_2d <= S_y_1d;
        end
    end

    // CNT 数字 = 工件计数（与框坐标同拍取 pending 包）
    reg [3:0] S_cnt_d0, S_cnt_d1, S_cnt_d2, S_cnt_d3, S_cnt_d4, S_cnt_d5;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            {S_cnt_d5, S_cnt_d4, S_cnt_d3, S_cnt_d2, S_cnt_d1, S_cnt_d0} <= 24'd0;
        else if(I_video_user)
            {S_cnt_d5, S_cnt_d4, S_cnt_d3, S_cnt_d2, S_cnt_d1, S_cnt_d0} <= S_bbox_cnt_p;
    end

    // Batch status crosses from the 50 MHz control domain.  The buses change
    // only on a debounced key press or a target publication, so two-stage
    // sampling followed by a video-frame latch is sufficient bundled-data CDC.
    reg [47:0] batch_counts_meta,batch_counts_sync,batch_counts_frame;
    reg [47:0] batch_targets_meta,batch_targets_sync,batch_targets_frame;
    reg [2:0] batch_filter_meta,batch_filter_sync,batch_filter_frame;
    reg batch_done_meta,batch_done_sync,batch_done_frame;
    reg batch_overrun_meta,batch_overrun_sync,batch_overrun_frame;
    reg [3:0] batch_overrun_mask_meta,batch_overrun_mask_sync,batch_overrun_mask_frame;
    reg [13:0] menu_meta,menu_sync,menu_frame;
    reg [4:0] ae_target_meta,ae_target_sync,ae_target_frame;
    reg [47:0] total_meta,total_sync,total_frame;
    reg [6:0] enhance_meta,enhance_sync,enhance_frame;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin visual_compare_sync<=0;visual_compare_frame<=0;end
        else begin
            case(I_enhance_compare) 1'b1:visual_compare_sync<={visual_compare_sync[0],1'b1};
                default:visual_compare_sync<={visual_compare_sync[0],1'b0};endcase
            if(I_video_user) visual_compare_frame<=visual_compare_sync[1];
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            batch_counts_meta<=0;batch_counts_sync<=0;batch_counts_frame<=0;
            batch_targets_meta<=48'h000000000010;batch_targets_sync<=48'h000000000010;batch_targets_frame<=48'h000000000010;
            batch_filter_meta<=0;batch_filter_sync<=0;batch_filter_frame<=0;
            batch_done_meta<=0;batch_done_sync<=0;batch_done_frame<=0;
            batch_overrun_meta<=0;batch_overrun_sync<=0;batch_overrun_frame<=0;
            batch_overrun_mask_meta<=0;batch_overrun_mask_sync<=0;batch_overrun_mask_frame<=0;
            menu_meta<=0;menu_sync<=0;menu_frame<=0;
            ae_target_meta<=19;ae_target_sync<=19;ae_target_frame<=19;
            total_meta<=0;total_sync<=0;total_frame<=0;
            enhance_meta<={1'b0,2'd2,4'd4};enhance_sync<={1'b0,2'd2,4'd4};enhance_frame<={1'b0,2'd2,4'd4};
        end else begin
            batch_counts_meta<=I_batch_counts_bcd;batch_counts_sync<=batch_counts_meta;
            batch_targets_meta<=I_batch_targets_bcd;batch_targets_sync<=batch_targets_meta;
            batch_filter_meta<=I_batch_filter_type;batch_filter_sync<=batch_filter_meta;
            batch_done_meta<=I_batch_done;batch_done_sync<=batch_done_meta;
            batch_overrun_meta<=I_batch_overrun;batch_overrun_sync<=batch_overrun_meta;
            batch_overrun_mask_meta<=I_batch_overrun_mask;batch_overrun_mask_sync<=batch_overrun_mask_meta;
            menu_meta<={I_menu_ae_locked,I_menu_open,I_menu_index,I_menu_preview_mode,
                       I_menu_motor_level,I_menu_awb_freeze,I_menu_ae_auto};
            menu_sync<=menu_meta;
            ae_target_meta<=I_menu_ae_target_level;ae_target_sync<=ae_target_meta;
            total_meta<=I_batch_total_counts_bcd;total_sync<=total_meta;
            enhance_meta<={I_batch_wait_clear,I_enhance_strength,I_enhance_noise};enhance_sync<=enhance_meta;
            if(I_video_user) begin
                batch_counts_frame<=batch_counts_sync;
                batch_targets_frame<=batch_targets_sync;
                batch_filter_frame<=batch_filter_sync;
                batch_done_frame<=batch_done_sync;
                batch_overrun_frame<=batch_overrun_sync;
                batch_overrun_mask_frame<=batch_overrun_mask_sync;
                menu_frame<=menu_sync;total_frame<=total_sync;enhance_frame<=enhance_sync;
                if(ae_target_sync>=8 && ae_target_sync<=24) ae_target_frame<=ae_target_sync;
            end
        end
    end
    wire menu_open_frame=menu_frame[12];
    wire [3:0] menu_index_frame=menu_frame[11:8];
    wire [2:0] menu_preview_frame=menu_frame[7:5];
    wire [2:0] menu_motor_frame=menu_frame[4:2];
    wire menu_awb_frame=menu_frame[1];
    wire menu_ae_auto_frame=menu_frame[0];
    wire menu_ae_locked_frame=menu_frame[13];
    function [11:0] ae_target_bcd;
        input [4:0] level;
        begin
            case(level)
                8:ae_target_bcd=12'h064;9:ae_target_bcd=12'h072;
                10:ae_target_bcd=12'h080;11:ae_target_bcd=12'h088;
                12:ae_target_bcd=12'h096;13:ae_target_bcd=12'h104;
                14:ae_target_bcd=12'h112;15:ae_target_bcd=12'h120;
                16:ae_target_bcd=12'h128;17:ae_target_bcd=12'h136;
                18:ae_target_bcd=12'h144;19:ae_target_bcd=12'h152;
                20:ae_target_bcd=12'h160;21:ae_target_bcd=12'h168;
                22:ae_target_bcd=12'h176;23:ae_target_bcd=12'h184;
                24:ae_target_bcd=12'h192;default:ae_target_bcd=12'h152;
            endcase
        end
    endfunction
    wire [11:0] ae_target_digits=ae_target_bcd(ae_target_frame);
    wire [4:0] ae_stable_display=menu_ae_locked_frame ? 5'd16 : ae_diag_frame[13:9];

    //---- 十进制转换：3 级流水（源值整帧稳定，帧头锁存后 3 拍就绪，
    //     远早于 OSD 行 y=152）----
    reg        W_ge_a, H_ge_a, V_a;
    reg [9:0]  W_r1_a, H_r1_a;
    reg [3:0]  W_d2_b, H_d2_b;
    reg [6:0]  W_r2_b, H_r2_b;
    reg        W_ge_b, H_ge_b, V_b;
    reg [7:0]  W_DCHAR0, W_DCHAR1, W_DCHAR2, W_DCHAR3;
    reg [7:0]  H_DCHAR0, H_DCHAR1, H_DCHAR2, H_DCHAR3;
    reg [1:0]  T_d2_a;
    reg [6:0]  T_r_a;
    reg [7:0]  T_DCHAR2, T_DCHAR1, T_DCHAR0;
    wire [3:0] W_q100 = f_q100(W_r1_a);
    wire [3:0] H_q100 = f_q100(H_r1_a);
    wire [3:0] W_q10  = f_q10(W_r2_b);
    wire [3:0] H_q10  = f_q10(H_r2_b);
    wire [3:0] T_q10  = f_q10(T_r_a);
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {W_ge_a, H_ge_a, V_a, W_ge_b, H_ge_b, V_b} <= 6'd0;
            W_r1_a <= 10'd0; H_r1_a <= 10'd0;
            W_d2_b <= 4'd0;  H_d2_b <= 4'd0;
            W_r2_b <= 7'd0;  H_r2_b <= 7'd0;
            {W_DCHAR0, W_DCHAR1, W_DCHAR2, W_DCHAR3} <= {4{8'h58}};
            {H_DCHAR0, H_DCHAR1, H_DCHAR2, H_DCHAR3} <= {4{8'h58}};
            T_d2_a <= 2'd0; T_r_a <= 7'd0;
            {T_DCHAR2, T_DCHAR1, T_DCHAR0} <= {3{8'h30}};
        end else begin
            V_a    <= S_meas_valid;
            W_ge_a <= (S_span_r >= 16'd1000);
            H_ge_a <= (S_hole_r >= 16'd1000);
            W_r1_a <= (S_span_r >= 16'd1000) ? S_span_r - 16'd1000 : S_span_r;
            H_r1_a <= (S_hole_r >= 16'd1000) ? S_hole_r - 16'd1000 : S_hole_r;

            V_b    <= V_a;
            W_ge_b <= W_ge_a; H_ge_b <= H_ge_a;
            W_d2_b <= W_q100; H_d2_b <= H_q100;
            W_r2_b <= W_r1_a - W_q100 * 7'd100;
            H_r2_b <= H_r1_a - H_q100 * 7'd100;

            W_DCHAR0 <= V_b ? {7'h18, W_ge_b} : 8'h58;
            W_DCHAR1 <= V_b ? {4'h3, W_d2_b} : 8'h58;
            W_DCHAR2 <= V_b ? {4'h3, W_q10} : 8'h58;
            W_DCHAR3 <= V_b ? {4'h3, W_r2_b[3:0] - W_q10 * 4'd10} : 8'h58;
            H_DCHAR0 <= V_b ? {7'h18, H_ge_b} : 8'h58;
            H_DCHAR1 <= V_b ? {4'h3, H_d2_b} : 8'h58;
            H_DCHAR2 <= V_b ? {4'h3, H_q10} : 8'h58;
            H_DCHAR3 <= V_b ? {4'h3, H_r2_b[3:0] - H_q10 * 4'd10} : 8'h58;

            T_d2_a <= (S_thresh_r >= 8'd200) ? 2'd2 : (S_thresh_r >= 8'd100) ? 2'd1 : 2'd0;
            T_r_a  <= (S_thresh_r >= 8'd200) ? S_thresh_r - 8'd200 :
                      (S_thresh_r >= 8'd100) ? S_thresh_r - 8'd100 : S_thresh_r;
            T_DCHAR2 <= {6'h0c, T_d2_a};
            T_DCHAR1 <= {4'h3, T_q10};
            T_DCHAR0 <= {4'h3, T_r_a[3:0] - T_q10 * 4'd10};
        end
    end

    //================================================================
    // 渲染流水线（2026-10-11 重构，目标 75MHz）：
    //   P0 (S_x_2d)  → 叠加线命中、文本带/局部坐标、Logo 裁剪坐标
    //   P1 → P2      : 字符码/行/列、Logo 地址
    //   P2 → P3      : osd_char_lib 行点阵寄存；Logo 索引 ERAM 读
    //   P3 → P4      : 点阵位选；调色板 ERAM 读
    //   P4 → 输出寄存: 优先级合成
    // de/hs/vs/视频数据同步延迟 4 拍，与原设计相比整体多 4 拍时延。
    //================================================================
    localparam [11:0] LOGO_CX0 = 12'd7,  LOGO_CY0 = 12'd34;   // 与 gen_logo_mem.py 输出一致
    localparam [11:0] LOGO_CW  = 12'd146, LOGO_CH = 12'd94;

    localparam [3:0] BAND_NONE = 4'd0, BAND_DYN = 4'd1, BAND_W2 = 4'd2, BAND_W3 = 4'd3,
                     BAND_W4 = 4'd4, BAND_ST = 4'd5, BAND_MO = 4'd6, BAND_TY = 4'd7, BAND_CO=4'd8, BAND_FX=4'd9, BAND_TARGET=4'd10,
                     BAND_EXPOSURE=4'd11,BAND_GAIN=4'd12,BAND_COLOUR_DIAG=4'd13,BAND_LATENCY=4'd14,BAND_BATCH=4'd15;

    //---- P0 组合：叠加线（测试直接观察这些名字）----
    wire S_line_on = !TARGET_ONLY && S_video_de_2d && S_meas_valid &&
        (((S_y_2d == S_center_y) && (S_x_2d+12'd8 >= S_center_x) &&
          (S_x_2d <= {1'b0,S_center_x}+12'd8)) ||
         ((S_x_2d == S_center_x) && (S_y_2d+12'd8 >= S_center_y) &&
          (S_y_2d <= {1'b0,S_center_y}+12'd8)));
    wire S_hole_center_on = !TARGET_ONLY && S_video_de_2d && S_meas_valid &&
        (((S_y_2d == S_hole_y) && (S_x_2d+12'd3 >= S_hole_x) &&
          (S_x_2d <= {1'b0,S_hole_x}+12'd3)) ||
         ((S_x_2d == S_hole_x) && (S_y_2d+12'd3 >= S_hole_y) &&
          (S_y_2d <= {1'b0,S_hole_y}+12'd3)));

    wire menu_panel_on=menu_open_frame && S_video_de_2d && S_x_2d>=MENU_X &&
        S_x_2d<MENU_X+MENU_W && S_y_2d>=MENU_Y && S_y_2d<MENU_Y+MENU_H;
    wire [11:0] menu_local_y=S_y_2d-MENU_Y-16;
    wire menu_text_on=menu_panel_on && S_x_2d>=MENU_X+16 && S_x_2d<MENU_X+272 &&
        S_y_2d>=MENU_Y+16 && S_y_2d<MENU_Y+352;
    //---- P0 组合：文本带选择 ----
    reg  [3:0]  p0_band;
    reg  [11:0] p0_ly;
    reg [3:0] p0_diag_row;
    always @(*) begin
        p0_band = BAND_NONE;
        p0_ly   = 12'd0;
        p0_diag_row=0;
        if (!TARGET_ONLY && S_video_de_2d && (S_x_2d >= W2_X) && (S_x_2d < DYN_OSD_X + DYN_OSD_W)) begin
            if      (S_y_2d >= DYN_OSD_Y && S_y_2d < DYN_OSD_Y + DYN_OSD_H) begin p0_band = BAND_DYN; p0_ly = S_y_2d - DYN_OSD_Y; end
            else if (S_y_2d >= W2_Y && S_y_2d < W2_Y + 12'd24)          begin p0_band = BAND_W2;  p0_ly = S_y_2d - W2_Y; end
            else if (S_y_2d >= W3_Y && S_y_2d < W3_Y + 12'd24)          begin p0_band = BAND_W3;  p0_ly = S_y_2d - W3_Y; end
            else if (S_y_2d >= W4_Y && S_y_2d < W4_Y + 12'd24)          begin p0_band = BAND_W4;  p0_ly = S_y_2d - W4_Y; end
            else if (S_y_2d >= STATUS_Y && S_y_2d < STATUS_Y + 12'd16)  begin p0_band = BAND_ST;  p0_ly = S_y_2d - STATUS_Y; end
            else if (S_y_2d >= MOTION_Y && S_y_2d < MOTION_Y + 12'd16)  begin p0_band = BAND_MO;  p0_ly = S_y_2d - MOTION_Y; end
            else if (S_y_2d >= TYPE_Y && S_y_2d < TYPE_Y + 12'd16)      begin p0_band = BAND_TY;  p0_ly = S_y_2d - TYPE_Y; end
            else if (S_y_2d >= COLOR_Y && S_y_2d < COLOR_Y + 12'd16)    begin p0_band = BAND_CO; p0_ly = S_y_2d - COLOR_Y; end
            else if (DISPLAY_MODES && S_y_2d >= MODE_Y && S_y_2d < MODE_Y + 12'd16) begin p0_band=BAND_FX;p0_ly=S_y_2d-MODE_Y;end
        end
        if(TARGET_ONLY && DISPLAY_MODES && S_video_de_2d &&
           S_x_2d>=CONTROL_X && S_x_2d<CONTROL_X+208 && S_y_2d>=20 && S_y_2d<36) begin
            p0_band=BAND_FX;p0_ly=S_y_2d-12'd20;
        end
        if(S_label_on && S_x_2d>=S_label_x+4 && S_x_2d<S_label_x+TARGET_LABEL_W-4 &&
           S_y_2d>=S_label_y+2 && S_y_2d<S_label_y+18) begin
            p0_band=BAND_TARGET;p0_ly=S_y_2d-S_label_y-12'd2;
        end
        if(CAMERA_CONTROL && S_video_de_2d && S_x_2d>=CONTROL_X && S_x_2d<CONTROL_X+208) begin
            if(S_y_2d>=40 && S_y_2d<56) begin p0_band=BAND_EXPOSURE;p0_ly=S_y_2d-12'd40;end
            else if(S_y_2d>=60 && S_y_2d<76) begin p0_band=BAND_GAIN;p0_ly=S_y_2d-12'd60;end
        end
        if(PARTS_MODE && S_video_de_2d && S_x_2d>=CONTROL_X && S_x_2d<CONTROL_X+256) begin
            if(S_y_2d>=80 && S_y_2d<96) begin p0_band=BAND_COLOUR_DIAG;p0_ly=S_y_2d-80;p0_diag_row=12;end
            if(S_y_2d>=100 && S_y_2d<116) begin p0_band=BAND_BATCH;p0_ly=S_y_2d-100;p0_diag_row=0;end
            if(S_y_2d>=120 && S_y_2d<136) begin p0_band=BAND_BATCH;p0_ly=S_y_2d-120;p0_diag_row=1;end
            if(S_y_2d>=140 && S_y_2d<156) begin p0_band=BAND_BATCH;p0_ly=S_y_2d-140;p0_diag_row=2;end
            if(S_y_2d>=160 && S_y_2d<176) begin p0_band=BAND_BATCH;p0_ly=S_y_2d-160;p0_diag_row=3;end
        end
        if(COLOR_DIAGNOSTICS && S_video_de_2d && S_x_2d>=CONTROL_X && S_x_2d<CONTROL_X+256) begin
            if(S_y_2d>=84 && S_y_2d<100) begin p0_band=BAND_COLOUR_DIAG;p0_ly=S_y_2d-84;p0_diag_row=0;end
            else if((!COMPACT_DIAGNOSTICS || WB_DIAGNOSTICS) && S_y_2d>=104 && S_y_2d<120) begin p0_band=BAND_COLOUR_DIAG;p0_ly=S_y_2d-104;p0_diag_row=1;end
            else if((!COMPACT_DIAGNOSTICS || WB_DIAGNOSTICS) && S_y_2d>=124 && S_y_2d<140) begin p0_band=BAND_COLOUR_DIAG;p0_ly=S_y_2d-124;p0_diag_row=2;end
            else if((!COMPACT_DIAGNOSTICS || WB_DIAGNOSTICS) && S_y_2d>=144 && S_y_2d<160) begin p0_band=BAND_COLOUR_DIAG;p0_ly=S_y_2d-144;p0_diag_row=3;end
            else if((!COMPACT_DIAGNOSTICS || WB_DIAGNOSTICS) && S_y_2d>=164 && S_y_2d<180) begin p0_band=BAND_COLOUR_DIAG;p0_ly=S_y_2d-164;p0_diag_row=4;end
            else if((!COMPACT_DIAGNOSTICS || WB_DIAGNOSTICS) && S_y_2d>=184 && S_y_2d<200) begin p0_band=BAND_COLOUR_DIAG;p0_ly=S_y_2d-184;p0_diag_row=5;end
            else if((!COMPACT_DIAGNOSTICS || WB_DIAGNOSTICS) && S_y_2d>=204 && S_y_2d<220) begin p0_band=BAND_COLOUR_DIAG;p0_ly=S_y_2d-204;p0_diag_row=6;end
        end
        if(LATENCY_DIAGNOSTICS && S_video_de_2d &&
           S_x_2d>=LATENCY_X && S_x_2d<LATENCY_X+176 && S_y_2d>=16 && S_y_2d<32) begin
            p0_band=BAND_LATENCY;p0_ly=S_y_2d-12'd16;
        end
        // Keep batch safety visible without the two AE debug rows.
        if(PARTS_MODE && S_video_de_2d && S_x_2d>=CONTROL_X && S_x_2d<CONTROL_X+256 &&
           S_y_2d>=180 && S_y_2d<196) begin
            p0_band=BAND_COLOUR_DIAG;p0_ly=S_y_2d-12'd180;p0_diag_row=15;
        end
        // Text, boxes and old labels cannot bleed through menu padding.
        if(FPS_DISPLAY && PARTS_MODE && S_video_de_2d && S_x_2d>=CONTROL_X && S_x_2d<CONTROL_X+256 &&
           S_y_2d>=200 && S_y_2d<216) begin
            p0_band=BAND_COLOUR_DIAG;p0_ly=S_y_2d-12'd200;p0_diag_row=14;
        end
        if(menu_panel_on) begin
            p0_band=BAND_NONE;
            if(menu_text_on) begin
                p0_band=BAND_COLOUR_DIAG;p0_ly=menu_local_y[4:0];p0_diag_row=menu_local_y[8:5];
            end
        end
    end
    wire [11:0] p0_dx = p0_band==BAND_LATENCY ? S_x_2d-LATENCY_X :
        p0_band==BAND_TARGET ? S_x_2d-S_label_x-12'd4 :
        (p0_band==BAND_COLOUR_DIAG && menu_text_on) ? S_x_2d-MENU_X-16 :
        (p0_band==BAND_EXPOSURE || p0_band==BAND_GAIN || p0_band==BAND_COLOUR_DIAG || p0_band==BAND_BATCH) ? S_x_2d-CONTROL_X :
        (TARGET_ONLY && p0_band==BAND_FX) ? S_x_2d-CONTROL_X : S_x_2d-W2_X;

    //---- P0 组合：调试底图 ----
    reg [23:0] p0_base;
    always @(*) begin
        p0_base = S_aligned_video_data;
        if(S_label_on) p0_base=24'h202020;
        // Production information overlays the camera, including spaces in each row.
        if(!TARGET_ONLY && (p0_band==BAND_EXPOSURE || p0_band==BAND_GAIN ||
           p0_band==BAND_BATCH || p0_band==BAND_COLOUR_DIAG)) p0_base=24'h202020;
        if(p0_band==BAND_LATENCY) p0_base=24'h202020;
        if(menu_panel_on) begin
            p0_base=24'h15202e;
            if(S_x_2d==MENU_X || S_x_2d==MENU_X+MENU_W-1 || S_y_2d==MENU_Y || S_y_2d==MENU_Y+MENU_H-1) p0_base=24'h45627b;
            if(menu_local_y[8:5]==0 && S_y_2d>=MENU_Y+16) p0_base=24'h24374a;
            if(menu_text_on && menu_local_y[8:5]=={1'b0,menu_index_frame[2:0]}+1'b1) p0_base=24'h214e69;
        end
        if (DEBUG_MODE == 1) begin
            if      (S_x_2d < 12'd128) p0_base = 24'hff0000;
            else if (S_x_2d < 12'd256) p0_base = 24'h00ff00;
            else if (S_x_2d < 12'd384) p0_base = 24'h0000ff;
            else if (S_x_2d < 12'd512) p0_base = 24'hffff00;
            else if (S_x_2d < 12'd640) p0_base = 24'h00ffff;
            else if (S_x_2d < 12'd768) p0_base = 24'hff00ff;
            else if (S_x_2d < 12'd896) p0_base = 24'hffffff;
            else                       p0_base = 24'h202020;
        end else if (DEBUG_MODE == 2) begin
            case (I_debug_status)
                4'b0000: p0_base = 24'h000000;
                4'b0001: p0_base = 24'hff0000;
                4'b0011: p0_base = 24'hffff00;
                4'b0111: p0_base = 24'h00ff00;
                4'b1111: p0_base = S_aligned_video_data;
                default: p0_base = 24'h0000ff;
            endcase
        end else if (DEBUG_MODE == 3) begin
            if      (S_x_2d < 12'd256) p0_base = I_debug_status[0] ? 24'hff8000 : 24'h201000;
            else if (S_x_2d < 12'd512) p0_base = I_debug_status[1] ? 24'hffff00 : 24'h202000;
            else if (S_x_2d < 12'd768) p0_base = I_debug_status[2] ? 24'hff0000 : 24'h200000;
            else                       p0_base = I_debug_status[3] ? 24'h00ffff : 24'h002020;
        end
        if (!S_video_de_2d) p0_base = 24'd0;
    end

    //---- P1 寄存 ----
    reg        p1_de, p1_hs, p1_vs;
    reg [23:0] p1_base;
    reg [3:0]  p1_band;
    reg [7:0]  p1_dx;
    reg [4:0]  p1_ly;
    reg [3:0] p1_diag_row;
    reg [2:0] p1_target_shape,p1_target_colour;
    reg [4:0]  p1_ovl;          // {roi, box, hole_center, line, probe}
    reg        p1_logo_in;
    reg [7:0]  p1_lgx;
    reg [6:0]  p1_lgy;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            {p1_de, p1_hs, p1_vs} <= 3'd0;
            p1_base <= 24'd0; p1_band <= BAND_NONE; p1_dx <= 8'd0; p1_ly <= 5'd0;p1_diag_row<=0;p1_target_shape<=0;p1_target_colour<=0;
            p1_ovl <= 5'd0; p1_logo_in <= 1'b0; p1_lgx <= 8'd0; p1_lgy <= 7'd0;
        end else begin
            p1_de   <= S_video_de_2d;
            p1_hs   <= S_video_hsync_2d;
            p1_vs   <= S_video_vsync_2d;
            p1_base <= p0_base;
            p1_band <= (DEBUG_MODE == 0) ? p0_band : BAND_NONE;
            p1_dx   <= p0_dx[7:0];
            p1_ly   <= p0_ly[4:0];
            p1_diag_row<=p0_diag_row;
            p1_target_shape<=label_shape;p1_target_colour<=label_colour;
            p1_ovl  <= (DEBUG_MODE == 0 && !menu_panel_on) ? {S_roi_on, S_box_on, S_hole_center_on, S_line_on, S_probe_on} : 5'd0;
            p1_logo_in <= (!TARGET_ONLY || SHOW_LOGO) && (DEBUG_MODE == 0) && S_video_de_2d &&
                          (S_x_2d >= LOGO_X + LOGO_CX0) && (S_x_2d < LOGO_X + LOGO_CX0 + LOGO_CW) &&
                          (S_y_2d >= LOGO_Y + LOGO_CY0) && (S_y_2d < LOGO_Y + LOGO_CY0 + LOGO_CH);
            p1_lgx  <= S_x_2d - (LOGO_X + LOGO_CX0);
            p1_lgy  <= S_y_2d - (LOGO_Y + LOGO_CY0);
        end
    end

    reg p1_is_menu;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) p1_is_menu<=0;else p1_is_menu<=menu_text_on;
    end
    //---- P1 组合：字符译码 ----
    reg [7:0]  c_char;
    reg [3:0]  c_row, c_col;
    reg        c_ok;          // 本像素落在某字形格内
    reg [23:0] c_color;
    reg [7:0]  c_dig_x;       // 数字区局部 x（相对首个数字）
    reg [2:0]  c_dig_i;
    reg [3:0]  c_dig_l;       // 数字格内列 0..14
    reg [11:0] c_batch_count,c_batch_target,c_batch_total;
    reg [127:0] ui_text;
    reg [3:0] ui_item;
    reg [2:0] c_batch_type;
    reg c_batch_overrun;
    // Choose glyph contrast from the underlying camera pixel; no HUD backplate.
    wire hud_light_bg=(p1_base[23] && p1_base[15]) ||
        (p1_base[23] && p1_base[7]) || (p1_base[15] && p1_base[7]);
    always @(*) begin
        c_char = 8'h20; c_row = 4'd0; c_col = 4'd0; c_ok = 1'b0; c_color = COLOR_WIDTH;
        c_dig_x = 8'd0; c_dig_i = 3'd0; c_dig_l = 4'd0;
        c_batch_count=0;c_batch_target=0;c_batch_total=0;c_batch_type=1;c_batch_overrun=0;ui_text="                ";ui_item=0;
        // 数字格：15 像素一格，比较链求格号（不用除法）
        c_dig_x = (p1_band == BAND_DYN) ? p1_dx - 8'd110 : p1_dx - 8'd28;
        if      (c_dig_x < 8'd15) begin c_dig_i = 3'd0; c_dig_l = c_dig_x[3:0]; end
        else if (c_dig_x < 8'd30) begin c_dig_i = 3'd1; c_dig_l = c_dig_x - 8'd15; end
        else if (c_dig_x < 8'd45) begin c_dig_i = 3'd2; c_dig_l = c_dig_x - 8'd30; end
        else if (c_dig_x < 8'd60) begin c_dig_i = 3'd3; c_dig_l = c_dig_x - 8'd45; end
        else if (c_dig_x < 8'd75) begin c_dig_i = 3'd4; c_dig_l = c_dig_x - 8'd60; end
        else                      begin c_dig_i = 3'd5; c_dig_l = c_dig_x - 8'd75; end
        case (p1_band)
            BAND_FX:begin
                c_col=p1_dx[3:0];c_row=p1_ly[3:0];c_ok=p1_dx<208;
                c_color=TARGET_ONLY && hud_light_bg ? 24'h005a86:24'h63c5ff;
                ui_text="VIEW            ";
                ui_text[63-:8]=display_mode_char(display_mode,0);ui_text[55-:8]=display_mode_char(display_mode,1);ui_text[47-:8]=display_mode_char(display_mode,2);ui_text[39-:8]=display_mode_char(display_mode,3);ui_text[31-:8]=display_mode_char(display_mode,4);
                c_char=TARGET_ONLY ? ui_text[127-p1_dx[7:4]*8-:8]:display_mode_char(display_mode,p1_dx[6:4]);
                if(!TARGET_ONLY) c_ok=p1_dx<80;
            end
            BAND_BATCH: begin
                case(p1_diag_row)
                    1:begin c_batch_count=batch_counts_frame[23:12];c_batch_target=batch_targets_frame[23:12];c_batch_type=2;c_batch_overrun=batch_overrun_mask_frame[1];end
                    2:begin c_batch_count=batch_counts_frame[35:24];c_batch_target=batch_targets_frame[35:24];c_batch_type=3;c_batch_overrun=batch_overrun_mask_frame[2];end
                    3:begin c_batch_count=batch_counts_frame[47:36];c_batch_target=batch_targets_frame[47:36];c_batch_type=4;c_batch_overrun=batch_overrun_mask_frame[3];end
                    default:begin c_batch_count=batch_counts_frame[11:0];c_batch_target=batch_targets_frame[11:0];c_batch_type=1;c_batch_overrun=batch_overrun_mask_frame[0];end
                endcase
                c_col=p1_dx[3:0];c_row=p1_ly[3:0];c_ok=p1_dx<240;
                c_color=(batch_overrun_frame && c_batch_overrun) ? (hud_light_bg ? 24'hb71c1c:24'hff7b72) :
                    (batch_done_frame ? (hud_light_bg ? 24'h00662f:24'h40ff80) :
                    (c_batch_target==0 ? (hud_light_bg ? 24'h5c6670:24'h9bacbf) :
                    (c_batch_count>=c_batch_target ? (hud_light_bg ? 24'h00662f:24'h40ff80) :
                    (batch_filter_frame==c_batch_type ? (hud_light_bg ? 24'h805000:24'hfff200):
                    (hud_light_bg ? 24'h18212b:24'he6edf5)))));
                case(c_batch_type)
                    1:c_batch_total=total_frame[11:0];2:c_batch_total=total_frame[23:12];
                    3:c_batch_total=total_frame[35:24];4:c_batch_total=total_frame[47:36];
                endcase
                case(p1_dx[7:4])
                    12:c_char={4'h3,c_batch_total[11:8]};
                    13:c_char={4'h3,c_batch_total[7:4]};
                    14:c_char={4'h3,c_batch_total[3:0]};
                    0:begin case(c_batch_type) 1:c_char="S";2:c_char="W";3:c_char="H";default:c_char="S";endcase end
                    1:begin case(c_batch_type) 1:c_char="C";2:c_char="A";3:c_char="E";default:c_char="Q";endcase end
                    2:begin case(c_batch_type) 1:c_char="R";2:c_char="S";3:c_char="X";default:c_char="U";endcase end
                    3:c_char=CHAR_COLON;
                    4:c_char={4'h3,c_batch_count[11:8]};
                    5:c_char={4'h3,c_batch_count[7:4]};
                    6:c_char={4'h3,c_batch_count[3:0]};
                    7:c_char=CHAR_SLASH;
                    8:c_char={4'h3,c_batch_target[11:8]};
                    9:c_char={4'h3,c_batch_target[7:4]};
                    10:c_char={4'h3,c_batch_target[3:0]};
                    default:c_char=8'h20;
                endcase
            end
            BAND_LATENCY: begin
                c_char=latency_char(p1_dx[7:4]);c_col=p1_dx[3:0];c_row=p1_ly[3:0];
                c_ok=1;c_color=24'hffffff;
            end
            BAND_COLOUR_DIAG: begin
                c_col=p1_dx[3:0];c_row=p1_ly[3:0];c_ok=p1_dx<256;
                c_color=24'he6edf5;
                if(p1_is_menu) begin
                    c_ok=c_ok && p1_ly<16;
                    ui_item={menu_index_frame[3],3'd0}+p1_diag_row-1'b1;
                    if(p1_diag_row==0) begin
                        ui_text="CONTROLS    1/2 ";ui_text[31:24]=menu_index_frame[3] ? "2":"1";
                        c_color=24'h63c5ff;
                    end else if(p1_diag_row==9) begin ui_text="K1 UP  K2 DOWN  ";c_color=24'h9bacbf;end
                    else if(p1_diag_row==10) begin ui_text="K3 -   K4 +/ACK ";c_color=24'h9bacbf;end
                    else if(p1_diag_row>=1 && p1_diag_row<=8 && ui_item<=14) begin
                        if(ui_item==menu_index_frame) c_color=24'hffffff;
                        case(ui_item)
                            0:begin ui_text=" VIEW           ";ui_text[55-:8]=display_mode_char(menu_preview_frame,0);ui_text[47-:8]=display_mode_char(menu_preview_frame,1);ui_text[39-:8]=display_mode_char(menu_preview_frame,2);ui_text[31-:8]=display_mode_char(menu_preview_frame,3);ui_text[23-:8]=display_mode_char(menu_preview_frame,4);end
                            1:begin
                                case(menu_motor_frame)
                                    1:ui_text=" MOTOR   LOW 65%";
                                    2:ui_text=" MOTOR   MID 80%";
                                    3:ui_text=" MOTOR   HI 100%";
                                    default:ui_text=" MOTOR   STOP   ";
                                endcase
                            end
                            2:ui_text=menu_awb_frame ? " AWB     FREEZE ":" AWB     AUTO   ";
                            3:ui_text=!menu_ae_auto_frame ? " AE      MAN    ":menu_ae_locked_frame ? " AE      LOCK   ":" AE      AUTO   ";
                            4:begin ui_text=" EXP     0000   ";ui_text[55:24]={{4'h3,camera_display[27:24]},{4'h3,camera_display[23:20]},{4'h3,camera_display[19:16]},{4'h3,camera_display[15:12]}};end
                            5:begin ui_text=" GAIN    000    ";ui_text[55:32]={{4'h3,camera_display[11:8]},{4'h3,camera_display[7:4]},{4'h3,camera_display[3:0]}};end
                            6,7,8,9:begin
                                case(ui_item) 6:begin ui_text=" SCR SET 000    ";c_batch_target=batch_targets_frame[11:0];end
                                    7:begin ui_text=" WAS SET 000    ";c_batch_target=batch_targets_frame[23:12];end
                                    8:begin ui_text=" HEX SET 000    ";c_batch_target=batch_targets_frame[35:24];end
                                    9:begin ui_text=" SQU SET 000    ";c_batch_target=batch_targets_frame[47:36];end endcase
                                ui_text[55:32]={{4'h3,c_batch_target[11:8]},{4'h3,c_batch_target[7:4]},{4'h3,c_batch_target[3:0]}};
                            end
                            10:ui_text=" NEW BATCH RESET";
                            11:begin ui_text=" AE Y    152    ";ui_text[55:32]={{4'h3,ae_target_digits[11:8]},{4'h3,ae_target_digits[7:4]},{4'h3,ae_target_digits[3:0]}};end
                            12:begin ui_text=" DETAIL  2      ";ui_text[55:48]=8'd48+enhance_frame[5:4];end
                            13:begin ui_text=" NOISE   04     ";ui_text[55:48]=enhance_frame[3:0]>=10 ? "1":"0";ui_text[47:40]=8'd48+(enhance_frame[3:0]>=10 ? enhance_frame[3:0]-10:enhance_frame[3:0]);end
                            14:ui_text=" ACK NG  CONFIRM";
                        endcase
                        if(ui_item==menu_index_frame) ui_text[127:120]=">";
                    end
                    c_char=ui_text[127-p1_dx[7:4]*8-:8];
                end else if(PARTS_MODE && p1_diag_row==15) begin
                    c_color=hud_light_bg ? 24'h18212b:24'he6edf5;
                    ui_text=menu_motor_frame!=0 ? "BATCH: RUN      ":"BATCH: READY    ";
                    if(batch_overrun_frame) begin ui_text="BATCH: NG STOP  ";c_color=hud_light_bg ? 24'hb71c1c:24'hff7b72;end
                    else if(enhance_frame[6]) begin ui_text="BATCH:CLEAR VIEW";c_color=hud_light_bg ? 24'h805000:24'hfff200;end
                    else if(batch_done_frame) begin ui_text="BATCH: COMPLETE ";c_color=hud_light_bg ? 24'h00662f:24'h72dca2;end
                    c_char=ui_text[127-p1_dx[7:4]*8-:8];
                end else if(FPS_DISPLAY && PARTS_MODE && p1_diag_row==14) begin
                    ui_text="FPS     ---     ";
                    if(fps_frame_valid) ui_text[63:40]={{4'h3,fps_frame[11:8]},{4'h3,fps_frame[7:4]},{4'h3,fps_frame[3:0]}};
                    c_char=ui_text[127-p1_dx[7:4]*8-:8];c_color=hud_light_bg ? 24'h18212b:24'he6edf5;
                end else if(PARTS_MODE && p1_diag_row==12) begin
                    ui_text="PART OK/SET PASS";c_char=ui_text[127-p1_dx[7:4]*8-:8];c_color=hud_light_bg ? 24'h005a86:24'h9bc5e4;
                end else begin
                    c_char=WB_DIAGNOSTICS ? (p1_diag_row==0 ? colour_diagnostic_char(0,p1_dx[7:4]):wb_diagnostic_char(p1_diag_row[2:0],p1_dx[7:4])):
                        colour_diagnostic_char(p1_diag_row[2:0],p1_dx[7:4]);
                end
            end
            BAND_EXPOSURE,BAND_GAIN: begin
                c_col=p1_dx[3:0];c_row=p1_ly[3:0];c_ok=p1_dx<208;
                c_color=TARGET_ONLY && hud_light_bg ? 24'h18212b:24'he6edf5;
                if(p1_band==BAND_EXPOSURE) begin
                    ui_text="EXP     0000    ";ui_text[63:32]={{4'h3,camera_display[27:24]},{4'h3,camera_display[23:20]},{4'h3,camera_display[19:16]},{4'h3,camera_display[15:12]}};
                end else begin
                    ui_text="GAIN    000     ";ui_text[63:40]={{4'h3,camera_display[11:8]},{4'h3,camera_display[7:4]},{4'h3,camera_display[3:0]}};
                end
                c_char=ui_text[127-p1_dx[7:4]*8-:8];
            end
            BAND_TARGET: begin
                c_char=target_label_char(p1_target_shape,p1_target_colour,p1_dx[7:4]);
                c_col=p1_dx[3:0];c_row=p1_ly[3:0];
                c_color=24'hffffff;c_ok=p1_dx<(PARTS_MODE ? 208 : 192);
            end
            BAND_DYN: begin
                c_color = COLOR_DYN_TEXT;
                if (p1_dx < 8'd48) begin
                    // 安/路：24x24 → 16x16，下移 2 行
                    c_char = (p1_dx < 8'd24) ? CHAR_AN : CHAR_LU;
                    c_col  = f_s24((p1_dx < 8'd24) ? p1_dx[4:0] : p1_dx - 8'd24);
                    c_row  = f_s24(p1_ly - 5'd2);
                    c_ok   = (p1_ly >= 5'd2);
                end else if (p1_dx >= 8'd52 && p1_dx < 8'd100) begin
                    c_char = (p1_dx < 8'd68) ? CHAR_C : (p1_dx < 8'd84) ? CHAR_N : CHAR_T;
                    c_col  = (p1_dx < 8'd68) ? p1_dx - 8'd52 : (p1_dx < 8'd84) ? p1_dx - 8'd68 : p1_dx - 8'd84;
                    c_row  = p1_ly - 5'd4;
                    c_ok   = (p1_ly >= 5'd4) && (p1_ly < 5'd20);
                end else if (p1_dx >= 8'd100 && p1_dx < 8'd108) begin
                    c_char = CHAR_COLON;
                    c_col  = {p1_dx[2:0] - 3'd4, 1'b0};   // (dx-100)*2
                    c_row  = p1_ly - 5'd4;
                    c_ok   = (p1_ly >= 5'd4) && (p1_ly < 5'd20);
                end else if (p1_dx >= 8'd110 && p1_dx < 8'd200) begin
                    case (c_dig_i)
                        3'd0: c_char = {4'h3, S_cnt_d5};
                        3'd1: c_char = {4'h3, S_cnt_d4};
                        3'd2: c_char = {4'h3, S_cnt_d3};
                        3'd3: c_char = {4'h3, S_cnt_d2};
                        3'd4: c_char = {4'h3, S_cnt_d1};
                        default: c_char = {4'h3, S_cnt_d0};
                    endcase
                    c_col = c_dig_l;              // floor(lx*16/15) = lx (lx<15)
                    c_row = f_s24(p1_ly);
                    c_ok  = 1'b1;
                end
            end
            BAND_W2, BAND_W3, BAND_W4: begin
                c_color = (p1_band == BAND_W2) ? COLOR_WIDTH :
                          (p1_band == BAND_W3) ? COLOR_HOLE : COLOR_THRESH;
                if (p1_dx < 8'd24) begin
                    c_char = (p1_dx >= 8'd16) ? CHAR_COLON :
                             (p1_band == BAND_W2) ? CHAR_W :
                             (p1_band == BAND_W3) ? CHAR_I : CHAR_T;
                    c_col  = (p1_dx >= 8'd16) ? {p1_dx[2:0], 1'b0} : p1_dx[3:0];
                    c_row  = p1_ly - 5'd4;
                    c_ok   = (p1_ly >= 5'd4) && (p1_ly < 5'd20);
                end else if (p1_dx >= 8'd28 &&
                             p1_dx < ((p1_band == BAND_W4) ? 8'd73 : 8'd88)) begin
                    case ({p1_band == BAND_W4, p1_band == BAND_W3, c_dig_i[1:0]})
                        4'b0000: c_char = W_DCHAR0;
                        4'b0001: c_char = W_DCHAR1;
                        4'b0010: c_char = W_DCHAR2;
                        4'b0011: c_char = W_DCHAR3;
                        4'b0100: c_char = H_DCHAR0;
                        4'b0101: c_char = H_DCHAR1;
                        4'b0110: c_char = H_DCHAR2;
                        4'b0111: c_char = H_DCHAR3;
                        4'b1000: c_char = T_DCHAR2;
                        4'b1001: c_char = T_DCHAR1;
                        default: c_char = T_DCHAR0;
                    endcase
                    c_col = c_dig_l;
                    c_row = f_s24(p1_ly);
                    c_ok  = 1'b1;
                end
            end
            BAND_ST, BAND_MO, BAND_TY, BAND_CO: begin
                if (p1_dx < 8'd80) begin
                    c_col = p1_dx[3:0];
                    c_row = p1_ly[3:0];
                    c_ok  = 1'b1;
                    if(p1_band==BAND_FX) begin
                        c_char=display_mode_char(display_mode,p1_dx[6:4]);
                        c_color=24'hffffff;
                    end else if (p1_band == BAND_ST) begin
                        c_char  = measurement_char(S_meas_status, p1_dx[6:4]);
                        c_color = S_meas_valid ? COLOR_WIDTH : 24'hff6040;
                    end else if (p1_band == BAND_MO) begin
                        c_char  = motion_char(S_bbox_valid, S_bbox_moving, p1_dx[6:4]);
                        c_color = (!MULTI_TARGETS && S_bbox_moving) ? COLOR_MOVE : COLOR_WIDTH;
                    end else if(p1_band==BAND_CO) begin
                        c_char=color_char(S_bbox_valid,S_bbox_color_r,p1_dx[6:4]);
                        c_color=S_bbox_color_r==3 ? 24'h4080ff : S_bbox_color_r==2 ? 24'h40ff60 : S_bbox_color_r==1 ? 24'hff6040 : 24'hffa500;
                    end else begin
                        c_char  = type_char(S_bbox_type_r, p1_dx[6:4]);
                        c_color = (S_bbox_type_r == 3'd2 || S_bbox_type_r == 3'd6) ? COLOR_WIDTH : 24'hffa500;
                    end
                end
            end
            default: ;
        endcase
    end

    //---- P2 寄存：字符码/行/列、Logo 地址（146 = 128+16+2，移位加）----
    reg        p2_de, p2_hs, p2_vs;
    reg [23:0] p2_base;
    reg [4:0]  p2_ovl;
    reg [7:0]  S_pf_char;     // 送 osd_char_lib 的字符码（测试观察）
    reg [3:0]  S_pf_row, p2_col;
    reg        p2_ok;
    reg [23:0] S_osd_color;   // 当前文本像素颜色（测试观察）
    reg        p2_logo_in;
    reg [13:0] p2_lg_addr;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            {p2_de, p2_hs, p2_vs} <= 3'd0;
            p2_base <= 24'd0; p2_ovl <= 5'd0;
            S_pf_char <= 8'h20; S_pf_row <= 4'd0; p2_col <= 4'd0; p2_ok <= 1'b0;
            S_osd_color <= 24'd0; p2_logo_in <= 1'b0;
        end else begin
            p2_de <= p1_de; p2_hs <= p1_hs; p2_vs <= p1_vs;
            p2_base <= p1_base; p2_ovl <= p1_ovl;
            S_pf_char   <= c_char;
            S_pf_row    <= c_row;
            p2_col      <= c_col;
            p2_ok       <= c_ok && (p1_band != BAND_NONE);
            S_osd_color <= c_color;
            p2_logo_in  <= p1_logo_in;
        end
    end
    // ERAM 读地址寄存器不带复位，TD 才能吸收进 BRAM
    always @(posedge I_clk)
        p2_lg_addr <= {p1_lgy, 7'd0} + {p1_lgy, 4'd0} + {p1_lgy, 1'b0} + p1_lgx;

    //---- P3：字库行点阵寄存；Logo 索引 ERAM 同步读 ----
    wire [15:0] S_pf_row_bits;
    osd_font_sync u_osd_char_lib(.I_clk(I_clk),.I_char(S_pf_char),.I_row(S_pf_row),.O_row_bits(S_pf_row_bits));

    (* ram_style = "bram" *) reg [9:0]  S_logo_idx_mem [0:16383];
    (* ram_style = "bram" *) reg [24:0] S_logo_pal_mem [0:1023];   // [24]=不透明
    initial begin
        $readmemh("logo_idx.hex", S_logo_idx_mem);
        $readmemh("logo_pal.hex", S_logo_pal_mem);
    end

    reg        p3_de, p3_hs, p3_vs;
    reg [23:0] p3_base, p3_color;
    reg [4:0]  p3_ovl;
    reg [3:0]  p3_col;
    reg        p3_ok, p3_logo_in;
    wire [15:0] p3_bits=S_pf_row_bits;
    reg [9:0]  p3_logo_idx;
    always @(posedge I_clk) begin
        p3_logo_idx <= S_logo_idx_mem[p2_lg_addr];
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            {p3_de, p3_hs, p3_vs} <= 3'd0;
            p3_base <= 24'd0; p3_color <= 24'd0; p3_ovl <= 5'd0; p3_col <= 4'd0;
            p3_ok <= 1'b0; p3_logo_in <= 1'b0;
        end else begin
            p3_de <= p2_de; p3_hs <= p2_hs; p3_vs <= p2_vs;
            p3_base <= p2_base; p3_color <= S_osd_color; p3_ovl <= p2_ovl;
            p3_col <= p2_col; p3_ok <= p2_ok; p3_logo_in <= p2_logo_in;
        end
    end

    //---- P4：点阵位选；调色板 ERAM 同步读 ----
    reg        p4_de, p4_hs, p4_vs;
    reg [23:0] p4_base, p4_color;
    reg [24:0] p4_logo_rgb;
    reg [4:0]  p4_ovl;
    reg        p4_txt_on, p4_logo_on;
    always @(posedge I_clk) begin
        p4_logo_rgb <= S_logo_pal_mem[p3_logo_idx];
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            {p4_de, p4_hs, p4_vs} <= 3'd0;
            p4_base <= 24'd0; p4_color <= 24'd0; p4_ovl <= 5'd0;
            p4_txt_on <= 1'b0; p4_logo_on <= 1'b0;
        end else begin
            p4_de <= p3_de; p4_hs <= p3_hs; p4_vs <= p3_vs;
            p4_base <= p3_base; p4_color <= p3_color; p4_ovl <= p3_ovl;
            p4_txt_on  <= p3_ok && p3_bits[~p3_col];
            p4_logo_on <= p3_logo_in;
        end
    end

    //---- 输出：Logo > 文本 > 外接框 > 孔心 > 外心 > 检测线 > 视频 ----
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_hsync_1d <= 1'b0;
            S_video_hsync_2d <= 1'b0;
            S_video_de_1d    <= 1'b0;
            S_video_de_2d    <= 1'b0;
            S_video_data_1d  <= 24'd0;
            S_video_data_2d  <= 24'd0;
            O_hdmi_vsync     <= 1'b0;
            O_hdmi_hsync     <= 1'b0;
            O_hdmi_de        <= 1'b0;
            O_hdmi_data      <= 24'd0;
        end
        else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            S_video_hsync_1d <= I_video_hsync;
            S_video_hsync_2d <= S_video_hsync_1d;
            S_video_de_1d    <= I_video_de;
            S_video_de_2d    <= S_video_de_1d;
            S_video_data_1d  <= I_video_rd_data;
            S_video_data_2d  <= S_video_data_1d;
            O_hdmi_vsync     <= p4_vs;
            O_hdmi_hsync     <= p4_hs;
            O_hdmi_de        <= p4_de;
            if      (p4_logo_on && p4_logo_rgb[24]) O_hdmi_data <= p4_logo_rgb[23:0];
            else if (p4_txt_on)  O_hdmi_data <= p4_color;
            else if (p4_ovl[3])  O_hdmi_data <= (!MULTI_TARGETS && S_bbox_moving) ? COLOR_MOVE : COLOR_BOX;
            else if (p4_ovl[2])  O_hdmi_data <= COLOR_HOLE;
            else if (p4_ovl[1])  O_hdmi_data <= COLOR_WIDTH;
            else if (p4_ovl[0])  O_hdmi_data <= COLOR_PROBE;
            else if (p4_ovl[4])  O_hdmi_data <= COLOR_ROI;
            else                 O_hdmi_data <= p4_base;
        end
    end

endmodule
