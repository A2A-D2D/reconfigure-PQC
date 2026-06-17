`timescale 1ns/1ps

// Adaptive Barrett modular reduction:  result = x mod q
//
// Uses Barrett reduction with k = ceil(log2(q)) instead of fixed WIDTH.
// This guarantees the standard Barrett bound (≤ 2 corrections) for all q.
//
// Inputs:
//   x       — dividend (2*WIDTH-bit, typically a product of two WIDTH-bit values)
//   q       — modulus
//   mu      — precomputed floor(2^(2k) / q), where k = ceil(log2(q))
//   k_log2  — ceil(log2(q)), 1..WIDTH
//   use_mod — enable modular reduction
//
// Hardware:  fixed 66-bit × 66-bit multiplier path (sized for WIDTH=32 worst case)
//            with variable shifts controlled by k_log2.

module barrett_reduce #(
    parameter WIDTH = 32
) (
    input  wire [(2*WIDTH)-1:0] x,          // dividend
    input  wire [WIDTH-1:0]     q,          // modulus
    input  wire [(2*WIDTH)-1:0] mu,         // floor(2^(2k) / q), k = ceil(log2(q))
    input  wire [4:0]           k_log2,     // ceil(log2(q)), 1..WIDTH
    input  wire                  use_mod,   // enable modular reduction
    output wire [WIDTH-1:0]      result
);

    // ------------------------------------------------------------------
    // Truncation path (no modular reduction)
    // ------------------------------------------------------------------
    wire [WIDTH-1:0] truncated;
    assign truncated = x[WIDTH-1:0];

    // ------------------------------------------------------------------
    // Barrett path with adaptive k
    //
    // q1 = floor(x / 2^(k-1))           — upper bits of x
    // q2 = q1 * mu                       — product
    // q3 = floor(q2 / 2^(k+1))          — approximate quotient
    // r1 = x - q3 * q                   — remainder estimate
    // corrections: while r1 >= q, r1 -= q (≤ 2 iterations by Barrett bound)
    // ------------------------------------------------------------------

    // Shift amounts derived from k_log2
    wire [5:0] sh1;    // k-1
    wire [5:0] sh2;    // k+1
    assign sh1 = {1'b0, k_log2} - 6'd1;   // k_log2 - 1
    assign sh2 = {1'b0, k_log2} + 6'd1;   // k_log2 + 1

    // q1 = x >> (k-1)
    // Maximum q1 width: when k=1, q1 = x[63:0] (64-bit)
    // We extract up to 2*WIDTH bits dynamically.
    wire [(2*WIDTH)-1:0] q1_full;
    assign q1_full = x >> sh1;

    // mu is precomputed with the same k.  It fits in ≤ k+1 bits (≤ 33 for WIDTH=32).
    // For the multiply, we use the full q1 width × mu width.
    // Maximum product width: (2*WIDTH) + (WIDTH+1) = 97 bits for WIDTH=32.
    localparam PQ_W = (2*WIDTH) + (WIDTH + 1);   // 97
    wire [PQ_W-1:0] q2_full;
    assign q2_full = q1_full * mu;

    // q3 = q2 >> (k+1)   — approximate quotient
    // q2[PQ_W-1 : sh2]
    wire [(2*WIDTH)-1:0] q3;
    assign q3 = q2_full >> sh2;

    // r1 = x - q3 * q   (only lower 2*WIDTH bits matter)
    wire [(2*WIDTH)-1:0] prod_lo;
    wire [(2*WIDTH):0]   r1_full;
    wire [(2*WIDTH)-1:0] r1;

    assign prod_lo = q3 * q;
    assign r1_full = {1'b0, x} - {1'b0, prod_lo};
    assign r1      = r1_full[(2*WIDTH)-1:0];

    // Correction: ≤ 2 conditional subtractions (Barrett bound for adaptive k)
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
