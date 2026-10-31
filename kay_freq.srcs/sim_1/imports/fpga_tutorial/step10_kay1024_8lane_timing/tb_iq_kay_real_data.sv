`timescale 1ns/1ps

// Real IQ: first 8192 little-endian int16 I,Q pairs.
// Chirp wrapper below: 20000 samples, -1000 to +1000 MHz, Fs=2500 MHz.
module tb_iq_kay_real_data #(
    parameter integer CHIRP = 0
);
    localparam integer N = CHIRP ? 20000 : 8192;
    localparam integer GROUPS = N/8;
    localparam integer LATENCY = 53;
    localparam real PI = 3.14159265358979323846;
    localparam real Q20 = 1048576.0;
    localparam real KAY_DENOM = 178956800.0;
    localparam real MAX_ERROR_MHZ = CHIRP ? 0.005 : 0.001;

    reg clk = 0, rst = 1, valid_in = 0;
    reg signed [15:0] ii [0:7], qq [0:7];
    wire [7:0] valid_out;
    wire signed [31:0] freq [0:7];
    reg [7:0] raw [0:4*N-1];
    integer data_i [0:N-1], data_q [0:N-1];
    real phase [0:N-2], golden_mhz [0:N-1];
    integer fd, bytes_read, n, j, g, lane, cycles = 0;
    integer first_input_cycle = -1, out_group, expected_count = 0;
    integer measured_count = 0, errors = 0, max_error_sample = -1;
    real re, im, weighted, actual, delta, max_error = 0.0, chirp_phase = 0.0;
    real first_actual, first_golden, last_actual, last_golden;
    real actual_mean = 0.0, golden_mean = 0.0;
    real actual_m2 = 0.0, golden_m2 = 0.0;
    integer group_window_count = 0;
    real group_actual_mean = 0.0, group_golden_mean = 0.0;
    real group_actual_m2 = 0.0, group_golden_m2 = 0.0;
    real da, dg;
    reg [7:0] expected_valid;
    string data_file;

    function integer rounded;
        input real x;
        begin
            rounded = (x >= 0.0) ? $rtoi(x+0.5) : $rtoi(x-0.5);
        end
    endfunction

    iq_kay_freq_8lane_lookahead dut (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .i0(ii[0]), .q0(qq[0]), .i1(ii[1]), .q1(qq[1]),
        .i2(ii[2]), .q2(qq[2]), .i3(ii[3]), .q3(qq[3]),
        .i4(ii[4]), .q4(qq[4]), .i5(ii[5]), .q5(qq[5]),
        .i6(ii[6]), .q6(qq[6]), .i7(ii[7]), .q7(qq[7]),
        .valid_out(valid_out),
        .freq0(freq[0]), .freq1(freq[1]), .freq2(freq[2]), .freq3(freq[3]),
        .freq4(freq[4]), .freq5(freq[5]), .freq6(freq[6]), .freq7(freq[7])
    );

    always #1.6 clk = ~clk;

    // Inspect outputs after the DUT's nonblocking assignments have settled.
    always @(posedge clk) begin
        cycles = cycles + 1;
        #0.001;
        out_group = cycles - first_input_cycle - LATENCY;
        expected_valid = 8'h00;
        if (!rst && first_input_cycle > 0 && out_group >= 127 && out_group < GROUPS) begin
            expected_valid = (out_group == 127) ? 8'h80 : 8'hff;
        end
        if (valid_out !== expected_valid)
            $fatal(1, "FAIL valid cycle=%0d group=%0d expected=%02h actual=%02h",
                   cycles, out_group, expected_valid, valid_out);
        for (integer l = 0; l < 8; l = l + 1) begin
            if (expected_valid[l]) begin
                n = 8*out_group+l;
                actual = $itor($signed(freq[l]))/Q20;
                delta = actual-golden_mhz[n];
                if (delta < 0.0) delta = -delta;
                if (delta > max_error) begin
                    max_error = delta;
                    max_error_sample = n;
                end
                if (delta > MAX_ERROR_MHZ) begin
                    if (errors < 8)
                        $display("ERROR sample=%0d actual=%f golden=%f MHz", n, actual, golden_mhz[n]);
                    errors = errors + 1;
                end
                measured_count = measured_count + 1;
                if (measured_count == 1) begin
                    first_actual = actual;
                    first_golden = golden_mhz[n];
                end
                last_actual = actual;
                last_golden = golden_mhz[n];
                da = actual-actual_mean;
                actual_mean = actual_mean+da/measured_count;
                actual_m2 = actual_m2+da*(actual-actual_mean);
                dg = golden_mhz[n]-golden_mean;
                golden_mean = golden_mean+dg/measured_count;
                golden_m2 = golden_m2+dg*(golden_mhz[n]-golden_mean);
                // Lane 7 matches the one-window-per-group SysGen comparison.
                if (l == 7) begin
                    group_window_count = group_window_count+1;
                    da = actual-group_actual_mean;
                    group_actual_mean = group_actual_mean+da/group_window_count;
                    group_actual_m2 = group_actual_m2+da*(actual-group_actual_mean);
                    dg = golden_mhz[n]-group_golden_mean;
                    group_golden_mean = group_golden_mean+dg/group_window_count;
                    group_golden_m2 = group_golden_m2+dg*(golden_mhz[n]-group_golden_mean);
                end
            end
        end
    end

    initial begin
        if (CHIRP) begin
            for (integer k = 0; k < N; k = k + 1) begin
                // Same phase construction and 0.75*2^13 quantization as MATLAB.
                chirp_phase = chirp_phase + 2.0*PI*(-1000.0+2000.0*k/(N-1))/2500.0;
                if (chirp_phase > PI) chirp_phase = chirp_phase-2.0*PI;
                if (chirp_phase < -PI) chirp_phase = chirp_phase+2.0*PI;
                data_i[k] = rounded(6144.0*$cos(chirp_phase));
                data_q[k] = rounded(6144.0*$sin(chirp_phase));
                golden_mhz[k] = 0.0;
            end
        end else begin
            if (!$value$plusargs("DATA_FILE=%s", data_file))
                data_file = "E:/FPGA/kay_recursive/data_10dB_100MHz.dat";
            fd = $fopen(data_file, "rb");
            if (fd == 0) $fatal(1, "Cannot open IQ data: %s", data_file);
            bytes_read = $fread(raw, fd);
            $fclose(fd);
            if (bytes_read < 4*N)
                $fatal(1, "IQ file too short: read %0d bytes, need %0d", bytes_read, 4*N);
            for (integer k = 0; k < N; k = k + 1) begin
                data_i[k] = $signed({raw[4*k+1],raw[4*k]});
                data_q[k] = $signed({raw[4*k+3],raw[4*k+2]});
                golden_mhz[k] = 0.0;
            end
        end
        for (integer k = 0; k < N-1; k = k + 1) begin
            re = $itor(data_i[k])*$itor(data_i[k+1]) +
                 $itor(data_q[k])*$itor(data_q[k+1]);
            im = $itor(data_i[k])*$itor(data_q[k+1]) -
                 $itor(data_q[k])*$itor(data_i[k+1]);
            phase[k] = $atan2(im, re);
        end
        for (integer end_sample = 1023; end_sample < N; end_sample = end_sample + 1) begin
            weighted = 0.0;
            for (integer w = 1; w < 1024; w = w + 1)
                weighted = weighted + $itor(w*(1024-w))*phase[end_sample-1024+w];
            golden_mhz[end_sample] = weighted*2500.0/(2.0*PI*KAY_DENOM);
        end
        for (integer l = 0; l < 8; l = l + 1) begin
            ii[l] = 0;
            qq[l] = 0;
        end
        repeat (4) @(negedge clk);
        rst = 0;
        for (g = 0; g < GROUPS; g = g + 1) begin
            @(negedge clk);
            valid_in = 1;
            if (g == 0) first_input_cycle = cycles+1;
            for (integer l = 0; l < 8; l = l + 1) begin
                ii[l] = data_i[8*g+l];
                qq[l] = data_q[8*g+l];
            end
        end
        @(negedge clk);
        valid_in = 0;
        repeat (LATENCY+5) @(negedge clk);
        expected_count = N-1023;
        if (measured_count != expected_count)
            $fatal(1, "FAIL output count actual=%0d expected=%0d", measured_count, expected_count);
        if (errors != 0)
            $fatal(1, "FAIL dataset=%0d errors=%0d max_error=%f MHz", CHIRP, errors, max_error);
        if (CHIRP)
            $display("CHIRP_PASS samples=%0d outputs=%0d latency=%0d max_error=%f MHz at sample=%0d", N, measured_count, LATENCY, max_error, max_error_sample);
        else
            $display("REAL_IQ_PASS samples=%0d outputs=%0d latency=%0d max_error=%f MHz", N, measured_count, LATENCY, max_error);
        $display("RTL:    mean=%f MHz variance=%g MHz^2", actual_mean, actual_m2/(measured_count-1));
        $display("Kay_ref_SV: mean=%f MHz variance=%g MHz^2", golden_mean, golden_m2/(measured_count-1));
        if (CHIRP) begin
            $display("Chirp noise: no added AWGN; integer I/Q quantization only");
            $display("Group windows=%0d RTL mean=%.9f variance=%.9f MHz^2", group_window_count, group_actual_mean, group_actual_m2/(group_window_count-1));
            $display("Group windows=%0d Kay_ref_SV mean=%.9f variance=%.9f MHz^2", group_window_count, group_golden_mean, group_golden_m2/(group_window_count-1));
        end
        $display("First:  RTL=%f Kay=%f MHz", first_actual, first_golden);
        $display("Last:   RTL=%f Kay=%f MHz", last_actual, last_golden);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL simulation timeout");
    end
endmodule

// Select this top in Vivado to test the 20000-point chirp.
module tb_iq_kay_chirp;
    tb_iq_kay_real_data #(.CHIRP(1)) test();
endmodule
