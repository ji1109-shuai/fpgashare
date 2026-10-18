`timescale 1ns / 1ps
// One pixel per four valid beats, two independently owned histogram banks.
// RAM is cleared after reset and as bins are consumed. Frames arriving before
// initialization, or while both banks are occupied, are skipped in full.
// Exact Otsu comparison: (S*w - s*N)^2 / (w*(N-w)); N is the actual count.
// Cross multiplication preserves ties without quantizing class means. The
// shared multiplier uses a 16-bit carry chain, avoiding a long DSP cascade.
module img_otsu #(
    parameter BEATS_PER_LINE = 320,
    parameter LINES_PER_FRAME = 720,
    // 显著性门限：最优切分的两类均值差 |Δμ| ≥ MIN_DMU 才发布阈值。
    // 0=关闭（回归默认）。无目标/单峰场景 Otsu 会切噪声，此门限使其保持上帧阈值。
    parameter MIN_DMU = 0
)(
    input I_clk,
    input I_rst_n,
    input [95:0] I_tdata,
    input I_tvalid,
    input I_tuser,
    input I_tlast,
    output reg [7:0] O_threshold,
    output reg O_upd
);
    localparam MAX_SAMPLES = (BEATS_PER_LINE * LINES_PER_FRAME + 3) / 4;
    localparam CW = (MAX_SAMPLES < 2) ? 1 : $clog2(MAX_SAMPLES + 1);
    localparam SW = CW + 8;
    localparam DW = SW + CW;
    localparam NW = 2 * DW;
    localparam QW = 2 * CW;
    localparam MW = ((NW + QW + 15) / 16) * 16;
    localparam LIMBS = MW / 16;

    localparam S_IDLE = 0, S_DRAIN = 1, S_READ = 2, S_GET = 3,
               S_ACC = 4, S_PREP = 5, S_DELTA = 6,
               S_SQUARE = 7, S_SQUARE_WAIT = 8,
               S_LEFT = 9, S_LEFT_WAIT = 10,
               S_RIGHT = 11, S_RIGHT_WAIT = 12,
               S_COMPARE = 13, S_NEXT = 14, S_DONE = 15,
               S_FIN0 = 16, S_FIN1 = 17;
    reg [4:0] st;
    reg initializing;
    reg [7:0] clear_addr;
    reg [1:0] bank_free, bank_full;
    reg capture_active, capture_bank, fsm_bank;
    reg [1:0] sample_div;
    reg pending_sof;
    reg [31:0] line_idx;
    reg [CW-1:0] run_w, full_w_a, full_w_b;
    reg [SW-1:0] run_s, full_s_a, full_s_b;

    wire [9:0] gray_sum = {2'b0, I_tdata[23:16]} +
                         {1'b0, I_tdata[15:8], 1'b0} +
                         {2'b0, I_tdata[7:0]};
    // End AWB/gray conversion before the histogram's distributed RAM read.
    // Delay all markers, including an early SOF on an invalid beat, together.
    // Only this statistics branch gains latency; video timing is untouched.
    reg [7:0] gray;
    reg hist_valid,hist_user,hist_last;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin gray<=0;hist_valid<=0;hist_user<=0;hist_last<=0;end
        else begin
            gray<=gray_sum[9:2];hist_valid<=I_tvalid;hist_user<=I_tuser;hist_last<=I_tlast;
        end
    end
    wire sof = hist_valid && (hist_user || pending_sof);
    wire free_bank = bank_free[0] ? 1'b0 : 1'b1;
    wire sample_bank = sof ? free_bank : capture_bank;
    wire sample_en = !initializing && hist_valid &&
                     (sof ? (|bank_free) :
                     (capture_active && sample_div == 0 && run_w < MAX_SAMPLES));
    wire eof = hist_valid && hist_last &&
               ((sof ? 32'd0 : line_idx) == LINES_PER_FRAME - 1);
    wire [CW-1:0] frame_w = sof ? {{(CW-1){1'b0}}, sample_en} :
                                run_w + sample_en;
    wire [SW-1:0] frame_s = (sof ? {SW{1'b0}} : run_s) +
                            (sample_en ? {{CW{1'b0}}, gray} : {SW{1'b0}});
    wire take_frame = !initializing && st == S_IDLE && (|bank_full);
    wire take_bank = bank_full[0] ? 1'b0 : 1'b1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            initializing <= 1'b1;
            clear_addr <= 0;
            bank_free <= 0;
            bank_full <= 0;
            capture_active <= 0;
            capture_bank <= 0;
            sample_div <= 0;
            pending_sof <= 0;
            line_idx <= 0;
            run_w <= 0; run_s <= 0;
            full_w_a <= 0; full_w_b <= 0;
            full_s_a <= 0; full_s_b <= 0;
        end else if (initializing) begin
            if (clear_addr == 255) begin
                initializing <= 0;
                bank_free <= 2'b11;
            end else clear_addr <= clear_addr + 1'b1;
        end else begin
            if (sof) pending_sof <= 0;
            else if (hist_user) pending_sof <= 1;

            if (take_frame) bank_full[take_bank] <= 0;
            if (st == S_DONE) bank_free[fsm_bank] <= 1;

            if (sof) begin
                // Close a partial frame using its actual sample count.
                if (capture_active) begin
                    bank_full[capture_bank] <= 1;
                    if (capture_bank) begin
                        full_w_b <= run_w; full_s_b <= run_s;
                    end else begin
                        full_w_a <= run_w; full_s_a <= run_s;
                    end
                end
                capture_active <= |bank_free;
                capture_bank <= free_bank;
                if (|bank_free) bank_free[free_bank] <= 0;
                sample_div <= 1;
                line_idx <= hist_last ? 1 : 0;
                run_w <= frame_w;
                run_s <= frame_s;
            end else if (hist_valid) begin
                sample_div <= sample_div + 1'b1;
                if (hist_last) line_idx <= line_idx + 1'b1;
                if (sample_en) begin
                    run_w <= frame_w;
                    run_s <= frame_s;
                end
            end

            if (eof && (sof ? (|bank_free) : capture_active)) begin
                capture_active <= 0;
                bank_full[sample_bank] <= 1;
                if (sample_bank) begin
                    full_w_b <= frame_w; full_s_b <= frame_s;
                end else begin
                    full_w_a <= frame_w; full_s_a <= frame_s;
                end
            end
        end
    end

    reg [CW-1:0] hist_a [0:255];
    reg [CW-1:0] hist_b [0:255];
    reg [CW-1:0] rd_a, rd_b;
    reg rmw_valid, rmw_bank;
    reg [7:0] rmw_addr, bin_idx;
    wire [CW-1:0] bin_value = fsm_bank ? rd_b : rd_a;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rmw_valid <= 0; rmw_bank <= 0; rmw_addr <= 0;
        end else begin
            rmw_valid <= sample_en;
            if (sample_en) begin
                rmw_bank <= sample_bank;
                rmw_addr <= gray;
            end
        end
    end

    // Each bank has one synchronous read and one write port. Ownership
    // prevents sampling and scan/clear from addressing the same bank.
    always @(posedge I_clk) begin
        if (sample_en && !sample_bank) rd_a <= hist_a[gray];
        else if (st == S_READ && !fsm_bank) rd_a <= hist_a[bin_idx];
        if (sample_en && sample_bank) rd_b <= hist_b[gray];
        else if (st == S_READ && fsm_bank) rd_b <= hist_b[bin_idx];

        if (initializing) begin
            hist_a[clear_addr] <= 0;
            hist_b[clear_addr] <= 0;
        end else begin
            if (rmw_valid && !rmw_bank) hist_a[rmw_addr] <= rd_a + 1'b1;
            else if (st == S_GET && !fsm_bank) hist_a[bin_idx] <= 0;
            if (rmw_valid && rmw_bank) hist_b[rmw_addr] <= rd_b + 1'b1;
            else if (st == S_GET && fsm_bank) hist_b[bin_idx] <= 0;
        end
    end

    reg [CW-1:0] total_w, cum_w, bin_w, upper_w;
    reg [SW-1:0] total_s, cum_s, bin_s;
    reg [DW-1:0] product_l, product_r, delta;
    reg [NW-1:0] candidate_num, best_num;
    reg [QW-1:0] candidate_den, best_den;
    reg [7:0] best_t;
    reg        delta_neg;              // 候选 delta 的符号
    reg [DW-1:0] delta_abs;            // 候选 |delta|
    reg [DW-1:0] best_delta_abs;       // 最优候选的 |delta|
    reg        best_delta_neg;
    reg [CW-1:0] best_w0, best_w1;     // 最优候选的类0/类1样本计数
    reg [MW-1:0] compare_l, compare_r;
    reg [7:0] compare_count;
    // 显著性门限 MIN_DMU·w0·w1 两级寄存（S_FIN0/S_FIN1），
    // 原 S_DONE 组合乘法链是全设计最差建立路径（+0.003ns）
    reg [DW-1:0] dmu_p0, dmu_bound;

    reg mul_start, mul_busy, mul_done, mul_carry;
    reg [MW-1:0] mul_a, mul_shift, mul_acc;
    reg [DW-1:0] mul_b, mul_factor;
    reg [7:0] mul_limb;
    wire [16:0] mul_sum = {1'b0, mul_acc[15:0]} +
                         (mul_factor[0] ? {1'b0, mul_shift[15:0]} : 17'd0) +
                         mul_carry;
    wire [MW-1:0] rotated_a = {mul_shift[15:0], mul_shift[MW-1:16]};

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            mul_busy <= 0; mul_done <= 0; mul_carry <= 0;
            mul_shift <= 0; mul_acc <= 0; mul_factor <= 0; mul_limb <= 0;
        end else begin
            mul_done <= 0;
            if (mul_start) begin
                mul_busy <= 1; mul_carry <= 0; mul_limb <= 0;
                mul_shift <= mul_a; mul_factor <= mul_b; mul_acc <= 0;
            end else if (mul_busy) begin
                mul_acc <= {mul_sum[15:0], mul_acc[MW-1:16]};
                if (mul_limb == LIMBS - 1) begin
                    mul_limb <= 0;
                    mul_carry <= 0;
                    mul_shift <= rotated_a << 1;
                    mul_factor <= mul_factor >> 1;
                    if ((mul_factor >> 1) == 0) begin
                        mul_busy <= 0;
                        mul_done <= 1;
                    end
                end else begin
                    mul_limb <= mul_limb + 1'b1;
                    mul_carry <= mul_sum[16];
                    mul_shift <= rotated_a;
                end
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            st <= S_IDLE; fsm_bank <= 0; bin_idx <= 0;
            total_w <= 0; total_s <= 0; cum_w <= 0; cum_s <= 0;
            bin_w <= 0; bin_s <= 0; upper_w <= 0;
            product_l <= 0; product_r <= 0; delta <= 0;
            candidate_num <= 0; candidate_den <= 0;
            best_num <= 0; best_den <= 0; best_t <= 0;
            best_delta_abs <= 0; best_delta_neg <= 1'b0;
            best_w0 <= 0; best_w1 <= 0;
            delta_abs <= 0; delta_neg <= 1'b0;
            compare_l <= 0; compare_r <= 0; compare_count <= 0;
            dmu_p0 <= 0; dmu_bound <= 0;
            mul_start <= 0; mul_a <= 0; mul_b <= 0;
            O_threshold <= 128; O_upd <= 0;
        end else begin
            mul_start <= 0;
            case (st)
            S_IDLE: if (take_frame) begin
                fsm_bank <= take_bank;
                total_w <= take_bank ? full_w_b : full_w_a;
                total_s <= take_bank ? full_s_b : full_s_a;
                cum_w <= 0; cum_s <= 0; bin_idx <= 0;
                best_num <= 0; best_den <= 0; best_t <= 0;
                st <= S_DRAIN;
            end
            S_DRAIN: st <= S_READ;
            S_READ: st <= S_GET;
            S_GET: begin
                bin_w <= bin_value;
                bin_s <= bin_value * bin_idx;
                st <= S_ACC;
            end
            S_ACC: begin
                cum_w <= cum_w + bin_w;
                cum_s <= cum_s + bin_s;
                if (bin_w != 0 && (cum_w + bin_w) < total_w) st <= S_PREP;
                else st <= S_NEXT;
            end
            S_PREP: begin
                upper_w <= total_w - cum_w;
                product_l <= total_s * cum_w;
                product_r <= cum_s * total_w;
                st <= S_DELTA;
            end
            S_DELTA: begin
                delta     <= product_l - product_r;
                delta_abs <= (product_l >= product_r) ? (product_l - product_r)
                                                      : (product_r - product_l);
                delta_neg <= (product_l < product_r);
                candidate_den <= cum_w * upper_w;
                st <= S_SQUARE;
            end
            S_SQUARE: begin
                mul_a <= {{(MW-DW){1'b0}}, delta}; mul_b <= delta;
                mul_start <= 1; st <= S_SQUARE_WAIT;
            end
            S_SQUARE_WAIT: if (mul_done) begin
                candidate_num <= mul_acc[NW-1:0];
                if (best_den == 0) begin
                    best_num <= mul_acc[NW-1:0];
                    best_den <= candidate_den; best_t <= bin_idx;
                    best_delta_abs <= delta_abs; best_delta_neg <= delta_neg;
                    best_w0 <= cum_w; best_w1 <= upper_w;
                    st <= S_NEXT;
                end else st <= S_LEFT;
            end
            S_LEFT: begin
                mul_a <= {{(MW-NW){1'b0}}, candidate_num};
                mul_b <= {{(DW-QW){1'b0}}, best_den};
                mul_start <= 1; st <= S_LEFT_WAIT;
            end
            S_LEFT_WAIT: if (mul_done) begin
                compare_l <= mul_acc; st <= S_RIGHT;
            end
            S_RIGHT: begin
                mul_a <= {{(MW-NW){1'b0}}, best_num};
                mul_b <= {{(DW-QW){1'b0}}, candidate_den};
                mul_start <= 1; st <= S_RIGHT_WAIT;
            end
            S_RIGHT_WAIT: if (mul_done) begin
                compare_r <= mul_acc; compare_count <= 0; st <= S_COMPARE;
            end
            S_COMPARE: begin
                if (compare_l[MW-1 -: 16] > compare_r[MW-1 -: 16]) begin
                    best_num <= candidate_num; best_den <= candidate_den;
                    best_t <= bin_idx; st <= S_NEXT;
                    best_delta_abs <= delta_abs; best_delta_neg <= delta_neg;
                    best_w0 <= cum_w; best_w1 <= upper_w;
                end else if (compare_l[MW-1 -: 16] < compare_r[MW-1 -: 16] ||
                             compare_count == LIMBS - 1) st <= S_NEXT;
                else begin
                    compare_l <= compare_l << 16; compare_r <= compare_r << 16;
                    compare_count <= compare_count + 1'b1;
                end
            end
            S_NEXT: begin
                if (bin_idx == 255) st <= S_FIN0;
                else begin bin_idx <= bin_idx + 1'b1; st <= S_READ; end
            end
            S_FIN0: begin
                dmu_p0 <= MIN_DMU * {8'd0, best_w0};
                st <= S_FIN1;
            end
            S_FIN1: begin
                dmu_bound <= dmu_p0 * {8'd0, best_w1};
                st <= S_DONE;
            end
            S_DONE: begin
                // Uniform frames retain T, but still signal completion.
                // 显著性门限：|Δμ| = |delta|/(w0·w1) ≥ MIN_DMU 才更新阈值；
                // 单峰/无目标场景（类均值差小）保持上一帧阈值（设计行为）。
                if (best_den != 0 &&
                    best_delta_abs >= dmu_bound)
                    O_threshold <= (best_t == 8'd255) ? 8'd255 : (best_t + 8'd1);
                O_upd <= ~O_upd;
                st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
