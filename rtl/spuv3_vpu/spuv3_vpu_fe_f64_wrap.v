`timescale 1ns/1ps
// ============================================================================
// Module: spuv3_vpu_fe_f64_wrap
// ============================================================================
// Purpose:
//   SPUV3-facing adapter for the Falcon f64 shared FE path.  SPUV3 exposes a
//   320-bit vector register (VR) as ten 32-bit lanes.  Falcon f64 arithmetic
//   naturally groups that same 320-bit payload as five 64-bit FE lanes.
//
// Responsibilities:
//   1. Pass 320-bit VR operands into the f64 FFT/FE compute core.
//   2. Convert the CSR VMASK register into a 5-bit FE lane mask.
//   3. Present SPUV3-style busy/valid/done status for task control.
//
// Lane mapping:
//   VR[ 63:  0] -> FE lane 0
//   VR[127: 64] -> FE lane 1
//   VR[191:128] -> FE lane 2
//   VR[255:192] -> FE lane 3
//   VR[319:256] -> FE lane 4
//
// CSR VMASK modes:
//   BITMASK mode:
//     Each FE lane is enabled only when both of its two 32-bit sub-lanes are
//     enabled in csr_vmask_i[9:0].
//
//   COUNT mode:
//     csr_vmask_i[4:0] is treated as the active 32-bit lane count.  FE lane i
//     is enabled when the count covers both 32-bit sub-lanes for that lane.
//
// Control/data split:
//   CSR registers should configure mode, VMASK, addresses, length, and start.
//   Bulk vector data should arrive through the VR/DLM path, optionally using
//   spuv3_vpu_fe_mem_pack at the memory boundary.  This wrapper only owns the
//   compute-side VR and mask adaptation.
// ============================================================================

module spuv3_vpu_fe_f64_wrap #(
    parameter VMASK_USE_BITMASK = 0,     // 0=count mode, 1=bitmask mode
    parameter FE_LATENCY        = 1      // pipeline latency override (cycles)
) (
    // Clock and reset.
    input                  clk,
    input                  rst_n,

    // Task handshake.
    input                  valid_in,         // start a new FE operation
    input                  ready_in,         // downstream ready (used for done_pulse)
    input                  inverse,          // 0=forward (CT), 1=inverse (GS)

    // CSR VMASK: 32-bit lane-enable or active-lane-count register.
    input      [31:0]      csr_vmask_i,

    // 320-bit VR inputs: real, imaginary, and twiddle operands.
    input      [319:0]     va_re_vr_i,
    input      [319:0]     va_im_vr_i,
    input      [319:0]     vb_re_vr_i,
    input      [319:0]     vb_im_vr_i,
    input      [319:0]     tw_re_vr_i,
    input      [319:0]     tw_im_vr_i,

    // Status outputs.
    output                 busy,
    output                 valid_out,
    output                 done_pulse,

    // 320-bit VR outputs.
    output     [319:0]     va_re_vr_o,
    output     [319:0]     va_im_vr_o,
    output     [319:0]     vb_re_vr_o,
    output     [319:0]     vb_im_vr_o,

    // FE lane mask exposed for debug or downstream chaining.
    output     [4:0]       fe_lane_mask_o,

    // IEEE-754 exception flags from the FE core.
    output                 status_invalid,
    output                 status_overflow,
    output                 status_underflow,
    output                 status_inexact
);

    localparam LANES = 5;                   // 5 x 64-bit = 320-bit VR
    localparam IDX_W = 3;                   // ceil(log2(5)) for lane indexing

    // ----------------------------------------------------------------------
    // CSR VMASK -> FE lane mask conversion
    // ----------------------------------------------------------------------
    // BITMASK mode:
    //   lane i covers 32-bit sub-lanes {2i+1, 2i}.  Both sub-lanes must be
    //   enabled before the corresponding f64 lane is active.
    //
    // COUNT mode:
    //   csr_vmask_i[4:0] holds the number of active 32-bit lanes.  A 64-bit
    //   f64 lane becomes active only when the count reaches both sub-lanes.
    // ----------------------------------------------------------------------
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

    // Completion pulse used by the CSR/status side.  The compute core owns
    // valid_out; SPUV3 observes done only when the downstream side accepts it.
    assign done_pulse = valid_out & ready_in;

    // Shared f64 FFT/FE compute core.  No additional bit repacking is needed
    // here because both sides use the same 320-bit payload width.
    reconfig_fft_f64_shared_operator #(
        .LANES(LANES),
        .IDX_W(IDX_W),
        .FE_LATENCY(FE_LATENCY)
    ) u_fft_shared (
        .clk              (clk),
        .rst_n            (rst_n),
        .valid_in         (valid_in),
        .ready_in         (ready_in),
        .inverse          (inverse),
        .lane_mask        (fe_lane_mask),
        .va_re_vec        (va_re_vr_i),
        .va_im_vec        (va_im_vr_i),
        .vb_re_vec        (vb_re_vr_i),
        .vb_im_vec        (vb_im_vr_i),
        .tw_re_vec        (tw_re_vr_i),
        .tw_im_vec        (tw_im_vr_i),
        .busy             (busy),
        .valid_out        (valid_out),
        .va_out_re_vec    (va_re_vr_o),
        .va_out_im_vec    (va_im_vr_o),
        .vb_out_re_vec    (vb_re_vr_o),
        .vb_out_im_vec    (vb_im_vr_o),
        .status_invalid   (status_invalid),
        .status_overflow  (status_overflow),
        .status_underflow (status_underflow),
        .status_inexact   (status_inexact)
    );

endmodule
