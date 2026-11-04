

module design_top_wrapper (
    input wire        I_sys_clk,
    input wire        I_rst_n,
      
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    input wire [3:0]  I_button,

    input wire [3:0]  I_switch,      //乒乓开关SW1~SW4，拨上=1；SW1用于二值化显示开关

    output wire       O_pwm_v1,
    output wire       O_pwm_v2,
    output wire [3:0] O_motor_led,
    output wire       O_buzzer,

    output wire       O_screen_pwm,
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,

    inout wire        IO_rx_clk_pad_n, 
    inout wire        IO_rx_clk_pad_p, 
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n   
);


    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
    wire        	S_rst_n;
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req; 
    wire [28:0] S_camera_status;
    wire S_camera_status_upd;
    // The AWB diagnostic packet carries an uncorrected centre-background
    // RGB mean for white-balance diagnostics only. AE uses its own meter.
    wire [127:0] S_wb_diag;
    wire S_wb_diag_upd;
    wire [7:0] S_ae_meter_luma;
    wire S_ae_meter_valid,S_ae_meter_upd;
    wire [2:0] S_target_count;
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
		
	wire        	S_raw10_frame_start; 
	wire        	S_raw10_frame_end;   
	wire        	S_raw10_valid;       
	wire [39:0] 	S_raw10_data;
		
	wire 			S_axis_tlast;  
	wire 			S_axis_tuser;  
	wire [39:0]		S_axis_tdata;  
	wire 			S_axis_tvalid; 
	
	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;
	
	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid;
	wire 			S_ISP_frame_start;  //原始帧起始（早于数据~55拍），专供video_in同步
	

    wire        S_ddr_clk;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;


    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;      
    wire[127:0] S_vi_128b_data;    
    
    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy; 
    wire[1:0]   S_video_out_rp;     

    wire        S_ddr_user_wr_en;       
    wire        S_ddr_user_rd_en;       
    wire[24:0]  S_ddr_user_addr;        
    wire[127:0] S_ddr_user_wr_data;     
    wire        S_ddr_user_ready;       
    wire        S_ddr_user_rd_valid;    
    wire[127:0] S_ddr_user_rd_data;     

    wire        S_vi_ddr_wr_en;   
    wire[24:0]  S_vi_ddr_wr_addr; 
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;   
    wire[24:0]  S_vo_ddr_rd_addr; 
    wire        S_vo_ddr_rd_ready;
    wire        S_vo_dbg_fifo_rst;
    wire        S_vo_dbg_ddr_rd_valid;
    wire        S_vo_dbg_fifo_rd_en;
    wire        S_vo_dbg_fifo_empty;

    wire        S_init_calib_complete; 
    wire[24:0]  S_mc_app_addr;          
    wire[2:0]   S_mc_app_cmd;           
    wire        S_mc_app_en;            
    wire[127:0] S_mc_app_wdf_data;      
    wire        S_mc_app_wdf_end;       
    wire[15:0]  S_mc_app_wdf_mask;      
    wire        S_mc_app_wdf_wren;      
    wire[127:0] S_mc_app_rd_data;       
    wire        S_mc_app_rd_data_end;   
    wire        S_mc_app_rd_data_valid; 
    wire        S_mc_app_rdy;           
    wire        S_mc_app_wdf_rdy;       
    wire        S_mc_dbg_fifo_afull;
    wire        S_mc_dbg_app_rdy;
    wire        S_mc_dbg_wdf_rdy;
    wire        S_mc_dbg_cmd_pop;

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;

    wire[23:0]  S_video_rd_data;
    reg         S_dbg_raw_seen;
    reg         S_dbg_isp_seen;
    reg         S_dbg_ddr_wr_seen;
    reg         S_dbg_ddr_rd_seen;
    reg         S_dbg_cam_cfg_seen;
    reg         S_dbg_hs_seen;
    reg         S_dbg_csi_seen;
    reg         S_dbg_raw10_seen;
    reg         S_dbg_isp_fs_seen;
    reg         S_dbg_isp_valid_seen;
    reg         S_dbg_ddr_req_seen;
    reg         S_dbg_ddr_ready_seen;
    reg [1:0]   S_dbg_raw_seen_sync;
    reg [1:0]   S_dbg_isp_seen_sync;
    reg [1:0]   S_dbg_ddr_wr_seen_sync;
    reg [1:0]   S_dbg_ddr_rd_seen_sync;
    reg [1:0]   S_dbg_cam_cfg_seen_sync;
    reg [1:0]   S_dbg_hs_seen_sync;
    reg [1:0]   S_dbg_csi_seen_sync;
    reg [1:0]   S_dbg_raw10_seen_sync;
    reg [1:0]   S_dbg_isp_fs_seen_sync;
    reg [1:0]   S_dbg_isp_valid_seen_sync;
    reg [1:0]   S_dbg_ddr_req_seen_sync;
    reg [1:0]   S_dbg_ddr_ready_seen_sync;
    reg         S_dbg_video_nonzero_seen;
    reg         S_dbg_rd_req_seen;
    reg         S_dbg_rd_valid_seen;
    reg         S_dbg_rd_nonzero_seen;
    reg [1:0]   S_dbg_rd_req_seen_sync;
    reg [1:0]   S_dbg_rd_valid_seen_sync;
    reg [1:0]   S_dbg_rd_nonzero_seen_sync;
    reg         S_dbg_mc_init_seen;
    reg         S_dbg_mc_app_rdy_seen;
    reg         S_dbg_mc_wdf_rdy_seen;
    reg         S_dbg_mc_cmd_pop_seen;
    reg [1:0]   S_dbg_mc_init_seen_sync;
    reg [1:0]   S_dbg_mc_app_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_wdf_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_cmd_pop_seen_sync;
    wire[3:0]   S_hdmi_debug_status;
    wire        S_lane_error_any;
    wire        S_hdmi_pll_lock;


    assign O_screen_pwm = 1'b1;
    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    assign S_rst_n 		= S_pll_lock;
    assign S_hdmi_rst_n = S_pll_lock & S_hdmi_pll_lock;

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw_seen <= 1'b0;
        else if(S_raw10_frame_start | S_axis_tvalid)
            S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_seen <= 1'b0;
        else if(S_ISP_O_tuser | S_ISP_O_tvalid)
            S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_wr_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_rd_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_cam_cfg_seen <= 1'b0;
        else if(S_cam_cfg_done)
            S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_csi_seen <= 1'b0;
        else if(S_csi_frame_start | S_csi_valid)
            S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw10_seen <= 1'b0;
        else if(S_raw10_frame_start | S_raw10_valid)
            S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_fs_seen <= 1'b0;
        else if(S_ISP_O_tuser)
            S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_valid_seen <= 1'b0;
        else if(S_ISP_O_tvalid)
            S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_req_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_ready_seen <= 1'b0;
        else if(S_ddr_user_ready)
            S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_vo_ddr_rd_en)
            S_dbg_rd_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
            S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_init_seen <= 1'b0;
        else if(S_init_calib_complete)
            S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_app_rdy_seen <= 1'b0;
        else if(S_mc_dbg_app_rdy)
            S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if(S_mc_dbg_wdf_rdy)
            S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if(S_mc_dbg_cmd_pop)
            S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_dbg_cam_cfg_seen_sync <= 2'b00;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end
        else begin
            S_dbg_cam_cfg_seen_sync <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync      <= {S_dbg_hs_seen_sync[0],      S_dbg_hs_seen};
            S_dbg_csi_seen_sync     <= {S_dbg_csi_seen_sync[0],     S_dbg_csi_seen};
            S_dbg_raw10_seen_sync   <= {S_dbg_raw10_seen_sync[0],   S_dbg_raw10_seen};
            S_dbg_raw_seen_sync    <= {S_dbg_raw_seen_sync[0],    S_dbg_raw_seen};
            S_dbg_isp_seen_sync    <= {S_dbg_isp_seen_sync[0],    S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync  <= {S_dbg_isp_fs_seen_sync[0],  S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
                S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    assign S_hdmi_debug_status = {
        (|S_ddr_user_rd_data),
        S_ddr_user_rd_valid,
        S_vo_ddr_rd_en,
        S_vi_ddr_wr_en
    };
	
	assign O_cam_rst 	= 1'b1;
    assign O_cam_24m 	= S_24m_clk;
	
	
	
	
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( ~I_rst_n          ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        .clk4_out    (                   ),   // 52/260MHz 不再使用（HDMI 改由 u_pll_hdmi 提供）
        .clk5_out    (                   ),

        .lock        ( S_pll_lock        )

    );

    // HDMI 720p60 时钟：75MHz 像素 / 375MHz 串行（CEA-861 标准 74.25MHz 的近似，60.6Hz）
    pll_hdmi75 u_pll_hdmi(
        .refclk      ( I_sys_clk         ),
        .reset       ( ~I_rst_n          ),
        .clk0_out    ( S_hdmi_pixel_clk  ),
        .clk1_out    ( S_hdmi_serial_clk ),
        .lock        ( S_hdmi_pll_lock   )
    );


	

  
  // SW4 opens the on-screen function menu.  While the menu is visible all
  // four keys belong to it; with the menu closed KEY1/KEY2 retain the proven
  // camera exposure/gain control path.
  wire       S_menu_open;
  wire [3:0] S_menu_index;
  wire [2:0] S_menu_preview_mode;
  wire [2:0] S_menu_motor_level;
  wire       S_menu_awb_freeze;
  wire       S_menu_ae_auto;
  wire       S_camera_keys_armed;
  wire [24:0] S_ae_diagnostics;
  wire [4:0] S_menu_ae_target_level;
  wire [1:0] S_menu_enhance_strength;
  wire [3:0] S_menu_enhance_noise;
  wire S_menu_fault_ack;
  wire S_menu_ae_target_upd;
  wire S_ae_diagnostics_upd;
  // AE starts at power-on and uses a dedicated, validated image meter.
  // Neither motor selection nor recognition confirmation gates acquisition.
  wire       S_ae_auto_locked;
  wire [2:0] S_menu_target_type;
  wire       S_menu_target_inc;
  wire       S_menu_target_dec;
  wire       S_menu_count_clear;
  wire       S_menu_camera_adjust_toggle;
  wire       S_menu_camera_adjust_gain;
  wire       S_menu_camera_adjust_up;
  wire [3:0] S_camera_keys = (S_menu_open || !S_camera_keys_armed) ?
      4'hf : {I_button[1:0],2'b11};

  ae_set #(.DYNAMIC_TARGET(1)) u_ae_set (
      .I_clk(S_24m_clk),
      .I_rst(~S_rst_n),
      .I_btn(S_camera_keys),
      .I_cam_cfg_done(S_cam_cfg_done),
      .I_ae_cfg_done(S_ae_cfg_done),
      .I_menu_adjust_toggle(S_menu_camera_adjust_toggle),
      .I_menu_adjust_gain(S_menu_camera_adjust_gain),
      .I_menu_adjust_up(S_menu_camera_adjust_up),
      .I_auto_enable(S_menu_ae_auto),
      .I_target_level(S_menu_ae_target_level),.I_target_upd(S_menu_ae_target_upd),
      .I_luma(S_ae_meter_luma),
      .I_luma_valid(S_ae_meter_valid),
      .I_luma_upd(S_ae_meter_upd),
      .O_ae_req(S_ae_req),
      .O_ae(S_ae),
      .O_ag(S_ag),
      .O_status(S_camera_status),
      .O_status_upd(S_camera_status_upd),
      .O_auto_locked(S_ae_auto_locked),
      .O_diagnostics(S_ae_diagnostics),.O_diagnostics_upd(S_ae_diagnostics_upd)
  );

  // Central menu controller.  SW4 is synchronized internally; KEY1/KEY2 move
  // the cursor and KEY3/KEY4 decrement/increment (or execute RESET).
  wire        S_batch_done;
  wire        S_batch_overrun;
  wire [3:0]  S_batch_overrun_mask;
  wire        S_batch_wait_clear;
  wire        S_batch_stop=S_batch_done|S_batch_overrun|S_batch_wait_clear;
  wire [11:0] S_batch_count_bcd;
  wire [11:0] S_batch_target_bcd;
  wire [47:0] S_batch_counts_bcd;
  wire [47:0] S_batch_total_counts_bcd;
  wire [47:0] S_batch_targets_bcd;
  wire [2:0]  S_batch_filter_type;
  screen_menu_control u_screen_menu (
      .clk(I_sys_clk),
      .rst_n(S_rst_n),
      .I_menu_switch(I_switch[3]),
      .I_button_n(I_button),
      // A correct completed batch clears the remembered speed.  An overrun
      // only pauses PWM; after the rejected part is removed the old speed is
      // still available for automatic resume.
      .I_batch_done(S_batch_done|S_batch_wait_clear),
      .O_menu_open(S_menu_open),
      .O_menu_index(S_menu_index),
      .O_preview_mode(S_menu_preview_mode),
      .O_motor_level(S_menu_motor_level),
      .O_awb_freeze(S_menu_awb_freeze),
      .O_ae_auto(S_menu_ae_auto),
      .O_camera_keys_armed(S_camera_keys_armed),
      .O_ae_target_level(S_menu_ae_target_level),
      .O_enhance_strength(S_menu_enhance_strength),.O_enhance_noise(S_menu_enhance_noise),
      .O_fault_ack(S_menu_fault_ack),.O_ae_target_upd(S_menu_ae_target_upd),
      .O_target_type(S_menu_target_type),
      .O_target_inc(S_menu_target_inc),
      .O_target_dec(S_menu_target_dec),
      .O_count_clear(S_menu_count_clear),
      .O_camera_adjust_toggle(S_menu_camera_adjust_toggle),
      .O_camera_adjust_gain(S_menu_camera_adjust_gain),
      .O_camera_adjust_up(S_menu_camera_adjust_up)
  );

  // L298N output remains the verified one-PWM/one-LOW topology.  The desired
  // speed now comes from the menu instead of a hidden KEY4 state machine.
  l298n_motor_control u_motor_control (
      .clk(I_sys_clk),
      .rst_n(S_rst_n),
      .key_n(1'b1),
      .force_stop(S_batch_stop),
      .I_menu_override(1'b1),
      .I_menu_level(S_menu_motor_level),
      .in1(O_pwm_v1),
      .in2(O_pwm_v2),
      .level(),
      .status_toggle()
  );
  assign O_motor_led = 4'b0000;

  // Use the same latched NG that stops the conveyor. Normal STOP, DONE and
  // NEW BATCH / clear-view are silent; the sound never acknowledges a fault.
  batch_error_buzzer u_batch_error_buzzer (
      .clk(I_sys_clk),.rst_n(S_rst_n),
      .alarm(S_batch_overrun),.buzzer_n(O_buzzer)
  );
  
    uicfgcs500 #(
      .CLK_DIV(24000000 / 100000 - 1)
  ) u_uicfgcs500 (
      .I_clk(S_24m_clk),  //系统时钟输入
      .I_rst_n(S_rst_n),  //系统复位输入
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
      .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
      .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
      .O_ae_cfg_done(S_ae_cfg_done)  //AE配置完成
  );
	
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "0dB"   ),//"0dB","1.5dB","3dB","4.5dB","6dB","7.5dB","9dB","10.5dB"
        .HS_VGA_GAIN           ( "8dB" ),//"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 ( ~S_rst_n         ),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),
     
        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),
      
        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),
      
        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),
      
        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),
      
        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );
	
	
 //  cwc cwc_inst
 //(
 //    .probe0(S_hs_rx_valid),
 //    .probe1(S_hs_rx_data),
 //    .probe2(S_lane_error),
 //    .clk(S_csi_rx_clk)
 //);

 //csi 解码为RAW数据
csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               ( S_rst_n        	),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        )
);


//解码为RAW8
raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );


//将数据转为stream流
uial2axis #(
.IMG_WIDTH(1280),
.IMG_HEIGHT(720),
.INPUT_DATA_WIDTH(40)
) 
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
);
	

image_correction #(
    .DATA_WIDTH(40)
)(
    .I_clk   		(S_csi_rx_clk),
    .I_rst_n 		(S_rst_n),
					
    .I_raw_data 	(S_axis_tdata),
    .I_raw_frame_end 	(S_axis_tlast),
    .I_raw_valid	(S_axis_tvalid),
    .I_raw_frame_start 	(S_axis_tuser),
					
    .O_raw_tdata 	(S_raw_tdata ),
    .O_raw_tlast 	(S_raw_tlast ),
    .O_raw_tvalid	(S_raw_tvalid),
    .O_raw_tuser 	(S_raw_tuser )
);


//cwc1 cwc1_Inst
//  (
//      .probe0(S_axis_tuser),
//      .probe1(S_axis_tvalid),
//      .probe2(S_axis_tlast),
//      .probe3(S_axis_tdata),
//      .probe4(S_ISP_O_tuser),
//      .probe5(S_ISP_O_tvalid),
//      .probe6(S_ISP_O_tlast),
//      .probe7(S_ISP_O_tdata),
//      .probe8 (S_raw_tdata ),
//      .probe9 (S_raw_tlast ),
//      .probe10(S_raw_tvalid),
//      .probe11(S_raw_tuser ),
//      .clk(S_csi_rx_clk)
//  );


