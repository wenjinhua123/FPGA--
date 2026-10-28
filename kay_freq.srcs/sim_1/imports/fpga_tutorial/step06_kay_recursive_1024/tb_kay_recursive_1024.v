`timescale 1ns/1ps
module tb_kay_recursive_1024;
    reg clk = 0;
    reg rst = 1;
    reg valid_in = 0;
    reg signed [31:0] phase_in = 0;
    wire valid_out;
    wire signed [63:0] kay_sum;
    reg done = 0;
    integer errors = 0, checked_outputs = 0;
    integer checked_cycles = 0, accepted_inputs = 0;
    integer invalid_cycles = 0, reset_cycles = 0;
    integer fill = 0;
    integer index, weight, stim;
    reg expected_valid;
    reg signed [31:0] samples [0:1022];
    reg signed [63:0] expected_sum = 0;
    reg signed [63:0] held_sum = 0;
    reg signed [63:0] sample64, weight64, product64;
    real frequency_mhz;

    kay_recursive_1024 dut(
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .phase_in(phase_in), .valid_out(valid_out), .kay_sum(kay_sum)
    );

    // 时钟在测试结束后停止；再次 run all 也不会继续制造事件。
    initial begin
        while (!done) begin
            #5;
            if (!done) clk = ~clk;
        end
    end
    initial begin
        #200000;
        if (!done) begin
            $display("FAIL watchdog timeout");
            done = 1;
            $finish;
        end
    end

    // 独立参考：每次直接相乘求和，不使用 DUT 的递推公式。
    always @(posedge clk) begin
        checked_cycles = checked_cycles + 1;
        expected_valid = 0;
        if (rst) begin
            fill = 0;
            expected_sum = 0;
            reset_cycles = reset_cycles + 1;
        end else if (valid_in) begin
            accepted_inputs = accepted_inputs + 1;
            for (index = 0; index < 1022; index = index + 1)
                samples[index] = samples[index + 1];
            samples[1022] = phase_in;
            if (fill < 1023) fill = fill + 1;
            expected_valid = (fill == 1023);
            expected_sum = 0;
            for (index = 0; index < 1023; index = index + 1) begin
                // 未填满时，窗口左端相当于补零，不读取未初始化数据。
                if (index >= 1023 - fill) begin
                    weight = (index + 1) * (1024 - (index + 1));
                    sample64 = {{32{samples[index][31]}}, samples[index]};
                    weight64 = weight;
                    product64 = sample64 * weight64;
                    expected_sum = expected_sum + product64;
                end
            end
        end else begin
            invalid_cycles = invalid_cycles + 1;
        end
        #0.1;
        if (valid_out !== expected_valid) begin
            if (errors < 8) $display("FAIL valid cycle=%0d expected=%b got=%b", checked_cycles, expected_valid, valid_out);
            errors = errors + 1;
        end
        if (expected_valid) begin
            checked_outputs = checked_outputs + 1;
            if (kay_sum !== expected_sum) begin
                if (errors < 8) $display("FAIL sum cycle=%0d expected=%0d got=%0d", checked_cycles, expected_sum, kay_sum);
                errors = errors + 1;
            end
        end
        // 无效输入时必须保持；同步复位则必须清零。
        if ((rst && kay_sum !== 64'sd0) ||
            (!rst && !valid_in && kay_sum !== held_sum)) begin
            if (errors < 8) $display("FAIL reset/hold cycle=%0d", checked_cycles);
            errors = errors + 1;
        end
        held_sum = kay_sum;
    end

    // 所有输入只在下降沿改变，避开上升沿的采样与检查。
    task drive;
        input reset_value, valid_value;
        input signed [31:0] phase_value;
        begin
            @(negedge clk);
            rst = reset_value;
            valid_in = valid_value;
            phase_in = phase_value;
        end
    endtask

    initial begin
        drive(1, 0, 0);
        // 常量正相位：超过两次指针回绕，穿插暂停。
        for (stim = 0; stim < 3200; stim = stim + 1) begin
            if (stim % 31 == 0) drive(0, 0, 123);
            drive(0, 1, 32'sd42949673);
        end
        drive(0, 0, 0);
        @(posedge clk); #1;
        // 先将有符号 64 位整数赋给 real，避免 $itor 截断。
        frequency_mhz = kay_sum;
        frequency_mhz = frequency_mhz / 178956800.0 * 2500.0 / 1073741824.0;
        $display("INFO constant positive frequency_MHz=%0.9f", frequency_mhz);
        // 在满窗口复位，再检查负常量。
        drive(1, 1, 32'sh7fffffff);
        for (stim = 0; stim < 1250; stim = stim + 1)
            drive(0, 1, -32'sd429496730);
        // 在部分窗口复位，确保旧 RAM 内容不会泄漏。
        drive(1, 0, 0);
        for (stim = 0; stim < 37; stim = stim + 1)
            drive(0, 1, stim * 137);
        drive(1, 0, 0);
        // 单位脉冲经过整个窗口并退出。
        for (stim = 0; stim < 1250; stim = stim + 1)
            drive(0, 1, (stim == 0) ? 32'sd1073741824 : 32'sd0);
        // 变化输入以及正负全量程，覆盖符号扩展和中间位宽。
        for (stim = 0; stim < 2300; stim = stim + 1) begin
            if (stim % 17 == 0) drive(0, 0, -32'sd1);
            case (stim % 4)
                0: drive(0, 1, 32'sh7fffffff);
                1: drive(0, 1, 32'sh80000000);
                2: drive(0, 1, stim * 1000003);
                3: drive(0, 1, -stim * 731003);
            endcase
        end
        drive(0, 0, 0);
        drive(1, 0, 0);
        drive(0, 0, 0);
        @(posedge clk); #1;
        if (errors == 0 && checked_outputs > 0)
            $display("PASS N=1024 L=1023 checked_outputs=%0d accepted_inputs=%0d checked_cycles=%0d invalid_cycles=%0d reset_cycles=%0d errors=%0d", checked_outputs, accepted_inputs, checked_cycles, invalid_cycles, reset_cycles, errors);
        else
            $display("FAIL final checked_outputs=%0d errors=%0d", checked_outputs, errors);
        done = 1;
        $finish;
    end
endmodule
