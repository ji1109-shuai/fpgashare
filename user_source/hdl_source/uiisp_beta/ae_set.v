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
// Exposure/gain values are manual sensor controls, with no image feedback.
module ae_set #(
    parameter integer CLK_HZ=24000000,
    parameter integer DEBOUNCE_MS=20,HOLD_MS=500,REPEAT_MS=100,CHORD_MS=800,
    parameter integer EXP_DEFAULT=2244,GAIN_DEFAULT=112,EXP_STEP=32,
    parameter integer EXP_MIN=2,EXP_MAX=2244,GAIN_MIN=16,GAIN_MAX=143
)(
    input wire I_clk,I_rst,
    input wire [3:0] I_btn,
    input wire I_ae_cfg_done,I_cam_cfg_done,
    output reg O_ae_req,
    output reg [15:0] O_ae,O_ag,
    // Bundled BCD packet {gain_edit,exposure[4 digits],gain[3 digits]}.
    output reg [28:0] O_status,
    output reg O_status_upd
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
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            btn_sync1<=0;btn_sync2<=0;btn_sample<=0;buttons<=0;previous<=0;
            debounce_count<=0;hold_count<=0;repeat_count<=0;chord_count<=0;
            repeated<=0;chord_lock<=0;chord_toggled<=0;gain_edit<=0;
            step_down<=0;step_up<=0;
        end else begin
            btn_sync1<=~I_btn[3:2];btn_sync2<=btn_sync1;previous<=buttons;
            if(btn_sync2!=btn_sample) begin btn_sample<=btn_sync2;debounce_count<=0;end
            else if(debounce_count<DB_CYCLES) debounce_count<=debounce_count+1'b1;
            else buttons<=btn_sample;
            step_down<=0;step_up<=0;
            if(buttons==3) begin
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
        else if(gain_edit) begin
            if(step_down && desired_ag>GAIN_MIN) desired_ag<=desired_ag-1'b1;
            else if(step_up && desired_ag<GAIN_MAX) desired_ag<=desired_ag+1'b1;
        end else begin
            if(step_down) desired_ae<=desired_ae>EXP_MIN+EXP_STEP ? desired_ae-EXP_STEP : EXP_MIN;
            else if(step_up) desired_ae<=desired_ae<EXP_MAX-EXP_STEP ? desired_ae+EXP_STEP : EXP_MAX;
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