//ISP算法顶层模块
    wire [15:0] S_proj_span, S_proj_hole;
    wire        S_proj_upd;
    wire        S_proj_valid;
    wire [2:0]  S_proj_status;
    wire [10:0] S_proj_cx, S_proj_cy, S_proj_hx, S_proj_hy;
    wire [7:0]  S_otsu_thresh;
    wire        S_otsu_upd;
    wire [10:0] S_bbox_x0, S_bbox_x1, S_bbox_y0, S_bbox_y1;
    wire [10:0] S_bbox_cx, S_bbox_cy, S_bbox_w, S_bbox_h;
    wire [19:0] S_bbox_area;
    wire [2:0]  S_bbox_type;
    wire [2:0]  S_bbox_color;
    wire [31:0] S_color_reference;
    wire S_color_reference_upd;
    wire [127:0] S_color_diag;
    wire [223:0] S_targets;
    wire S_target_overflow;
    wire        S_bbox_moving, S_bbox_valid, S_bbox_upd;
    wire [23:0] S_bbox_cnt;
    wire [10:0] S_roi_x0, S_roi_x1, S_roi_y0, S_roi_y1;
    wire        S_roi_valid, S_roi_upd;

    localparam TIRE_MODE=1;
    // Set back to 0 to recover the confirmed black-ring/colour-cap demo.
    // One shared constant must select both recognition and OSD vocabulary.
    localparam PARTS_MODE=1;
    wire [2:0] S_display_mode;
    wire [15:0] S_latency_bcd;
    wire S_latency_valid,S_latency_upd;
    wire [11:0] S_fps_bcd;
    wire S_fps_upd;
    // Count complete 172800-word ISP frames, not the fixed HDMI refresh.
    video_frame_rate u_frame_rate(
        .camera_clk(S_csi_rx_clk),.system_clk(I_sys_clk),.rst_n(S_rst_n),
        .frame_start(S_ISP_O_tuser),.word_valid(S_ISP_O_tvalid),
        .fps_bcd(S_fps_bcd),.fps_update(S_fps_upd));
    isp_top #(.TIRE_MODE(TIRE_MODE),.PARTS_MODE(PARTS_MODE),.VIDEO_MODES(1),.DEBUG_CAPTURE(0),
        .COLOR_STABILITY(0),.AUTO_WHITE_BALANCE(PARTS_MODE),.MULTI_TARGETS(PARTS_MODE),.LATENCY_DIAGNOSTICS(1)) u_isp_top (
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_rst_n),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
.I_tdest         (),
.I_bin_en        (S_menu_preview_mode[2]   ),
.I_morph_mode    (S_menu_preview_mode[1:0] ),
.I_enhance_strength(S_menu_enhance_strength),.I_enhance_noise(S_menu_enhance_noise),
 .I_enhance_compare(I_switch[0]),
        .O_display_mode(S_display_mode),
