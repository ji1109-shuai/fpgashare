`timescale 1ns/1ps

// Display-domain regression for conveyor box interpolation.  It checks that a
// confirmed box advances once per HDMI frame, while target replacement and a
// large association jump snap immediately instead of drawing a travelling box.
module tb_box_tracking;
    reg clk=0,rst_n=0,sof=0,toggle=0;
    reg [223:0] targets=0;
    wire [23:0] video;

    hdmi_mixer #(
        .IMG_WIDTH(1280),.IMG_HEIGHT(720),.MULTI_TARGETS(1),
        .BOX_TRACKING(1),.BOX_TRACK_STEP(8),.BOX_TRACK_SNAP(96)
    ) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(1'b0),.I_video_hsync(1'b0),
        .I_video_de(1'b0),.I_video_user(sof),.I_video_last(1'b0),
        .I_debug_status(4'd0),.I_video_rd_data(24'd0),
        .I_bbox_upd(toggle),.I_targets(targets),.I_target_count(3'd1),
        .I_target_overflow(1'b0),.I_meas_upd(1'b0),.I_thresh_upd(1'b0),
        .I_camera_status_upd(1'b0),.I_color_reference_upd(1'b0),
        .I_wb_diag_upd(1'b0),.I_latency_upd(1'b0),.I_roi_upd(1'b0),
        .O_hdmi_data(video)
    );

    always #5 clk=~clk;

    function [55:0] packet;
        input valid;
        input [2:0] shape;
        input [10:0] x0,x1,y0,y1;
        begin packet={valid,shape,3'd5,5'd0,x0,x1,y0,y1}; end
    endfunction

    task publish;
        input [55:0] item;
        begin
            targets={168'd0,item};
            toggle=~toggle;
            repeat(8) @(posedge clk);
        end
    endtask

    task display_frame;
        begin
            @(negedge clk);sof=1;
            @(negedge clk);sof=0;
            repeat(6) @(posedge clk);
            #1;
        end
    endtask

    task expect_x0;
        input [10:0] expected;
        begin
            if(dut.targets_display[43:33]!==expected)
                $fatal(1,"tracked x0 got %0d expected %0d",dut.targets_display[43:33],expected);
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        publish(packet(1'b1,3'd1,11'd100,11'd200,11'd120,11'd220));
        display_frame();expect_x0(11'd100); // first confirmed target snaps in

        publish(packet(1'b1,3'd1,11'd124,11'd224,11'd120,11'd220));
        display_frame();expect_x0(11'd108);
        display_frame();expect_x0(11'd116);
        display_frame();expect_x0(11'd124);

        publish(packet(1'b1,3'd2,11'd140,11'd240,11'd120,11'd220));
        display_frame();expect_x0(11'd140); // shape change means a new target
        publish(packet(1'b1,3'd2,11'd400,11'd500,11'd120,11'd220));
        display_frame();expect_x0(11'd400); // far jump snaps instead of gliding
        publish(56'd0);display_frame();
        if(dut.targets_display[55]) $fatal(1,"removed target remained visible");
        $display("ALL PASS box tracking: frame interpolation, snap and removal");
        $finish;
    end

    initial begin #100000;$fatal(1,"box tracking watchdog");end
endmodule
