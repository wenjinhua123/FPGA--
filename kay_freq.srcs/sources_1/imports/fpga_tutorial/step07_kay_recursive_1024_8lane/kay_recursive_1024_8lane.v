`timescale 1ns/1ps
// 1024 个 IQ 点对应 1023 个相邻相位差；每拍按 phase0 到 phase7 顺序处理。
// 权重 c_j=j*(1024-j)，j=1..1023；归一化分母为 178956800。
// 此模块输出带权分子，软件或后级再做归一化和频率换算。
module kay_recursive_1024_8lane (
    input clk, input rst, input group_valid_in,
    input [7:0] phase_valid_in,
    input signed [31:0] phase0, phase1, phase2, phase3,
    input signed [31:0] phase4, phase5, phase6, phase7,
    output reg [7:0] valid_out,
    output reg signed [63:0] kay_sum0, kay_sum1, kay_sum2, kay_sum3,
    output reg signed [63:0] kay_sum4, kay_sum5, kay_sum6, kay_sum7
);
    // 1024 个物理槽分为 8 组存储（bank），保存同一条时间序列。
    // 它们不是八套互相独立的滑动窗口；实际窗口始终只有 1023 项。
    reg signed [31:0] bank0 [0:127];
    reg signed [31:0] bank1 [0:127];
    reg signed [31:0] bank2 [0:127];
    reg signed [31:0] bank3 [0:127];
    reg signed [31:0] bank4 [0:127];
    reg signed [31:0] bank5 [0:127];
    reg signed [31:0] bank6 [0:127];
    reg signed [31:0] bank7 [0:127];
    reg [6:0] row;
    wire [6:0] next_row = row + 7'd1;
    reg signed [63:0] sum_s, sum_t, sum_w;
    reg [9:0] fill;

    wire signed [31:0] incoming [0:7];
    wire signed [31:0] outgoing [0:7];
    wire signed [63:0] stage_s [0:8];
    wire signed [63:0] stage_t [0:8];
    wire signed [63:0] stage_w [0:8];
    wire [9:0] stage_fill [0:8];
    wire [7:0] lane_valid;
    assign incoming[0] = phase0;
    assign incoming[1] = phase1;
    assign incoming[2] = phase2;
    assign incoming[3] = phase3;
    assign incoming[4] = phase4;
    assign incoming[5] = phase5;
    assign incoming[6] = phase6;
    assign incoming[7] = phase7;

    // 1023 比物理容量少一项，因此出窗项比当前写入位置前进一槽。
    // 最后一条通道跨到下一行；7 位 next_row 在 127 后自然回到 0。
    assign outgoing[0] = bank1[row];
    assign outgoing[1] = bank2[row];
    assign outgoing[2] = bank3[row];
    assign outgoing[3] = bank4[row];
    assign outgoing[4] = bank5[row];
    assign outgoing[5] = bank6[row];
    assign outgoing[6] = bank7[row];
    assign outgoing[7] = bank0[next_row];
    assign stage_s[0] = sum_s;
    assign stage_t[0] = sum_t;
    assign stage_w[0] = sum_w;
    assign stage_fill[0] = fill;

    // generate 展开八级组合硬件，一拍内依次得到八个窗口结果。
    // 每一级都引用前一级旧 S/T/W，避免顺序更新临时变量产生歧义。
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : lanes
            wire signed [63:0] b;
            wire signed [63:0] a;
            wire signed [63:0] b_times_1023;
            wire signed [63:0] s_times_1025;
            // 必须先扩展到 64 位再移位，保留负数及 32 位极值。
            assign b = {{32{incoming[g][31]}}, incoming[g]};
            assign a = (stage_fill[g] == 10'd1023) ?
                       {{32{outgoing[g][31]}}, outgoing[g]} : 64'sd0;
            assign b_times_1023 = (b <<< 10) - b;
            assign s_times_1025 = (stage_s[g] <<< 10) + stage_s[g];
            // S'=S-a+b；T'=T-S+1023b；W'=W+2T-1025S+1023b。
            assign stage_s[g+1] = phase_valid_in[g] ?
                         stage_s[g] - a + b : 64'sd0;
            assign stage_t[g+1] = phase_valid_in[g] ?
                         stage_t[g] - stage_s[g] + b_times_1023 : 64'sd0;
            assign stage_w[g+1] = phase_valid_in[g] ?
                         stage_w[g] + (stage_t[g] <<< 1) -
                         s_times_1025 + b_times_1023 : 64'sd0;
            assign stage_fill[g+1] = !phase_valid_in[g] ? 10'd0 :
                         ((stage_fill[g] < 10'd1023) ?
                           stage_fill[g] + 10'd1 : 10'd1023);
            assign lane_valid[g] = phase_valid_in[g] &&
                                   (stage_fill[g] >= 10'd1022);
        end
    endgenerate

    // 同步高有效复位；存储器不清零，填充计数屏蔽陈旧数据。
    always @(posedge clk) begin
        if (rst) begin
            row <= 7'd0;
            sum_s <= 64'sd0;
            sum_t <= 64'sd0;
            sum_w <= 64'sd0;
            fill <= 10'd0;
            valid_out <= 8'h00;
            kay_sum0 <= 64'sd0;
            kay_sum1 <= 64'sd0;
            kay_sum2 <= 64'sd0;
            kay_sum3 <= 64'sd0;
            kay_sum4 <= 64'sd0;
            kay_sum5 <= 64'sd0;
            kay_sum6 <= 64'sd0;
            kay_sum7 <= 64'sd0;
        end else begin
            valid_out <= 8'h00;
            if (group_valid_in) begin
                // 即使掩码为 00，也接受这一组并推进物理行号。
                bank0[row] <= phase_valid_in[0] ? phase0 : 32'sd0;
                bank1[row] <= phase_valid_in[1] ? phase1 : 32'sd0;
                bank2[row] <= phase_valid_in[2] ? phase2 : 32'sd0;
                bank3[row] <= phase_valid_in[3] ? phase3 : 32'sd0;
                bank4[row] <= phase_valid_in[4] ? phase4 : 32'sd0;
                bank5[row] <= phase_valid_in[5] ? phase5 : 32'sd0;
                bank6[row] <= phase_valid_in[6] ? phase6 : 32'sd0;
                bank7[row] <= phase_valid_in[7] ? phase7 : 32'sd0;
                // 非阻塞写入保证本拍组合运算读取的是覆盖前的旧样本。
                row <= next_row;
                sum_s <= stage_s[8];
                sum_t <= stage_t[8];
                sum_w <= stage_w[8];
                fill <= stage_fill[8];
                valid_out <= lane_valid;
                kay_sum0 <= stage_w[1];
                kay_sum1 <= stage_w[2];
                kay_sum2 <= stage_w[3];
                kay_sum3 <= stage_w[4];
                kay_sum4 <= stage_w[5];
                kay_sum5 <= stage_w[6];
                kay_sum6 <= stage_w[7];
                kay_sum7 <= stage_w[8];
            end
        end
    end
    // 这是功能教学实现；八级组合路径的时序、资源及存储映射需另行验证。
endmodule
