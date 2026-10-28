`timescale 1ns/1ps
// 用量化后的 IQ 独立计算直接加权和，同时检查每拍 valid 和固定 43 拍延迟。
module tb_iq_kay_freq_8lane;
    reg clk = 0, rst = 1, valid_in = 0, done = 0;
    reg signed [15:0] ii [0:7], qq [0:7];
    wire [7:0] valid_out;
    wire signed [31:0] freq [0:7];
    iq_kay_freq_8lane dut (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i0(ii[0]), .q0(qq[0]), .i1(ii[1]), .q1(qq[1]),
        .i2(ii[2]), .q2(qq[2]), .i3(ii[3]), .q3(qq[3]),
        .i4(ii[4]), .q4(qq[4]), .i5(ii[5]), .q5(qq[5]),
        .i6(ii[6]), .q6(qq[6]), .i7(ii[7]), .q7(qq[7]),
        .valid_out(valid_out),
        .freq0(freq[0]), .freq1(freq[1]), .freq2(freq[2]), .freq3(freq[3]),
        .freq4(freq[4]), .freq5(freq[5]), .freq6(freq[6]), .freq7(freq[7])
    );
    localparam QUEUE = 4000;
    localparam real PI = 3.14159265358979323846;
    reg [7:0] expected_mask [0:QUEUE-1];
    real expected_freq [0:QUEUE*8-1];
    real history [0:1022];
    integer cycle = 0, errors = 0, tested = 0, nonzero = 0, groups = 0;
    integer fill = 0, head = 0, k, lane, j, address, target;
    integer prev_i = 0, prev_q = 0;
    reg have_prev = 0, first_window = 1;
    reg [7:0] new_mask;
    reg signed [63:0] re_product, im_product;
    real angle, re_real, im_real, weighted, actual, difference, max_error_hz = 0.0;
    real phase_acc = 0.0, tone_mhz = 100.0;

    // 真正停止时钟，避免 runall 在测试结束后继续等待周期事件。
    initial while (!done) begin #5; if (!done) clk = ~clk; end
    initial begin
        #400000;
        if (!done) begin $display("FAIL watchdog timeout"); errors = errors + 1; done = 1; end
    end

    always @(posedge clk) begin
        cycle = cycle + 1;
        if (cycle >= QUEUE-44) begin
            $display("FAIL scoreboard capacity"); errors = errors + 1; done = 1;
        end
        if (rst) begin
            // 复位连同流水线中尚未输出的期望一起冲掉；cycle 始终单调递增。
            for (k = 0; k < QUEUE; k = k + 1) expected_mask[k] = 0;
            fill = 0; head = 0; have_prev = 0; first_window = 1;
        end else if (valid_in) begin
            groups = groups + 1;
            new_mask = 0;
            target = cycle + 43;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                re_product = $signed(ii[lane]) * prev_i + $signed(qq[lane]) * prev_q;
                im_product = $signed(qq[lane]) * prev_i - $signed(ii[lane]) * prev_q;
                if (!have_prev || ((re_product == 0) && (im_product == 0))) begin
                    fill = 0; head = 0;
                end else begin
                    // atan2 接受实数；共轭乘积来自实际送给 DUT 的整数 IQ。
                    re_real = re_product; im_real = im_product;
                    angle = $atan2(im_real, re_real);
                    history[head] = angle;
                    head = (head + 1) % 1023;
                    if (fill < 1023) fill = fill + 1;
                    if (fill == 1023) begin
                        weighted = 0.0;
                        // 与 DUT 的递推式独立：从最老到最新直接点乘权重。
                        for (j = 1; j <= 1023; j = j + 1) begin
                            address = (head + j - 1) % 1023;
                            weighted = weighted + history[address] * j * (1024-j);
                        end
                        new_mask[lane] = 1;
                        expected_freq[target*8+lane] = weighted / 178956800.0 * 2500.0 / (2.0*PI);
                    end
                end
                prev_i = $signed(ii[lane]); prev_q = $signed(qq[lane]); have_prev = 1;
            end
            expected_mask[target] = new_mask;
            if (first_window && (new_mask != 0)) begin
                if (new_mask !== 8'h80) begin
                    $display("FAIL first warmup mask expected 80 got %h", new_mask);
                    errors = errors + 1;
                end
                first_window = 0;
            end
        end
        #0.1;
        if (valid_out !== expected_mask[cycle]) begin
            if (errors < 12) $display("FAIL cycle %0d mask expected %h got %h", cycle, expected_mask[cycle], valid_out);
            errors = errors + 1;
        end
        for (lane = 0; lane < 8; lane = lane + 1) begin
            if (expected_mask[cycle][lane] && valid_out[lane]) begin
                tested = tested + 1;
                if ((^freq[lane]) === 1'bx) begin
                    $display("FAIL unknown frequency cycle %0d lane %0d", cycle, lane);
                    errors = errors + 1;
                end else begin
                    actual = $signed(freq[lane]) / 1048576.0;
                    difference = actual - expected_freq[cycle*8+lane];
                    if (difference < 0.0) difference = -difference;
                    if (difference * 1000000.0 > max_error_hz) max_error_hz = difference * 1000000.0;
                    if (freq[lane] != 0) nonzero = nonzero + 1;
                    if (difference > 0.000010) begin
                        if (errors < 12) $display("FAIL frequency cycle %0d lane %0d actual %.9f gold %.9f MHz", cycle, lane, actual, expected_freq[cycle*8+lane]);
                        errors = errors + 1;
                    end
                end
            end
        end
    end

    task quiet;
        input integer count;
        integer n;
        begin
            @(negedge clk); valid_in = 0;
            for (n = 1; n < count; n = n + 1) @(negedge clk);
        end
    endtask
    task reset_chain;
        begin
            @(negedge clk); rst = 1; valid_in = 0;
            repeat (4) @(negedge clk);
            rst = 0; phase_acc = 0.0;
            repeat (2) @(negedge clk);
        end
    endtask
    task packet;
        input integer zero_mode;
        integer n;
        begin
            @(negedge clk); valid_in = 1;
            for (n = 0; n < 8; n = n + 1) begin
                ii[n] = $rtoi(12000.0 * $cos(phase_acc));
                qq[n] = $rtoi(12000.0 * $sin(phase_acc));
                if ((zero_mode == 1) || ((zero_mode == 2) && ((n % 2) == 0))) begin
                    ii[n] = 0; qq[n] = 0;
                end
                phase_acc = phase_acc + 2.0*PI*tone_mhz/2500.0;
                if (phase_acc > PI) phase_acc = phase_acc - 2.0*PI;
                if (phase_acc < -PI) phase_acc = phase_acc + 2.0*PI;
            end
        end
    endtask
    task healthy;
        input integer count;
        integer n;
        begin
            for (n = 0; n < count; n = n + 1) begin
                if ((n % 11) == 4) quiet(1);
                packet(0);
            end
        end
    endtask
    task trial;
        input real frequency;
        integer before_tested;
        begin
            reset_chain; tone_mhz = frequency; before_tested = tested;
            healthy(170); quiet(85);
            $display("Tone %0.0f MHz: checked %0d lane outputs", frequency, tested-before_tested);
        end
    endtask
    initial begin
        for (k = 0; k < 8; k = k + 1) begin ii[k] = 0; qq[k] = 0; end
        for (k = 0; k < QUEUE; k = k + 1) expected_mask[k] = 0;
        trial(100.0); trial(1000.0); trial(-100.0); trial(-1000.0);
        reset_chain; tone_mhz = 100.0;
        healthy(175); tone_mhz = -700.0; healthy(175);
        // 已满窗口后注入 00 相位掩码包；随后相位必须重新积满窗口。
        packet(1); healthy(170);
        // 当前全零包的下一包相位均无效，不能用 |phase_valid 代替组标记。
        packet(2); healthy(170); quiet(85);
        // 流水线尚有有效数据时复位，随后重新填窗检查。
        healthy(10); reset_chain; tone_mhz = 300.0;
        healthy(170); quiet(85);
        if ((tested == 0) || (nonzero == 0)) begin
            $display("FAIL no nonzero frequency outputs were checked"); errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS iq_kay_freq_8lane groups=%0d lane_outputs=%0d latency=43 max_error=%.6f Hz", groups, tested, max_error_hz);
        else $display("FAIL iq_kay_freq_8lane errors=%0d checked=%0d", errors, tested);
        done = 1;
    end
endmodule
