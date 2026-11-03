`timescale 1ns/1ps
module tb_ae_boot_keys #(parameter integer LEGACY=0);
    reg clk=0,rst_n=0;
    // KEY1 is low while board inputs settle at power-on, then released.
    reg [3:0] buttons=4'b1110;
    wire auto_enable,menu_open,armed,req;
    wire [15:0] exp,gain;
    wire [3:0] camera_keys=(menu_open || !armed)?4'hf:{buttons[1:0],2'b11};
    always #5 clk=~clk;
    generate if(!LEGACY) begin : g_fixed
    screen_menu_control #(.DEBOUNCE_CYCLES(4)) menu(
        .clk(clk),.rst_n(rst_n),.I_menu_switch(1'b0),.I_button_n(buttons),
        .I_batch_done(1'b0),.O_menu_open(menu_open),.O_ae_auto(auto_enable),
        .O_camera_keys_armed(armed));
    end else begin : g_legacy
        assign armed=1'b1;
        screen_menu_control #(.DEBOUNCE_CYCLES(4)) menu(
            .clk(clk),.rst_n(rst_n),.I_menu_switch(1'b0),.I_button_n(buttons),
            .I_batch_done(1'b0),.O_menu_open(menu_open),.O_ae_auto(auto_enable));
    end endgenerate
    ae_set #(.CLK_HZ(1000)) ae(
        .I_clk(clk),.I_rst(!rst_n),.I_btn(camera_keys),
        .I_ae_cfg_done(1'b1),.I_cam_cfg_done(1'b1),
        .I_menu_adjust_toggle(1'b0),.I_menu_adjust_gain(1'b0),.I_menu_adjust_up(1'b0),
        .I_auto_enable(auto_enable),.I_luma(8'd0),.I_luma_valid(1'b0),.I_luma_upd(1'b0),
        .O_ae_req(req),.O_ae(exp),.O_ag(gain));
    task ticks(input integer n);repeat(n) @(negedge clk);endtask
    initial begin
        ticks(5);rst_n=1;
        ticks(600);
        if(!auto_enable || exp!=2244 || gain!=112 || armed)
            $fatal(1,"startup key level forced MAN/manual values auto=%b exp=%0d gain=%0d armed=%b",auto_enable,exp,gain,armed);
        buttons=4'hf;ticks(80);
        if(!auto_enable || !armed) $fatal(1,"release failed to retain AUTO and arm camera keys");
        buttons[0]=0;ticks(80);buttons[0]=1;ticks(80);
        if(auto_enable || exp!=2212)
            $fatal(1,"fresh manual key failed auto=%b exp=%0d",auto_enable,exp);
        $display("ALL PASS startup key held/settling does not force MAN; debounced release arms fresh explicit manual takeover");
        $finish;
    end
endmodule
module tb_ae_boot_keys_legacy;
    tb_ae_boot_keys #(.LEGACY(1)) test();
endmodule
