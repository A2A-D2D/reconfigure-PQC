`timescale 1ns/1ps
// Module: spuv3_vpu_fe_f64_wrap
// Purpose: SPUV3-facing adapter for the Falcon f64 shared FE path. SPUV3 VPU
// exposes a 320-bit vector register as 10 x 32-bit lanes; this wrapper maps it
// to 5 x 64-bit FE lanes and converts CSR VMASK into the FE lane mask.

module spuv3_vpu_fe_f64_wrap #(
    parameter VMASK_USE_BITMASK = 0,
    parameter FE_LATENCY        = 1
) (
    input                  clk,
    input                  rst_n,
    input                  valid_in,
    input                  ready_in,
    input                  inverse,
    input      [31:0]      csr_vmask_i,
    input      [319:0]     va_re_vr_i,
    input      [319:0]     va_im_vr_i,
    input      [319:0]     vb_re_vr_i,
    input      [319:0]     vb_im_vr_i,
    input      [319:0]     tw_re_vr_i,
    input      [319:0]     tw_im_vr_i,
    output                 busy,
    output                 valid_out,
    output                 done_pulse,
    output     [319:0]     va_re_vr_o,
    output     [319:0]     va_im_vr_o,
    output     [319:0]     vb_re_vr_o,
    output     [319:0]     vb_im_vr_o,
    output     [4:0]       fe_lane_mask_o,
    output                 status_invalid,
    output                 status_overflow,
    output                 status_underflow,
    output                 status_inexact
);

    localparam LANES  = 5;
    localparam IDX_W  = 3;

    reg [4:0] fe_lane_mask;
    integer lane_i;

    always @(*) begin
        fe_lane_mask = 5'b00000;
        for (lane_i = 0; lane_i < LANES; lane_i = lane_i + 1) begin
            if (VMASK_USE_BITMASK != 0) begin
                fe_lane_mask[lane_i] =
                    csr_vmask_i[lane_i*2] & csr_vmask_i[lane_i*2 + 1];
            end else begin
                fe_lane_mask[lane_i] =
                    (csr_vmask_i[4:0] >= ((lane_i + 1) * 2));
            end
        end
    end

    assign fe_lane_mask_o = fe_lane_mask;
    assign done_pulse     = valid_out & ready_in;

    reconfig_fft_f64_shared_operator #(
        .LANES(LANES),
        .IDX_W(IDX_W),
        .FE_LATENCY(FE_LATENCY)
    ) u_fft_shared (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .ready_in(ready_in),
        .inverse(inverse),
        .lane_mask(fe_lane_mask),
        .va_re_vec(va_re_vr_i),
        .va_im_vec(va_im_vr_i),
        .vb_re_vec(vb_re_vr_i),
        .vb_im_vec(vb_im_vr_i),
        .tw_re_vec(tw_re_vr_i),
        .tw_im_vec(tw_im_vr_i),
        .busy(busy),
        .valid_out(valid_out),
        .va_out_re_vec(va_re_vr_o),
        .va_out_im_vec(va_im_vr_o),
        .vb_out_re_vec(vb_re_vr_o),
        .vb_out_im_vec(vb_im_vr_o),
        .status_invalid(status_invalid),
        .status_overflow(status_overflow),
        .status_underflow(status_underflow),
        .status_inexact(status_inexact)
    );

endmodule
