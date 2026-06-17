`timescale 1ns/1ps

module tb_reconfig_ntt_operator;

    localparam LANES = 32;

    reg clk;
    reg rst_n;
    reg valid_in;
    reg inverse;
    reg use_mod;
    reg acc_clr;
    reg [31:0] modulus;
    reg [63:0] mu;
    reg [31:0] mu_mont;
    reg [4:0]  k_log2;
    reg [1023:0] va_vec;
    reg [1023:0] vb_vec;
    reg [1023:0] twiddle_vec;

    wire valid_out;
    wire [1023:0] va_out_vec;
    wire [1023:0] vb_out_vec;
    wire [2047:0] acc_out_vec;

    integer error_count;
    integer test_count;

    reconfig_ntt_operator dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .valid_in    (valid_in),
        .inverse     (inverse),
        .use_mod     (use_mod),
        .acc_clr     (acc_clr),
        .modulus     (modulus),
        .mu          (mu),
        .mu_mont     (mu_mont),
        .k_log2      (k_log2),
        .va_vec      (va_vec),
        .vb_vec      (vb_vec),
        .twiddle_vec (twiddle_vec),
        .valid_out   (valid_out),
        .va_out_vec  (va_out_vec),
        .vb_out_vec  (vb_out_vec),
        .acc_out_vec (acc_out_vec)
    );

    always #5 clk = ~clk;

    function [31:0] get_lane;
        input [1023:0] vec;
        input integer idx;
        begin
            get_lane = vec[(idx*32) +: 32];
        end
    endfunction

    function [31:0] mod_add;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] q;
        reg [32:0] sum_ext;
        begin
            sum_ext = {1'b0, lhs} + {1'b0, rhs};
            mod_add = sum_ext % q;
        end
    endfunction

    function [31:0] mod_sub;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] q;
        begin
            if (lhs >= rhs) begin
                mod_sub = lhs - rhs;
            end else begin
                mod_sub = (lhs + q - rhs) % q;
            end
        end
    endfunction

    function [31:0] mod_mul;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] q;
        reg [63:0] prod;
        begin
            prod = lhs * rhs;
            mod_mul = prod % q;
        end
    endfunction

    task init_vectors;
        integer i;
        reg [31:0] a_val;
        reg [31:0] b_val;
        reg [31:0] w_val;
        begin
            for (i = 0; i < LANES; i = i + 1) begin
                a_val = (32'd100 + i) % modulus;
                b_val = (32'd17 + (i * 32'd3)) % modulus;
                w_val = (32'd5 + i) % modulus;
                va_vec[(i*32) +: 32]      = a_val;
                vb_vec[(i*32) +: 32]      = b_val;
                twiddle_vec[(i*32) +: 32] = w_val;
            end
        end
    endtask

    task run_operator_case;
        input t_inverse;
        integer i;
        reg [31:0] a_val;
        reg [31:0] b_val;
        reg [31:0] w_val;
        reg [31:0] bw_val;
        reg [31:0] exp_va;
        reg [31:0] exp_vb;
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
                $display("TB_FAIL NTT inverse=%0d valid_out was not asserted", t_inverse);
                error_count = error_count + 1;
            end

            for (i = 0; i < LANES; i = i + 1) begin
                a_val = get_lane(va_vec, i) % modulus;
                b_val = get_lane(vb_vec, i) % modulus;
                w_val = get_lane(twiddle_vec, i) % modulus;
                if (t_inverse == 1'b0) begin
                    bw_val = mod_mul(b_val, w_val, modulus);
                    exp_va = mod_add(a_val, bw_val, modulus);
                    exp_vb = mod_sub(a_val, bw_val, modulus);
                end else begin
                    exp_va = mod_add(a_val, b_val, modulus);
                    exp_vb = mod_mul(mod_sub(a_val, b_val, modulus), w_val, modulus);
                end

                if ((get_lane(va_out_vec, i) !== exp_va) || (get_lane(vb_out_vec, i) !== exp_vb)) begin
                    $display("TB_FAIL NTT inverse=%0d lane=%0d got va=%0d vb=%0d expected va=%0d vb=%0d",
                             t_inverse, i, get_lane(va_out_vec, i), get_lane(vb_out_vec, i), exp_va, exp_vb);
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
        use_mod     = 1'b1;
        acc_clr     = 1'b0;
        modulus     = 32'd12289;
        mu          = 64'd1501077717772768;
        mu_mont     = 32'd4143984639;
        k_log2      = 5'd14;
        va_vec      = 1024'd0;
        vb_vec      = 1024'd0;
        twiddle_vec = 1024'd0;
        error_count = 0;
        test_count  = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        run_operator_case(1'b0);
        run_operator_case(1'b1);

        if (error_count == 0) begin
            $display("TB_PASS all %0d NTT operator cases", test_count);
        end else begin
            $display("TB_FAIL %0d errors in %0d NTT operator cases", error_count, test_count);
        end
        $finish;
    end

    initial begin
        repeat (700) @(posedge clk);
        $display("TB_FAIL NTT operator timeout");
        $finish;
    end

endmodule
