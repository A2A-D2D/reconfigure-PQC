`timescale 1ns/1ps
// ============================================================================
// Module: falcon_fft_buffered_engine
// ============================================================================
// Purpose:
//   Performance-oriented Falcon FFT/iFFT engine with local ping-pong data
//   buffer and independent twiddle cache.  SPU/CSR starts one transform task;
//   the FE block then keeps stage-to-stage data local.
//
// Buffer policy:
//   - preload input into bank 0 through ext_* before start.
//   - stage s reads bank s[0] and writes bank ~s[0].
//   - final_bank_o tells software which bank to drain after done.
//
// This module is the intended high-utilization path.  The lower-level
// falcon_fft_task_engine remains useful for bring-up with an external
// gather/scatter adapter.
// ============================================================================

module falcon_fft_buffered_engine #(
    parameter N = 1024,
    parameter LANES = 5,
    parameter LOGN_W = 4,
    parameter STAGE_W = 4,
    parameter ADDR_W = 10,
    parameter IDX_W = 3,
    parameter FE_LATENCY = 1,
    parameter BACKEND = 0,
    parameter TW_RE_FILE = "gm_rom_re.hex",
    parameter TW_IM_FILE = "gm_rom_im.hex"
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire                 inverse,
    input  wire [LOGN_W-1:0]    logn,

    // External preload/drain port.
    input  wire                 ext_we,
    input  wire                 ext_bank,
    input  wire [ADDR_W-1:0]    ext_addr,
    input  wire [63:0]          ext_re_i,
    input  wire [63:0]          ext_im_i,
    output wire [63:0]          ext_re_o,
    output wire [63:0]          ext_im_o,

    output wire                 busy,
    output wire                 done,
    output wire                 final_bank_o,

    output wire                 status_invalid,
    output wire                 status_overflow,
    output wire                 status_underflow,
    output wire                 status_inexact
);

    wire load_valid;
    wire [STAGE_W-1:0] load_stage_idx;
    wire [ADDR_W-1:0] load_batch_idx;
    wire [LANES-1:0] load_lane_mask;
    wire [LANES*ADDR_W-1:0] load_a_re_addr;
    wire [LANES*ADDR_W-1:0] load_a_im_addr;
    wire [LANES*ADDR_W-1:0] load_b_re_addr;
    wire [LANES*ADDR_W-1:0] load_b_im_addr;
    wire [LANES*ADDR_W-1:0] load_twiddle_addr;
    wire [LANES*64-1:0] load_va_re;
    wire [LANES*64-1:0] load_va_im;
    wire [LANES*64-1:0] load_vb_re;
    wire [LANES*64-1:0] load_vb_im;
    wire [LANES*64-1:0] load_tw_re;
    wire [LANES*64-1:0] load_tw_im;

    wire store_valid;
    wire [STAGE_W-1:0] store_stage_idx;
    wire [ADDR_W-1:0] store_batch_idx;
    wire [LANES-1:0] store_lane_mask;
    wire [LANES*ADDR_W-1:0] store_a_re_addr;
    wire [LANES*ADDR_W-1:0] store_a_im_addr;
    wire [LANES*ADDR_W-1:0] store_b_re_addr;
    wire [LANES*ADDR_W-1:0] store_b_im_addr;
    wire [LANES*64-1:0] store_y0_re;
    wire [LANES*64-1:0] store_y0_im;
    wire [LANES*64-1:0] store_y1_re;
    wire [LANES*64-1:0] store_y1_im;

    wire read_bank;
    wire write_bank;

    assign read_bank = load_stage_idx[0];
    assign write_bank = ~store_stage_idx[0];
    assign final_bank_o = (logn - 1'b1) & 1'b1;

    falcon_fft_task_engine #(
        .LANES(LANES),
        .LOGN_W(LOGN_W),
        .STAGE_W(STAGE_W),
        .ADDR_W(ADDR_W),
        .IDX_W(IDX_W),
        .FE_LATENCY(FE_LATENCY),
        .BACKEND(BACKEND)
    ) u_task_engine (
        .clk                  (clk),
        .rst_n                (rst_n),
        .start                (start),
        .inverse              (inverse),
        .logn                 (logn),
        .busy                 (busy),
        .done                 (done),
        .load_valid_o         (load_valid),
        .load_ready_i         (1'b1),
        .load_stage_idx_o     (load_stage_idx),
        .load_batch_idx_o     (load_batch_idx),
        .load_lane_mask_o     (load_lane_mask),
        .load_a_re_addr_o     (load_a_re_addr),
        .load_a_im_addr_o     (load_a_im_addr),
        .load_b_re_addr_o     (load_b_re_addr),
        .load_b_im_addr_o     (load_b_im_addr),
        .load_twiddle_addr_o  (load_twiddle_addr),
        .load_va_re_vec_i     (load_va_re),
        .load_va_im_vec_i     (load_va_im),
        .load_vb_re_vec_i     (load_vb_re),
        .load_vb_im_vec_i     (load_vb_im),
        .load_tw_re_vec_i     (load_tw_re),
        .load_tw_im_vec_i     (load_tw_im),
        .store_valid_o        (store_valid),
        .store_ready_i        (1'b1),
        .store_stage_idx_o    (store_stage_idx),
        .store_batch_idx_o    (store_batch_idx),
        .store_lane_mask_o    (store_lane_mask),
        .store_a_re_addr_o    (store_a_re_addr),
        .store_a_im_addr_o    (store_a_im_addr),
        .store_b_re_addr_o    (store_b_re_addr),
        .store_b_im_addr_o    (store_b_im_addr),
        .store_y0_re_vec_o    (store_y0_re),
        .store_y0_im_vec_o    (store_y0_im),
        .store_y1_re_vec_o    (store_y1_re),
        .store_y1_im_vec_o    (store_y1_im),
        .status_invalid       (status_invalid),
        .status_overflow      (status_overflow),
        .status_underflow     (status_underflow),
        .status_inexact       (status_inexact)
    );

    falcon_fft_local_buffer #(
        .N(N),
        .LANES(LANES),
        .ADDR_W(ADDR_W)
    ) u_local_buffer (
        .clk              (clk),
        .ext_we           (ext_we),
        .ext_bank         (ext_bank),
        .ext_addr         (ext_addr),
        .ext_re_i         (ext_re_i),
        .ext_im_i         (ext_im_i),
        .ext_re_o         (ext_re_o),
        .ext_im_o         (ext_im_o),
        .read_bank        (read_bank),
        .read_lane_mask   (load_lane_mask),
        .a_re_addr_vec    (load_a_re_addr),
        .a_im_addr_vec    (load_a_im_addr),
        .b_re_addr_vec    (load_b_re_addr),
        .b_im_addr_vec    (load_b_im_addr),
        .va_re_vec        (load_va_re),
        .va_im_vec        (load_va_im),
        .vb_re_vec        (load_vb_re),
        .vb_im_vec        (load_vb_im),
        .write_en         (store_valid),
        .write_bank       (write_bank),
        .write_lane_mask  (store_lane_mask),
        .y0_re_addr_vec   (store_a_re_addr),
        .y0_im_addr_vec   (store_a_im_addr),
        .y1_re_addr_vec   (store_b_re_addr),
        .y1_im_addr_vec   (store_b_im_addr),
        .y0_re_vec        (store_y0_re),
        .y0_im_vec        (store_y0_im),
        .y1_re_vec        (store_y1_re),
        .y1_im_vec        (store_y1_im)
    );

    falcon_fft_twiddle_cache #(
        .N(N),
        .LANES(LANES),
        .ADDR_W(ADDR_W),
        .RE_FILE(TW_RE_FILE),
        .IM_FILE(TW_IM_FILE)
    ) u_twiddle_cache (
        .conj_i             (inverse),
        .twiddle_addr_vec_i (load_twiddle_addr),
        .tw_re_vec_o        (load_tw_re),
        .tw_im_vec_o        (load_tw_im)
    );

endmodule
