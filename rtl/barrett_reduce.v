`timescale 1ns/1ps

// Combinational Barrett modular reduction:  result = x mod q
//
// For a WIDTH-bit modulus q, precompute mu = floor(2^(2*WIDTH) / q).
// Barrett computes r = x mod q using two multiplications + correction
// subtractions, replacing expensive division with synthesizable multipliers.
//
// Algorithm (k = WIDTH):
//   Step 1:  q1 = floor(x / 2^(k-1))        — wiring, (WIDTH+1) bits
//   Step 2:  q2 = q1 * mu                    — multiplier
//   Step 3:  q3 = floor(q2 / 2^(k+1))       — wiring (select upper bits)
//   Step 4:  r1 = x - q3 * q                — multiplier + subtractor
//   Step 5-6: r1 >= q ? r1 -= q  (at most 2 corrections)
//
// All combinational — single-cycle latency for drop-in replacement of %
// in the AE pipeline's output stage.
//
// NOTE:  This module is designed for 2*WIDTH-bit dividends (64-bit products
//        in S2 of the AE pipeline).  S0 input reduction uses a separate
//        lightweight path because Barrett with fixed k=WIDTH requires
//        x ~ 2^(2*WIDTH) to stay within the 2-correction guarantee.

module barrett_reduce #(
    parameter WIDTH = 32
) (
    input  wire [(2*WIDTH)-1:0] x,          // dividend (2*WIDTH-bit)
    input  wire [WIDTH-1:0]     q,          // modulus
    input  wire [(2*WIDTH)-1:0] mu,         // precomputed floor(2^(2*WIDTH) / q)
    input  wire                  use_mod,   // enable modular reduction
    output wire [WIDTH-1:0]      result
);

    localparam Q1_W = WIDTH + 1;         // 33  — bits in q1
    localparam Q2_W = Q1_W + (2*WIDTH);  // 97  — bits in q1 * mu
    localparam SH1  = WIDTH - 1;         // 31  — right-shift for q1
    localparam SH2  = WIDTH + 1;         // 33  — right-shift for q3
    localparam Q3_W = Q2_W - SH2;        // 64  — bits in q3

    // ------------------------------------------------------------------
    // Truncation path
    // ------------------------------------------------------------------
    wire [WIDTH-1:0] truncated;
    assign truncated = x[WIDTH-1:0];

    // ------------------------------------------------------------------
    // Barrett path
    // ------------------------------------------------------------------

    // Step 1: q1 = floor(x / 2^(WIDTH-1))   — wiring only
    wire [Q1_W-1:0] q1;
    assign q1 = x[(2*WIDTH)-1 : SH1];

    // Step 2: q2 = q1 * mu
    //   Verilog multiplication width = operand widths summed = Q1_W + 2*WIDTH
    wire [Q2_W-1:0] q2_full;
    assign q2_full = q1 * mu;

    // Step 3: q3 = floor(q2 / 2^(WIDTH+1))  — select upper Q3_W bits of q2
    wire [Q3_W-1:0] q3;
    assign q3 = q2_full[Q2_W-1 : SH2];

    // Step 4: r1 = x - q3 * q
    //   Barrett guarantees q3 <= floor(x/q), so q3 * q <= x < 2^(2*WIDTH).
    //   The lower 2*WIDTH bits of q3*q suffice for the subtraction.
    wire [(2*WIDTH)-1:0] prod_lo;
    wire [(2*WIDTH):0]   r1_full;
    wire [(2*WIDTH)-1:0] r1;

    assign prod_lo = q3 * q;                // truncated to lower 2*WIDTH bits
    assign r1_full = {1'b0, x} - {1'b0, prod_lo};
    assign r1      = r1_full[(2*WIDTH)-1:0];

    // Step 5-6: at most 2 conditional subtractions
    wire [(2*WIDTH)-1:0] q_ext;
    assign q_ext = {{WIDTH{1'b0}}, q};

    wire                r1_ge_q = (r1 >= q_ext);
    wire [(2*WIDTH)-1:0] r2     = r1_ge_q ? (r1 - q_ext) : r1;

    wire                r2_ge_q = (r2 >= q_ext);
    wire [(2*WIDTH)-1:0] r3     = r2_ge_q ? (r2 - q_ext) : r2;

    // ------------------------------------------------------------------
    // Output mux
    // ------------------------------------------------------------------
    wire q_is_zero;
    assign q_is_zero = (q == {WIDTH{1'b0}});

    assign result = (!use_mod || q_is_zero) ? truncated : r3[WIDTH-1:0];

endmodule
