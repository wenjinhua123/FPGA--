`timescale 1ns / 1ps

module tb_complex_conj_mul;
    reg signed [15:0] i_now, q_now, i_prev, q_prev;
    wire signed [32:0] re_out, im_out;
    integer errors = 0;
    integer tests = 0;

    complex_conj_mul dut (
        .i_now(i_now), .q_now(q_now),
        .i_prev(i_prev), .q_prev(q_prev),
        .re_out(re_out), .im_out(im_out)
    );

    task check;
        input signed [15:0] a, b, c, d;
        input signed [32:0] expected_re, expected_im;
        begin
            i_now = a; q_now = b;
            i_prev = c; q_prev = d;
            #10;
            tests = tests + 1;
            if (re_out !== expected_re || im_out !== expected_im) begin
                errors = errors + 1;
                $display("FAIL test %0d: inputs=(%0d,%0d,%0d,%0d)",
                         tests, a, b, c, d);
                $display("  got=(%0d,%0d), expected=(%0d,%0d)",
                         re_out, im_out, expected_re, expected_im);
            end
        end
    endtask

    initial begin
        check(3, 4, 1, 2, 33'sd11, -33'sd2);
        check(0, 1, 1, 0, 33'sd0, 33'sd1);
        check(1, 0, 0, 1, 33'sd0, -33'sd1);
        check(-3, 4, 1, -2, -33'sd11, -33'sd2);
        check(0, 0, 123, -456, 33'sd0, 33'sd0);
        check(-32768, -32768, -32768, -32768,
              33'sd2147483648, 33'sd0);
        check(32767, 32767, 32767, 32767,
              33'sd2147352578, 33'sd0);

        if (errors == 0)
            $display("PASS: all %0d complex conjugate multiply tests passed.", tests);
        else
            $display("FAIL: %0d of %0d tests failed.", errors, tests);
        $finish;
    end
endmodule