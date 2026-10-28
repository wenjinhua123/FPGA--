`timescale 1ns/1ps

// The proven Step08 chain is the reference. The new chain must reproduce
// every frequency and valid bit after its fixed additional pipeline delay.
module tb_iq_kay_freq_8lane_lookahead #(
    parameter integer EXTRA_LATENCY = 10
);
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg valid_in = 1'b0;
    reg signed [15:0] ii [0:7];
    reg signed [15:0] qq [0:7];
    wire [7:0] old_valid, new_valid;
    wire signed [31:0] old_freq [0:7], new_freq [0:7];
    reg [7:0] delayed_valid [0:EXTRA_LATENCY];
    reg signed [31:0] delayed_freq [0:EXTRA_LATENCY][0:7];
    integer cycles = 0, groups = 0, checked_outputs = 0;
    integer bubbles = 0, resets = 0;
    integer groups_after_reset = 0, first_target_cycle = -1;
    integer first_masks_checked = 0, golden_checked = 0;
    integer lane_outputs [0:7];
    integer recovery_outputs [0:7];
    integer recovery_start_cycle = -1, recovery_stop_cycle = -1;
    integer scenario = 0;
    integer golden_tag [0:2047]; // +1=100 MHz, -1=-100 MHz
    integer stage, lane, group_index;
    real expected_mhz, actual_mhz, error_mhz;
    real phase_acc = 0.0;
    real tone_mhz = 100.0;
    localparam real PI = 3.14159265358979323846;

    iq_kay_freq_8lane reference_chain (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i0(ii[0]), .q0(qq[0]), .i1(ii[1]), .q1(qq[1]),
        .i2(ii[2]), .q2(qq[2]), .i3(ii[3]), .q3(qq[3]),
        .i4(ii[4]), .q4(qq[4]), .i5(ii[5]), .q5(qq[5]),
        .i6(ii[6]), .q6(qq[6]), .i7(ii[7]), .q7(qq[7]),
        .valid_out(old_valid),
        .freq0(old_freq[0]), .freq1(old_freq[1]),
        .freq2(old_freq[2]), .freq3(old_freq[3]),
        .freq4(old_freq[4]), .freq5(old_freq[5]),
        .freq6(old_freq[6]), .freq7(old_freq[7])
    );

    iq_kay_freq_8lane_lookahead dut (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i0(ii[0]), .q0(qq[0]), .i1(ii[1]), .q1(qq[1]),
        .i2(ii[2]), .q2(qq[2]), .i3(ii[3]), .q3(qq[3]),
        .i4(ii[4]), .q4(qq[4]), .i5(ii[5]), .q5(qq[5]),
        .i6(ii[6]), .q6(qq[6]), .i7(ii[7]), .q7(qq[7]),
        .valid_out(new_valid),
        .freq0(new_freq[0]), .freq1(new_freq[1]),
        .freq2(new_freq[2]), .freq3(new_freq[3]),
        .freq4(new_freq[4]), .freq5(new_freq[5]),
        .freq6(new_freq[6]), .freq7(new_freq[7])
    );

    always #5 clk = ~clk;

    // Both reference and DUT have committed their clocked assignments at #1.
    always @(posedge clk) begin
        #1;
        cycles = cycles + 1;
        if (rst) begin
            resets = resets + 1;
            groups_after_reset = 0;
            first_target_cycle = -1;
            for (stage = 0; stage < 2048; stage = stage + 1)
                golden_tag[stage] = 0;
            for (stage = 0; stage <= EXTRA_LATENCY; stage = stage + 1) begin
                delayed_valid[stage] = 8'h00;
                for (lane = 0; lane < 8; lane = lane + 1)
                    delayed_freq[stage][lane] = 32'sd0;
            end
        end else begin
            if (valid_in) begin
                groups = groups + 1;
                groups_after_reset = groups_after_reset + 1;
                if (groups_after_reset == 128)
                    first_target_cycle = cycles + 43 + EXTRA_LATENCY;
                // These input groups are safely inside a settled tone section.
                if (scenario == 1 && groups_after_reset >= 140 && groups_after_reset <= 160)
                    golden_tag[cycles + 43 + EXTRA_LATENCY] = 1;
                if (scenario == 2 && groups_after_reset >= 140 && groups_after_reset <= 170)
                    golden_tag[cycles + 43 + EXTRA_LATENCY] = -1;
            end else bubbles = bubbles + 1;
            for (stage = EXTRA_LATENCY; stage > 0; stage = stage - 1) begin
                delayed_valid[stage] = delayed_valid[stage-1];
                for (lane = 0; lane < 8; lane = lane + 1)
                    delayed_freq[stage][lane] = delayed_freq[stage-1][lane];
            end
            delayed_valid[0] = old_valid;
            for (lane = 0; lane < 8; lane = lane + 1)
                delayed_freq[0][lane] = old_freq[lane];
        end
        if (new_valid !== delayed_valid[EXTRA_LATENCY])
            $fatal(1, "FAIL cycle=%0d valid old_delayed=%02h new=%02h",
                   cycles, delayed_valid[EXTRA_LATENCY], new_valid);
        if (cycles == first_target_cycle) begin
            if (new_valid !== 8'h80)
                $fatal(1, "FAIL first window cycle=%0d expected=80 got=%02h", cycles, new_valid);
            first_masks_checked = first_masks_checked + 1;
            first_target_cycle = -1;
        end
        for (lane = 0; lane < 8; lane = lane + 1) begin
            if (new_freq[lane] !== delayed_freq[EXTRA_LATENCY][lane])
                $fatal(1, "FAIL cycle=%0d lane=%0d freq old_delayed=%0d new=%0d",
                       cycles, lane, delayed_freq[EXTRA_LATENCY][lane], new_freq[lane]);
            if (new_valid[lane]) begin
                checked_outputs = checked_outputs + 1;
                lane_outputs[lane] = lane_outputs[lane] + 1;
                if (recovery_start_cycle >= 0 && cycles >= recovery_start_cycle &&
                    (recovery_stop_cycle < 0 || cycles < recovery_stop_cycle))
                    recovery_outputs[lane] = recovery_outputs[lane] + 1;
            end
            if (golden_tag[cycles] != 0) begin
                if (!new_valid[lane])
                    $fatal(1, "FAIL golden valid cycle=%0d lane=%0d", cycles, lane);
                expected_mhz = 100.0 * golden_tag[cycles];
                actual_mhz = $itor($signed(new_freq[lane])) / 1048576.0;
                error_mhz = actual_mhz - expected_mhz;
                if (error_mhz < 0.0) error_mhz = -error_mhz;
                if (error_mhz > 0.005)
                    $fatal(1, "FAIL IQ golden cycle=%0d lane=%0d actual=%f expected=%f MHz",
                           cycles, lane, actual_mhz, expected_mhz);
                golden_checked = golden_checked + 1;
            end
        end
    end

    task send_group;
        input accepted;
        input integer mode;  // 0=tone, 1=all zero, 2=alternate zero
        integer g;
        begin
            @(negedge clk);
            valid_in = accepted;
            for (g = 0; g < 8; g = g + 1) begin
                ii[g] = $rtoi(12000.0*$cos(phase_acc));
                qq[g] = $rtoi(12000.0*$sin(phase_acc));
                if (mode == 1 || (mode == 2 && g % 2 == 0)) begin
                    ii[g] = 16'sd0;
                    qq[g] = 16'sd0;
                end
                // A bubble is not a consumed IQ group: preserve sample time.
                if (accepted) begin
                    phase_acc = phase_acc + 2.0*PI*tone_mhz/2500.0;
                    if (phase_acc > PI) phase_acc = phase_acc - 2.0*PI;
                    if (phase_acc < -PI) phase_acc = phase_acc + 2.0*PI;
                end
            end
            if (accepted && mode == 1)
                recovery_start_cycle = cycles + 140 + 43 + EXTRA_LATENCY;
            if (accepted && mode == 2)
                recovery_stop_cycle = cycles + 43 + EXTRA_LATENCY;
            @(posedge clk);
            #2;
        end
    endtask

    task reset_chain;
        begin
            @(negedge clk);
            rst = 1'b1;
            valid_in = 1'b0;
            repeat (4) @(posedge clk);
            #2;
            @(negedge clk);
            rst = 1'b0;
            phase_acc = 0.0;
        end
    endtask

    initial begin
        if (EXTRA_LATENCY < 4 || EXTRA_LATENCY > 16)
            $fatal(1, "FAIL unsupported EXTRA_LATENCY=%0d", EXTRA_LATENCY);
        for (lane = 0; lane < 8; lane = lane + 1) begin
            ii[lane] = 16'sd0;
            qq[lane] = 16'sd0;
            lane_outputs[lane] = 0;
            recovery_outputs[lane] = 0;
        end
        for (group_index = 0; group_index < 2048; group_index = group_index + 1)
            golden_tag[group_index] = 0;
        reset_chain();
        scenario = 1;
        for (group_index = 0; group_index < 170; group_index = group_index + 1) begin
            if (group_index % 11 == 4) send_group(1'b0, 0);
            send_group(1'b1, 0);
        end
        tone_mhz = 1000.0;
        for (group_index = 0; group_index < 170; group_index = group_index + 1)
            send_group(1'b1, 0);
        send_group(1'b1, 1);
        for (group_index = 0; group_index < 170; group_index = group_index + 1)
            send_group(1'b1, 0);
        send_group(1'b1, 2);
        for (group_index = 0; group_index < 170; group_index = group_index + 1)
            send_group(1'b1, 0);
        // Flush a partly occupied pipeline and verify it restarts cleanly.
        for (group_index = 0; group_index < 10; group_index = group_index + 1)
            send_group(1'b1, 0);
        reset_chain();
        scenario = 2;
        tone_mhz = -100.0;
        for (group_index = 0; group_index < 180; group_index = group_index + 1)
            send_group(1'b1, 0);
        for (group_index = 0; group_index < 55; group_index = group_index + 1)
            send_group(1'b0, 0);
        if (checked_outputs < 100 || bubbles == 0 || resets < 8 ||
            first_masks_checked != 2 || golden_checked < 300)
            $fatal(1, "FAIL coverage outputs=%0d bubbles=%0d resets=%0d first=%0d golden=%0d",
                   checked_outputs, bubbles, resets, first_masks_checked, golden_checked);
        for (lane = 0; lane < 8; lane = lane + 1)
            if (lane_outputs[lane] < 100 || recovery_outputs[lane] == 0)
                $fatal(1, "FAIL lane coverage lane=%0d outputs=%0d recovery=%0d",
                       lane, lane_outputs[lane], recovery_outputs[lane]);
        $display("COVERAGE first_windows=%0d IQ_golden=%0d recovery_min=%0d",
                 first_masks_checked, golden_checked, recovery_outputs[0]);
        $display("PASS full_chain groups=%0d lane_outputs=%0d latency=%0d cycles=%0d",
                 groups, checked_outputs, 43+EXTRA_LATENCY, cycles);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL simulation timeout");
    end
endmodule
