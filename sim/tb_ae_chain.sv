`timescale 1ns/1ps
// Real production meter -> CDC/controller -> gain ROM -> register sequencer ->
// bit-level I2C slave -> sensor-register-based synthetic RGB feedback.
// No injected mean and no fake cfg_done/busy pulse in this test.
module tb_ae_chain #(
    parameter integer INITIAL_EXP=2244,LIGHT=100,START_MOTOR=0,NACK_ONCE=0,NACK_BOOT=0,REAL_ISP=0,CSI_INPUT=0,TARGET_LEVEL=19,RETARGET=0,
    parameter integer EXPECT_EXP_CHANGE=1,EXPECT_GAIN_CHANGE=0,PREVIEW_ENHANCE=0
);
    localparam W=REAL_ISP?1280:128,H=REAL_ISP?720:96;
    reg clk=0,cfg_clk=0,rst_n=0,valid=0,sof=0,last=0;
    always #5 clk=~clk;
    always #7 cfg_clk=~cfg_clk;
    reg [95:0] rgb=0;
    reg hs_valid=0;
    reg [15:0] hs_data=0;
    integer csi_native_beats=0,csi_corrected_beats=0;
    wire [7:0] meter;
    wire meter_valid,meter_upd;
    generate if(!REAL_ISP) begin : g_meter
    camera_exposure_meter #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) meter_dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_tdata(rgb),.I_tvalid(valid),
        .I_tuser(sof),.I_tlast(last),.O_luma(meter),.O_valid(meter_valid),.O_upd(meter_upd));
    end else begin : g_full_isp
        wire [39:0] raw_data,isp_data;
        wire isp_valid,isp_sof,isp_last;
        for(genvar p=0;p<4;p=p+1) begin : g_raw
            assign raw_data[p*10+:10]={rgb[(3-p)*24+16+:8],2'b00};
        end
        if(CSI_INPUT) begin : g_csi
            wire frame_start,frame_end,csi_valid,raw_sof,raw_end,raw_valid;
            wire [31:0] csi_data;
            wire [39:0] raw_native,axis_data;
            wire axis_valid,axis_sof,axis_last;
            csi_unpacket_2lane csi(.I_clk(clk),.I_rst_n(rst_n),
                .I_hs_valid(hs_valid),.I_hs_data(hs_data),
                .O_csi_frame_start(frame_start),.O_csi_frame_end(frame_end),
                .O_csi_valid(csi_valid),.O_csi_data(csi_data));
            raw10_unpacket_2lane raw10(.I_clk(clk),.I_rst_n(rst_n),
                .I_csi_frame_start(frame_start),.I_csi_frame_end(frame_end),
                .I_csi_valid(csi_valid),.I_csi_data(csi_data),.I_camera_black_level(10'd0),
                .O_raw10_frame_start(raw_sof),.O_raw10_frame_end(raw_end),
                .O_raw10_valid(raw_valid),.O_raw10_data(raw_native));
            uial2axis #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.INPUT_DATA_WIDTH(40)) axis(
                .I_native_clk(clk),.I_rst_n(rst_n),.I_data(raw_native),
                .I_data_valid(raw_valid),.I_data_start(raw_sof),.I_data_end(raw_end),
                .axis_tvalid(axis_valid),.axis_tuser(axis_sof),.axis_tlast(axis_last),.axis_tdata(axis_data));
            image_correction #(.DATA_WIDTH(40)) correction(.I_clk(clk),.I_rst_n(rst_n),
                .I_raw_data(axis_data),.I_raw_valid(axis_valid),
                .I_raw_frame_start(axis_sof),.I_raw_frame_end(axis_last),
                .O_raw_tdata(isp_data),.O_raw_tvalid(isp_valid),
                .O_raw_tuser(isp_sof),.O_raw_tlast(isp_last),.O_raw_tready(1'b1));
            always @(posedge clk) if(rst_n) begin
                if(raw_valid) csi_native_beats=csi_native_beats+1;
                if(isp_valid) csi_corrected_beats=csi_corrected_beats+1;
            end
        end else begin : g_direct
            assign isp_data=raw_data;
            assign isp_valid=valid;
            assign isp_sof=sof;
            assign isp_last=last;
        end
        isp_top #(.TIRE_MODE(1),.PARTS_MODE(1),.VIDEO_MODES(1),
            .AUTO_WHITE_BALANCE(1),.MULTI_TARGETS(1)) isp(
            .axi4s_video_aclk(clk),.I_rst_n(rst_n),.I_tlast(isp_last),.I_tuser(isp_sof),
            .I_tdata(isp_data),.I_tvalid(isp_valid),.I_tdest(10'd0),.O_tready(1'b1),
            .I_bin_en(PREVIEW_ENHANCE!=0),.I_morph_mode(PREVIEW_ENHANCE ? 2'd3:2'd0),.I_awb_freeze(1'b0),
            .I_enhance_strength(2'd2),.I_enhance_noise(4'd4),.I_enhance_compare(1'b0),
            .I_camera_status(29'd0),.I_camera_status_upd(1'b0),
            .O_ae_luma(meter),.O_ae_valid(meter_valid),.O_ae_upd(meter_upd));
    end endgenerate
    reg menu_switch=0;
    reg [3:0] buttons=4'hf;
    wire menu_open,auto_enable,camera_keys_armed,target_upd;
    wire [4:0] target_level;
    wire [3:0] menu_index;
    wire [2:0] motor_level;
    wire adjust_toggle,adjust_gain,adjust_up;
    screen_menu_control #(.DEBOUNCE_CYCLES(3)) menu(
        .clk(clk),.rst_n(rst_n),.I_menu_switch(menu_switch),.I_button_n(buttons),
        .I_batch_done(1'b0),.O_menu_open(menu_open),.O_menu_index(menu_index),
        .O_ae_auto(auto_enable),.O_motor_level(motor_level),
        .O_camera_keys_armed(camera_keys_armed),
        .O_ae_target_level(target_level),.O_ae_target_upd(target_upd),
        .O_camera_adjust_toggle(adjust_toggle),.O_camera_adjust_gain(adjust_gain),
        .O_camera_adjust_up(adjust_up));
    wire req,locked,cam_done,ae_done;
    wire [15:0] exposure,gain;
    ae_set #(.CLK_HZ(1000),.EXP_DEFAULT(INITIAL_EXP),.DYNAMIC_TARGET(1)) ae(
        .I_clk(cfg_clk),.I_rst(!rst_n),.I_btn((menu_open || !camera_keys_armed)?4'hf:{buttons[1:0],2'b11}),
        .I_ae_cfg_done(ae_done),.I_cam_cfg_done(cam_done),
        .I_menu_adjust_toggle(adjust_toggle),.I_menu_adjust_gain(adjust_gain),
        .I_menu_adjust_up(adjust_up),.I_auto_enable(auto_enable),
        .I_target_level(target_level),.I_target_upd(target_upd),
        .I_luma(meter),.I_luma_valid(meter_valid),.I_luma_upd(meter_upd),
        .O_ae_req(req),.O_ae(exposure),.O_ag(gain),.O_auto_locked(locked));
    wire scl;
    tri1 sda;
    uicfgcs500 #(.CLK_DIV(7)) camera(
        .I_clk(cfg_clk),.I_rst_n(rst_n),.I_ae_req(req),.I_ae(exposure),.I_ag(gain),
        .O_cam_scl(scl),.IO_cam_sda(sda),.O_cfg_done(cam_done),.O_ae_cfg_done(ae_done));

    // Open-drain, independently decoded 4-byte I2C transactions.
    reg ack=0,in_transaction=0;
    reg nack_done=0,rejected=0;
    integer retries=0;
    assign sda=ack?1'b0:1'bz;
    integer bit_count=0,byte_count=0,transactions=0,ae_sequences=0,requests=0;
    integer good_transactions=0;
    reg [7:0] shift=0,bytes[0:3];
    reg [7:0] eh=0,em=8'h8c,el=8'h60,gh=8'h1f,gl=8'h20,mode=0;
    wire [15:0] sensor_exp={eh[3:0],em,el[7:4]};
    reg [15:0] delayed_exp=2246,applied_exp=2246;
    reg [15:0] delayed_gain=16'h1f20,applied_gain=16'h1f20;
    wire [7:0] applied_gh=applied_gain[15:8];
    wire [3:0] coarse=applied_gh==8'h03 ? 4'd1:applied_gh==8'h07 ? 4'd2:
        applied_gh==8'h0f ? 4'd4:applied_gh==8'h1f ? 4'd8:4'd0;
    always @(negedge sda) if(scl===1'b1 && !ack && rst_n) begin
        if(in_transaction) $fatal(1,"unexpected repeated START");
        in_transaction=1;bit_count=0;byte_count=0;shift=0;rejected=0;
    end
    always @(posedge scl) if(in_transaction) begin
        if(bit_count<8) begin shift={shift[6:0],sda};bit_count=bit_count+1;end
        else if(bit_count==8) begin
            if(sda!==0 && !(rejected && byte_count==3)) $fatal(1,"slave ACK was not sampled");
            if(byte_count<4) bytes[byte_count]=shift;
            byte_count=byte_count+1;bit_count=9;
        end
    end
    always @(negedge scl) if(in_transaction) begin
        if(bit_count==8) begin
            if(NACK_ONCE && (requests>0 || NACK_BOOT) && !nack_done && byte_count==3) begin
                ack=0;nack_done=1;rejected=1;
            end else ack=1;
        end
        else if(bit_count==9) begin ack=0;bit_count=0;shift=0;end
    end
    always @(posedge sda) if(scl===1'b1 && in_transaction && !ack) begin
        in_transaction=0;
        if(byte_count!=4 || bytes[0]!=8'h6c)
            $fatal(1,"I2C transaction corrupt bytes=%0d address=%h",byte_count,bytes[0]);
        transactions=transactions+1;
        if(rejected) retries=retries+1;
        else begin
        good_transactions=good_transactions+1;
        case({bytes[1],bytes[2]})
            16'h3e00:eh=bytes[3];16'h3e01:em=bytes[3];16'h3e02:el=bytes[3];
            16'h3e08:gh=bytes[3];16'h3e09:gl=bytes[3];16'h3e03:mode=bytes[3];
        endcase
        end
    end
    reg prev_done=0;
    integer expected_code;
    reg [15:0] previous_exp,previous_gain;
    integer exposure_changes=0,gain_changes=0;
    always @(posedge cfg_clk) if(rst_n) begin
        if(req) requests=requests+1;
        if(cam_done && good_transactions<122) $fatal(1,"initialization skipped a NACK register");
        if(ae_done && !prev_done) begin
            if(good_transactions!=122+5*(ae_sequences+1))
                $fatal(1,"AE completion skipped/duplicated acknowledged registers: good=%0d seq=%0d rejected=%0d",good_transactions,ae_sequences,retries);
            expected_code=(((1<<(((gain-16)/32)+2))-1)<<8) | (32+(gain-16)%32);
            if(sensor_exp!==exposure || {gh,gl}!==expected_code[15:0] || mode[3:0]!=4'hb)
                $fatal(1,"actual I2C registers disagree exp=%0d/%0d gain=%h/%h mode=%h",
                    sensor_exp,exposure,{gh,gl},expected_code[15:0],mode);
            if(ae_sequences>0) begin
                if(sensor_exp!=previous_exp && gain!=previous_gain)
                    $fatal(1,"one automatic step changed both exposure and gain");
                if(gain<previous_gain && sensor_exp!=3 && !(sensor_exp<=8 && ae.trim_gain && previous_gain-gain==1))
                    $fatal(1,"gain reduced before exposure reached minimum exp=%0d gain=%0d",sensor_exp,gain);
                if(gain>previous_gain && sensor_exp!=2244 && !(sensor_exp<=8 && ae.trim_gain && gain-previous_gain==1))
                    $fatal(1,"gain increased before exposure reached maximum exp=%0d gain=%0d",sensor_exp,gain);
                if(sensor_exp!=previous_exp) exposure_changes=exposure_changes+1;
                if(gain!=previous_gain) gain_changes=gain_changes+1;
                $display("I2C AE complete seq=%0d decoded_EXP=%0d previous_EXP=%0d GAIN=%0d previous_GAIN=%0d",ae_sequences,sensor_exp,previous_exp,gain,previous_gain);
            end
            previous_exp=sensor_exp;previous_gain=gain;
            ae_sequences=ae_sequences+1;
        end
        prev_done=ae_done;
        if(locked && (!meter_valid || !cam_done || !ae_done)) $fatal(1,"false convergence");
    end
    task ticks(input integer n);repeat(n) @(negedge clk);endtask
    task key(input integer k);begin buttons[k]=0;ticks(10);buttons[k]=1;ticks(12);end endtask
    integer scene_light=LIGHT;
    function [23:0] sensor_pixel(input integer px,input integer py);
        longint unsigned g;
        begin
            g=scene_light;
            g=(g*applied_exp*coarse*applied_gain[7:0])/(2244*32);
            if(g>255) g=255;
            // A dark part occupies the OLD centre meter. It must not stop AE
            // or dominate the independent spatial percentile statistic.
            if(px>=W/2-(REAL_ISP?32:16) && px<W/2+(REAL_ISP?32:16) &&
               py>=H/2-(REAL_ISP?32:16) && py<H/2+(REAL_ISP?32:16)) g=0;
            sensor_pixel={g[7:0],g[7:0],g[7:0]};
        end
    endfunction
    function [7:0] csi_raw_byte(input integer byte_index,input integer py);
        reg [23:0] color;
        begin
            if(byte_index%5==4) csi_raw_byte=0;
            else begin
                color=sensor_pixel((byte_index/5)*4+byte_index%5,py);
                csi_raw_byte=color[23:16];
            end
        end
    endfunction
    task hs_word(input [15:0] word_value);
        begin @(negedge clk);hs_valid=1;hs_data=word_value;end
    endtask
    task hs_idle(input integer cycles);
        begin @(negedge clk);hs_valid=0;hs_data=0;ticks(cycles);end
    endtask
    task csi_short(input [7:0] data_type);
        begin hs_word({data_type,8'd0});hs_word(16'd0);hs_idle(32);end
    endtask
    integer x,y,lane,frames=0;
    task frame;
        integer native_before,corrected_before;
        begin
            native_before=csi_native_beats;corrected_before=csi_corrected_beats;
            @(negedge clk);sof=1;valid=0;last=0;
            // Datasheet section 2.2.2: writes during N become image data in
            // N+2. Use only acknowledged bus-decoded registers, held per frame.
            applied_exp=delayed_exp;applied_gain=delayed_gain;
            delayed_exp=sensor_exp;delayed_gain={gh,gl};
            // Multi-clock early SOF is a real supported upstream convention.
            ticks(3);sof=0;ticks(20);
            if(CSI_INPUT) begin
                csi_short(8'h00);
                for(y=0;y<H;y=y+1) begin
                    hs_word({8'h2b,8'h40});hs_word(16'h0600); // 1600 RAW10 bytes
                    for(x=0;x<W*5/4;x=x+2)
                        hs_word({csi_raw_byte(x,y),csi_raw_byte(x+1,y)});
                    hs_word(16'd0); // CRC payload, not image pixels
                    hs_idle(600+(y%3)*256);
                end
                csi_short(8'h01);
            end else begin
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+4) begin
                    @(negedge clk);valid=1;last=(x==W-4);
                    for(lane=0;lane<4;lane=lane+1) rgb[(3-lane)*24+:24]=sensor_pixel(x+lane,y);
                end
                @(negedge clk);valid=0;last=0;ticks(REAL_ISP?100:2);
            end
            end
            ticks(REAL_ISP?2000:32);frames=frames+1;
            if(CSI_INPUT && (csi_native_beats-native_before!=W*H/4 ||
                            csi_corrected_beats-corrected_before!=W*H/4))
                $fatal(1,"CSI/correction frame truncated native=%0d corrected=%0d expected=%0d",csi_native_beats-native_before,csi_corrected_beats-corrected_before,W*H/4);
            if(CSI_INPUT && frames>=3 && !meter_valid)
                $fatal(1,"complete CSI frames failed to produce valid exposure measurements");
            if(CSI_INPUT) $display("CSI AE frame=%0d valid=%b luma=%0d cfg=%b/%b exp=%0d gain=%0d locked=%b",frames,meter_valid,meter,cam_done,ae_done,exposure,gain,locked);
        end
    endtask
    integer before_requests,first_valid=-1;
    reg dark_seen=0;
    reg [15:0] locked_exp,locked_gain;
    initial begin
        ticks(8);rst_n=1;ticks(20);
        if(!auto_enable || menu_switch || buttons!=4'hf) $fatal(1,"power-on requires an AUTO key press");
        if(TARGET_LEVEL!=19) begin
            menu_switch=1;ticks(12);repeat(11) key(1);
            if(TARGET_LEVEL<19) repeat(19-TARGET_LEVEL) key(2);
            else repeat(TARGET_LEVEL-19) key(3);
            menu_switch=0;ticks(20);
            if(target_level!=TARGET_LEVEL || !auto_enable) $fatal(1,"target menu setup failed");
        end
        if(START_MOTOR) begin
            menu_switch=1;ticks(10);key(1);key(3);
            if(motor_level!=1 || !auto_enable) $fatal(1,"motor setup disabled AE");
            menu_switch=0;ticks(10);
        end
        while(!locked && frames<360) begin
            frame;
            if(cam_done && ae_done && meter_valid && first_valid<0) first_valid=meter;
            if(cam_done && ae_done && meter_valid && meter<16) dark_seen=1;
        end
        if(!locked || frames>=180 || requests==0 || ae_sequences<2)
            $fatal(1,"pixel/I2C loop failed frames=%0d meter=%0d valid=%b exp=%0d gain=%0d requests=%0d cfg=%b/%b txn=%0d sensor=%0d/%h%h index=%0d state=%0d bus=%b i2c=%0d",frames,meter,meter_valid,exposure,gain,requests,cam_done,ae_done,transactions,sensor_exp,gh,gl,camera.reg_index,camera.TS_S,camera.iic_busy,camera.uii2c_inst.IIC_S);
        if(INITIAL_EXP==32 && !dark_seen) $fatal(1,"dark-start regression did not exercise luma<16");
        if(NACK_ONCE && retries!=1) $fatal(1,"NACK/retry case was not exercised");
        if(meter<target_level*8-8 || meter>target_level*8+8)
            $fatal(1,"locked outside selected brightness target meter=%0d target=%0d",meter,target_level*8);
        if(EXPECT_EXP_CHANGE && exposure_changes==0)
            $fatal(1,"no runtime exposure register change was observed on the actual I2C bus");
        if(EXPECT_GAIN_CHANGE && gain_changes==0)
            $fatal(1,"exposure boundary case failed to exercise gain fallback");
        if(RETARGET) begin
            before_requests=requests;
            menu_switch=1;ticks(12);repeat(11) key(1);repeat(11) key(2);menu_switch=0;ticks(20);
            if(locked || !auto_enable || target_level!=8) $fatal(1,"locked live I2C loop did not rearm on target edit");
            while(!locked && frames<360) frame;
            if(!locked || requests<=before_requests || meter<48 || meter>80)
                $fatal(1,"live I2C retarget failed meter=%0d frames=%0d",meter,frames);
            $display("PASS real I2C retarget center152 to64 without MAN/AUTO toggle");
        end
        before_requests=requests;locked_exp=exposure;locked_gain=gain;
        scene_light=LIGHT/8;
        repeat(12) frame;
        if(!locked || requests!=before_requests || exposure!=locked_exp || gain!=locked_gain)
            $fatal(1,"converged loop kept adjusting");
        $display("ALL PASS REAL AE CHAIN raw_isp=%0d csi_input=%0d exp_init=%0d light=%0d motor=%0d frames=%0d first_luma=%0d I2C_sequences=%0d locked_exp=%0d gain=%0d exposure_changes=%0d gain_changes=%0d",REAL_ISP,CSI_INPUT,INITIAL_EXP,LIGHT,START_MOTOR,frames,first_valid,ae_sequences,locked_exp,locked_gain,exposure_changes,gain_changes);
        $finish;
    end
    initial begin #(REAL_ISP?2000000000:200000000);$fatal(1,"real AE chain watchdog");end
endmodule
module tb_ae_full_system;
    tb_ae_chain #(.REAL_ISP(1)) test();
endmodule
module tb_ae_csi_system;
    // Full 720p CSI integration uses a clipped scene that needs a real EXP
    // write before convergence. The fast pixel/I2C tests cover longer paths.
    tb_ae_chain #(.REAL_ISP(1),.CSI_INPUT(1),.LIGHT(32)) test();
endmodule
module tb_ae_csi_enhance;
    tb_ae_chain #(.REAL_ISP(1),.CSI_INPUT(1),.LIGHT(32),.PREVIEW_ENHANCE(1)) test();
endmodule
module tb_ae_chain_nack;
    tb_ae_chain #(.NACK_ONCE(1)) test();
endmodule
module tb_ae_chain_boot_nack;
    tb_ae_chain #(.NACK_ONCE(1),.NACK_BOOT(1)) test();
endmodule
module tb_ae_chain_dark;
    tb_ae_chain #(.INITIAL_EXP(32)) test();
endmodule
module tb_ae_chain_midlight;
    tb_ae_chain #(.LIGHT(285)) test();
endmodule
module tb_ae_chain_extreme;
    tb_ae_chain #(.LIGHT(10000)) test();
endmodule
module tb_ae_chain_gain_low;
    tb_ae_chain #(.LIGHT(40000),.EXPECT_GAIN_CHANGE(1)) test();
endmodule
module tb_ae_chain_gain_high;
    tb_ae_chain #(.LIGHT(10),.EXPECT_EXP_CHANGE(0),.EXPECT_GAIN_CHANGE(1)) test();
endmodule
module tb_ae_chain_motor;
    tb_ae_chain #(.START_MOTOR(1)) test();
endmodule

module tb_ae_meter;
    reg clk=0,rst_n=0,valid=0,sof=0,last=0;
    reg [95:0] rgb=0;
    wire [7:0] luma;wire good,upd;
    always #5 clk=~clk;
    camera_exposure_meter #(.IMG_WIDTH(128),.IMG_HEIGHT(96)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_tdata(rgb),.I_tvalid(valid),.I_tuser(sof),
        .I_tlast(last),.O_luma(luma),.O_valid(good),.O_upd(upd));
    integer x,y;
    task ticks(input integer n);repeat(n) @(negedge clk);endtask
    task shot(input [23:0] color,input integer rows,input integer corrupt,input integer expect_good,input integer expect_luma);
        begin
            sof=1;ticks(3);sof=0;ticks(20);
            for(y=0;y<rows;y=y+1) begin
                for(x=0;x<128;x=x+4) begin
                    @(negedge clk);valid=1;last=(x==124) || (corrupt && x==60 && y==16);
                    // Other lanes deliberately disagree: verify canonical lane.
                    rgb={color,72'h00ff0000ff0000ff00};
                end
                @(negedge clk);valid=0;last=0;ticks(2);
            end
            ticks(2);sof=1;ticks(3);sof=0;ticks(20);
            if(good!==expect_good[0] || (expect_good && luma!==expect_luma[7:0]))
                $fatal(1,"meter color=%h rows=%0d corrupt=%0d good=%b luma=%0d",color,rows,corrupt,good,luma);
        end
    endtask
    initial begin
        ticks(4);rst_n=1;ticks(2);
        shot(24'h000000,96,0,1,8);shot(24'hffffff,96,0,1,248);
        shot(24'h404040,96,0,1,72);shot(24'hff0000,96,0,1,56);
        shot(24'h00ff00,96,0,1,120);shot(24'h0000ff,96,0,1,56);
        shot(24'hc8c8c8,48,0,0,0);shot(24'hc8c8c8,96,1,0,0);
        shot(24'hc8c8c8,96,0,1,200);
        $display("ALL PASS independent AE meter: real dark/clip, RGB lane/weights, early SOF, partial/corrupt rejection and recovery");$finish;
    end
    initial begin #10000000;$fatal(1,"meter watchdog");end
endmodule

module tb_ae_chain_target_low; tb_ae_chain #(.TARGET_LEVEL(8)) test(); endmodule
module tb_ae_chain_target_high; tb_ae_chain #(.TARGET_LEVEL(24)) test(); endmodule
module tb_ae_chain_retarget; tb_ae_chain #(.RETARGET(1)) test(); endmodule
