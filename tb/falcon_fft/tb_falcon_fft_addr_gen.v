`timescale 1ns/1ps

module tb_falcon_fft_addr_gen;
    reg         inverse;
    reg  [3:0]  logn;
    reg  [3:0]  stage_idx;
    reg  [9:0]  pair_idx;
    wire [9:0]  a_re_addr;
    wire [9:0]  a_im_addr;
    wire [9:0]  b_re_addr;
    wire [9:0]  b_im_addr;
    wire [9:0]  twiddle_addr;
    wire        pair_valid;

    integer errors;

    falcon_fft_addr_gen dut (
        .inverse      (inverse),
        .logn         (logn),
        .stage_idx    (stage_idx),
        .pair_idx     (pair_idx),
        .a_re_addr    (a_re_addr),
        .a_im_addr    (a_im_addr),
        .b_re_addr    (b_re_addr),
        .b_im_addr    (b_im_addr),
        .twiddle_addr (twiddle_addr),
        .pair_valid   (pair_valid)
    );

    task check_case;
        input        case_inverse;
        input [3:0]  case_logn;
        input [3:0]  case_stage;
        input [9:0]  case_pair;
        input [9:0]  exp_a;
        input [9:0]  exp_b;
        input [9:0]  exp_tw;
        begin
            inverse   = case_inverse;
            logn      = case_logn;
            stage_idx = case_stage;
            pair_idx  = case_pair;
            #1;
            if (!pair_valid || a_re_addr != exp_a || a_im_addr != exp_a + (10'd1 << (case_logn - 1)) ||
                b_re_addr != exp_b || b_im_addr != exp_b + (10'd1 << (case_logn - 1)) ||
                twiddle_addr != exp_tw) begin
                $display("TB_FAIL inv=%0d logn=%0d stage=%0d pair=%0d got a=%0d/%0d b=%0d/%0d tw=%0d valid=%0d exp a=%0d b=%0d tw=%0d",
                         case_inverse, case_logn, case_stage, case_pair,
                         a_re_addr, a_im_addr, b_re_addr, b_im_addr,
                         twiddle_addr, pair_valid, exp_a, exp_b, exp_tw);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;

        // Falcon-512 forward FFT.
        check_case(1'b0, 4'd9, 4'd0, 10'd0,   10'd0,   10'd128, 10'd2);
        check_case(1'b0, 4'd9, 4'd0, 10'd127, 10'd127, 10'd255, 10'd2);
        check_case(1'b0, 4'd9, 4'd1, 10'd64,  10'd128, 10'd192, 10'd5);
        check_case(1'b0, 4'd9, 4'd7, 10'd127, 10'd254, 10'd255, 10'd383);

        // Falcon-512 inverse FFT.  The twiddle data path must conjugate GM.
        check_case(1'b1, 4'd9, 4'd0, 10'd0,   10'd0,   10'd1,   10'd256);
        check_case(1'b1, 4'd9, 4'd0, 10'd127, 10'd254, 10'd255, 10'd383);
        check_case(1'b1, 4'd9, 4'd1, 10'd1,   10'd1,   10'd3,   10'd128);
        check_case(1'b1, 4'd9, 4'd1, 10'd2,   10'd4,   10'd6,   10'd129);

        // Out-of-range pair should be rejected.
        inverse = 1'b0;
        logn = 4'd9;
        stage_idx = 4'd0;
        pair_idx = 10'd128;
        #1;
        if (pair_valid) begin
            $display("TB_FAIL out-of-range pair reported valid");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TB_PASS falcon_fft_addr_gen");
        end else begin
            $display("TB_FAIL errors=%0d", errors);
        end
        $finish;
    end
endmodule
