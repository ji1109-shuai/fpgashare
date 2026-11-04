

module video_in #(
    parameter DEBUG_CAPTURE=0,
    parameter FRAME_WORDS=172800
) (
    input wire         I_rst_n,

    input wire         I_camera_clk,
    input wire         I_camera_frame_start,
    input wire         I_camera_valid,
    input wire[127:0]  I_camera_data,
    input wire         I_mipi_rx_error,

    input wire         I_ddr_clk,

    input wire         I_display_pause,
    input wire         I_video_out_rd_busy,
    output wire        O_video_in_wr_busy,
    output reg[1:0]    O_video_out_rp,     ///读指针

    output reg         O_ddr_user_wr_en,
    output reg[24:0]   O_ddr_user_addr,
    output wire[127:0] O_ddr_user_wr_data,
    input wire         I_ddr_user_ready
);

    wire        S_fifo_rst;
    reg         S_camera_frame_start_extend; ///脉冲展宽，同步到ddr_clk时钟域
    reg[3:0]    S_extend_cnt;
    reg         S_camera_frame_start_extend_1d;
    reg         S_camera_frame_start_extend_2d;
    reg         S_camera_frame_start_extend_3d;
    wire        S_frame_start;
    reg[1:0]    S_video_in_wp;       ///写指针
    wire[8:0]   S_fifo_rd_num;      
    wire        S_fifo_rd_en;   
    wire        S_fifo_rd_valid;
    wire[127:0] S_fifo_rd_data; 
    reg         S_ddr_wr_valid;
    reg[9:0]    S_ddr_wr_cnt;
    wire S_fifo_full,S_fifo_empty;
    wire [8:0] S_fifo_wr_num;

    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;


    assign S_fifo_rst = S_camera_frame_start_extend_3d;

    assign O_video_in_wr_busy = S_ddr_wr_valid | O_ddr_user_wr_en;

    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst         ),   

        .clkw       ( I_camera_clk       ),     
        .we         ( I_camera_valid     ),
        .di         ( I_camera_data      ),
        .afull      (),
        .full_flag  ( S_fifo_full ),
        .wrusedw    ( S_fifo_wr_num ),
 
        .clkr       ( I_ddr_clk          ),
        .re         ( S_fifo_rd_en       ), 
        .dout       ( O_ddr_user_wr_data ),  
        .rdusedw    ( S_fifo_rd_num      ),
        .valid      (), 
        .empty_flag ( S_fifo_empty ),
        .aempty     ()
    );

    // Diagnostic taps only: no gating or change to the video/FIFO protocol.
    // MARK_DEBUG registers have explicit clocks so TD can assign instances.
    generate if(DEBUG_CAPTURE) begin : g_debug
        (* MARK_DEBUG="TRUE" *) reg [7:0] DBG_CAM_FLAGS;
        (* MARK_DEBUG="TRUE" *) reg [3:0] DBG_CAM_ERROR;
        (* MARK_DEBUG="TRUE" *) reg [17:0] DBG_CAM_WORDS,DBG_CAM_PREV_WORDS;
        (* MARK_DEBUG="TRUE" *) reg [8:0] DBG_CAM_FIFO_USED,DBG_CAM_FIFO_PEAK;
        reg cam_seen;
        // reset is generated in DDR domain; synchronize it for observation.
        reg cam_reset_d1,cam_reset_d2;
        always @(posedge I_camera_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                DBG_CAM_FLAGS<=0;DBG_CAM_ERROR<=0;
                DBG_CAM_WORDS<=0;DBG_CAM_PREV_WORDS<=0;
                DBG_CAM_FIFO_USED<=0;DBG_CAM_FIFO_PEAK<=0;
                cam_seen<=0;cam_reset_d1<=0;cam_reset_d2<=0;
            end else begin
                cam_reset_d1<=S_fifo_rst;cam_reset_d2<=cam_reset_d1;
                DBG_CAM_FLAGS<={4'd0,cam_reset_d2,S_fifo_full,I_camera_valid,I_camera_frame_start};
                DBG_CAM_FIFO_USED<=S_fifo_wr_num;
                if(S_fifo_wr_num>DBG_CAM_FIFO_PEAK) DBG_CAM_FIFO_PEAK<=S_fifo_wr_num;
                if(I_camera_frame_start) begin
                    if(cam_seen && DBG_CAM_WORDS!=FRAME_WORDS) DBG_CAM_ERROR[2]<=1;
                    DBG_CAM_PREV_WORDS<=DBG_CAM_WORDS;
                    DBG_CAM_WORDS<=I_camera_valid ? 18'd1 : 18'd0;
                    cam_seen<=1;
                end else if(cam_seen && I_camera_valid && DBG_CAM_WORDS!=18'h3ffff)
                    DBG_CAM_WORDS<=DBG_CAM_WORDS+1'b1;
                if(I_camera_valid && S_fifo_full) DBG_CAM_ERROR[0]<=1;
                // Delayed reset overlap is evidence, not an exact accepted-word count.
                if(I_camera_valid && cam_reset_d2) DBG_CAM_ERROR[1]<=1;
                if(cam_seen && I_camera_valid && DBG_CAM_WORDS==18'h3ffff) DBG_CAM_ERROR[3]<=1;
            end
        end
        (* MARK_DEBUG="TRUE" *) reg [7:0] DBG_DDR_FLAGS;
        (* MARK_DEBUG="TRUE" *) reg [3:0] DBG_DDR_ERROR;
        (* MARK_DEBUG="TRUE" *) reg [17:0] DBG_DDR_WORDS,DBG_DDR_PREV_WORDS;
        (* MARK_DEBUG="TRUE" *) reg [8:0] DBG_DDR_FIFO_USED;
        (* MARK_DEBUG="TRUE" *) reg [9:0] DBG_DDR_BURST_COUNT;
        reg ddr_seen;
        always @(posedge I_ddr_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                DBG_DDR_FLAGS<=0;DBG_DDR_ERROR<=0;
                DBG_DDR_WORDS<=0;DBG_DDR_PREV_WORDS<=0;
                DBG_DDR_FIFO_USED<=0;DBG_DDR_BURST_COUNT<=0;ddr_seen<=0;
            end else begin
                DBG_DDR_FLAGS<={S_fifo_empty,S_fifo_rd_en,O_ddr_user_wr_en,
                    I_ddr_user_ready,I_video_out_rd_busy,S_ddr_wr_valid,S_fifo_rst,S_frame_start};
                DBG_DDR_FIFO_USED<=S_fifo_rd_num;DBG_DDR_BURST_COUNT<=S_ddr_wr_cnt;
                if(S_frame_start) begin
                    if(ddr_seen && DBG_DDR_WORDS!=FRAME_WORDS) DBG_DDR_ERROR[2]<=1;
                    DBG_DDR_PREV_WORDS<=DBG_DDR_WORDS;
                    DBG_DDR_WORDS<=O_ddr_user_wr_en ? 18'd1 : 18'd0;ddr_seen<=1;
                end else if(ddr_seen && O_ddr_user_wr_en && DBG_DDR_WORDS!=18'h3ffff)
                    DBG_DDR_WORDS<=DBG_DDR_WORDS+1'b1;
                if(S_fifo_rd_en && S_fifo_empty) DBG_DDR_ERROR[0]<=1;
                if(S_fifo_rst && (S_ddr_wr_valid || O_ddr_user_wr_en)) DBG_DDR_ERROR[1]<=1;
                if(ddr_seen && O_ddr_user_wr_en && DBG_DDR_WORDS==18'h3ffff) DBG_DDR_ERROR[3]<=1;
            end
        end
    end endgenerate


    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_camera_frame_start_extend <= 1'b0;
        else
            if(I_camera_frame_start)
                S_camera_frame_start_extend <= 1'b1;
            else if(S_extend_cnt == 'd7)
                S_camera_frame_start_extend <= 1'b0;
            else
                S_camera_frame_start_extend <= S_camera_frame_start_extend;
    end

	
    always @ (posedge I_camera_clk) begin
    	if(S_camera_frame_start_extend)
        	S_extend_cnt <= S_extend_cnt + 'd1;
      	else
          	S_extend_cnt <= 'd0;
    end


    always @(posedge I_ddr_clk) begin
        S_camera_frame_start_extend_1d <= S_camera_frame_start_extend;
        S_camera_frame_start_extend_2d <= S_camera_frame_start_extend_1d;
        S_camera_frame_start_extend_3d <= S_camera_frame_start_extend_2d;
    end

    assign S_frame_start = ~S_camera_frame_start_extend_3d & S_camera_frame_start_extend_2d;

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_video_in_wp <= 'd0;
        else
            if(I_display_pause)
                S_video_in_wp <= S_video_in_wp;
            else if(S_frame_start)
                begin
                    if(I_mipi_rx_error)
                        S_video_in_wp <= S_video_in_wp;
                    else
                        S_video_in_wp <= S_video_in_wp + 'd1;
                end
            else
                S_video_in_wp <= S_video_in_wp;
    end


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_video_out_rp <= 'd0;
        else
            if(I_display_pause)
                O_video_out_rp <= O_video_out_rp;
            else if(S_frame_start)
                begin
                    case(S_video_in_wp)
                        'd0: O_video_out_rp <= 'd2;
                        'd1: O_video_out_rp <= 'd3;
                        'd2: O_video_out_rp <= 'd0;
                        'd3: O_video_out_rp <= 'd1;
                    endcase
                end
            else
                O_video_out_rp <= O_video_out_rp;
    end

    /*
        fifo的深度是512，实际的深度是510，因此需要注意每次读出的长度避免为256，否则连续两次读写会引起fifo读空，丢失数据
    */
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_ddr_wr_valid <= 1'b0;
        else
            if(S_ddr_wr_valid && I_ddr_user_ready && S_ddr_wr_cnt == 'd239)
                S_ddr_wr_valid <= 1'b0;
            else if(S_fifo_rd_num >= 'd240 && (!I_video_out_rd_busy) && (!S_fifo_rst))
                S_ddr_wr_valid <= 1'b1;
            else
                S_ddr_wr_valid <= S_ddr_wr_valid;
    end

    always @(posedge I_ddr_clk) begin
        if(S_ddr_wr_valid)
            begin
                if(I_ddr_user_ready)
                    S_ddr_wr_cnt <= S_ddr_wr_cnt + 'd1;
                else
                    S_ddr_wr_cnt <= S_ddr_wr_cnt;
            end
        else
            S_ddr_wr_cnt <= 'd0;
    end

    assign S_fifo_rd_en = S_ddr_wr_valid & I_ddr_user_ready;

    always @(posedge I_ddr_clk) begin
        O_ddr_user_wr_en <= S_fifo_rd_en;
    end

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_addr <= 1'b0;
        else
            if(S_frame_start && (!I_mipi_rx_error))
                begin
                    case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
			else if(S_frame_start && I_mipi_rx_error)
				begin
                	case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                    endcase
                end
            else if(O_ddr_user_wr_en)
                O_ddr_user_addr <= O_ddr_user_addr + 'd8;
            else    
                O_ddr_user_addr <= O_ddr_user_addr;
    end

    
endmodule
