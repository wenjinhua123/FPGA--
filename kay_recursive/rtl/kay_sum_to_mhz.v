`timescale 1ns/1ps
// Kay N=1024 weighted-phase sum to MHz, Fix32_20.
// Input phase is signed Fix21_18 radians and Fs is 2500 MHz.
// C = round(2^48 * 5000 / (pi * 178956800)) = 2503293191.
// Output = round_half_away_from_zero(weighted_sum * C / 2^48).
// Coefficient error contributes <= 0.2301 output LSB over +/-pi radians.
// The full 52-bit input is multiplied. The nominal physical range is +/-1250 MHz
// and fits signed32. Larger results wrap to 32 bits, with no saturation.
// Eight enabled register stages: an input accepted on enabled edge k appears
// just after enabled edge k+7. ce=0 freezes ALL registers; synchronous rst wins.
module kay_sum_to_mhz (
    input  wire               clk,
    input  wire               ce,
    input  wire               rst,
    input  wire               valid_in,
    input  wire signed [51:0] weighted_sum,
    output reg                valid_out,
    output reg signed [31:0]  freq_q20
);
    // 2503293191 = 80135 + 19098*2^17. Each tile fits one 27x18 DSP48E2.
    localparam signed [17:0] C_LO = 18'sd80135;
    localparam signed [15:0] C_HI = 16'sd19098;
    reg signed [26:0] input_lo;
    reg signed [25:0] input_hi;
    (* use_dsp = "yes" *) reg signed [44:0] mul00;
    (* use_dsp = "yes" *) reg signed [42:0] mul01;
    (* use_dsp = "yes" *) reg signed [43:0] mul10;
    (* use_dsp = "yes" *) reg signed [41:0] mul11;
    reg signed [44:0] product00;
    reg signed [42:0] product01;
    reg signed [43:0] product10;
    reg signed [41:0] product11;

    // Reconstruct two 58-bit products with a registered carry between chunks.
    wire [57:0] lo_term0 = {13'b0, product00};
    wire [57:0] lo_term1 = {product01[40:0], 17'b0};
    wire [57:0] hi_term0 = {{14{product10[43]}}, product10};
    wire [57:0] hi_term1 = {product11[40:0], 17'b0};
    reg [30:0] lo_add_low, hi_add_low;
    reg [27:0] lo_add_high, hi_add_high;
    wire [27:0] lo_completed_high = lo_add_high + lo_add_low[30];
    wire [27:0] hi_completed_high = hi_add_high + hi_add_low[30];
    reg [57:0] lo_product, hi_product;

    // The full product is lo_product + (signed(hi_product) << 26).
    // Bits 25:0 cannot create a carry. Only bits 47:26 determine the carry
    // into the retained integer and the bit-47 rounding decision.
    reg [22:0] middle_sum;
    reg [31:0] integer_sum;
    reg [16:0] rounded_low;
    reg [15:0] rounded_high;
    reg [6:0] valid_pipe;
    reg [5:0] negative_pipe, tie_pipe;
    wire round_increment = middle_sum[21] &&
                           (!negative_pipe[5] || !tie_pipe[5]);
    wire [1:0] integer_increment = {1'b0, middle_sum[22]} +
                                   {1'b0, round_increment};
    wire [15:0] completed_high = rounded_high + rounded_low[16];

    // C is odd, so W*C mod 2^48 == 2^47 iff W mod 2^48 == 2^47.
    // This detects exact ties without a wide sticky-bit tree after multiplication.
    wire input_tie = weighted_sum[47:0] == 48'h800000000000;

    always @(posedge clk) begin
        if (rst) begin
            input_lo <= 0;
            input_hi <= 0;
            mul00 <= 0;
            mul01 <= 0;
            mul10 <= 0;
            mul11 <= 0;
            product00 <= 0;
            product01 <= 0;
            product10 <= 0;
            product11 <= 0;
            lo_add_low <= 0;
            hi_add_low <= 0;
            lo_add_high <= 0;
            hi_add_high <= 0;
            lo_product <= 0;
            hi_product <= 0;
            middle_sum <= 0;
            integer_sum <= 0;
            rounded_low <= 0;
            rounded_high <= 0;
            freq_q20 <= 0;
            valid_pipe <= 0;
            negative_pipe <= 0;
            tie_pipe <= 0;
            valid_out <= 0;
        end else if (ce) begin
            // S1: signed/unsigned input split.
            input_lo <= {1'b0, weighted_sum[25:0]};
            input_hi <= weighted_sum[51:26];
            // S2/S3 map to DSP multiply/output registers.
            mul00 <= input_lo * C_LO;
            mul01 <= input_lo * C_HI;
            mul10 <= input_hi * C_LO;
            mul11 <= input_hi * C_HI;
            product00 <= mul00;
            product01 <= mul01;
            product10 <= mul10;
            product11 <= mul11;
            // S4: parallel short additions.
            lo_add_low <= {1'b0, lo_term0[29:0]} + {1'b0, lo_term1[29:0]};
            hi_add_low <= {1'b0, hi_term0[29:0]} + {1'b0, hi_term1[29:0]};
            lo_add_high <= lo_term0[57:30] + lo_term1[57:30];
            hi_add_high <= hi_term0[57:30] + hi_term1[57:30];
            // S5: propagate the registered carries.
            lo_product <= {lo_completed_high, lo_add_low[29:0]};
            hi_product <= {hi_completed_high, hi_add_low[29:0]};
            // S6: combine the aligned tiles around the binary-point cut.
            middle_sum <= {1'b0, lo_product[47:26]} +
                          {1'b0, hi_product[21:0]};
            integer_sum <= hi_product[53:22] + {22'b0, lo_product[57:48]};
            // S7/S8: signed round-half-away, split to keep carry chains short.
            rounded_low <= {1'b0, integer_sum[15:0]} +
                           {15'b0, integer_increment};
            rounded_high <= integer_sum[31:16];
            freq_q20 <= {completed_high, rounded_low[15:0]};
            valid_pipe <= {valid_pipe[5:0], valid_in};
            valid_out <= valid_pipe[6];
            negative_pipe <= {negative_pipe[4:0], weighted_sum[51]};
            tie_pipe <= {tie_pipe[4:0], input_tie};
        end
    end
endmodule
