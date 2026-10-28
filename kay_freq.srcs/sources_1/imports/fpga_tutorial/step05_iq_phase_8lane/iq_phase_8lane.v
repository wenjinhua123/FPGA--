`timescale 1ns/1ps
module iq_phase_8lane (
    input wire clk, rst, valid_in,
    input wire signed [15:0] i0, q0,
    input wire signed [15:0] i1, q1,
    input wire signed [15:0] i2, q2,
    input wire signed [15:0] i3, q3,
    input wire signed [15:0] i4, q4,
    input wire signed [15:0] i5, q5,
    input wire signed [15:0] i6, q6,
    input wire signed [15:0] i7, q7,
    output wire signed [31:0] phase0, phase1, phase2, phase3,
    output wire signed [31:0] phase4, phase5, phase6, phase7,
    output wire [7:0] valid_out
);
    // rst 同步高有效；保持至少 2 个时钟，建议 4 个，以满足 CORDIC 复位要求。
    // valid_in 为 0 表示传输暂停，历史样本保持；新的一段不连续记录须先复位。
    wire signed [32:0] re0, im0, re1, im1, re2, im2, re3, im3;
    wire signed [32:0] re4, im4, re5, im5, re6, im6, re7, im7;
    wire [7:0] pair_valid;
    complex_conj_mul_8lane pair_mul (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i0(i0), .q0(q0), .i1(i1), .q1(q1),
        .i2(i2), .q2(q2), .i3(i3), .q3(q3),
        .i4(i4), .q4(q4), .i5(i5), .q5(q5),
        .i6(i6), .q6(q6), .i7(i7), .q7(q7),
        .re0(re0), .im0(im0), .re1(re1), .im1(im1),
        .re2(re2), .im2(im2), .re3(re3), .im3(im3),
        .re4(re4), .im4(im4), .re5(re5), .im5(im5),
        .re6(re6), .im6(im6), .re7(re7), .im7(im7),
        .valid_out(pair_valid)
    );

    // Cartesian 的每个 33 位分量独占 40 位字段；高 7 位为 AXI 字节对齐填充。
    // 零复数没有相位，禁止送入 CORDIC。无效输出路的 phase 数据必须忽略。
    // IP 输出 P = phase/pi * 2^29；这里只输出相位编码，不增加寄存器或换算 Hz。
    cordic_atan phase_lane0 (
        .aclk(clk), .aresetn(~rst),
        .s_axis_cartesian_tvalid(pair_valid[0] && ((re0 != 0) || (im0 != 0))),
        .s_axis_cartesian_tdata({7'b0, im0, 7'b0, re0}),
        .m_axis_dout_tvalid(valid_out[0]), .m_axis_dout_tdata(phase0)
    );
    cordic_atan phase_lane1 (
        .aclk(clk), .aresetn(~rst),
        .s_axis_cartesian_tvalid(pair_valid[1] && ((re1 != 0) || (im1 != 0))),
        .s_axis_cartesian_tdata({7'b0, im1, 7'b0, re1}),
        .m_axis_dout_tvalid(valid_out[1]), .m_axis_dout_tdata(phase1)
    );
    cordic_atan phase_lane2 (
        .aclk(clk), .aresetn(~rst),
        .s_axis_cartesian_tvalid(pair_valid[2] && ((re2 != 0) || (im2 != 0))),
        .s_axis_cartesian_tdata({7'b0, im2, 7'b0, re2}),
        .m_axis_dout_tvalid(valid_out[2]), .m_axis_dout_tdata(phase2)
    );
    cordic_atan phase_lane3 (
        .aclk(clk), .aresetn(~rst),
        .s_axis_cartesian_tvalid(pair_valid[3] && ((re3 != 0) || (im3 != 0))),
        .s_axis_cartesian_tdata({7'b0, im3, 7'b0, re3}),
        .m_axis_dout_tvalid(valid_out[3]), .m_axis_dout_tdata(phase3)
    );
    cordic_atan phase_lane4 (
        .aclk(clk), .aresetn(~rst),
        .s_axis_cartesian_tvalid(pair_valid[4] && ((re4 != 0) || (im4 != 0))),
        .s_axis_cartesian_tdata({7'b0, im4, 7'b0, re4}),
        .m_axis_dout_tvalid(valid_out[4]), .m_axis_dout_tdata(phase4)
    );
    cordic_atan phase_lane5 (
        .aclk(clk), .aresetn(~rst),
        .s_axis_cartesian_tvalid(pair_valid[5] && ((re5 != 0) || (im5 != 0))),
        .s_axis_cartesian_tdata({7'b0, im5, 7'b0, re5}),
        .m_axis_dout_tvalid(valid_out[5]), .m_axis_dout_tdata(phase5)
    );
    cordic_atan phase_lane6 (
        .aclk(clk), .aresetn(~rst),
        .s_axis_cartesian_tvalid(pair_valid[6] && ((re6 != 0) || (im6 != 0))),
        .s_axis_cartesian_tdata({7'b0, im6, 7'b0, re6}),
        .m_axis_dout_tvalid(valid_out[6]), .m_axis_dout_tdata(phase6)
    );
    cordic_atan phase_lane7 (
        .aclk(clk), .aresetn(~rst),
        .s_axis_cartesian_tvalid(pair_valid[7] && ((re7 != 0) || (im7 != 0))),
        .s_axis_cartesian_tdata({7'b0, im7, 7'b0, re7}),
        .m_axis_dout_tvalid(valid_out[7]), .m_axis_dout_tdata(phase7)
    );
endmodule
