`timescale 1ns/1ps

module tb_kay_lookahead_1024_8lane #(
    parameter integer EXTRA_LATENCY = 0
);
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg group_valid_in = 1'b0;
    reg [7:0] phase_valid_in = 8'h00;
    reg signed [31:0] phase [0:7];
    wire [7:0] reference_valid;
    wire [7:0] actual_valid;
    wire signed [63:0] reference_sum [0:7];
    wire signed [63:0] actual_sum [0:7];

    // Entry zero is the reference result from the current input edge.
    // Entry EXTRA_LATENCY is the result expected at the new output edge.
    reg [7:0] expected_valid [0:EXTRA_LATENCY];
    reg signed [63:0] expected_sum [0:EXTRA_LATENCY][0:7];
    integer expected_cycle [0:EXTRA_LATENCY];
    integer expected_group [0:EXTRA_LATENCY];
    integer expected_scenario [0:EXTRA_LATENCY];
    reg expected_mask [0:EXTRA_LATENCY];

    integer cycles = 0;
    integer accepted_groups = 0;
    integer groups_since_reset = 0;
    integer row_wraps = 0;
    integer checked_lanes = 0;
    integer masks_tested = 0;
    integer checked_masks = 0;
    integer bubbles = 0;
    integer scenario = 0;
    integer sample_index = 0;
    reg [31:0] random_state = 32'h6d2b79f5;
    reg mark_mask = 1'b0;
    integer depth;
    integer lane;
    integer group_index;
    integer mask_index;

    kay_recursive_1024_8lane reference_core (
        .clk(clk), .rst(rst), .group_valid_in(group_valid_in),
        .phase_valid_in(phase_valid_in),
        .phase0(phase[0]), .phase1(phase[1]),
        .phase2(phase[2]), .phase3(phase[3]),
        .phase4(phase[4]), .phase5(phase[5]),
        .phase6(phase[6]), .phase7(phase[7]),
        .valid_out(reference_valid),
        .kay_sum0(reference_sum[0]), .kay_sum1(reference_sum[1]),
        .kay_sum2(reference_sum[2]), .kay_sum3(reference_sum[3]),
        .kay_sum4(reference_sum[4]), .kay_sum5(reference_sum[5]),
        .kay_sum6(reference_sum[6]), .kay_sum7(reference_sum[7])
    );

    kay_lookahead_1024_8lane dut (
        .clk(clk), .rst(rst), .group_valid_in(group_valid_in),
        .phase_valid_in(phase_valid_in),
        .phase0(phase[0]), .phase1(phase[1]),
        .phase2(phase[2]), .phase3(phase[3]),
        .phase4(phase[4]), .phase5(phase[5]),
        .phase6(phase[6]), .phase7(phase[7]),
        .valid_out(actual_valid),
        .kay_sum0(actual_sum[0]), .kay_sum1(actual_sum[1]),
        .kay_sum2(actual_sum[2]), .kay_sum3(actual_sum[3]),
        .kay_sum4(actual_sum[4]), .kay_sum5(actual_sum[5]),
        .kay_sum6(actual_sum[6]), .kay_sum7(actual_sum[7])
    );

    always #5 clk = ~clk;

    // Sample after both cores have committed their nonblocking assignments.
    // Reset discards every queued transaction, including results in flight.
    always @(posedge clk) begin
        #1;
        cycles = cycles + 1;
        if (rst) begin
            groups_since_reset = 0;
            for (depth = 0; depth <= EXTRA_LATENCY; depth = depth + 1) begin
                expected_valid[depth] = 8'h00;
                expected_cycle[depth] = -1;
                expected_group[depth] = -1;
                expected_scenario[depth] = scenario;
                expected_mask[depth] = 1'b0;
                for (lane = 0; lane < 8; lane = lane + 1)
                    expected_sum[depth][lane] = 64'sd0;
            end
        end else begin
            if (group_valid_in) begin
                accepted_groups = accepted_groups + 1;
                groups_since_reset = groups_since_reset + 1;
                if ((groups_since_reset % 128) == 0)
                    row_wraps = row_wraps + 1;
            end else begin
                bubbles = bubbles + 1;
            end
            for (depth = EXTRA_LATENCY; depth > 0; depth = depth - 1) begin
                expected_valid[depth] = expected_valid[depth-1];
                expected_cycle[depth] = expected_cycle[depth-1];
                expected_group[depth] = expected_group[depth-1];
                expected_scenario[depth] = expected_scenario[depth-1];
                expected_mask[depth] = expected_mask[depth-1];
                for (lane = 0; lane < 8; lane = lane + 1)
                    expected_sum[depth][lane] = expected_sum[depth-1][lane];
            end
            expected_valid[0] = reference_valid;
            expected_cycle[0] = cycles;
            expected_group[0] = group_valid_in ? accepted_groups : -1;
            expected_scenario[0] = scenario;
            expected_mask[0] = mark_mask;
            for (lane = 0; lane < 8; lane = lane + 1)
                expected_sum[0][lane] = reference_sum[lane];
        end

        // Four-state comparisons also reject an unknown DUT output.
        for (lane = 0; lane < 8; lane = lane + 1) begin
            checked_lanes = checked_lanes + 1;
            if ((actual_valid[lane] !== expected_valid[EXTRA_LATENCY][lane]) ||
                (actual_sum[lane] !== expected_sum[EXTRA_LATENCY][lane])) begin
                $fatal(1,
                    "FAIL scenario=%0d cycle=%0d source_cycle=%0d group=%0d lane=%0d old_valid=%b new_valid=%b old_sum=%0d new_sum=%0d",
                    expected_scenario[EXTRA_LATENCY], cycles,
                    expected_cycle[EXTRA_LATENCY], expected_group[EXTRA_LATENCY],
                    lane, expected_valid[EXTRA_LATENCY][lane], actual_valid[lane],
                    expected_sum[EXTRA_LATENCY][lane], actual_sum[lane]);
            end
        end
        if (expected_mask[EXTRA_LATENCY])
            checked_masks = checked_masks + 1;
    end

    task send_cycle;
        input accepted;
        input [7:0] mask;
        integer drive_lane;
        begin
            @(negedge clk);
            rst = 1'b0;
            group_valid_in = accepted;
            phase_valid_in = mask;
            for (drive_lane = 0; drive_lane < 8; drive_lane = drive_lane + 1) begin
                random_state = random_state ^ (random_state << 13);
                random_state = random_state ^ (random_state >> 17);
                random_state = random_state ^ (random_state << 5);
                // Rotate the deterministic 32-bit extremes across all lanes.
                case (((sample_index / 8) + drive_lane) % 16)
                    0: phase[drive_lane] = 32'sh80000000;
                    1: phase[drive_lane] = 32'sh7fffffff;
                    2: phase[drive_lane] = -32'sd1;
                    3: phase[drive_lane] = 32'sd0;
                    default: phase[drive_lane] = $signed(random_state);
                endcase
                sample_index = sample_index + 1;
            end
            @(posedge clk);
            #2;
        end
    endtask

    task reset_core;
        begin
            @(negedge clk);
            rst = 1'b1;
            // A high group strobe during reset must still clear the pipeline.
            group_valid_in = 1'b1;
            phase_valid_in = 8'hff;
            @(posedge clk);
            #2;
        end
    endtask

    initial begin
        for (lane = 0; lane < 8; lane = lane + 1)
            phase[lane] = 32'sd0;
        if (EXTRA_LATENCY < 0 || EXTRA_LATENCY > 9)
            $fatal(1, "FAIL unsupported EXTRA_LATENCY=%0d", EXTRA_LATENCY);

        repeat (2) @(posedge clk);
        #2;

        // FE starts with a gap, so only lane 7 is valid on group 128.
        scenario = 1;
        send_cycle(1'b1, 8'hfe);
        for (group_index = 1; group_index < 128; group_index = group_index + 1)
            send_cycle(1'b1, 8'hff);
        if (reference_valid !== 8'h80)
            $fatal(1, "FAIL FE startup group=128 expected=80 old=%02h", reference_valid);
        send_cycle(1'b1, 8'hff);
        if (reference_valid !== 8'hff)
            $fatal(1, "FAIL FE startup group=129 expected=ff old=%02h", reference_valid);
        repeat (EXTRA_LATENCY + 1) send_cycle(1'b0, 8'h00);

        // An all-valid stream first produces valid lanes 6 and 7.
        reset_core();
        scenario = 2;
        for (group_index = 0; group_index < 128; group_index = group_index + 1)
            send_cycle(1'b1, 8'hff);
        if (reference_valid !== 8'hc0)
            $fatal(1, "FAIL FF startup group=128 expected=c0 old=%02h", reference_valid);
        send_cycle(1'b1, 8'hff);
        if (reference_valid !== 8'hff)
            $fatal(1, "FAIL FF startup group=129 expected=ff old=%02h", reference_valid);
        repeat (EXTRA_LATENCY + 1) send_cycle(1'b0, 8'h00);

        // Continue across multiple row wraps, with bubbles and a received 00 group.
        scenario = 3;
        for (group_index = 0; group_index < 260; group_index = group_index + 1) begin
            send_cycle(1'b1, 8'hff);
            if ((group_index % 47) == 0)
                send_cycle(1'b0, 8'ha5);
        end
        send_cycle(1'b1, 8'h00);
        send_cycle(1'b0, 8'hff);
        for (group_index = 0; group_index < 5; group_index = group_index + 1)
            send_cycle(1'b1, 8'hff);
        // The prior groups are still in the queue when this reset arrives.
        reset_core();

        // Every mask gets its own complete warmup. After the mask, refill the
        // window before reset so delayed responses cannot be flushed away.
        scenario = 4;
        for (mask_index = 0; mask_index < 256; mask_index = mask_index + 1) begin
            reset_core();
            for (group_index = 0; group_index < 129; group_index = group_index + 1)
                send_cycle(1'b1, 8'hff);
            if (reference_valid !== 8'hff)
                $fatal(1, "FAIL warmup mask=%02h old_valid=%02h", mask_index, reference_valid);
            mark_mask = 1'b1;
            send_cycle(1'b1, mask_index[7:0]);
            mark_mask = 1'b0;
            masks_tested = masks_tested + 1;
            send_cycle(1'b0, ~mask_index[7:0]);
            for (group_index = 0; group_index < 129; group_index = group_index + 1)
                send_cycle(1'b1, 8'hff);
            if (reference_valid !== 8'hff)
                $fatal(1, "FAIL refill mask=%02h old_valid=%02h", mask_index, reference_valid);
        end

        // Drain all delayed results, including a bubble that holds the sum.
        scenario = 5;
        for (group_index = 0; group_index < EXTRA_LATENCY + 3; group_index = group_index + 1)
            send_cycle(1'b0, 8'ha5);

        // Consecutive changing masks exercise state resets across groups.
        scenario = 6;
        reset_core();
        for (group_index = 0; group_index < 129; group_index = group_index + 1)
            send_cycle(1'b1, 8'hff);
        for (mask_index = 0; mask_index < 256; mask_index = mask_index + 1) begin
            send_cycle(1'b1, mask_index[7:0]);
            if (mask_index % 13 == 0)
                send_cycle(1'b0, 8'ha5);
        end
        for (group_index = 0; group_index < EXTRA_LATENCY + 1; group_index = group_index + 1)
            send_cycle(1'b0, 8'h00);
        if (masks_tested != 256 || checked_masks != 256 || row_wraps < 258 || bubbles == 0)
            $fatal(1, "FAIL coverage masks=%0d checked_masks=%0d row_wraps=%0d bubbles=%0d",
                   masks_tested, checked_masks, row_wraps, bubbles);
        $display("PASS core_sim latency=%0d cycles=%0d groups=%0d masks=%0d row_wraps=%0d bubbles=%0d lanes=%0d",
                 EXTRA_LATENCY, cycles, accepted_groups, masks_tested, row_wraps,
                 bubbles, checked_lanes);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "FAIL watchdog expired after %0d cycles", cycles);
    end
endmodule
