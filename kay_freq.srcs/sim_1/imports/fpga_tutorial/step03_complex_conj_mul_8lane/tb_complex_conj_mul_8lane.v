`timescale 1ns/1ps
module tb_complex_conj_mul_8lane;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 0, valid_in = 0;
    reg signed [15:0] i_data [0:7];
    reg signed [15:0] q_data [0:7];
    wire signed [32:0] re_data [0:7];
    wire signed [32:0] im_data [0:7];
    wire [7:0] valid_out;

    complex_conj_mul_8lane dut (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i0(i_data[0]), .q0(q_data[0]), .i1(i_data[1]), .q1(q_data[1]),
        .i2(i_data[2]), .q2(q_data[2]), .i3(i_data[3]), .q3(q_data[3]),
        .i4(i_data[4]), .q4(q_data[4]), .i5(i_data[5]), .q5(q_data[5]),
        .i6(i_data[6]), .q6(q_data[6]), .i7(i_data[7]), .q7(q_data[7]),
        .re0(re_data[0]), .im0(im_data[0]), .re1(re_data[1]), .im1(im_data[1]),
        .re2(re_data[2]), .im2(im_data[2]), .re3(re_data[3]), .im3(im_data[3]),
        .re4(re_data[4]), .im4(im_data[4]), .re5(re_data[5]), .im5(im_data[5]),
        .re6(re_data[6]), .im6(im_data[6]), .re7(re_data[7]), .im7(im_data[7]),
        .valid_out(valid_out)
    );

    // 参考模型按时间顺序逐个处理样本，而不是照搬八路连接。
    reg have_previous = 0;
    reg signed [63:0] previous_i = 0, previous_q = 0;
    reg signed [63:0] now_i, now_q;
    reg signed [63:0] pending_re [0:7], pending_im [0:7];
    reg signed [63:0] expected_re [0:7], expected_im [0:7];
    reg [7:0] pending_mask = 0, expected_mask;
    integer cycles = 0, valid_results = 0, extreme_results = 0, failures = 0;
    integer lane;

    // 数据提前准备，复位/有效在下降沿设置；上升沿后等 0.1ns 检查。
    // 本拍输出来自上一拍接受的输入，气泡时结果保持。
    task tick;
        input reset_value;
        input input_valid;
        integer n;
        begin
            @(negedge clk);
            rst = reset_value;
            valid_in = input_valid;
            @(posedge clk);
            cycles = cycles + 1;
            if (rst) begin
                expected_mask = 0;
                pending_mask = 0;
                have_previous = 0;
                previous_i = 0;
                previous_q = 0;
                for (n = 0; n < 8; n = n + 1) begin
                    expected_re[n] = 0;
                    expected_im[n] = 0;
                    pending_re[n] = 0;
                    pending_im[n] = 0;
                end
            end else begin
                expected_mask = pending_mask;
                for (n = 0; n < 8; n = n + 1) begin
                    if (pending_mask[n]) begin
                        expected_re[n] = pending_re[n];
                        expected_im[n] = pending_im[n];
                    end
                end
                pending_mask = 0;
                if (valid_in) begin
                    for (n = 0; n < 8; n = n + 1) begin
                        now_i = $signed(i_data[n]);
                        now_q = $signed(q_data[n]);
                        if (have_previous) begin
                            pending_mask[n] = 1;
                            pending_re[n] = now_i * previous_i + now_q * previous_q;
                            pending_im[n] = now_q * previous_i - now_i * previous_q;
                        end
                        previous_i = now_i;
                        previous_q = now_q;
                        have_previous = 1;
                    end
                end
            end
            #0.1;
            if (valid_out !== expected_mask) begin
                $display("FAIL cycle=%0d mask got=%h expected=%h", cycles, valid_out, expected_mask);
                failures = failures + 1;
            end
            for (n = 0; n < 8; n = n + 1) begin
                if ($signed(re_data[n]) !== expected_re[n] ||
                    $signed(im_data[n]) !== expected_im[n]) begin
                    $display("FAIL cycle=%0d lane=%0d re=%0d/%0d im=%0d/%0d", cycles, n,
                        $signed(re_data[n]), expected_re[n], $signed(im_data[n]), expected_im[n]);
                    failures = failures + 1;
                end
                if (expected_mask[n]) begin
                    valid_results = valid_results + 1;
                    if (expected_re[n] == 64'sd2147483648 && expected_im[n] == 0)
                        extreme_results = extreme_results + 1;
                end
            end
        end
    endtask

    task set_group;
        input integer seed;
        integer n;
        begin
            for (n = 0; n < 8; n = n + 1) begin
                i_data[n] = seed + 13*n;
                q_data[n] = -2*seed + 7*n;
            end
        end
    endtask

    initial begin
        set_group(1);
        tick(1, 0);
        tick(0, 0);
        // 第一组应延迟一拍得到 FE，连续第二组得到 FF。
        set_group(17); tick(0, 1);
        set_group(-91); tick(0, 1);
        set_group(213); tick(0, 1);
        // 气泡里的数据故意改变；恢复时仍接上最后被接受的样本。
        set_group(1100); tick(0, 0);
        set_group(-1400); tick(0, 0);
        set_group(39); tick(0, 1);
        tick(0, 0);
        tick(0, 0);
        // 33 位边界：(-32768)^2 + (-32768)^2 = 2147483648。
        for (lane = 0; lane < 8; lane = lane + 1) begin
            i_data[lane] = -32768;
            q_data[lane] = -32768;
        end
        tick(0, 1);
        tick(0, 1);
        for (lane = 0; lane < 8; lane = lane + 1) begin
            i_data[lane] = (lane % 2) ? 32767 : -32768;
            q_data[lane] = (lane % 3) ? -32768 : 32767;
        end
        tick(0, 1);
        tick(0, 0);
        tick(0, 0);
        // 有待输出的结果时复位，且 valid_in 同时为 1：复位优先。
        set_group(503); tick(0, 1);
        set_group(700); tick(1, 1);
        set_group(-31); tick(0, 1);
        tick(0, 0);
        tick(0, 0);
        set_group(55); tick(0, 1);
        tick(0, 0);
        tick(0, 0);
        if (extreme_results != 15) begin
            $display("FAIL extreme result count=%0d expected=15", extreme_results);
            failures = failures + 1;
        end
        if (failures == 0)
            $display("PASS directed: cycles=%0d valid_lane_results=%0d extreme_33bit_results=%0d", cycles, valid_results, extreme_results);
        else
            $display("FAIL directed: failures=%0d", failures);
        $finish;
    end
endmodule
