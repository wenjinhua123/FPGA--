`timescale 1ns/1ps
// 独立参考模型按时间移动队列并直接点积，不使用 DUT 的递推或分组存储地址。
module tb_kay_recursive_1024_8lane;
    reg clk = 0;
    reg done = 0;
    reg rst = 1;
    reg group_valid_in = 0;
    reg [7:0] phase_valid_in = 0;
    reg signed [31:0] phase [0:7];
    wire [7:0] valid_out;
    wire signed [63:0] result [0:7];
    reg signed [31:0] history [0:1022];
    reg signed [63:0] expected [0:7];
    reg [7:0] expected_valid;
    reg signed [63:0] term, dot;
    integer fill = 0;
    integer errors = 0;
    integer groups = 0;
    integer checked_lanes = 0;
    integer cycles = 0;
    integer lane, tap, init_index;
    integer stim_group, serial = 0;
    integer case_group = 0;
    integer scenario = 0;

    kay_recursive_1024_8lane dut (
        .clk(clk), .rst(rst), .group_valid_in(group_valid_in),
        .phase_valid_in(phase_valid_in),
        .phase0(phase[0]), .phase1(phase[1]),
        .phase2(phase[2]), .phase3(phase[3]),
        .phase4(phase[4]), .phase5(phase[5]),
        .phase6(phase[6]), .phase7(phase[7]),
        .valid_out(valid_out),
        .kay_sum0(result[0]), .kay_sum1(result[1]),
        .kay_sum2(result[2]), .kay_sum3(result[3]),
        .kay_sum4(result[4]), .kay_sum5(result[5]),
        .kay_sum6(result[6]), .kay_sum7(result[7])
    );
    initial begin
        while (!done) begin
            #5;
            if (!done) clk = ~clk;
        end
    end

    task fail;
        input [255:0] reason;
        begin
            errors = errors + 1;
            if (errors <= 12)
                $display("FAIL cycle=%0d lane=%0d %0s", cycles, lane, reason);
        end
    endtask

    // 每个有效时钟都检查，包括无效输出时的部分窗口数值和气泡保持。
    always @(posedge clk) begin
        cycles = cycles + 1;
        expected_valid = 0;
        if (rst) begin
            fill = 0;
            case_group = 0;
            for (lane = 0; lane < 8; lane = lane + 1)
                expected[lane] = 0;
        end else if (group_valid_in) begin
            groups = groups + 1;
            case_group = case_group + 1;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if (!phase_valid_in[lane]) begin
                    fill = 0;
                    expected[lane] = 0;
                end else begin
                    // 左侧补零；只读 fill 范围内的已初始化样本。
                    for (tap = 0; tap < 1022; tap = tap + 1)
                        history[tap] = history[tap + 1];
                    history[1022] = phase[lane];
                    if (fill < 1023) fill = fill + 1;
                    dot = 0;
                    for (tap = 1023-fill; tap < 1023; tap = tap + 1) begin
                        term = {{32{history[tap][31]}}, history[tap]};
                        dot = dot + term * (tap+1) * (1023-tap);
                    end
                    expected[lane] = dot;
                    expected_valid[lane] = (fill == 1023);
                end
            end
        end
        #0.1;
        if (valid_out !== expected_valid) fail("valid mask mismatch");
        for (lane = 0; lane < 8; lane = lane + 1) begin
            checked_lanes = checked_lanes + 1;
            if (result[lane] !== expected[lane]) begin
                if (errors < 12)
                    $display("  actual=%0d expected=%0d", result[lane], expected[lane]);
                fail("numerator mismatch");
            end
        end
        if (!rst && group_valid_in && case_group == 128 && scenario < 3) begin
            $display("STARTUP scenario=%0d group=128 mask=%02h", scenario, valid_out);
            if (scenario == 1 && valid_out !== 8'h80) fail("FE startup expected 80");
            if (scenario == 2 && valid_out !== 8'hc0) fail("FF startup expected C0");
        end
        if (!rst && group_valid_in && case_group == 129 && scenario < 3) begin
            $display("STARTUP scenario=%0d group=129 mask=%02h", scenario, valid_out);
            if (valid_out !== 8'hff) fail("next startup mask expected FF");
        end
    end

    // pattern 0 为约 +100 MHz，1 为约 -1 GHz，2 混合正负极值。
    task send;
        input accepted;
        input [7:0] mask;
        input integer pattern;
        integer drive_lane;
        begin
            @(negedge clk);
            rst = 0;
            group_valid_in = accepted;
            phase_valid_in = mask;
            for (drive_lane = 0; drive_lane < 8; drive_lane = drive_lane + 1) begin
                serial = serial + 1;
                case (pattern)
                    0: phase[drive_lane] = 32'sd42949673;
                    1: phase[drive_lane] = -32'sd429496730;
                    default: case (serial % 4)
                        0: phase[drive_lane] = 32'sh80000000;
                        1: phase[drive_lane] = 32'sh7fffffff;
                        2: phase[drive_lane] = serial * 7919;
                        3: phase[drive_lane] = -serial * 3571;
                    endcase
                endcase
            end
        end
    endtask

    task reset_dut;
        begin
            @(negedge clk);
            rst = 1;
            group_valid_in = 0;
            phase_valid_in = 0;
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        for (init_index = 0; init_index < 8; init_index = init_index + 1) begin
            phase[init_index] = 0;
            expected[init_index] = 0;
        end
        for (init_index = 0; init_index < 1023; init_index = init_index + 1)
            history[init_index] = 0;
        repeat (2) @(negedge clk);
        scenario = 1;
        send(1, 8'hfe, 0);
        for (stim_group = 1; stim_group < 305; stim_group = stim_group + 1) begin
            send(1, 8'hff, 0);
            if (stim_group % 47 == 0) send(0, 8'h00, 2);
        end
        // 重置已满窗口，再验证 FF 从第一组开始的 C0 边界。
        reset_dut;
        scenario = 2;
        for (stim_group = 0; stim_group < 265; stim_group = stim_group + 1)
            send(1, 8'hff, 1);
        send(1, 8'hf7, 2);
        @(posedge clk); #0.2;
        if (valid_out !== 8'h07) fail("F7 gap expected mask 07");
        scenario = 3;
        for (stim_group = 0; stim_group < 140; stim_group = stim_group + 1)
            send(1, 8'hff, 2);
        send(0, 8'h00, 2);
        send(1, 8'h00, 2);
        for (stim_group = 0; stim_group < 15; stim_group = stim_group + 1)
            send(1, 8'hff, 2);
        // 部分窗口时重置，且旧存储器内容仍然存在。
        reset_dut;
        for (stim_group = 0; stim_group < 275; stim_group = stim_group + 1) begin
            send(1, (stim_group == 0) ? 8'hfe : 8'hff, 2);
            if (stim_group % 39 == 0) send(0, 8'hff, 0);
        end
        send(0, 8'hff, 2);
        @(posedge clk); #0.2;
        if (errors == 0)
            $display("PASS groups=%0d checked_lanes=%0d errors=0", groups, checked_lanes);
        else
            $display("FAIL summary groups=%0d checked_lanes=%0d errors=%0d", groups, checked_lanes, errors);
        done = 1;
        $finish;
    end
    initial begin
        #200000;
        if (!done) begin
            $display("FATAL watchdog expired");
            done = 1;
            $finish;
        end
    end
endmodule
