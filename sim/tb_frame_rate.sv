`timescale 1ns/1ps
module tb_frame_rate;
    reg cam=0,sys=0,rst=0,sof=0,valid=0;
    wire [11:0] fps;wire update;
    integer completed=0,window_frames=0,windows=0,reference_tick=0;
    integer words=0;reg started=0,finished=0,source_toggle=0;
    reg [2:0] pipe=0;
    reg expected_update=0;reg [11:0] expected_fps=0;
    always #3 cam=~cam;always #5 sys=~sys;
    video_frame_rate #(.SYSTEM_HZ(1000),.WORDS_PER_FRAME(8)) dut(
        .camera_clk(cam),.system_clk(sys),.rst_n(rst),.frame_start(sof),
        .word_valid(valid),.fps_bcd(fps),.fps_update(update));
    // Independent integer oracle counts supplied camera words, then models
    // only the documented three-clock event synchronization latency.
    always @(posedge cam) begin
        if(!rst) begin words=0;started=0;finished=0;source_toggle=0;completed=0;end
        else begin
            if(sof) begin words=0;started=1;finished=0;end
            if(valid && started && !finished) begin
                words=words+1;
                if(words==8) begin completed=completed+1;source_toggle=~source_toggle;finished=1;end
            end
        end
    end
    always @(posedge sys) begin
        if(!rst) begin pipe=0;window_frames=0;reference_tick=0;windows=0;expected_update=0;expected_fps=0;end
        else begin
            if(pipe[2]!=pipe[1]) window_frames=window_frames+1;
            pipe={pipe[1:0],source_toggle};
            reference_tick=reference_tick+1;
            if(reference_tick==1000) begin
                expected_fps=((window_frames/100)%10)*256+((window_frames/10)%10)*16+window_frames%10;
                expected_update=~expected_update;reference_tick=0;window_frames=0;windows=windows+1;
            end
            #1;
            if(fps!==expected_fps || update!==expected_update)
                $fatal(1,"FPS window mismatch window=%0d tick=%0d got=%h/%b expected=%h/%b",windows,reference_tick,fps,update,expected_fps,expected_update);
        end
    end
    task emit(input integer count,input bit simultaneous);
        begin
            @(negedge cam);sof=1;valid=simultaneous;
            @(negedge cam);sof=0;valid=0;
            repeat(2) @(negedge cam);
            repeat(count-(simultaneous?1:0)) begin valid=1;@(negedge cam);end
            valid=0;repeat(2) @(negedge cam);
        end
    endtask
    initial begin
        repeat(5) @(negedge sys);rst=1;
        // Noise without SOF and interrupted short frames never count.
        @(negedge cam);valid=1;repeat(12) @(negedge cam);valid=0;
        emit(4,0);emit(7,1);
        repeat(30) emit(8,0);
        repeat(1200) @(negedge sys);
        if(completed!=30 || fps!=12'h030) $fatal(1,"30fps camera complete/partial qualification failed %0d %h",completed,fps);
        repeat(1100) @(negedge sys);
        if(fps!=0) $fatal(1,"camera stop must publish zero instead of stale FPS");
        repeat(120) emit(8,1);
        // Extra words following completion must never emit a second event.
        @(negedge cam);valid=1;repeat(30) @(negedge cam);valid=0;
        repeat(1200) @(negedge sys);
        if(completed!=150) $fatal(1,"extra camera words duplicated complete frames");
        // Continuous valid/blank traffic crosses several reference boundaries.
        repeat(300) emit(8,1);repeat(1200) @(negedge sys);
        if(completed!=450 || windows<5) $fatal(1,"FPS coverage insufficient");
        $display("ALL PASS frame rate: 450 complete frames, malformed/partial ignored, delayed and simultaneous SOF, decimal rollover, asynchronous clocks, window boundary, stopped camera zero; %0d windows",windows);$finish;
    end
    initial begin #200000;$fatal(1,"FPS watchdog");end
endmodule
