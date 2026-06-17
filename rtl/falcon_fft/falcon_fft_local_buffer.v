`timescale 1ns/1ps
// ============================================================================
// Module: falcon_fft_local_buffer
// ============================================================================
// Purpose:
//   Two-bank local f64 scalar buffer for Falcon FFT/iFFT.  It supports
//   LANES-wide gather and scatter so stage-to-stage data can stay inside the FE
//   block instead of returning to DLM/DPRAM after every butterfly batch.
//
// Use model:
//   - preload bank 0 from DLM/VR before the task starts.
//   - for stage s, read from bank s[0] and write to bank ~s[0].
//   - after the final stage, drain the last write bank back to DLM/VR.
//
// This module intentionally stores the Falcon reference layout directly:
//   f[0 .. hn-1]  = real parts
//   f[hn .. n-1] = imaginary parts
// Address generation therefore passes full f[] indexes for both real and imag
// values, and writeback stores y0/y1 components back to those full indexes.
// ============================================================================

module falcon_fft_local_buffer #(
    parameter N = 1024,
    parameter LANES = 5,
    parameter ADDR_W = 10
) (
    input  wire                 clk,

    // External preload/drain access.  ext_data_i/ext_data_o use ext_re_i/o;
    // ext_im_i/o are kept as aliases for older smoke tests.
    input  wire                 ext_we,
    input  wire                 ext_bank,
    input  wire [ADDR_W-1:0]    ext_addr,
    input  wire [63:0]          ext_re_i,
    input  wire [63:0]          ext_im_i,
    output wire [63:0]          ext_re_o,
    output wire [63:0]          ext_im_o,

    // LANES-wide gather access for the FE task engine.
    input  wire                 read_bank,
    input  wire [LANES-1:0]     read_lane_mask,
    input  wire [LANES*ADDR_W-1:0] a_re_addr_vec,
    input  wire [LANES*ADDR_W-1:0] a_im_addr_vec,
    input  wire [LANES*ADDR_W-1:0] b_re_addr_vec,
    input  wire [LANES*ADDR_W-1:0] b_im_addr_vec,
    output wire [LANES*64-1:0]  va_re_vec,
    output wire [LANES*64-1:0]  va_im_vec,
    output wire [LANES*64-1:0]  vb_re_vec,
    output wire [LANES*64-1:0]  vb_im_vec,

    // LANES-wide scatter access for FE results.
    input  wire                 write_en,
    input  wire                 write_bank,
    input  wire [LANES-1:0]     write_lane_mask,
    input  wire [LANES*ADDR_W-1:0] y0_re_addr_vec,
    input  wire [LANES*ADDR_W-1:0] y0_im_addr_vec,
    input  wire [LANES*ADDR_W-1:0] y1_re_addr_vec,
    input  wire [LANES*ADDR_W-1:0] y1_im_addr_vec,
    input  wire [LANES*64-1:0]  y0_re_vec,
    input  wire [LANES*64-1:0]  y0_im_vec,
    input  wire [LANES*64-1:0]  y1_re_vec,
    input  wire [LANES*64-1:0]  y1_im_vec
);

    reg [63:0] bank0 [0:N-1];
    reg [63:0] bank1 [0:N-1];

    assign ext_re_o = ext_bank ? bank1[ext_addr] : bank0[ext_addr];
    assign ext_im_o = ext_re_o;

    genvar lane_g;
    generate
        for (lane_g = 0; lane_g < LANES; lane_g = lane_g + 1) begin : g_read
            wire [ADDR_W-1:0] a_re_addr;
            wire [ADDR_W-1:0] a_im_addr;
            wire [ADDR_W-1:0] b_re_addr;
            wire [ADDR_W-1:0] b_im_addr;

            assign a_re_addr = a_re_addr_vec[lane_g*ADDR_W +: ADDR_W];
            assign a_im_addr = a_im_addr_vec[lane_g*ADDR_W +: ADDR_W];
            assign b_re_addr = b_re_addr_vec[lane_g*ADDR_W +: ADDR_W];
            assign b_im_addr = b_im_addr_vec[lane_g*ADDR_W +: ADDR_W];

            assign va_re_vec[lane_g*64 +: 64] =
                read_lane_mask[lane_g] ? (read_bank ? bank1[a_re_addr] : bank0[a_re_addr]) : 64'd0;
            assign va_im_vec[lane_g*64 +: 64] =
                read_lane_mask[lane_g] ? (read_bank ? bank1[a_im_addr] : bank0[a_im_addr]) : 64'd0;
            assign vb_re_vec[lane_g*64 +: 64] =
                read_lane_mask[lane_g] ? (read_bank ? bank1[b_re_addr] : bank0[b_re_addr]) : 64'd0;
            assign vb_im_vec[lane_g*64 +: 64] =
                read_lane_mask[lane_g] ? (read_bank ? bank1[b_im_addr] : bank0[b_im_addr]) : 64'd0;
        end
    endgenerate

    integer lane_i;
    always @(posedge clk) begin
        if (ext_we) begin
            if (ext_bank) begin
                bank1[ext_addr] <= ext_re_i;
            end else begin
                bank0[ext_addr] <= ext_re_i;
            end
        end

        if (write_en) begin
            for (lane_i = 0; lane_i < LANES; lane_i = lane_i + 1) begin
                if (write_lane_mask[lane_i]) begin
                    if (write_bank) begin
                        bank1[y0_re_addr_vec[lane_i*ADDR_W +: ADDR_W]] <= y0_re_vec[lane_i*64 +: 64];
                        bank1[y0_im_addr_vec[lane_i*ADDR_W +: ADDR_W]] <= y0_im_vec[lane_i*64 +: 64];
                        bank1[y1_re_addr_vec[lane_i*ADDR_W +: ADDR_W]] <= y1_re_vec[lane_i*64 +: 64];
                        bank1[y1_im_addr_vec[lane_i*ADDR_W +: ADDR_W]] <= y1_im_vec[lane_i*64 +: 64];
                    end else begin
                        bank0[y0_re_addr_vec[lane_i*ADDR_W +: ADDR_W]] <= y0_re_vec[lane_i*64 +: 64];
                        bank0[y0_im_addr_vec[lane_i*ADDR_W +: ADDR_W]] <= y0_im_vec[lane_i*64 +: 64];
                        bank0[y1_re_addr_vec[lane_i*ADDR_W +: ADDR_W]] <= y1_re_vec[lane_i*64 +: 64];
                        bank0[y1_im_addr_vec[lane_i*ADDR_W +: ADDR_W]] <= y1_im_vec[lane_i*64 +: 64];
                    end
                end
            end
        end
    end

endmodule
