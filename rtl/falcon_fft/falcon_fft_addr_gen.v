`timescale 1ns/1ps
// ============================================================================
// Module: falcon_fft_addr_gen
// ============================================================================
// Purpose:
//   Generate Falcon FFT/iFFT butterfly addresses for one pair index inside a
//   stage.  This is the address-side counterpart of the f64 butterfly BFU.
//
// Falcon layout:
//   f[0 .. hn-1]  stores real parts
//   f[hn .. n-1] stores imaginary parts
//
// Forward FFT, stage s=0..logn-2:
//   ht = hn >> (s + 1)
//   t  = ht << 1
//   i1 = pair_idx / ht
//   j  = i1*t + (pair_idx % ht)
//   twiddle = GM[(2 << s) + i1]
//
// Inverse FFT, stage s=0..logn-2:
//   t  = 1 << s
//   dt = t << 1
//   i1 = pair_idx / t
//   j  = i1*dt + (pair_idx % t)
//   twiddle = conj(GM[(n >> (s + 1)) + i1])
//
// Notes:
//   1. This module only emits addresses and the GM table index.  The iFFT
//      conjugation is a twiddle-data responsibility: negate the imaginary
//      component before feeding the GS butterfly.
//   2. pair_valid deasserts if pair_idx is outside the stage pair count.
// ============================================================================

module falcon_fft_addr_gen #(
    parameter LOGN_W = 4,
    parameter STAGE_W = 4,
    parameter ADDR_W = 10
) (
    input  wire                 inverse,
    input  wire [LOGN_W-1:0]    logn,
    input  wire [STAGE_W-1:0]   stage_idx,
    input  wire [ADDR_W-1:0]    pair_idx,

    output reg  [ADDR_W-1:0]    a_re_addr,
    output reg  [ADDR_W-1:0]    a_im_addr,
    output reg  [ADDR_W-1:0]    b_re_addr,
    output reg  [ADDR_W-1:0]    b_im_addr,
    output reg  [ADDR_W-1:0]    twiddle_addr,
    output reg                  pair_valid
);

    reg [ADDR_W:0]   n_val;
    reg [ADDR_W-1:0] hn_val;
    reg [ADDR_W-1:0] pairs_per_stage;
    reg [ADDR_W-1:0] stride;
    reg [ADDR_W-1:0] stride_mask;
    reg [ADDR_W-1:0] block_idx;
    reg [ADDR_W-1:0] local_idx;
    reg [ADDR_W-1:0] j_idx;
    reg [ADDR_W-1:0] tw_base;
    reg [STAGE_W-1:0] fwd_stride_shift;

    always @(*) begin
        n_val           = ({ {(ADDR_W-1){1'b0}}, 1'b1 } << logn);
        hn_val          = n_val >> 1;
        pairs_per_stage = n_val >> 2;

        a_re_addr       = {ADDR_W{1'b0}};
        a_im_addr       = {ADDR_W{1'b0}};
        b_re_addr       = {ADDR_W{1'b0}};
        b_im_addr       = {ADDR_W{1'b0}};
        twiddle_addr    = {ADDR_W{1'b0}};
        pair_valid      = 1'b0;

        stride          = {ADDR_W{1'b0}};
        stride_mask     = {ADDR_W{1'b0}};
        block_idx       = {ADDR_W{1'b0}};
        local_idx       = {ADDR_W{1'b0}};
        j_idx           = {ADDR_W{1'b0}};
        tw_base         = {ADDR_W{1'b0}};
        fwd_stride_shift = {STAGE_W{1'b0}};

        if ((logn >= 4'd2) && (stage_idx < (logn - 1'b1)) &&
            (pair_idx < pairs_per_stage)) begin
            pair_valid = 1'b1;

            if (inverse) begin
                stride      = ({ {(ADDR_W-1){1'b0}}, 1'b1 } << stage_idx);
                stride_mask = stride - 1'b1;
                block_idx   = pair_idx >> stage_idx;
                local_idx   = pair_idx & stride_mask;
                j_idx       = (block_idx << (stage_idx + 1'b1)) + local_idx;
                tw_base     = n_val >> (stage_idx + 1'b1);

                a_re_addr    = j_idx;
                b_re_addr    = j_idx + stride;
                twiddle_addr = tw_base + block_idx;
            end else begin
                fwd_stride_shift = logn - stage_idx - 4'd2;
                stride      = ({ {(ADDR_W-1){1'b0}}, 1'b1 } << fwd_stride_shift);
                stride_mask = stride - 1'b1;
                block_idx   = pair_idx >> fwd_stride_shift;
                local_idx   = pair_idx & stride_mask;
                j_idx       = (block_idx << (fwd_stride_shift + 1'b1)) + local_idx;
                tw_base     = ({ {(ADDR_W-1){1'b0}}, 1'b1 } << (stage_idx + 1'b1));

                a_re_addr    = j_idx;
                b_re_addr    = j_idx + stride;
                twiddle_addr = tw_base + block_idx;
            end

            a_im_addr = a_re_addr + hn_val;
            b_im_addr = b_re_addr + hn_val;
        end
    end

endmodule
