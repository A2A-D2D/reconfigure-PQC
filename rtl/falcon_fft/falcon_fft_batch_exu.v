`timescale 1ns/1ps
// ============================================================================
// Module: falcon_fft_batch_exu
// ============================================================================
// Purpose:
//   One 5-lane Falcon FFT/iFFT batch execution wrapper.  This is the datapath
//   slice used by a full FFT task engine: the stage controller and address
//   generator choose which butterflies enter each lane; this module runs the
//   existing shared f64 BFU and returns the two updated complex values.
//
// Important:
//   For iFFT, feed a conjugated twiddle into tw_*_vec before asserting start.
//   The GS BFU computes y1 = w * (a-b) and does not conjugate internally.
// ============================================================================

module falcon_fft_batch_exu #(
    parameter LANES = 5,
    parameter IDX_W = 3,
    parameter FE_LATENCY = 1,
    parameter BACKEND = 0       // 0=shared FE, 1=pipelined FE
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire                 inverse,
    input  wire [LANES-1:0]     lane_mask,
    input  wire [LANES*64-1:0]  va_re_vec,
    input  wire [LANES*64-1:0]  va_im_vec,
    input  wire [LANES*64-1:0]  vb_re_vec,
    input  wire [LANES*64-1:0]  vb_im_vec,
    input  wire [LANES*64-1:0]  tw_re_vec,
    input  wire [LANES*64-1:0]  tw_im_vec,

    output wire                 busy,
    output wire                 done,
    output wire [LANES*64-1:0]  y0_re_vec,
    output wire [LANES*64-1:0]  y0_im_vec,
    output wire [LANES*64-1:0]  y1_re_vec,
    output wire [LANES*64-1:0]  y1_im_vec,
    output wire                 status_invalid,
    output wire                 status_overflow,
    output wire                 status_underflow,
    output wire                 status_inexact
);

    generate
        if (BACKEND == 0) begin : g_shared_backend
            reconfig_fft_f64_shared_operator #(
                .LANES(LANES),
                .IDX_W(IDX_W),
                .FE_LATENCY(FE_LATENCY)
            ) u_shared_operator (
                .clk              (clk),
                .rst_n            (rst_n),
                .valid_in         (start),
                .ready_in         (1'b1),
                .inverse          (inverse),
                .lane_mask        (lane_mask),
                .va_re_vec        (va_re_vec),
                .va_im_vec        (va_im_vec),
                .vb_re_vec        (vb_re_vec),
                .vb_im_vec        (vb_im_vec),
                .tw_re_vec        (tw_re_vec),
                .tw_im_vec        (tw_im_vec),
                .busy             (busy),
                .valid_out        (done),
                .va_out_re_vec    (y0_re_vec),
                .va_out_im_vec    (y0_im_vec),
                .vb_out_re_vec    (y1_re_vec),
                .vb_out_im_vec    (y1_im_vec),
                .status_invalid   (status_invalid),
                .status_overflow  (status_overflow),
                .status_underflow (status_underflow),
                .status_inexact   (status_inexact)
            );
        end else begin : g_pipe_backend
            // The pipelined backend is the performance option.  It accepts a
            // new vector whenever start is asserted; inactive lanes should be
            // zeroed or ignored by the surrounding lane_mask-aware writer.
            assign busy = 1'b0;

            reconfig_fft_f64_pipe_operator #(
                .LANES(LANES)
            ) u_pipe_operator (
                .clk              (clk),
                .rst_n            (rst_n),
                .valid_in         (start),
                .inverse          (inverse),
                .va_re_vec        (va_re_vec),
                .va_im_vec        (va_im_vec),
                .vb_re_vec        (vb_re_vec),
                .vb_im_vec        (vb_im_vec),
                .tw_re_vec        (tw_re_vec),
                .tw_im_vec        (tw_im_vec),
                .valid_out        (done),
                .va_out_re_vec    (y0_re_vec),
                .va_out_im_vec    (y0_im_vec),
                .vb_out_re_vec    (y1_re_vec),
                .vb_out_im_vec    (y1_im_vec),
                .status_invalid   (status_invalid),
                .status_overflow  (status_overflow),
                .status_underflow (status_underflow),
                .status_inexact   (status_inexact)
            );
        end
    endgenerate

endmodule
