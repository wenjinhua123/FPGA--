`timescale 1ns/1ps
module tb_iq_phase_8lane;
    reg clk = 0, rst = 1, valid_in = 0, done = 0;
    reg signed [15:0] i_sample [0:7], q_sample [0:7];
    wire signed [31:0] phase [0:7];
    wire [7:0] valid_out;
    integer cycle = 0, errors = 0, sent = 0, received = 0, phase_count = 0;
    integer latency = -1, head = 0, tail = 0;
    reg [7:0] expected_mask [0:31];
    real expected_mhz [0:31];
    integer accept_cycle [0:31];
    integer lane, tone, group_index, n, before_count, before_received;
    real frequency, angle, measured, difference;
    localparam real PI = 3.14159265358979323846;

    // 输入在下降沿设置；检查放在上升沿非阻塞赋值完成后。
    initial begin
        while (!done) begin
            #5;
            if (!done) clk = ~clk;
        end
    end
    iq_phase_8lane dut (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i0(i_sample[0]), .q0(q_sample[0]), .i1(i_sample[1]), .q1(q_sample[1]),
        .i2(i_sample[2]), .q2(q_sample[2]), .i3(i_sample[3]), .q3(q_sample[3]),
        .i4(i_sample[4]), .q4(q_sample[4]), .i5(i_sample[5]), .q5(q_sample[5]),
        .i6(i_sample[6]), .q6(q_sample[6]), .i7(i_sample[7]), .q7(q_sample[7]),
        .phase0(phase[0]), .phase1(phase[1]), .phase2(phase[2]), .phase3(phase[3]),
        .phase4(phase[4]), .phase5(phase[5]), .phase6(phase[6]), .phase7(phase[7]),
        .valid_out(valid_out)
    );

    // FIFO 记录每个已接收组的掩码、频率和时刻，不硬编码流水线延迟。
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (!rst && valid_in) begin
            expected_mask[tail] = (group_index == 0) ? 8'hfe : 8'hff;
            expected_mhz[tail] = frequency;
            accept_cycle[tail] = cycle;
            tail = tail + 1;
            sent = sent + 1;
        end
        #0.1;
        if ((^valid_out) === 1'bx) begin
            errors = errors + 1;
            $display("FAIL: unknown valid mask at cycle %0d", cycle);
        end else if (valid_out != 0) begin
            if (rst || head >= tail) begin
                errors = errors + 1;
                $display("FAIL: unexpected output at cycle %0d", cycle);
            end else begin
                if (valid_out !== expected_mask[head]) begin
                    errors = errors + 1;
                    $display("FAIL: group %0d mask %h expected %h", head, valid_out, expected_mask[head]);
                end
                if (latency < 0) latency = cycle - accept_cycle[head];
                if (cycle - accept_cycle[head] != latency) begin
                    errors = errors + 1;
                    $display("FAIL: group %0d latency changed", head);
                end
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    // 无效路的 phase 数据没有意义，不能拿来检查。
                    if (valid_out[lane]) begin
                        phase_count = phase_count + 1;
                        if ((^phase[lane]) === 1'bx) begin
                            errors = errors + 1;
                            $display("FAIL: group %0d lane %0d unknown phase", head, lane);
                        end else begin
                            measured = $itor($signed(phase[lane])) * 2500.0 / 1073741824.0;
                            difference = measured - expected_mhz[head];
                            if (difference < 0) difference = -difference;
                            // 0.1 MHz 是整数 IQ 量化容差，不代表 CORDIC 精度。
                            if (difference > 0.1) begin
                                errors = errors + 1;
                                $display("FAIL: group %0d lane %0d f=%0.6f expected=%0.1f MHz",
                                         head, lane, measured, expected_mhz[head]);
                            end
                        end
                    end
                end
                received = received + 1;
                head = head + 1;
            end
        end
    end

    initial begin
        for (n = 0; n < 8; n = n + 1) begin
            i_sample[n] = 0;
            q_sample[n] = 0;
        end
        for (tone = 0; tone < 4; tone = tone + 1) begin
            case (tone)
                0: frequency = 100.0;
                1: frequency = 1000.0;
                2: frequency = -100.0;
                3: frequency = -1000.0;
            endcase
            before_count = errors;
            before_received = received;
            @(negedge clk); rst = 1; valid_in = 0;
            repeat (4) @(negedge clk);
            rst = 0;
            repeat (2) @(negedge clk);
            for (group_index = 0; group_index < 8; group_index = group_index + 1) begin
                valid_in = 1;
                for (n = 0; n < 8; n = n + 1) begin
                    angle = 2.0 * PI * frequency * (group_index * 8 + n) / 2500.0;
                    i_sample[n] = $rtoi(12000.0 * $cos(angle));
                    q_sample[n] = $rtoi(12000.0 * $sin(angle));
                end
                @(negedge clk);
                // 暂停传输不跳过采样序号，组间相邻关系保持。
                if (group_index == 2 || group_index == 5) begin
                    valid_in = 0;
                    repeat (2) @(negedge clk);
                end
            end
            valid_in = 0;
            repeat (80) @(negedge clk);
            if (received - before_received != 8) begin
                errors = errors + 1;
                $display("FAIL: tone %0.1f MHz groups=%0d/8", frequency, received - before_received);
            end
            $display("TONE %0.1f MHz: groups=%0d/8, errors=%0d",
                     frequency, received - before_received, errors - before_count);
        end
        if (sent != 32 || received != 32 || phase_count != 252 || head != tail) begin
            errors = errors + 1;
            $display("FAIL: totals sent=%0d received=%0d phases=%0d", sent, received, phase_count);
        end
        if (errors == 0)
            $display("PASS: groups=32 phases=252 latency=%0d cycles errors=0", latency);
        else
            $display("FAIL: errors=%0d groups=%0d phases=%0d", errors, received, phase_count);
        done = 1;
        $finish;
    end

    initial begin
        #20000;
        if (!done) begin
            errors = errors + 1;
            $display("FAIL: watchdog timeout, groups=%0d phases=%0d", received, phase_count);
            done = 1;
            $finish;
        end
    end
endmodule
