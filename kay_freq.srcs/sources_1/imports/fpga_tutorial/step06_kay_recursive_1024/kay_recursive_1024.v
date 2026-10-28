`timescale 1ns/1ps
module kay_recursive_1024(
    input wire clk,
    input wire rst,
    input wire valid_in,
    input wire signed [31:0] phase_in,
    output reg valid_out,
    output reg signed [63:0] kay_sum
);
    // 1024 个原始 IQ 样本对应 1023 个相邻相位增量。
    // 从最旧到最新，权重为 j*(1024-j)，j=1..1023。
    // 输出只有整数分子，归一化分母为 178956800。
    reg signed [31:0] history [0:1022];
    reg [9:0] write_ptr;
    reg [9:0] fill_count;
    reg signed [63:0] sum0;  // S：窗口内相位增量之和
    reg signed [63:0] sum1;  // T：窗口内 j*x_j 之和

    // 必须先扩展到 64 位，再移位；否则 32 位移位会丢高位。
    wire signed [63:0] incoming;
    wire signed [63:0] outgoing;
    wire signed [63:0] incoming_times_1023;
    wire signed [63:0] sum0_times_1025;
    wire signed [63:0] next_sum0;
    wire signed [63:0] next_sum1;
    wire signed [63:0] next_kay_sum;

    assign incoming = {{32{phase_in[31]}}, phase_in};
    // 暖机阶段离开窗口的是零，不读取尚未写过的 RAM 内容。
    assign outgoing = (fill_count < 10'd1023) ? 64'sd0 :
                      {{32{history[write_ptr][31]}}, history[write_ptr]};
    assign incoming_times_1023 = (incoming <<< 10) - incoming;
    assign sum0_times_1025 = (sum0 <<< 10) + sum0;

    // 右侧全部使用旧状态；非阻塞赋值使三个状态同时更新。
    assign next_sum0 = sum0 - outgoing + incoming;
    assign next_sum1 = sum1 - sum0 + incoming_times_1023;
    assign next_kay_sum = kay_sum + (sum1 <<< 1)
                        - sum0_times_1025 + incoming_times_1023;

    // 同步高有效复位。RAM 不清零，fill_count 隔离其中的旧数据。
    always @(posedge clk) begin
        if (rst) begin
            write_ptr <= 10'd0;
            fill_count <= 10'd0;
            sum0 <= 64'sd0;
            sum1 <= 64'sd0;
            kay_sum <= 64'sd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b0;
            if (valid_in) begin
                history[write_ptr] <= phase_in;
                if (write_ptr == 10'd1022)
                    write_ptr <= 10'd0;
                else
                    write_ptr <= write_ptr + 10'd1;
                if (fill_count < 10'd1023)
                    fill_count <= fill_count + 10'd1;
                sum0 <= next_sum0;
                sum1 <= next_sum1;
                kay_sum <= next_kay_sum;
                valid_out <= (fill_count >= 10'd1022);
            end
        end
    end
    // valid_in=0 表示传输暂停，所有窗口状态保持。
    // 若相位记录本身不连续，应先复位，再开始一段新记录。
    // 这是单通道教学核心，尚未实现每拍 8 路吞吐。
endmodule
