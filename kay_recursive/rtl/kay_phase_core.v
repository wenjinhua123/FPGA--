`timescale 1ns/1ps
// Sliding Kay numerator for N=1024 raw complex samples (1023 increments).
// phase0..7 are chronological, signed radians with 18 fractional bits.
// One result per accepted group, ending at phase6. phase7 is still processed
// into feedback for the following group. All registers freeze when ce=0.
// Input edge to output edge: 11 enabled-clock intervals.
(* use_dsp = "no" *)
module kay_phase_core (
    input wire clk, ce, rst, valid_in,
    input wire signed [20:0] phase0, phase1, phase2, phase3,
    input wire signed [20:0] phase4, phase5, phase6, phase7,
    output reg valid_out,
    output reg signed [51:0] weighted_sum
);
    // The 1024 physical slots hold a mathematical window of 1023 values.
    // A read is one physical slot ahead of the write; bank7 crosses the row.
    (* ram_style = "distributed" *) reg signed [20:0] bank0[0:127],bank1[0:127];
    (* ram_style = "distributed" *) reg signed [20:0] bank2[0:127],bank3[0:127];
    (* ram_style = "distributed" *) reg signed [20:0] bank4[0:127],bank5[0:127];
    (* ram_style = "distributed" *) reg signed [20:0] bank6[0:127],bank7[0:127];
    reg [6:0] row;
    reg [9:0] fill;
    wire [6:0] next_row=row+7'd1;
    wire signed [20:0] incoming[0:7],outgoing[0:7];
    assign incoming[0]=phase0;assign incoming[1]=phase1;
    assign incoming[2]=phase2;assign incoming[3]=phase3;
    assign incoming[4]=phase4;assign incoming[5]=phase5;
    assign incoming[6]=phase6;assign incoming[7]=phase7;
    assign outgoing[0]=bank1[row];assign outgoing[1]=bank2[row];
    assign outgoing[2]=bank3[row];assign outgoing[3]=bank4[row];
    assign outgoing[4]=bank5[row];assign outgoing[5]=bank6[row];
    assign outgoing[6]=bank7[row];assign outgoing[7]=bank0[next_row];
    // Preserve one identity LUT on each RAM-read capture path for physical
    // hold timing. Without it Vivado packs RAM/MUX/capture-FF into a shape
    // whose intra-site connection cannot be lengthened by the router.
    // This has no arithmetic effect and adds no register or clock latency.
    wire signed [20:0] capture_selected[0:7],capture_buffered[0:7];
    genvar capture_lane,capture_bit;
    generate for(capture_lane=0;capture_lane<8;capture_lane=capture_lane+1) begin:read_capture
        assign capture_selected[capture_lane]=(fill+capture_lane>=1023) ? outgoing[capture_lane] : 21'sd0;
`ifdef SYNTHESIS
        for(capture_bit=0;capture_bit<21;capture_bit=capture_bit+1) begin:bit_delay
            (* dont_touch="true" *) LUT1 #(.INIT(2'h2)) read_hold_buffer(
                .I0(capture_selected[capture_lane][capture_bit]),
                .O(capture_buffered[capture_lane][capture_bit]));
        end
