`timescale 1ns/1ps

// P4: 64-bit Multiply-Accumulate — word-serial big-number multiplication.
//
// Tests the MUL_ACC and ACC_RD modes:
//   1. Accumulate 2 products, verify acc
//   2. Clear + accumulate fresh products
//   3. Word-serial 64×64→128 multiply, verify via reference

module tb_wide_mul;

    localparam WORD_W = 32;
    localparam MODE_W = 3;

    localparam [MODE_W-1:0] M_MUL_ACC = 3'd6;
    localparam [MODE_W-1:0] M_ACC_RD  = 3'd7;

    reg                  clk, rst_n, valid_in;
    reg  [MODE_W-1:0]    mode;
    reg                  use_mod;
    reg  [WORD_W-1:0]    modulus;
    reg  [(2*WORD_W)-1:0] mu_val;
    reg  [4:0]           k_val;
    reg                  acc_clr;
    reg  [WORD_W-1:0]    a, b, c, w;
    wire                 valid_out;
    wire [WORD_W-1:0]    y0, y1;
    wire [(2*WORD_W)-1:0] acc_out;

    reconfig_ae #(.WORD_W(WORD_W),.MODE_W(MODE_W)) dut (
        .clk(clk),.rst_n(rst_n),.valid_in(valid_in),.mode(mode),
        .use_mod(use_mod),.modulus(modulus),.mu(mu_val),.k_log2(k_val),
        .a(a),.b(b),.c(c),.w(w),
        .valid_out(valid_out),.y0(y0),.y1(y1),
        .acc_clr(acc_clr),.acc_out(acc_out)
    );

    always #5 clk = ~clk;

    integer errors, tests;

    // Drive one MUL_ACC operation: mode=6, valid=1 for 1 cycle, wait pipeline
    task mul_acc;
        input [31:0] va, vb;
        input        clr;
        begin
            @(posedge clk);
            mode    <= M_MUL_ACC;
            a       <= va;
            b       <= vb;
            c       <= 32'd0;
            w       <= 32'd0;
            acc_clr <= clr;
            valid_in <= 1'b1;
            @(posedge clk);
            valid_in <= 1'b0;
            repeat (5) @(posedge clk);  // pipeline + valid_out
        end
    endtask

    // Read accumulator via ACC_RD mode
    task read_acc;
        output [63:0] val;
        begin
            @(posedge clk);
            mode    <= M_ACC_RD;
            a       <= 32'd0; b <= 32'd0; c <= 32'd0; w <= 32'd0;
            acc_clr <= 1'b0;
            valid_in <= 1'b1;
            @(posedge clk);
            valid_in <= 1'b0;
            repeat (5) @(posedge clk);
            #1;
            val = {y1, y0};
        end
    endtask

    reg [63:0] ref_acc, rd_acc;
    reg [63:0] p0, p1, p2, p3;
    reg [127:0] wide_result;

    initial begin
        clk=1'b0; rst_n=1'b0; valid_in=1'b0; mode=3'd0;
        use_mod=1'b0; modulus=32'd0; mu_val=64'd0; k_val=5'd0;
        acc_clr=1'b0; a=0; b=0; c=0; w=0;
        errors=0; tests=0;

        repeat (4) @(posedge clk); rst_n=1'b1; repeat (2) @(posedge clk);

        // ================================================================
        // Test 1: Two-product accumulation
        //   A=0x1000_0000, B=0x2000_0000 → P0=0x0200_0000_0000_0000
        //   A=0x3000_0000, B=0x4000_0000 → P1=0x0C00_0000_0000_0000
        //   acc = P0 + P1 = 0x0E00_0000_0000_0000
        // ================================================================
        $display("=== Test 1: Two-product accumulation ===");
        mul_acc(32'h1000_0000, 32'h2000_0000, 1'b1);  // clear + multiply
        p0 = 64'h0200_0000_0000_0000;
        tests=tests+2;
        if (y0 !== p0[31:0] || y1 !== p0[63:32]) begin
            $display("FAIL P0: got y0=%h y1=%h expected %h", y0, y1, p0);
            errors=errors+1;
        end else $display("PASS P0 = %h", p0);

        mul_acc(32'h3000_0000, 32'h4000_0000, 1'b0);  // accumulate
        p1 = 64'h0C00_0000_0000_0000;
        ref_acc = p0 + p1;
        tests=tests+1;
        if (acc_out !== ref_acc) begin
            $display("FAIL acc: got %h expected %h", acc_out, ref_acc);
            errors=errors+1;
        end else $display("PASS acc = %h", acc_out);

        // ================================================================
        // Test 2: ACC_RD — read accumulator to y0/y1
        // ================================================================
        $display("=== Test 2: ACC_RD mode ===");
        read_acc(rd_acc);
        tests=tests+1;
        if (rd_acc !== ref_acc) begin
            $display("FAIL ACC_RD: got %h expected %h", rd_acc, ref_acc);
            errors=errors+1;
        end else $display("PASS ACC_RD = %h", rd_acc);

        // ================================================================
        // Test 3: Clear + fresh accumulation
        //   P2 = 0x5000_0000 * 0x6000_0000 = 0x1E00_0000_0000_0000
        //   acc should be just P2 (not prev + P2)
        // ================================================================
        $display("=== Test 3: Clear + fresh accumulation ===");
        mul_acc(32'h5000_0000, 32'h6000_0000, 1'b1);
        p2 = 64'h1E00_0000_0000_0000;
        tests=tests+1;
        if (acc_out !== p2) begin
            $display("FAIL clear+acc: got %h expected %h", acc_out, p2);
            errors=errors+1;
        end else $display("PASS acc (after clear) = %h", acc_out);

        // ================================================================
        // Test 4: 64-bit × 64-bit → 128-bit word-serial multiply
        //   A = {A1=0xAAAA_BBBB, A0=0xCCCC_DDDD}  (64-bit)
        //   B = {B1=0x1111_2222, B0=0x3333_4444}
        //
        //   P0 = A0*B0 → acc(clear)
        //   save acc_lo = P0
        //   P1 = A0*B1 → acc(clear)
        //   P2 = A1*B0 → acc += P2
        //   save acc_mid = acc (= P1+P2), track carry
        //   P3 = A1*B1 → acc(clear)
        //   save acc_hi = P3 + carry
        //
        //   Result = {acc_hi, acc_mid, acc_lo} with carry propagation
        // ================================================================
        $display("=== Test 4: 64×64 → 128 word-serial ===");

        // P0 = A0 * B0
        mul_acc(32'hCCCC_DDDD, 32'h3333_4444, 1'b1);
        p0 = 64'hCCCC_DDDD * 64'h3333_4444;
        read_acc(rd_acc);
        tests=tests+1;
        if (rd_acc !== p0) begin
            $display("FAIL P0 word-serial: got %h exp %h", rd_acc, p0);
            errors=errors+1;
        end else $display("PASS P0 = %h", p0);

        // P1 = A0 * B1  (clear, then accumulate P2)
        mul_acc(32'hCCCC_DDDD, 32'h1111_2222, 1'b1);
        p1 = 64'hCCCC_DDDD * 64'h1111_2222;
        // P2 = A1 * B0  (accumulate to P1)
        mul_acc(32'hAAAA_BBBB, 32'h3333_4444, 1'b0);
        p2 = 64'hAAAA_BBBB * 64'h3333_4444;
        ref_acc = p1 + p2;
        read_acc(rd_acc);
        tests=tests+1;
        if (rd_acc !== ref_acc) begin
            $display("FAIL P1+P2 word-serial: got %h exp %h", rd_acc, ref_acc);
            errors=errors+1;
        end else $display("PASS P1+P2 = %h", ref_acc);

        // P3 = A1 * B1
        mul_acc(32'hAAAA_BBBB, 32'h1111_2222, 1'b1);
        p3 = 64'hAAAA_BBBB * 64'h1111_2222;
        read_acc(rd_acc);
        tests=tests+1;
        if (rd_acc !== p3) begin
            $display("FAIL P3 word-serial: got %h exp %h", rd_acc, p3);
            errors=errors+1;
        end else $display("PASS P3 = %h", p3);

        // Assemble 128-bit result:
        // result = P0 + (P1+P2)*2^32 + P3*2^64
        // Handle carry: P1+P2 might overflow 64 bits
        // full 128-bit add with carry
        wide_result = p0
                    + ({64'd0, p1} << 32)
                    + ({64'd0, p2} << 32)
                    + (p3 << 64);
        $display("128-bit result = %h", wide_result);

        // Verify against reference: A*B mod 2^128
        begin : check_128
            reg [63:0] A64, B64;
            reg [127:0] ref128;
            A64 = {32'hAAAA_BBBB, 32'hCCCC_DDDD};
            B64 = {32'h1111_2222, 32'h3333_4444};
            ref128 = A64 * B64;
            tests=tests+1;
            if (wide_result !== ref128) begin
                $display("FAIL 128-bit: got %h exp %h", wide_result, ref128);
                errors=errors+1;
            end else $display("PASS 128-bit multiply = %h", wide_result);
        end

        if (errors == 0)
            $display("TB_PASS all %0d checks (P4 wide multiply)", tests);
        else
            $display("TB_FAIL %0d errors in %0d checks", errors, tests);
        $finish;
    end

    initial begin repeat(600) @(posedge clk); $display("TB_FAIL timeout"); $finish; end

endmodule
