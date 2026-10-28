`timescale 1ns/1ps
// SysGen boundary: Fix30_18 radians in chronological order, after the
// original instantaneous-frequency CORDIC, BEFORE multiplication by Fs/(2*pi).
// clk/ce are supplied by SysGen. valid_in is aligned with the phase ports.
// Each output window ends after phase6; phase7 still updates the sliding state.
module kay1024_phase_blackbox (
    input clk, input ce, input rst, input valid_in,
    input [29:0] phase0, phase1, phase2, phase3,
    input [29:0] phase4, phase5, phase6, phase7,
    output reg [31:0] freq_q20,
    output reg [15:0] freq_q4,
    output reg valid_out
);
    wire signed [51:0] weighted_sum;
    wire sum_valid, scale_valid;
    wire signed [31:0] scaled_mhz;
    // Every valid CORDIC phase lies in [-pi,pi], so the discarded bits
    // are all sign extension; no phase precision is lost here.
    kay_phase_core core (
        .clk(clk), .ce(ce), .rst(rst), .valid_in(valid_in),
        .phase0(phase0[20:0]), .phase1(phase1[20:0]),
        .phase2(phase2[20:0]), .phase3(phase3[20:0]),
        .phase4(phase4[20:0]), .phase5(phase5[20:0]),
        .phase6(phase6[20:0]), .phase7(phase7[20:0]),
        .valid_out(sum_valid), .weighted_sum(weighted_sum)
    );
    kay_sum_to_mhz scale (
        .clk(clk), .ce(ce), .rst(rst), .valid_in(sum_valid),
        .weighted_sum(weighted_sum), .valid_out(scale_valid), .freq_q20(scaled_mhz)
    );
    wire signed [32:0] mhz_extended = {scaled_mhz[31],scaled_mhz};
    wire signed [32:0] rounded_q4 =
        (mhz_extended + (scaled_mhz[31] ? 33'sd32767 : 33'sd32768)) >>> 16;
    always @(posedge clk) begin
        if (rst) begin
            freq_q20 <= 0; freq_q4 <= 0; valid_out <= 0;
        end else if (ce) begin
            valid_out <= scale_valid;
            if (scale_valid) begin
                freq_q20 <= scaled_mhz;
                freq_q4 <= rounded_q4[15:0];
            end
        end
    end
endmodule
