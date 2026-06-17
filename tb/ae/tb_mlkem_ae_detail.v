`timescale 1ns/1ps

// ML-KEM (FIPS 203) detailed cycle-level verification.
// Shows pipeline latency and per-mode arithmetic timing.
//
// Pipeline stages:
//   Cycle 0: Inputs captured (S0) — valid_in, a, b, c, w, mode, mod params
//   Cycle 1: Multiplication (S1) — 4 parallel 32×32→64 multipliers
//   Cycle 2: Barrett/Montgomery reduction (S2) — combinational reduction
//   Cycle 3: Output selection and valid_out asserted
//   Latency  = 4 cycles from valid_in to valid_out

module tb_mlkem_ae_detail;

    localparam WORD_W = 32;
    localparam MODE_W = 4;

    localparam [WORD_W-1:0] MLKEM_Q    = 32'd3329;
    localparam [WORD_W-1:0] MLKEM_ZETA = 32'd17;

    localparam [MODE_W-1:0] M_CT_BFU    = 4'd0;
    localparam [MODE_W-1:0] M_GS_BFU    = 4'd1;
    localparam [MODE_W-1:0] M_MUL_ADD   = 4'd2;
    localparam [MODE_W-1:0] M_ADD_SUB   = 4'd4;
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
    realtime cycle_in, cycle_out;

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
    // Helper functions
    // ==================================================================
    function [4:0] compute_k;
        input [WORD_W-1:0] q;
        integer i;
        begin
            compute_k = 5'd0;
            for (i = WORD_W-1; i >= 0; i = i - 1)
                if (q[i] && (compute_k == 5'd0)) compute_k = i + 1;
        end
    endfunction

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

    function [WORD_W-1:0] compute_mont_inv;
        input [WORD_W-1:0] q_in;
        reg [63:0] x, prod;
        integer i;
        begin
            x = 64'd1;
            for (i = 0; i < 5; i = i + 1) begin
                prod = q_in * x;
                prod = 64'd2 - prod;
                x = x * prod;
                case (i)
                    0: x = x & 64'h3;
                    1: x = x & 64'hF;
                    2: x = x & 64'hFF;
                    3: x = x & 64'hFFFF;
                    4: x = x & 64'hFFFF_FFFF;
                endcase
            end
            compute_mont_inv = ({32'd1, 32'd0} - x);
        end
    endfunction

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

    function [WORD_W-1:0] ref_mont;
        input [(2*WORD_W)-1:0] T;
        input [WORD_W-1:0] qq, qinv;
        input en;
        reg [(2*WORD_W)-1:0] m, mq;
        reg [(2*WORD_W):0]   t_full;
        reg [(2*WORD_W):0]   t_wide;
        begin
            if (en && qq != 0) begin
                m      = T[WORD_W-1:0] * qinv;
                m      = m[WORD_W-1:0];
                mq     = m * qq;
                t_full = {1'b0, T} + {1'b0, mq};
                t_wide = t_full >> WORD_W;
                ref_mont = (t_wide >= qq) ? (t_wide - qq) : t_wide[WORD_W-1:0];
            end else begin
                ref_mont = T[WORD_W-1:0];
            end
        end
    endfunction

    // ==================================================================
    // Single test-case runner WITH cycle counting
    // ==================================================================
    task run_case;
        input [MODE_W-1:0] t_mode;
        input [WORD_W-1:0] t_a, t_b, t_c, t_w;
        input [WORD_W-1:0] t_q;
        input              t_use_mod;
        input [WORD_W-1:0] exp_y0;
        input [WORD_W-1:0] exp_y1;
        input [8*30:1]     desc;
        begin
            k_log2  = compute_k(t_q);
            mu      = compute_mu(t_q, k_log2);
            mu_mont = compute_mont_inv(t_q);

            // ── Drive inputs at this rising edge ──
            @(posedge clk);
            cycle_in = $realtime;
            valid_in <= 1'b1;
            mode     <= t_mode;
            use_mod  <= t_use_mod;
            modulus  <= t_q;
            a <= t_a; b <= t_b; c <= t_c; w <= t_w;

            // ── Deassert valid_in next cycle ──
            @(posedge clk);
            valid_in <= 1'b0;
            mode     <= {MODE_W{1'b0}};
            use_mod  <= 1'b0;
            modulus  <= 0;
            a <= 0; b <= 0; c <= 0; w <= 0;

            // ── Wait for pipeline to drain ──
            @(posedge clk);  // S1 in progress
            @(posedge clk);  // S2 in progress
            @(posedge clk);  // output appears
            cycle_out = $realtime;
            #1;

            tests = tests + 2;
            if (valid_out !== 1'b1) begin
                $display("[t=%0t] FAIL [%0s] valid_out not asserted", $realtime, desc);
                errors = errors + 2;
            end else begin
                $display("[t=%0t] MODE=%0d %0s | latency=%0d ns (%0d cycles)",
                         $realtime, t_mode, desc,
                         cycle_out - cycle_in,
                         (cycle_out - cycle_in) / 10);
                $display("         in : a=%0d b=%0d c=%0d w=%0d", t_a, t_b, t_c, t_w);
                $display("         out: y0=%0d y1=%0d", y0, y1);
                $display("         exp: y0=%0d y1=%0d", exp_y0, exp_y1);
                if (y0 !== exp_y0) begin
                    $display("         ** FAIL y0 **");
                    errors = errors + 1;
                end
                if (y1 !== exp_y1) begin
                    $display("         ** FAIL y1 **");
                    errors = errors + 1;
                end
                if (y0 === exp_y0 && y1 === exp_y1)
                    $display("         PASS");
            end
        end
    endtask

    // ==================================================================
    // Main test sequence
    // ==================================================================
    initial begin
        clk = 1'b0; rst_n = 1'b0; valid_in = 1'b0;
        mode = 0; use_mod = 1'b0; modulus = 0;
        mu = 0; mu_mont = 0; k_log2 = 0;
        a = 0; b = 0; c = 0; w = 0;
        errors = 0; tests = 0;

        repeat(4) @(posedge clk); rst_n = 1'b1; repeat(2) @(posedge clk);

        $display("================================================================================");
        $display("ML-KEM (FIPS 203) Cycle-Level Pipeline Verification");
        $display("q = %0d, zeta = %0d, clk period = 10ns", MLKEM_Q, MLKEM_ZETA);
        $display("Pipeline: S0(input)→S1(mul)→S2(reduce)→OUT = 4-cycle latency");
        $display("================================================================================");

        // === CT Butterfly ===
        begin
            reg [31:0] ar, br, vr, exp0, exp1;
            ar = 100; br = 200;
            vr = (br * 17) % MLKEM_Q;
            exp0 = (ar + vr) % MLKEM_Q;
            exp1 = (ar >= vr) ? (ar - vr) : (ar + MLKEM_Q - vr) % MLKEM_Q;
            run_case(M_CT_BFU, 100, 200, 0, 17, MLKEM_Q, 1'b1, exp0, exp1, "CT_BFU zeta=17");
        end

        // === GS Butterfly ===
        begin
            reg [31:0] ar, br, zinv, exp0, exp1;
            ar = 100; br = 200;
            zinv = 1175;  // 17^{-1} mod 3329
            exp0 = (ar + br) % MLKEM_Q;
            exp1 = ((ar >= br) ? (ar-br) : (ar+MLKEM_Q-br) % MLKEM_Q) * zinv % MLKEM_Q;
            run_case(M_GS_BFU, 100, 200, 0, zinv, MLKEM_Q, 1'b1, exp0, exp1, "GS_BFU zeta_inv=1175");
        end

        // === Point-wise Multiply ===
        begin
            reg [31:0] exp0;
            exp0 = 32'd500 * 32'd600 % MLKEM_Q;  // 300000 % 3329 = 390
            run_case(M_MUL_ADD, 500, 600, 0, 0, MLKEM_Q, 1'b1, exp0, exp0, "MUL 500*600");
        end

        // === Multiply-Accumulate ===
        begin
            reg [31:0] accum, prod, exp0, exp1;
            accum = 390; prod = 32'd700 * 32'd800 % MLKEM_Q;  // prod = 728
            exp0 = (accum + prod) % MLKEM_Q;  // 1118
            run_case(M_MUL_ADD, 700, 800, 390, 0, MLKEM_Q, 1'b1, exp0, 728, "MAC acc+700*800");
        end

        // === Base Multiplication (2-step) ===
        begin
            reg [31:0] stepA;
            stepA = 32'd300 * 32'd400 % MLKEM_Q;  // 156
            run_case(M_MUL_ADD, 300, 400, 0, 0, MLKEM_Q, 1'b1, stepA, stepA, "BASE_MUL stepA: a1*b1");
            run_case(M_MUL_ADD, 100, 200, (300*400*17) % MLKEM_Q, 0, MLKEM_Q, 1'b1,
                     ((100*200) + (300*400*17)) % MLKEM_Q, (100*200) % MLKEM_Q,
                     "BASE_MUL stepB: a0*b0+a1*b1*zeta");
        end

        // === Montgomery Multiplication ===
        begin
            reg [63:0] T;
            reg [31:0] qinv, exp_mont;
            T = 32'd500 * 32'd600;
            qinv = compute_mont_inv(MLKEM_Q);
            exp_mont = ref_mont(T, MLKEM_Q, qinv, 1'b1);
            run_case(M_MONT_MUL, 500, 600, 0, 0, MLKEM_Q, 1'b1, exp_mont, T[31:0], "MONT_MUL 500*600");
        end

        // === Extended modes ===
        begin
            run_case(M_MUL_SUB, 100, 200, 50, 0, MLKEM_Q, 1'b1,
                     (20000 % MLKEM_Q + MLKEM_Q - 50) % MLKEM_Q, 20000 % MLKEM_Q,
                     "MUL_SUB ab-c");
            run_case(M_MADD_MSUB, 100, 200, 50, 0, MLKEM_Q, 1'b1,
                     (20000 % MLKEM_Q + 50) % MLKEM_Q, (20000 % MLKEM_Q + MLKEM_Q - 50) % MLKEM_Q,
                     "MADD_MSUB ab+c,ab-c");
            run_case(M_MACC_W, 100, 200, 0, 500, MLKEM_Q, 1'b1,
                     (20000 % MLKEM_Q + 500) % MLKEM_Q, 20000 % MLKEM_Q,
                     "MACC_W ab+w");
            run_case(M_SQUARE, 100, 200, 0, 17, MLKEM_Q, 1'b1,
                     (100*100) % MLKEM_Q, (200*17) % MLKEM_Q,
                     "SQUARE a²,b*w");
        end

        // === Lazy / Conditional ===
        begin
            run_case(M_CT_LAZY, 100, 10, 0, 17, MLKEM_Q, 1'b0,
                     100 + 10*17, 32'hFFFF_FFBA, "CT_LAZY no mod");
            run_case(M_COND_RED, 4000, 7000, 0, 0, MLKEM_Q, 1'b1,
                     4000 % MLKEM_Q, 7000 - 2*MLKEM_Q, "COND_RED large");
        end

        // === Boundary stress ===
        begin
            run_case(M_MUL_ADD, 3328, 3328, 0, 0, MLKEM_Q, 1'b1,
                     (3328*3328) % MLKEM_Q, (3328*3328) % MLKEM_Q,
                     "Barrett (q-1)²");
            run_case(M_MUL_ADD, 3000, 3000, 2500, 0, MLKEM_Q, 1'b1,
                     (3000*3000 + 2500) % MLKEM_Q, (3000*3000) % MLKEM_Q,
                     "Barrett big MAC");
        end

        // ================================================================
        // Results
        // ================================================================
        $display("================================================================================");
        if (errors == 0) begin
            $display("PASS: All %0d ML-KEM arithmetic checks passed.", tests);
        end else begin
            $display("FAIL: %0d errors in %0d checks.", errors, tests);
        end
        $display("================================================================================");
        $display("Pipeline latency: 4 clock cycles from valid_in↑ to valid_out↑");
        $display("Throughput: 1 new input every cycle (fully pipelined)");
        $display("================================================================================");
        $finish;
    end

    initial begin
        repeat (500) @(posedge clk);
        $display("TIMEOUT");
        $finish;
    end

endmodule
