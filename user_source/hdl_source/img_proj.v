`timescale 1ns / 1ps
// Single-ring measurement on the UNMODIFIED binary stream, four pixels/beat.
// Pixel 0 is I_tdata[23:0]. SOF/EOL must accompany a valid beat.
// A candidate has one connected foreground band and one enclosed hole:
// nonempty rows follow 1-run / 2-run / 1-run topology. Extra fragments fail
// closed. This is a ring-candidate check, not a general component labeller or
// a roundness/defect classifier. Dimensions are integer pixel extents.
module img_proj #(
    parameter BEATS_PER_LINE = 320,
    parameter LINES_PER_FRAME = 720,
    parameter FG_IS_WHITE = 1,
    parameter MIN_OUTER = 16,
    parameter MIN_HOLE = 4,
    parameter ASPECT_TOL = 2
)(
    input I_clk, I_rst_n,
    input [95:0] I_tdata,
    input I_tvalid, I_tuser, I_tlast,
    output reg [15:0] O_span, O_hole,
    output reg [10:0] O_center_x, O_center_y,
    output reg [10:0] O_hole_x, O_hole_y,
    output reg O_valid,
    // 0=valid candidate, 1=empty, 2=edge, 3=topology, 4=size/aspect, 5=stream
    output reg [2:0] O_status,
    output reg O_upd
);
    localparam WIDTH = BEATS_PER_LINE * 4;
    wire [3:0] bright = {|I_tdata[95:72], |I_tdata[71:48],
                         |I_tdata[47:24], |I_tdata[23:0]};
    wire [3:0] fg = FG_IS_WHITE ? bright : ~bright;
    reg active;
    reg [10:0] x, y;
    wire [10:0] cur_x = I_tuser ? 11'd0 : x;
    wire [10:0] cur_y = I_tuser ? 11'd0 : y;
    reg prev_bit;
    reg [1:0] runs;
    reg [10:0] first_x, last_x, gap_l, gap_r;
    reg [1:0] nruns;
    reg nprev;
    reg [10:0] nfirst, nlast, ngap_l, ngap_r;
    integer p;

    // At most four transitions; the run count saturates at 3 (invalid).
    always @* begin
        nruns = I_tuser ? 2'd0 : runs;
        nprev = I_tuser ? 1'b0 : prev_bit;
        nfirst = I_tuser ? 11'd0 : first_x;
        nlast = I_tuser ? 11'd0 : last_x;
        ngap_l = I_tuser ? 11'd0 : gap_l;
        ngap_r = I_tuser ? 11'd0 : gap_r;
        for (p=0; p<4; p=p+1) begin
            if (fg[p] && !nprev) begin
                if (nruns == 0) nfirst = cur_x + p;
                if (nruns == 1) ngap_r = cur_x + p - 1;
                if (nruns != 3) nruns = nruns + 1'b1;
            end
            if (!fg[p] && nprev && nruns == 1) ngap_l = cur_x + p;
            if (fg[p]) nlast = cur_x + p;
            nprev = fg[p];
        end
    end

    reg row_v, row_sof, row_eof, row_err, abort_frame;
    reg [1:0] row_runs;
    reg [10:0] row_y, row_first, row_last, row_gl, row_gr;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            active<=0; x<=0; y<=0; runs<=0; prev_bit<=0;
            first_x<=0; last_x<=0; gap_l<=0; gap_r<=0;
            row_v<=0; row_sof<=0; row_eof<=0; row_err<=0;
            row_runs<=0; row_y<=0; row_first<=0; row_last<=0;
            row_gl<=0; row_gr<=0; abort_frame<=0;
        end else begin
            row_v<=0; abort_frame<=0;
            if (I_tvalid && (I_tuser || active)) begin
                if (I_tuser) begin
                    active<=1;
                    abort_frame<=active;
                end
                if (I_tlast) begin
                    row_v<=1;
                    row_sof<=(cur_y == 0);
                    row_eof<=(cur_y == LINES_PER_FRAME-1);
                    row_err<=(cur_x != WIDTH-4);
                    row_y<=cur_y; row_runs<=nruns;
                    row_first<=nfirst; row_last<=nlast;
                    row_gl<=ngap_l; row_gr<=ngap_r;
                    x<=0; y<=cur_y+1'b1; runs<=0; prev_bit<=0;
                    if (cur_y == LINES_PER_FRAME-1) active<=0;
                end else begin
                    // Saturation preserves the bad-length indication on overrun.
                    x <= cur_x < WIDTH ? cur_x+11'd4 : cur_x;
                    y<=cur_y; runs<=nruns; prev_bit<=nprev;
                    first_x<=nfirst; last_x<=nlast;
                    gap_l<=ngap_l; gap_r<=ngap_r;
                end
            end
        end
    end

    // Row descriptors decouple pixel transitions from frame geometry.
    reg seen, ended, hole_seen, hole_done, bad_topology, border, stream_bad;
    reg [10:0] xmin,xmax,ymin,ymax,hxmin,hxmax,hymin,hymax;
    reg [10:0] max_span,max_hole;
    reg [1:0] prev_runs;
    reg [10:0] prev_first,prev_last,prev_gl,prev_gr;
    wire [10:0] row_span = row_last-row_first+1'b1;
    wire [10:0] row_hole = row_gr-row_gl+1'b1;

    function connected;
        input [10:0] a,b,c,d;
        begin connected = ({1'b0,a} <= {1'b0,d}+12'd1) &&
                          ({1'b0,c} <= {1'b0,b}+12'd1); end
    endfunction
    wire [10:0] a_end = row_runs == 2 ? row_gl-1'b1 : row_last;
    wire [10:0] b_start = row_gr+1'b1;
    wire [10:0] pa_end = prev_runs == 2 ? prev_gl-1'b1 : prev_last;
    wire [10:0] pb_start = prev_gr+1'b1;
    wire aa = connected(row_first,a_end,prev_first,pa_end);
    wire ab = prev_runs == 2 && connected(row_first,a_end,pb_start,prev_last);
    wire ba = row_runs == 2 && connected(b_start,row_last,prev_first,pa_end);
    wire bb = row_runs == 2 && prev_runs == 2 &&
              connected(b_start,row_last,pb_start,prev_last);
    wire links_ok = (aa || ab) && (row_runs != 2 || ba || bb) &&
                    (aa || ba) && (prev_runs != 2 || ab || bb);
    reg finish;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            seen<=0; ended<=0; hole_seen<=0; hole_done<=0;
            bad_topology<=0; border<=0; stream_bad<=0; finish<=0;
            xmin<=0; xmax<=0; ymin<=0; ymax<=0;
            hxmin<=0; hxmax<=0; hymin<=0; hymax<=0;
            max_span<=0; max_hole<=0; prev_runs<=0;
            prev_first<=0; prev_last<=0; prev_gl<=0; prev_gr<=0;
        end else begin
            finish<=row_v && row_eof;
            if (row_v) begin
                prev_runs<=row_runs; prev_first<=row_first; prev_last<=row_last;
                prev_gl<=row_gl; prev_gr<=row_gr;
                if (row_sof) begin
                    seen<=(row_runs != 0); ended<=0;
                    hole_seen<=0; hole_done<=0;
                    bad_topology<=(row_runs > 1);
                    border<=(row_runs != 0); stream_bad<=row_err;
                    xmin<=row_first; xmax<=row_last; ymin<=0; ymax<=0;
                    hxmin<=0; hxmax<=0; hymin<=0; hymax<=0;
                    max_span<=row_runs != 0 ? row_span : 11'd0;
                    max_hole<=0;
                end else begin
                    if (row_err) stream_bad<=1;
                    if (row_runs != 0) begin
                        seen<=1;
                        if (!seen) begin
                            xmin<=row_first; xmax<=row_last; ymin<=row_y;
                        end else begin
                            if (row_first < xmin) xmin<=row_first;
                            if (row_last > xmax) xmax<=row_last;
                        end
                        ymax<=row_y;
                        if (row_span > max_span) max_span<=row_span;
                        if (row_first == 0 || row_last >= WIDTH-1 || row_eof) border<=1;
                        if (ended || row_runs > 2 || (seen && !links_ok)) bad_topology<=1;
                    end else if (seen) begin
                        ended<=1;
                        if (hole_seen && !hole_done) bad_topology<=1;
                    end

                    if (row_runs == 2) begin
                        hole_seen<=1;
                        if (!hole_seen) begin
                            hxmin<=row_gl; hxmax<=row_gr; hymin<=row_y;
                            if (prev_runs != 1 || prev_first > row_gl || prev_last < row_gr)
                                bad_topology<=1;
                        end else begin
                            if (row_gl < hxmin) hxmin<=row_gl;
                            if (row_gr > hxmax) hxmax<=row_gr;
                            if (hole_done || row_gl > prev_gr || row_gr < prev_gl)
                                bad_topology<=1;
                        end
                        hymax<=row_y;
                        if (row_hole > max_hole) max_hole<=row_hole;
                    end else if (prev_runs == 2) begin
                        hole_done<=1;
                        if (row_runs != 1 || row_first > prev_gl || row_last < prev_gr)
                            bad_topology<=1;
                    end
                end
            end
        end
    end

    reg result_v;
    reg [10:0] ow,oh,iw,ih,diameter,hole_diameter;
    reg [11:0] cx_sum,cy_sum,hcx_sum,hcy_sum;
    reg m_seen,m_border,m_bad,m_stream,m_hole;
    // Snapshot after the last row's nonblocking updates, before another
    // frame can alter the accumulators. Width checks get a separate stage.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            result_v<=0; ow<=0; oh<=0; iw<=0; ih<=0;
            diameter<=0; hole_diameter<=0;
            cx_sum<=0; cy_sum<=0; hcx_sum<=0; hcy_sum<=0;
            m_seen<=0; m_border<=0; m_bad<=0; m_stream<=0; m_hole<=0;
        end else begin
            result_v<=finish;
            if (finish) begin
                ow<=xmax-xmin+1'b1; oh<=ymax-ymin+1'b1;
                iw<=hxmax-hxmin+1'b1; ih<=hymax-hymin+1'b1;
                diameter<=max_span; hole_diameter<=max_hole;
                cx_sum<={1'b0,xmin}+{1'b0,xmax}; cy_sum<={1'b0,ymin}+{1'b0,ymax};
                hcx_sum<={1'b0,hxmin}+{1'b0,hxmax}; hcy_sum<={1'b0,hymin}+{1'b0,hymax};
                m_seen<=seen; m_border<=border; m_bad<=bad_topology;
                m_stream<=stream_bad; m_hole<=hole_seen && hole_done;
            end
        end
    end
    wire [10:0] outer_diff = ow > oh ? ow-oh : oh-ow;
    wire [10:0] inner_diff = iw > ih ? iw-ih : ih-iw;
    wire shape_bad = ow < MIN_OUTER || oh < MIN_OUTER ||
                     iw < MIN_HOLE || ih < MIN_HOLE || iw >= ow || ih >= oh ||
                     outer_diff > (ow >> 4)+ASPECT_TOL ||
                     inner_diff > (iw >> 4)+ASPECT_TOL ||
                     ow != diameter || iw != hole_diameter;
    wire [2:0] status = m_stream ? 3'd5 : !m_seen ? 3'd1 :
                        m_border ? 3'd2 : (m_bad || !m_hole) ? 3'd3 :
                        shape_bad ? 3'd4 : 3'd0;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_span<=0; O_hole<=0; O_center_x<=0; O_center_y<=0;
            O_hole_x<=0; O_hole_y<=0; O_valid<=0; O_status<=5; O_upd<=0;
        end else if (abort_frame || result_v) begin
            O_upd<=~O_upd;
            O_status<=abort_frame ? 3'd5 : status;
            O_valid<=!abort_frame && status == 0;
            if (!abort_frame && status == 0) begin
                O_span<={5'd0,diameter}; O_hole<={5'd0,hole_diameter};
                O_center_x<=cx_sum[11:1]; O_center_y<=cy_sum[11:1];
                O_hole_x<=hcx_sum[11:1]; O_hole_y<=hcy_sum[11:1];
            end else begin
                O_span<=0; O_hole<=0; O_center_x<=0; O_center_y<=0;
                O_hole_x<=0; O_hole_y<=0;
            end
        end
    end
endmodule

// Rotation-independent, bounded single-part shape features. Coordinates are
// doubled grid-cell distances from the selected outer bounding-box centre.
// Three 9x9 point products and ONE shared 16x16 post-frame multiplier.
// Fourfold/sixfold radial energy separates square/hex outlines from washers;
// unlike an axis-aligned bbox ratio it survives arbitrary in-plane rotation.
module img_parts_shape(
    input I_clk,I_rst_n,I_start,I_point,I_finish,
    input signed [8:0] I_dx,I_dy,
    output reg O_done,O_elongated,O_round,O_hex,O_circle,O_head,O_square
);
    reg [31:0] moment_x,moment_y;
    reg signed [31:0] moment_xy;
    reg signed [23:0] sum_x,sum_y;
    reg [15:0] points;
    reg signed [8:0] input_dx,input_dy,pending_dx,pending_dy;
    wire [23:0] sum_abs_x=sum_x<0 ? -sum_x : sum_x;
    wire [23:0] sum_abs_y=sum_y<0 ? -sum_y : sum_y;
    reg [15:0] radial[0:23];
    // Valid follows each point through input, rotation, weights, compares,
    // and bin encoding. Finish drains these stages before reading radial[].
    reg [4:0] point_valid;
    reg [17:0] point_x,point_y;
    reg signed [17:0] point_xy;
    reg [4:0] point_bin;
    reg [18:0] radius_s2,radius_s3,point_r2;
    reg [8:0] ax,ay;
    reg [1:0] quadrant;
    reg [1:0] quadrant_s2,quadrant_s3;
    reg axis,axis_s2,axis_s3;
    reg [4:0] axis_bin,axis_bin_s2,axis_bin_s3;
    reg [17:0] x69,x148,y69,y148,x256,y256;
    reg [4:0] angle_less;
    reg diagonal_less;
    reg [2:0] sector;
    reg [4:0] bin;
    always @* begin
        sector=0;bin=0;
        if(angle_less[0]) sector=0;
        else if(angle_less[1]) sector=1;
        else if(angle_less[2]) sector=2;
        else if(angle_less[3]) sector=3;
        else if(angle_less[4]) sector=4;
        else sector=5;
        case(quadrant_s3)
            0:bin=sector;1:bin=6+sector;2:bin=12+sector;3:bin=18+sector;
        endcase
        if(axis_s3) bin=axis_bin_s3;
    end
    reg [3:0] state;
    reg [4:0] index;
    reg [2:0] square_index;
    reg [31:0] radial_sum;
    reg signed [31:0] radial_cos,radial_sin;
    reg signed [31:0] four_cos,four_sin;
    reg [2:0] four_phase;
    reg signed [19:0] four_weight_cos,four_weight_sin;
    wire signed [19:0] radial_value=$signed({4'd0,radial[index]});
    wire signed [19:0] radial_seven=(radial_value<<3)-radial_value;
    reg [15:0] mul_a,mul_b;
    reg [31:0] product,diff_sq,cross_sq,trace_sq,cos_sq,sin_sq;
    reg [32:0] anis_num,six_num;
    reg [31:0] four_cos_sq,four_sin_sq;
    reg [32:0] four_num;
    wire [32:0] moment_trace={1'b0,moment_x}+{1'b0,moment_y};
    reg [35:0] anis_five;
    reg [23:0] centroid_abs_x,centroid_abs_y;
    reg [24:0] centroid_abs_sum;
    reg [31:0] radial_total_sq;
    integer k;
    always @(posedge I_clk) product<=mul_a*mul_b;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            moment_x<=0;moment_y<=0;moment_xy<=0;point_valid<=0;
            input_dx<=0;input_dy<=0;ax<=0;ay<=0;quadrant<=0;
            quadrant_s2<=0;quadrant_s3<=0;axis<=0;axis_s2<=0;axis_s3<=0;
            axis_bin<=0;axis_bin_s2<=0;axis_bin_s3<=0;
            x69<=0;x148<=0;y69<=0;y148<=0;x256<=0;y256<=0;
            diagonal_less<=0;angle_less<=0;radius_s2<=0;radius_s3<=0;point_r2<=0;
            anis_num<=0;six_num<=0;anis_five<=0;radial_total_sq<=0;
            four_cos<=0;four_sin<=0;four_phase<=0;four_cos_sq<=0;four_sin_sq<=0;four_num<=0;
            four_weight_cos<=0;four_weight_sin<=0;
            centroid_abs_x<=0;centroid_abs_y<=0;centroid_abs_sum<=0;
            sum_x<=0;sum_y<=0;points<=0;pending_dx<=0;pending_dy<=0;
            point_x<=0;point_y<=0;point_xy<=0;point_bin<=0;
            state<=0;index<=0;square_index<=0;radial_sum<=0;radial_cos<=0;radial_sin<=0;
            mul_a<=0;mul_b<=0;diff_sq<=0;cross_sq<=0;trace_sq<=0;cos_sq<=0;sin_sq<=0;
            O_done<=0;O_elongated<=0;O_round<=0;O_hex<=0;O_circle<=0;O_head<=0;O_square<=0;
            for(k=0;k<24;k=k+1) radial[k]<=0;
        end else begin
            O_done<=0;
            point_valid<={point_valid[3:0],I_point && state==0};
            // Stage 0: end the queue RAM / centre subtraction path here.
            input_dx<=I_dx;input_dy<=I_dy;
            // Stage 1: rotate into the first quadrant, and form moments.
            if(input_dx>=0 && input_dy>=0) begin ax<=input_dx;ay<=input_dy;quadrant<=0;end
            else if(input_dx<0 && input_dy>=0) begin ax<=input_dy;ay<=-input_dx;quadrant<=1;end
            else if(input_dx<0 && input_dy<0) begin ax<=-input_dx;ay<=-input_dy;quadrant<=2;end
            else begin ax<=-input_dy;ay<=input_dx;quadrant<=3;end
            axis<=input_dy==0 || input_dx==0;
            axis_bin<=input_dy==0 ? (input_dx<0 ? 12 : 0) : (input_dy<0 ? 18 : 6);
            pending_dx<=input_dx;pending_dy<=input_dy;
            point_x<=input_dx*input_dx;point_y<=input_dy*input_dy;point_xy<=input_dx*input_dy;
            // Stage 2: fixed tan(15/30/60/75) weights, no new multipliers.
            x69<=({9'd0,ax}<<6)+({9'd0,ax}<<2)+ax;
            x148<=({9'd0,ax}<<7)+({9'd0,ax}<<4)+({9'd0,ax}<<2);
            y69<=({9'd0,ay}<<6)+({9'd0,ay}<<2)+ay;
            y148<=({9'd0,ay}<<7)+({9'd0,ay}<<4)+({9'd0,ay}<<2);
            x256<={1'b0,ax,8'd0};y256<={1'b0,ay,8'd0};diagonal_less<=ay<ax;
            quadrant_s2<=quadrant;axis_s2<=axis;axis_bin_s2<=axis_bin;
            radius_s2<={1'b0,point_x}+{1'b0,point_y};
            // Stage 3: parallel comparisons. Stage 4: priority/bin encode.
            angle_less<={y69<x256,y148<x256,diagonal_less,y256<x148,y256<x69};
            quadrant_s3<=quadrant_s2;axis_s3<=axis_s2;axis_bin_s3<=axis_bin_s2;radius_s3<=radius_s2;
            point_bin<=bin;point_r2<=radius_s3;
            if(I_start) begin
                moment_x<=0;moment_y<=0;moment_xy<=0;point_valid<=0;
                sum_x<=0;sum_y<=0;points<=0;
                state<=0;index<=0;radial_sum<=0;radial_cos<=0;radial_sin<=0;
                four_cos<=0;four_sin<=0;four_phase<=0;
                O_elongated<=0;O_round<=0;O_hex<=0;O_circle<=0;O_head<=0;O_square<=0;
                for(k=0;k<24;k=k+1) radial[k]<=0;
            end else begin
                if(point_valid[1]) begin
                    sum_x<=sum_x+{{15{pending_dx[8]}},pending_dx};
                    sum_y<=sum_y+{{15{pending_dy[8]}},pending_dy};
                    points<=points+1'b1;
                    moment_x<=moment_x+point_x;moment_y<=moment_y+point_y;
                    moment_xy<=moment_xy+{{14{point_xy[17]}},point_xy};
                end
                if(point_valid[4] && point_r2>radial[point_bin]) radial[point_bin]<=point_r2[15:0];
                case(state)
                    0:if(I_finish) begin state<=9;index<=0;end
                    9:if(point_valid==0) state<=1;
                    1:begin
                        radial_sum<=radial_sum+radial[index];
                        case(index[1:0])
                            0:radial_cos<=radial_cos+$signed({16'd0,radial[index]});
                            1:radial_sin<=radial_sin+$signed({16'd0,radial[index]});
                            2:radial_cos<=radial_cos-$signed({16'd0,radial[index]});
                            3:radial_sin<=radial_sin-$signed({16'd0,radial[index]});
                        endcase
                        // Four cycles over 24 angular bins. Cosine weights
                        // 8,4,-4,-8,-4,4; sine 0,7,7,0,-7,-7 approximate
                        // sin/cos at 60 degrees with add/shift logic only.
                        // Register weights before the accumulator; the new
                        // harmonic must not create a chained add/sub path.
                        four_weight_cos<=0;four_weight_sin<=0;
                        case(four_phase)
                            0:four_weight_cos<=radial_value<<3;
                            1:begin four_weight_cos<=radial_value<<2;four_weight_sin<=radial_seven;end
                            2:begin four_weight_cos<=-(radial_value<<2);four_weight_sin<=radial_seven;end
                            3:four_weight_cos<=-(radial_value<<3);
                            4:begin four_weight_cos<=-(radial_value<<2);four_weight_sin<=-radial_seven;end
                            5:begin four_weight_cos<=radial_value<<2;four_weight_sin<=-radial_seven;end
                        endcase
                        state<=11;
                    end
                    11:begin
                        four_cos<=four_cos+{{12{four_weight_cos[19]}},four_weight_cos};
                        four_sin<=four_sin+{{12{four_weight_sin[19]}},four_weight_sin};
                        four_phase<=four_phase==5 ? 0 : four_phase+1'b1;
                        if(index==23) state<=10;else begin index<=index+1'b1;state<=1;end
                    end
                    10:begin four_cos<=four_cos>>>3;four_sin<=four_sin>>>3;state<=2;end
                    2:begin
                        // Common power-of-two normalization preserves each
                        // invariant while bounding every shared square to16b.
                        if(moment_trace>65535) begin
                            moment_x<=moment_x>>1;moment_y<=moment_y>>1;moment_xy<=moment_xy>>>1;
                        end
                        if(radial_sum>65535) begin
                            radial_sum<=radial_sum>>1;radial_cos<=radial_cos>>>1;radial_sin<=radial_sin>>>1;
                            four_cos<=four_cos>>>1;four_sin<=four_sin>>>1;
                        end
                        if(moment_trace<=65535 && radial_sum<=65535) begin square_index<=0;state<=3;end
                    end
                    3:begin
                        case(square_index)
                            0:begin mul_a<=moment_x>moment_y ? moment_x-moment_y : moment_y-moment_x;
                                    mul_b<=moment_x>moment_y ? moment_x-moment_y : moment_y-moment_x;end
                            1:begin mul_a<=moment_xy<0 ? -moment_xy : moment_xy;mul_b<=moment_xy<0 ? -moment_xy : moment_xy;end
                            2:begin mul_a<=moment_trace;mul_b<=moment_trace;end
                            3:begin mul_a<=radial_cos<0 ? -radial_cos : radial_cos;mul_b<=radial_cos<0 ? -radial_cos : radial_cos;end
                            4:begin mul_a<=radial_sin<0 ? -radial_sin : radial_sin;mul_b<=radial_sin<0 ? -radial_sin : radial_sin;end
                            5:begin mul_a<=radial_sum;mul_b<=radial_sum;end
                            6:begin mul_a<=four_cos<0 ? -four_cos : four_cos;mul_b<=four_cos<0 ? -four_cos : four_cos;end
                            7:begin mul_a<=four_sin<0 ? -four_sin : four_sin;mul_b<=four_sin<0 ? -four_sin : four_sin;end
                        endcase
                        state<=4;
                    end
                    4:state<=5;
                    5:begin
                        case(square_index)
                            0:diff_sq<=product;1:cross_sq<=product;2:trace_sq<=product;
                            3:cos_sq<=product;4:sin_sq<=product;
                            5:radial_total_sq<=product;6:four_cos_sq<=product;7:four_sin_sq<=product;
                        endcase
                        if(square_index==7) begin
                            state<=6;
                        end else begin square_index<=square_index+1'b1;state<=3;end
                    end
                    6:begin
                        anis_num<={1'b0,diff_sq}+({1'b0,cross_sq}<<2);
                        six_num<={1'b0,cos_sq}+{1'b0,sin_sq};
                        four_num<={1'b0,four_cos_sq}+{1'b0,four_sin_sq};
                        centroid_abs_x<=sum_abs_x;centroid_abs_y<=sum_abs_y;
                        state<=7;
                    end
                    7:begin
                        anis_five<=({3'd0,anis_num}<<2)+{3'd0,anis_num};
                        centroid_abs_sum<={1'b0,centroid_abs_x}+{1'b0,centroid_abs_y};
                        state<=8;
                    end
                    8:begin
                            O_elongated<=trace_sq!=0 && anis_five>=trace_sq;
                            O_round<=trace_sq!=0 && ({4'd0,anis_num}<<4)<=trace_sq;
                            // A larger head shifts the occupied-cell centroid
                            // away from the bounding-box centre. Symmetric
                            // bars and elongated rings must not become screws.
                            O_head<=centroid_abs_sum>={8'd0,points};
                            // A dead band rejects ambiguous outlines rather
                            // than forcing a nut/washer decision.
                            O_hex<=radial_total_sq!=0 && ({10'd0,six_num}<<10)>=radial_total_sq && ({6'd0,six_num}<<6)<=radial_total_sq &&
                                ({8'd0,four_num}<<8)<radial_total_sq;
                            O_circle<=radial_total_sq!=0 && ({11'd0,six_num}<<11)<=radial_total_sq &&
                                ({9'd0,four_num}<<9)<=radial_total_sq;
                            O_square<=radial_total_sq!=0 && ({8'd0,four_num}<<8)>=radial_total_sq &&
                                ({4'd0,four_num}<<4)<=radial_total_sq;
                            O_done<=1;state<=0;
                    end
                endcase
            end
        end
    end
endmodule

// Two-stage relative appearance classifier. Keep exactly TWO clocks so the
// independent binary/marker pipeline and all four pixel lanes remain aligned.
module img_parts_color #(
    parameter SIGNAL_FLOOR=16
)(input I_clk,I_rst_n,input [23:0] I_rgb,input [7:0] I_reference,
  output reg [2:0] O_color);
    reg [8:0] red,green,blue,peak,spread,reference;
    reg [7:0] maximum,minimum;
    wire [8:0] neutral_band=(peak>>3)+9'd4;
    wire [8:0] black_band=(peak>>2)+9'd4;
    wire [8:0] black_limit=(reference>>2)+(reference>>4);
    // HSV sector inequalities: H=60*(G-B)/(max-min) when R is max.
    // Widen BEFORE shifting; four lanes sustain one pixel/lane/clock.
    wire [8:0] gb_delta=green>=blue ? green-blue:blue-green;
    wire [8:0] gr_delta=green>=red ? green-red:9'd0;
    wire [12:0] hue_num={4'd0,gb_delta};
    wire [12:0] hue_den={4'd0,spread};
    wire hue_red=red==peak && (hue_num<<2)<=hue_den;
    wire hue_brass=blue<=red && blue<=green &&
        (red>=green ? (hue_num<<4)>=((hue_den<<2)+hue_den) :
                      ({4'd0,gr_delta}<<3)<=hue_den);
    always @* begin
        maximum=I_rgb[23:16]>I_rgb[15:8] ? I_rgb[23:16]:I_rgb[15:8];
        if(I_rgb[7:0]>maximum) maximum=I_rgb[7:0];
        minimum=I_rgb[23:16]<I_rgb[15:8] ? I_rgb[23:16]:I_rgb[15:8];
        if(I_rgb[7:0]<minimum) minimum=I_rgb[7:0];
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin red<=0;green<=0;blue<=0;peak<=0;spread<=0;reference<=224;O_color<=0;end
        else begin
            red<={1'b0,I_rgb[23:16]};green<={1'b0,I_rgb[15:8]};blue<={1'b0,I_rgb[7:0]};
            peak<={1'b0,maximum};spread<={1'b0,maximum}-{1'b0,minimum};
            reference<=I_reference>=64 ? {1'b0,I_reference}:9'd224;
            O_color<=0;
            // Neutral dark foreground includes true zero: segmentation has
            // already established the object. Never infer BLACK from UNKN.
            // Mild colour casts at low signal must not create unstable hue.
            if(peak<=black_limit && spread<=black_band) O_color<=4;
            else if(peak<250 && peak>=SIGNAL_FLOOR) begin
                if(spread<=neutral_band) begin
                    if(peak>=(reference>>2)+(reference>>3)) O_color<=5;
                end else if(hue_brass) O_color<=6; // 18.75..67.5 degrees
                else if(hue_red) O_color<=1;      // -15..15 degrees (wrap)
                // Retain unknown intervals rather than merging red/brass.
            end
        end
    end
endmodule

// Sparse diagnostic mean from original foreground in the previous bbox.
// One pixel per 8x8 cell, no image RAM and one shared serial divider.
// The mean is descriptive only: highlights/shadows are deliberately retained.
module img_parts_monitor #(
    parameter BEATS_PER_LINE=320,LINES_PER_FRAME=720
)(input I_clk,I_rst_n,input [95:0] I_rgb,input I_valid,I_sof,I_eol,
  input [10:0] I_x0,I_x1,I_y0,I_y1,input I_box_valid,input [7:0] I_threshold,
  output reg [31:0] O_stats);
    reg [10:0] x,y,x0,x1,y0,y1;
    reg active,box_valid;
    wire [10:0] cx=I_sof ? 11'd0:x,cy=I_sof ? 11'd0:y;
    wire [9:0] gray={2'd0,I_rgb[23:16]}+{1'b0,I_rgb[15:8],1'b0}+{2'd0,I_rgb[7:0]};
    wire sample=I_valid && (active || I_sof) && box_valid && cx[2:0]==4 && cy[2:0]==4 &&
        cx>x0+2 && cx+2<x1 && cy>y0+2 && cy+2<y1 && gray[9:2]<I_threshold;
    reg [23:0] sr,sg,sb;
    reg [15:0] count,clipped;
    reg busy,clip_flag;
    reg [1:0] channel;
    reg [4:0] bit_index;
    reg [23:0] num,quot,snap_g,snap_b;
    reg [15:0] den;
    reg [16:0] rem;
    reg [7:0] mr,mg;
    wire [16:0] trial={rem[15:0],num[23]};
    wire ge=trial>={1'b0,den};
    wire [23:0] result={quot[22:0],ge};
    wire stable_box=I_box_valid && x0==I_x0 && x1==I_x1 && y0==I_y0 && y1==I_y1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x<=0;y<=0;active<=0;box_valid<=0;x0<=0;x1<=0;y0<=0;y1<=0;
            sr<=0;sg<=0;sb<=0;count<=0;clipped<=0;busy<=0;clip_flag<=0;
            channel<=0;bit_index<=0;num<=0;quot<=0;snap_g<=0;snap_b<=0;
            den<=1;rem<=0;mr<=0;mg<=0;O_stats<=0;
        end else begin
            if(I_valid && (active || I_sof)) begin
                if(I_sof) begin
                    active<=1;sr<=0;sg<=0;sb<=0;count<=0;clipped<=0;
                    x0<=I_x0;x1<=I_x1;y0<=I_y0;y1<=I_y1;box_valid<=I_box_valid;
                end else if(sample) begin
                    sr<=sr+I_rgb[23:16];sg<=sg+I_rgb[15:8];sb<=sb+I_rgb[7:0];count<=count+1'b1;
                    if(I_rgb[23:16]>=250 || I_rgb[15:8]>=250 || I_rgb[7:0]>=250) clipped<=clipped+1'b1;
                end
                if(I_eol) begin
                    x<=0;y<=cy+1'b1;
                    if(cy==LINES_PER_FRAME-1) begin
                        active<=0;
                        if(count>=8 && stable_box && !busy) begin
                            busy<=1;channel<=0;bit_index<=0;num<=sr;quot<=0;rem<=0;den<=count;
                            snap_g<=sg;snap_b<=sb;clip_flag<=({clipped,2'd0}>={2'd0,count});
                        end else O_stats<=0;
                    end
                end else begin x<=cx+4;y<=cy;end
            end
            if(busy) begin
                num<={num[22:0],1'b0};quot<=result;rem<=ge ? trial-{1'b0,den}:trial;
                if(bit_index==23) begin
                    bit_index<=0;rem<=0;quot<=0;
                    if(channel==0) begin mr<=result[7:0];channel<=1;num<=snap_g;end
                    else if(channel==1) begin mg<=result[7:0];channel<=2;num<=snap_b;end
                    else begin
                        busy<=0;O_stats<={1'b1,clip_flag,(mr<16 && mg<16 && result[7:0]<16),5'd0,mr,mg,result[7:0]};
                    end
                end else bit_index<=bit_index+1'b1;
            end
        end
    end
endmodule

// Coarse single-tire recognizer. Kept in this existing project source so TD
// needs no new source registration. Video is never stalled. Capture complete
// frames only while idle; analysis may skip input frames. 8x8 majority cells,
// 4-connected components of BOTH polarities, one visited bit per cell.
// A hole is an enclosed BACKGROUND component, never inferred from failure.
// Serial, one-to-one association across completed observations. History is
// private until the batch publishes; raster slot changes do not transfer votes.
module img_parts_multi_tracker(
    input I_clk,I_rst_n,I_batch,I_start,I_publish,
    input [1:0] I_index,
    input [55:0] I_packet,
    input [7:0] I_epoch,
    output reg O_done,
    output reg [55:0] O_packet
);
    reg [55:0] previous[0:3],following[0:3];
    reg [1:0] previous_shape[0:3],following_shape[0:3];
    reg [1:0] previous_colour[0:3],following_colour[0:3];
    reg [7:0] previous_epoch,batch_epoch;
    reg [3:0] used;
    reg [2:0] state;
    reg [1:0] cursor,index,best;
    reg found,eligible;
    reg [12:0] distance,best_distance;
    reg [55:0] packet;
    integer j;
    function [10:0] delta;
        input [10:0] a,b;
        begin delta=a>=b ? a-b:b-a;end
    endfunction
    wire [55:0] old=previous[cursor];
    wire [10:0] dx=delta(packet[43:33],old[43:33]);
    wire [10:0] dy=delta(packet[21:11],old[21:11]);
    wire [10:0] dw=delta(packet[32:22]-packet[43:33],old[32:22]-old[43:33]);
    wire [10:0] dh=delta(packet[10:0]-packet[21:11],old[10:0]-old[21:11]);
    wire [1:0] shape_count=found ? (previous_shape[best]<3 ? previous_shape[best]+2'd1:2'd3):2'd1;
    wire colour_match=found && previous_epoch==batch_epoch && batch_epoch==I_epoch &&
        packet[51:49]!=0 && packet[51:49]==previous[best][51:49];
    wire [1:0] colour_count=packet[51:49]==0 ? 2'd0:colour_match ?
        (previous_colour[best]<3 ? previous_colour[best]+2'd1:2'd3):2'd1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=0;O_done<=0;O_packet<=0;used<=0;packet<=0;
            previous_epoch<=0;batch_epoch<=0;cursor<=0;index<=0;best<=0;
            found<=0;eligible<=0;distance<=0;best_distance<=0;
            for(j=0;j<4;j=j+1) begin
                previous[j]<=0;following[j]<=0;
                previous_shape[j]<=0;following_shape[j]<=0;
                previous_colour[j]<=0;following_colour[j]<=0;
            end
        end else begin
            O_done<=0;
            if(I_batch) begin
                used<=0;batch_epoch<=I_epoch;state<=0;
                for(j=0;j<4;j=j+1) begin following[j]<=0;following_shape[j]<=0;following_colour[j]<=0;end
            end else if(I_publish) begin
                previous_epoch<=batch_epoch;
                for(j=0;j<4;j=j+1) begin
                    previous[j]<=following[j];previous_shape[j]<=following_shape[j];previous_colour[j]<=following_colour[j];
                end
            end else case(state)
                0:if(I_start) begin
                    packet<=I_packet;index<=I_index;cursor<=0;found<=0;best_distance<=13'h1fff;state<=1;
                end
                1:begin
                    eligible<=packet[55] && old[55] && !used[cursor] && packet[54:52]==old[54:52] &&
                        dx<=64 && dy<=64 && dw<=32 && dh<=32;
                    distance<={2'd0,dx}+{2'd0,dy};state<=2;
                end
                2:begin
                    if(eligible && distance<best_distance) begin found<=1;best<=cursor;best_distance<=distance;end
                    if(cursor==3) state<=3;else begin cursor<=cursor+1'b1;state<=1;end
                end
                3:begin
                    following[index]<=packet;
                    following_shape[index]<=packet[55] ? shape_count:2'd0;
                    following_colour[index]<=packet[55] ? colour_count:2'd0;
                    if(found) used[best]<=1;
                    O_packet<={packet[55] && shape_count>=3,packet[54:52],
                        colour_count>=2 && batch_epoch==I_epoch ? packet[51:49]:3'd0,packet[48:0]};
                    O_done<=1;state<=0;
                end
                default:state<=0;
            endcase
        end
    end
endmodule

// 0.1 ms units; BCD carry increments only at the divided tick. No divider or
// wide multiply in the pixel path. Tick value follows the camera clock report.
module recognition_latency_meter #(parameter TICK_CYCLES=11251)(
    input I_clk,I_rst_n,I_start,I_finish,I_abort,
    output reg [15:0] O_bcd,output reg O_valid,O_upd
);
    localparam DIV_BITS=$clog2(TICK_CYCLES+1);
    reg [DIV_BITS-1:0] prescale;
    reg [15:0] elapsed;
    reg armed;
    wire tick=prescale==TICK_CYCLES-1;
    function [15:0] next_bcd;
        input [15:0] value;
        begin
            next_bcd=value+16'd1;
            if(value[3:0]==9) begin
                next_bcd={value[15:4]+12'd1,4'd0};
                if(value[7:4]==9) begin
                    next_bcd={value[15:8]+8'd1,8'd0};
                    if(value[11:8]==9) next_bcd={value[15:12]+4'd1,12'd0};
                end
            end
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin prescale<=0;elapsed<=0;armed<=0;O_bcd<=0;O_valid<=0;O_upd<=0;end
        else if(I_abort) begin
            armed<=0;
            if(armed || O_valid) begin O_valid<=0;O_upd<=~O_upd;end
        end else if(I_start) begin prescale<=0;elapsed<=0;armed<=1;end
        else if(armed) begin
            if(I_finish) begin
                O_bcd<=tick ? next_bcd(elapsed):elapsed;
                O_valid<=!(tick && elapsed==16'h9999);O_upd<=~O_upd;armed<=0;
            end else if(tick) begin
                prescale<=0;
                if(elapsed==16'h9999) begin armed<=0;O_valid<=0;O_upd<=~O_upd;end
                else elapsed<=next_bcd(elapsed);
            end else prescale<=prescale+1'b1;
        end
    end
endmodule

module img_tire #(
    parameter BEATS_PER_LINE=320, LINES_PER_FRAME=720,
    parameter FG_IS_WHITE=0, CONFIRM_FRAMES=3,
    parameter LINE_X=640, LINE_HYST=32,
    parameter MIN_DIAM_CELLS=8, MIN_AREA_CELLS=16,
    parameter WHITE_BOARD=1, BOARD_MIN_CELLS=8, COLOR_MODE=0,
    parameter PARTS_MODE=0, PARTS_WHITE_MARGIN=24, COLOR_CALIBRATION=0, MULTI_TARGETS=0,
    parameter LATENCY_DIAGNOSTICS=0, LATENCY_TICK_CYCLES=11251
)(
    input I_clk, I_rst_n,
    input [95:0] I_tdata,
    input [95:0] I_rgb,
    input I_tvalid, I_tuser, I_tlast,
    input I_roi_valid,
    input [10:0] I_roi_x0,I_roi_x1,I_roi_y0,I_roi_y1,
    output reg [10:0] O_x0,O_x1,O_y0,O_y1,O_cx,O_cy,O_w,O_h,
    output reg [19:0] O_area,
    output reg [2:0] O_type, // PARTS: 1 screw, 2 washer, 3 hex nut, 4 square nut, 7 candidate
    output reg [2:0] O_color, // 0 unknown, 1 red, 2 green, 3 blue, 4 black, 5 silver, 6 brass
    output reg O_valid,O_upd,O_moving,
    output reg [23:0] O_cnt,
    output reg [15:0] O_span,O_hole,
    output reg [10:0] O_hx,O_hy,
    output reg O_ring_valid,
    output reg [2:0] O_status,
    output reg O_board_valid, O_board_bank,
    output reg [10:0] O_board_x0,O_board_x1,O_board_y0,O_board_y1,
    input I_query_bank,
    input [7:0] I_query_row,
    output [16:0] O_query_row,O_query_prev,O_query_next,
    input [7:0] I_color_reference,I_color_epoch,
    input I_color_ready,
    output reg [127:0] O_color_diag,
    output reg [223:0] O_targets,
    output reg [2:0] O_target_count,
    output reg O_target_overflow,
    output [15:0] O_latency_bcd,
    output O_latency_valid,O_latency_upd
);
    // Split RGB comparisons from vote/column accumulation. Binary data and
    // markers take the same stage; color and shape stay on identical pixels.
    reg [95:0] binary_d;
    reg valid_d,user_d,last_d;
    reg [2:0] pc0_r,pc1_r,pc2_r,pc3_r;
    reg [95:0] binary_pre;
    reg valid_pre,user_pre,last_pre;
    reg [3:0] lum_pre0,lum_pre1,lum_pre2,lum_pre3;
    wire [2:0] parts_pc0,parts_pc1,parts_pc2,parts_pc3;
    reg [7:0] parts_threshold;
    wire [7:0] color_reference=COLOR_CALIBRATION ? I_color_reference:8'd224;
    reg [7:0] capture_epoch;
    reg capture_color_ready;
    wire color_context_ok=!COLOR_CALIBRATION ||
        (I_color_ready && capture_color_ready && capture_epoch==I_color_epoch);
    // Diagnostic RGB is sampled from the previous published bbox, on current
    // original foreground only. It does not participate in classification.
    wire [31:0] monitor_rgb;
    img_parts_monitor #(.BEATS_PER_LINE(BEATS_PER_LINE),.LINES_PER_FRAME(LINES_PER_FRAME)) monitor(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_rgb(I_rgb),.I_valid(I_tvalid),.I_sof(I_tuser),.I_eol(I_tlast),
        .I_x0(O_x0),.I_x1(O_x1),.I_y0(O_y0),.I_y1(O_y1),.I_box_valid(PARTS_MODE && O_valid),
        .I_threshold(parts_threshold),.O_stats(monitor_rgb));
    generate if(PARTS_MODE) begin : g_parts_color
        img_parts_color c0(I_clk,I_rst_n,I_rgb[23:0],color_reference,parts_pc0);
        img_parts_color c1(I_clk,I_rst_n,I_rgb[47:24],color_reference,parts_pc1);
        img_parts_color c2(I_clk,I_rst_n,I_rgb[71:48],color_reference,parts_pc2);
        img_parts_color c3(I_clk,I_rst_n,I_rgb[95:72],color_reference,parts_pc3);
    end else begin : g_no_parts_color
        assign parts_pc0=0;assign parts_pc1=0;assign parts_pc2=0;assign parts_pc3=0;
    end endgenerate
    wire [95:0] capture_data=(COLOR_MODE || PARTS_MODE) ? binary_d : I_tdata;
    wire capture_valid=(COLOR_MODE || PARTS_MODE) ? valid_d : I_tvalid;
    wire capture_user=(COLOR_MODE || PARTS_MODE) ? user_d : I_tuser;
    wire capture_last=(COLOR_MODE || PARTS_MODE) ? last_d : I_tlast;
    localparam GW=BEATS_PER_LINE/2, GH=LINES_PER_FRAME/8, N=GW*GH;
    localparam AW=$clog2(N), CW=$clog2(GW);
    localparam IDLE=0, SCAN_REQ=1, SCAN_WAIT=2, SCAN_CHECK=3,
        POP_REQ=4, POP_WAIT=5, POP_USE=6, NB_REQ=7, NB_WAIT=8,
        NB_CHECK=9, COMPONENT=10, FEATURES=11, DECIDE=12, PUBLISH=13,
        BOARD_INIT=15, PART_HIST=16, MORPH_CENTER=17, MORPH_CENTER_WAIT=18,
        MORPH_CENTER_USE=19, MORPH_REQ=20, MORPH_WAIT=21, MORPH_USE=22,
        MORPH_WRITE=23, PART_TRACE=24, PART_WAIT=25, NB_FETCH=26, COLOR_TOTAL=27, MULTI_LOAD=28, MULTI_CLEAR=29,
        MULTI_CLEAR_WAIT=30, MULTI_CLEAR_WRITE=31, MULTI_MATCH=32, MULTI_SAVE=33, MULTI_PUBLISH=34;
    localparam FIND_BOARD=0, TRACE_BOARD=1, FIND_DARK=2, FIND_HOLES=3, TRACE_TARGET=4;
    reg [5:0] state;
    reg capturing, frame_bad, frame_done, frame_error;
    reg frame_end;
    reg [3:0] frame_end_delay;
    reg [7:0] sx,sy,px,py,nx,ny;
    reg [2:0] phase;
    reg build_bank;
    reg [7:0] init_row;
    // Two banks: analysis builds the next boundary while preview reads the
    // last published boundary. Each row stores {present,left,right} in cells.
    reg [16:0] board_rows[0:2*GH-1];
    wire [16:0] scan_row=board_rows[(build_bank ? GH : 0)+sy];
    wire [16:0] neighbor_row=board_rows[(build_bank ? GH : 0)+ny];
    wire scan_inside=scan_row[16] && sx>scan_row[15:8] && sx<scan_row[7:0];
    reg neighbor_inside;
    always @(posedge I_clk) neighbor_inside<=neighbor_row[16] && nx>neighbor_row[15:8] && nx<neighbor_row[7:0];
    assign O_query_row=I_query_row<GH ? board_rows[(I_query_bank ? GH : 0)+I_query_row] : 17'd0;
    assign O_query_prev=(I_query_row>0 && I_query_row<GH) ? board_rows[(I_query_bank ? GH : 0)+I_query_row-1] : 17'd0;
    assign O_query_next=I_query_row<GH-1 ? board_rows[(I_query_bank ? GH : 0)+I_query_row+1] : 17'd0;
    reg board_found;
    reg [15:0] board_score;
    reg [7:0] board_l,board_r,board_t,board_b,board_sx,board_sy;
    reg [AW-1:0] board_seed;

    // Store 8x8 foreground counts. Consecutive 4-pixel beats form one row
    // of a cell. Synchronous column read is available on the second beat.
    reg [7:0] columns[0:GW-1];
    reg [7:0] column_q;
    reg half_clip;
    reg [2:0] half_count;
    reg [8:0] beat;
    reg [10:0] line;
    wire [8:0] bx=capture_user ? 9'd0 : beat;
    wire [10:0] yy=capture_user ? 11'd0 : line;
    wire [CW-1:0] col=bx >> 1;
    wire [3:0] bright={|capture_data[95:72],|capture_data[71:48],|capture_data[47:24],|capture_data[23:0]};
    // Relative RGB dominance rejects neutral white/gray. Also require an
    // absolute channel difference so nearly black noise cannot become blue.
    function [2:0] pixel_color;
        input [23:0] rgb;
        reg [10:0] r,g,b;
        begin
            r={3'd0,rgb[23:16]};g={3'd0,rgb[15:8]};b={3'd0,rgb[7:0]};
            pixel_color=0;
            // BLACK is measured from RGB, never inferred from lack of color.
            if(r<=80 && g<=80 && b<=80) pixel_color=4;
            if(r>=48 && r>=g+32 && r>=b+32 && (r<<2)>=g+(g<<2) && (r<<2)>=b+(b<<2)) pixel_color=1;
            else if(g>=48 && g>=r+32 && g>=b+32 && (g<<2)>=r+(r<<2) && (g<<2)>=b+(b<<2)) pixel_color=2;
            else if(b>=48 && b>=r+32 && b>=g+32 && (b<<2)>=r+(r<<2) && (b<<2)>=g+(g<<2)) pixel_color=3;
        end
    endfunction
    function [7:0] parts_gray;
        input [23:0] rgb;
        reg [9:0] sum;
        begin sum={2'd0,rgb[23:16]}+{1'd0,rgb[15:8],1'd0}+{2'd0,rgb[7:0]};parts_gray=sum[9:2];end
    endfunction
    // Dominant bright histogram bin estimates the backlit board each frame.
    // Classification uses this mask; the tested display path stays separate.
    reg [3:0] lum0,lum1,lum2,lum3;
    reg [19:0] white_hist[0:15];
    reg [3:0] hist_index,hist_best_bin;
    reg [19:0] hist_best;
    integer hi;
    wire take = capture_user ? (state==IDLE && !frame_done && !frame_error && !frame_end && frame_end_delay==0) : capturing;
    // Passive observer of the accepted batch, not every incoming camera SOF.
    // Finish on the very edge that publishes all slots, including empty scenes.
    generate if(LATENCY_DIAGNOSTICS) begin : g_latency
        recognition_latency_meter #(.TICK_CYCLES(LATENCY_TICK_CYCLES)) u_meter (
            .I_clk(I_clk),.I_rst_n(I_rst_n),
            .I_start(capture_valid && capture_user && take),
            .I_finish(MULTI_TARGETS ? state==MULTI_PUBLISH : state==14),
            .I_abort(frame_error),.O_bcd(O_latency_bcd),
            .O_valid(O_latency_valid),.O_upd(O_latency_upd));
    end else begin : g_no_latency
        assign O_latency_bcd=0;assign O_latency_valid=0;assign O_latency_upd=0;
    end endgenerate
    always @(posedge I_clk) begin
        if(PARTS_MODE && capture_valid && take) begin
            for(hi=0;hi<16;hi=hi+1)
                white_hist[hi]<=(capture_user ? 20'd0 : white_hist[hi])+
                    {19'd0,lum0==hi}+{19'd0,lum1==hi}+{19'd0,lum2==hi}+{19'd0,lum3==hi};
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            binary_d<=0;valid_d<=0;user_d<=0;last_d<=0;
            binary_pre<=0;valid_pre<=0;user_pre<=0;last_pre<=0;
            lum_pre0<=0;lum_pre1<=0;lum_pre2<=0;lum_pre3<=0;
            lum0<=0;lum1<=0;lum2<=0;lum3<=0;
            pc0_r<=0;pc1_r<=0;pc2_r<=0;pc3_r<=0;
        end else begin
            binary_d<=I_tdata;valid_d<=I_tvalid;user_d<=I_tuser;last_d<=I_tlast;
            if(PARTS_MODE) begin
                binary_pre[23:0]<=parts_gray(I_rgb[23:0])<parts_threshold ? 24'd0 : 24'hffffff;
                binary_pre[47:24]<=parts_gray(I_rgb[47:24])<parts_threshold ? 24'd0 : 24'hffffff;
                binary_pre[71:48]<=parts_gray(I_rgb[71:48])<parts_threshold ? 24'd0 : 24'hffffff;
                binary_pre[95:72]<=parts_gray(I_rgb[95:72])<parts_threshold ? 24'd0 : 24'hffffff;
                binary_d<=binary_pre;valid_pre<=I_tvalid;user_pre<=I_tuser;last_pre<=I_tlast;
                valid_d<=valid_pre;user_d<=user_pre;last_d<=last_pre;
            end
            lum0<=parts_gray(I_rgb[23:0])>>4;lum1<=parts_gray(I_rgb[47:24])>>4;
            lum2<=parts_gray(I_rgb[71:48])>>4;lum3<=parts_gray(I_rgb[95:72])>>4;
            if(PARTS_MODE) begin
                lum_pre0<=parts_gray(I_rgb[23:0])>>4;lum_pre1<=parts_gray(I_rgb[47:24])>>4;
                lum_pre2<=parts_gray(I_rgb[71:48])>>4;lum_pre3<=parts_gray(I_rgb[95:72])>>4;
                lum0<=lum_pre0;lum1<=lum_pre1;lum2<=lum_pre2;lum3<=lum_pre3;
            end
            pc0_r<=pixel_color(I_rgb[23:0]);pc1_r<=pixel_color(I_rgb[47:24]);
            pc2_r<=pixel_color(I_rgb[71:48]);pc3_r<=pixel_color(I_rgb[95:72]);
        end
    end
    wire [2:0] pc0=PARTS_MODE ? parts_pc0 : COLOR_MODE ? pc0_r : 3'd0;
    wire [2:0] pc1=PARTS_MODE ? parts_pc1 : COLOR_MODE ? pc1_r : 3'd0;
    wire [2:0] pc2=PARTS_MODE ? parts_pc2 : COLOR_MODE ? pc2_r : 3'd0;
    wire [2:0] pc3=PARTS_MODE ? parts_pc3 : COLOR_MODE ? pc3_r : 3'd0;
    wire [3:0] chromatic={(pc3>=1 && pc3<=3),(pc2>=1 && pc2<=3),
                          (pc1>=1 && pc1<=3),(pc0>=1 && pc0<=3)};
    // In parts mode colour cannot alter the proven shape mask. Vote only on
    // original foreground pixels; bright background/holes never become silver.
    wire [3:0] fg=(FG_IS_WHITE ? bright : ~bright) | (PARTS_MODE ? 4'd0 : chromatic);
    wire [3:0] vote_fg=PARTS_MODE ? fg : 4'hf;
    wire [2:0] silver_code=PARTS_MODE ? 3'd5 : 3'd2;
    wire [2:0] brass_code=PARTS_MODE ? 3'd6 : 3'd3;
    wire [2:0] red_four={2'd0,(pc0==1 && vote_fg[0])}+{2'd0,(pc1==1 && vote_fg[1])}+{2'd0,(pc2==1 && vote_fg[2])}+{2'd0,(pc3==1 && vote_fg[3])};
    wire [2:0] green_four={2'd0,(pc0==silver_code && vote_fg[0])}+{2'd0,(pc1==silver_code && vote_fg[1])}+{2'd0,(pc2==silver_code && vote_fg[2])}+{2'd0,(pc3==silver_code && vote_fg[3])};
    wire [2:0] blue_four={2'd0,(pc0==brass_code && vote_fg[0])}+{2'd0,(pc1==brass_code && vote_fg[1])}+{2'd0,(pc2==brass_code && vote_fg[2])}+{2'd0,(pc3==brass_code && vote_fg[3])};
    wire [2:0] black_four={2'd0,(pc0==4 && fg[0])}+{2'd0,(pc1==4 && fg[1])}+
                          {2'd0,(pc2==4 && fg[2])}+{2'd0,(pc3==4 && fg[3])};
    reg [27:0] rgb_columns[0:GW-1];
    reg [27:0] rgb_column_q;
    reg [2:0] half_red,half_green,half_blue,half_black;
    wire [6:0] black_sum=(yy[2:0]==0 ? 7'd0 : rgb_column_q[27:21])+half_black+black_four;
    wire [6:0] red_sum=(yy[2:0]==0 ? 7'd0 : rgb_column_q[20:14])+half_red+red_four;
    wire [6:0] green_sum=(yy[2:0]==0 ? 7'd0 : rgb_column_q[13:7])+half_green+green_four;
    wire [6:0] blue_sum=(yy[2:0]==0 ? 7'd0 : rgb_column_q[6:0])+half_blue+blue_four;
    wire [2:0] four={2'd0,fg[0]}+{2'd0,fg[1]}+{2'd0,fg[2]}+{2'd0,fg[3]};
    wire [6:0] cell_sum=(yy[2:0]==0 ? 7'd0 : column_q[6:0])+half_count+four;
    wire stream_error=(bx>=BEATS_PER_LINE || yy>=LINES_PER_FRAME ||
                      capture_last != (bx==BEATS_PER_LINE-1));
    reg [AW-1:0] cap_base;
    wire cap_we=capture_valid && take && bx<BEATS_PER_LINE && yy<LINES_PER_FRAME && bx[0] && yy[2:0]==7;
    wire [AW-1:0] cap_addr=cap_base+col;
    wire cell_clip;
    // Retire each completed 8x8 cell through explicit register boundaries.
    // Column RAM -> four totals -> balanced vote total/comparisons -> class
    // -> map RAM. Carry address, geometry and write-valid alongside colour.
    reg [2:0] cap_pending;
    reg [AW-1:0] cap_addr_s0,cap_addr_s1,cap_addr_s2;
    reg [6:0] cap_red,cap_silver,cap_brass,cap_black,cap_count;
    reg [2:0] cap_meta_s0,cap_meta_s1;
    reg [2:0] cap_legacy;
    reg [8:0] cap_total;
    reg [3:0] cap_majority;
    reg [7:0] cap_data_s2;
    wire [8:0] cap_pair0={2'd0,cap_red}+{2'd0,cap_silver};
    wire [8:0] cap_pair1={2'd0,cap_brass}+{2'd0,cap_black};
    // Totals must remain paired with the registered sum even for consecutive
    // cell completions; do not rely on the usual two-beat spacing.
    reg [6:0] cap_red_s1,cap_silver_s1,cap_brass_s1,cap_black_s1,cap_count_s1;
    wire [2:0] cap_parts_result=cap_total<16 ? 0 :
        (cap_majority[0] && {cap_red_s1,1'b0}>=cap_total) ? 1 :
        (cap_majority[1] && {cap_silver_s1,1'b0}>=cap_total) ? 5 :
        (cap_majority[2] && {cap_brass_s1,1'b0}>=cap_total) ? 6 :
        (cap_majority[3] && {cap_black_s1,1'b0}>=cap_total) ? 4 : 0;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            cap_pending<=0;cap_addr_s0<=0;cap_addr_s1<=0;cap_addr_s2<=0;
            cap_red<=0;cap_silver<=0;cap_brass<=0;cap_black<=0;cap_count<=0;
            cap_red_s1<=0;cap_silver_s1<=0;cap_brass_s1<=0;cap_black_s1<=0;
            cap_total<=0;cap_majority<=0;cap_meta_s0<=0;cap_meta_s1<=0;cap_count_s1<=0;
            cap_legacy<=0;cap_data_s2<=0;
        end else begin
            cap_pending<={cap_pending[1:0],cap_we};
            if(cap_we) begin
                cap_addr_s0<=cap_addr;cap_red<=red_sum;cap_silver<=green_sum;
                cap_brass<=blue_sum;cap_black<=black_sum;cap_count<=cell_sum;
                cap_meta_s0<={cell_clip,1'b0,cell_sum>=32};
            end
            if(cap_pending[0]) begin
                cap_addr_s1<=cap_addr_s0;cap_meta_s1<=cap_meta_s0;cap_count_s1<=cap_count;
                cap_total<=cap_pair0+cap_pair1;
                cap_red_s1<=cap_red;cap_silver_s1<=cap_silver;
                cap_brass_s1<=cap_brass;cap_black_s1<=cap_black;
                cap_majority[0]<=cap_red>=8 && cap_red>cap_silver && cap_red>cap_brass && cap_red>cap_black;
                cap_majority[1]<=cap_silver>=8 && cap_silver>cap_red && cap_silver>cap_brass && cap_silver>cap_black;
                cap_majority[2]<=cap_brass>=8 && cap_brass>cap_red && cap_brass>cap_silver && cap_brass>cap_black;
                cap_majority[3]<=cap_black>=8 && cap_black>cap_red && cap_black>cap_silver && cap_black>cap_brass;
                cap_legacy<=!COLOR_MODE ? 0 :
                    (cap_red>=8 && {cap_red,1'b0}>=cap_count && cap_red>cap_silver && cap_red>cap_brass) ? 1 :
                    (cap_silver>=8 && {cap_silver,1'b0}>=cap_count && cap_silver>cap_red && cap_silver>cap_brass) ? 2 :
                    (cap_brass>=8 && {cap_brass,1'b0}>=cap_count && cap_brass>cap_red && cap_brass>cap_silver) ? 3 :
                    (cap_black>=8 && {cap_black,1'b0}>=cap_count) ? 4 : 0;
            end
            if(cap_pending[1]) begin
                cap_addr_s2<=cap_addr_s1;
                cap_data_s2<={PARTS_MODE && cap_count_s1>=56,PARTS_MODE ? cap_parts_result : cap_legacy,1'b0,cap_meta_s1};
            end
        end
    end
    reg roi_valid;
    reg [10:0] rx0,rx1,ry0,ry1;
    // Tag actual foreground pixels touching a crop line, rather than
    // rejecting a quantized bbox which can extend 7 pixels beyond the object.
    reg four_clip;
    integer clip_p;
    reg [11:0] clip_x;
    wire active_roi=capture_user ? I_roi_valid : roi_valid;
    wire [10:0] active_rx0=capture_user ? I_roi_x0 : rx0;
    wire [10:0] active_rx1=capture_user ? I_roi_x1 : rx1;
    wire [10:0] active_ry0=capture_user ? I_roi_y0 : ry0;
    wire [10:0] active_ry1=capture_user ? I_roi_y1 : ry1;
    always @* begin
        four_clip=0; clip_x=0;
        for(clip_p=0;clip_p<4;clip_p=clip_p+1) begin
            clip_x={1'b0,bx,2'b00}+clip_p;
            if(fg[clip_p] && (clip_x==0 || clip_x==BEATS_PER_LINE*4-1 ||
                yy==0 || yy==LINES_PER_FRAME-1 ||
                (active_roi && (clip_x==active_rx0 || clip_x==active_rx1 ||
                                yy==active_ry0 || yy==active_ry1)))) four_clip=1;
        end
    end
    assign cell_clip=(yy[2:0]==0 ? 1'b0 : column_q[7]) | half_clip | four_clip;
    always @(posedge I_clk) begin
        if(capture_valid && take && bx<BEATS_PER_LINE) begin
            if(!bx[0]) column_q<=columns[col];
            else columns[col]<={cell_clip,cell_sum};
            if(COLOR_MODE || PARTS_MODE) begin
                if(!bx[0]) rgb_column_q<=rgb_columns[col];
                else rgb_columns[col]<={black_sum,red_sum,green_sum,blue_sum};
            end
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            beat<=0; line<=0; half_count<=0; half_clip<=0; cap_base<=0;
            half_red<=0;half_green<=0;half_blue<=0;half_black<=0;
            capturing<=0; frame_bad<=0; frame_done<=0; frame_error<=0;
            frame_end<=0;frame_end_delay<=0;
            roi_valid<=0; rx0<=0; rx1<=0; ry0<=0; ry1<=0;
        end else begin
            frame_end<=0;frame_end_delay<={frame_end_delay[2:0],frame_end};
            frame_done<=frame_end_delay[3]; frame_error<=0;
            if(capture_valid) begin
                if(capture_user) begin
                    capturing<=take; frame_bad<=stream_error; cap_base<=0;
                    if(capturing) frame_error<=1;
                    if(take) begin
                        roi_valid<=I_roi_valid;
                        rx0<=I_roi_x0; rx1<=I_roi_x1; ry0<=I_roi_y0; ry1<=I_roi_y1;
                    end
                end
                if(take) begin
                    if(!bx[0]) begin
                        half_count<=four; half_clip<=four_clip;
                        half_red<=red_four;half_green<=green_four;half_blue<=blue_four;half_black<=black_four;
                    end
                    if(stream_error) begin
                        frame_bad<=1; capturing<=0; frame_error<=1;
                    end
                    if(capture_last) begin
                        beat<=0; line<=yy+1'b1;
                        if(yy[2:0]==7) cap_base<=cap_base+GW;
                        if(yy==LINES_PER_FRAME-1) begin
                            capturing<=0;
                            if(frame_bad || stream_error) frame_error<=1;
                            else frame_end<=1;
                        end
                    end else begin
                        beat<=bx<BEATS_PER_LINE ? bx+1'b1 : bx;
                        line<=yy;
                    end
                end
            end
        end
    end

    // RAMs have synchronous reads and no array reset. Every captured frame
    // overwrites every map cell including visited bits before analysis.
    reg [7:0] map[0:N-1];
    reg [7:0] map_q;
    reg holes_phase;
    reg [AW-1:0] scan, addr;
    reg [2:0] direction;
    reg color;
    // Constant scaling must stay in add/shift logic. TD otherwise maps
    // constant products to DSPs even though no general multiplier is needed.
    function [31:0] scale_const;
        input [31:0] value;
        input integer factor;
        integer bit_index;
        begin
            scale_const=0;
            for(bit_index=0;bit_index<16;bit_index=bit_index+1)
                if((factor>>bit_index)&1) scale_const=scale_const+(value<<bit_index);
        end
    endfunction
    reg [AW-1:0] neighbor_addr;
    always @(posedge I_clk) neighbor_addr<=scale_const({24'd0,ny},GW)+nx;
    // Closing at the 8x8-cell mask resolution bridges small reflective gaps
    // without eroding thin washer/nut features. Component/hole analysis below
    // rejects detached shadow islands while preserving the original shape.
    reg morph_pass;
    reg morph_acc;
    reg [3:0] morph_tap;
    reg [6:0] morph_meta;
    reg morph_q;
    reg morph_scratch[0:N-1];
    reg [7:0] morph_x,morph_y;
    wire morph_tapping=state>=MORPH_REQ && state<=MORPH_USE;
    wire morph_use_scratch=morph_pass;
    wire [AW-1:0] morph_addr=scale_const({24'd0,morph_y},GW)+morph_x;
    always @* begin
        morph_x=sx;morph_y=sy;
        if(morph_tap%3==0 && sx>0) morph_x=sx-1'b1;
        if(morph_tap%3==2 && sx<GW-1) morph_x=sx+1'b1;
        if(morph_tap<3 && sy>0) morph_y=sy-1'b1;
        if(morph_tap>=6 && sy<GH-1) morph_y=sy+1'b1;
    end
    wire [AW-1:0] map_ra=morph_tapping ? morph_addr :
        (state==NB_REQ || state==NB_WAIT || state==NB_FETCH || state==NB_CHECK) ? neighbor_addr : scan;
    // Each multi-object hole search is confined to that object's rectangle.
    // Bright regions reaching its edge fail the existing strict containment
    // test. This avoids flood-filling the entire backlight four times.
    reg [7:0] cl,cr,ct,cb,bl,br,bt,bb,hl,hr,ht,hb;
    wire local_holes=MULTI_TARGETS && phase==FIND_HOLES;
    wire hole_scan_inside=sx>=bl && sx<=br && sy>=bt && sy<=bb;
    wire neighbor_ok=direction==0 ? px>(local_holes ? bl:0) : direction==1 ? px<(local_holes ? br:GW-1) :
                     direction==2 ? py>(local_holes ? bt:0) : py<(local_holes ? bb:GH-1);
    wire start_component=state==SCAN_CHECK && (phase==TRACE_TARGET ?
        (!map_q[3] && map_q[0]) : WHITE_BOARD ?
        (phase==FIND_BOARD ? (!map_q[1] && !map_q[0]) :
         phase==TRACE_BOARD ? (!map_q[3] && !map_q[0]) :
         phase==FIND_DARK ? (!map_q[1] && map_q[0] && scan_inside) :
                           (!map_q[1] && !map_q[0] && (!local_holes || hole_scan_inside))) :
        (!map_q[1] && (holes_phase || map_q[0])));
    wire add_neighbor=state==NB_CHECK && map_q[0]==color && (phase==TRACE_TARGET ? !map_q[3] : WHITE_BOARD ?
        (phase==TRACE_BOARD ? !map_q[3] : !map_q[1]) &&
        (phase!=FIND_DARK || neighbor_inside) : !map_q[1]);
    wire visit_we=start_component || add_neighbor;
    wire [AW-1:0] visit_addr=start_component ? scan : neighbor_addr;
    always @(posedge I_clk) begin
        map_q<=map[map_ra];
        if(PARTS_MODE) morph_q<=morph_use_scratch ? morph_scratch[map_ra] : map_q[0];
        if(cap_pending[2]) map[cap_addr_s2]<=cap_data_s2;
        else if(MULTI_TARGETS && state==MULTI_CLEAR_WRITE) map[scan]<={map_q[7:4],1'b0,map_q[2],map_q[0] && map_q[1],map_q[0]};
        else if(PARTS_MODE && state==MORPH_WRITE && morph_pass) map[scan]<={morph_meta,morph_acc};
        else if(visit_we) map[visit_addr]<={map_q[7:4],map_q[3] | (phase==TRACE_TARGET || (WHITE_BOARD && phase==TRACE_BOARD)),map_q[2],1'b1,start_component ? map_q[0] : color};
        // FIND_BOARD visited every bright region, including the tire hole.
        // Re-enable bright regions for the final enclosed-hole traversal.
        else if(WHITE_BOARD && phase==FIND_DARK && state==SCAN_CHECK && !map_q[0])
            map[scan]<={map_q[7:2],1'b0,1'b0};
        if(PARTS_MODE && state==MORPH_WRITE && !morph_pass) morph_scratch[scan]<=morph_acc;
    end
    reg [15:0] queue[0:N-1];
    reg [15:0] queue_q;
    reg [AW:0] head,tail;
    wire [AW-1:0] queue_wa=start_component ? {AW{1'b0}} : tail[AW-1:0];
    wire [15:0] queue_wd=start_component ? {sy,sx} : {ny,nx};
    always @(posedge I_clk) begin
        queue_q<=queue[head[AW-1:0]];
        if(visit_we) queue[queue_wa]<=queue_wd;
    end

    // Four small descriptors share the existing map, queue and shape engine.
    // The first four sufficiently large enclosed components in raster order
    // are analysed. Overflow is published instead of silently claiming all.
    reg [2:0] multi_count;
    reg [1:0] multi_index;
    reg multi_overflow;
    reg [31:0] multi_bounds[0:3];
    reg [15:0] multi_area[0:3];
    reg [AW-1:0] multi_seed[0:3];
    reg [15:0] multi_xy[0:3];
    reg [143:0] multi_votes[0:3];
    reg [223:0] multi_build;
    reg [15:0] ca,ba,ha,second_b,second_h;
    reg [AW-1:0] target_seed;
    reg [7:0] target_sx,target_sy;
    reg [15:0] cred,cgreen,cblue,cblack,bred,bgreen,bblue,bblack;
    reg [17:0] parts_vote_total;
    reg [15:0] cire,cisi,ciye,cibl,bire,bisi,biye,bibl,ci_count,bi_count;
    reg [15:0] vote_red,vote_silver,vote_brass,vote_black,vote_area;
    reg inner_fallback;
    reg [3:0] color_reason; // 0 OK,1 CAL,2 EMPTY,3 SAMPLE,4 MIXED,5 CONFIRM,6 DARK,7 CLIP
    wire choose_inner=bi_count>=8;
    wire [17:0] chosen_total={2'd0,vote_red}+{2'd0,vote_silver}+{2'd0,vote_brass}+{2'd0,vote_black};
    reg [2:0] parts_color_choice;
    reg [1:0] color_streak;
    reg cborder,bborder,cclip,bclip;
    // Prepare rank/containment while flood-fill finishes its neighbour scan.
    // Separate registered commits keep state/phase decode off bbox CE paths.
    reg rank_target,rank_hole,save_target,save_hole,clear_bounds;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            rank_target<=0;rank_hole<=0;save_target<=0;save_hole<=0;clear_bounds<=0;
            bl<=0;br<=0;bt<=0;bb<=0;hl<=0;hr<=0;ht<=0;hb<=0;
        end else begin
            rank_target<=!((WHITE_BOARD && (phase==FIND_BOARD || phase==TRACE_BOARD)) ||
                (PARTS_MODE && phase==TRACE_TARGET)) && color && ca>ba;
            rank_hole<=!((WHITE_BOARD && (phase==FIND_BOARD || phase==TRACE_BOARD)) ||
                (PARTS_MODE && phase==TRACE_TARGET)) && !color && !cborder &&
                cl>bl && cr<br && ct>bt && cb<bb && ca>ha;
            save_target<=state==POP_REQ && head==tail && rank_target;
            save_hole<=state==POP_REQ && head==tail && rank_hole;
            clear_bounds<=state==IDLE && frame_done;
            if(MULTI_TARGETS && state==MULTI_LOAD) begin
                {bl,br,bt,bb}<=multi_bounds[multi_index];hl<=0;hr<=0;ht<=0;hb<=0;
            end else if(clear_bounds) begin
                bl<=0;br<=0;bt<=0;bb<=0;hl<=0;hr<=0;ht<=0;hb<=0;
            end else begin
                if(save_target) begin bl<=cl;br<=cr;bt<=ct;bb<=cb;end
                if(save_hole) begin hl<=cl;hr<=cr;ht<=ct;hb<=cb;end
            end
        end
    end
    wire [15:0] component_box=({8'd0,cr}-{8'd0,cl}+16'd1)*({8'd0,cb}-{8'd0,ct}+16'd1);
    wire component_board_ok=ca>=16 && ({1'b0,cr}-{1'b0,cl}+9'd1)>=BOARD_MIN_CELLS &&
        ({1'b0,cb}-{1'b0,ct}+9'd1)>=BOARD_MIN_CELLS;
    // Row span updates only while retracing the selected board component.
    wire [7:0] trace_y=queue_q[15:8], trace_x=queue_q[7:0];
    wire [16:0] trace_row=board_rows[(build_bank ? GH : 0)+trace_y];
    always @(posedge I_clk) begin
        if(state==BOARD_INIT) board_rows[(build_bank ? GH : 0)+init_row]<=17'd0;
        else if(WHITE_BOARD && phase==TRACE_BOARD && state==POP_USE)
            board_rows[(build_bank ? GH : 0)+trace_y]<={1'b1,
                (!trace_row[16] || trace_x<trace_row[15:8]) ? trace_x : trace_row[15:8],
                (!trace_row[16] || trace_x>trace_row[7:0]) ? trace_x : trace_row[7:0]};
    end
    reg [15:0] bw,bh,hw,hh;
    reg [31:0] box_area,filled;
    reg [15:0] outer_cx2,outer_cy2,inner_cx2,inner_cy2;
    wire [15:0] dx2=outer_cx2>inner_cx2 ? outer_cx2-inner_cx2 : inner_cx2-outer_cx2;
    wire [15:0] dy2=outer_cy2>inner_cy2 ? outer_cy2-inner_cy2 : inner_cy2-outer_cy2;
    wire target_ok=ba>=(COLOR_MODE ? 8 : MIN_AREA_CELLS) && (!WHITE_BOARD || board_found);
    wire [2:0] target_color=PARTS_MODE ? parts_color_choice : (bred>=8 && scale_const(bred,5)>=scale_const(ba,3)) ? 1 :
        (bgreen>=8 && scale_const(bgreen,5)>=scale_const(ba,3)) ? 2 :
        (bblue>=8 && scale_const(bblue,5)>=scale_const(ba,3)) ? 3 :
        (bblack>=8 && scale_const(bblack,5)>=scale_const(ba,3)) ? 4 : 0;
    // Component pixel contact is accumulated during flood fill. A nearby
    // object or rounded-up coarse bounding box cannot set this flag.
    wire at_edge=bclip;
    wire hole_ok=ha>=4 && hl>bl && hr<br && ht>bt && hb<bb &&
                 ({16'd0,second_h}<<2)<=ha;
    wire round_ok=bw>=MIN_DIAM_CELLS && bh>=MIN_DIAM_CELLS &&
        scale_const(bw,4)<=scale_const(bh,5) && scale_const(bh,4)<=scale_const(bw,5) &&
        scale_const(hw,20)>=scale_const(bw,11) && scale_const(hw,20)<=scale_const(bw,17) &&
        scale_const(hh,20)>=scale_const(bh,11) && scale_const(hh,20)<=scale_const(bh,17) &&
        scale_const(dx2,6)<=bw && scale_const(dy2,6)<=bh &&
        scale_const(filled,20)>=scale_const(box_area,13) && scale_const(filled,10)<=scale_const(box_area,9);

    reg candidate;
    reg [2:0] candidate_type,last_type;
    reg [2:0] last_color;
    wire tire_ok=ba>=MIN_AREA_CELLS && hole_ok && round_ok;
    // A colored solid circle: allow a small specular hole, but never a large
    // central hole. Area/circularity gates reject square and elongated caps.
    wire disc_ok=COLOR_MODE && target_color>=1 && target_color<=3 && bw>=4 && bh>=4 &&
        scale_const(bw,4)<=scale_const(bh,5) && scale_const(bh,4)<=scale_const(bw,5) &&
        scale_const(ba,20)>=scale_const(box_area,13) && scale_const(ba,10)<=scale_const(box_area,9) &&
        scale_const(ha,8)<=ba && scale_const(second_h,8)<=ba;
    // Nine-bit modular subtraction also covers grid coordinates above 127.
    // The centre was already registered in FEATURES, before target retrace.
    wire signed [8:0] parts_dx=$signed({queue_q[7:0],1'b0})-$signed(outer_cx2[8:0]);
    wire signed [8:0] parts_dy=$signed({queue_q[15:8],1'b0})-$signed(outer_cy2[8:0]);
    wire parts_done,parts_elongated,parts_round,parts_hex,parts_circle,parts_head,parts_square;
    generate if(PARTS_MODE) begin : g_parts_shape
        img_parts_shape shape(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(state==PART_TRACE),
            .I_point(state==POP_USE && phase==TRACE_TARGET),.I_dx(parts_dx),.I_dy(parts_dy),
            .I_finish(state==COMPONENT && phase==TRACE_TARGET),.O_done(parts_done),
            .O_elongated(parts_elongated),.O_round(parts_round),.O_hex(parts_hex),.O_circle(parts_circle),.O_head(parts_head),.O_square(parts_square));
    end else begin : g_no_parts_shape
        assign parts_done=0;assign parts_elongated=0;assign parts_round=0;
        assign parts_hex=0;assign parts_circle=0;assign parts_head=0;assign parts_square=0;
    end endgenerate
    // Bound the first release to one complete object and a resolvable hole.
    // Small specular holes are tolerated; the dominant aperture may contain
    // shadows and need not have the tire demo's fixed diameter/concentricity.
    wire parts_single=MULTI_TARGETS || ({16'd0,second_b}<<2)<ba;
    wire parts_hole=ha>=6 && hw>=2 && hh>=2 && hl>bl && hr<br && ht>bt && hb<bb &&
        scale_const(ha,32)>=filled && scale_const(ha,5)<=scale_const(filled,4) &&
        ({16'd0,second_h}<<2)<=ha && scale_const(dx2,2)<=bw && scale_const(dy2,2)<=bh;
    // Need at least 12 cells across to resolve the hexagonal outer edge.
    wire parts_compact=bw>=12 && bh>=12 && scale_const(bw,3)<=scale_const(bh,4) &&
        scale_const(bh,3)<=scale_const(bw,4) && scale_const(filled,12)>=scale_const(box_area,7) &&
        scale_const(filled,20)<=scale_const(box_area,18);
    wire screw_ok=PARTS_MODE && parts_single && parts_elongated && parts_head && bw>=2 && bh>=2 &&
        (bw>=12 || bh>=12) && scale_const(ha,8)<=filled;
    wire nut_ok=PARTS_MODE && parts_single && parts_compact && parts_hole && parts_round && parts_hex;
    wire washer_ok=PARTS_MODE && parts_single && parts_compact && parts_hole && parts_round && parts_circle;
    // A rotated square fills about half its axis-aligned box; an unrotated
    // square fills almost all of it. Do not reuse the circular occupancy band.
    wire square_nut_ok=PARTS_MODE && parts_single && parts_hole && parts_round && parts_square &&
        bw>=12 && bh>=12 && scale_const(bw,3)<=scale_const(bh,4) && scale_const(bh,3)<=scale_const(bw,4) &&
        scale_const(filled,16)>=scale_const(box_area,7) && filled<=box_area;
    wire class_ok=PARTS_MODE ? (screw_ok || nut_ok || washer_ok || square_nut_ok) : (tire_ok || disc_ok);
    reg [2:0] result_status;
    reg [7:0] streak;
    reg tracked,armed;
    reg [10:0] last_cx,last_cy;
    wire [10:0] center_x=({3'd0,bl}+{3'd0,br}+11'd1)<<2;
    wire [10:0] center_y=({3'd0,bt}+{3'd0,bb}+11'd1)<<2;
    wire [10:0] motion_x=center_x>last_cx ? center_x-last_cx : last_cx-center_x;
    wire [10:0] motion_y=center_y>last_cy ? center_y-last_cy : last_cy-center_y;
    // A large position jump is a new object, not accumulated confirmation.
    wire same_object=O_valid && motion_x <= (bw<<2)+16 && motion_y <= (bh<<2)+16;
    wire same_class=same_object && candidate_type==last_type && (PARTS_MODE || target_color==last_color);
    wire confirmed=candidate && (CONFIRM_FRAMES<=1 || (same_class && streak>=CONFIRM_FRAMES-1));
    wire multi_done;
    wire [55:0] multi_packet;
    wire [55:0] multi_raw={candidate,candidate_type,color_context_ok ? target_color:3'd0,5'd0,
        {bl,3'b000},{br,3'b111},{bt,3'b000},{bb,3'b111}};
    img_parts_multi_tracker tracker(.I_clk(I_clk),.I_rst_n(I_rst_n),
        .I_batch(MULTI_TARGETS && state==IDLE && frame_done),
        .I_start(MULTI_TARGETS && state==MULTI_MATCH),.I_index(multi_index),.I_packet(multi_raw),
        .I_publish(MULTI_TARGETS && state==MULTI_PUBLISH),.I_epoch(COLOR_CALIBRATION ? I_color_epoch:8'd0),
        .O_done(multi_done),.O_packet(multi_packet));
    function [23:0] bcd_next;
        input [23:0] value;
        integer i;
        reg carry;
        begin
            bcd_next=value; carry=1;
            for(i=0;i<6;i=i+1) if(carry) begin
                if(value[i*4+:4]==9) bcd_next[i*4+:4]=0;
                else begin bcd_next[i*4+:4]=value[i*4+:4]+1'b1; carry=0; end
            end
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_color_diag<=0;capture_epoch<=0;capture_color_ready<=0;
            O_targets<=0;O_target_count<=0;O_target_overflow<=0;
            multi_count<=0;multi_index<=0;multi_overflow<=0;multi_build<=0;
            state<=IDLE; scan<=0; addr<=0; holes_phase<=0; sx<=0; sy<=0;
            phase<=FIND_BOARD;build_bank<=1;init_row<=0;board_found<=0;board_score<=0;
            parts_threshold<=192;hist_index<=8;hist_best<=0;hist_best_bin<=13;
            morph_pass<=0;morph_acc<=0;morph_tap<=0;morph_meta<=0;
            target_seed<=0;target_sx<=0;target_sy<=0;
            board_l<=0;board_r<=0;board_t<=0;board_b<=0;board_sx<=0;board_sy<=0;board_seed<=0;
            O_board_valid<=0;O_board_bank<=0;O_board_x0<=0;O_board_x1<=0;O_board_y0<=0;O_board_y1<=0;
            px<=0; py<=0; nx<=0; ny<=0; direction<=0; head<=0; tail<=0; color<=0;
            ca<=0; ba<=0; ha<=0; second_b<=0; second_h<=0;
            cred<=0;cgreen<=0;cblue<=0;cblack<=0;bred<=0;bgreen<=0;bblue<=0;bblack<=0;
            parts_vote_total<=0;parts_color_choice<=0;color_streak<=0;
            cire<=0;cisi<=0;ciye<=0;cibl<=0;bire<=0;bisi<=0;biye<=0;bibl<=0;ci_count<=0;bi_count<=0;
            vote_red<=0;vote_silver<=0;vote_brass<=0;vote_black<=0;vote_area<=0;inner_fallback<=0;color_reason<=2;
            candidate_type<=0;last_type<=0;last_color<=0;O_color<=0;
            cl<=0; cr<=0; ct<=0; cb<=0;
            cborder<=0; bborder<=0; cclip<=0; bclip<=0;
            bw<=0; bh<=0; hw<=0; hh<=0; box_area<=0; filled<=0;
            outer_cx2<=0; outer_cy2<=0; inner_cx2<=0; inner_cy2<=0;
            candidate<=0; result_status<=5; streak<=0; tracked<=0; armed<=1;
            last_cx<=0; last_cy<=0;
            O_x0<=0;O_x1<=0;O_y0<=0;O_y1<=0;O_cx<=0;O_cy<=0;O_w<=0;O_h<=0;
            O_area<=0;O_type<=0;O_valid<=0;O_upd<=0;O_moving<=0;O_cnt<=0;
            O_span<=0;O_hole<=0;O_hx<=0;O_hy<=0;O_ring_valid<=0;O_status<=5;
        end else begin
            if(capture_valid && capture_user && take) begin
                capture_epoch<=I_color_epoch;capture_color_ready<=I_color_ready;
            end
            case(state)
                IDLE: if(frame_done) begin
                    scan<=0;sx<=0;sy<=0;holes_phase<=0;bclip<=0;ba<=0;ha<=0;second_b<=0;second_h<=0;
                    bborder<=0;multi_count<=0;multi_index<=0;multi_overflow<=0;multi_build<=0;
                    phase<=FIND_BOARD;board_found<=0;board_score<=0;
                    bred<=0;bgreen<=0;bblue<=0;bblack<=0;bire<=0;bisi<=0;biye<=0;bibl<=0;bi_count<=0;
                    build_bank<=~O_board_bank;init_row<=0;
                    hist_index<=8;hist_best<=0;hist_best_bin<=13;
                    state<=PARTS_MODE ? PART_HIST : WHITE_BOARD ? BOARD_INIT : SCAN_REQ;
                end
                PART_HIST: begin
                    if(white_hist[hist_index]>hist_best) begin
                        hist_best<=white_hist[hist_index];hist_best_bin<=hist_index;
                    end
                    if(hist_index==15) begin
                        if(white_hist[15]>hist_best) parts_threshold<=8'd248-PARTS_WHITE_MARGIN;
                        else if(hist_best!=0) parts_threshold<=hist_best_bin<10 ? 8'd128 :
                            {hist_best_bin,4'd8}-PARTS_WHITE_MARGIN;
                    morph_pass<=0;scan<=0;sx<=0;sy<=0;state<=MORPH_CENTER;
                    end else hist_index<=hist_index+1'b1;
                end
                MORPH_CENTER: state<=MORPH_CENTER_WAIT;
                MORPH_CENTER_WAIT: state<=MORPH_CENTER_USE;
                MORPH_CENTER_USE: begin
                    // Metadata stays in map throughout both bit-mask passes.
                    morph_meta<=map_q[7:1];
                    morph_tap<=0;morph_acc<=morph_pass;state<=MORPH_REQ;
                end
                MORPH_REQ: state<=MORPH_WAIT;
                MORPH_WAIT: state<=MORPH_USE;
                MORPH_USE: begin
                    // Dilation reads the captured mask; erosion reads its
                    // scratch result. Keep the established close operation.
                    morph_acc<=morph_pass ? (morph_acc && morph_q) :
                        (morph_acc || map_q[0]);
                    if(morph_tap==8) state<=MORPH_WRITE;
                    else begin morph_tap<=morph_tap+1'b1;state<=MORPH_REQ;end
                end
                MORPH_WRITE: begin
                    if(scan==N-1) begin
                        scan<=0;sx<=0;sy<=0;
                        if(!morph_pass) begin morph_pass<=1;state<=MORPH_CENTER;end
                        else state<=WHITE_BOARD ? BOARD_INIT : SCAN_REQ;
                    end else begin
                        scan<=scan+1'b1;
                        if(sx==GW-1) begin sx<=0;sy<=sy+1'b1;end else sx<=sx+1'b1;
                        state<=MORPH_CENTER;
                    end
                end
                BOARD_INIT: if(init_row==GH-1) state<=SCAN_REQ; else init_row<=init_row+1'b1;
                SCAN_REQ: state<=SCAN_WAIT;
                SCAN_WAIT: state<=SCAN_CHECK;
                SCAN_CHECK: if(start_component) begin
                    cire<=map_q[7] && map_q[6:4]==1 ? 1:0;
                    cisi<=map_q[7] && map_q[6:4]==5 ? 1:0;
                    ciye<=map_q[7] && map_q[6:4]==6 ? 1:0;
                    cibl<=map_q[7] && map_q[6:4]==4 ? 1:0;
                    ci_count<=map_q[7] ? 1:0;
                    cred<=map_q[6:4]==1 ? 1 : 0;
                    cgreen<=map_q[6:4]==(PARTS_MODE ? 5 : 2) ? 1 : 0;
                    cblue<=map_q[6:4]==(PARTS_MODE ? 6 : 3) ? 1 : 0;
                    cblack<=map_q[6:4]==4 ? 1 : 0;
                    color<=map_q[0]; head<=0;tail<=1;ca<=0;
                    cl<=sx;cr<=sx;ct<=sy;cb<=sy;cborder<=0;cclip<=map_q[2];state<=POP_REQ;
                end else if(scan==N-1) begin
                    if(WHITE_BOARD) begin
                        if(phase==FIND_BOARD) begin
                            if(board_found) begin
                                phase<=TRACE_BOARD;scan<=board_seed;sx<=board_sx;sy<=board_sy;state<=SCAN_REQ;
                            end else state<=MULTI_TARGETS ? MULTI_PUBLISH:FEATURES;
                        end else if(phase==FIND_DARK) begin
                            phase<=FIND_HOLES;scan<=0;sx<=0;sy<=0;
                            state<=MULTI_TARGETS ? (multi_count!=0 ? MULTI_LOAD:MULTI_PUBLISH):SCAN_REQ;
                        end else state<=FEATURES;
                    end else if(!holes_phase) begin holes_phase<=1;scan<=0;sx<=0;sy<=0;state<=SCAN_REQ;end
                    else state<=FEATURES;
                end
                else begin
                    scan<=scan+1'b1;
                    if(sx==GW-1) begin sx<=0;sy<=sy+1'b1;end else sx<=sx+1'b1;
                    state<=SCAN_REQ;
                end
                POP_REQ: if(head==tail) state<=COMPONENT; else state<=POP_WAIT;
                POP_WAIT: state<=POP_USE;
                POP_USE: begin
                    px<=queue_q[7:0];py<=queue_q[15:8];head<=head+1'b1;
                    ca<=ca+1'b1;
                    if(queue_q[7:0]<cl) cl<=queue_q[7:0];
                    if(queue_q[7:0]>cr) cr<=queue_q[7:0];
                    if(queue_q[15:8]<ct) ct<=queue_q[15:8];
                    if(queue_q[15:8]>cb) cb<=queue_q[15:8];
                    if(queue_q[7:0]==0 || queue_q[7:0]==GW-1 || queue_q[15:8]==0 || queue_q[15:8]==GH-1) cborder<=1;
                    direction<=0;state<=NB_REQ;
                end
                NB_REQ: begin
                    nx<=direction==0 ? px-1'b1 : direction==1 ? px+1'b1 : px;
                    ny<=direction==2 ? py-1'b1 : direction==3 ? py+1'b1 : py;
                    if(neighbor_ok) state<=NB_WAIT;
                    else if(direction==3) state<=POP_REQ;
                    else direction<=direction+1'b1;
                end
                NB_WAIT: state<=NB_FETCH;
                NB_FETCH: state<=NB_CHECK;
                NB_CHECK: begin
                    if(add_neighbor) begin tail<=tail+1'b1; cclip<=cclip | map_q[2]; end
                    if(add_neighbor) begin
                        if(map_q[7]) begin
                            ci_count<=ci_count+1'b1;
                            if(map_q[6:4]==1) cire<=cire+1'b1;
                            if(map_q[6:4]==5) cisi<=cisi+1'b1;
                            if(map_q[6:4]==6) ciye<=ciye+1'b1;
                            if(map_q[6:4]==4) cibl<=cibl+1'b1;
                        end
                        if(map_q[6:4]==1) cred<=cred+1'b1;
                        if(map_q[6:4]==(PARTS_MODE ? 5 : 2)) cgreen<=cgreen+1'b1;
                        if(map_q[6:4]==(PARTS_MODE ? 6 : 3)) cblue<=cblue+1'b1;
                        if(map_q[6:4]==4) cblack<=cblack+1'b1;
                    end
                    if(WHITE_BOARD && phase==FIND_DARK && map_q[0] && !neighbor_inside) cclip<=1;
                    if(direction==3) state<=POP_REQ;
                    else begin direction<=direction+1'b1;state<=NB_REQ;end
                end
                COMPONENT: begin
                    if(MULTI_TARGETS && phase==FIND_DARK && color && ca>=MIN_AREA_CELLS && !cclip && !cborder) begin
                        if(multi_count<4) begin
                            multi_bounds[multi_count[1:0]]<={cl,cr,ct,cb};
                            multi_area[multi_count[1:0]]<=ca;multi_seed[multi_count[1:0]]<=scan;
                            multi_xy[multi_count[1:0]]<={sy,sx};
                            multi_votes[multi_count[1:0]]<={cred,cgreen,cblue,cblack,cire,cisi,ciye,cibl,ci_count};
                            multi_count<=multi_count+1'b1;
                        end else multi_overflow<=1;
                    end
                    if(WHITE_BOARD && phase==FIND_BOARD) begin
                        // Rank outer extent rather than white area: the tire
                        // may cover most of a small board, leaving a thin rim.
                        if(component_board_ok && component_box>board_score) begin
                            board_found<=1;board_score<=component_box;
                            board_l<=cl;board_r<=cr;board_t<=ct;board_b<=cb;
                            board_seed<=scan;board_sx<=sx;board_sy<=sy;
                        end
                    end else if(WHITE_BOARD && phase==TRACE_BOARD) begin
                        phase<=FIND_DARK;scan<=0;sx<=0;sy<=0;
                    end else if(PARTS_MODE && phase==TRACE_TARGET) begin
                        state<=PART_WAIT;
                    end else if(color) begin
                        if(ca>ba) begin
                            second_b<=ba;ba<=ca;bborder<=cborder;bclip<=cclip;
                            bred<=cred;bgreen<=cgreen;bblue<=cblue;bblack<=cblack;
                            bire<=cire;bisi<=cisi;biye<=ciye;bibl<=cibl;bi_count<=ci_count;
                            target_seed<=scan;target_sx<=sx;target_sy<=sy;
                        end else if(ca>second_b) second_b<=ca;
                    end else if(!cborder && cl>bl && cr<br && ct>bt && cb<bb) begin
                        if(ca>ha) begin second_h<=ha;ha<=ca;end
                        else if(ca>second_h) second_h<=ca;
                    end
                    // Revisit scan seed, now marked; common path advances it.
                    if(!(PARTS_MODE && phase==TRACE_TARGET)) state<=SCAN_REQ;
                end
                FEATURES: begin
                    vote_red<=choose_inner ? bire:bred;vote_silver<=choose_inner ? bisi:bgreen;
                    vote_brass<=choose_inner ? biye:bblue;vote_black<=choose_inner ? bibl:bblack;
                    vote_area<=choose_inner ? bi_count:ba;inner_fallback<=!choose_inner;
                    bw<={8'd0,br}-{8'd0,bl}+16'd1;bh<={8'd0,bb}-{8'd0,bt}+16'd1;
                    hw<={8'd0,hr}-{8'd0,hl}+16'd1;hh<={8'd0,hb}-{8'd0,ht}+16'd1;
                    outer_cx2<={8'd0,bl}+br;outer_cy2<={8'd0,bt}+bb;
                    inner_cx2<={8'd0,hl}+hr;inner_cy2<={8'd0,ht}+hb;
                    filled<={16'd0,ba}+ha; state<=COLOR_TOTAL;
                end
                COLOR_TOTAL: begin
                    parts_vote_total<=chosen_total;state<=DECIDE;
                end
                DECIDE: begin
                    parts_color_choice<=0;color_reason<=0;
                    if(!color_context_ok) color_reason<=1;
                    else if(!target_ok) color_reason<=2;
                    else if(parts_vote_total<8 || scale_const(parts_vote_total,4)<vote_area) color_reason<=3;
                    else if(vote_red>=8 && scale_const(vote_red,5)>=scale_const(parts_vote_total,2) &&
                            {1'b0,vote_red}>={vote_brass,1'b0}) parts_color_choice<=1;
                    else if(vote_brass>=8 && scale_const(vote_brass,5)>=scale_const(parts_vote_total,2) &&
                            {1'b0,vote_brass}>={vote_red,1'b0}) parts_color_choice<=6;
                    else if(vote_silver>=8 && scale_const(vote_silver,5)>=scale_const(parts_vote_total,4)) parts_color_choice<=5;
                    // Black material may contain neutral specular patches.
                    // Require positive dark evidence (>=60%), not absence of hue.
                    else if(vote_black>=8 && scale_const(vote_black,5)>=scale_const(parts_vote_total,3)) parts_color_choice<=4;
                    else color_reason<=4;
                    box_area<=bw*bh;state<=PARTS_MODE && target_ok ? PART_TRACE : PUBLISH;
                end
                PART_TRACE: begin
                    phase<=TRACE_TARGET;scan<=target_seed;sx<=target_sx;sy<=target_sy;state<=SCAN_REQ;
                end
                PART_WAIT: if(parts_done) state<=PUBLISH;
                PUBLISH: begin
                    candidate<=target_ok && !at_edge && class_ok;
                    candidate_type<=PARTS_MODE ? (screw_ok ? 1 : square_nut_ok ? 4 : nut_ok ? 3 : washer_ok ? 2 : 7) :
                        tire_ok ? 6 : disc_ok ? 4 : 7;
                    result_status<=!target_ok ? 3'd1 : at_edge ? 3'd2 : class_ok ? 3'd0 :
                        (COLOR_MODE && target_color!=0) ? 3'd4 : ha<4 ? 3'd6 : ({16'd0,second_h}<<2)>ha ? 3'd7 : !hole_ok ? 3'd3 : 3'd4;
                    state<=14;
                end
                MULTI_LOAD: begin
                    ba<=multi_area[multi_index];second_b<=0;ha<=0;second_h<=0;bclip<=0;bborder<=0;
                    target_seed<=multi_seed[multi_index];{target_sy,target_sx}<=multi_xy[multi_index];
                    {bred,bgreen,bblue,bblack,bire,bisi,biye,bibl,bi_count}<=multi_votes[multi_index];
                    phase<=FIND_HOLES;scan<=0;sx<=0;sy<=0;state<=MULTI_CLEAR;
                end
                MULTI_CLEAR: state<=MULTI_CLEAR_WAIT;
                MULTI_CLEAR_WAIT: state<=MULTI_CLEAR_WRITE;
                MULTI_CLEAR_WRITE: begin
                    if(scan==N-1) begin scan<=0;sx<=0;sy<=0;state<=SCAN_REQ;end
                    else begin scan<=scan+1'b1;state<=MULTI_CLEAR;end
                end
                MULTI_MATCH: state<=MULTI_SAVE;
                MULTI_SAVE: if(multi_done) begin
                    multi_build[multi_index*56+:56]<=multi_packet;
                    if({1'b0,multi_index}+3'd1<multi_count) begin multi_index<=multi_index+1'b1;state<=MULTI_LOAD;end
                    else state<=MULTI_PUBLISH;
                end
                MULTI_PUBLISH: begin
                    O_targets<=multi_build;O_target_count<={2'd0,multi_build[55]}+{2'd0,multi_build[111]}+{2'd0,multi_build[167]}+{2'd0,multi_build[223]};O_target_overflow<=multi_overflow;
                    O_board_valid<=board_found;O_board_bank<=build_bank;
                    O_board_x0<=board_found ? {board_l,3'b000}:0;O_board_x1<=board_found ? {board_r,3'b111}:0;
                    O_board_y0<=board_found ? {board_t,3'b000}:0;O_board_y1<=board_found ? {board_b,3'b111}:0;
                    // Existing diagnostic/compatibility fields refer to slot 0.
                    O_valid<=multi_build[55];O_type<=multi_build[55] ? multi_build[54:52]:0;
                    O_color<=multi_count!=0 ? multi_build[51:49]:0;
                    O_x0<=multi_build[43:33];O_x1<=multi_build[32:22];
                    O_y0<=multi_build[21:11];O_y1<=multi_build[10:0];
                    O_cx<=0;O_cy<=0;O_w<=0;O_h<=0;O_area<=0;
                    O_span<=0;O_hole<=0;O_hx<=0;O_hy<=0;
                    O_status<=multi_count==0 ? 1:0;O_ring_valid<=0;O_moving<=0;
                    O_upd<=~O_upd;state<=IDLE;
                end
                14: if(MULTI_TARGETS) begin
                    // Keep the list private until every slot has finished.
                    if(multi_index==0) O_color_diag<={monitor_rgb[23:0],vote_red,vote_silver,vote_brass,vote_black,vote_area,
                        4'd0,monitor_rgb[31],inner_fallback,target_color,color_context_ok ? color_reason:4'd1,11'd0};
                    state<=MULTI_MATCH;
                end else begin
                    O_board_valid<=WHITE_BOARD && board_found;O_board_bank<=build_bank;
                    O_board_x0<=board_found ? {board_l,3'b000} : 0;
                    O_board_x1<=board_found ? {board_r,3'b111} : 0;
                    O_board_y0<=board_found ? {board_t,3'b000} : 0;
                    O_board_y1<=board_found ? {board_b,3'b111} : 0;
                    O_upd<=~O_upd; O_valid<=target_ok; O_status<=result_status;
                    O_color_diag<={monitor_rgb[23:0],vote_red,vote_silver,vote_brass,vote_black,vote_area,
                        2'd0,monitor_rgb[30:29],monitor_rgb[31],inner_fallback,target_color,
                        !color_context_ok ? 4'd1 : !target_ok ? 4'd2 :
                        target_color==0 ? (color_reason==3 && monitor_rgb[31] ? (monitor_rgb[30] ? 4'd7 : monitor_rgb[29] ? 4'd6:color_reason):color_reason) :
                        !(candidate && same_object && candidate_type==last_type && target_color==last_color && color_streak>=1) ? 4'd5 : 4'd0,
                        11'd0};
                    O_x0<=target_ok ? {bl,3'b000} : 0; O_x1<=target_ok ? {br,3'b111} : 0;
                    O_y0<=target_ok ? {bt,3'b000} : 0; O_y1<=target_ok ? {bb,3'b111} : 0;
                    O_cx<=target_ok ? center_x : 0;O_cy<=target_ok ? center_y : 0;
                    O_w<=target_ok ? bw<<3 : 0;O_h<=target_ok ? bh<<3 : 0;
                    O_area<=target_ok ? {ba,6'd0} : 0;
                    O_type<=!target_ok ? 0 : confirmed ? candidate_type : 7;
                    // Colour confirmation is independent of shape: an
                    // uncertain colour must not hide a correctly found nut.
                    if(PARTS_MODE) begin
                        O_color<=color_context_ok && candidate && same_object && candidate_type==last_type &&
                            target_color!=0 && target_color==last_color && color_streak>=1 ? target_color : 0;
                        color_streak<=!color_context_ok || !candidate || target_color==0 ? 0 :
                            same_object && candidate_type==last_type && target_color==last_color ?
                            (color_streak<3 ? color_streak+1'b1 : color_streak) : 1;
                    end else O_color<=target_ok ? target_color : 0;
                    O_ring_valid<=confirmed && (candidate_type==6 || (PARTS_MODE && (candidate_type==2 || candidate_type==3 || candidate_type==4)));
                    O_span<=confirmed && (candidate_type==6 || (PARTS_MODE && candidate_type!=1)) ? bw<<3 : 0;
                    O_hole<=confirmed && (candidate_type==6 || (PARTS_MODE && candidate_type!=1)) ? hw<<3 : 0;
                    O_hx<=confirmed && (candidate_type==6 || (PARTS_MODE && candidate_type!=1)) ? ({3'd0,hl}+{3'd0,hr}+11'd1)<<2 : 0;
                    O_hy<=confirmed && (candidate_type==6 || (PARTS_MODE && candidate_type!=1)) ? ({3'd0,ht}+{3'd0,hb}+11'd1)<<2 : 0;
                    last_type<=candidate_type;last_color<=target_color;
                    streak<=!candidate ? 0 : !same_class ? 1 : streak<CONFIRM_FRAMES ? streak+1'b1 : streak;
                    O_moving<=confirmed && tracked && same_object && ({1'b0,motion_x}+motion_y>=8);
                    if(confirmed && tracked && same_object && armed && last_cx<LINE_X && center_x>=LINE_X) begin
                        O_cnt<=bcd_next(O_cnt); armed<=0;
                    end else if(!confirmed || !same_object || center_x<LINE_X-LINE_HYST) armed<=1;
                    tracked<=confirmed;last_cx<=center_x;last_cy<=center_y;
                    state<=IDLE;
                end
                default: state<=IDLE;
            endcase
            if(COLOR_CALIBRATION && (!I_color_ready || capture_epoch!=I_color_epoch)) begin
                O_color<=0;color_streak<=0;last_color<=0;
                // An epoch can change after an earlier slot has finished.
                // Override those private votes even on the publication edge.
                if(MULTI_TARGETS) begin
                    O_targets[51:49]<=0;O_targets[107:105]<=0;
                    O_targets[163:161]<=0;O_targets[219:217]<=0;
                end
            end
            if(frame_error && state==IDLE) begin
                O_color_diag<={113'd0,4'd8,11'd0};
                O_targets<=0;O_target_count<=0;O_target_overflow<=0;
                O_board_valid<=0;
                O_valid<=0;O_ring_valid<=0;O_type<=0;O_status<=5;O_upd<=~O_upd;
                O_x0<=0;O_x1<=0;O_y0<=0;O_y1<=0;O_cx<=0;O_cy<=0;O_w<=0;O_h<=0;
                O_area<=0;O_span<=0;O_hole<=0;O_hx<=0;O_hy<=0;O_moving<=0;
                O_color<=0;last_type<=0;last_color<=0;
                color_streak<=0;
                streak<=0;tracked<=0;armed<=1;
            end
        end
    end
endmodule
