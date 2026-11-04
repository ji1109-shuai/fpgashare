/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********ae_set �ֶ��������AE ***********
--�汾��1.0
*********************************************************************/

// Runtime manual exposure/gain control; camera configuration clock is 24 MHz.
// Active-low I_btn[2]: down; I_btn[3]: up. Hold both to select EXP/GAIN.
// AUTO is a one-shot calibration: converge using independent image metering,
// then retain exposure/gain until MAN -> AUTO or a target edit re-arms it.
module ae_set #(
    parameter integer CLK_HZ=24000000,
    parameter integer DEBOUNCE_MS=20,HOLD_MS=500,REPEAT_MS=100,CHORD_MS=800,
    parameter integer EXP_DEFAULT=2244,GAIN_DEFAULT=112,EXP_STEP=32,
    // SC500CS V1.8 table 2-2: half-line codes, minimum 3; VTS=1127
    // permits 2*1127-10=2244. Register writes take effect in frame N+2.
    parameter integer EXP_MIN=3,EXP_MAX=2244,GAIN_MIN=16,GAIN_MAX=143,
    // Independent pre-AWB image meter. A wide dead band avoids breathing.
    parameter integer AE_LOW=144,AE_HIGH=160,AE_CONFIRM_FRAMES=4,
    parameter integer AUTO_GAIN_STEP=4,
    parameter integer AE_LOCK_FRAMES=16,AE_SETTLE_FRAMES=2,
    parameter integer DYNAMIC_TARGET=0
)(
    input wire I_clk,I_rst,
    input wire [3:0] I_btn,
    input wire I_ae_cfg_done,I_cam_cfg_done,
    input wire I_menu_adjust_toggle,I_menu_adjust_gain,I_menu_adjust_up,
    input wire I_auto_enable,
    input wire [4:0] I_target_level,
    input wire I_target_upd,
    input wire [7:0] I_luma,
    input wire I_luma_valid,
    input wire I_luma_upd,
    output reg O_ae_req,
    output reg [15:0] O_ae,O_ag,
    // Bundled BCD packet {gain_edit,exposure[4 digits],gain[3 digits]}.
    output reg [28:0] O_status,
    output reg O_status_upd,
    output reg O_auto_locked,
    output reg [24:0] O_diagnostics,
    output reg O_diagnostics_upd
);
    localparam integer DB_CYCLES=CLK_HZ/1000*DEBOUNCE_MS;
    localparam integer HOLD_CYCLES=CLK_HZ/1000*HOLD_MS;
    localparam integer REPEAT_CYCLES=CLK_HZ/1000*REPEAT_MS;
    localparam integer CHORD_CYCLES=CLK_HZ/1000*CHORD_MS;
    reg [1:0] btn_sync1,btn_sync2,btn_sample,buttons,previous;
    reg [25:0] debounce_count,hold_count,repeat_count,chord_count;
    reg repeated,chord_lock,chord_toggled,gain_edit;
    reg step_down,step_up;
    reg [15:0] desired_ae,desired_ag;
    reg transaction_pending,saw_busy;
    (* ASYNC_REG="TRUE" *) reg [1:0] menu_toggle_sync,menu_gain_sync,menu_up_sync;
    (* ASYNC_REG="TRUE" *) reg [1:0] auto_enable_sync,luma_toggle_sync,luma_valid_sync;
    reg [7:0] luma_meta,luma_sync;
    reg menu_toggle_seen;
    reg luma_toggle_seen;
    (* ASYNC_REG="TRUE" *) reg [1:0] target_toggle_sync;
    reg target_toggle_seen;
    reg [4:0] target_level;
    wire target_event=DYNAMIC_TARGET && (target_toggle_sync[1]^target_toggle_seen);
    wire [7:0] target_center={target_level,3'b000};
    wire [7:0] target_low=DYNAMIC_TARGET ? target_center-8'd8 : AE_LOW;
    wire [7:0] target_high=DYNAMIC_TARGET ? target_center+8'd8 : AE_HIGH;
    localparam integer CONFIRM_W=(AE_CONFIRM_FRAMES>1)?$clog2(AE_CONFIRM_FRAMES+1):1;
    localparam integer LOCK_W=(AE_LOCK_FRAMES>1)?$clog2(AE_LOCK_FRAMES+1):1;
    localparam integer SETTLE_W=(AE_SETTLE_FRAMES>0)?$clog2(AE_SETTLE_FRAMES+1):1;
    reg [CONFIRM_W-1:0] auto_confirm_count;
    reg [LOCK_W-1:0] auto_stable_count;
    reg [SETTLE_W-1:0] auto_settle_count;
    reg auto_adjust_pulse,auto_brighter,auto_far;
    wire [15:0] fine_exp_step=(desired_ae>>4)==0 ? 16'd1 :
        (desired_ae>>4)>EXP_STEP ? EXP_STEP : (desired_ae>>4);
    wire [15:0] coarse_exp_step=(desired_ae>>1)==0 ? 16'd1 : (desired_ae>>1);
    wire [15:0] auto_gain_step=auto_far ? AUTO_GAIN_STEP*4 : AUTO_GAIN_STEP;
    wire menu_adjust_event=menu_toggle_sync[1]^menu_toggle_seen;
    wire luma_event=luma_toggle_sync[1]^luma_toggle_seen;
    // At very short exposures adjacent integer shutter codes can straddle
    // the entire +/-8 target band. Detect a real direction reversal there,
    // then trim gain one code at a time instead of cycling EXP 3 <-> 4.
    reg trim_gain,last_adjust_valid,last_adjust_brighter;
    wire short_exp_trim=DYNAMIC_TARGET && desired_ae<=8 &&
        (trim_gain || (last_adjust_valid && last_adjust_brighter!=auto_brighter));
    wire accepted_auto_adjust=auto_enable_sync[1] && !O_auto_locked &&
        !menu_adjust_event && !target_event && auto_adjust_pulse &&
        !transaction_pending && I_cam_cfg_done && I_ae_cfg_done;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin trim_gain<=0;last_adjust_valid<=0;last_adjust_brighter<=0;end
        else if(!auto_enable_sync[1] || menu_adjust_event || target_event || step_down || step_up) begin
            trim_gain<=0;last_adjust_valid<=0;
        end else if(accepted_auto_adjust) begin
            last_adjust_valid<=1;last_adjust_brighter<=auto_brighter;
            if(desired_ae>8) trim_gain<=0;
            else if(last_adjust_valid && last_adjust_brighter!=auto_brighter) trim_gain<=1;
        end
    end
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            btn_sync1<=0;btn_sync2<=0;btn_sample<=0;buttons<=0;previous<=0;
            debounce_count<=0;hold_count<=0;repeat_count<=0;chord_count<=0;
            repeated<=0;chord_lock<=0;chord_toggled<=0;gain_edit<=0;
            step_down<=0;step_up<=0;
            menu_toggle_sync<=0;menu_gain_sync<=0;menu_up_sync<=0;menu_toggle_seen<=0;
            auto_enable_sync<=0;luma_toggle_sync<=0;luma_valid_sync<=0;
            O_auto_locked<=0;
            luma_meta<=0;luma_sync<=0;luma_toggle_seen<=0;
            target_toggle_sync<=0;target_toggle_seen<=0;target_level<=5'd19;
            auto_confirm_count<=0;auto_adjust_pulse<=0;auto_brighter<=0;auto_far<=0;
            auto_stable_count<=0;auto_settle_count<=AE_SETTLE_FRAMES;
        end else begin
            menu_toggle_sync<={menu_toggle_sync[0],I_menu_adjust_toggle};
            menu_gain_sync<={menu_gain_sync[0],I_menu_adjust_gain};
            menu_up_sync<={menu_up_sync[0],I_menu_adjust_up};
            auto_enable_sync<={auto_enable_sync[0],I_auto_enable};
            luma_toggle_sync<={luma_toggle_sync[0],I_luma_upd};
            luma_valid_sync<={luma_valid_sync[0],I_luma_valid};
            luma_meta<=I_luma;luma_sync<=luma_meta;
            target_toggle_sync<={target_toggle_sync[0],I_target_upd};
            // Bundled target is held from a debounced key event until the next.
            if(target_event) begin
                target_toggle_seen<=target_toggle_sync[1];
                if(I_target_level>=8 && I_target_level<=24) target_level<=I_target_level;
            end
            btn_sync1<=~I_btn[3:2];btn_sync2<=btn_sync1;previous<=buttons;
            if(btn_sync2!=btn_sample) begin btn_sample<=btn_sync2;debounce_count<=0;end
            else if(debounce_count<DB_CYCLES) debounce_count<=debounce_count+1'b1;
            else buttons<=btn_sample;
            step_down<=0;step_up<=0;
            auto_adjust_pulse<=0;
            if(luma_event) luma_toggle_seen<=luma_toggle_sync[1];
            // Recognition results and motor settings are not AE prerequisites.
            // MAN/manual input or an explicit target edit re-arms the session.
            if(!auto_enable_sync[1] || menu_adjust_event || step_down || step_up || target_event) begin
                O_auto_locked<=0;auto_confirm_count<=0;auto_stable_count<=0;
                auto_settle_count<=AE_SETTLE_FRAMES;
            end else if(!I_cam_cfg_done || !I_ae_cfg_done || transaction_pending ||
                        desired_ae!=O_ae || desired_ag!=O_ag || auto_adjust_pulse) begin
                auto_confirm_count<=0;auto_stable_count<=0;
                auto_settle_count<=AE_SETTLE_FRAMES;
            end else if(luma_event && !O_auto_locked) begin
                // Drop full measurement packets after each completed I2C
                // update: an old/integrating frame is not convergence proof.
                if(!luma_valid_sync[1]) begin
                    auto_confirm_count<=0;auto_stable_count<=0;
                end else if(auto_settle_count!=0) begin
                    auto_settle_count<=auto_settle_count-1'b1;
                    auto_confirm_count<=0;auto_stable_count<=0;
                end else if(luma_sync>=target_low && luma_sync<=target_high) begin
                    auto_confirm_count<=0;
                    if(auto_stable_count==AE_LOCK_FRAMES-1) begin
                        O_auto_locked<=1;auto_stable_count<=0;
                    end else auto_stable_count<=auto_stable_count+1'b1;
                end else begin
                    auto_stable_count<=0;
                    // Require consecutive samples on the SAME side of the
                    // dead band; alternating dark/bright is not convergence.
                    if(AE_CONFIRM_FRAMES<=1 ||
                            (auto_confirm_count!=0 &&
                             auto_brighter==(luma_sync<target_low) &&
                             auto_confirm_count==AE_CONFIRM_FRAMES-1)) begin
                        auto_confirm_count<=0;auto_adjust_pulse<=1;
                        auto_brighter<=luma_sync<target_low;
                        auto_far<=luma_sync<target_low-32 || luma_sync>target_high+24;
                    end else if(auto_confirm_count==0 || auto_brighter!=(luma_sync<target_low)) begin
                        auto_confirm_count<=1;auto_brighter<=luma_sync<target_low;
                    end else auto_confirm_count<=auto_confirm_count+1'b1;
                end
            end
            if(menu_adjust_event) begin
                menu_toggle_seen<=menu_toggle_sync[1];
                gain_edit<=menu_gain_sync[1];
                step_down<=~menu_up_sync[1];
                step_up<=menu_up_sync[1];
                chord_lock<=0;chord_count<=0;chord_toggled<=0;
                hold_count<=0;repeat_count<=0;repeated<=0;
            end else if(buttons==3) begin
                chord_lock<=1;hold_count<=0;repeat_count<=0;repeated<=0;
                if(!chord_toggled) begin
                    if(chord_count==CHORD_CYCLES-1) begin gain_edit<=~gain_edit;chord_toggled<=1;end
                    else chord_count<=chord_count+1'b1;
                end
            end else if(chord_lock) begin
                if(buttons==0) begin chord_lock<=0;chord_count<=0;chord_toggled<=0;end
            end else if(buttons==0) begin
                if(!repeated) begin step_down<=previous==1;step_up<=previous==2;end
                hold_count<=0;repeat_count<=0;repeated<=0;chord_count<=0;
            end else if(buttons!=previous) begin
                hold_count<=0;repeat_count<=0;repeated<=0;
            end else if(hold_count<HOLD_CYCLES) begin
                hold_count<=hold_count+1'b1;
                if(hold_count==HOLD_CYCLES-1) begin
                    step_down<=buttons==1;step_up<=buttons==2;repeated<=1;
                end
            end else if(repeat_count==REPEAT_CYCLES-1) begin
                repeat_count<=0;step_down<=buttons==1;step_up<=buttons==2;
            end else repeat_count<=repeat_count+1'b1;
        end
    end
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin desired_ae<=EXP_DEFAULT;desired_ag<=GAIN_DEFAULT;end
        else if(step_down || step_up) begin
            // Manual changes have priority.  The menu controller also leaves
            // AUTO when EXP/GAIN is edited, so the chosen value is retained.
            if(gain_edit) begin
                if(step_down && desired_ag>GAIN_MIN) desired_ag<=desired_ag-1'b1;
                else if(step_up && desired_ag<GAIN_MAX) desired_ag<=desired_ag+1'b1;
            end else begin
                if(step_down) desired_ae<=desired_ae>EXP_MIN+EXP_STEP ? desired_ae-EXP_STEP : EXP_MIN;
                else if(step_up) desired_ae<=desired_ae<EXP_MAX-EXP_STEP ? desired_ae+EXP_STEP : EXP_MAX;
            end
        end else if(auto_enable_sync[1] && !O_auto_locked &&
                    !menu_adjust_event && !target_event && auto_adjust_pulse &&
                    !transaction_pending && I_cam_cfg_done && I_ae_cfg_done) begin
            // Exposure is the primary actuator in both directions. Only when
            // the shutter reaches its relevant bound may analogue gain
            // compensate. A bright frame must change EXP before GAIN.
            if(short_exp_trim && ((auto_brighter && desired_ag<GAIN_MAX) || (!auto_brighter && desired_ag>GAIN_MIN))) begin
                desired_ag<=auto_brighter ? desired_ag+1'b1:desired_ag-1'b1;
            end else if(auto_brighter) begin
                if(desired_ae<EXP_MAX) begin
                    // Limit brightening to 1.5x. Doubling a reading around
                    // 140 clips, then the bright-side halving returns to 140:
                    // a permanent two-point cycle at minimum analogue gain.
                    if(auto_far) desired_ae<=desired_ae<EXP_MAX-coarse_exp_step ?
                        desired_ae+coarse_exp_step : EXP_MAX;
                    else desired_ae<=desired_ae<EXP_MAX-fine_exp_step ? desired_ae+fine_exp_step : EXP_MAX;
                end
                else if(desired_ag<GAIN_MAX)
                    desired_ag<=desired_ag<GAIN_MAX-auto_gain_step ? desired_ag+auto_gain_step : GAIN_MAX;
            end else begin
                if(desired_ae>EXP_MIN) begin
                    if(auto_far) desired_ae<=desired_ae>EXP_MIN*2 ? desired_ae>>1 : EXP_MIN;
                    else desired_ae<=desired_ae>EXP_MIN+fine_exp_step ? desired_ae-fine_exp_step : EXP_MIN;
                end else if(desired_ag>GAIN_MIN)
                    desired_ag<=desired_ag>GAIN_MIN+auto_gain_step ? desired_ag-auto_gain_step : GAIN_MIN;
            end
        end
    end
    // Hold a coherent value for the entire I2C register sequence. Wait for
    // done to fall then rise; coalesce adjustments made during a transaction.
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            O_ae<=EXP_DEFAULT;O_ag<=GAIN_DEFAULT;O_ae_req<=0;
            transaction_pending<=0;saw_busy<=0;
        end else begin
            O_ae_req<=0;
            if(transaction_pending) begin
                if(!I_ae_cfg_done) saw_busy<=1;
                if(saw_busy && I_ae_cfg_done) begin transaction_pending<=0;saw_busy<=0;end
            end else if(I_cam_cfg_done && I_ae_cfg_done &&
                (desired_ae!=O_ae || desired_ag!=O_ag)) begin
                O_ae<=desired_ae;O_ag<=desired_ag;O_ae_req<=1;
                transaction_pending<=1;saw_busy<=0;
            end
        end
    end
    // Slow held diagnostic packet for HDMI: luma, valid, configuration done,
    // convergence count, completed runtime I2C sequences, measurement seen.
    reg diag_pending,diag_cam_d,diag_cfg_d,diag_meter_seen;
    reg [7:0] diag_write_count;
    wire [4:0] diag_stable_count=auto_stable_count;
    wire diag_write_done=transaction_pending && saw_busy && I_ae_cfg_done;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            O_diagnostics<=0;O_diagnostics_upd<=0;diag_pending<=0;
            diag_cam_d<=0;diag_cfg_d<=0;diag_meter_seen<=0;diag_write_count<=0;
        end else begin
            diag_cam_d<=I_cam_cfg_done;diag_cfg_d<=I_ae_cfg_done;
            diag_pending<=luma_event || diag_write_done || target_event ||
                (I_cam_cfg_done && !diag_cam_d) || (I_ae_cfg_done && !diag_cfg_d);
            if(luma_event) diag_meter_seen<=1;
            if(diag_write_done) diag_write_count<=diag_write_count+1'b1;
            if(diag_pending) begin
                O_diagnostics<={luma_sync,luma_valid_sync[1],I_cam_cfg_done,
                    I_ae_cfg_done,diag_stable_count,diag_write_count,diag_meter_seen};
                O_diagnostics_upd<=~O_diagnostics_upd;
            end
        end
    end
    // Sequential double-dabble; no combinational decimal division path.
    reg converting,converted_valid;
    reg [4:0] digit_cycle;
    reg [32:0] converted_setting;
    reg [15:0] exposure_shift,gain_shift;
    reg [15:0] exposure_bcd,exposure_adjusted;
    reg [19:0] gain_bcd,gain_adjusted;
    integer d;
    always @* begin
        exposure_adjusted=exposure_bcd;gain_adjusted=gain_bcd;
        for(d=0;d<4;d=d+1) if(exposure_bcd[d*4+:4]>=5)
            exposure_adjusted[d*4+:4]=exposure_bcd[d*4+:4]+4'd3;
        for(d=0;d<5;d=d+1) if(gain_bcd[d*4+:4]>=5)
            gain_adjusted[d*4+:4]=gain_bcd[d*4+:4]+4'd3;
    end
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            converting<=0;converted_valid<=0;digit_cycle<=0;converted_setting<=0;
            exposure_shift<=0;gain_shift<=0;exposure_bcd<=0;gain_bcd<=0;
            O_status<=0;O_status_upd<=0;
        end else if(!converting) begin
            // Advertise only completed register writes, not pending values.
            if(I_cam_cfg_done && I_ae_cfg_done && !transaction_pending && !O_ae_req &&
                (!converted_valid || converted_setting!={gain_edit,O_ae,O_ag})) begin
                converted_setting<={gain_edit,O_ae,O_ag};converting<=1;digit_cycle<=0;
                exposure_shift<=O_ae;gain_shift<=O_ag;exposure_bcd<=0;gain_bcd<=0;
            end
        end else if(digit_cycle<16) begin
            exposure_bcd<={exposure_adjusted[14:0],exposure_shift[15]};exposure_shift<=exposure_shift<<1;
            gain_bcd<={gain_adjusted[18:0],gain_shift[15]};gain_shift<=gain_shift<<1;
            digit_cycle<=digit_cycle+1'b1;
        end else begin
            O_status<={converted_setting[32],exposure_bcd,gain_bcd[11:0]};
            O_status_upd<=~O_status_upd;converting<=0;converted_valid<=1;
        end
    end
endmodule
