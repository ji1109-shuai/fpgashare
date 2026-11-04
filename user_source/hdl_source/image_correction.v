
module image_correction #(
    parameter DATA_WIDTH   = 40
)(
    input                          	  I_clk   			,
    input                          	  I_rst_n 			,

    input    [DATA_WIDTH - 1:0]       I_raw_data		,       
    input                             I_raw_valid 		,     
    input                             I_raw_frame_start	,
    input                             I_raw_frame_end  	,
    // Êä³öRAW10Êý¾Ý
    output     [DATA_WIDTH - 1:0]     O_raw_tdata 		,
    output                            O_raw_tlast 		,
    output                            O_raw_tvalid		,
    output                            O_raw_tuser 		,
    input                             O_raw_tready
);

    // uial2axis already supplies valid-qualified SOF/EOL markers. Keep the
    // original one-cycle data latency and pipeline those markers with data.
    // Never infer lines from idle-clock counts: CSI blanking is variable and
    // may exceed 256 clocks or contain gaps within an active line.
    reg [DATA_WIDTH-1:0] data_d;
    reg valid_d,sof_d,eol_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            data_d <= 0;
            valid_d <= 0;
            sof_d <= 0;
            eol_d <= 0;
        end else begin
            data_d <= I_raw_data;
            valid_d <= I_raw_valid;
            sof_d <= I_raw_valid && I_raw_frame_start;
            eol_d <= I_raw_valid && I_raw_frame_end;
        end
    end
    assign O_raw_tdata = data_d;
    assign O_raw_tvalid = valid_d;
    assign O_raw_tuser = sof_d;
    assign O_raw_tlast = eol_d;
endmodule