.O_proj_span      (S_proj_span      ),
.O_proj_hole      (S_proj_hole      ),
.O_proj_upd       (S_proj_upd       ),
.O_proj_valid     (S_proj_valid     ),
.O_proj_status    (S_proj_status    ),
.O_proj_cx        (S_proj_cx        ),
.O_proj_cy        (S_proj_cy        ),
.O_proj_hx        (S_proj_hx        ),
.O_proj_hy        (S_proj_hy        ),
.O_thresh_val     (S_otsu_thresh    ),
.O_thresh_upd     (S_otsu_upd       ),
.O_frame_start    (S_ISP_frame_start),
.O_bbox_x0        (S_bbox_x0        ),
.O_bbox_x1        (S_bbox_x1        ),
.O_bbox_y0        (S_bbox_y0        ),
.O_bbox_y1        (S_bbox_y1        ),
.O_bbox_cx        (S_bbox_cx        ),
.O_bbox_cy        (S_bbox_cy        ),
.O_bbox_w         (S_bbox_w         ),
.O_bbox_h         (S_bbox_h         ),
.O_bbox_area      (S_bbox_area      ),
.O_bbox_type      (S_bbox_type      ),
.O_bbox_color     (S_bbox_color     ),
.O_bbox_moving    (S_bbox_moving    ),
.O_bbox_cnt       (S_bbox_cnt       ),
.O_bbox_valid     (S_bbox_valid     ),
.O_bbox_upd       (S_bbox_upd       ),
.O_roi_x0         (S_roi_x0         ),
.O_roi_x1         (S_roi_x1         ),
.O_roi_y0         (S_roi_y0         ),
.O_roi_y1         (S_roi_y1         ),
.O_roi_valid      (S_roi_valid      ),
.O_roi_upd        (S_roi_upd        ),
.I_awb_freeze     (S_menu_awb_freeze),
.I_camera_status(S_camera_status),.I_camera_status_upd(S_camera_status_upd),
.O_color_reference(S_color_reference),.O_color_reference_upd(S_color_reference_upd),
.O_color_diag(S_color_diag),
.O_wb_diag(S_wb_diag),.O_wb_diag_upd(S_wb_diag_upd),
.O_ae_luma(S_ae_meter_luma),.O_ae_valid(S_ae_meter_valid),.O_ae_upd(S_ae_meter_upd),
.O_targets(S_targets),.O_target_count(S_target_count),.O_target_overflow(S_target_overflow),
.O_latency_bcd(S_latency_bcd),.O_latency_valid(S_latency_valid),.O_latency_upd(S_latency_upd),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        ()
  );

    // Batch counter for the left-to-right conveyor.  S_bbox_upd is already a
    // camera-domain toggle and S_targets remains stable until the next toggle,
    // so the controller uses a bundled-data CDC into the 50 MHz system domain.
    // Target editing and count clearing are now explicit menu events.  The old
    // direct-key inputs are held released so one press cannot affect two
    // independent controllers.
    conveyor_batch_counter #(
        .LINE_X(11'd640),
        .DEFAULT_TARGET_BCD(12'h010)
    ) u_batch_counter (
        .clk(I_sys_clk),
        .rst_n(S_rst_n),
        .I_targets_toggle(S_bbox_upd),
        .I_targets(S_targets),
        .I_set_enable(1'b0),
        .I_key_inc_n(1'b1),
        .I_key_dec_n(1'b1),
        .I_key_clear_n(1'b1),
        .I_menu_type(S_menu_target_type),
        .I_menu_inc(S_menu_target_inc),
        .I_menu_dec(S_menu_target_dec),
        .I_menu_clear(S_menu_count_clear),
        .I_menu_ack(S_menu_fault_ack),.I_detection_fault(S_target_overflow),.I_count_active(S_menu_motor_level!=0),
        .O_total_counts_bcd(S_batch_total_counts_bcd),.O_wait_clear(S_batch_wait_clear),
        .O_count_bcd(S_batch_count_bcd),
        .O_target_bcd(S_batch_target_bcd),
        .O_counts_bcd(S_batch_counts_bcd),
        .O_targets_bcd(S_batch_targets_bcd),
        .O_filter_type(S_batch_filter_type),
        .O_done(S_batch_done),
        .O_overrun(S_batch_overrun),
        .O_overrun_mask(S_batch_overrun_mask)
    );


    video_in #(.DEBUG_CAPTURE(0)) u_video_in(
        .I_rst_n              (  S_rst_n             ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        .I_camera_frame_start ( S_ISP_frame_start     ),
        .I_camera_valid       ( S_ISP_O_tvalid ),
        .I_camera_data        ( S_ISP_O_tdata  ),
        .I_mipi_rx_error      ( 1'b0			      ),

        .I_ddr_clk            ( S_ddr_clk             ),
		.I_display_pause      ( 1'b0                  ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy   ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_ddr_user_ready      )
    );



    assign S_ddr_user_wr_en    = S_vi_ddr_wr_en;

    assign S_ddr_user_rd_en    = S_vo_ddr_rd_en;

    assign S_ddr_user_addr     = S_vi_ddr_wr_en ? S_vi_ddr_wr_addr :
                                 S_vo_ddr_rd_en ? S_vo_ddr_rd_addr : 'd0;

    assign S_ddr_user_wr_data  = S_vi_ddr_wr_data;


    assign S_video_out_rst_n = S_hdmi_rst_n;

    video_out u_video_out(
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),
 
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy   ),
        .I_video_out_rp      ( S_video_out_rp       ),
 
        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_ddr_user_ready     ),
        .I_ddr_user_rd_valid ( S_ddr_user_rd_valid  ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_window_rd_en  ),
        .O_vdieo_data        ( S_video_rd_data      )
    );



    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),
            
        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );



    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk              ),
        .I_sys_rst_n            ( S_rst_n                ),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );



    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DEBUG_MODE ( 0    ),
        .VIDEO_READ_LATENCY ( 2 ),
        .DISPLAY_MODES ( 0 ),
        .TARGET_ONLY ( 1 ),
        .PARTS_MODE ( PARTS_MODE ),
        .CAMERA_CONTROL ( 1 ),
        .AE_DIAGNOSTICS ( 1 ),
        .LATENCY_DIAGNOSTICS ( 1 ),
        .FPS_DISPLAY ( 1 ),
        // Brass thresholds are now confirmed on hardware.  Remove the temporary
        // REF/RGB/R/S/Y/K/WHY panel to recover routing space; classification is
        // performed upstream and is not gated by this display-only parameter.
        .COLOR_DIAGNOSTICS ( 0 ),
        .SHOW_LOGO(1),.COMPACT_DIAGNOSTICS(0),.MULTI_TARGETS(PARTS_MODE),
        .BOX_TRACKING(PARTS_MODE),.BOX_TRACK_STEP(8),.BOX_TRACK_SNAP(96),
        .WB_DIAGNOSTICS(0),.AUTO_WHITE_BALANCE(PARTS_MODE)
    )u_hdmi_mixer(
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_hdmi_vsync       ),
        .I_video_hsync   ( S_hdmi_hsync       ),
        .I_video_de      ( S_hdmi_de          ),
        .I_video_user    ( S_hdmi_user        ),
        .I_video_last    ( S_hdmi_last        ),
        .I_debug_status  ( S_hdmi_debug_status),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_data ( S_video_rd_data    ),
        .I_meas_upd      ( S_proj_upd         ),
        .I_span          ( S_proj_span        ),
        .I_hole          ( S_proj_hole        ),
        .I_meas_valid    ( S_proj_valid       ),
        .I_meas_status   ( S_proj_status      ),
        .I_center_x      ( S_proj_cx          ),
        .I_center_y      ( S_proj_cy          ),
        .I_hole_x        ( S_proj_hx          ),
        .I_hole_y        ( S_proj_hy          ),
        .I_thresh_upd    ( S_otsu_upd         ),
        .I_thresh        ( S_otsu_thresh      ),
        .I_bbox_upd      ( S_bbox_upd         ),
        .I_bbox_x0       ( S_bbox_x0          ),
        .I_bbox_x1       ( S_bbox_x1          ),
        .I_bbox_y0       ( S_bbox_y0          ),
        .I_bbox_y1       ( S_bbox_y1          ),
        .I_bbox_cx       ( S_bbox_cx          ),
        .I_bbox_cy       ( S_bbox_cy          ),
        .I_bbox_w        ( S_bbox_w           ),
        .I_bbox_h        ( S_bbox_h           ),
        .I_bbox_area     ( S_bbox_area        ),
        .I_bbox_type     ( S_bbox_type        ),
        .I_bbox_moving   ( S_bbox_moving      ),
        .I_bbox_cnt      ( S_bbox_cnt         ),
        .I_bbox_valid    ( S_bbox_valid       ),
        .I_roi_upd       ( S_roi_upd          ),
        .I_roi_x0        ( S_roi_x0           ),
        .I_roi_x1        ( S_roi_x1           ),
        .I_roi_y0        ( S_roi_y0           ),
        .I_roi_y1        ( S_roi_y1           ),
        // Board mask is internal; production display only shows confirmed targets.
        .I_roi_valid     ( 1'b0 ),
        .I_bbox_color    ( S_bbox_color ),
        .I_display_mode  ( S_display_mode ),
        .I_camera_status ( S_camera_status ),
        .I_camera_status_upd ( S_camera_status_upd ),
        .I_color_reference(S_color_reference),.I_color_reference_upd(S_color_reference_upd),
        .I_color_diag(S_color_diag),
        .I_wb_diag(S_wb_diag),.I_wb_diag_upd(S_wb_diag_upd),
        .I_targets(S_targets),.I_target_count(S_target_count),.I_target_overflow(S_target_overflow),
        .I_batch_counts_bcd(S_batch_counts_bcd),.I_batch_total_counts_bcd(S_batch_total_counts_bcd),
        .I_batch_wait_clear(S_batch_wait_clear),.I_enhance_strength(S_menu_enhance_strength),.I_enhance_noise(S_menu_enhance_noise),
        .I_enhance_compare(I_switch[0]),
        .I_batch_targets_bcd(S_batch_targets_bcd),
        .I_batch_filter_type(S_batch_filter_type),.I_batch_done(S_batch_done),
        .I_batch_overrun(S_batch_overrun),.I_batch_overrun_mask(S_batch_overrun_mask),
        .I_menu_open(S_menu_open),.I_menu_index(S_menu_index),
        .I_menu_preview_mode(S_menu_preview_mode),.I_menu_motor_level(S_menu_motor_level),
        .I_menu_awb_freeze(S_menu_awb_freeze),.I_menu_ae_auto(S_menu_ae_auto),
        .I_menu_ae_locked(S_ae_auto_locked),
        .I_menu_ae_target_level(S_menu_ae_target_level),
        .I_ae_diagnostics(S_ae_diagnostics),.I_ae_diagnostics_upd(S_ae_diagnostics_upd),
        .I_latency_bcd(S_latency_bcd),.I_latency_valid(S_latency_valid),.I_latency_upd(S_latency_upd),
        .I_fps_bcd(S_fps_bcd),.I_fps_update(S_fps_upd),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_hdmi_out_vsync  ),
        .I_video_in_de      ( S_hdmi_out_de     ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_hdmi_out_data   ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );


    
endmodule

