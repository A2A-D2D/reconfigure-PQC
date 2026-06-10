`timescale 1ns/1ps

module reconfig_ae #(
    parameter WORD_W = 32,
    parameter MODE_W = 4     // expanded to 4 bits → 16 modes for multi-scheme PQC
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  valid_in,
    input  wire [MODE_W-1:0]     mode,
    input  wire                  use_mod,
    input  wire [WORD_W-1:0]     modulus,
    input  wire [(2*WORD_W)-1:0] mu,        // Barrett constant = floor(2^(2k) / modulus)
    input  wire [WORD_W-1:0]     mu_mont,   // Montgomery constant = -q^{-1} mod 2^WORD_W
    input  wire [4:0]            k_log2,    // ceil(log2(modulus)), 1..WORD_W
    input  wire [WORD_W-1:0]     a,
    input  wire [WORD_W-1:0]     b,
    input  wire [WORD_W-1:0]     c,
    input  wire [WORD_W-1:0]     w,
    output reg                   valid_out,
    output reg  [WORD_W-1:0]     y0,
    output reg  [WORD_W-1:0]     y1,

    // P4: 64-bit multiply-accumulate for big-number multiplication
    input  wire                  acc_clr,     // clear accumulator
    output wire [(2*WORD_W)-1:0] acc_out      // accumulator value
);

    // ====================================================================
    // Mode definitions — 16 modes (MODE_W=4)
    //
    // Modes 0-7 : Baseline NTT / polynomial arithmetic (Barrett reduction)
    // Modes 8-15: Extended — Montgomery, lazy reduction, square, etc.
    //
    // Paper reference: reconfigurable AE for multi-scheme PQC (NTT,
    // FFT, polynomial convolution). Different modes map to different
    // algorithmic "personalities": NTT-butterfly, point-wise MAC,
    // big-integer multiply, Montgomery-form arithmetic.
    // ====================================================================
    localparam [MODE_W-1:0] AE_MODE_CT_BFU   = 4'd0;   // CT butterfly:  y0=a+b*w, y1=a-b*w (mod q)
    localparam [MODE_W-1:0] AE_MODE_GS_BFU   = 4'd1;   // GS butterfly:  y0=a+b,   y1=(a-b)*w (mod q)
    localparam [MODE_W-1:0] AE_MODE_MUL_ADD  = 4'd2;   // Mul-add:       y0=a*b+c, y1=a*b     (mod q)
    localparam [MODE_W-1:0] AE_MODE_ADD_MUL  = 4'd3;   // Add-mul:       y0=(a+b)*c, y1=a+b   (mod q)
    localparam [MODE_W-1:0] AE_MODE_ADD_SUB  = 4'd4;   // Add-sub:       y0=a+b,   y1=a-b     (mod q)
    localparam [MODE_W-1:0] AE_MODE_BIG_MUL  = 4'd5;   // Big multiply:  y0=lo(a*b), y1=hi(a*b)
    localparam [MODE_W-1:0] AE_MODE_MUL_ACC  = 4'd6;   // Mul-accumulate: acc += a*b, y0/y1 = a*b
    localparam [MODE_W-1:0] AE_MODE_ACC_RD   = 4'd7;   // Accum read:    y0=acc_lo, y1=acc_hi

    // --- Extended modes (PQC multi-scheme) ---
    localparam [MODE_W-1:0] AE_MODE_MONT_MUL = 4'd8;   // Montgomery mul: y0=Mont(a*b), y1=a*b raw
    localparam [MODE_W-1:0] AE_MODE_MUL_SUB  = 4'd9;   // Mul-sub:        y0=a*b-c,  y1=a*b     (mod q)
    localparam [MODE_W-1:0] AE_MODE_MADD_MSUB= 4'd10;  // Madd-msub:      y0=a*b+c,  y1=a*b-c   (mod q)
    localparam [MODE_W-1:0] AE_MODE_MACC_W   = 4'd11;  // Macc-w:         y0=a*b+w,  y1=a*b     (mod q)
    localparam [MODE_W-1:0] AE_MODE_SQUARE   = 4'd12;  // Square:         y0=a²,     y1=a*b     (mod q)
    localparam [MODE_W-1:0] AE_MODE_CT_LAZY  = 4'd13;  // CT lazy:        y0=a+b*w,  y1=a-b*w   (no mod)
    localparam [MODE_W-1:0] AE_MODE_COND_RED = 4'd14;  // Cond reduction: y0=red(a), y1=red(b)
    localparam [MODE_W-1:0] AE_MODE_PASSTHRU = 4'd15;  // Passthrough:    y0=a,      y1=b

    // --------------------------------------------------------------------
    // Stage 0 registers
    // --------------------------------------------------------------------
    reg [MODE_W-1:0] mode_s0;
    reg [MODE_W-1:0] mode_s1;
    reg [MODE_W-1:0] mode_s2;
    reg              use_mod_s0;
    reg              use_mod_s1;
    reg              use_mod_s2;
    reg [WORD_W-1:0] modulus_s0;
    reg [WORD_W-1:0] modulus_s1;
    reg [WORD_W-1:0] modulus_s2;
    reg [(2*WORD_W)-1:0] mu_s0;
    reg [(2*WORD_W)-1:0] mu_s1;
    reg [(2*WORD_W)-1:0] mu_s2;
    reg [WORD_W-1:0]     mu_mont_s0;   // Montgomery constant pipeline
    reg [WORD_W-1:0]     mu_mont_s1;
    reg [WORD_W-1:0]     mu_mont_s2;
    reg [4:0]            k_log2_s0;
    reg [4:0]            k_log2_s1;
    reg [4:0]            k_log2_s2;
    reg              valid_s0;
    reg              valid_s1;
    reg              valid_s2;

    //
    // S0: Pre-Add / Input Reduction
    //
    // Input values are assumed to be field elements already in [0, q).
    // We use a lightweight boundary reduction (1 conditional subtraction):
    //   if (val >= q) val - q  else val
    // This is valid for val < 2*q, which holds for properly reduced inputs
    // and for sums of two reduced values (< 2*q).
    //
    reg [WORD_W-1:0] pre_a_s0;
    reg [WORD_W-1:0] pre_b_s0;
    reg [WORD_W-1:0] pre_c_s0;
    reg [WORD_W-1:0] pre_w_s0;
    reg [WORD_W-1:0] add_ab_s0;
    reg [WORD_W-1:0] sub_ab_s0;

    // Lightweight S0 reduction:  val mod q
    // Uses 3 conditional subtractions to cover val < 4*q (robust for
    // inputs that are up to ~4x the modulus, which handles typical PQC
    // coefficient ranges even before strict external pre-reduction).
    function [WORD_W-1:0] reduce_s0;
        input [WORD_W-1:0] val;
        input [WORD_W-1:0] mod_val;
        input              en;
        reg [WORD_W-1:0]   tmp;
        begin
            if ((en == 1'b1) && (mod_val != {WORD_W{1'b0}})) begin
                tmp = val;
                if (tmp >= mod_val) tmp = tmp - mod_val;
                if (tmp >= mod_val) tmp = tmp - mod_val;
                if (tmp >= mod_val) tmp = tmp - mod_val;
                reduce_s0 = tmp;
            end else begin
                reduce_s0 = val;
            end
        end
    endfunction

    // Modular add via S0 reduction:  (lhs + rhs) mod q
    function [WORD_W-1:0] add_mod_s0;
        input [WORD_W-1:0] lhs;
        input [WORD_W-1:0] rhs;
        input [WORD_W-1:0] mod_val;
        input              en;
        reg [WORD_W:0]     sum_ext;
        begin
            sum_ext = {1'b0, lhs} + {1'b0, rhs};
            add_mod_s0 = reduce_s0(sum_ext[WORD_W-1:0], mod_val, en);
        end
    endfunction

    // Modular sub via S0 reduction:  (lhs - rhs) mod q
    function [WORD_W-1:0] sub_mod_s0;
        input [WORD_W-1:0] lhs;
        input [WORD_W-1:0] rhs;
        input [WORD_W-1:0] mod_val;
        input              en;
        begin
            if ((en == 1'b1) && (mod_val != {WORD_W{1'b0}})) begin
                if (lhs >= rhs) begin
                    sub_mod_s0 = lhs - rhs;
                end else begin
                    sub_mod_s0 = reduce_s0(lhs + mod_val - rhs, mod_val, 1'b1);
                end
            end else begin
                sub_mod_s0 = lhs - rhs;
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            valid_s0   <= 1'b0;
            mode_s0    <= {MODE_W{1'b0}};
            use_mod_s0 <= 1'b0;
            modulus_s0 <= {WORD_W{1'b0}};
            mu_s0      <= {(2*WORD_W){1'b0}};
            mu_mont_s0 <= {WORD_W{1'b0}};
            k_log2_s0  <= 5'd0;
            pre_a_s0   <= {WORD_W{1'b0}};
            pre_b_s0   <= {WORD_W{1'b0}};
            pre_c_s0   <= {WORD_W{1'b0}};
            pre_w_s0   <= {WORD_W{1'b0}};
            add_ab_s0  <= {WORD_W{1'b0}};
            sub_ab_s0  <= {WORD_W{1'b0}};
        end else begin
            valid_s0   <= valid_in;
            mode_s0    <= mode;
            use_mod_s0 <= use_mod;
            modulus_s0 <= modulus;
            mu_s0      <= mu;
            mu_mont_s0 <= mu_mont;
            k_log2_s0  <= k_log2;
            pre_a_s0   <= reduce_s0(a, modulus, use_mod);
            pre_b_s0   <= reduce_s0(b, modulus, use_mod);
            pre_c_s0   <= reduce_s0(c, modulus, use_mod);
            pre_w_s0   <= reduce_s0(w, modulus, use_mod);
            add_ab_s0  <= add_mod_s0(reduce_s0(a, modulus, use_mod), reduce_s0(b, modulus, use_mod), modulus, use_mod);
            sub_ab_s0  <= sub_mod_s0(reduce_s0(a, modulus, use_mod), reduce_s0(b, modulus, use_mod), modulus, use_mod);
        end
    end

    // --------------------------------------------------------------------
    // Stage 1 registers: Multiplication
    // --------------------------------------------------------------------
    reg [WORD_W-1:0]    pre_a_s1;
    reg [WORD_W-1:0]    pre_b_s1;
    reg [WORD_W-1:0]    pre_c_s1;
    reg [WORD_W-1:0]    pre_w_s1;
    reg [WORD_W-1:0]    add_ab_s1;
    reg [WORD_W-1:0]    sub_ab_s1;
    reg [(2*WORD_W)-1:0] mul_main_s1;
    reg [(2*WORD_W)-1:0] mul_btw_s1;
    reg [(2*WORD_W)-1:0] mul_addc_s1;
    reg [(2*WORD_W)-1:0] mul_subw_s1;

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            valid_s1    <= 1'b0;
            mode_s1     <= {MODE_W{1'b0}};
            use_mod_s1  <= 1'b0;
            modulus_s1  <= {WORD_W{1'b0}};
            mu_s1       <= {(2*WORD_W){1'b0}};
            k_log2_s1   <= 5'd0;
            mu_mont_s1  <= {WORD_W{1'b0}};
            pre_a_s1    <= {WORD_W{1'b0}};
            pre_b_s1    <= {WORD_W{1'b0}};
            pre_c_s1    <= {WORD_W{1'b0}};
            pre_w_s1    <= {WORD_W{1'b0}};
            add_ab_s1   <= {WORD_W{1'b0}};
            sub_ab_s1   <= {WORD_W{1'b0}};
            mul_main_s1 <= {(2*WORD_W){1'b0}};
            mul_btw_s1  <= {(2*WORD_W){1'b0}};
            mul_addc_s1 <= {(2*WORD_W){1'b0}};
            mul_subw_s1 <= {(2*WORD_W){1'b0}};
        end else begin
            valid_s1    <= valid_s0;
            mode_s1     <= mode_s0;
            use_mod_s1  <= use_mod_s0;
            modulus_s1  <= modulus_s0;
            mu_s1       <= mu_s0;
            k_log2_s1   <= k_log2_s0;
            mu_mont_s1  <= mu_mont_s0;
            pre_a_s1    <= pre_a_s0;
            pre_b_s1    <= pre_b_s0;
            pre_c_s1    <= pre_c_s0;
            pre_w_s1    <= pre_w_s0;
            add_ab_s1   <= add_ab_s0;
            sub_ab_s1   <= sub_ab_s0;
            // SQUARE mode: route a to both multiplier inputs → a*a
            // Normal mode:  a * b
            mul_main_s1 <= (mode_s0 == AE_MODE_SQUARE)
                           ? (pre_a_s0 * pre_a_s0)
                           : (pre_a_s0 * pre_b_s0);
            mul_btw_s1  <= pre_b_s0 * pre_w_s0;
            mul_addc_s1 <= add_ab_s0 * pre_c_s0;
            mul_subw_s1 <= sub_ab_s0 * pre_w_s0;
        end
    end

    // --------------------------------------------------------------------
    // Stage 2 registers: Post-Add / Barrett Reduction
    //
    // Barrett reduction (combinational) computes r = x mod q for the
    // 64-bit multiplication products using two multipliers + correction.
    // This replaces the original "%" operator with synthesizable hardware.
    // --------------------------------------------------------------------
    reg [WORD_W-1:0]     pre_a_s2;
    reg [WORD_W-1:0]     pre_b_s2;
    reg [WORD_W-1:0]     pre_c_s2;
    reg [WORD_W-1:0]     pre_w_s2;
    reg [WORD_W-1:0]     add_ab_s2;
    reg [WORD_W-1:0]     sub_ab_s2;
    reg [(2*WORD_W)-1:0] mul_main_s2;
    reg [(2*WORD_W)-1:0] mul_btw_s2;
    reg [(2*WORD_W)-1:0] mul_addc_s2;
    reg [(2*WORD_W)-1:0] mul_subw_s2;

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            valid_s2    <= 1'b0;
            mode_s2     <= {MODE_W{1'b0}};
            use_mod_s2  <= 1'b0;
            modulus_s2  <= {WORD_W{1'b0}};
            mu_s2       <= {(2*WORD_W){1'b0}};
            k_log2_s2   <= 5'd0;
            mu_mont_s2  <= {WORD_W{1'b0}};
            pre_a_s2    <= {WORD_W{1'b0}};
            pre_b_s2    <= {WORD_W{1'b0}};
            pre_c_s2    <= {WORD_W{1'b0}};
            pre_w_s2    <= {WORD_W{1'b0}};
            add_ab_s2   <= {WORD_W{1'b0}};
            sub_ab_s2   <= {WORD_W{1'b0}};
            mul_main_s2 <= {(2*WORD_W){1'b0}};
            mul_btw_s2  <= {(2*WORD_W){1'b0}};
            mul_addc_s2 <= {(2*WORD_W){1'b0}};
            mul_subw_s2 <= {(2*WORD_W){1'b0}};
        end else begin
            valid_s2    <= valid_s1;
            mode_s2     <= mode_s1;
            use_mod_s2  <= use_mod_s1;
            modulus_s2  <= modulus_s1;
            mu_s2       <= mu_s1;
            k_log2_s2   <= k_log2_s1;
            mu_mont_s2  <= mu_mont_s1;
            pre_a_s2    <= pre_a_s1;
            pre_b_s2    <= pre_b_s1;
            pre_c_s2    <= pre_c_s1;
            pre_w_s2    <= pre_w_s1;
            add_ab_s2   <= add_ab_s1;
            sub_ab_s2   <= sub_ab_s1;
            mul_main_s2 <= mul_main_s1;
            mul_btw_s2  <= mul_btw_s1;
            mul_addc_s2 <= mul_addc_s1;
            mul_subw_s2 <= mul_subw_s1;
        end
    end

    // --- Barrett reduction instances for the four 64-bit products ---

    wire [WORD_W-1:0] mod_mul_main;
    wire [WORD_W-1:0] mod_mul_btw;
    wire [WORD_W-1:0] mod_mul_addc;
    wire [WORD_W-1:0] mod_mul_subw;

    barrett_reduce #(.WIDTH(WORD_W)) u_barrett_main (
        .x       (mul_main_s2),
        .q       (modulus_s2),
        .mu      (mu_s2),
        .k_log2  (k_log2_s2),
        .use_mod (use_mod_s2),
        .result  (mod_mul_main)
    );

    barrett_reduce #(.WIDTH(WORD_W)) u_barrett_btw (
        .x       (mul_btw_s2),
        .q       (modulus_s2),
        .mu      (mu_s2),
        .k_log2  (k_log2_s2),
        .use_mod (use_mod_s2),
        .result  (mod_mul_btw)
    );

    barrett_reduce #(.WIDTH(WORD_W)) u_barrett_addc (
        .x       (mul_addc_s2),
        .q       (modulus_s2),
        .mu      (mu_s2),
        .k_log2  (k_log2_s2),
        .use_mod (use_mod_s2),
        .result  (mod_mul_addc)
    );

    barrett_reduce #(.WIDTH(WORD_W)) u_barrett_subw (
        .x       (mul_subw_s2),
        .q       (modulus_s2),
        .mu      (mu_s2),
        .k_log2  (k_log2_s2),
        .use_mod (use_mod_s2),
        .result  (mod_mul_subw)
    );

    // --- Montgomery reduction instance for mul_main (MONT_MUL mode) ---
    wire [WORD_W-1:0] mont_mul_main;

    montgomery_reduce #(.WIDTH(WORD_W)) u_mont_main (
        .T       (mul_main_s2),
        .q       (modulus_s2),
        .q_inv   (mu_mont_s2),
        .use_mod (use_mod_s2),
        .result  (mont_mul_main)
    );

    // S2-level modular add/sub (for final output combination)
    // These use the same lightweight reduction since operands are < 2*q
    function [WORD_W-1:0] add_mod_s2;
        input [WORD_W-1:0] lhs;
        input [WORD_W-1:0] rhs;
        input [WORD_W-1:0] mod_val;
        input              en;
        reg [WORD_W:0]     sum_ext;
        begin
            sum_ext = {1'b0, lhs} + {1'b0, rhs};
            add_mod_s2 = reduce_s0(sum_ext[WORD_W-1:0], mod_val, en);
        end
    endfunction

    function [WORD_W-1:0] sub_mod_s2;
        input [WORD_W-1:0] lhs;
        input [WORD_W-1:0] rhs;
        input [WORD_W-1:0] mod_val;
        input              en;
        begin
            if ((en == 1'b1) && (mod_val != {WORD_W{1'b0}})) begin
                if (lhs >= rhs) begin
                    sub_mod_s2 = lhs - rhs;
                end else begin
                    sub_mod_s2 = reduce_s0(lhs + mod_val - rhs, mod_val, 1'b1);
                end
            end else begin
                sub_mod_s2 = lhs - rhs;
            end
        end
    endfunction

    // --------------------------------------------------------------------
    // P4: 64-bit Multiply-Accumulate register
    //
    // MUL_ACC mode (6): y0/y1 = a*b, then acc = acc + {y1,y0}  (or
    //   acc = {y1,y0} if acc_clr is asserted alongside valid_in).
    // ACC_RD mode (7):  y0 = acc[31:0], y1 = acc[63:32]  (read-only).
    // acc_out provides combinational read access for lane chaining.
    // --------------------------------------------------------------------
    reg [(2*WORD_W)-1:0] acc_reg;

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            acc_reg <= {(2*WORD_W){1'b0}};
        end else if (valid_s2) begin
            if (mode_s2 == AE_MODE_MUL_ACC) begin
                if (acc_clr)
                    acc_reg <= mul_main_s2;
                else
                    acc_reg <= acc_reg + mul_main_s2;
            end
        end
    end

    assign acc_out = acc_reg;

    // --------------------------------------------------------------------
    // Output stage: mode-dependent result selection
    // --------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            valid_out <= 1'b0;
            y0        <= {WORD_W{1'b0}};
            y1        <= {WORD_W{1'b0}};
        end else begin
            valid_out <= valid_s2;
            if (valid_s2) begin
            case (mode_s2)
                // ============================================================
                // Baseline modes (0-7): Barrett-based NTT / polynomial ops
                // ============================================================
                AE_MODE_CT_BFU: begin
                    y0 <= add_mod_s2(pre_a_s2, mod_mul_btw, modulus_s2, use_mod_s2);
                    y1 <= sub_mod_s2(pre_a_s2, mod_mul_btw, modulus_s2, use_mod_s2);
                end
                AE_MODE_GS_BFU: begin
                    y0 <= add_ab_s2;
                    y1 <= mod_mul_subw;
                end
                AE_MODE_MUL_ADD: begin
                    y0 <= add_mod_s2(mod_mul_main, pre_c_s2, modulus_s2, use_mod_s2);
                    y1 <= mod_mul_main;
                end
                AE_MODE_ADD_MUL: begin
                    y0 <= mod_mul_addc;
                    y1 <= add_ab_s2;
                end
                AE_MODE_ADD_SUB: begin
                    y0 <= add_ab_s2;
                    y1 <= sub_ab_s2;
                end
                AE_MODE_BIG_MUL: begin
                    y0 <= mul_main_s2[WORD_W-1:0];
                    y1 <= mul_main_s2[(2*WORD_W)-1:WORD_W];
                end
                AE_MODE_MUL_ACC: begin
                    y0 <= mul_main_s2[WORD_W-1:0];
                    y1 <= mul_main_s2[(2*WORD_W)-1:WORD_W];
                end
                AE_MODE_ACC_RD: begin
                    y0 <= acc_reg[WORD_W-1:0];
                    y1 <= acc_reg[(2*WORD_W)-1:WORD_W];
                end

                // ============================================================
                // Extended modes (8-15): Montgomery, dual-path, lazy, etc.
                // ============================================================
                AE_MODE_MONT_MUL: begin
                    // Montgomery modular multiplication for Kyber/Dilithium
                    // y0 = a*b * R^{-1} mod q  (Montgomery form)
                    // y1 = a*b raw 64-bit (for chaining / debugging)
                    y0 <= mont_mul_main;
                    y1 <= mul_main_s2[WORD_W-1:0];
                end
                AE_MODE_MUL_SUB: begin
                    // y0 = a*b - c mod q  (subtract variant of MUL_ADD)
                    // y1 = a*b mod q
                    y0 <= sub_mod_s2(mod_mul_main, pre_c_s2, modulus_s2, use_mod_s2);
                    y1 <= mod_mul_main;
                end
                AE_MODE_MADD_MSUB: begin
                    // Dual-path: y0 = a*b + c, y1 = a*b - c (both mod q)
                    // Useful for symmetric polynomial evaluation
                    y0 <= add_mod_s2(mod_mul_main, pre_c_s2, modulus_s2, use_mod_s2);
                    y1 <= sub_mod_s2(mod_mul_main, pre_c_s2, modulus_s2, use_mod_s2);
                end
                AE_MODE_MACC_W: begin
                    // y0 = a*b + w mod q  (like MUL_ADD but uses w operand)
                    // y1 = a*b mod q
                    y0 <= add_mod_s2(mod_mul_main, pre_w_s2, modulus_s2, use_mod_s2);
                    y1 <= mod_mul_main;
                end
                AE_MODE_SQUARE: begin
                    // y0 = a² mod q  (square: mul_main = a*a in S1)
                    // y1 = b*w mod q  (set w=a at input to get a*b)
                    y0 <= mod_mul_main;   // mul_main_s2 already = a*a in this mode
                    y1 <= mod_mul_btw;    // b*w → b*a when w=a
                end
                AE_MODE_CT_LAZY: begin
                    // Lazy CT butterfly — no modular reduction on outputs.
                    // Used in lazy-reduction NTT strategies where intermediate
                    // values can grow and reduction is deferred to later stages.
                    // Caveat: outputs may exceed q; caller must bound growth.
                    y0 <= pre_a_s2 + mul_btw_s2[WORD_W-1:0];
                    y1 <= pre_a_s2 - mul_btw_s2[WORD_W-1:0];
                end
                AE_MODE_COND_RED: begin
                    // Conditional coefficient reduction pass.
                    // Each output = input reduced mod q (3 subtractions at S0
                    // are sufficient for inputs < 4*q).
                    y0 <= pre_a_s2;
                    y1 <= pre_b_s2;
                end
                AE_MODE_PASSTHRU: begin
                    // Raw data passthrough — no arithmetic, no reduction.
                    // Useful for data movement, register file load/store,
                    // and debug visibility into pipeline contents.
                    y0 <= pre_a_s2;
                    y1 <= pre_b_s2;
                end
                default: begin
                    y0 <= {WORD_W{1'b0}};
                    y1 <= {WORD_W{1'b0}};
                end
            endcase
            end
        end
    end

endmodule
