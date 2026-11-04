`timescale 1ns/1ps

module tb_screen_menu;
    reg clk=1'b0;
    reg rst_n=1'b0;
    reg menu_switch=1'b0;
    reg [3:0] button_n=4'hf;
    reg batch_done=1'b0;
    wire menu_open;
    wire [3:0] menu_index;
    wire [2:0] preview_mode;
    wire [2:0] motor_level;
    wire awb_freeze;
    wire ae_auto;
    wire [2:0] target_type;
    wire target_inc,target_dec,count_clear;
    wire camera_adjust_toggle,camera_adjust_gain,camera_adjust_up;

    integer errors=0;
    integer inc_pulses=0;
    always #5 clk=~clk;
    always @(posedge clk) if(rst_n && target_inc) inc_pulses=inc_pulses+1;

    screen_menu_control #(.DEBOUNCE_CYCLES(3)) dut(
        .clk(clk),.rst_n(rst_n),.I_menu_switch(menu_switch),
        .I_button_n(button_n),.I_batch_done(batch_done),
        .O_menu_open(menu_open),.O_menu_index(menu_index),
        .O_preview_mode(preview_mode),.O_motor_level(motor_level),
        .O_awb_freeze(awb_freeze),.O_ae_auto(ae_auto),.O_target_type(target_type),
        .O_target_inc(target_inc),.O_target_dec(target_dec),
        .O_count_clear(count_clear),
        .O_camera_adjust_toggle(camera_adjust_toggle),
        .O_camera_adjust_gain(camera_adjust_gain),
        .O_camera_adjust_up(camera_adjust_up)
    );

    task wait_clocks;
        input integer count;
        integer n;
        begin
            for(n=0;n<count;n=n+1) @(posedge clk);
            #1;
        end
    endtask

    task press_key;
        input integer key_number;
        begin
            button_n[key_number]=1'b0;
            wait_clocks(9);
            button_n[key_number]=1'b1;
            wait_clocks(9);
        end
    endtask

    task expect3;
        input [8*24-1:0] label;
        input [2:0] actual;
        input [2:0] expected;
        begin
            if(actual!==expected) begin
                $display("FAIL %-24s actual=%0d expected=%0d",label,actual,expected);
                errors=errors+1;
            end else $display("PASS %-24s value=%0d",label,actual);
        end
    endtask

    task expect4;
        input [8*24-1:0] label;
        input [3:0] actual;
        input [3:0] expected;
        begin
            if(actual!==expected) begin
                $display("FAIL %-24s actual=%0d expected=%0d",label,actual,expected);
                errors=errors+1;
            end else $display("PASS %-24s value=%0d",label,actual);
        end
    endtask

    task expect1;
        input [8*24-1:0] label;
        input actual;
        input expected;
        begin
            if(actual!==expected) begin
                $display("FAIL %-24s actual=%0d expected=%0d",label,actual,expected);
                errors=errors+1;
            end else $display("PASS %-24s value=%0d",label,actual);
        end
    endtask

    initial begin
        wait_clocks(4);
        rst_n=1'b1;
        wait_clocks(4);

        menu_switch=1'b1;
        wait_clocks(5);
        expect1("menu opens",menu_open,1'b1);
        expect4("cursor starts at VIEW",menu_index,4'd0);

        // KEY4: increment preview once; a held key must not repeat.
        press_key(3);
        expect3("preview increments once",preview_mode,3'd0);

        // KEY2 selects MOTOR; KEY4 selects 50 percent (level 1).
        press_key(1);
        expect4("cursor MOTOR",menu_index,4'd1);
        press_key(3);
        expect3("motor level 50 percent",motor_level,3'd1);

        // KEY2 selects AWB; KEY4 toggles freeze.
        press_key(1);
        expect4("cursor AWB",menu_index,4'd2);
        press_key(3);
        expect1("AWB freeze toggled",awb_freeze,1'b1);

        // Power-on AUTO must work without a menu/key action.
        press_key(1);
        expect4("cursor AE",menu_index,4'd3);
        expect1("AE defaults auto",ae_auto,1'b1);
        press_key(3);
        expect1("AE toggles manual",ae_auto,1'b0);
        press_key(3);
        expect1("AE re-arms auto",ae_auto,1'b1);

        // EXP and GAIN are menu-driven camera-domain actions.  Any direct
        // edit retains manual AE mode.
        press_key(1);
        expect4("cursor EXP",menu_index,4'd4);
        press_key(3);
        expect1("EXP edit leaves AUTO",ae_auto,1'b0);
        expect1("EXP increment direction",camera_adjust_up,1'b1);
        expect1("EXP selection",camera_adjust_gain,1'b0);
        press_key(1);
        expect4("cursor GAIN",menu_index,4'd5);
        press_key(2);
        expect1("GAIN decrement direction",camera_adjust_up,1'b0);
        expect1("GAIN selection",camera_adjust_gain,1'b1);

        // SCR quota row: target type must follow the cursor and KEY4 pulses INC.
        press_key(1);
        expect4("cursor SCR quota",menu_index,4'd6);
        expect3("target type SCR",target_type,3'd1);
        button_n[3]=1'b0;
        wait_clocks(30);
        expect1("SCR increment pulse ended",target_inc,1'b0);
        if(inc_pulses!=1) begin
            $display("FAIL quota held key repeated pulses=%0d",inc_pulses);
            errors=errors+1;
        end
        button_n[3]=1'b1;
        wait_clocks(9);

        // Visit the other three quota rows and verify the selected class.
        press_key(1); expect3("target type WAS",target_type,3'd2);
        press_key(1); expect3("target type HEX",target_type,3'd3);
        press_key(1); expect3("target type SQU",target_type,3'd4);

        // RESET row and KEY4 generates only a one-cycle clear action.
        press_key(1);
        expect4("cursor RESET",menu_index,4'd10);
        press_key(3);
        expect1("clear pulse ended",count_clear,1'b0);

        // A completed batch forces remembered belt speed to STOP.
        batch_done=1'b1;
        wait_clocks(2);
        batch_done=1'b0;
        expect3("batch stops motor",motor_level,3'd0);

        // Close/reopen: settings persist, cursor returns to VIEW.
        menu_switch=1'b0;
        wait_clocks(5);
        expect1("menu closes",menu_open,1'b0);
        menu_switch=1'b1;
        wait_clocks(5);
        expect4("cursor resets on reopen",menu_index,4'd0);
        expect3("preview persists",preview_mode,3'd1);
        expect1("AWB setting persists",awb_freeze,1'b1);

        // Re-enable AUTO, then verify the direct camera keys take over MAN.
        press_key(1);press_key(1);press_key(1);press_key(3);
        expect1("AE re-enabled",ae_auto,1'b1);
        menu_switch=0;wait_clocks(6);press_key(0);
        expect1("direct camera key MAN",ae_auto,1'b0);

        if(errors==0) $display("TB_PASS screen_menu_control");
        else $display("TB_FAIL screen_menu_control errors=%0d",errors);
        $finish;
    end
endmodule
