

module data_96bit_to_128bit (
    input wire        I_clk,
    input wire        I_rst_n,
   
    input wire        I_96b_frame_start,
    input wire        I_96b_valid,
    input wire[95:0]  I_96b_data,
  
    output reg        O_128b_frame_start,
    output reg        O_128b_valid,
    output reg[127:0] O_128b_data
);



    // Four 96-bit beats become three 128-bit words, high byte first.
    // Partial data and phase survive invalid cycles. A new frame discards
    // any old partial word. SOF may arrive early or with the first valid beat;
    // the output SOF always accompanies the first complete output word.
    reg [95:0] previous_data;
    reg [1:0] phase;
    reg sof_pending;
    wire [1:0] phase_now = I_96b_frame_start ? 2'd0 : phase;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            previous_data <= 96'd0;
            phase <= 2'd0;
            sof_pending <= 1'b0;
            O_128b_valid <= 1'b0;
            O_128b_frame_start <= 1'b0;
            O_128b_data <= 128'd0;
        end else begin
            O_128b_valid <= 1'b0;
            O_128b_frame_start <= 1'b0;
            if (I_96b_frame_start) begin
                phase <= 2'd0;
                sof_pending <= 1'b1;
            end
            if (I_96b_valid) begin
                previous_data <= I_96b_data;
                phase <= phase_now + 2'd1;
                case (phase_now)
                    2'd0: O_128b_data <= 128'd0;
                    2'd1: O_128b_data <= {previous_data, I_96b_data[95:64]};
                    2'd2: O_128b_data <= {previous_data[63:0], I_96b_data[95:32]};
                    2'd3: O_128b_data <= {previous_data[31:0], I_96b_data};
                endcase
                if (phase_now != 2'd0) begin
                    O_128b_valid <= 1'b1;
                    O_128b_frame_start <= sof_pending;
                    sof_pending <= 1'b0;
                end
            end
        end
    end

    

endmodule







/*
module data96_128 (

    input wire [95:0] I_tdata,

    output wire [127:0] O_tdata

);

  assign O_tdata = {
    {8'd0}, I_tdata[95:72], {8'd0}, I_tdata[71:48], {8'd0}, I_tdata[47:24], {8'd0}, I_tdata[23:0]
  };
 
endmodule
*/

