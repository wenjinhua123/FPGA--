`timescale 1ns/1ps
module kay_sum_to_freq_q20 (
    input wire clk, rst, valid_in,
    input wire signed [63:0] kay_sum_in,
    output reg valid_out,
    output reg signed [31:0] freq_q20
);
    // Input is Kay weighted numerator W, D=178956800; |W| <= D*2^29.
    // Both rounding steps send exact half ties away from zero.
    // Output is signed Fix32_20 MHz: frequency = freq_q20/1048576.0 MHz.
    wire [63:0] magnitude = kay_sum_in[63] ? -kay_sum_in : kay_sum_in;
    reg [63:0] a1, a2, q02;
    reg sign1, sign2, valid1, valid2, valid3, valid4;
    reg signed [31:0] p3;
    reg signed [63:0] z4;

    // A=3|W|, E=3D=2^29-2^9; q0 slightly underestimates A/E.
    // One comparison completes rounding over the supported input range.
    wire [63:0] remainder0 = a2 - ((q02 << 29) - (q02 << 9));
    wire [63:0] rounded_p = q02 + ((remainder0 >= 64'd268435200) ? 64'd1 : 64'd0);
    // Sign-extend to 64 bits before evaluating 625=512+128-16+1.
    wire signed [63:0] p64 = {{32{p3[31]}}, p3};

    always @(posedge clk) begin
        if (rst) begin
            a1 <= 0; a2 <= 0; q02 <= 0;
            sign1 <= 0; sign2 <= 0;
            p3 <= 0; z4 <= 0; freq_q20 <= 0;
            valid1 <= 0; valid2 <= 0; valid3 <= 0; valid4 <= 0; valid_out <= 0;
        end else begin
            valid1 <= valid_in;
            valid2 <= valid1;
            valid3 <= valid2;
            valid4 <= valid3;
            valid_out <= valid4;
            // Five registered stages; input and output edges are four clocks apart.
            if (valid_in) begin
                a1 <= (magnitude << 1) + magnitude;
                sign1 <= kay_sum_in[63];
            end
            if (valid1) begin
                q02 <= (a1 + (a1 >> 20)) >> 29;
                a2 <= a1;
                sign2 <= sign1;
            end
            if (valid2) p3 <= sign2 ? -$signed(rounded_p) : $signed(rounded_p);
            if (valid3) z4 <= (p64 <<< 9) + (p64 <<< 7) - (p64 <<< 4) + p64;
            // For negative values, add 127 before arithmetic shift for half-away rounding.
            if (valid4) freq_q20 <= (z4 + (z4[63] ? 64'sd127 : 64'sd128)) >>> 8;
        end
    end
endmodule

`timescale 1ns/1ps
module kay_sum_to_freq_q20_plus1 (
    input wire clk, rst, valid_in,
    input wire signed [63:0] kay_sum_in,
    output reg valid_out,
    output reg signed [31:0] freq_q20
);
    // Input is Kay weighted numerator W, D=178956800; |W| <= D*2^29.
    // Both rounding steps send exact half ties away from zero.
    // Output is signed Fix32_20 MHz: frequency = freq_q20/1048576.0 MHz.
    wire [63:0] magnitude = kay_sum_in[63] ? -kay_sum_in : kay_sum_in;
    reg [63:0] a1, a2, q02;
    reg sign1, sign2, sign3, round3;
    reg valid1, valid2, valid3, valid4, valid5;
    reg [31:0] q3;
    reg signed [31:0] p4;
    reg signed [63:0] z5;

    // A=3|W|, E=3D=2^29-2^9; q0 slightly underestimates A/E.
    // One comparison completes rounding over the supported input range.
    wire [63:0] remainder0 = a2 - ((q02 << 29) - (q02 << 9));
    wire round_up = remainder0 >= 64'd268435200;
    // For a negative result, -q-round_up = ~q + !round_up (mod 2^32).
    // Select the sign before the only 32-bit incrementer.
    wire [31:0] signed_base = q3 ^ {32{sign3}};
    wire [31:0] signed_round = signed_base + {31'd0, sign3 ^ round3};
    // Sign-extend to 64 bits before evaluating 625=512+128-16+1.
    wire signed [63:0] p64 = {{32{p4[31]}}, p4};

    always @(posedge clk) begin
        if (rst) begin
            a1 <= 0; a2 <= 0; q02 <= 0;
            sign1 <= 0; sign2 <= 0; sign3 <= 0; round3 <= 0;
            q3 <= 0; p4 <= 0; z5 <= 0; freq_q20 <= 0;
            valid1 <= 0; valid2 <= 0; valid3 <= 0;
            valid4 <= 0; valid5 <= 0; valid_out <= 0;
        end else begin
            valid1 <= valid_in;
            valid2 <= valid1;
            valid3 <= valid2;
            valid4 <= valid3;
            valid5 <= valid4;
            valid_out <= valid5;
            // Six stages: the received input reaches the output five clocks later.
            if (valid_in) begin
                a1 <= (magnitude << 1) + magnitude;
                sign1 <= kay_sum_in[63];
            end
            if (valid1) begin
                q02 <= (a1 + (a1 >> 20)) >> 29;
                a2 <= a1;
                sign2 <= sign1;
            end
            if (valid2) begin
                q3 <= q02[31:0];
                sign3 <= sign2;
                round3 <= round_up;
            end
            if (valid3) p4 <= $signed(signed_round);
            if (valid4) z5 <= (p64 <<< 9) + (p64 <<< 7) - (p64 <<< 4) + p64;
            // For negative values, add 127 before arithmetic shift for half-away rounding.
            if (valid5) freq_q20 <= (z5 + (z5[63] ? 64'sd127 : 64'sd128)) >>> 8;
        end
    end
endmodule