// Low-resource front-panel controller for the on-screen function menu.
// SW4=1 opens the menu.  KEY1/KEY2 move the cursor; KEY3/KEY4 change the
// selected value.  Settings are ordinary registers and remain active after
// SW4 closes the panel.  Button changes share one debounce timer because the
// user interface deliberately accepts one key action at a time.
module screen_menu_control #(
    parameter integer DEBOUNCE_CYCLES=250000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       I_menu_switch,
    input  wire [3:0] I_button_n,
    input  wire       I_batch_done,
    output reg        O_menu_open,
    output reg  [3:0] O_menu_index,
    output reg  [2:0] O_preview_mode,
    output reg  [2:0] O_motor_level,
    output reg        O_awb_freeze,
    output reg        O_ae_auto,
    output reg        O_camera_keys_armed,
    output reg [4:0]  O_ae_target_level,
    output reg [1:0]  O_enhance_strength,
    output reg [3:0]  O_enhance_noise,
    output reg        O_fault_ack,
    output reg        O_ae_target_upd,
    output reg  [2:0] O_target_type,
    output reg        O_target_inc,
    output reg        O_target_dec,
    output reg        O_count_clear,
    output reg        O_camera_adjust_toggle,
    output reg        O_camera_adjust_gain,
    output reg        O_camera_adjust_up
);
    localparam integer DBW=(DEBOUNCE_CYCLES<2)?1:$clog2(DEBOUNCE_CYCLES+1);
    (* ASYNC_REG="TRUE" *) reg [1:0] menu_sync;
    (* ASYNC_REG="TRUE" *) reg [3:0] button_meta,button_sync;
    reg [3:0] button_sample,button_stable;
    reg [DBW-1:0] debounce_count;
    reg menu_open_d;
    wire button_changed=button_sync!=button_sample;
    wire debounce_done=(debounce_count==DEBOUNCE_CYCLES) && !button_changed;
    wire [3:0] button_pressed=debounce_done ? (button_sample & ~button_stable):4'd0;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            menu_sync<=0;button_meta<=0;button_sync<=0;
        end else begin
            menu_sync<={menu_sync[0],I_menu_switch};
            button_meta<=~I_button_n;
            button_sync<=button_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            button_sample<=0;button_stable<=0;debounce_count<=0;
            O_menu_open<=0;menu_open_d<=0;O_menu_index<=0;
            // Power-on must acquire exposure without a key press. AUTO locks
            // itself only after valid image feedback has converged.
            O_preview_mode<=7;O_motor_level<=0;O_awb_freeze<=0;O_ae_auto<=1;
            O_camera_keys_armed<=0;O_ae_target_level<=19;O_ae_target_upd<=0;
            O_enhance_strength<=2;O_enhance_noise<=4;O_fault_ack<=0;
            O_target_type<=3'd1;O_target_inc<=0;O_target_dec<=0;O_count_clear<=0;O_fault_ack<=0;
            O_camera_adjust_toggle<=0;O_camera_adjust_gain<=0;O_camera_adjust_up<=0;
        end else begin
            O_target_inc<=0;O_target_dec<=0;O_count_clear<=0;O_fault_ack<=0;
            O_menu_open<=menu_sync[1];menu_open_d<=O_menu_open;
            if(button_changed) begin
                button_sample<=button_sync;debounce_count<=0;
            end else if(debounce_count<DEBOUNCE_CYCLES) begin
                debounce_count<=debounce_count+1'b1;
            end else begin
                button_stable<=button_sample;
            end

            // A completed quota always drops the remembered speed to STOP;
            // clearing counts therefore cannot restart the belt unexpectedly.
            if(I_batch_done) O_motor_level<=0;
            // Explicit camera keys outside the menu select manual control.
            // Startup-low or slowly settling key inputs are not an explicit
            // manual command. Arm only after a debounced released state.
            if(debounce_done && button_sample[1:0]==0) O_camera_keys_armed<=1;
            if(O_camera_keys_armed && !O_menu_open && |button_pressed[1:0]) O_ae_auto<=0;

            if(O_menu_open && !menu_open_d) O_menu_index<=0;
            else if(O_menu_open) begin
                if(button_pressed[0])
                    O_menu_index<=O_menu_index==0 ? 4'd14:O_menu_index-1'b1;
                else if(button_pressed[1])
                    O_menu_index<=O_menu_index==14 ? 4'd0:O_menu_index+1'b1;
                else if(button_pressed[2]) begin
                    case(O_menu_index)
                        4'd0:O_preview_mode<=O_preview_mode==0 ? 3'd7:O_preview_mode-1'b1;
                        4'd1:O_motor_level<=O_motor_level==0 ? 3'd3:O_motor_level-1'b1;
                        4'd2:O_awb_freeze<=~O_awb_freeze;
                        4'd3:O_ae_auto<=~O_ae_auto;
                        4'd4,4'd5:begin
                            O_ae_auto<=0;
                            O_camera_adjust_gain<=O_menu_index==5;
                            O_camera_adjust_up<=0;
                            O_camera_adjust_toggle<=~O_camera_adjust_toggle;
                        end
                        4'd6,4'd7,4'd8,4'd9:O_target_dec<=1;
                        4'd12:if(O_enhance_strength!=0) O_enhance_strength<=O_enhance_strength-1'b1;
                        4'd13:if(O_enhance_noise!=0) O_enhance_noise<=O_enhance_noise-1'b1;
                        4'd14:O_fault_ack<=1;
                        4'd11:if(O_ae_target_level>8) begin
                            O_ae_target_level<=O_ae_target_level-1'b1;
                            O_ae_target_upd<=~O_ae_target_upd;
                        end
                        default:begin O_count_clear<=1;O_motor_level<=0;end
                    endcase
                end else if(button_pressed[3]) begin
                    case(O_menu_index)
                        4'd0:O_preview_mode<=O_preview_mode==7 ? 3'd0:O_preview_mode+1'b1;
                        4'd1:O_motor_level<=O_motor_level>=3 ? 3'd0:O_motor_level+1'b1;
                        4'd2:O_awb_freeze<=~O_awb_freeze;
                        4'd3:O_ae_auto<=~O_ae_auto;
                        4'd4,4'd5:begin
                            O_ae_auto<=0;
                            O_camera_adjust_gain<=O_menu_index==5;
                            O_camera_adjust_up<=1;
                            O_camera_adjust_toggle<=~O_camera_adjust_toggle;
                        end
                        4'd6,4'd7,4'd8,4'd9:O_target_inc<=1;
                        4'd12:if(O_enhance_strength!=3) O_enhance_strength<=O_enhance_strength+1'b1;
                        4'd13:if(O_enhance_noise!=15) O_enhance_noise<=O_enhance_noise+1'b1;
                        4'd14:O_fault_ack<=1;
                        4'd11:if(O_ae_target_level<24) begin
                            O_ae_target_level<=O_ae_target_level+1'b1;
                            O_ae_target_upd<=~O_ae_target_upd;
                        end
                        default:begin O_count_clear<=1;O_motor_level<=0;end
                    endcase
                end
            end

            if(O_menu_index>=6 && O_menu_index<=9)
                O_target_type<=O_menu_index-4'd5;
        end
    end
endmodule

// Single DC motor, L298N bridge A: ENA must be held HIGH externally.
// IN1 = 10 kHz drive/brake PWM, IN2 = LOW. 00 is BRAKE, not coast.
// KEY4 short RELEASE: STOP -> LOW 65 -> MID 80 -> HIGH 100 -> STOP.
// Hold for 1 second: stop; releasing after a long press does not restart.
// Duty is open loop, not measured RPM. No automatic startup boost.
module l298n_motor_control #(
    parameter integer CLK_HZ=50000000,
    parameter integer PWM_HZ=10000,
    parameter integer DEBOUNCE_CYCLES=1000000,
    parameter integer LONG_PRESS_CYCLES=50000000
)(
    input wire clk,rst_n,key_n,force_stop,
    input wire I_menu_override,
    input wire [2:0] I_menu_level,
    output reg in1,
    output wire in2,
    output reg [2:0] level,
    output reg status_toggle
);
    localparam integer PERIOD=CLK_HZ/PWM_HZ;
    localparam integer PW=$clog2(PERIOD+1);
    localparam integer DW=(DEBOUNCE_CYCLES<2)?1:$clog2(DEBOUNCE_CYCLES);
    localparam integer LW=(LONG_PRESS_CYCLES<2)?1:$clog2(LONG_PRESS_CYCLES);
    // Local reset release and asynchronous pushbutton synchronization.
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync;
    (* ASYNC_REG="TRUE" *) reg [1:0] key_sync;
    wire ready=reset_sync[1];
    reg key_stable,armed,press_active,long_fired;
    reg [DW-1:0] debounce_count;
    reg [LW-1:0] hold_count;
    reg [PW-1:0] phase,active_duty;
    reg [PW-1:0] requested_duty;
    wire key_transition=key_sync[1]!=key_stable && debounce_count==DEBOUNCE_CYCLES-1;
    wire stop_hold=press_active && !key_stable && !long_fired && hold_count==LONG_PRESS_CYCLES-1;
    assign in2=1'b0;

    always @* begin
        case(level)
            1:requested_duty=(PERIOD*65)/100;
            2:requested_duty=(PERIOD*80)/100;
            3:requested_duty=PERIOD;
            default:requested_duty=0;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin reset_sync<=0;key_sync<=0;end
        else begin reset_sync<={reset_sync[0],1'b1};key_sync<={key_sync[0],key_n};end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            // Treat startup as held/unarmed. A stable release must occur first.
            key_stable<=0;armed<=0;press_active<=0;long_fired<=0;
            debounce_count<=0;hold_count<=0;level<=0;status_toggle<=0;
        end else if(!ready)begin
            key_stable<=0;armed<=0;press_active<=0;long_fired<=0;
            debounce_count<=0;hold_count<=0;level<=0;status_toggle<=0;
        end else if(force_stop) begin
            // A completed batch is latched by the batch controller.  Clear the
            // selected speed as well as the PWM so releasing KEY4 cannot cause
            // an unintended restart when the next batch is armed.
            key_stable<=key_sync[1];armed<=0;press_active<=0;long_fired<=0;
            debounce_count<=0;hold_count<=0;level<=0;
        end else if(I_menu_override) begin
            key_stable<=key_sync[1];armed<=0;press_active<=0;long_fired<=0;
            debounce_count<=0;hold_count<=0;level<=I_menu_level;
        end else begin
            if(key_sync[1]==key_stable)debounce_count<=0;
            else if(key_transition)begin
                key_stable<=key_sync[1];debounce_count<=0;
                if(key_sync[1])begin
                    armed<=1;press_active<=0;hold_count<=0;long_fired<=0;
                    if(press_active && !long_fired && !stop_hold)begin
                        level<=level>=3 ? 3'd0:level+1'b1;
                        status_toggle<=~status_toggle;
                    end
                end else if(armed)begin
                    press_active<=1;hold_count<=0;long_fired<=0;
                end
            end else debounce_count<=debounce_count+1'b1;

            if(press_active && !key_stable && !long_fired)begin
                if(stop_hold)begin
                    level<=0;long_fired<=1;hold_count<=0;
                    status_toggle<=~status_toggle;
                end else hold_count<=hold_count+1'b1;
            end
        end
    end
    // Boundary-only duty changes avoid partial/extra drive pulses. Stop bypasses
    // the boundary wait. The motor clock never depends on video or BG READY.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin phase<=PERIOD-1;active_duty<=0;in1<=0;end
        else if(!ready || force_stop || level==0 || stop_hold)begin
            phase<=PERIOD-1;active_duty<=0;in1<=0;
        end else if(phase==PERIOD-1)begin
            phase<=0;active_duty<=requested_duty;in1<=requested_duty!=0;
        end else begin
            phase<=phase+1'b1;in1<=(phase+1'b1)<active_duty;
        end
    end
