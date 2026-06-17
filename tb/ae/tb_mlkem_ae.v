`timescale 1ns/1ps

// P5: ML-KEM (FIPS 203) arithmetic verification on reconfig_ae.
//
// Demonstrates that the enhanced 16-mode AE supports all core arithmetic
// operations required by ML-KEM:
//   - CT/GS NTT butterflies (modes 0, 1) with q = 3329, zeta = 17
//   - Point-wise multiply-accumulate (mode 2) for base multiplication
//   - Montgomery modular multiplication (mode 8)
//   - Barrett-based modular ops (modes 2, 4, 9, 10, 12)
//
// ML-KEM parameters (FIPS 203):
//   q = 3329,  n = 256,  zeta = 17 (primitive 256-th root)
//   X^256 + 1 = prod_{i=0..127} (X^2 - zeta^(2i+1))
//   Base multiplication on the 2-degree extensions is the critical path.

module tb_mlkem_ae;

    localparam WORD_W = 32;
    localparam MODE_W = 4;

    // ML-KEM constants
    localparam [WORD_W-1:0] MLKEM_Q    = 32'd3329;
    localparam [WORD_W-1:0] MLKEM_ZETA = 32'd17;     // primitive 256-th root

    // Mode aliases (matching reconfig_ae.v)
    localparam [MODE_W-1:0] M_CT_BFU    = 4'd0;
    localparam [MODE_W-1:0] M_GS_BFU    = 4'd1;
    localparam [MODE_W-1:0] M_MUL_ADD   = 4'd2;
    localparam [MODE_W-1:0] M_ADD_MUL   = 4'd3;
    localparam [MODE_W-1:0] M_ADD_SUB   = 4'd4;
    localparam [MODE_W-1:0] M_BIG_MUL   = 4'd5;
    localparam [MODE_W-1:0] M_MONT_MUL  = 4'd8;
    localparam [MODE_W-1:0] M_MUL_SUB   = 4'd9;
    localparam [MODE_W-1:0] M_MADD_MSUB = 4'd10;
    localparam [MODE_W-1:0] M_MACC_W    = 4'd11;
    localparam [MODE_W-1:0] M_SQUARE    = 4'd12;
    localparam [MODE_W-1:0] M_CT_LAZY   = 4'd13;
    localparam [MODE_W-1:0] M_COND_RED  = 4'd14;

    reg                 clk, rst_n, valid_in;
    reg  [MODE_W-1:0]   mode;
    reg                 use_mod;
    reg  [WORD_W-1:0]   modulus;
    reg  [(2*WORD_W)-1:0] mu;
    reg  [WORD_W-1:0]   mu_mont;
    reg  [4:0]          k_log2;
    reg  [WORD_W-1:0]   a, b, c, w;
    wire                valid_out;
    wire [WORD_W-1:0]   y0, y1;

    integer errors, tests;

    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode(mode), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .mu_mont(mu_mont), .k_log2(k_log2),
        .a(a), .b(b), .c(c), .w(w),
        .valid_out(valid_out), .y0(y0), .y1(y1),
        .acc_clr(1'b0), .acc_out()
    );

    always #5 clk = ~clk;

    // ==================================================================
    // Helper functions for ML-KEM arithmetic
    // ==================================================================

    // ceil(log2(q)) — bit-width for Barrett k
    function [4:0] compute_k;
        input [WORD_W-1:0] q;
        integer i;
        begin
            compute_k = 5'd0;
            for (i = WORD_W-1; i >= 0; i = i - 1)
                if (q[i] && (compute_k == 5'd0)) compute_k = i + 1;
        end
    endfunction

    // Barrett mu = floor(2^(2k) / q)
    function [(2*WORD_W)-1:0] compute_mu;
        input [WORD_W-1:0] q;
        input [4:0]        k;
        reg [95:0] num;
        begin
            if (k > 0 && q > 1) begin
                num = 96'd0; num[2*k] = 1'b1;
                compute_mu = num / q;
            end else
                compute_mu = 64'd0;
        end
    endfunction

    // Montgomery constant: q_inv = -q^{-1} mod 2^WORD_W
    // Satisfies  q * q_inv ≡ -1  (mod 2^WORD_W)
    //
    // Uses Hensel-lifting / Newton iteration for modular inverse mod 2^k.
    // For odd q:  x_{i+1} = x_i * (2 - q * x_i)  mod 2^{2^{i+1}}
    // Starting from x_0 = 1 (works since q is odd), 5 iterations
    // suffice for 32-bit precision (2^1 → 2^2 → 2^4 → 2^8 → 2^16 → 2^32).
    function [WORD_W-1:0] compute_mont_inv;
        input [WORD_W-1:0] q_in;
        reg [63:0] x, prod;
        integer i;
        begin
            x = 64'd1;   // initial: q * 1 ≡ 1 (mod 2^1) since q is odd
            for (i = 0; i < 5; i = i + 1) begin
                // x = x * (2 - q_in * x) mod 2^(2^{i+1})
                prod = q_in * x;                // q * x
                prod = 64'd2 - prod;            // 2 - q*x  (mod 2^64, ok for the mask below)
                x = x * prod;
                // Truncate to current precision: 2^(2^{i+1})
                case (i)
                    0: x = x & 64'h3;           // 2^2 = 4
                    1: x = x & 64'hF;           // 2^4 = 16
                    2: x = x & 64'hFF;          // 2^8 = 256
                    3: x = x & 64'hFFFF;        // 2^16 = 65536
                    4: x = x & 64'hFFFF_FFFF;   // 2^32
                endcase
            end
            // x = q^{-1} mod 2^WORD_W
            // Montgomery constant = (-x) mod 2^WORD_W
            compute_mont_inv = ({32'd1, 32'd0} - x);   // 2^32 - x
        end
    endfunction

    // Reference modular reduction (simulation-only, uses %)
    function [WORD_W-1:0] ref_mod;
        input [63:0] v;
        input [WORD_W-1:0] qq;
        input en;
        begin
            ref_mod = (en && qq != 0) ? (v % qq) : v[WORD_W-1:0];
        end
    endfunction

    function [WORD_W-1:0] ref_add;
        input [WORD_W-1:0] lhs, rhs, qq;
        input en;
        begin
            ref_add = ref_mod({32'd0, ({1'b0,lhs} + {1'b0,rhs})}, qq, en);
        end
    endfunction

    function [WORD_W-1:0] ref_sub;
        input [WORD_W-1:0] lhs, rhs, qq;
        input en;
        begin
            if (en && qq != 0)
                ref_sub = (lhs >= rhs) ? (lhs - rhs) : ref_mod(lhs + qq - rhs, qq, 1'b1);
            else
                ref_sub = lhs - rhs;
        end
    endfunction

    // Reference Montgomery reduction: MontReduce(T) = T * R^{-1} mod q
    // R = 2^WORD_W
    function [WORD_W-1:0] ref_mont;
        input [(2*WORD_W)-1:0] T;
        input [WORD_W-1:0] qq, qinv;
        input en;
        reg [(2*WORD_W)-1:0] m, mq;
        reg [(2*WORD_W):0]   t_full;   // 65-bit to hold carry (match hardware)
        reg [(2*WORD_W):0]   t_wide;
        begin
            if (en && qq != 0) begin
                m      = T[WORD_W-1:0] * qinv;
                m      = m[WORD_W-1:0];            // m mod 2^WORD_W
                mq     = m * qq;
                t_full = {1'b0, T} + {1'b0, mq};   // 65-bit sum
                t_wide = t_full >> WORD_W;          // shift right by WORD_W
                ref_mont = (t_wide >= qq) ? (t_wide - qq) : t_wide[WORD_W-1:0];
            end else begin
                ref_mont = T[WORD_W-1:0];
            end
        end
    endfunction

    // ==================================================================
    // Single test-case runner
    // ==================================================================
    task run_mlkem_case;
        input [MODE_W-1:0] t_mode;
        input [WORD_W-1:0] t_a, t_b, t_c, t_w;
        input [WORD_W-1:0] t_q;
        input              t_use_mod;
        input [WORD_W-1:0] exp_y0;
        input [WORD_W-1:0] exp_y1;
        input string       desc;
        begin
            // Compute Barrett / Montgomery constants
            k_log2  = compute_k(t_q);
            mu      = compute_mu(t_q, k_log2);
            mu_mont = compute_mont_inv(t_q);

            @(posedge clk);
            valid_in <= 1'b1;
            mode     <= t_mode;
            use_mod  <= t_use_mod;
            modulus  <= t_q;
            a <= t_a; b <= t_b; c <= t_c; w <= t_w;
            @(posedge clk);
            valid_in <= 1'b0;
            mode     <= {MODE_W{1'b0}};
            use_mod  <= 1'b0;
            modulus  <= 0;
            a <= 0; b <= 0; c <= 0; w <= 0;
            repeat (3) @(posedge clk);  // wait for 3-stage pipeline
            #1;

            tests = tests + 2;
            if (valid_out !== 1'b1) begin
                $display("FAIL [%0s] valid_out not asserted", desc);
                errors = errors + 2;
            end else begin
                if (y0 !== exp_y0) begin
                    $display("FAIL [%0s] y0=%0d expected=%0d", desc, y0, exp_y0);
                    errors = errors + 1;
                end else
                    $display("PASS [%0s] y0=%0d", desc, y0);

                if (y1 !== exp_y1) begin
                    $display("FAIL [%0s] y1=%0d expected=%0d", desc, y1, exp_y1);
                    errors = errors + 1;
                end else
                    $display("PASS [%0s] y1=%0d", desc, y1);
            end
        end
    endtask

    // ==================================================================
    // Test sequence
    // ==================================================================
    initial begin
        clk = 1'b0; rst_n = 1'b0; valid_in = 1'b0;
        mode = 0; use_mod = 1'b0; modulus = 0;
        mu = 0; mu_mont = 0; k_log2 = 0;
        a = 0; b = 0; c = 0; w = 0;
        errors = 0; tests = 0;

        repeat(4) @(posedge clk); rst_n = 1'b1; repeat(2) @(posedge clk);

        // ================================================================
        // ML-KEM q = 3329
        // zeta = 17 (primitive 256-th root of unity)
        // ================================================================
        $display("============================================================");
        $display("ML-KEM (FIPS 203) Arithmetic Verification — q = %0d", MLKEM_Q);
        $display("============================================================");

        // --- Test 1: CT Butterfly (Forward NTT) ---
        // ML-KEM forward NTT:  u=a, v=b*zeta^twiddle, a'=u+v, b'=u-v
        // zeta^1 = 17, a=100, b=200:
        //   v = 200 * 17 = 3400 > 3329 → 3400-3329=71 (or %=71)
        //   a' = 100 + 71 = 171 (mod 3329)
        //   b' = 100 - 71 = 29 (mod 3329)
        begin
            reg [31:0] ar, br, vr, exp0, exp1;
            ar = 100 % MLKEM_Q; br = 200 % MLKEM_Q;
            vr = (br * 17) % MLKEM_Q;
            exp0 = (ar + vr) % MLKEM_Q;
            exp1 = (ar >= vr) ? (ar - vr) : (ar + MLKEM_Q - vr) % MLKEM_Q;
            run_mlkem_case(M_CT_BFU, 100, 200, 0, 17, MLKEM_Q, 1'b1, exp0, exp1,
                           "CT_BFU: a=100, b=200, zeta=17");
        end

        // --- Test 2: GS Butterfly (Inverse NTT) ---
        // ML-KEM inverse NTT:  u=a+b, v=(a-b)*zeta_inv, a'=u, b'=v
        // a=100, b=200, w = zeta_inv (= 17^{-1} mod 3329):
        //   17 * 17^{-1} ≡ 1 mod 3329
        //   17 * x - 3329*y = 1
        //   Extended GCD: 17*1959 - 3329*10 = 33303-33290=-587? No...
        //   Let me compute: 17*1959=33303, 3329*10=33290, diff=13→not right
        // Actually let me compute the modular inverse properly.
        // Using extended Euclidean algorithm:
        // 3329 = 195*17 + 14
        // 17 = 1*14 + 3
        // 14 = 4*3 + 2
        // 3 = 1*2 + 1
        // 2 = 2*1 + 0
        // Back-substitute:
        // 1 = 3 - 2
        //   = 3 - (14 - 4*3) = 5*3 - 14
        //   = 5*(17 - 14) - 14 = 5*17 - 6*14
        //   = 5*17 - 6*(3329 - 195*17) = 1175*17 - 6*3329
        // So 17^{-1} mod 3329 = 1175
        // Let me verify: 17*1175 = 19975, 3329*6 = 19974, diff = 1. YES!
        begin
            reg [31:0] ar, br, zinv, exp0, exp1;
            ar = 100 % MLKEM_Q; br = 200 % MLKEM_Q;
            zinv = 1175;   // 17^{-1} mod 3329
            exp0 = (ar + br) % MLKEM_Q;              // a+b
            exp1 = ((ar >= br) ? (ar-br) : (ar+MLKEM_Q-br) % MLKEM_Q) * zinv % MLKEM_Q;
            run_mlkem_case(M_GS_BFU, 100, 200, 0, zinv, MLKEM_Q, 1'b1, exp0, exp1,
                           "GS_BFU: a=100, b=200, zeta_inv=1175");
        end

        // --- Test 3: Point-wise multiply (MUL_ADD with c=0) ---
        // NTT domain element-wise multiplication: c = a * b mod q
        // a=500, b=600 → 500*600=300000, 300000 mod 3329 = ?
        // 3329*90=299610, 300000-299610=390
        begin
            run_mlkem_case(M_MUL_ADD, 500, 600, 0, 0, MLKEM_Q, 1'b1,
                           390, 390,
                           "MUL_ADD(c=0): 500*600 mod 3329");
        end

        // --- Test 4: Point-wise MAC (MUL_ADD with c≠0) ---
        // Accumulate: acc = prev_acc + a*b mod q
        // prev_acc(c)=390, a=700, b=800
        // 700*800=560000, 560000 mod 3329:
        // 3329*168=559272, 560000-559272=728
        // result = 390 + 728 = 1118 mod 3329
        begin
            run_mlkem_case(M_MUL_ADD, 700, 800, 390, 0, MLKEM_Q, 1'b1,
                           1118, 728,
                           "MUL_ADD(c=390): 700*800+390 mod 3329");
        end

        // --- Test 5: Base Multiplication component ---
        // ML-KEM base multiplication: h0 = a0*b0 + a1*b1*zeta
        // Step A: a1*b1 mod q → y1
        // a1=300, b1=400 → 300*400=120000, 3329*36=119844, 120000-119844=156
        // Step B: (a1*b1) * zeta + a0*b0 → y0
        // a0=100, b0=200, prev_ab=156, zeta=17
        // 156*17=2652, + 20000=22652, 22652 mod 3329:
        // 3329*6=19974, 22652-19974=2678
        begin
            run_mlkem_case(M_MUL_ADD, 300, 400, 0, 0, MLKEM_Q, 1'b1,
                           156, 156,
                           "BASE_MUL stepA: a1*b1=300*400 mod 3329");
            run_mlkem_case(M_MUL_ADD, 100, 200, (300*400*17) % MLKEM_Q, 0, MLKEM_Q, 1'b1,
                           ((100*200) + (300*400*17)) % MLKEM_Q,
                           (100*200) % MLKEM_Q,
                           "BASE_MUL stepB: a0*b0 + (a1*b1)*17 mod 3329");
        end

        // --- Test 6: Montgomery Multiplication (MODE 8) ---
        // MontReduce(a*b) = a*b * R^{-1} mod q,  R = 2^32
        // a=500, b=600 → T=300000
        // Expected: T * R^{-1} mod 3329 (via reference function)
        begin
            reg [63:0] T;
            reg [31:0] qinv, exp_mont;
            T = 32'd500 * 32'd600;    // 300000
            qinv = compute_mont_inv(MLKEM_Q);
            exp_mont = ref_mont(T, MLKEM_Q, qinv, 1'b1);
            run_mlkem_case(M_MONT_MUL, 500, 600, 0, 0, MLKEM_Q, 1'b1,
                           exp_mont, T[31:0],
                           "MONT_MUL: MontReduce(500*600)");
        end

        // --- Test 7: Mul-Sub (MODE 9) ---
        // y0 = a*b - c mod q,  y1 = a*b mod q
        // a=100, b=200, c=50
        // a*b=20000, 20000 mod 3329: 3329*6=19974, 20000-19974=26
        // 26 - 50: 26+3329-50=3305
        begin
            run_mlkem_case(M_MUL_SUB, 100, 200, 50, 0, MLKEM_Q, 1'b1,
                           (20000 % MLKEM_Q + MLKEM_Q - 50) % MLKEM_Q,
                           20000 % MLKEM_Q,
                           "MUL_SUB: 100*200 - 50 mod 3329");
        end

        // --- Test 8: MADD_MSUB (MODE 10) ---
        // y0 = a*b + c mod q, y1 = a*b - c mod q
        // a=100, b=200, c=50
        // a*b = 20000 ≡ 26 (mod 3329)
        // y0 = 26+50 = 76, y1 = (26-50)%3329 = 3305
        begin
            run_mlkem_case(M_MADD_MSUB, 100, 200, 50, 0, MLKEM_Q, 1'b1,
                           (20000 % MLKEM_Q + 50) % MLKEM_Q,
                           (20000 % MLKEM_Q + MLKEM_Q - 50) % MLKEM_Q,
                           "MADD_MSUB: y0=ab+c, y1=ab-c mod 3329");
        end

        // --- Test 9: MACC_W (MODE 11) ---
        // y0 = a*b + w mod q, y1 = a*b mod q
        // a=100, b=200, w=500
        begin
            run_mlkem_case(M_MACC_W, 100, 200, 0, 500, MLKEM_Q, 1'b1,
                           (20000 % MLKEM_Q + 500) % MLKEM_Q,
                           20000 % MLKEM_Q,
                           "MACC_W: y0=ab+w, y1=ab mod 3329");
        end

        // --- Test 10: SQUARE (MODE 12) ---
        // y0 = a*a mod q, y1 = b*w mod q
        // a=100 → 10000 mod 3329:
        // 3329*3=9987, 10000-9987=13
        // b=200, w=17 → 3400 mod 3329 = 71
        begin
            run_mlkem_case(M_SQUARE, 100, 200, 0, 17, MLKEM_Q, 1'b1,
                           (100*100) % MLKEM_Q,
                           (200*17) % MLKEM_Q,
                           "SQUARE: y0=100², y1=200*17 mod 3329");
        end

        // --- Test 11: CT_LAZY (MODE 13) — no mod reduction ---
        // y0 = a + b*w (raw), y1 = a - b*w (raw)
        // a=100, b=10, w=17 → b*w=170
        // y0=270, y1=100-170=-70 (unsigned: 2^32-70 = 4294967226)
        begin
            run_mlkem_case(M_CT_LAZY, 100, 10, 0, 17, MLKEM_Q, 1'b0,
                           100 + 10*17,
                           32'hFFFF_FFBA,
                           "CT_LAZY: 100+10*17, 100-10*17 (no mod)");
        end

        // --- Test 12: COND_RED (MODE 14) ---
        // Pass inputs through S0 reduction
        // a=4000 (>3329) → reduced to 4000-3329=671
        // b=7000 (>2*3329=6658) → reduced to 7000-2*3329=7000-6658=342
        begin
            run_mlkem_case(M_COND_RED, 4000, 7000, 0, 0, MLKEM_Q, 1'b1,
                           4000 % MLKEM_Q,
                           (7000 >= MLKEM_Q) ? ((7000 >= 2*MLKEM_Q) ? (7000 - 2*MLKEM_Q) : (7000 - MLKEM_Q)) : 7000,
                           "COND_RED: reduce(4000), reduce(7000)");
        end

        // ================================================================
        // Additional Barrett-stress tests with ML-KEM q=3329
        // ================================================================
        $display("--- Barrett stress with q=3329 ---");

        // Near-boundary products
        run_mlkem_case(M_MUL_ADD, 3328, 3328, 0, 0, MLKEM_Q, 1'b1,
                       (3328*3328) % MLKEM_Q,
                       (3328*3328) % MLKEM_Q,
                       "Barrett: 3328*3328 mod 3329");

        // Large accumulation test (simulating matrix-vector MAC)
        run_mlkem_case(M_MUL_ADD, 3000, 3000, 2500, 0, MLKEM_Q, 1'b1,
                       (3000*3000 + 2500) % MLKEM_Q,
                       (3000*3000) % MLKEM_Q,
                       "MAC: 3000*3000+2500 mod 3329");

        // ================================================================
        // Results
        // ================================================================
        if (errors == 0) begin
            $display("============================================================");
            $display("PASS: All %0d ML-KEM arithmetic checks passed.", tests);
            $display("============================================================");
        end else begin
            $display("============================================================");
            $display("FAIL: %0d errors in %0d checks.", errors, tests);
            $display("============================================================");
        end
        $finish;
    end

    initial begin
        repeat (500) @(posedge clk);
        $display("TIMEOUT");
        $finish;
    end

endmodule
