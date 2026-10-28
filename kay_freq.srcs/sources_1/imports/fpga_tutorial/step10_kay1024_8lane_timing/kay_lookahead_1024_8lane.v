`timescale 1ns/1ps

// Eight adjacent phase differences per clock. The bank read and fill counter
// advance on the input edge; all arithmetic after that is pipelined.
// Output latency is nine clocks beyond the original one-cycle Kay core.
module kay_lookahead_1024_8lane (
    input clk, input rst, input group_valid_in,
    input [7:0] phase_valid_in,
    input signed [31:0] phase0, phase1, phase2, phase3,
    input signed [31:0] phase4, phase5, phase6, phase7,
    output reg [7:0] valid_out,
    output reg signed [63:0] kay_sum0, kay_sum1, kay_sum2, kay_sum3,
    output reg signed [63:0] kay_sum4, kay_sum5, kay_sum6, kay_sum7
);
    // Physical ring of 1024 samples; the mathematical window has 1023.
    reg signed [31:0] bank0 [0:127], bank1 [0:127];
    reg signed [31:0] bank2 [0:127], bank3 [0:127];
    reg signed [31:0] bank4 [0:127], bank5 [0:127];
    reg signed [31:0] bank6 [0:127], bank7 [0:127];
    reg [6:0] row;
    wire [6:0] next_row = row + 7'd1;
    reg [9:0] fill;
    wire signed [31:0] incoming [0:7];
    wire signed [31:0] outgoing [0:7];
    wire [9:0] fill_before [0:8];
    wire [7:0] input_lane_valid;

    assign incoming[0] = phase0; assign incoming[1] = phase1;
    assign incoming[2] = phase2; assign incoming[3] = phase3;
    assign incoming[4] = phase4; assign incoming[5] = phase5;
    assign incoming[6] = phase6; assign incoming[7] = phase7;
    assign outgoing[0] = bank1[row]; assign outgoing[1] = bank2[row];
    assign outgoing[2] = bank3[row]; assign outgoing[3] = bank4[row];
    assign outgoing[4] = bank5[row]; assign outgoing[5] = bank6[row];
    assign outgoing[6] = bank7[row]; assign outgoing[7] = bank0[next_row];
    assign fill_before[0] = fill;
    genvar j, k, m;
    generate for (j = 0; j < 8; j = j + 1) begin : input_fill
        assign input_lane_valid[j] = phase_valid_in[j] &&
                                     fill_before[j] >= 10'd1022;
        assign fill_before[j+1] = !phase_valid_in[j] ? 10'd0 :
                       fill_before[j] < 10'd1023 ?
                       fill_before[j] + 10'd1 : 10'd1023;
    end endgenerate

    // Edge n: capture old bank values before the nonblocking writes replace
    // them. A bubble does not advance the ring or the fill count.
    reg cap_group;
    reg [7:0] cap_mask, cap_valid;
    reg signed [31:0] cap_b [0:7], cap_a [0:7];
    always @(posedge clk) begin
        if (rst) begin
            row <= 7'd0;
            fill <= 10'd0;
            cap_group <= 1'b0;
            cap_mask <= 8'd0;
            cap_valid <= 8'd0;
        end else begin
            cap_group <= group_valid_in;
            cap_mask <= phase_valid_in;
            cap_valid <= input_lane_valid;
            cap_b[0] <= phase0; cap_b[1] <= phase1;
            cap_b[2] <= phase2; cap_b[3] <= phase3;
            cap_b[4] <= phase4; cap_b[5] <= phase5;
            cap_b[6] <= phase6; cap_b[7] <= phase7;
            cap_a[0] <= fill_before[0] == 10'd1023 ? outgoing[0] : 32'sd0;
            cap_a[1] <= fill_before[1] == 10'd1023 ? outgoing[1] : 32'sd0;
            cap_a[2] <= fill_before[2] == 10'd1023 ? outgoing[2] : 32'sd0;
            cap_a[3] <= fill_before[3] == 10'd1023 ? outgoing[3] : 32'sd0;
            cap_a[4] <= fill_before[4] == 10'd1023 ? outgoing[4] : 32'sd0;
            cap_a[5] <= fill_before[5] == 10'd1023 ? outgoing[5] : 32'sd0;
            cap_a[6] <= fill_before[6] == 10'd1023 ? outgoing[6] : 32'sd0;
            cap_a[7] <= fill_before[7] == 10'd1023 ? outgoing[7] : 32'sd0;
            if (group_valid_in) begin
                bank0[row] <= phase_valid_in[0] ? phase0 : 32'sd0;
                bank1[row] <= phase_valid_in[1] ? phase1 : 32'sd0;
                bank2[row] <= phase_valid_in[2] ? phase2 : 32'sd0;
                bank3[row] <= phase_valid_in[3] ? phase3 : 32'sd0;
                bank4[row] <= phase_valid_in[4] ? phase4 : 32'sd0;
                bank5[row] <= phase_valid_in[5] ? phase5 : 32'sd0;
                bank6[row] <= phase_valid_in[6] ? phase6 : 32'sd0;
                bank7[row] <= phase_valid_in[7] ? phase7 : 32'sd0;
                row <= next_row;
                fill <= fill_before[8];
            end
        end
    end

    // For prefix k, input j survives iff all q[j..k-1] are valid.
    // The first arithmetic stage computes only input-dependent terms.
    wire signed [63:0] b64 [0:7], a64 [0:7];
    generate for (j = 0; j < 8; j = j + 1) begin : extend_input
        assign b64[j] = {{32{cap_b[j][31]}}, cap_b[j]};
        assign a64[j] = {{32{cap_a[j][31]}}, cap_a[j]};
    end endgenerate
    wire signed [63:0] calc_ds [1:8][0:7];
    wire signed [63:0] calc_dtb [1:8][0:7], calc_dta [1:8][0:7];
    wire signed [63:0] calc_dwb [1:8][0:7], calc_dwa [1:8][0:7];
    wire signed [63:0] calc_dvb [0:7], calc_dva [0:7];
    generate for (k = 1; k <= 8; k = k + 1) begin : make_prefix_term
        for (j = 0; j < 8; j = j + 1) begin : make_term
            if (j < k) begin : used
                localparam integer H = k-1-j;
                localparam signed [63:0] BT = 1023-H;
                localparam signed [63:0] AT = H;
                localparam signed [63:0] BW = (H+1)*(1023-H);
                localparam signed [63:0] AW = H*(H+1024);
                wire active = &cap_mask[k-1:j];
                assign calc_ds[k][j] = active ? b64[j]-a64[j] : 64'sd0;
                assign calc_dtb[k][j] = active ? BT*b64[j] : 64'sd0;
                assign calc_dta[k][j] = active ? AT*a64[j] : 64'sd0;
                assign calc_dwb[k][j] = active ? BW*b64[j] : 64'sd0;
                assign calc_dwa[k][j] = active ? AW*a64[j] : 64'sd0;
            end else begin : unused
                assign calc_ds[k][j] = 64'sd0;
                assign calc_dtb[k][j] = 64'sd0;
                assign calc_dta[k][j] = 64'sd0;
                assign calc_dwb[k][j] = 64'sd0;
                assign calc_dwa[k][j] = 64'sd0;
            end
        end
    end endgenerate
    // V=W-1032*T removes S from the eight-lane feedback equation.
    // Direct DV terms avoid a DW8-1032*DT8 subtraction in that feedback path.
    generate for (j = 0; j < 8; j = j + 1) begin : make_v_term
        localparam integer H = 7-j;
        localparam signed [63:0] BV = (H-1031)*(1023-H);
        localparam signed [63:0] AV = H*(H-8);
        wire active = &cap_mask[7:j];
        assign calc_dvb[j] = active ? BV*b64[j] : 64'sd0;
        assign calc_dva[j] = active ? AV*a64[j] : 64'sd0;
    end endgenerate

    // n+1 separate products; n+2 term sums; n+3 pair; n+4 four;
    // n+5 eight. Each stage accepts a new group on every clock.
    reg p1_group;
    reg [7:0] p1_mask, p1_valid;
    reg t1_group, t2_group, t3_group, t4_group;
    reg [7:0] t1_mask, t2_mask, t3_mask, t4_mask;
    reg [7:0] t1_valid, t2_valid, t3_valid, t4_valid;
    reg signed [63:0] p1_ds [1:8][0:7];
    reg signed [63:0] p1_dtb [1:8][0:7], p1_dta [1:8][0:7];
    reg signed [63:0] p1_dwb [1:8][0:7], p1_dwa [1:8][0:7];
    reg signed [63:0] t1_ds [1:8][0:7], t1_dt [1:8][0:7], t1_dw [1:8][0:7];
    reg signed [63:0] t2_ds [1:8][0:3], t2_dt [1:8][0:3], t2_dw [1:8][0:3];
    reg signed [63:0] t3_ds [1:8][0:1], t3_dt [1:8][0:1], t3_dw [1:8][0:1];
    reg signed [63:0] t4_ds [1:8], t4_dt [1:8], t4_dw [1:8];
    reg signed [63:0] p1_dvb [0:7], p1_dva [0:7];
    reg signed [63:0] t1_dv [0:7], t2_dv [0:3], t3_dv [0:1], t4_dv;
    integer ni, nj;
    always @(posedge clk) begin
        if (rst) begin
            p1_group <= 1'b0;
            t1_group <= 1'b0; t2_group <= 1'b0;
            t3_group <= 1'b0; t4_group <= 1'b0;
            p1_mask <= 8'd0;
            t1_mask <= 8'd0; t2_mask <= 8'd0;
            t3_mask <= 8'd0; t4_mask <= 8'd0;
            p1_valid <= 8'd0;
            t1_valid <= 8'd0; t2_valid <= 8'd0;
            t3_valid <= 8'd0; t4_valid <= 8'd0;
        end else begin
            p1_group <= cap_group; t1_group <= p1_group;
            t2_group <= t1_group;
            t3_group <= t2_group; t4_group <= t3_group;
            p1_mask <= cap_mask; t1_mask <= p1_mask;
            t2_mask <= t1_mask;
            t3_mask <= t2_mask; t4_mask <= t3_mask;
            p1_valid <= cap_valid; t1_valid <= p1_valid;
            t2_valid <= t1_valid;
            t3_valid <= t2_valid; t4_valid <= t3_valid;
            for (ni = 1; ni <= 8; ni = ni + 1) begin
                for (nj = 0; nj < 8; nj = nj + 1) begin
                    p1_ds[ni][nj] <= calc_ds[ni][nj];
                    p1_dtb[ni][nj] <= calc_dtb[ni][nj];
                    p1_dta[ni][nj] <= calc_dta[ni][nj];
                    p1_dwb[ni][nj] <= calc_dwb[ni][nj];
                    p1_dwa[ni][nj] <= calc_dwa[ni][nj];
                    t1_ds[ni][nj] <= p1_ds[ni][nj];
                    t1_dt[ni][nj] <= p1_dtb[ni][nj]+p1_dta[ni][nj];
                    t1_dw[ni][nj] <= p1_dwb[ni][nj]+p1_dwa[ni][nj];
                end
                for (nj = 0; nj < 4; nj = nj + 1) begin
                    t2_ds[ni][nj] <= t1_ds[ni][2*nj]+t1_ds[ni][2*nj+1];
                    t2_dt[ni][nj] <= t1_dt[ni][2*nj]+t1_dt[ni][2*nj+1];
                    t2_dw[ni][nj] <= t1_dw[ni][2*nj]+t1_dw[ni][2*nj+1];
                end
                for (nj = 0; nj < 2; nj = nj + 1) begin
                    t3_ds[ni][nj] <= t2_ds[ni][2*nj]+t2_ds[ni][2*nj+1];
                    t3_dt[ni][nj] <= t2_dt[ni][2*nj]+t2_dt[ni][2*nj+1];
                    t3_dw[ni][nj] <= t2_dw[ni][2*nj]+t2_dw[ni][2*nj+1];
                end
                t4_ds[ni] <= t3_ds[ni][0]+t3_ds[ni][1];
                t4_dt[ni] <= t3_dt[ni][0]+t3_dt[ni][1];
                t4_dw[ni] <= t3_dw[ni][0]+t3_dw[ni][1];
            end
            for (nj = 0; nj < 8; nj = nj + 1) begin
                p1_dvb[nj] <= calc_dvb[nj];
                p1_dva[nj] <= calc_dva[nj];
                t1_dv[nj] <= p1_dvb[nj]+p1_dva[nj];
            end
            for (nj = 0; nj < 4; nj = nj + 1)
                t2_dv[nj] <= t1_dv[2*nj]+t1_dv[2*nj+1];
            for (nj = 0; nj < 2; nj = nj + 1)
                t3_dv[nj] <= t2_dv[2*nj]+t2_dv[2*nj+1];
            t4_dv <= t3_dv[0]+t3_dv[1];
        end
    end

    // n+6: one feedback update for every accepted group, including mask 00.
    // A bubble holds S/T/V. All old-state operands are gated by P8.
    reg signed [63:0] state_s, state_t, state_v;
    wire p8 = &t4_mask;
    wire [63:0] fb_s = (p8 ? state_s : 64'd0) + t4_ds[8];
    wire [63:0] tx = p8 ? state_t : 64'd0;
    wire [63:0] ty = p8 ? ~(state_s << 3) : 64'd0;
    wire [63:0] tz = t4_dt[8];
    wire [63:0] ts = tx ^ ty ^ tz;
    wire [63:0] tc = ((tx & ty) | (tx & tz) | (ty & tz)) << 1;
    wire [63:0] fb_t = ts + {tc[63:1], p8};
    wire [63:0] vx = p8 ? state_v : 64'd0;
    wire [63:0] vy = p8 ? (state_t << 4) : 64'd0;
    wire [63:0] vz = t4_dv;
    wire [63:0] vs = vx ^ vy ^ vz;
    wire [63:0] vc = ((vx & vy) | (vx & vz) | (vy & vz)) << 1;
    wire [63:0] fb_v = vs + vc;

    reg snap_group;
    reg [7:0] snap_mask, snap_valid;
    reg signed [63:0] snap_s, snap_t, snap_v;
    reg signed [63:0] snap_dw [1:8];
    integer si;
    always @(posedge clk) begin
        if (rst) begin
            state_s <= 64'sd0; state_t <= 64'sd0; state_v <= 64'sd0;
            snap_group <= 1'b0; snap_mask <= 8'd0; snap_valid <= 8'd0;
        end else begin
            snap_group <= t4_group;
            snap_mask <= t4_mask;
            snap_valid <= t4_valid;
            // Nonblocking assignments capture the state before this group.
            snap_s <= state_s; snap_t <= state_t; snap_v <= state_v;
            for (si = 1; si <= 8; si = si + 1)
                snap_dw[si] <= t4_dw[si];
            if (t4_group) begin
                state_s <= fb_s; state_t <= fb_t; state_v <= fb_v;
            end
        end
    end

    // n+7 constant products, n+8 two carry-save compressors, n+9 one CPA.
    reg o6_group, o7_group;
    reg [7:0] o6_mask, o6_valid, o7_valid;
    reg signed [63:0] o6_v;
    reg signed [63:0] o6_tprod [1:8], o6_sprod [1:8], o6_dw [1:8];
    reg [63:0] o7_sum [1:8], o7_carry [1:8];
    always @(posedge clk) begin
        if (rst) begin
            o6_group <= 1'b0; o7_group <= 1'b0;
            o6_mask <= 8'd0; o6_valid <= 8'd0; o7_valid <= 8'd0;
        end else begin
            o6_group <= snap_group; o7_group <= o6_group;
            o6_mask <= snap_mask;
            o6_valid <= snap_valid;
            o7_valid <= o6_valid;
            o6_v <= snap_v;
        end
    end
    generate for (k = 1; k <= 8; k = k + 1) begin : output_lane
        localparam signed [63:0] T_GAIN = 1032+2*k;
        localparam signed [63:0] S_GAIN = k*(k+1024);
        wire pk = &o6_mask[k-1:0];
        wire [63:0] x = pk ? o6_v : 64'd0;
        wire [63:0] y = pk ? o6_tprod[k] : 64'd0;
        wire [63:0] z = pk ? ~o6_sprod[k] : 64'd0;
        wire [63:0] cs1 = x ^ y ^ z;
        wire [63:0] cc1_shift = ((x & y) | (x & z) | (y & z)) << 1;
        wire [63:0] cc1 = {cc1_shift[63:1], pk};
        wire [63:0] d = o6_dw[k];
        wire [63:0] cs2 = cs1 ^ cc1 ^ d;
        wire [63:0] cc2 = ((cs1 & cc1) | (cs1 & d) | (cc1 & d)) << 1;
        always @(posedge clk) begin
            if (!rst) begin
                o6_tprod[k] <= T_GAIN*snap_t;
                o6_sprod[k] <= S_GAIN*snap_s;
                o6_dw[k] <= snap_dw[k];
                o7_sum[k] <= cs2;
                o7_carry[k] <= cc2;
            end
        end
    end endgenerate

    always @(posedge clk) begin
        if (rst) begin
            valid_out <= 8'd0;
            kay_sum0 <= 64'sd0; kay_sum1 <= 64'sd0;
            kay_sum2 <= 64'sd0; kay_sum3 <= 64'sd0;
            kay_sum4 <= 64'sd0; kay_sum5 <= 64'sd0;
            kay_sum6 <= 64'sd0; kay_sum7 <= 64'sd0;
        end else begin
            valid_out <= 8'd0;
            if (o7_group) begin
                valid_out <= o7_valid;
                kay_sum0 <= o7_sum[1]+o7_carry[1];
                kay_sum1 <= o7_sum[2]+o7_carry[2];
                kay_sum2 <= o7_sum[3]+o7_carry[3];
                kay_sum3 <= o7_sum[4]+o7_carry[4];
                kay_sum4 <= o7_sum[5]+o7_carry[5];
                kay_sum5 <= o7_sum[6]+o7_carry[6];
                kay_sum6 <= o7_sum[7]+o7_carry[7];
                kay_sum7 <= o7_sum[8]+o7_carry[8];
            end
        end
    end
endmodule
