`timescale 1ns/1ps
module iq_kay_freq_8lane_lookahead (
    input wire clk, rst, valid_in,
    input wire signed [15:0] i0, q0, i1, q1, i2, q2, i3, q3,
    input wire signed [15:0] i4, q4, i5, q5, i6, q6, i7, q7,
    output wire [7:0] valid_out,
    output wire signed [31:0] freq0, freq1, freq2, freq3, freq4, freq5, freq6, freq7
);
    // 每拍输入连续的 8 个复数采样点，0 最早，7 最晚。
    // rst 为同步高电平复位，清空流水线有效标志和状态。
    wire signed [31:0] phase [0:7];
    wire [7:0] phase_valid, kay_valid;
    wire signed [63:0] raw_sum [0:7];
    wire signed [31:0] frequency [0:7];
    reg [37:0] group_pipe;
    always @(posedge clk) begin
        if (rst) group_pipe <= 38'd0;
        else group_pipe <= {group_pipe[36:0], valid_in};
    end

    iq_phase_8lane phase_frontend (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i0(i0), .q0(q0), .i1(i1), .q1(q1), .i2(i2), .q2(q2), .i3(i3), .q3(q3),
        .i4(i4), .q4(q4), .i5(i5), .q5(q5), .i6(i6), .q6(q6), .i7(i7), .q7(q7),
        .phase0(phase[0]), .phase1(phase[1]), .phase2(phase[2]), .phase3(phase[3]),
        .phase4(phase[4]), .phase5(phase[5]), .phase6(phase[6]), .phase7(phase[7]),
        .valid_out(phase_valid)
    );
    // 将输入组有效标志延迟到 CORDIC 相位结果到达。
    // 当前 CORDIC 相位链路延迟 37 拍；修改 IP 配置后须重新核对。
    kay_lookahead_1024_8lane kay_window (
        .clk(clk), .rst(rst), .group_valid_in(group_pipe[37]), .phase_valid_in(phase_valid),
        .phase0(phase[0]), .phase1(phase[1]), .phase2(phase[2]), .phase3(phase[3]),
        .phase4(phase[4]), .phase5(phase[5]), .phase6(phase[6]), .phase7(phase[7]),
        .valid_out(kay_valid),
        .kay_sum0(raw_sum[0]), .kay_sum1(raw_sum[1]), .kay_sum2(raw_sum[2]), .kay_sum3(raw_sum[3]),
        .kay_sum4(raw_sum[4]), .kay_sum5(raw_sum[5]), .kay_sum6(raw_sum[6]), .kay_sum7(raw_sum[7])
    );
    genvar lane;
    generate for (lane = 0; lane < 8; lane = lane + 1) begin : convert_lane
        kay_sum_to_freq_q20_plus1 convert (
            .clk(clk), .rst(rst), .valid_in(kay_valid[lane]), .kay_sum_in(raw_sum[lane]),
            .valid_out(valid_out[lane]), .freq_q20(frequency[lane])
        );
    end endgenerate
    assign freq0 = frequency[0]; assign freq1 = frequency[1];
    assign freq2 = frequency[2]; assign freq3 = frequency[3];
    assign freq4 = frequency[4]; assign freq5 = frequency[5];
    assign freq6 = frequency[6]; assign freq7 = frequency[7];
    // Full-chain latency = 43 base + 9 Kay pipeline + 1 converter = 53 clocks.
    // Frequency outputs use signed Fix32_20 units of MHz.
endmodule
