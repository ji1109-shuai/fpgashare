`timescale 1ns/1ps
module tb_ae_target;
    reg clk=0,cfg_clk=0,rst_n=0,menu_switch=0;
    reg [3:0] buttons=4'hf;
    always #5 clk=~clk;
    always #7 cfg_clk=~cfg_clk;
    wire auto_en,menu_open,armed,target_upd,adjust_upd,adjust_gain,adjust_up;
    wire [3:0] index;
    wire [4:0] target_level;
    wire count_clear,target_inc,target_dec;
    screen_menu_control #(.DEBOUNCE_CYCLES(3)) menu(
        .clk(clk),.rst_n(rst_n),.I_menu_switch(menu_switch),.I_button_n(buttons),.I_batch_done(1'b0),
        .O_menu_open(menu_open),.O_menu_index(index),.O_ae_auto(auto_en),.O_camera_keys_armed(armed),
        .O_ae_target_level(target_level),.O_ae_target_upd(target_upd),
        .O_count_clear(count_clear),.O_target_inc(target_inc),.O_target_dec(target_dec),
        .O_camera_adjust_toggle(adjust_upd),.O_camera_adjust_gain(adjust_gain),.O_camera_adjust_up(adjust_up));
    reg [7:0] luma=152;
    reg luma_upd=0,valid=1,cfg_done=1;
    wire req,locked;
    wire [15:0] exp,gain;
    wire [24:0] diagnostics;
    ae_set #(.CLK_HZ(1000),.DYNAMIC_TARGET(1)) ae(
        .I_clk(cfg_clk),.I_rst(!rst_n),.I_btn((menu_open || !armed)?4'hf:{buttons[1:0],2'b11}),
        .I_ae_cfg_done(cfg_done),.I_cam_cfg_done(1'b1),.I_auto_enable(auto_en),
        .I_menu_adjust_toggle(adjust_upd),.I_menu_adjust_gain(adjust_gain),.I_menu_adjust_up(adjust_up),
        .I_target_level(target_level),.I_target_upd(target_upd),
        .I_luma(luma),.I_luma_valid(valid),.I_luma_upd(luma_upd),
        .O_ae_req(req),.O_ae(exp),.O_ag(gain),.O_auto_locked(locked),.O_diagnostics(diagnostics));
    integer requests=0,busy=0,n,saved_requests,write_latency=40;
    reg [15:0] write_exp,write_gain;
    reg saved_toggle;
    always @(negedge clk) if(rst_n && index==11 && (count_clear || target_inc || target_dec))
        $fatal(1,"AE Y edit disturbed quota counts or reset");
    always @(posedge cfg_clk) begin
        if(!rst_n) begin requests<=0;busy<=0;cfg_done<=1;end
        else if(req) begin
            if(busy) $fatal(1,"overlapping target-change I2C writes");
            requests<=requests+1;busy<=write_latency;cfg_done<=0;write_exp<=exp;write_gain<=gain;
        end else if(busy) begin
            if(exp!==write_exp || gain!==write_gain) $fatal(1,"target edit corrupted an in-flight write");
            busy<=busy-1;
            if(busy==1) cfg_done<=1;
        end
    end
    task ticks(input integer count);repeat(count) @(negedge clk);endtask
    task key(input integer k);begin buttons[k]=0;ticks(12);buttons[k]=1;ticks(14);end endtask
    task sample(input [7:0] value);
        begin luma=value;ticks(8);luma_upd=~luma_upd;ticks(30);end
    endtask
    task samples(input integer count,input [7:0] value);repeat(count) sample(value);endtask
    task reset_case;
        begin rst_n=0;buttons=4'hf;menu_switch=0;luma_upd=0;valid=1;ticks(10);rst_n=1;ticks(40);end
    endtask
    task target_menu;
        begin
            menu_switch=1;ticks(12);key(0);
            if(index!=14) $fatal(1,"up-wrap missed ACK NG");
            key(1);if(index!=0) $fatal(1,"down-wrap missed VIEW");
            repeat(11) key(1);if(index!=11) $fatal(1,"AE Y row unreachable");
        end
    endtask
    initial begin
        reset_case;
        if(!auto_en || target_level!=19 || ae.target_low!=144 || ae.target_high!=160)
            $fatal(1,"lower default target or power-on AUTO is missing");
        samples(2,152);samples(15,152);ticks(500);
        if(locked) $fatal(1,"locked before sixteen actual measurements");
        valid=0;sample(152);valid=1;samples(15,152);
        if(locked) $fatal(1,"invalid measurement retained partial convergence");
        sample(152);if(!locked || requests) $fatal(1,"sixteen valid default samples failed to lock");
        samples(8,200);if(!locked || requests) $fatal(1,"locked session continued automatic writes");
        $display("PASS default center152 band144..160 needs16 valid observations; idle clocks do not count");

        target_menu;key(2);ticks(40);
        if(!auto_en || locked || target_level!=18 || ae.target_low!=136 || ae.target_high!=152)
            $fatal(1,"editing locked AE target failed to rearm automatically");
        repeat(10) key(2);ticks(40);
        if(target_level!=8 || ae.target_low!=56 || ae.target_high!=72) $fatal(1,"minimum target64 wrong");
        samples(2,64);samples(16,64);if(!locked) $fatal(1,"target64 failed to lock");
        saved_toggle=target_upd;key(2);ticks(40);
        if(target_level!=8 || target_upd!=saved_toggle || !locked) $fatal(1,"minimum clamp emitted a false edit");
        key(3);samples(2,72);samples(16,72);if(!locked || target_level!=9) $fatal(1,"target72 failed");
        repeat(20) key(3);ticks(40);
        if(target_level!=24 || ae.target_low!=184 || ae.target_high!=200 || locked)
            $fatal(1,"maximum target192 or restart failed");
        samples(2,192);samples(16,192);if(!locked) $fatal(1,"target192 failed to lock");
        saved_toggle=target_upd;key(3);ticks(40);
        if(target_upd!=saved_toggle || !locked) $fatal(1,"maximum clamp emitted a false edit");
        $display("PASS menu range64..192 step8, clamp, bundled target CDC and locked-session restart");

        reset_case;write_latency=600;samples(2,152);samples(4,200);ticks(8);
        if(!requests || locked || exp>=2244 || gain!=112)
            $fatal(1,"bright value200 must reduce exposure first exp=%0d gain=%0d",exp,gain);
        target_menu;key(2);ticks(40);
        if(!busy || locked || target_level!=18) $fatal(1,"busy retarget case was not exercised");
        ticks(1000);samples(2,144);samples(16,144);
        if(!locked) $fatal(1,"new target144 failed to converge after a completed write");
        $display("PASS target edit during an in-flight write preserves payload and waits for completion plus N+2");
        saved_requests=requests;samples(12,240);
        if(!locked || requests!=saved_requests) $fatal(1,"retargeted session failed to stop writing");

        menu_switch=0;ticks(12);key(0);ticks(100);
        if(auto_en || locked) $fatal(1,"explicit manual edit failed to retain MAN");
        target_menu;key(2);ticks(80);
        if(auto_en || locked) $fatal(1,"target editing unexpectedly overrode explicit MAN");
        $display("ALL PASS adjustable darker AE target, sixteen-sample lock, automatic retarget and manual ownership");
        $finish;
    end
    initial begin #5000000;$fatal(1,"adjustable AE watchdog");end
endmodule
