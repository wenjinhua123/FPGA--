`timescale 1ns/1ps
module complex_conj_mul_pipe (
    input wire clk, rst, valid_in,
    input wire signed [15:0] i_now, q_now, i_prev, q_prev,
    output reg valid_out,
    output reg signed [32:0] re_out, im_out
);
    reg valid_stage1;
    reg signed [31:0] product_ii, product_qq, product_qi, product_iq;

    // 两级寄存器：这一拍做乘法，紧接着的下一拍做加减法。
    always @(posedge clk) begin
        if (rst) begin
            product_ii <= 32'sd0;
            product_qq <= 32'sd0;
            product_qi <= 32'sd0;
            product_iq <= 32'sd0;
            valid_stage1 <= 1'b0;
            valid_out <= 1'b0;
            re_out <= 33'sd0;
            im_out <= 33'sd0;
        end else begin
            valid_stage1 <= valid_in;
            valid_out <= valid_stage1;

            // 第一级：仅在输入有效时保存四个有符号乘积。
            if (valid_in) begin
                product_ii <= i_now * i_prev;
                product_qq <= q_now * q_prev;
                product_qi <= q_now * i_prev;
                product_iq <= i_now * q_prev;
            end

            // 第二级：先各自符号扩展到 33 位，再进行加减。
            // 非阻塞赋值读取旧乘积；无有效数据时结果保持。
            if (valid_stage1) begin
                re_out <= $signed({product_ii[31], product_ii})
                        + $signed({product_qq[31], product_qq});
                im_out <= $signed({product_qi[31], product_qi})
                        - $signed({product_iq[31], product_iq});
            end
        end
    end
endmodule
