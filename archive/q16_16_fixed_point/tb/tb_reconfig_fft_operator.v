`timescale 1ns/1ps

module tb_reconfig_fft_operator;

    localparam WORD_W = 32;
    localparam FRAC_W = 16;
    localparam MODE_W = 4;
    localparam LANES  = 8;

    localparam signed [WORD_W-1:0] FX_ONE     = 32'sd65536;
    localparam signed [WORD_W-1:0] FX_HALF    = 32'sd32768;
    localparam signed [WORD_W-1:0] FX_QUARTER = 32'sd16384;

    reg clk;
    reg rst_n;
    reg valid_in;
    reg inverse;
    reg [(LANES*WORD_W)-1:0] va_re_vec;
    reg [(LANES*WORD_W)-1:0] va_im_vec;
    reg [(LANES*WORD_W)-1:0] vb_re_vec;
    reg [(LANES*WORD_W)-1:0] vb_im_vec;
    reg [(LANES*WORD_W)-1:0] tw_re_vec;
    reg [(LANES*WORD_W)-1:0] tw_im_vec;

    wire valid_out;
    wire [(LANES*WORD_W)-1:0] va_out_re_vec;
    wire [(LANES*WORD_W)-1:0] va_out_im_vec;
    wire [(LANES*WORD_W)-1:0] vb_out_re_vec;
    wire [(LANES*WORD_W)-1:0] vb_out_im_vec;

    integer error_count;
    integer test_count;

    reconfig_fft_operator #(
        .WORD_W(WORD_W),
        .FRAC_W(FRAC_W),
        .MODE_W(MODE_W),
        .LANES (LANES)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .valid_in      (valid_in),
        .inverse       (inverse),
        .va_re_vec     (va_re_vec),
        .va_im_vec     (va_im_vec),
        .vb_re_vec     (vb_re_vec),
        .vb_im_vec     (vb_im_vec),
        .tw_re_vec     (tw_re_vec),
        .tw_im_vec     (tw_im_vec),
        .valid_out     (valid_out),
        .va_out_re_vec (va_out_re_vec),
        .va_out_im_vec (va_out_im_vec),
        .vb_out_re_vec (vb_out_re_vec),
        .vb_out_im_vec (vb_out_im_vec)
    );

    always #5 clk = ~clk;

    function signed [WORD_W-1:0] lane;
        input [(LANES*WORD_W)-1:0] vec;
        input integer idx;
        begin
            lane = vec[(idx*WORD_W) +: WORD_W];
        end
    endfunction

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

    task init_vectors;
        integer i;
        begin
            for (i = 0; i < LANES; i = i + 1) begin
                va_re_vec[(i*WORD_W) +: WORD_W] = FX_ONE + (i * 32'sd1024);
                va_im_vec[(i*WORD_W) +: WORD_W] = FX_QUARTER + (i * 32'sd512);
                vb_re_vec[(i*WORD_W) +: WORD_W] = FX_HALF;
                vb_im_vec[(i*WORD_W) +: WORD_W] = FX_QUARTER;
                tw_re_vec[(i*WORD_W) +: WORD_W] = FX_HALF;
                tw_im_vec[(i*WORD_W) +: WORD_W] = FX_HALF;
            end
        end
    endtask

    task run_operator_case;
        input t_inverse;
        integer i;
        reg signed [WORD_W-1:0] a_re;
        reg signed [WORD_W-1:0] a_im;
        reg signed [WORD_W-1:0] b_re;
        reg signed [WORD_W-1:0] b_im;
        reg signed [WORD_W-1:0] tw_re;
        reg signed [WORD_W-1:0] tw_im;
        reg signed [WORD_W-1:0] bw_re;
        reg signed [WORD_W-1:0] bw_im;
        reg signed [WORD_W-1:0] diff_re;
        reg signed [WORD_W-1:0] diff_im;
        reg signed [WORD_W-1:0] exp_va_re;
        reg signed [WORD_W-1:0] exp_va_im;
        reg signed [WORD_W-1:0] exp_vb_re;
        reg signed [WORD_W-1:0] exp_vb_im;
        begin
            init_vectors;
            @(posedge clk);
            inverse  <= t_inverse;
            valid_in <= 1'b1;
            @(posedge clk);
            valid_in <= 1'b0;
            repeat (3) @(posedge clk);
            #1;

            test_count = test_count + 1;
            if (valid_out !== 1'b1) begin
                $display("TB_FAIL FFT inverse=%0d valid_out was not asserted", t_inverse);
                error_count = error_count + 1;
            end

            for (i = 0; i < LANES; i = i + 1) begin
                a_re  = lane(va_re_vec, i);
                a_im  = lane(va_im_vec, i);
                b_re  = lane(vb_re_vec, i);
                b_im  = lane(vb_im_vec, i);
                tw_re = lane(tw_re_vec, i);
                tw_im = lane(tw_im_vec, i);
                bw_re = cmul_re(b_re, b_im, tw_re, tw_im);
                bw_im = cmul_im(b_re, b_im, tw_re, tw_im);
                diff_re = a_re - b_re;
                diff_im = a_im - b_im;
                if (t_inverse == 1'b0) begin
                    exp_va_re = a_re + bw_re;
                    exp_va_im = a_im + bw_im;
                    exp_vb_re = a_re - bw_re;
                    exp_vb_im = a_im - bw_im;
                end else begin
                    exp_va_re = a_re + b_re;
                    exp_va_im = a_im + b_im;
                    exp_vb_re = cmul_re(diff_re, diff_im, tw_re, tw_im);
                    exp_vb_im = cmul_im(diff_re, diff_im, tw_re, tw_im);
                end
                if ((lane(va_out_re_vec, i) !== exp_va_re) || (lane(va_out_im_vec, i) !== exp_va_im) ||
                    (lane(vb_out_re_vec, i) !== exp_vb_re) || (lane(vb_out_im_vec, i) !== exp_vb_im)) begin
                    $display("TB_FAIL FFT inverse=%0d lane=%0d got va=(%0d,%0d) vb=(%0d,%0d) expected va=(%0d,%0d) vb=(%0d,%0d)",
                             t_inverse, i,
                             lane(va_out_re_vec, i), lane(va_out_im_vec, i),
                             lane(vb_out_re_vec, i), lane(vb_out_im_vec, i),
                             exp_va_re, exp_va_im, exp_vb_re, exp_vb_im);
                    error_count = error_count + 1;
                end
            end
        end
    endtask

    initial begin
        clk         = 1'b0;
        rst_n       = 1'b0;
        valid_in    = 1'b0;
        inverse     = 1'b0;
        va_re_vec   = {(LANES*WORD_W){1'b0}};
        va_im_vec   = {(LANES*WORD_W){1'b0}};
        vb_re_vec   = {(LANES*WORD_W){1'b0}};
        vb_im_vec   = {(LANES*WORD_W){1'b0}};
        tw_re_vec   = {(LANES*WORD_W){1'b0}};
        tw_im_vec   = {(LANES*WORD_W){1'b0}};
        error_count = 0;
        test_count  = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        run_operator_case(1'b0);
        run_operator_case(1'b1);

        if (error_count == 0) begin
            $display("TB_PASS all %0d FFT operator cases", test_count);
        end else begin
            $display("TB_FAIL %0d errors in %0d FFT operator cases", error_count, test_count);
        end
        $finish;
    end

    initial begin
        repeat (700) @(posedge clk);
        $display("TB_FAIL FFT operator timeout");
        $finish;
    end

endmodule