endmodule

// Identity-based, directional batch counter. Each observed ID must first
// enter the upstream zone; crossing the downstream boundary counts once.
// Missing observations do not immediately release identities. Removed reject
// classes resume after qualified observations; ambiguous faults require ACK.
// Complete-frame event crosses to the reference clock; held BCD statistics
// cross onward to HDMI only once per second. No video data is delayed.
module video_frame_rate #(
    parameter integer SYSTEM_HZ=50000000,
    parameter integer WORDS_PER_FRAME=172800
)(
    input wire camera_clk,system_clk,rst_n,frame_start,word_valid,
    output reg [11:0] fps_bcd,
    output reg fps_update
);
    localparam integer WORD_BITS=$clog2(WORDS_PER_FRAME+1);
    localparam integer SECOND_BITS=$clog2(SYSTEM_HZ+1);
    reg [WORD_BITS-1:0] words;
    reg active,completed,complete_toggle;
    wire [WORD_BITS-1:0] words_now=frame_start ? 0:words;
    always @(posedge camera_clk or negedge rst_n) begin
        if(!rst_n) begin words<=0;active<=0;completed<=0;complete_toggle<=0;end
        else begin
            if(frame_start) begin words<=0;active<=1;completed<=0;end
            if(word_valid && (active || frame_start) && (!completed || frame_start)) begin
                if(words_now==WORDS_PER_FRAME-1) begin
                    completed<=1;complete_toggle<=~complete_toggle;
                end else words<=words_now+1'b1;
            end
        end
    end
    (* ASYNC_REG="TRUE" *) reg [1:0] complete_sync;
    reg complete_seen;
    reg [SECOND_BITS-1:0] second_counter;
    reg [11:0] frame_count;
    wire frame_event=complete_sync[1]!=complete_seen;
    function [11:0] increment_bcd;
        input [11:0] value;
        begin
            if(value==12'h999) increment_bcd=value;
            else if(value[3:0]!=9) increment_bcd=value+12'h001;
            else if(value[7:4]!=9) increment_bcd=value+12'h007;
            else increment_bcd=value+12'h067;
        end
    endfunction
    always @(posedge system_clk or negedge rst_n) begin
        if(!rst_n) begin
            complete_sync<=0;complete_seen<=0;second_counter<=0;
            frame_count<=0;fps_bcd<=0;fps_update<=0;
        end else begin
            complete_sync<={complete_sync[0],complete_toggle};complete_seen<=complete_sync[1];
            if(second_counter==SYSTEM_HZ-1) begin
                second_counter<=0;fps_bcd<=frame_event ? increment_bcd(frame_count):frame_count;
                frame_count<=0;fps_update<=~fps_update;
            end else begin
                second_counter<=second_counter+1'b1;
                if(frame_event) frame_count<=increment_bcd(frame_count);
            end
        end
    end
endmodule

// Board C12 drives the buzzer through an active-low PNP stage. An NG starts
// a 200 ms / 2 kHz burst immediately and repeats once per second until the
// counter clears NG. Keep this observer separate from all counting controls.
module batch_error_buzzer #(
    parameter integer CLK_HZ=50000000,
    parameter integer TONE_HZ=2000,
    parameter integer ON_MS=200,
    parameter integer PERIOD_MS=1000
)(
    input wire clk,
    input wire rst_n,
    input wire alarm,
    output reg buzzer_n
);
    localparam integer HALF_CYCLES=CLK_HZ/(2*TONE_HZ);
    localparam integer ON_CYCLES=(CLK_HZ/1000)*ON_MS;
    localparam integer PERIOD_CYCLES=(CLK_HZ/1000)*PERIOD_MS;
    localparam integer TW=(HALF_CYCLES<2)?1:$clog2(HALF_CYCLES);
    localparam integer PW=(PERIOD_CYCLES<2)?1:$clog2(PERIOD_CYCLES);
    reg [TW-1:0] tone_count;
    reg [PW-1:0] period_count;
    reg active;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            buzzer_n<=1'b1;active<=1'b0;tone_count<=0;period_count<=0;
        end else if(!alarm) begin
            buzzer_n<=1'b1;active<=1'b0;tone_count<=0;period_count<=0;
        end else if(!active || period_count==PERIOD_CYCLES-1) begin
            buzzer_n<=1'b0;active<=1'b1;tone_count<=0;period_count<=0;
        end else begin
            period_count<=period_count+1'b1;
            if(period_count>=ON_CYCLES-1) begin
                buzzer_n<=1'b1;tone_count<=0;
            end else if(tone_count==HALF_CYCLES-1) begin
                tone_count<=0;buzzer_n<=~buzzer_n;
            end else tone_count<=tone_count+1'b1;
        end
    end
endmodule

