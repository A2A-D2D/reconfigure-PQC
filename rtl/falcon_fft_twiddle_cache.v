`timescale 1ns/1ps
// ============================================================================
// Module: falcon_fft_twiddle_cache
// ============================================================================
// Purpose:
//   Independent LANES-wide f64 GM twiddle cache/ROM for Falcon FFT/iFFT.
//   Keeping twiddle reads outside the main data buffer is important for FE
//   utilization because each butterfly batch already needs four data streams.
//
// File format:
//   RE_FILE and IM_FILE contain one 64-bit f64 hex value per line.
//
// IFFT:
//   Set conj_i=1 to negate the imaginary part, matching Falcon iFFT's
//   conj(GM) convention before the RTL GS BFU.
// ============================================================================

module falcon_fft_twiddle_cache #(
    parameter N = 1024,
    parameter LANES = 5,
    parameter ADDR_W = 10,
    parameter RE_FILE = "gm_rom_re.hex",
    parameter IM_FILE = "gm_rom_im.hex"
) (
    input  wire                 conj_i,
    input  wire [LANES*ADDR_W-1:0] twiddle_addr_vec_i,
    output wire [LANES*64-1:0]  tw_re_vec_o,
    output wire [LANES*64-1:0]  tw_im_vec_o
);

    reg [63:0] gm_re [0:N-1];
    reg [63:0] gm_im [0:N-1];

    initial begin
        $readmemh(RE_FILE, gm_re);
        $readmemh(IM_FILE, gm_im);
    end

    genvar lane_g;
    generate
        for (lane_g = 0; lane_g < LANES; lane_g = lane_g + 1) begin : g_tw
            wire [ADDR_W-1:0] tw_addr;
            wire [63:0] im_raw;

            assign tw_addr = twiddle_addr_vec_i[lane_g*ADDR_W +: ADDR_W];
            assign im_raw = gm_im[tw_addr];
            assign tw_re_vec_o[lane_g*64 +: 64] = gm_re[tw_addr];
            assign tw_im_vec_o[lane_g*64 +: 64] = conj_i ? {~im_raw[63], im_raw[62:0]} : im_raw;
        end
    endgenerate

endmodule
