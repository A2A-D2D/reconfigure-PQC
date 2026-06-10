`timescale 1ns/1ps

// AE Lane with local Register File (P3).
//
// Wraps a single reconfig_ae + ae_regfile with input muxing so that
// operands a, b can be sourced from either the local register file
// (rf_rdata_a / rf_rdata_b) or from external ports (ext_a / ext_b).
// Operands c, w always come from external ports (typically twiddle factors
// shared across lanes).
//
// Write-back:  when valid_out is asserted, the AE output (y0 or y1,
// selected by rf_wsel) can be written to the register file at rf_waddr
// if rf_we is high.  This allows results to be captured for the next
// NTT stage without going through external memory.
//
// Register file:  DEPTH entries x WORD_W bits, 2-read 1-write.

module reconfig_ae_rf #(
    parameter WORD_W = 32,
    parameter MODE_W = 4,
    parameter DEPTH  = 8,
    parameter ADDR_W = 3
) (
    input  wire                  clk,
    input  wire                  rst_n,

    // --- AE control (same as reconfig_ae) ---
    input  wire                  valid_in,
    input  wire [MODE_W-1:0]     mode,
    input  wire                  use_mod,
    input  wire [WORD_W-1:0]     modulus,
    input  wire [(2*WORD_W)-1:0] mu,
    input  wire [WORD_W-1:0]     mu_mont,   // Montgomery constant
    input  wire [4:0]            k_log2,

    // --- External operand ports (c, w always from here) ---
    input  wire [WORD_W-1:0]     ext_a,
    input  wire [WORD_W-1:0]     ext_b,
    input  wire [WORD_W-1:0]     ext_c,
    input  wire [WORD_W-1:0]     ext_w,

    // --- Register file read control ---
    input  wire [ADDR_W-1:0]     rf_raddr_a,
    input  wire [ADDR_W-1:0]     rf_raddr_b,
    input  wire                  use_rf_a,       // 1 = use rf_rdata_a for a
    input  wire                  use_rf_b,       // 1 = use rf_rdata_b for b

    // --- Register file write control ---
    input  wire [ADDR_W-1:0]     rf_waddr,
    input  wire                  rf_we,          // write enable
    input  wire                  rf_wsel,        // 0 = write y0, 1 = write y1

    // --- AE outputs ---
    output wire                  valid_out,
    output wire [WORD_W-1:0]     y0,
    output wire [WORD_W-1:0]     y1,

    // --- P4 accumulator ---
    input  wire                  acc_clr,
    output wire [(2*WORD_W)-1:0] acc_out,

    // --- Register file read data (debug / external access) ---
    output wire [WORD_W-1:0]     rf_rdata_a,
    output wire [WORD_W-1:0]     rf_rdata_b
);

    // Internal operand wires (muxed)
    wire [WORD_W-1:0] ae_a, ae_b;

    // Register file instance
    ae_regfile #(.WORD_W(WORD_W), .DEPTH(DEPTH), .ADDR_W(ADDR_W)) u_rf (
        .clk      (clk),
        .rst_n    (rst_n),
        .raddr_a  (rf_raddr_a),
        .rdata_a  (rf_rdata_a),
        .raddr_b  (rf_raddr_b),
        .rdata_b  (rf_rdata_b),
        .waddr    (rf_waddr),
        .wdata    (rf_wsel ? y1 : y0),
        .we       (rf_we && valid_out)
    );

    // Input mux: a = RF or external
    assign ae_a = use_rf_a ? rf_rdata_a : ext_a;
    assign ae_b = use_rf_b ? rf_rdata_b : ext_b;

    // AE instance
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .mode      (mode),
        .use_mod   (use_mod),
        .modulus   (modulus),
        .mu        (mu),
        .mu_mont   (mu_mont),
        .k_log2    (k_log2),
        .a         (ae_a),
        .b         (ae_b),
        .c         (ext_c),
        .w         (ext_w),
        .valid_out (valid_out),
        .y0        (y0),
        .y1        (y1),
        .acc_clr   (acc_clr),
        .acc_out   (acc_out)
    );

endmodule
