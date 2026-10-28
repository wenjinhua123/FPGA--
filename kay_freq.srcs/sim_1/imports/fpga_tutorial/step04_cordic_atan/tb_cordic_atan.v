`timescale 1ns / 1ps

module tb_cordic_atan;
    reg aclk = 1'b0;
    reg aresetn = 1'b0;
    reg s_axis_cartesian_tvalid = 1'b0;
    reg [79:0] s_axis_cartesian_tdata = 80'b0;
    wire m_axis_dout_tvalid;
    wire [31:0] m_axis_dout_tdata;

    // 10 ns 时钟周期；本文件只验证已经生成的 CORDIC IP。
    always #5 aclk = ~aclk;
    cordic_atan dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_cartesian_tvalid(s_axis_cartesian_tvalid),
        .s_axis_cartesian_tdata(s_axis_cartesian_tdata),
        .m_axis_dout_tvalid(m_axis_dout_tvalid),
        .m_axis_dout_tdata(m_axis_dout_tdata)
    );

    localparam TOTAL = 13;
    real expected [0:TOTAL-1];
    integer input_cycle [0:TOTAL-1];
    integer cycle = 0;
    integer sent = 0;
    integer received = 0;
    integer errors = 0;
    integer latency = -1;
    integer this_latency;
    real measured;
    real angle_error;

    // 在下降沿准备输入，下一上升沿 IP 采样。
    // 两个 33 位 Q2.31 数分别补齐到 40 位，虚部在高位。
    task send_sample;
        input signed [32:0] re33;
        input signed [32:0] im33;
        input real expected_degrees;
        begin
            @(negedge aclk);
            expected[sent] = expected_degrees;
            input_cycle[sent] = cycle + 1;
            sent = sent + 1;
            s_axis_cartesian_tdata <= {7'b0, im33, 7'b0, re33};
            s_axis_cartesian_tvalid <= 1'b1;
        end
    endtask

    // 无效周期故意改变数据：输出只应该由 valid=1 的输入决定。
    task insert_gap;
        input integer clocks;
        begin
            @(negedge aclk);
            s_axis_cartesian_tvalid <= 1'b0;
            s_axis_cartesian_tdata <= {40'h123456789a, 40'h5abcdef012};
            repeat (clocks-1) @(negedge aclk);
        end
    endtask

    always @(posedge aclk) begin
        cycle = cycle + 1;
        // 等待 IP 本拍的寄存器更新，再读取输出。
        #0.1;
        if (aresetn) begin
            if ((m_axis_dout_tvalid !== 1'b0) &&
                (m_axis_dout_tvalid !== 1'b1)) begin
                errors = errors + 1;
                $display("FAIL: unknown output valid at cycle %0d", cycle);
            end else if (m_axis_dout_tvalid === 1'b1) begin
                if (received >= sent || received >= TOTAL) begin
                    errors = errors + 1;
                    $display("FAIL: unexpected extra output at cycle %0d", cycle);
                end else begin
                    this_latency = cycle - input_cycle[received];
                    if (latency < 0) latency = this_latency;
                    if (this_latency != latency) begin
                        errors = errors + 1;
                        $display("FAIL: latency %0d, expected %0d", this_latency, latency);
                    end
                    if ((^m_axis_dout_tdata) === 1'bx) begin
                        errors = errors + 1;
                        $display("FAIL: unknown phase for sample %0d", received+1);
                    end else begin
                        // Scaled Radians：P / 2^29 对应角度 / 180。
                        measured = $itor($signed(m_axis_dout_tdata)) * 180.0 / 536870912.0;
                        angle_error = measured - expected[received];
                        if (angle_error < 0.0) angle_error = -angle_error;
                        $display("sample %0d: expected=%0.9f deg measured=%0.9f deg error=%0.9f deg latency=%0d",
                                 received+1, expected[received], measured, angle_error, this_latency);
                        if (angle_error > 0.0001) begin
                            errors = errors + 1;
                            $display("FAIL: angle error exceeds 0.0001 degree");
                        end
                    end
                end
                received = received + 1;
            end
        end
    end

    initial begin
        // (0,0) 的相位没有定义，因此不作为有效输入发送。
        repeat (4) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        repeat (2) @(posedge aclk);
        send_sample( 33'sd536870912,  33'sd0,           0.0);
        send_sample( 33'sd536870912,  33'sd536870912,  45.0);
        send_sample( 33'sd536870912, -33'sd536870912, -45.0);
        insert_gap(2);
        send_sample( 33'sd0,          33'sd536870912,  90.0);
        send_sample( 33'sd0,         -33'sd536870912, -90.0);
        send_sample(-33'sd536870912,  33'sd536870912, 135.0);
        send_sample(-33'sd536870912, -33'sd536870912,-135.0);
        insert_gap(3);
        send_sample( 33'sd805306368,  33'sd1073741824, 53.130102354);
        // 100 MHz 的正、负相位差，以及 1 GHz 的第二、第三象限。
        send_sample( 33'sd520004125,  33'sd133514367,  14.4);
        send_sample( 33'sd520004125, -33'sd133514367, -14.4);
        send_sample(-33'sd434337692,  33'sd315564804, 144.0);
        send_sample(-33'sd434337692, -33'sd315564804,-144.0);
        // +1.0 在 33 位输入中合法，可帮助发现误用 32 位的情况。
        send_sample( 33'sd2147483648, 33'sd0,           0.0);
        insert_gap(1);
        repeat (80) @(negedge aclk);
        if (sent != TOTAL || received != TOTAL) begin
            errors = errors + 1;
            $display("FAIL: expected %0d samples, sent=%0d received=%0d", TOTAL, sent, received);
        end
        if (errors == 0)
            $display("PASS: sent=%0d received=%0d latency=%0d clocks errors=0", sent, received, latency);
        else
            $display("FAIL: sent=%0d received=%0d errors=%0d", sent, received, errors);
        $finish;
    end

    // 独立超时保护，防止测试因等待时钟或输出而一直运行。
    initial begin
        #5000;
        $display("FAIL: simulation timeout, sent=%0d received=%0d", sent, received);
        $finish;
    end
endmodule