module conveyor_batch_counter #(
    parameter [10:0] LINE_X=11'd640,
    parameter [10:0] LINE_HYST=11'd16,
    parameter [11:0] DEFAULT_TARGET_BCD=12'h010,
    parameter integer DEBOUNCE_CYCLES=250000,
    parameter integer LONG_PRESS_CYCLES=50000000,
    // Number of consecutive target publications for which no object of the
    // offending class may be visible before the sorter resumes.
    parameter integer RECOVERY_PUBLICATIONS=3
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         I_targets_toggle,
    input  wire [223:0] I_targets,
    input  wire         I_set_enable,
    input  wire         I_key_inc_n,
    input  wire         I_key_dec_n,
    input  wire         I_key_clear_n,
    input  wire [2:0]   I_menu_type,
    input  wire         I_menu_inc,
    input  wire         I_menu_dec,
    input  wire         I_menu_clear,
    input wire I_menu_ack,I_detection_fault,I_count_active,
    output wire [47:0] O_total_counts_bcd,
    output reg O_wait_clear,
    output reg  [11:0]  O_count_bcd,
    output reg  [11:0]  O_target_bcd,
    output wire [47:0]  O_counts_bcd,
    output wire [47:0]  O_targets_bcd,
    output reg  [2:0]   O_filter_type,
    output reg          O_done,
    output reg          O_overrun,
    output reg  [3:0]   O_overrun_mask
);
    localparam integer DBW=(DEBOUNCE_CYCLES<2)?1:$clog2(DEBOUNCE_CYCLES);
    localparam integer LPW=(LONG_PRESS_CYCLES<2)?1:$clog2(LONG_PRESS_CYCLES);

    (* ASYNC_REG="TRUE" *) reg [1:0] targets_toggle_sync;
    reg targets_toggle_d;
    wire targets_event=targets_toggle_sync[1]^targets_toggle_d;

    (* ASYNC_REG="TRUE" *) reg [2:0] key_inc_sync,key_dec_sync,key_clear_sync;
    reg key_inc_stable,key_dec_stable,key_clear_stable;
    reg [DBW-1:0] key_inc_count,key_dec_count,key_clear_count;
    reg key_inc_pulse,key_dec_pulse,key_clear_press_pulse,key_clear_release_pulse;
    reg key_clear_active,key_clear_long_fired;
    reg [LPW-1:0] key_clear_hold_count;
    reg key_clear_short_pulse,key_shape_cycle_pulse;

    function [11:0] bcd_inc;
        input [11:0] value;
        begin
            if(value>=12'h099) bcd_inc=12'h099;
            else if(value[3:0]!=4'd9) bcd_inc={value[11:4],value[3:0]+1'b1};
            else bcd_inc={4'd0,value[7:4]+1'b1,4'd0};
        end
    endfunction

    function [11:0] bcd_dec;
        input [11:0] value;
        begin
            if(value==12'h000) bcd_dec=12'h000;
            else if(value[3:0]!=0) bcd_dec={value[11:4],value[3:0]-1'b1};
            else bcd_dec={4'd0,value[7:4]-1'b1,4'd9};
        end
    endfunction

    // Accepted batch counts and lifetime-through counts are separate. Only
    // a qualified reject removal can reduce accepted counts; totals
    // continue through DONE/NG and are never rewritten by reject recovery.
    reg [11:0] screw_count_bcd,washer_count_bcd,hex_count_bcd,square_count_bcd;
    reg [11:0] screw_total_bcd,washer_total_bcd,hex_total_bcd,square_total_bcd;
    reg [11:0] screw_target_bcd,washer_target_bcd,hex_target_bcd,square_target_bcd;
    reg [2:0] recovery_count;
    reg [223:0] observation;
    reg [1:0] process_index;
    reg [1:0] process_state;
    reg [3:0] seen_slots,pending_fault;
    reg pending_manual,manual_fault;
    reg [3:0] known,armed,counted;
    reg [1:0] generation[0:3],missing[0:3];
    reg [3:0] present_class_mask;
    reg any_observed;
    integer i,k;
    wire [55:0] current=observation[process_index*56+:56];
    wire observed=current[48];
    wire [1:0] slot=current[45:44];
    wire new_identity=!known[slot] || generation[slot]!=current[47:46];
    wire [11:0] centre_sum={1'b0,current[43:33]}+{1'b0,current[32:22]};
    wire [10:0] centre_x=centre_sum[11:1];
    wire known_class=current[54:52]>=1 && current[54:52]<=4;
    wire class_requested=current[54:52]==1 ? screw_target_bcd!=0:
        current[54:52]==2 ? washer_target_bcd!=0:
        current[54:52]==3 ? hex_target_bcd!=0:
        current[54:52]==4 ? square_target_bcd!=0:1'b0;
    wire [3:0] class_mask=current[54:52]==1 ? 4'b0001:current[54:52]==2 ? 4'b0010:
        current[54:52]==3 ? 4'b0100:current[54:52]==4 ? 4'b1000:4'b1111;
    wire crossing=observed && current[55] && known_class && !new_identity &&
        armed[slot] && !counted[slot] && centre_x>=LINE_X+LINE_HYST && !O_wait_clear;
    wire any_quota=(screw_target_bcd!=0)||(washer_target_bcd!=0)||
        (hex_target_bcd!=0)||(square_target_bcd!=0);
    wire quotas_met=any_quota &&
        (screw_target_bcd==0 || screw_count_bcd>=screw_target_bcd) &&
        (washer_target_bcd==0 || washer_count_bcd>=washer_target_bcd) &&
        (hex_target_bcd==0 || hex_count_bcd>=hex_target_bcd) &&
        (square_target_bcd==0 || square_count_bcd>=square_target_bcd);
    wire [3:0] overrun_now={
        square_target_bcd!=0 && square_count_bcd>square_target_bcd,
        hex_target_bcd!=0 && hex_count_bcd>hex_target_bcd,
        washer_target_bcd!=0 && washer_count_bcd>washer_target_bcd,
        screw_target_bcd!=0 && screw_count_bcd>screw_target_bcd};
    assign O_counts_bcd={square_count_bcd,hex_count_bcd,washer_count_bcd,screw_count_bcd};
    assign O_total_counts_bcd={square_total_bcd,hex_total_bcd,washer_total_bcd,screw_total_bcd};
    assign O_targets_bcd={square_target_bcd,hex_target_bcd,washer_target_bcd,screw_target_bcd};
    always @* begin
        case(O_filter_type)
            2:begin O_count_bcd=washer_count_bcd;O_target_bcd=washer_target_bcd;end
            3:begin O_count_bcd=hex_count_bcd;O_target_bcd=hex_target_bcd;end
            4:begin O_count_bcd=square_count_bcd;O_target_bcd=square_target_bcd;end
            default:begin O_count_bcd=screw_count_bcd;O_target_bcd=screw_target_bcd;end
        endcase
    end
    reg [55:0] view_packet;
    always @* begin
        present_class_mask=0;any_observed=0;
        for(i=0;i<4;i=i+1) begin
            view_packet=observation[i*56+:56];
            if(view_packet[48]) begin
                any_observed=1;
                case(view_packet[54:52])
                    1:present_class_mask[0]=1;2:present_class_mask[1]=1;
                    3:present_class_mask[2]=1;4:present_class_mask[3]=1;
                    default:present_class_mask=4'b1111;
                endcase
            end
        end
    end

    // Toggle and key synchronizers.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            targets_toggle_sync<=0;targets_toggle_d<=0;
            key_inc_sync<=3'b111;key_dec_sync<=3'b111;key_clear_sync<=3'b111;
        end else begin
            targets_toggle_sync<={targets_toggle_sync[0],I_targets_toggle};
            targets_toggle_d<=targets_toggle_sync[1];
            key_inc_sync<={key_inc_sync[1:0],I_key_inc_n};
            key_dec_sync<={key_dec_sync[1:0],I_key_dec_n};
            key_clear_sync<={key_clear_sync[1:0],I_key_clear_n};
        end
    end

    // Debounce KEY1..KEY3 and emit one pulse on each stable press.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            key_inc_stable<=1;key_dec_stable<=1;key_clear_stable<=1;
            key_inc_count<=0;key_dec_count<=0;key_clear_count<=0;
            key_inc_pulse<=0;key_dec_pulse<=0;key_clear_press_pulse<=0;key_clear_release_pulse<=0;
        end else begin
            key_inc_pulse<=0;key_dec_pulse<=0;key_clear_press_pulse<=0;key_clear_release_pulse<=0;
            if(key_inc_sync[2]==key_inc_stable) key_inc_count<=0;
            else if(key_inc_count==DEBOUNCE_CYCLES-1) begin
                key_inc_stable<=key_inc_sync[2];key_inc_count<=0;
                if(!key_inc_sync[2]) key_inc_pulse<=1;
            end else key_inc_count<=key_inc_count+1'b1;
            if(key_dec_sync[2]==key_dec_stable) key_dec_count<=0;
            else if(key_dec_count==DEBOUNCE_CYCLES-1) begin
                key_dec_stable<=key_dec_sync[2];key_dec_count<=0;
                if(!key_dec_sync[2]) key_dec_pulse<=1;
            end else key_dec_count<=key_dec_count+1'b1;
            if(key_clear_sync[2]==key_clear_stable) key_clear_count<=0;
            else if(key_clear_count==DEBOUNCE_CYCLES-1) begin
                key_clear_stable<=key_clear_sync[2];key_clear_count<=0;
                if(!key_clear_sync[2]) key_clear_press_pulse<=1;
                else key_clear_release_pulse<=1;
            end else key_clear_count<=key_clear_count+1'b1;
        end
    end

    // KEY3 short release clears all class counts.  A one-second hold changes
    // the selected quota/display class and suppresses the short-release action.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            key_clear_active<=0;key_clear_long_fired<=0;key_clear_hold_count<=0;
            key_clear_short_pulse<=0;key_shape_cycle_pulse<=0;
        end else begin
            key_clear_short_pulse<=0;key_shape_cycle_pulse<=0;
            if(key_clear_press_pulse) begin
                key_clear_active<=1;key_clear_long_fired<=0;key_clear_hold_count<=0;
            end else if(key_clear_active && !key_clear_stable && !key_clear_long_fired) begin
                if(key_clear_hold_count==LONG_PRESS_CYCLES-1) begin
                    key_shape_cycle_pulse<=1;key_clear_long_fired<=1;key_clear_hold_count<=0;
                end else key_clear_hold_count<=key_clear_hold_count+1'b1;
            end
            if(key_clear_release_pulse) begin
                if(key_clear_active && !key_clear_long_fired) key_clear_short_pulse<=1;
                key_clear_active<=0;key_clear_long_fired<=0;key_clear_hold_count<=0;
            end
        end
    end

    // Count publication events and maintain the batch setpoint/completion latch.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            screw_count_bcd<=0;washer_count_bcd<=0;hex_count_bcd<=0;square_count_bcd<=0;
            screw_total_bcd<=0;washer_total_bcd<=0;hex_total_bcd<=0;square_total_bcd<=0;
            screw_target_bcd<=DEFAULT_TARGET_BCD;washer_target_bcd<=0;hex_target_bcd<=0;square_target_bcd<=0;
            O_filter_type<=1;O_done<=0;O_overrun<=0;O_overrun_mask<=0;O_wait_clear<=0;
            recovery_count<=0;observation<=0;process_index<=0;process_state<=0;
            seen_slots<=0;pending_fault<=0;pending_manual<=0;manual_fault<=0;known<=0;armed<=0;counted<=0;
            for(k=0;k<4;k=k+1) begin generation[k]<=0;missing[k]<=0;end
        end else begin
            if(I_menu_type>=1 && I_menu_type<=4) O_filter_type<=I_menu_type;
            if(key_shape_cycle_pulse) O_filter_type<=O_filter_type==4 ? 3'd1:O_filter_type+1'b1;
            if(key_clear_short_pulse || I_menu_clear) begin
                screw_count_bcd<=0;washer_count_bcd<=0;hex_count_bcd<=0;square_count_bcd<=0;
                screw_total_bcd<=0;washer_total_bcd<=0;hex_total_bcd<=0;square_total_bcd<=0;
                O_done<=0;O_overrun<=0;O_overrun_mask<=0;recovery_count<=0;
                process_state<=0;pending_fault<=0;pending_manual<=0;manual_fault<=0;O_wait_clear<=1;
                // Objects already in view belong to the old batch. Require an
                // empty observation before allowing a fresh batch to start.
                armed<=0;counted<=known;
            end else begin
                if((I_set_enable && key_inc_pulse) || I_menu_inc) begin
                    O_done<=0;
                    case(I_menu_inc ? I_menu_type:O_filter_type)
                        2:washer_target_bcd<=bcd_inc(washer_target_bcd);
                        3:hex_target_bcd<=bcd_inc(hex_target_bcd);
                        4:square_target_bcd<=bcd_inc(square_target_bcd);
                        default:screw_target_bcd<=bcd_inc(screw_target_bcd);
                    endcase
                end else if((I_set_enable && key_dec_pulse) || I_menu_dec) begin
                    O_done<=0;
                    case(I_menu_dec ? I_menu_type:O_filter_type)
                        2:washer_target_bcd<=bcd_dec(washer_target_bcd);
                        3:hex_target_bcd<=bcd_dec(hex_target_bcd);
                        4:square_target_bcd<=bcd_dec(square_target_bcd);
                        default:screw_target_bcd<=bcd_dec(screw_target_bcd);
                    endcase
                end
                if(!O_overrun && |overrun_now) begin
                    O_overrun<=1;O_done<=0;O_overrun_mask<=overrun_now;recovery_count<=0;
                end
                // Ambiguous detector/identity faults retain explicit ACK.
                // Ordinary wrong/excess parts recover only from fresh complete
                // observations in state 2, never from elapsed clocks alone.
                if(I_menu_ack && O_overrun && process_state==0 && !targets_event && !I_detection_fault && recovery_count>=RECOVERY_PUBLICATIONS) begin
                    if(O_overrun_mask[0] && screw_count_bcd>screw_target_bcd) screw_count_bcd<=screw_target_bcd;
                    if(O_overrun_mask[1] && washer_count_bcd>washer_target_bcd) washer_count_bcd<=washer_target_bcd;
                    if(O_overrun_mask[2] && hex_count_bcd>hex_target_bcd) hex_count_bcd<=hex_target_bcd;
                    if(O_overrun_mask[3] && square_count_bcd>square_target_bcd) square_count_bcd<=square_target_bcd;
                    O_overrun<=0;O_overrun_mask<=0;recovery_count<=0;manual_fault<=0;O_done<=quotas_met;
                end
                if(targets_event) begin
                    if(process_state!=0) begin O_overrun<=1;O_overrun_mask<=4'b1111;O_done<=0;manual_fault<=1;recovery_count<=0;end
                    else begin
                        observation<=I_targets;process_index<=0;process_state<=1;seen_slots<=0;
                        pending_fault<=I_detection_fault ? 4'b1111:4'b0000;
                        pending_manual<=I_detection_fault;
                    end
                end else case(process_state)
                    1:begin
                        if(observed) begin
                            if(seen_slots[slot] || !known_class) begin pending_fault<=pending_fault|class_mask;pending_manual<=1;end
                            else begin
                                if(current[55] && !class_requested && !O_wait_clear && (I_count_active || O_done || O_overrun))
                                    pending_fault<=pending_fault|class_mask;
                                seen_slots[slot]<=1;missing[slot]<=0;known[slot]<=1;generation[slot]<=current[47:46];
                                if(new_identity) begin
                                    armed[slot]<=centre_x<=LINE_X-LINE_HYST && !O_wait_clear;
                                    counted[slot]<=O_wait_clear || centre_x>LINE_X-LINE_HYST;
                                    if(centre_x>LINE_X-LINE_HYST && !O_wait_clear && (I_count_active || O_done || O_overrun)) begin pending_fault<=pending_fault|class_mask;pending_manual<=1;end
                                end else if(!counted[slot] && centre_x<=LINE_X-LINE_HYST) armed[slot]<=1;
                                if(crossing) begin
                                    counted[slot]<=1;armed[slot]<=0;
                                    case(current[54:52])
                                        1:begin screw_count_bcd<=bcd_inc(screw_count_bcd);screw_total_bcd<=bcd_inc(screw_total_bcd);
                                            if(screw_total_bcd==12'h099) begin pending_fault<=pending_fault|4'b0001;pending_manual<=1;end end
                                        2:begin washer_count_bcd<=bcd_inc(washer_count_bcd);washer_total_bcd<=bcd_inc(washer_total_bcd);
                                            if(washer_total_bcd==12'h099) begin pending_fault<=pending_fault|4'b0010;pending_manual<=1;end end
                                        3:begin hex_count_bcd<=bcd_inc(hex_count_bcd);hex_total_bcd<=bcd_inc(hex_total_bcd);
                                            if(hex_total_bcd==12'h099) begin pending_fault<=pending_fault|4'b0100;pending_manual<=1;end end
                                        4:begin square_count_bcd<=bcd_inc(square_count_bcd);square_total_bcd<=bcd_inc(square_total_bcd);
                                            if(square_total_bcd==12'h099) begin pending_fault<=pending_fault|4'b1000;pending_manual<=1;end end
                                    endcase
                                end else if(current[55] && centre_x>=LINE_X+LINE_HYST &&
                                    (new_identity || (!armed[slot] && !counted[slot])) && !O_wait_clear &&
                                    (I_count_active || O_done || O_overrun))
                                    // Never invent a count for an object first seen downstream.
                                    begin pending_fault<=pending_fault|class_mask;pending_manual<=1;end
                            end
                        end
                        if(process_index==3) process_state<=2;else process_index<=process_index+1'b1;
                    end
                    2:begin
                        process_state<=0;
                        for(k=0;k<4;k=k+1) if(!seen_slots[k] && known[k]) begin
                            if(missing[k]>=2) begin known[k]<=0;armed[k]<=0;counted[k]<=0;missing[k]<=0;end
                            else missing[k]<=missing[k]+1'b1;
                        end
                        if(O_wait_clear && !any_observed) O_wait_clear<=0;
                        if(|pending_fault || |overrun_now) begin
                            O_overrun<=1;O_overrun_mask<=O_overrun_mask|pending_fault|overrun_now;
                            O_done<=0;recovery_count<=0;
                            manual_fault<=manual_fault|pending_manual;
                        end else if(!O_overrun) O_done<=quotas_met && !O_wait_clear;
                        if(O_overrun) begin
                            if((present_class_mask&O_overrun_mask)==0 && pending_fault==0 && !I_detection_fault) begin
                                if(recovery_count<RECOVERY_PUBLICATIONS) recovery_count<=recovery_count+1'b1;
                                if(!manual_fault && !pending_manual && (overrun_now&~O_overrun_mask)==0 && recovery_count>=RECOVERY_PUBLICATIONS-1) begin
                                    if(O_overrun_mask[0] && screw_count_bcd>screw_target_bcd) screw_count_bcd<=screw_target_bcd;
                                    if(O_overrun_mask[1] && washer_count_bcd>washer_target_bcd) washer_count_bcd<=washer_target_bcd;
                                    if(O_overrun_mask[2] && hex_count_bcd>hex_target_bcd) hex_count_bcd<=hex_target_bcd;
                                    if(O_overrun_mask[3] && square_count_bcd>square_target_bcd) square_count_bcd<=square_target_bcd;
                                    O_overrun<=0;O_overrun_mask<=0;recovery_count<=0;O_done<=quotas_met;
                                end
                            end else recovery_count<=0;
                        end
                    end
                    default:;
                endcase
            end
        end
    end

endmodule
