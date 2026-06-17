`timescale 1ns/1ps
// Module: reconfig_fft_f64_shared_operator
// Purpose: area-controlled Falcon f64 FFT butterfly operator.  It uses the
// shared FE array so a vector batch is completed over multiple cycles.

module reconfig_fft_f64_shared_operator #(
    parameter LANES = 8,
    parameter IDX_W = 4,
    parameter FE_LATENCY = 1
) (
    input                     clk,
    input                     rst_n,
    input                     valid_in,
    input                     ready_in,
    input                     inverse,
    input      [LANES-1:0]    lane_mask,
    input      [LANES*64-1:0] va_re_vec,
    input      [LANES*64-1:0] va_im_vec,
    input      [LANES*64-1:0] vb_re_vec,
    input      [LANES*64-1:0] vb_im_vec,
    input      [LANES*64-1:0] tw_re_vec,
    input      [LANES*64-1:0] tw_im_vec,
    output                    busy,
    output                    valid_out,
    output     [LANES*64-1:0] va_out_re_vec,
    output     [LANES*64-1:0] va_out_im_vec,
    output     [LANES*64-1:0] vb_out_re_vec,
    output     [LANES*64-1:0] vb_out_im_vec,
    output                    status_invalid,
    output                    status_overflow,
    output                    status_underflow,
    output                    status_inexact
);

    localparam [3:0] FE_MODE_CT_BFU_COMPLEX = 4'd0;
    localparam [3:0] FE_MODE_GS_BFU_COMPLEX = 4'd1;

    wire [3:0] mode_sel;

    assign mode_sel = inverse ? FE_MODE_GS_BFU_COMPLEX : FE_MODE_CT_BFU_COMPLEX;

    reconfig_fe_f64_shared_array #(
        .LANES(LANES),
        .MODE_W(4),
        .IDX_W(IDX_W),
        .FE_LATENCY(FE_LATENCY)
    ) u_shared_fe (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .ready_in(ready_in),
        .lane_mask(lane_mask),
        .mode(mode_sel),
        .a_re_vec(va_re_vec),
        .a_im_vec(va_im_vec),
        .b_re_vec(vb_re_vec),
        .b_im_vec(vb_im_vec),
        .c_re_vec({(LANES*64){1'b0}}),
        .c_im_vec({(LANES*64){1'b0}}),
        .w_re_vec(tw_re_vec),
        .w_im_vec(tw_im_vec),
        .busy(busy),
        .valid_out(valid_out),
        .y0_re_vec(va_out_re_vec),
        .y0_im_vec(va_out_im_vec),
        .y1_re_vec(vb_out_re_vec),
        .y1_im_vec(vb_out_im_vec),
        .status_invalid(status_invalid),
        .status_overflow(status_overflow),
        .status_underflow(status_underflow),
        .status_inexact(status_inexact)
    );

endmodule
