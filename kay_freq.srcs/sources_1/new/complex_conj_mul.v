`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/21 22:04:11
// Design Name: 
// Module Name: complex_conj_mul
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module complex_conj_mul(
input wire signed [15:0] i_now,
input wire signed [15:0] q_now,
input wire signed [15:0] i_prev,
input wire signed [15:0] q_prev,
input wire signed [32:0] re_out,
input wire signed [32:0] im_out);

wire signed [31:0] ii,qq,qi,iq;
assign ii = i_now * i_prev;
assign qq = q_now * q_prev;
assign qi = q_now * i_prev;
assign iq = i_now * q_prev;

assign re_out = $signed({ii[31],ii}) + $signed({qq[31],qq});
assign im_out = $signed({qi[31],qi}) - $signed({iq[31],iq});
endmodule
