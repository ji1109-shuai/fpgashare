


module video_out #(
    parameter FRAME_WORDS=172800 // 1280*720*3/16
) (
    input wire        I_rst_n,

    input wire        I_ddr_clk,
    output wire       O_video_out_rd_busy,  
    input wire        I_video_in_wr_busy,   
    input wire[1:0]   I_video_out_rp,
    output wire       O_ddr_user_rd_en,
    output reg[24:0]  O_ddr_user_addr,
    input wire        I_ddr_user_ready,
    input wire        I_ddr_user_rd_valid,
    input wire[127:0] I_ddr_user_rd_data,

    input wire        I_dsi_clk,
    input wire        I_video_vsync,
    input wire        I_video_rd_en,  
    output reg[23:0]  O_vdieo_data
);

    reg         S_fifo_rst;     
    reg[7:0]    S_fifo_rst_cnt;
    wire[8:0]   S_fifo_wr_num;       
    wire        S_fifo_rd_en;        
    wire[127:0] S_fifo_rd_data;      
    reg         S_video_vsync_1d;
    reg         S_video_vsync_2d;
    reg         S_video_vsync_3d;
    wire        S_video_frame_start;   
    wire        S_ddr_rd_trig;       
    reg         S_ddr_rd_valid;      
    reg[9:0]    S_ddr_rd_cnt;        
    reg[3:0]    S_fifo_rd_cnt;       
    reg         S_video_rd_en_1d;
    reg[3:0]    S_fifo_rd_cnt_1d;     
    reg[127:0]  S_fifo_rd_data_1d;    
	wire        S_fifo_emtpy;     



    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;


    // Track accepted read commands until their in-order DDR responses return.
    // Clearing the display FIFO alone cannot cancel requests already in DDR.
    reg [9:0] outstanding;
    reg [17:0] issued_words;
    reg frame_seen;
    reg [9:0] burst_words;
    wire [18:0] remaining_words = FRAME_WORDS - issued_words;
    wire [10:0] reserved_words = {2'b0,S_fifo_wr_num} + {1'b0,outstanding};
    wire fifo_write = I_ddr_user_rd_valid && frame_seen &&
                      !S_fifo_rst && !S_video_frame_start;

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_vsync_1d<=0;S_video_vsync_2d<=0;S_video_vsync_3d<=0;
        end else begin
            S_video_vsync_1d<=I_video_vsync;
            S_video_vsync_2d<=S_video_vsync_1d;
            S_video_vsync_3d<=S_video_vsync_2d;
        end
    end
    assign S_video_frame_start = ~S_video_vsync_3d & S_video_vsync_2d;

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) outstanding<=0;
        else case({O_ddr_user_rd_en,I_ddr_user_rd_valid})
            2'b10: outstanding<=outstanding+1'b1;
            2'b01: if(outstanding!=0) outstanding<=outstanding-1'b1;
            default: outstanding<=outstanding;
        endcase
    end

    // At VSYNC cancel the unissued part of the burst; drain/discard all old
    // responses while holding FIFO reset. Start the new bank only afterwards.
    // Retain the original >=11 DDR-clock reset pulse for the async FIFO.
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_fifo_rst<=1;S_fifo_rst_cnt<=0;frame_seen<=0;
        end else if(S_video_frame_start) begin
            S_fifo_rst<=1;S_fifo_rst_cnt<=0;frame_seen<=1;
        end else if(S_fifo_rst) begin
            if(outstanding!=0 || I_ddr_user_rd_valid) S_fifo_rst_cnt<=0;
            else if(S_fifo_rst_cnt==10) S_fifo_rst<=0;
            else S_fifo_rst_cnt<=S_fifo_rst_cnt+1'b1;
        end
    end

    // Reserve FIFO space for both returned words AND every pending response.
    // Keep 300 slots free before starting a <=240-word burst (60-word margin).
    // Do not prefetch beyond the frame during the vertical blanking interval.
    assign S_ddr_rd_trig = reserved_words<=211 && issued_words<FRAME_WORDS &&
        frame_seen && !I_video_in_wr_busy && !S_ddr_rd_valid &&
        !S_fifo_rst && !S_video_frame_start && I_rst_n;

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_ddr_rd_valid<=0;S_ddr_rd_cnt<=0;burst_words<=240;issued_words<=0;
        end else if(S_video_frame_start) begin
            S_ddr_rd_valid<=0;S_ddr_rd_cnt<=0;issued_words<=0;
        end else begin
            if(S_ddr_rd_trig) begin
                S_ddr_rd_valid<=1;S_ddr_rd_cnt<=0;
                burst_words<=remaining_words>=240 ? 10'd240 : remaining_words[9:0];
            end
            if(O_ddr_user_rd_en) begin
                issued_words<=issued_words+1'b1;
                if(S_ddr_rd_cnt==burst_words-1'b1) begin
                    S_ddr_rd_valid<=0;S_ddr_rd_cnt<=0;
                end else S_ddr_rd_cnt<=S_ddr_rd_cnt+1'b1;
            end
        end
    end
    assign O_ddr_user_rd_en = S_ddr_rd_valid && I_ddr_user_ready &&
                             !S_video_frame_start && !S_fifo_rst && I_rst_n;
    assign O_video_out_rd_busy = S_ddr_rd_trig | S_ddr_rd_valid;

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) O_ddr_user_addr<=0;
        else if(S_video_frame_start) begin
            case(I_video_out_rp)
                0: O_ddr_user_addr<=IMAGE_BASE_ADDR_0;
                1: O_ddr_user_addr<=IMAGE_BASE_ADDR_1;
                2: O_ddr_user_addr<=IMAGE_BASE_ADDR_2;
                3: O_ddr_user_addr<=IMAGE_BASE_ADDR_3;
            endcase
        end else if(O_ddr_user_rd_en) O_ddr_user_addr<=O_ddr_user_addr+8;
    end

    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst          ),   

        .clkw       ( I_ddr_clk           ),     
        .we         ( fifo_write          ),
        .di         ( I_ddr_user_rd_data  ),
        .wrusedw    ( S_fifo_wr_num       ),
        .afull      (),
        .full_flag  (),
 
        .clkr       ( I_dsi_clk           ),
        .re         ( S_fifo_rd_en        ), 
        .dout       ( S_fifo_rd_data      ),  
        .rdusedw    (), 
        .valid      (),  
        .empty_flag ( S_fifo_emtpy        ),
        .aempty     ()
    );


   always @(posedge I_dsi_clk) begin
       if(I_video_rd_en)
           S_fifo_rd_cnt <= S_fifo_rd_cnt + 'd1;
       else
           S_fifo_rd_cnt <= 'd0;
   end

   assign S_fifo_rd_en = I_video_rd_en && (S_fifo_rd_cnt == 'd0)  ? 1'b1 :
                         I_video_rd_en && (S_fifo_rd_cnt == 'd5)  ? 1'b1 :
                         I_video_rd_en && (S_fifo_rd_cnt == 'd10) ? 1'b1 : 1'b0;

   always @(posedge I_dsi_clk) begin
       S_video_rd_en_1d  <= I_video_rd_en;
       S_fifo_rd_cnt_1d  <= S_fifo_rd_cnt;
       S_fifo_rd_data_1d <= S_fifo_rd_data;
   end

   always @(posedge I_dsi_clk) begin
       if(S_video_rd_en_1d)
           begin
               case(S_fifo_rd_cnt_1d)
                   'd0: O_vdieo_data  <= S_fifo_rd_data[127:104];
                   'd1: O_vdieo_data  <= S_fifo_rd_data[103:80];
                   'd2: O_vdieo_data  <= S_fifo_rd_data[79:56];
                   'd3: O_vdieo_data  <= S_fifo_rd_data[55:32];
                   'd4: O_vdieo_data  <= S_fifo_rd_data[31:8];
                   'd5: O_vdieo_data  <= {S_fifo_rd_data_1d[7:0],S_fifo_rd_data[127:112]};
                   'd6: O_vdieo_data  <= S_fifo_rd_data[111:88];
                   'd7: O_vdieo_data  <= S_fifo_rd_data[87:64];
                   'd8: O_vdieo_data  <= S_fifo_rd_data[63:40];
                   'd9: O_vdieo_data  <= S_fifo_rd_data[39:16];
                   'd10: O_vdieo_data <= {S_fifo_rd_data_1d[15:0],S_fifo_rd_data[127:120]};
                   'd11: O_vdieo_data <= S_fifo_rd_data[119:96];
                   'd12: O_vdieo_data <= S_fifo_rd_data[95:72];
                   'd13: O_vdieo_data <= S_fifo_rd_data[71:48];
                   'd14: O_vdieo_data <= S_fifo_rd_data[47:24];
                   'd15: O_vdieo_data <= S_fifo_rd_data[23:0];
               endcase
           end
       else
           O_vdieo_data <= 'd0;
   end

    
endmodule
