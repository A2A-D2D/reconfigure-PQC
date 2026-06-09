`timescale 1ns/1ps

module tb_reconfig_ae;

    localparam WORD_W = 32;
    localparam MODE_W = 3;

    localparam [MODE_W-1:0] AE_MODE_CT_BFU  = 3'd0;
    localparam [MODE_W-1:0] AE_MODE_GS_BFU  = 3'd1;
    localparam [MODE_W-1:0] AE_MODE_MUL_ADD = 3'd2;
    localparam [MODE_W-1:0] AE_MODE_ADD_MUL = 3'd3;
    localparam [MODE_W-1:0] AE_MODE_ADD_SUB = 3'd4;
    localparam [MODE_W-1:0] AE_MODE_BIG_MUL = 3'd5;

    reg                  clk;
    reg                  rst_n;
    reg                  valid_in;
    reg  [MODE_W-1:0]    mode;
    reg                  use_mod;
    reg  [WORD_W-1:0]    modulus;
    reg  [(2*WORD_W)-1:0] mu_barrett;
    reg  [WORD_W-1:0]    a;
    reg  [WORD_W-1:0]    b;
    reg  [WORD_W-1:0]    c;
    reg  [WORD_W-1:0]    w;
    wire                 valid_out;
    wire [WORD_W-1:0]    y0;
    wire [WORD_W-1:0]    y1;

    integer error_count;
    integer test_count;

    // Barrett constant:  mu = floor(2^64 / q)
    // Uses 65-bit arithmetic for the numerator.  Result fits in 64 bits
    // for all q >= 2.  For q <= 1, we return 0 (unused).
    function [(2*WORD_W)-1:0] compute_mu;
        input [WORD_W-1:0] q;
        reg [64:0] two64;
        begin
            if (q > 32'd1) begin
                two64 = 65'h1_0000_0000_0000_0000;   // 2^64
                compute_mu = two64 / q;
            end else begin
                // q = 0 or 1: Barrett not needed (result is 0 or x)
                compute_mu = 64'd0;
            end
        end
    endfunction

    reconfig_ae #(
        .WORD_W(WORD_W),
        .MODE_W(MODE_W)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .mode      (mode),
        .use_mod   (use_mod),
        .modulus   (modulus),
        .mu        (mu_barrett),
        .a         (a),
        .b         (b),
        .c         (c),
        .w         (w),
        .valid_out (valid_out),
        .y0        (y0),
        .y1        (y1)
    );

    always #5 clk = ~clk;

    // Reference reduction using % (simulation-only verification)
    function [WORD_W-1:0] ref_reduce;
        input [63:0] value;
        input [31:0] q;
        input        en;
        begin
            if ((en == 1'b1) && (q != 32'd0)) begin
                ref_reduce = value % q;
            end else begin
                ref_reduce = value[31:0];
            end
        end
    endfunction

    function [WORD_W-1:0] ref_add;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] q;
        input        en;
        begin
            ref_add = ref_reduce({31'd0, ({1'b0, lhs} + {1'b0, rhs})}, q, en);
        end
    endfunction

    function [WORD_W-1:0] ref_sub;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] q;
        input        en;
        begin
            if ((en == 1'b1) && (q != 32'd0)) begin
                if (lhs >= rhs) begin
                    ref_sub = lhs - rhs;
                end else begin
                    ref_sub = (lhs + q - rhs) % q;
                end
            end else begin
                ref_sub = lhs - rhs;
            end
        end
    endfunction

    task run_case;
        input [MODE_W-1:0] t_mode;
        input [31:0]       t_a;
        input [31:0]       t_b;
        input [31:0]       t_c;
        input [31:0]       t_w;
        input [31:0]       t_q;
        input              t_use_mod;
        reg [31:0]         a_r;
        reg [31:0]         b_r;
        reg [31:0]         c_r;
        reg [31:0]         w_r;
        reg [31:0]         exp_y0;
        reg [31:0]         exp_y1;
        reg [63:0]         prod_main;
        reg [63:0]         prod_btw;
        reg [63:0]         prod_addc;
        reg [63:0]         prod_subw;
        begin
            a_r = ref_reduce({32'd0, t_a}, t_q, t_use_mod);
            b_r = ref_reduce({32'd0, t_b}, t_q, t_use_mod);
            c_r = ref_reduce({32'd0, t_c}, t_q, t_use_mod);
            w_r = ref_reduce({32'd0, t_w}, t_q, t_use_mod);
            prod_main = a_r * b_r;
            prod_btw  = b_r * w_r;
            prod_addc = ref_add(a_r, b_r, t_q, t_use_mod) * c_r;
            prod_subw = ref_sub(a_r, b_r, t_q, t_use_mod) * w_r;

            case (t_mode)
                AE_MODE_CT_BFU: begin
                    exp_y0 = ref_add(a_r, ref_reduce(prod_btw, t_q, t_use_mod), t_q, t_use_mod);
                    exp_y1 = ref_sub(a_r, ref_reduce(prod_btw, t_q, t_use_mod), t_q, t_use_mod);
                end
                AE_MODE_GS_BFU: begin
                    exp_y0 = ref_add(a_r, b_r, t_q, t_use_mod);
                    exp_y1 = ref_reduce(prod_subw, t_q, t_use_mod);
                end
                AE_MODE_MUL_ADD: begin
                    exp_y0 = ref_add(ref_reduce(prod_main, t_q, t_use_mod), c_r, t_q, t_use_mod);
                    exp_y1 = ref_reduce(prod_main, t_q, t_use_mod);
                end
                AE_MODE_ADD_MUL: begin
                    exp_y0 = ref_reduce(prod_addc, t_q, t_use_mod);
                    exp_y1 = ref_add(a_r, b_r, t_q, t_use_mod);
                end
                AE_MODE_ADD_SUB: begin
                    exp_y0 = ref_add(a_r, b_r, t_q, t_use_mod);
                    exp_y1 = ref_sub(a_r, b_r, t_q, t_use_mod);
                end
                AE_MODE_BIG_MUL: begin
                    exp_y0 = prod_main[31:0];
                    exp_y1 = prod_main[63:32];
                end
                default: begin
                    exp_y0 = 32'd0;
                    exp_y1 = 32'd0;
                end
            endcase

            @(posedge clk);
            valid_in    <= 1'b1;
            mode        <= t_mode;
            use_mod     <= t_use_mod;
            modulus     <= t_q;
            mu_barrett  <= compute_mu(t_q);
            a           <= t_a;
            b           <= t_b;
            c           <= t_c;
            w           <= t_w;
            @(posedge clk);
            valid_in    <= 1'b0;
            mode        <= {MODE_W{1'b0}};
            use_mod     <= 1'b0;
            modulus     <= 32'd0;
            mu_barrett  <= 64'd0;
            a           <= 32'd0;
            b           <= 32'd0;
            c           <= 32'd0;
            w           <= 32'd0;
            repeat (3) @(posedge clk);
            #1;

            test_count = test_count + 1;
            if (valid_out !== 1'b1) begin
                $display("TB_FAIL mode=%0d valid_out was not asserted", t_mode);
                error_count = error_count + 1;
            end else if ((y0 !== exp_y0) || (y1 !== exp_y1)) begin
                $display("TB_FAIL mode=%0d got y0=%0d y1=%0d expected y0=%0d y1=%0d",
                         t_mode, y0, y1, exp_y0, exp_y1);
                $display("  inputs: a=%0d b=%0d c=%0d w=%0d q=%0d use_mod=%0d",
                         t_a, t_b, t_c, t_w, t_q, t_use_mod);
                $display("  mu_barrett=%0d", compute_mu(t_q));
                error_count = error_count + 1;
            end else begin
                $display("TB_PASS mode=%0d y0=%0d y1=%0d", t_mode, y0, y1);
            end
        end
    endtask

    initial begin
        clk         = 1'b0;
        rst_n       = 1'b0;
        valid_in    = 1'b0;
        mode        = {MODE_W{1'b0}};
        use_mod     = 1'b0;
        modulus     = 32'd0;
        mu_barrett  = 64'd0;
        a           = 32'd0;
        b           = 32'd0;
        c           = 32'd0;
        w           = 32'd0;
        error_count = 0;
        test_count  = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Original test cases (all use properly reduced inputs a,b,c,w < q)
        run_case(AE_MODE_CT_BFU,  32'd1000, 32'd3000, 32'd0,    32'd7,  32'd12289, 1'b1);
        run_case(AE_MODE_GS_BFU,  32'd9000, 32'd5000, 32'd0,    32'd11, 32'd12289, 1'b1);
        run_case(AE_MODE_MUL_ADD, 32'd77,   32'd91,   32'd123,  32'd0,  32'd3329,  1'b1);
        run_case(AE_MODE_ADD_MUL, 32'd100,  32'd200,  32'd33,   32'd0,  32'd3329,  1'b1);
        run_case(AE_MODE_ADD_SUB, 32'd5,    32'd10,   32'd0,    32'd0,  32'd17,    1'b1);
        run_case(AE_MODE_BIG_MUL, 32'h1234_5678, 32'h0000_1001, 32'd0, 32'd0, 32'd0,  1'b0);
        run_case(AE_MODE_ADD_SUB, 32'd12300, 32'd24590, 32'd0,  32'd0,  32'd12289, 1'b1);

        // Additional Barrett-stress cases: large modulus near 2^32,
        // products near 2^64 to exercise Barrett's full-precision path
        // Falcon-ish: q=12289
        run_case(AE_MODE_MUL_ADD, 32'd10000, 32'd12000, 32'd500, 32'd0, 32'd12289, 1'b1);
        run_case(AE_MODE_CT_BFU,  32'd5000,  32'd8000,  32'd0,   32'd3, 32'd12289, 1'b1);
        // Dilithium-ish: q=8380417
        run_case(AE_MODE_GS_BFU,  32'd1000000, 32'd2000000, 32'd0,  32'd5, 32'd8380417, 1'b1);
        run_case(AE_MODE_ADD_MUL, 32'd3000000, 32'd4000000, 32'd7, 32'd0, 32'd8380417, 1'b1);
        // Near-max modulus: q close to 2^31 to stress Barrett q3 width
        run_case(AE_MODE_MUL_ADD, 32'd100, 32'd200, 32'd50, 32'd0, 32'h7FFF_FFFF, 1'b1);
        run_case(AE_MODE_CT_BFU,  32'd1000, 32'd2000, 32'd0, 32'd99, 32'h7FFF_FFFF, 1'b1);

        // Edge: modulus near 2^15 (small), large products
        run_case(AE_MODE_MUL_ADD, 32'd32000, 32'd32000, 32'd100, 32'd0, 32'd32771, 1'b1);

        if (error_count == 0) begin
            $display("TB_PASS all %0d cases", test_count);
        end else begin
            $display("TB_FAIL %0d errors in %0d cases", error_count, test_count);
        end
        $finish;
    end

    initial begin
        repeat (500) @(posedge clk);
        $display("TB_FAIL timeout");
        $finish;
    end

endmodule
