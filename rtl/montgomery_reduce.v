`timescale 1ns/1ps

// Montgomery modular reduction:  result = T * R^{-1} mod q
//
// Implements the classic Montgomery reduction for PQC schemes
// (CRYSTALS-Kyber, CRYSTALS-Dilithium) that represent field elements
// in Montgomery form.  When combined with a preceding multiply, this
// yields a full Montgomery modular multiplication.
//
// Algorithm (from Montgomery, "Modular Multiplication Without Trial
// Division", Math. Comp. 1985):
//   Given T in [0, q*R-1], q odd, R = 2^WORD_W, q_inv = -q^{-1} mod R:
//     1. m  = T * q_inv  (mod R)       → lower WORD_W bits
//     2. t  = (T + m * q) >> WORD_W    → upper bits after carry
//     3. if t >= q:  result = t - q
//        else:        result = t
//
// The output satisfies  result ≡ T * R^{-1} (mod q),  0 ≤ result < q.
//
// For full Montgomery multiplication:  a * b mod q
//   1. T = a * b                       (standard multiply, 2*WORD_W bits)
//   2. result = mont_reduce(T)         (this module)
// This replaces Barrett reduction when inputs are in Montgomery form.
//
// Parameters:
//   WIDTH  — operand width (typically 32).  R = 2^WIDTH.
//   q      — modulus (must be odd for Montgomery to work)
//   q_inv  — precomputed Montgomery constant = -q^{-1} mod 2^WIDTH
//   use_mod — enable modular reduction (when 0, returns truncated T)

module montgomery_reduce #(
    parameter WIDTH = 32
) (
    input  wire [(2*WIDTH)-1:0] T,          // value to reduce (2*WIDTH-bit)
    input  wire [WIDTH-1:0]     q,          // modulus (must be odd)
    input  wire [WIDTH-1:0]     q_inv,      // -q^{-1} mod 2^WIDTH
    input  wire                  use_mod,   // enable modular reduction
    output wire [WIDTH-1:0]      result
);

    // ------------------------------------------------------------------
    // Montgomery reduction path
    // ------------------------------------------------------------------

    // Step 1: m = T[WIDTH-1:0] * q_inv  → take lower WIDTH bits
    // Since we only need m mod 2^WIDTH, we only multiply the lower halves
    wire [(2*WIDTH)-1:0] m_full;
    assign m_full = T[WIDTH-1:0] * q_inv;
    wire [WIDTH-1:0]    m;
    assign m = m_full[WIDTH-1:0];

    // Step 2: t_full = T + m * q
    // m is WIDTH bits, q is WIDTH bits → m*q is 2*WIDTH bits
    // T is 2*WIDTH bits → t_full can be 2*WIDTH+1 bits (carry)
    wire [(2*WIDTH)-1:0] mq;
    assign mq = m * q;

    wire [(2*WIDTH):0]   t_full;
    assign t_full = {1'b0, T} + {1'b0, mq};

    // t = t_full >> WIDTH   (upper WIDTH+1 bits → take WIDTH bits)
    wire [WIDTH:0] t_wide;
    assign t_wide = t_full[(2*WIDTH):WIDTH];   // bits [2*WIDTH : WIDTH]

    // Step 3: Conditional subtraction  if t >= q then t - q else t
    wire t_ge_q;
    assign t_ge_q = (t_wide >= {1'b0, q});

    wire [WIDTH:0] t_sub;
    assign t_sub = t_wide - {1'b0, q};

    wire [WIDTH-1:0] mont_result;
    assign mont_result = t_ge_q ? t_sub[WIDTH-1:0] : t_wide[WIDTH-1:0];

    // ------------------------------------------------------------------
    // Truncation path (no modular reduction)
    // ------------------------------------------------------------------
    wire [WIDTH-1:0] truncated;
    assign truncated = T[WIDTH-1:0];

    // ------------------------------------------------------------------
    // Output mux
    // ------------------------------------------------------------------
    wire q_is_zero;
    assign q_is_zero = (q == {WIDTH{1'b0}});

    assign result = (!use_mod || q_is_zero) ? truncated : mont_result;

endmodule
