`timescale 1ns/1ps

module reconfig_ae #(
    parameter WORD_W = 32,
    parameter MODE_W = 3
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  valid_in,
    input  wire [MODE_W-1:0]     mode,
    input  wire                  use_mod,
    input  wire [WORD_W-1:0]     modulus,
    input  wire [(2*WORD_W)-1:0] mu,        // Barrett constant = floor(2^(2k) / modulus)
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

    localparam [MODE_W-1:0] AE_MODE_CT_BFU  = 3'd0;
    localparam [MODE_W-1:0] AE_MODE_GS_BFU  = 3'd1;
    localparam [MODE_W-1:0] AE_MODE_MUL_ADD = 3'd2;
    localparam [MODE_W-1:0] AE_MODE_ADD_MUL = 3'd3;
    localparam [MODE_W-1:0] AE_MODE_ADD_SUB = 3'd4;
    localparam [MODE_W-1:0] AE_MODE_BIG_MUL = 3'd5;
    localparam [MODE_W-1:0] AE_MODE_MUL_ACC = 3'd6;
    localparam [MODE_W-1:0] AE_MODE_ACC_RD  = 3'd7;   // read accumulator to y0,y1

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
            pre_a_s1    <= pre_a_s0;
            pre_b_s1    <= pre_b_s0;
            pre_c_s1    <= pre_c_s0;
            pre_w_s1    <= pre_w_s0;
            add_ab_s1   <= add_ab_s0;
            sub_ab_s1   <= sub_ab_s0;
            mul_main_s1 <= pre_a_s0 * pre_b_s0;
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
    reg [WORD_W-1:0]     pre_c_s2;
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
            pre_a_s2    <= {WORD_W{1'b0}};
            pre_c_s2    <= {WORD_W{1'b0}};
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
            pre_a_s2    <= pre_a_s1;
            pre_c_s2    <= pre_c_s1;
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
                default: begin
                    y0 <= {WORD_W{1'b0}};
                    y1 <= {WORD_W{1'b0}};
                end
            endcase
            end
        end
    end

endmodule
