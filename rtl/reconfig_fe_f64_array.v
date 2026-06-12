`timescale 1ns/1ps
// Module: reconfig_fe_f64_array
// Purpose: vector wrapper for Falcon f64 FE lanes.

module reconfig_fe_f64_array #(
    parameter LANES  = 8,
    parameter MODE_W = 4
) (
    input                       clk,
    input                       rst_n,
    input                       valid_in,
    input      [MODE_W-1:0]     mode,
    input      [LANES*64-1:0]   a_re_vec,
    input      [LANES*64-1:0]   a_im_vec,
    input      [LANES*64-1:0]   b_re_vec,
    input      [LANES*64-1:0]   b_im_vec,
    input      [LANES*64-1:0]   c_re_vec,
    input      [LANES*64-1:0]   c_im_vec,
    input      [LANES*64-1:0]   w_re_vec,
    input      [LANES*64-1:0]   w_im_vec,
    output                      valid_out,
    output     [LANES*64-1:0]   y0_re_vec,
    output     [LANES*64-1:0]   y0_im_vec,
    output     [LANES*64-1:0]   y1_re_vec,
    output     [LANES*64-1:0]   y1_im_vec,
    output                      status_invalid,
    output                      status_overflow,
    output                      status_underflow,
    output                      status_inexact
);

    wire [LANES-1:0] lane_valid;
    wire [LANES-1:0] lane_invalid;
    wire [LANES-1:0] lane_overflow;
    wire [LANES-1:0] lane_underflow;
    wire [LANES-1:0] lane_inexact;

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : g_lane
            reconfig_fe_f64 #(
                .MODE_W(MODE_W)
            ) u_lane (
                .clk(clk),
                .rst_n(rst_n),
                .valid_in(valid_in),
                .mode(mode),
                .a_re(a_re_vec[i*64 +: 64]),
                .a_im(a_im_vec[i*64 +: 64]),
                .b_re(b_re_vec[i*64 +: 64]),
                .b_im(b_im_vec[i*64 +: 64]),
                .c_re(c_re_vec[i*64 +: 64]),
                .c_im(c_im_vec[i*64 +: 64]),
                .w_re(w_re_vec[i*64 +: 64]),
                .w_im(w_im_vec[i*64 +: 64]),
                .valid_out(lane_valid[i]),
                .y0_re(y0_re_vec[i*64 +: 64]),
                .y0_im(y0_im_vec[i*64 +: 64]),
                .y1_re(y1_re_vec[i*64 +: 64]),
                .y1_im(y1_im_vec[i*64 +: 64]),
                .status_invalid(lane_invalid[i]),
                .status_overflow(lane_overflow[i]),
                .status_underflow(lane_underflow[i]),
                .status_inexact(lane_inexact[i])
            );
        end
    endgenerate

    assign valid_out        = lane_valid[0];
    assign status_invalid   = |lane_invalid;
    assign status_overflow  = |lane_overflow;
    assign status_underflow = |lane_underflow;
    assign status_inexact   = |lane_inexact;

endmodule
