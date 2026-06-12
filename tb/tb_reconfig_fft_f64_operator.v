`timescale 1ns/1ps

module tb_reconfig_fft_f64_operator;
    localparam LANES = 2;

    localparam [63:0] F64_ZERO     = 64'h0000_0000_0000_0000;
    localparam [63:0] F64_NEG_ZERO = 64'h8000_0000_0000_0000;
    localparam [63:0] F64_050      = 64'h3fe0_0000_0000_0000;
    localparam [63:0] F64_100      = 64'h3ff0_0000_0000_0000;
    localparam [63:0] F64_150      = 64'h3ff8_0000_0000_0000;
    localparam [63:0] F64_NEG_050  = 64'hbfe0_0000_0000_0000;

    reg                     clk;
    reg                     rst_n;
    reg                     valid_in;
    reg                     inverse;
    reg  [LANES*64-1:0]     va_re_vec;
    reg  [LANES*64-1:0]     va_im_vec;
    reg  [LANES*64-1:0]     vb_re_vec;
    reg  [LANES*64-1:0]     vb_im_vec;
    reg  [LANES*64-1:0]     tw_re_vec;
    reg  [LANES*64-1:0]     tw_im_vec;
    wire                    valid_out;
    wire [LANES*64-1:0]     va_out_re_vec;
    wire [LANES*64-1:0]     va_out_im_vec;
    wire [LANES*64-1:0]     vb_out_re_vec;
    wire [LANES*64-1:0]     vb_out_im_vec;
    wire                    status_invalid;
    wire                    status_overflow;
    wire                    status_underflow;
    wire                    status_inexact;

    integer errors;

    reconfig_fft_f64_operator #(
        .LANES(LANES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .inverse(inverse),
        .va_re_vec(va_re_vec),
        .va_im_vec(va_im_vec),
        .vb_re_vec(vb_re_vec),
        .vb_im_vec(vb_im_vec),
        .tw_re_vec(tw_re_vec),
        .tw_im_vec(tw_im_vec),
        .valid_out(valid_out),
        .va_out_re_vec(va_out_re_vec),
        .va_out_im_vec(va_out_im_vec),
        .vb_out_re_vec(vb_out_re_vec),
        .vb_out_im_vec(vb_out_im_vec),
        .status_invalid(status_invalid),
        .status_overflow(status_overflow),
        .status_underflow(status_underflow),
        .status_inexact(status_inexact)
    );

    always #5 clk = ~clk;

    task check_word;
        input [127:0] name;
        input [63:0] got;
        input [63:0] exp;
        begin
            if (!((got == exp) || ((got == F64_ZERO) && (exp == F64_NEG_ZERO)) ||
                  ((got == F64_NEG_ZERO) && (exp == F64_ZERO)))) begin
                $display("TB_FAIL %0s got=%h exp=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task pulse_and_check_ct;
        begin
            @(negedge clk);
            inverse  = 1'b0;
            valid_in = 1'b1;
            @(posedge clk);
            #1;
            if (!valid_out) begin
                $display("TB_FAIL ct valid_out low");
                errors = errors + 1;
            end
            check_word("ct_l0_va_re", va_out_re_vec[0*64 +: 64], F64_150);
            check_word("ct_l0_va_im", va_out_im_vec[0*64 +: 64], F64_050);
            check_word("ct_l0_vb_re", vb_out_re_vec[0*64 +: 64], F64_050);
            check_word("ct_l0_vb_im", vb_out_im_vec[0*64 +: 64], F64_NEG_050);
            check_word("ct_l1_va_re", va_out_re_vec[1*64 +: 64], F64_150);
            check_word("ct_l1_va_im", va_out_im_vec[1*64 +: 64], F64_050);
            check_word("ct_l1_vb_re", vb_out_re_vec[1*64 +: 64], F64_050);
            check_word("ct_l1_vb_im", vb_out_im_vec[1*64 +: 64], F64_NEG_050);
            @(negedge clk);
            valid_in = 1'b0;
        end
    endtask

    task pulse_and_check_gs;
        begin
            @(negedge clk);
            inverse  = 1'b1;
            valid_in = 1'b1;
            @(posedge clk);
            #1;
            if (!valid_out) begin
                $display("TB_FAIL gs valid_out low");
                errors = errors + 1;
            end
            check_word("gs_l0_va_re", va_out_re_vec[0*64 +: 64], F64_150);
            check_word("gs_l0_va_im", va_out_im_vec[0*64 +: 64], F64_ZERO);
            check_word("gs_l0_vb_re", vb_out_re_vec[0*64 +: 64], F64_050);
            check_word("gs_l0_vb_im", vb_out_im_vec[0*64 +: 64], F64_100);
            check_word("gs_l1_va_re", va_out_re_vec[1*64 +: 64], F64_150);
            check_word("gs_l1_va_im", va_out_im_vec[1*64 +: 64], F64_ZERO);
            check_word("gs_l1_vb_re", vb_out_re_vec[1*64 +: 64], F64_050);
            check_word("gs_l1_vb_im", vb_out_im_vec[1*64 +: 64], F64_100);
            @(negedge clk);
            valid_in = 1'b0;
        end
    endtask

    initial begin
        clk       = 1'b0;
        rst_n     = 1'b0;
        valid_in  = 1'b0;
        inverse   = 1'b0;
        errors    = 0;
        va_re_vec = {F64_100, F64_100};
        va_im_vec = {F64_ZERO, F64_ZERO};
        vb_re_vec = {F64_050, F64_050};
        vb_im_vec = {F64_050, F64_050};
        tw_re_vec = {F64_100, F64_100};
        tw_im_vec = {F64_ZERO, F64_ZERO};

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        pulse_and_check_ct();

        va_re_vec = {F64_100, F64_100};
        va_im_vec = {F64_050, F64_050};
        vb_re_vec = {F64_050, F64_050};
        vb_im_vec = {F64_NEG_050, F64_NEG_050};
        tw_re_vec = {F64_100, F64_100};
        tw_im_vec = {F64_ZERO, F64_ZERO};

        pulse_and_check_gs();

        if (errors == 0) begin
            $display("TB_PASS all f64 FFT operator cases");
        end else begin
            $display("TB_FAIL errors=%0d", errors);
        end
        $finish;
    end

    initial begin
        #5000;
        $display("TB_FAIL timeout");
        $finish;
    end

endmodule
