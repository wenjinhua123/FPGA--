`timescale 1ns/1ps

module tb_complex_conj_mul_pipe;
    reg clk = 0;
    reg rst = 0, valid_in = 0;
    reg signed [15:0] i_now = 0, q_now = 0, i_prev = 0, q_prev = 0;
    wire valid_out;
    wire signed [32:0] re_out, im_out;
    reg pending = 0;
    reg signed [32:0] expected_re = 0, expected_im = 0;
    reg signed [32:0] held_re = 0, held_im = 0;
    integer cycles = 0, results = 0;

    complex_conj_mul_pipe dut (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i_now(i_now), .q_now(q_now), .i_prev(i_prev), .q_prev(q_prev),
        .valid_out(valid_out), .re_out(re_out), .im_out(im_out)
    );
    always #50 clk = ~clk;

    // 在下降沿送入数据；上升沿后等待非阻塞赋值完成再检查。
    task tick;
        input reset_now, valid_now;
        input signed [15:0] a, b, c, d;
        input signed [32:0] next_re, next_im;
        begin
            @(negedge clk);
            rst = reset_now;
            valid_in = valid_now;
            i_now = a; q_now = b; i_prev = c; q_prev = d;
            @(posedge clk); #0.1;
            cycles = cycles + 1;
            if (reset_now) begin
                if (valid_out !== 1'b0 || re_out !== 33'sd0 || im_out !== 33'sd0)
                    $fatal(1, "FAIL reset cycle=%0d", cycles);
                pending = 0;
                held_re = 0; held_im = 0;
            end else begin
                // 先检查上一拍进入乘法寄存器的数据，再记录这一拍。
                if (valid_out !== pending)
                    $fatal(1, "FAIL valid cycle=%0d expected=%b got=%b", cycles, pending, valid_out);
                if (pending) begin
                    if (re_out !== expected_re || im_out !== expected_im)
                        $fatal(1, "FAIL result cycle=%0d expected=(%0d,%0d) got=(%0d,%0d)",
                               cycles, expected_re, expected_im, re_out, im_out);
                    held_re = expected_re; held_im = expected_im;
                    results = results + 1;
                end else if (re_out !== held_re || im_out !== held_im)
                    $fatal(1, "FAIL output must hold cycle=%0d", cycles);
                pending = valid_now;
                expected_re = next_re; expected_im = next_im;
            end
        end
    endtask

    initial begin
        // 初始复位；连续输入；空拍时仍须输出前一拍的数据。
        tick(1, 0, 0, 0, 0, 0, 0, 0);
        tick(0, 1, 3, 4, 1, 2, 11, -2);
        tick(0, 1, 0, 1, 1, 0, 0, 1);
        tick(0, 0, 9, 8, 7, 6, 0, 0);
        tick(0, 0, -9, -8, -7, -6, 0, 0);
        // 单独一个有效输入，后面留两个空拍。
        tick(0, 1, 1, 0, 0, 1, 0, -1);
        tick(0, 0, 5, 6, 7, 8, 0, 0);
        tick(0, 0, 0, 0, 0, 0, 0, 0);
        tick(0, 1, -3, 4, 1, -2, -11, -2);
        tick(0, 1, 0, 0, 123, -456, 0, 0);
        tick(0, 1, -32768, -32768, -32768, -32768, 33'sd2147483648, 0);
        tick(0, 1, 32767, 32767, 32767, 32767, 33'sd2147352578, 0);
        tick(0, 0, 1, 2, 3, 4, 0, 0);
        tick(0, 0, 4, 3, 2, 1, 0, 0);
        // 同步复位优先：丢弃待输出数据，也不接收复位拍的有效输入。
        tick(0, 1, 3, 4, 1, 2, 11, -2);
        tick(1, 1, 0, 1, 1, 0, 0, 1);
        tick(0, 0, 0, 0, 0, 0, 0, 0);
        tick(0, 1, -3, 4, 1, -2, -11, -2);
        tick(0, 0, 7, 7, 7, 7, 0, 0);
        tick(0, 0, 0, 0, 0, 0, 0, 0);
        if (results !== 8) $fatal(1, "FAIL result count=%0d", results);
        $display("PASS: %0d checked cycles, %0d valid results; reset, bubbles, hold, restart", cycles, results);
        $finish;
    end
endmodule
