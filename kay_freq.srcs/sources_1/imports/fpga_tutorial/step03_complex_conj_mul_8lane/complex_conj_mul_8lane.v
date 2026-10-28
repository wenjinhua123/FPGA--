`timescale 1ns/1ps
module complex_conj_mul_8lane (
    input wire clk, rst, valid_in,
    input wire signed [15:0] i0, q0,
    input wire signed [15:0] i1, q1,
    input wire signed [15:0] i2, q2,
    input wire signed [15:0] i3, q3,
    input wire signed [15:0] i4, q4,
    input wire signed [15:0] i5, q5,
    input wire signed [15:0] i6, q6,
    input wire signed [15:0] i7, q7,
    output wire signed [32:0] re0, im0,
    output wire signed [32:0] re1, im1,
    output wire signed [32:0] re2, im2,
    output wire signed [32:0] re3, im3,
    output wire signed [32:0] re4, im4,
    output wire signed [32:0] re5, im5,
    output wire signed [32:0] re6, im6,
    output wire signed [32:0] re7, im7,
    output wire [7:0] valid_out
);
    // 只保存上一组最后一个有效样本，供下一组的第 0 路使用。
    reg signed [15:0] last_i7, last_q7;
    reg have_prev;

    always @(posedge clk) begin
        if (rst) begin
            last_i7 <= 16'sd0;
            last_q7 <= 16'sd0;
            have_prev <= 1'b0;
        end else if (valid_in) begin
            last_i7 <= i7;
            last_q7 <= q7;
            have_prev <= 1'b1;
        end
        // valid_in 为 0 只是传输暂停：历史保持，恢复后继续相邻计算。
        // 若开始一段不连续的采样记录，需要先复位。
    end

    // 第 0 路跨组相邻；复位后的第一组没有前驱，所以该路无效。
    // 子模块在当前上升沿保存乘积，紧接着的下一上升沿输出加减结果。
    complex_conj_mul_pipe lane0 (
        .clk(clk), .rst(rst), .valid_in(valid_in && have_prev),
        .i_now(i0), .q_now(q0),
        .i_prev(last_i7), .q_prev(last_q7),
        .valid_out(valid_out[0]), .re_out(re0), .im_out(im0)
    );

    // 第 1 到第 7 路的前驱，都是本组内紧邻的前一路。
    complex_conj_mul_pipe lane1 (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i_now(i1), .q_now(q1),
        .i_prev(i0), .q_prev(q0),
        .valid_out(valid_out[1]), .re_out(re1), .im_out(im1)
    );
    complex_conj_mul_pipe lane2 (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i_now(i2), .q_now(q2),
        .i_prev(i1), .q_prev(q1),
        .valid_out(valid_out[2]), .re_out(re2), .im_out(im2)
    );
    complex_conj_mul_pipe lane3 (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i_now(i3), .q_now(q3),
        .i_prev(i2), .q_prev(q2),
        .valid_out(valid_out[3]), .re_out(re3), .im_out(im3)
    );
    complex_conj_mul_pipe lane4 (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i_now(i4), .q_now(q4),
        .i_prev(i3), .q_prev(q3),
        .valid_out(valid_out[4]), .re_out(re4), .im_out(im4)
    );
    complex_conj_mul_pipe lane5 (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i_now(i5), .q_now(q5),
        .i_prev(i4), .q_prev(q4),
        .valid_out(valid_out[5]), .re_out(re5), .im_out(im5)
    );
    complex_conj_mul_pipe lane6 (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i_now(i6), .q_now(q6),
        .i_prev(i5), .q_prev(q5),
        .valid_out(valid_out[6]), .re_out(re6), .im_out(im6)
    );
    complex_conj_mul_pipe lane7 (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i_now(i7), .q_now(q7),
        .i_prev(i6), .q_prev(q6),
        .valid_out(valid_out[7]), .re_out(re7), .im_out(im7)
    );
endmodule
