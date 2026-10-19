`timescale 1ns/1ps
// Exercise the real ISP wiring after AWB. Camera/debayer vendor blocks are
// stubs; AWB output is driven explicitly with its observed early SOF timing.
module tb_isp_threshold;
    reg clk=0, rst_n=0;
    reg [95:0] rgb=0;
    reg valid=0, early_user=0;
    wire [7:0] applied;
    wire applied_upd;
    integer r,b,k,frames=0,lines=0,beats=0;
    reg [7:0] want_threshold=128;
    reg was_valid, was_sof, was_eol;
    reg [7:0] was_gray;
    reg upd_d=0;
    isp_top dut(.axi4s_video_aclk(clk), .I_rst_n(rst_n),
        .I_tlast(1'b0), .I_tuser(1'b0), .I_tdata(40'd0), .I_tvalid(1'b0),
        .I_tdest(10'd0), .O_tready(1'b1), .I_bin_en(1'b1),
        .I_morph_mode(2'b00), .I_awb_freeze(1'b1),
        .O_thresh_val(applied), .O_thresh_upd(applied_upd));
    always #5 clk=~clk;
    task begin_frame;
        input integer coincident;
        begin
            @(negedge clk); early_user=1; valid=0;
            if (!coincident) begin
                @(negedge clk); early_user=0;
                repeat (7) @(negedge clk);
            end
        end
    endtask
    always @(posedge clk) if (rst_n) begin
        was_valid=valid; was_sof=dut.awb_sof; was_eol=dut.awb_eol;
        was_gray=rgb[7:0];
        if (was_sof) begin frames=frames+1; beats=0; end
        if (was_valid) begin
            if (was_eol !== (beats % 320 == 319)) $fatal(1,"EOL misaligned beat=%0d",beats);
            if (was_eol) lines=lines+1;
            beats=beats+1;
        end
        #1;
        if (dut.bin_O_tvalid !== was_valid || dut.bin_O_tuser !== was_sof || dut.bin_O_tlast !== was_eol)
            $fatal(1,"binary sidebands lost alignment");
        if (was_valid && dut.bin_O_tdata !== ((was_gray >= want_threshold) ? {96{1'b1}} : 96'd0))
            $fatal(1,"frame threshold incorrect");
        if (applied !== want_threshold || applied !== dut.u_img_binarize.thresh_r)
            $fatal(1,"OSD threshold is undriven, stale, or differs from binarizer");
        if ((applied_upd !== upd_d) !== was_sof) $fatal(1,"OSD update must follow frame application");
        upd_d=applied_upd;
    end
    initial begin
        force dut.awb_O_tdata=rgb;
        force dut.awb_O_tvalid=valid;
        force dut.awb_O_tuser=early_user;
        force dut.awb_O_tlast=1'b0;
        #12; rst_n=1;
        repeat (270) @(negedge clk);
        begin_frame(0);
        for(r=0;r<720;r=r+1) begin
            for(b=0;b<320;b=b+1) begin
                @(negedge clk); valid=1; rgb={12{(b<160 ? 8'd32 : 8'd224)}};
            end
            @(negedge clk); valid=0;
            repeat (4) @(negedge clk);
        end
        k=0;
        while(dut.otsu_thresh !== 8'd33 && k<230400) begin @(negedge clk); k=k+1; end
        if(dut.otsu_thresh !== 8'd33) $fatal(1,"Otsu did not publish 33");
        if(applied !== 8'd128) $fatal(1,"pending result appeared as applied threshold");
        begin_frame(1);
        valid=1; rgb={12{8'd80}}; want_threshold=33;
        @(negedge clk); early_user=0;
        for(b=1;b<640;b=b+1) @(negedge clk);
        valid=0;
        repeat (10) @(negedge clk);
        if(frames!=2 || lines!=722) $fatal(1,"frame/line count mismatch %0d %0d",frames,lines);
        $display("ALL PASS: ISP early/coincident SOF, 320-beat EOL, Otsu->binary->OSD wiring");
        $finish;
    end
    initial begin #10000000; $fatal(1,"timeout"); end
endmodule

module demosaic #(parameter IMG_HEIGHT=720, IMG_WIDTH=1280,
    data_complete_delay=50, BAYER_MODE="BGGR")(
    input I_clk, I_rst_n, input [39:0] axi4s_video_tdata,
    input [9:0] axi4s_video_tdest,
    input axi4s_video_tlast, axi4s_video_tvalid, axi4s_video_tuser,
    output axi4s_video_tready, O_tlast, O_tuser, O_tvalid,
    output [127:0] O_tdata, input O_tready);
    assign axi4s_video_tready=1;
    assign O_tlast=0; assign O_tuser=0; assign O_tvalid=0; assign O_tdata=0;
endmodule
module awb #(parameter IMG_HEIGHT=720, IMG_WIDTH=1280,REFERENCE_ONLY=0,REFERENCE_WINDOW=0,DIAGNOSTICS=0,MIN_REFERENCE_SAMPLES=128,AUTO_REFERENCE=0)(
    input I_clk,I_rst_n,I_tlast,I_tuser,I_tvalid,I_gain_freeze,
    input [95:0] I_tdata, output I_tready,
    output O_tlast,O_tuser,O_tvalid, output [95:0] O_tdata, input O_tready,
    input I_cal_reset,output [31:0] O_reference,output O_reference_upd,
    output [127:0] O_diagnostics,output O_diagnostics_upd);
    assign I_tready=1;
    assign O_tlast=0; assign O_tuser=0; assign O_tvalid=0; assign O_tdata=0;
    assign O_reference=0;assign O_reference_upd=0;
    assign O_diagnostics=0;assign O_diagnostics_upd=0;
endmodule
