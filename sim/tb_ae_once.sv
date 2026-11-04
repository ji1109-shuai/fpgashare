`timescale 1ns/1ps
module tb_ae_once #(
    parameter integer CONFIRM=4, LOCK=8, SETTLE=2
);
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg auto_en=0,luma_valid=1;
    reg [7:0] luma=196;
    reg luma_upd=0,menu_toggle=0,menu_gain=0,menu_up=0;
    reg cam_done=1,cfg_done=1;
    wire req,locked,status_upd;
    wire [15:0] exposure,gain;
    wire [28:0] status;
    integer requests=0,busy_cycles=0,saved_requests,n;
    reg [15:0] saved_exposure,saved_gain;
    ae_set #(.CLK_HZ(1000),.AE_LOW(176),.AE_HIGH(216),.AE_CONFIRM_FRAMES(CONFIRM),
        .AE_LOCK_FRAMES(LOCK),.AE_SETTLE_FRAMES(SETTLE)) dut(
        .I_clk(clk),.I_rst(rst),.I_btn(4'hf),
        .I_ae_cfg_done(cfg_done),.I_cam_cfg_done(cam_done),
        .I_menu_adjust_toggle(menu_toggle),.I_menu_adjust_gain(menu_gain),
        .I_menu_adjust_up(menu_up),.I_auto_enable(auto_en),
        .I_luma(luma),.I_luma_valid(luma_valid),.I_luma_upd(luma_upd),
        .O_ae_req(req),.O_ae(exposure),.O_ag(gain),.O_status(status),
        .O_status_upd(status_upd),.O_auto_locked(locked)
    );
    // Model the real cfg_done high -> low -> high register-write handshake.
    always @(posedge clk) begin
        if(rst) begin cfg_done<=1;busy_cycles<=0;requests<=0;end
        else if(req) begin
            if(busy_cycles!=0) $fatal(1,"overlapping I2C request");
            requests<=requests+1;cfg_done<=0;busy_cycles<=40;
            saved_exposure<=exposure;saved_gain<=gain;
        end else if(busy_cycles!=0) begin
            if(exposure!==saved_exposure || gain!==saved_gain)
                $fatal(1,"I2C payload changed while busy");
            busy_cycles<=busy_cycles-1;
            if(busy_cycles==1) cfg_done<=1;
        end
    end
    task ticks(input integer count);
        repeat(count) begin @(posedge clk);#1;end
    endtask
    task sample(input [7:0] value);
        begin
            @(negedge clk);luma=value;ticks(3);
            @(negedge clk);luma_upd=~luma_upd;ticks(12);
        end
    endtask
    task samples(input integer count,input [7:0] value);
        repeat(count) sample(value);
    endtask
    task reset_case;
        begin
            @(negedge clk);rst=1;auto_en=0;luma_valid=1;
            cam_done=1;menu_toggle=0;menu_gain=0;menu_up=0;luma_upd=0;
            ticks(5);@(negedge clk);rst=0;ticks(8);
        end
    endtask
    task enable_auto;
        begin @(negedge clk);auto_en=1;ticks(8);end
    endtask
    initial begin
        reset_case;
        samples(12,240);
        if(requests!=0 || locked) $fatal(1,"MAN startup adjusted/locked");
        enable_auto;
        samples(SETTLE,196);
        for(n=0;n<LOCK-1;n=n+1) sample(n[0]?176:216);
        if(locked) $fatal(1,"locked before enough complete in-band samples");
        sample(196);
        if(!locked || requests!=0) $fatal(1,"in-band did not lock");
        samples(12,120);samples(12,240);
        luma_valid=0;samples(4,100);luma_valid=1;samples(8,120);
        if(!locked || requests!=0 || exposure!=2244 || gain!=112)
            $fatal(1,"converged exposure changed without explicit re-arm");
        $display("PASS convergence stays locked across light changes and invalid packets");

        auto_en=0;ticks(8);
        if(locked) $fatal(1,"MAN did not clear lock");
        enable_auto;samples(SETTLE,240);samples(CONFIRM,240);ticks(60);
        if(requests!=1 || gain!=112 || exposure!=2212 || locked)
            $fatal(1,"explicit re-arm must reduce exposure before gain exp=%0d gain=%0d",exposure,gain);
        samples(SETTLE,196);samples(LOCK,196);
        if(!locked) $fatal(1,"post-I2C convergence failed");
        $display("PASS explicit MAN/AUTO re-arm and post-I2C settling");

        reset_case;enable_auto;samples(SETTLE,196);
        if(CONFIRM>1) begin
            for(n=0;n<20;n=n+1) sample(n[0]?120:240);
            if(requests!=0 || locked) $fatal(1,"alternating errors accumulated");
        end
        luma_valid=0;samples(10,120);
        if(requests!=0 || locked) $fatal(1,"invalid packets adjusted exposure");
        luma_valid=1;samples(SETTLE,196);
        samples(CONFIRM-1,160);
        if(requests!=0) $fatal(1,"early dark adjustment");
        sample(160);
        // Saturated exposure must use gain for this upward adjustment.
        ticks(60);
        if(requests!=1 || gain!=116 || exposure!=2244)
            $fatal(1,"dark confirmation / gain increase failed");
        $display("PASS directional confirmation and invalid packet guard");

        reset_case;enable_auto;samples(SETTLE,196);
        samples(LOCK-1,196);luma_valid=0;samples(LOCK+3,196);
        if(locked || requests!=0) $fatal(1,"invalid packets allowed convergence");
        luma_valid=1;samples(LOCK-1,196);
        if(locked) $fatal(1,"invalid packet preserved a partial stability count");
        sample(196);if(!locked) $fatal(1,"resume convergence failed");
        // A menu edit has priority, clears LOCK and goes to MAN in production.
        auto_en=0;menu_gain=1;menu_up=0;ticks(5);
        @(negedge clk);menu_toggle=~menu_toggle;ticks(70);
        if(locked || gain!=111 || requests!=1) $fatal(1,"manual override failed");
        samples(12,240);
        if(gain!=111 || requests!=1) $fatal(1,"AUTO overwrote manual value");
        $display("PASS invalid packet discards partial count; manual override persists");

        reset_case;cam_done=0;enable_auto;samples(SETTLE+LOCK+3,196);
        if(locked || requests!=0) $fatal(1,"unconfigured camera counted stable samples");
        cam_done=1;samples(SETTLE,196);luma_valid=0;samples(8,0);luma_valid=1;
        if(locked || requests!=0) $fatal(1,"invalid luma changed exposure");
        samples(CONFIRM,240);
        // Send in-band packets during I2C busy; none may prove convergence.
        samples(2,196);
        if(locked) $fatal(1,"in-flight samples caused a false lock");
        ticks(60);samples(SETTLE,196);samples(LOCK,196);
        if(!locked || requests!=1) $fatal(1,"I2C settle guard failed");
        $display("PASS camera validity, invalid data and in-flight sample guard");

        reset_case;enable_auto;samples(SETTLE,196);samples(CONFIRM,0);ticks(60);
        if(requests!=1 || gain!=128 || locked)
            $fatal(1,"valid dark luma was incorrectly rejected");
        $display("PASS valid black frame can drive automatic brightening");

        reset_case;enable_auto;samples(SETTLE,196);
        // Check lower bounds and ensure a saturated controller never claims
        // convergence when brightness remains outside the dead band.
        samples(1800,248);ticks(60);
        if(exposure!=3 || gain!=16 || locked)
            $fatal(1,"limits / unreachable-target handling failed exp=%0d gain=%0d",exposure,gain);
        saved_requests=requests;samples(50,240);
        if(requests!=saved_requests) $fatal(1,"limit issued redundant I2C writes");
        $display("PASS sensor bounds and no false LOCK at an unreachable target");
        $display("ALL PASS one-shot AE confirm=%0d lock=%0d settle=%0d",CONFIRM,LOCK,SETTLE);
        $finish;
    end
    initial begin #10000000;$fatal(1,"AE watchdog");end
endmodule

module tb_ae_once_single;
    tb_ae_once #(.CONFIRM(1),.LOCK(1),.SETTLE(0)) test();
endmodule
