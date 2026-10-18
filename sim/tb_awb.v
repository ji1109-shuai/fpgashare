`timescale 1ns/1ps
// AWB 帧间增益架构回归（2026-10-11）
//  1) 偏色均匀帧：增益收敛到 G/R、G/B，输出 R≈G≈B
//  2) 帧内增益恒定：同一帧所有输出像素完全相同（旧版帧内逐拍变化）
//  3) 冻结：I_gain_freeze=1 时换场景，增益保持
//  4) 钳位：极端偏色时增益限制在 4.0
//  5) 时序：每行 320 个有效输出拍、像素位置不变（逐拍对比延迟后的输入）
module tb_awb;
    localparam W4 = 320, H = 16;
    reg clk = 0, rst_n = 0;
    reg [95:0] din = 0;
    reg vin = 0, uin = 0, freeze = 0;
    wire [95:0] dout;
    wire vout, uout, lout;
    always #5 clk = ~clk;

    awb #(.IMG_HEIGHT(H), .IMG_WIDTH(W4*4)) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(1'b0), .I_tuser(uin), .I_tdata(din), .I_tvalid(vin),
        .I_gain_freeze(freeze), .I_tready(),
        .O_tlast(lout), .O_tuser(uout), .O_tdata(dout), .O_tvalid(vout),
        .O_tready(1'b1));

    // 输出检查：记录当前帧第一个输出像素，后续像素必须完全一致
    integer out_beats = 0, line_beats = 0, errors = 0;
    reg [23:0] first_px;
    reg        have_first = 0;
    reg        check_uniform = 1;
    always @(posedge clk) if (rst_n && vout) begin
        if (!have_first) begin first_px = dout[23:0]; have_first = 1; end
        if (check_uniform && dout !== {4{first_px}}) begin
            if (errors < 5) $display("ERR non-uniform beat %0d: %h vs %h", out_beats, dout, {4{first_px}});
            errors = errors + 1;
        end
        out_beats = out_beats + 1;
    end
    // 每行恰好 320 拍（行尾 = valid 下降沿前一拍）
    always @(posedge clk) if (rst_n) begin
        if (vout) line_beats = line_beats + 1;
        if (lout) begin
            if (line_beats != W4) begin
                $display("ERR line length %0d", line_beats); errors = errors + 1;
            end
            line_beats = 0;
        end
    end

    task send_frame;
        input [7:0] r, g, b;
        integer y, x;
        begin
            @(negedge clk); uin = 1;
            @(negedge clk); uin = 0;
            repeat (8) @(negedge clk);
            have_first = 0; out_beats = 0;
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W4; x = x + 1) begin
                    @(negedge clk); vin = 1; din = {4{r, g, b}};
                end
                @(negedge clk); vin = 0;
                repeat (80) @(negedge clk);
            end
            repeat (200) @(negedge clk);
            if (out_beats != W4*H) begin
                $display("ERR frame beats %0d", out_beats); errors = errors + 1;
            end
        end
    endtask

    function integer absdiff; input integer a, b;
        absdiff = (a > b) ? a - b : b - a;
    endfunction

    integer i;
    initial begin
        #23 rst_n = 1;
        repeat (10) @(negedge clk);

        // 1) R=100 G=150 B=200：目标 G/R=1.5、G/B=0.75 → 输出约 150/150/150
        for (i = 0; i < 40; i = i + 1) send_frame(8'd100, 8'd150, 8'd200);
        $display("converged px = R%0d G%0d B%0d  gainR=%h gainB=%h",
                 first_px[23:16], first_px[15:8], first_px[7:0],
                 dut.in_r_r1, dut.in_b_r1);
        if (absdiff(first_px[23:16], 150) > 1 || absdiff(first_px[7:0], 150) > 1) begin
            $display("ERR AWB did not converge"); errors = errors + 1;
        end

        // 3) 冻结后换成中性场景，增益必须保持（输出仍按旧增益）
        freeze = 1;
        repeat (4) @(negedge clk);
        for (i = 0; i < 6; i = i + 1) send_frame(8'd100, 8'd100, 8'd100);
        $display("frozen    px = R%0d G%0d B%0d", first_px[23:16], first_px[15:8], first_px[7:0]);
        if (absdiff(first_px[23:16], 150) > 1 || absdiff(first_px[7:0], 75) > 1) begin
            $display("ERR freeze did not hold gains"); errors = errors + 1;
        end
        freeze = 0;

        // 4) R=20 G=200：G/R=10 → 钳位 4.0 → R=80；B=200 → G/B=1.0
        for (i = 0; i < 40; i = i + 1) send_frame(8'd20, 8'd200, 8'd200);
        $display("clamped   px = R%0d G%0d B%0d gainR=%h", first_px[23:16], first_px[15:8],
                 first_px[7:0], dut.in_r_r1);
        if (absdiff(first_px[23:16], 80) > 1 || absdiff(first_px[7:0], 200) > 1) begin
            $display("ERR clamp"); errors = errors + 1;
        end

        if (errors == 0) $display("=== ALL PASS ===");
        else             $display("FAIL errors=%0d", errors);
        $finish;
    end
endmodule

// 仿真替身：AWB 行延迟 RAM（真实 IP 为 PH1P ERAM，NOREG 同步读）
module blk_mem_gen_awb_delay_signal (
    output [95:0] doa, input [95:0] dia, input [10:0] addra, input wea, input clka,
    output reg [95:0] dob, input [10:0] addrb, input clkb, input [95:0] dib, input web);
    reg [95:0] mem [0:2047];
    assign doa = 96'd0;
    always @(posedge clka) if (wea) mem[addra] <= dia;
    always @(posedge clkb) dob <= mem[addrb];
endmodule