`else
        assign capture_buffered[capture_lane]=capture_selected[capture_lane];
`endif
    end endgenerate
    reg signed [20:0] cap_b[0:7],cap_a[0:7];
    reg [6:0] group_pipe,result_pipe;
    reg signed [51:0] a7_pipe[0:6];
    integer i;
    always @(posedge clk) begin
        if(rst) begin
            row<=0;fill<=0;group_pipe<=0;result_pipe<=0;
        end else if(ce) begin
            group_pipe<={group_pipe[5:0],valid_in};
            result_pipe<={result_pipe[5:0],valid_in && fill>=10'd1016};
            for(i=0;i<8;i=i+1) begin
                cap_b[i]<=incoming[i];
                cap_a[i]<=capture_buffered[i];
            end
            a7_pipe[0]<={{31{capture_buffered[7][20]}},capture_buffered[7]};
            for(i=1;i<7;i=i+1)a7_pipe[i]<=a7_pipe[i-1];
            if(valid_in) begin
                bank0[row]<=phase0;bank1[row]<=phase1;
                bank2[row]<=phase2;bank3[row]<=phase3;
                bank4[row]<=phase4;bank5[row]<=phase5;
                bank6[row]<=phase6;bank7[row]<=phase7;
                row<=next_row;
                fill<=(fill>=10'd1015) ? 10'd1023 : fill+10'd8;
            end
        end
    end

    // Constant products only. Every expression is explicitly shift/add.
    // Function arguments are elaboration-time constants between -16 and 16.
    function signed [51:0] small_product;
        input signed [51:0] value;
        input integer coefficient;
        reg signed [51:0] positive;
        integer magnitude;
        begin
            magnitude=coefficient<0?-coefficient:coefficient;
            case(magnitude)
                0:positive=0; 1:positive=value; 2:positive=value<<<1;
                3:positive=(value<<<2)-value; 4:positive=value<<<2;
                5:positive=(value<<<2)+value; 6:positive=(value<<<2)+(value<<<1);
                7:positive=(value<<<3)-value; 8:positive=value<<<3;
                9:positive=(value<<<3)+value; 10:positive=(value<<<3)+(value<<<1);
                11:positive=(value<<<3)+(value<<<1)+value;
                12:positive=(value<<<4)-(value<<<2);
                13:positive=(value<<<4)-(value<<<1)-value;
                14:positive=(value<<<4)-(value<<<1);
                15:positive=(value<<<4)-value; 16:positive=value<<<4;
                default:positive=0;
            endcase
            small_product=coefficient<0?-positive:positive;
        end
    endfunction

    // Let S=sum(x_j), T=sum(j*x_j), W=sum(j*(1024-j)*x_j), V=W-1032T.
    // Advancing eight values gives S'=S+DS, T'=T-8S+DT, V'=V+16T+DV.
    // For h=7-lane: DT=(1023-h)b+h*a,
    // DV=(h-1031)(1023-h)b+h(h-8)a. The large coefficient is expanded
    // around 2^20 to avoid a long constant-multiplier carry chain.
    reg signed [51:0] p_ds[0:7],p_tb[0:7],p_tm[0:7],p_ta[0:7];
    reg signed [51:0] p_vh[0:7],p_vm[0:7],p_vb[0:7],p_va[0:7];
    reg signed [51:0] q_ds[0:7],q_ts[0:7],q_tc[0:7],q_vs[0:7],q_vc[0:7];
    reg signed [51:0] r_ds[0:7],r_dt[0:7],r_dv[0:7];
    reg signed [51:0] pair_s[0:3],pair_t[0:3],pair_v[0:3];
    reg signed [51:0] four_s[0:1],four_t[0:1],four_v[0:1];
    reg signed [51:0] eight_s,eight_t,eight_v;
    genvar lane;
    generate for(lane=0;lane<8;lane=lane+1) begin:terms
        wire signed [51:0] b={{31{cap_b[lane][20]}},cap_b[lane]};
        wire signed [51:0] a={{31{cap_a[lane][20]}},cap_a[lane]};
        wire [51:0] vs1=p_vh[lane]^p_vm[lane]^p_vb[lane];
        wire [51:0] vc1=((p_vh[lane]&p_vm[lane])|(p_vh[lane]&p_vb[lane])|(p_vm[lane]&p_vb[lane]))<<1;
        always @(posedge clk) begin
            if(!rst && ce) begin
                // n+1: small products; n+2: carry-save; n+3: carry propagation.
                p_ds[lane]<=b-a;
                p_tb[lane]<=b<<<10;
                p_tm[lane]<=small_product(b,lane-8);
                p_ta[lane]<=small_product(a,7-lane);
                p_vh[lane]<=-(b<<<20);
                p_vm[lane]<=-(small_product(b,lane-4)<<<11);
                p_vb[lane]<=small_product(b,16-(lane-4)*(lane-4));
                p_va[lane]<=small_product(a,(7-lane)*(-1-lane));
                q_ds[lane]<=p_ds[lane];
                q_ts[lane]<=p_tb[lane]^p_tm[lane]^p_ta[lane];
                q_tc[lane]<=((p_tb[lane]&p_tm[lane])|(p_tb[lane]&p_ta[lane])|(p_tm[lane]&p_ta[lane]))<<1;
                q_vs[lane]<=vs1^vc1^p_va[lane];
                q_vc[lane]<=((vs1&vc1)|(vs1&p_va[lane])|(vc1&p_va[lane]))<<1;
                r_ds[lane]<=q_ds[lane];
                r_dt[lane]<=q_ts[lane]+q_tc[lane];
                r_dv[lane]<=q_vs[lane]+q_vc[lane];
            end
        end
    end endgenerate
    integer tree;
    always @(posedge clk) begin
        if(!rst && ce) begin
            for(tree=0;tree<4;tree=tree+1) begin
                pair_s[tree]<=r_ds[2*tree]+r_ds[2*tree+1];
                pair_t[tree]<=r_dt[2*tree]+r_dt[2*tree+1];
                pair_v[tree]<=r_dv[2*tree]+r_dv[2*tree+1];
            end
            for(tree=0;tree<2;tree=tree+1) begin
                four_s[tree]<=pair_s[2*tree]+pair_s[2*tree+1];
                four_t[tree]<=pair_t[2*tree]+pair_t[2*tree+1];
                four_v[tree]<=pair_v[2*tree]+pair_v[2*tree+1];
            end
            eight_s<=four_s[0]+four_s[1];
            eight_t<=four_t[0]+four_t[1];
            eight_v<=four_v[0]+four_v[1];
        end
    end

    reg signed [51:0] state_s,state_t,state_v;
    wire [51:0] tx=state_t,ty=~(state_s<<3),tz=eight_t;
    wire [51:0] ts=tx^ty^tz;
    wire [51:0] tc=((tx&ty)|(tx&tz)|(ty&tz))<<1;
    wire signed [51:0] next_t=ts+{tc[51:1],1'b1};
    wire [51:0] vx=state_v,vy=state_t<<4,vz=eight_v;
    wire [51:0] vs=vx^vy^vz;
    wire [51:0] vc=((vx&vy)|(vx&vz)|(vy&vz))<<1;
    wire signed [51:0] next_s=state_s+eight_s;
    wire signed [51:0] next_v=vs+vc;
    reg signed [51:0] snap_s,snap_t,snap_v,snap_a;
    reg [3:0] out_pipe;
    always @(posedge clk) begin
        if(rst) begin
            state_s<=0;state_t<=0;state_v<=0;out_pipe<=0;
        end else if(ce) begin
            // n+7. A bubble leaves the mathematical state unchanged.
            out_pipe<={out_pipe[2:0],result_pipe[6]};
            if(group_pipe[6]) begin
                state_s<=next_s;state_t<=next_t;state_v<=next_v;
                snap_s<=next_s;snap_t<=next_t;snap_v<=next_v;snap_a<=a7_pipe[6];
            end
        end
    end

    // The requested result is after lane6 although feedback includes lane7:
    // W7=V8+1030*T8+1023*S8+1023*a7. This removes a second weighted tree.
    reg signed [51:0] o1_t,o1_t2,o1_s,o1_v;
    reg signed [51:0] o2_t,o2_s,o2_v;
    reg [51:0] o3_sum,o3_carry;
    always @(posedge clk) begin
        if(!rst && ce) begin
            o1_t<=(snap_t<<<10)+(snap_t<<<2);
            o1_t2<=snap_t<<<1;o1_s<=snap_s+snap_a;o1_v<=snap_v;
            o2_t<=o1_t+o1_t2;o2_s<=(o1_s<<<10)-o1_s;o2_v<=o1_v;
            o3_sum<=o2_v^o2_t^o2_s;
            o3_carry<=((o2_v&o2_t)|(o2_v&o2_s)|(o2_t&o2_s))<<1;
        end
        if(rst) begin valid_out<=0;weighted_sum<=0;end
        else if(ce) begin
            valid_out<=out_pipe[3];
            if(out_pipe[3])weighted_sum<=o3_sum+o3_carry;
        end
    end
endmodule
