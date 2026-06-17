`timescale 1ns/1ps

module tb_reconfig_fe_f64_pipe;
    localparam [3:0] FE_MODE_CT_BFU_COMPLEX = 4'd0;
    localparam [3:0] FE_MODE_GS_BFU_COMPLEX = 4'd1;
    localparam [3:0] FE_MODE_FLOAT_ADD      = 4'd2;
    localparam [3:0] FE_MODE_FLOAT_SUB      = 4'd3;
    localparam [3:0] FE_MODE_FLOAT_MUL      = 4'd4;
    localparam [3:0] FE_MODE_COMPLEX_ADD    = 4'd5;
    localparam [3:0] FE_MODE_COMPLEX_SUB    = 4'd6;
    localparam [3:0] FE_MODE_COMPLEX_MUL    = 4'd7;
    localparam [3:0] FE_MODE_COMPLEX_SQR    = 4'd8;
    localparam [3:0] FE_MODE_COMPLEX_MAC    = 4'd9;

    localparam [63:0] F64_ZERO     = 64'h0000_0000_0000_0000;
    localparam [63:0] F64_NEG_ZERO = 64'h8000_0000_0000_0000;
    localparam [63:0] F64_025      = 64'h3fd0_0000_0000_0000;
    localparam [63:0] F64_050      = 64'h3fe0_0000_0000_0000;
    localparam [63:0] F64_075      = 64'h3fe8_0000_0000_0000;
    localparam [63:0] F64_100      = 64'h3ff0_0000_0000_0000;
    localparam [63:0] F64_150      = 64'h3ff8_0000_0000_0000;
    localparam [63:0] F64_NEG_050  = 64'hbfe0_0000_0000_0000;

    reg         clk;
    reg         rst_n;
    reg         valid_in;
    reg  [3:0]  mode;
    reg  [63:0] a_re;
    reg  [63:0] a_im;
    reg  [63:0] b_re;
    reg  [63:0] b_im;
    reg  [63:0] c_re;
    reg  [63:0] c_im;
    reg  [63:0] w_re;
    reg  [63:0] w_im;

    wire        valid_out;
    wire [63:0] y0_re;
    wire [63:0] y0_im;
    wire [63:0] y1_re;
    wire [63:0] y1_im;
    wire        status_invalid;
    wire        status_overflow;
    wire        status_underflow;
    wire        status_inexact;

    integer errors;

    reconfig_fe_f64_pipe dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .mode(mode),
        .a_re(a_re),
        .a_im(a_im),
        .b_re(b_re),
        .b_im(b_im),
        .c_re(c_re),
        .c_im(c_im),
        .w_re(w_re),
        .w_im(w_im),
        .valid_out(valid_out),
        .y0_re(y0_re),
        .y0_im(y0_im),
        .y1_re(y1_re),
        .y1_im(y1_im),
        .status_invalid(status_invalid),
        .status_overflow(status_overflow),
        .status_underflow(status_underflow),
        .status_inexact(status_inexact)
    );

    always #5 clk = ~clk;

    task check_word;
        input [127:0] name;
        input [63:0]  got;
        input [63:0]  exp;
        begin
            if (!((got == exp) || ((got == F64_ZERO) && (exp == F64_NEG_ZERO)) ||
                  ((got == F64_NEG_ZERO) && (exp == F64_ZERO)))) begin
                $display("TB_FAIL %0s got=%h exp=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task drive_case;
        input [3:0]   case_mode;
        input [63:0]  case_a_re;
        input [63:0]  case_a_im;
        input [63:0]  case_b_re;
        input [63:0]  case_b_im;
        input [63:0]  case_c_re;
        input [63:0]  case_c_im;
        input [63:0]  case_w_re;
        input [63:0]  case_w_im;
        begin
            mode     = case_mode;
            a_re     = case_a_re;
            a_im     = case_a_im;
            b_re     = case_b_re;
            b_im     = case_b_im;
            c_re     = case_c_re;
            c_im     = case_c_im;
            w_re     = case_w_re;
            w_im     = case_w_im;
            valid_in = 1'b1;
        end
    endtask

    task check_outputs;
        input [127:0] name;
        input [63:0]  exp_y0_re;
        input [63:0]  exp_y0_im;
        input [63:0]  exp_y1_re;
        input [63:0]  exp_y1_im;
        begin
            #1;
            if (!valid_out) begin
                $display("TB_FAIL %0s valid_out low", name);
                errors = errors + 1;
            end
            check_word({name, ".y0_re"}, y0_re, exp_y0_re);
            check_word({name, ".y0_im"}, y0_im, exp_y0_im);
            check_word({name, ".y1_re"}, y1_re, exp_y1_re);
            check_word({name, ".y1_im"}, y1_im, exp_y1_im);
        end
    endtask

    task run_case;
        input [127:0] name;
        input [3:0]   case_mode;
        input [63:0]  case_a_re;
        input [63:0]  case_a_im;
        input [63:0]  case_b_re;
        input [63:0]  case_b_im;
        input [63:0]  case_c_re;
        input [63:0]  case_c_im;
        input [63:0]  case_w_re;
        input [63:0]  case_w_im;
        input [63:0]  exp_y0_re;
        input [63:0]  exp_y0_im;
        input [63:0]  exp_y1_re;
        input [63:0]  exp_y1_im;
        begin
            @(negedge clk);
            drive_case(case_mode, case_a_re, case_a_im, case_b_re, case_b_im,
                       case_c_re, case_c_im, case_w_re, case_w_im);
            @(posedge clk);
            @(negedge clk);
            valid_in = 1'b0;
            @(posedge clk);
            @(posedge clk);
            check_outputs(name, exp_y0_re, exp_y0_im, exp_y1_re, exp_y1_im);
        end
    endtask

    initial begin
        clk      = 1'b0;
        rst_n    = 1'b0;
        valid_in = 1'b0;
        mode     = 4'd0;
        a_re     = 64'd0;
        a_im     = 64'd0;
        b_re     = 64'd0;
        b_im     = 64'd0;
        c_re     = 64'd0;
        c_im     = 64'd0;
        w_re     = 64'd0;
        w_im     = 64'd0;
        errors   = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        run_case("float_add", FE_MODE_FLOAT_ADD,
                 F64_100, F64_ZERO, F64_050, F64_ZERO,
                 F64_ZERO, F64_ZERO, F64_100, F64_ZERO,
                 F64_150, F64_ZERO, F64_ZERO, F64_ZERO);

        run_case("float_sub", FE_MODE_FLOAT_SUB,
                 F64_100, F64_ZERO, F64_050, F64_ZERO,
                 F64_ZERO, F64_ZERO, F64_100, F64_ZERO,
                 F64_050, F64_ZERO, F64_ZERO, F64_ZERO);

        run_case("float_mul", FE_MODE_FLOAT_MUL,
                 F64_100, F64_ZERO, F64_050, F64_ZERO,
                 F64_ZERO, F64_ZERO, F64_100, F64_ZERO,
                 F64_050, F64_ZERO, F64_ZERO, F64_ZERO);

        run_case("complex_mul", FE_MODE_COMPLEX_MUL,
                 F64_100, F64_100, F64_050, F64_050,
                 F64_ZERO, F64_ZERO, F64_100, F64_ZERO,
                 F64_ZERO, F64_100, F64_ZERO, F64_ZERO);

        run_case("complex_sqr", FE_MODE_COMPLEX_SQR,
                 F64_100, F64_050, F64_ZERO, F64_ZERO,
                 F64_ZERO, F64_ZERO, F64_100, F64_ZERO,
                 F64_075, F64_100, F64_ZERO, F64_ZERO);

        run_case("complex_mac", FE_MODE_COMPLEX_MAC,
                 F64_100, F64_100, F64_050, F64_050,
                 F64_025, F64_050, F64_100, F64_ZERO,
                 F64_025, F64_150, F64_ZERO, F64_100);

        run_case("ct_bfu", FE_MODE_CT_BFU_COMPLEX,
                 F64_100, F64_ZERO, F64_050, F64_050,
                 F64_ZERO, F64_ZERO, F64_100, F64_ZERO,
                 F64_150, F64_050, F64_050, F64_NEG_050);

        run_case("gs_bfu", FE_MODE_GS_BFU_COMPLEX,
                 F64_100, F64_050, F64_050, F64_NEG_050,
                 F64_ZERO, F64_ZERO, F64_100, F64_ZERO,
                 F64_150, F64_ZERO, F64_050, F64_100);

        @(negedge clk);
        drive_case(FE_MODE_FLOAT_ADD, F64_100, F64_ZERO, F64_050, F64_ZERO,
                   F64_ZERO, F64_ZERO, F64_100, F64_ZERO);
        @(posedge clk);
        @(negedge clk);
        drive_case(FE_MODE_FLOAT_SUB, F64_100, F64_ZERO, F64_050, F64_ZERO,
                   F64_ZERO, F64_ZERO, F64_100, F64_ZERO);
        @(posedge clk);
        @(negedge clk);
        valid_in = 1'b0;
        @(posedge clk);
        check_outputs("btb_add", F64_150, F64_ZERO, F64_ZERO, F64_ZERO);
        @(posedge clk);
        check_outputs("btb_sub", F64_050, F64_ZERO, F64_ZERO, F64_ZERO);

        if (errors == 0) begin
            $display("TB_PASS all pipelined f64 FE cases");
        end else begin
            $display("TB_FAIL errors=%0d", errors);
        end
        $finish;
    end

    initial begin
        #8000;
        $display("TB_FAIL timeout");
        $finish;
    end

endmodule
