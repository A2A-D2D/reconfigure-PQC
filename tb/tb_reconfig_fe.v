`timescale 1ns/1ps

module tb_reconfig_fe;

    localparam WORD_W = 32;
    localparam FRAC_W = 16;
    localparam MODE_W = 4;

    localparam signed [WORD_W-1:0] FX_ONE  = 32'sd65536;
    localparam signed [WORD_W-1:0] FX_HALF = 32'sd32768;

    localparam [MODE_W-1:0] FE_MODE_CT_BFU_COMPLEX = 4'd0;
    localparam [MODE_W-1:0] FE_MODE_GS_BFU_COMPLEX = 4'd1;
    localparam [MODE_W-1:0] FE_MODE_FLOAT_ADD      = 4'd2;
    localparam [MODE_W-1:0] FE_MODE_FLOAT_SUB      = 4'd3;
    localparam [MODE_W-1:0] FE_MODE_FLOAT_MUL      = 4'd4;
    localparam [MODE_W-1:0] FE_MODE_COMPLEX_ADD    = 4'd5;
    localparam [MODE_W-1:0] FE_MODE_COMPLEX_SUB    = 4'd6;
    localparam [MODE_W-1:0] FE_MODE_COMPLEX_MUL    = 4'd7;
    localparam [MODE_W-1:0] FE_MODE_COMPLEX_SQR    = 4'd8;
    localparam [MODE_W-1:0] FE_MODE_COMPLEX_MAC    = 4'd9;

    reg clk;
    reg rst_n;
    reg valid_in;
    reg [MODE_W-1:0] mode;
    reg signed [WORD_W-1:0] a_re;
    reg signed [WORD_W-1:0] a_im;
    reg signed [WORD_W-1:0] b_re;
    reg signed [WORD_W-1:0] b_im;
    reg signed [WORD_W-1:0] c_re;
    reg signed [WORD_W-1:0] c_im;
    reg signed [WORD_W-1:0] w_re;
    reg signed [WORD_W-1:0] w_im;

    wire valid_out;
    wire signed [WORD_W-1:0] y0_re;
    wire signed [WORD_W-1:0] y0_im;
    wire signed [WORD_W-1:0] y1_re;
    wire signed [WORD_W-1:0] y1_im;

    integer error_count;
    integer test_count;

    reconfig_fe #(
        .WORD_W(WORD_W),
        .FRAC_W(FRAC_W),
        .MODE_W(MODE_W)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .mode      (mode),
        .a_re      (a_re),
        .a_im      (a_im),
        .b_re      (b_re),
        .b_im      (b_im),
        .c_re      (c_re),
        .c_im      (c_im),
        .w_re      (w_re),
        .w_im      (w_im),
        .valid_out (valid_out),
        .y0_re     (y0_re),
        .y0_im     (y0_im),
        .y1_re     (y1_re),
        .y1_im     (y1_im)
    );

    always #5 clk = ~clk;

    function signed [WORD_W-1:0] scale_product;
        input signed [(2*WORD_W)-1:0] value;
        reg signed [(2*WORD_W)-1:0] shifted;
        begin
            shifted = value >>> FRAC_W;
            scale_product = shifted[WORD_W-1:0];
        end
    endfunction

    function signed [WORD_W-1:0] cmul_re;
        input signed [WORD_W-1:0] lhs_re;
        input signed [WORD_W-1:0] lhs_im;
        input signed [WORD_W-1:0] rhs_re;
        input signed [WORD_W-1:0] rhs_im;
        begin
            cmul_re = scale_product((lhs_re * rhs_re) - (lhs_im * rhs_im));
        end
    endfunction

    function signed [WORD_W-1:0] cmul_im;
        input signed [WORD_W-1:0] lhs_re;
        input signed [WORD_W-1:0] lhs_im;
        input signed [WORD_W-1:0] rhs_re;
        input signed [WORD_W-1:0] rhs_im;
        begin
            cmul_im = scale_product((lhs_re * rhs_im) + (lhs_im * rhs_re));
        end
    endfunction

    task run_case;
        input [MODE_W-1:0] t_mode;
        input signed [WORD_W-1:0] t_a_re;
        input signed [WORD_W-1:0] t_a_im;
        input signed [WORD_W-1:0] t_b_re;
        input signed [WORD_W-1:0] t_b_im;
        input signed [WORD_W-1:0] t_c_re;
        input signed [WORD_W-1:0] t_c_im;
        input signed [WORD_W-1:0] t_w_re;
        input signed [WORD_W-1:0] t_w_im;
        reg signed [WORD_W-1:0] exp_y0_re;
        reg signed [WORD_W-1:0] exp_y0_im;
        reg signed [WORD_W-1:0] exp_y1_re;
        reg signed [WORD_W-1:0] exp_y1_im;
        reg signed [WORD_W-1:0] bw_re;
        reg signed [WORD_W-1:0] bw_im;
        reg signed [WORD_W-1:0] subw_re;
        reg signed [WORD_W-1:0] subw_im;
        begin
            exp_y0_re = {WORD_W{1'b0}};
            exp_y0_im = {WORD_W{1'b0}};
            exp_y1_re = {WORD_W{1'b0}};
            exp_y1_im = {WORD_W{1'b0}};
            bw_re     = cmul_re(t_b_re, t_b_im, t_w_re, t_w_im);
            bw_im     = cmul_im(t_b_re, t_b_im, t_w_re, t_w_im);
            subw_re   = cmul_re(t_a_re - t_b_re, t_a_im - t_b_im, t_w_re, t_w_im);
            subw_im   = cmul_im(t_a_re - t_b_re, t_a_im - t_b_im, t_w_re, t_w_im);

            case (t_mode)
                FE_MODE_CT_BFU_COMPLEX: begin
                    exp_y0_re = t_a_re + bw_re;
                    exp_y0_im = t_a_im + bw_im;
                    exp_y1_re = t_a_re - bw_re;
                    exp_y1_im = t_a_im - bw_im;
                end
                FE_MODE_GS_BFU_COMPLEX: begin
                    exp_y0_re = t_a_re + t_b_re;
                    exp_y0_im = t_a_im + t_b_im;
                    exp_y1_re = subw_re;
                    exp_y1_im = subw_im;
                end
                FE_MODE_FLOAT_ADD: begin
                    exp_y0_re = t_a_re + t_b_re;
                end
                FE_MODE_FLOAT_SUB: begin
                    exp_y0_re = t_a_re - t_b_re;
                end
                FE_MODE_FLOAT_MUL: begin
                    exp_y0_re = scale_product(t_a_re * t_b_re);
                end
                FE_MODE_COMPLEX_ADD: begin
                    exp_y0_re = t_a_re + t_b_re;
                    exp_y0_im = t_a_im + t_b_im;
                end
                FE_MODE_COMPLEX_SUB: begin
                    exp_y0_re = t_a_re - t_b_re;
                    exp_y0_im = t_a_im - t_b_im;
                end
                FE_MODE_COMPLEX_MUL: begin
                    exp_y0_re = cmul_re(t_a_re, t_a_im, t_b_re, t_b_im);
                    exp_y0_im = cmul_im(t_a_re, t_a_im, t_b_re, t_b_im);
                end
                FE_MODE_COMPLEX_SQR: begin
                    exp_y0_re = cmul_re(t_a_re, t_a_im, t_a_re, t_a_im);
                    exp_y0_im = cmul_im(t_a_re, t_a_im, t_a_re, t_a_im);
                end
                FE_MODE_COMPLEX_MAC: begin
                    exp_y1_re = cmul_re(t_a_re, t_a_im, t_b_re, t_b_im);
                    exp_y1_im = cmul_im(t_a_re, t_a_im, t_b_re, t_b_im);
                    exp_y0_re = exp_y1_re + t_c_re;
                    exp_y0_im = exp_y1_im + t_c_im;
                end
                default: begin
                    exp_y0_re = {WORD_W{1'b0}};
                    exp_y0_im = {WORD_W{1'b0}};
                    exp_y1_re = {WORD_W{1'b0}};
                    exp_y1_im = {WORD_W{1'b0}};
                end
            endcase

            @(posedge clk);
            valid_in <= 1'b1;
            mode     <= t_mode;
            a_re     <= t_a_re;
            a_im     <= t_a_im;
            b_re     <= t_b_re;
            b_im     <= t_b_im;
            c_re     <= t_c_re;
            c_im     <= t_c_im;
            w_re     <= t_w_re;
            w_im     <= t_w_im;
            @(posedge clk);
            valid_in <= 1'b0;
            mode     <= {MODE_W{1'b0}};
            a_re     <= {WORD_W{1'b0}};
            a_im     <= {WORD_W{1'b0}};
            b_re     <= {WORD_W{1'b0}};
            b_im     <= {WORD_W{1'b0}};
            c_re     <= {WORD_W{1'b0}};
            c_im     <= {WORD_W{1'b0}};
            w_re     <= {WORD_W{1'b0}};
            w_im     <= {WORD_W{1'b0}};
            repeat (3) @(posedge clk);
            #1;

            test_count = test_count + 1;
            if (valid_out !== 1'b1) begin
                $display("TB_FAIL FE mode=%0d valid_out was not asserted", t_mode);
                error_count = error_count + 1;
            end else if ((y0_re !== exp_y0_re) || (y0_im !== exp_y0_im) || (y1_re !== exp_y1_re) || (y1_im !== exp_y1_im)) begin
                $display("TB_FAIL FE mode=%0d got y0=(%0d,%0d) y1=(%0d,%0d) expected y0=(%0d,%0d) y1=(%0d,%0d)",
                         t_mode, y0_re, y0_im, y1_re, y1_im, exp_y0_re, exp_y0_im, exp_y1_re, exp_y1_im);
                error_count = error_count + 1;
            end else begin
                $display("TB_PASS FE mode=%0d y0=(%0d,%0d) y1=(%0d,%0d)", t_mode, y0_re, y0_im, y1_re, y1_im);
            end
        end
    endtask

    initial begin
        clk         = 1'b0;
        rst_n       = 1'b0;
        valid_in    = 1'b0;
        mode        = {MODE_W{1'b0}};
        a_re        = {WORD_W{1'b0}};
        a_im        = {WORD_W{1'b0}};
        b_re        = {WORD_W{1'b0}};
        b_im        = {WORD_W{1'b0}};
        c_re        = {WORD_W{1'b0}};
        c_im        = {WORD_W{1'b0}};
        w_re        = {WORD_W{1'b0}};
        w_im        = {WORD_W{1'b0}};
        error_count = 0;
        test_count  = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        run_case(FE_MODE_CT_BFU_COMPLEX, FX_ONE, 32'sd0, FX_HALF, FX_HALF, 32'sd0, 32'sd0, FX_ONE, 32'sd0);
        run_case(FE_MODE_GS_BFU_COMPLEX, FX_ONE, FX_HALF, FX_HALF, -FX_HALF, 32'sd0, 32'sd0, FX_ONE, 32'sd0);
        run_case(FE_MODE_FLOAT_ADD,      FX_ONE, 32'sd0, FX_HALF, 32'sd0, 32'sd0, 32'sd0, 32'sd0, 32'sd0);
        run_case(FE_MODE_FLOAT_SUB,      FX_ONE, 32'sd0, FX_HALF, 32'sd0, 32'sd0, 32'sd0, 32'sd0, 32'sd0);
        run_case(FE_MODE_FLOAT_MUL,      FX_ONE, 32'sd0, FX_HALF, 32'sd0, 32'sd0, 32'sd0, 32'sd0, 32'sd0);
        run_case(FE_MODE_COMPLEX_ADD,    FX_ONE, FX_HALF, FX_HALF, -FX_HALF, 32'sd0, 32'sd0, 32'sd0, 32'sd0);
        run_case(FE_MODE_COMPLEX_SUB,    FX_ONE, FX_HALF, FX_HALF, -FX_HALF, 32'sd0, 32'sd0, 32'sd0, 32'sd0);
        run_case(FE_MODE_COMPLEX_MUL,    FX_ONE, FX_ONE, FX_HALF, FX_HALF, 32'sd0, 32'sd0, 32'sd0, 32'sd0);
        run_case(FE_MODE_COMPLEX_SQR,    FX_ONE, FX_HALF, 32'sd0, 32'sd0, 32'sd0, 32'sd0, 32'sd0, 32'sd0);
        run_case(FE_MODE_COMPLEX_MAC,    FX_ONE, FX_HALF, FX_HALF, FX_HALF, FX_HALF, -FX_HALF, 32'sd0, 32'sd0);

        if (error_count == 0) begin
            $display("TB_PASS all %0d FE cases", test_count);
        end else begin
            $display("TB_FAIL %0d errors in %0d FE cases", error_count, test_count);
        end
        $finish;
    end

    initial begin
        repeat (700) @(posedge clk);
        $display("TB_FAIL FE timeout");
        $finish;
    end

endmodule
