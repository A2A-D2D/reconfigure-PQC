`timescale 1ns/1ps
// Module: reconfig_fe_f64_pipe
// Purpose: pipelined Falcon f64 FE lane with explicit pre-add, shared
// 4-multiplier complex stage, and post-add datapath.

module reconfig_fe_f64_pipe #(
    parameter MODE_W = 4
) (
    input                  clk,
    input                  rst_n,
    input                  valid_in,
    input      [MODE_W-1:0] mode,

    input      [63:0]      a_re,
    input      [63:0]      a_im,
    input      [63:0]      b_re,
    input      [63:0]      b_im,
    input      [63:0]      c_re,
    input      [63:0]      c_im,
    input      [63:0]      w_re,
    input      [63:0]      w_im,

    output reg             valid_out,
    output reg [63:0]      y0_re,
    output reg [63:0]      y0_im,
    output reg [63:0]      y1_re,
    output reg [63:0]      y1_im,
    output reg             status_invalid,
    output reg             status_overflow,
    output reg             status_underflow,
    output reg             status_inexact
);

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

    wire [63:0] pre_add_re;
    wire [63:0] pre_add_im;
    wire [63:0] pre_sub_re;
    wire [63:0] pre_sub_im;
    wire        pre_add_re_inv;
    wire        pre_add_re_ovf;
    wire        pre_add_re_udf;
    wire        pre_add_re_inx;
    wire        pre_add_im_inv;
    wire        pre_add_im_ovf;
    wire        pre_add_im_udf;
    wire        pre_add_im_inx;
    wire        pre_sub_re_inv;
    wire        pre_sub_re_ovf;
    wire        pre_sub_re_udf;
    wire        pre_sub_re_inx;
    wire        pre_sub_im_inv;
    wire        pre_sub_im_ovf;
    wire        pre_sub_im_udf;
    wire        pre_sub_im_inx;

    reg                  valid_s1;
    reg [MODE_W-1:0]     mode_s1;
    reg [63:0]           a_re_s1;
    reg [63:0]           a_im_s1;
    reg [63:0]           b_re_s1;
    reg [63:0]           b_im_s1;
    reg [63:0]           c_re_s1;
    reg [63:0]           c_im_s1;
    reg [63:0]           w_re_s1;
    reg [63:0]           w_im_s1;
    reg [63:0]           add_re_s1;
    reg [63:0]           add_im_s1;
    reg [63:0]           sub_re_s1;
    reg [63:0]           sub_im_s1;
    reg                  invalid_s1;
    reg                  overflow_s1;
    reg                  underflow_s1;
    reg                  inexact_s1;

    reg [63:0]           mul0_a;
    reg [63:0]           mul0_b;
    reg [63:0]           mul1_a;
    reg [63:0]           mul1_b;
    reg [63:0]           mul2_a;
    reg [63:0]           mul2_b;
    reg [63:0]           mul3_a;
    reg [63:0]           mul3_b;

    wire [63:0]          mul0_y;
    wire [63:0]          mul1_y;
    wire [63:0]          mul2_y;
    wire [63:0]          mul3_y;
    wire                 mul0_inv;
    wire                 mul0_ovf;
    wire                 mul0_udf;
    wire                 mul0_inx;
    wire                 mul1_inv;
    wire                 mul1_ovf;
    wire                 mul1_udf;
    wire                 mul1_inx;
    wire                 mul2_inv;
    wire                 mul2_ovf;
    wire                 mul2_udf;
    wire                 mul2_inx;
    wire                 mul3_inv;
    wire                 mul3_ovf;
    wire                 mul3_udf;
    wire                 mul3_inx;

    reg                  valid_s2;
    reg [MODE_W-1:0]     mode_s2;
    reg [63:0]           a_re_s2;
    reg [63:0]           a_im_s2;
    reg [63:0]           c_re_s2;
    reg [63:0]           c_im_s2;
    reg [63:0]           add_re_s2;
    reg [63:0]           add_im_s2;
    reg [63:0]           sub_re_s2;
    reg [63:0]           sub_im_s2;
    reg [63:0]           prod0_s2;
    reg [63:0]           prod1_s2;
    reg [63:0]           prod2_s2;
    reg [63:0]           prod3_s2;
    reg                  invalid_s2;
    reg                  overflow_s2;
    reg                  underflow_s2;
    reg                  inexact_s2;

    wire [63:0]          cmul_re;
    wire [63:0]          cmul_im;
    wire [63:0]          ct_y0_re;
    wire [63:0]          ct_y0_im;
    wire [63:0]          ct_y1_re;
    wire [63:0]          ct_y1_im;
    wire [63:0]          mac_re;
    wire [63:0]          mac_im;
    wire                 post_inv;
    wire                 post_ovf;
    wire                 post_udf;
    wire                 post_inx;
    wire                 cmul_re_inv;
    wire                 cmul_re_ovf;
    wire                 cmul_re_udf;
    wire                 cmul_re_inx;
    wire                 cmul_im_inv;
    wire                 cmul_im_ovf;
    wire                 cmul_im_udf;
    wire                 cmul_im_inx;
    wire                 ct_y0_re_inv;
    wire                 ct_y0_re_ovf;
    wire                 ct_y0_re_udf;
    wire                 ct_y0_re_inx;
    wire                 ct_y0_im_inv;
    wire                 ct_y0_im_ovf;
    wire                 ct_y0_im_udf;
    wire                 ct_y0_im_inx;
    wire                 ct_y1_re_inv;
    wire                 ct_y1_re_ovf;
    wire                 ct_y1_re_udf;
    wire                 ct_y1_re_inx;
    wire                 ct_y1_im_inv;
    wire                 ct_y1_im_ovf;
    wire                 ct_y1_im_udf;
    wire                 ct_y1_im_inx;
    wire                 mac_re_inv;
    wire                 mac_re_ovf;
    wire                 mac_re_udf;
    wire                 mac_re_inx;
    wire                 mac_im_inv;
    wire                 mac_im_ovf;
    wire                 mac_im_udf;
    wire                 mac_im_inx;

    falcon_f64_add u_pre_add_re (
        .a(a_re), .b(b_re), .sub(1'b0), .y(pre_add_re),
        .invalid(pre_add_re_inv), .overflow(pre_add_re_ovf),
        .underflow(pre_add_re_udf), .inexact(pre_add_re_inx)
    );

    falcon_f64_add u_pre_add_im (
        .a(a_im), .b(b_im), .sub(1'b0), .y(pre_add_im),
        .invalid(pre_add_im_inv), .overflow(pre_add_im_ovf),
        .underflow(pre_add_im_udf), .inexact(pre_add_im_inx)
    );

    falcon_f64_add u_pre_sub_re (
        .a(a_re), .b(b_re), .sub(1'b1), .y(pre_sub_re),
        .invalid(pre_sub_re_inv), .overflow(pre_sub_re_ovf),
        .underflow(pre_sub_re_udf), .inexact(pre_sub_re_inx)
    );

    falcon_f64_add u_pre_sub_im (
        .a(a_im), .b(b_im), .sub(1'b1), .y(pre_sub_im),
        .invalid(pre_sub_im_inv), .overflow(pre_sub_im_ovf),
        .underflow(pre_sub_im_udf), .inexact(pre_sub_im_inx)
    );

    falcon_f64_mul u_mul0 (
        .a(mul0_a), .b(mul0_b), .y(mul0_y),
        .invalid(mul0_inv), .overflow(mul0_ovf),
        .underflow(mul0_udf), .inexact(mul0_inx)
    );

    falcon_f64_mul u_mul1 (
        .a(mul1_a), .b(mul1_b), .y(mul1_y),
        .invalid(mul1_inv), .overflow(mul1_ovf),
        .underflow(mul1_udf), .inexact(mul1_inx)
    );

    falcon_f64_mul u_mul2 (
        .a(mul2_a), .b(mul2_b), .y(mul2_y),
        .invalid(mul2_inv), .overflow(mul2_ovf),
        .underflow(mul2_udf), .inexact(mul2_inx)
    );

    falcon_f64_mul u_mul3 (
        .a(mul3_a), .b(mul3_b), .y(mul3_y),
        .invalid(mul3_inv), .overflow(mul3_ovf),
        .underflow(mul3_udf), .inexact(mul3_inx)
    );

    always @(*) begin
        mul0_a = a_re_s1;
        mul0_b = b_re_s1;
        mul1_a = a_im_s1;
        mul1_b = b_im_s1;
        mul2_a = a_re_s1;
        mul2_b = b_im_s1;
        mul3_a = a_im_s1;
        mul3_b = b_re_s1;

        case (mode_s1)
            FE_MODE_CT_BFU_COMPLEX: begin
                mul0_a = b_re_s1;
                mul0_b = w_re_s1;
                mul1_a = b_im_s1;
                mul1_b = w_im_s1;
                mul2_a = b_re_s1;
                mul2_b = w_im_s1;
                mul3_a = b_im_s1;
                mul3_b = w_re_s1;
            end

            FE_MODE_GS_BFU_COMPLEX: begin
                mul0_a = sub_re_s1;
                mul0_b = w_re_s1;
                mul1_a = sub_im_s1;
                mul1_b = w_im_s1;
                mul2_a = sub_re_s1;
                mul2_b = w_im_s1;
                mul3_a = sub_im_s1;
                mul3_b = w_re_s1;
            end

            FE_MODE_COMPLEX_SQR: begin
                mul0_a = a_re_s1;
                mul0_b = a_re_s1;
                mul1_a = a_im_s1;
                mul1_b = a_im_s1;
                mul2_a = a_re_s1;
                mul2_b = a_im_s1;
                mul3_a = a_re_s1;
                mul3_b = a_im_s1;
            end

            default: begin
                mul0_a = a_re_s1;
                mul0_b = b_re_s1;
                mul1_a = a_im_s1;
                mul1_b = b_im_s1;
                mul2_a = a_re_s1;
                mul2_b = b_im_s1;
                mul3_a = a_im_s1;
                mul3_b = b_re_s1;
            end
        endcase
    end

    falcon_f64_add u_cmul_re (
        .a(prod0_s2), .b(prod1_s2), .sub(1'b1), .y(cmul_re),
        .invalid(cmul_re_inv), .overflow(cmul_re_ovf),
        .underflow(cmul_re_udf), .inexact(cmul_re_inx)
    );

    falcon_f64_add u_cmul_im (
        .a(prod2_s2), .b(prod3_s2), .sub(1'b0), .y(cmul_im),
        .invalid(cmul_im_inv), .overflow(cmul_im_ovf),
        .underflow(cmul_im_udf), .inexact(cmul_im_inx)
    );

    falcon_f64_add u_ct_y0_re (
        .a(a_re_s2), .b(cmul_re), .sub(1'b0), .y(ct_y0_re),
        .invalid(ct_y0_re_inv), .overflow(ct_y0_re_ovf),
        .underflow(ct_y0_re_udf), .inexact(ct_y0_re_inx)
    );

    falcon_f64_add u_ct_y0_im (
        .a(a_im_s2), .b(cmul_im), .sub(1'b0), .y(ct_y0_im),
        .invalid(ct_y0_im_inv), .overflow(ct_y0_im_ovf),
        .underflow(ct_y0_im_udf), .inexact(ct_y0_im_inx)
    );

    falcon_f64_add u_ct_y1_re (
        .a(a_re_s2), .b(cmul_re), .sub(1'b1), .y(ct_y1_re),
        .invalid(ct_y1_re_inv), .overflow(ct_y1_re_ovf),
        .underflow(ct_y1_re_udf), .inexact(ct_y1_re_inx)
    );

    falcon_f64_add u_ct_y1_im (
        .a(a_im_s2), .b(cmul_im), .sub(1'b1), .y(ct_y1_im),
        .invalid(ct_y1_im_inv), .overflow(ct_y1_im_ovf),
        .underflow(ct_y1_im_udf), .inexact(ct_y1_im_inx)
    );

    falcon_f64_add u_mac_re (
        .a(cmul_re), .b(c_re_s2), .sub(1'b0), .y(mac_re),
        .invalid(mac_re_inv), .overflow(mac_re_ovf),
        .underflow(mac_re_udf), .inexact(mac_re_inx)
    );

    falcon_f64_add u_mac_im (
        .a(cmul_im), .b(c_im_s2), .sub(1'b0), .y(mac_im),
        .invalid(mac_im_inv), .overflow(mac_im_ovf),
        .underflow(mac_im_udf), .inexact(mac_im_inx)
    );

    assign post_inv = cmul_re_inv | cmul_im_inv |
                      ct_y0_re_inv | ct_y0_im_inv | ct_y1_re_inv |
                      ct_y1_im_inv | mac_re_inv | mac_im_inv;
    assign post_ovf = cmul_re_ovf | cmul_im_ovf |
                      ct_y0_re_ovf | ct_y0_im_ovf | ct_y1_re_ovf |
                      ct_y1_im_ovf | mac_re_ovf | mac_im_ovf;
    assign post_udf = cmul_re_udf | cmul_im_udf |
                      ct_y0_re_udf | ct_y0_im_udf | ct_y1_re_udf |
                      ct_y1_im_udf | mac_re_udf | mac_im_udf;
    assign post_inx = cmul_re_inx | cmul_im_inx |
                      ct_y0_re_inx | ct_y0_im_inx | ct_y1_re_inx |
                      ct_y1_im_inx | mac_re_inx | mac_im_inx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1        <= 1'b0;
            mode_s1         <= {MODE_W{1'b0}};
            a_re_s1         <= 64'd0;
            a_im_s1         <= 64'd0;
            b_re_s1         <= 64'd0;
            b_im_s1         <= 64'd0;
            c_re_s1         <= 64'd0;
            c_im_s1         <= 64'd0;
            w_re_s1         <= 64'd0;
            w_im_s1         <= 64'd0;
            add_re_s1       <= 64'd0;
            add_im_s1       <= 64'd0;
            sub_re_s1       <= 64'd0;
            sub_im_s1       <= 64'd0;
            invalid_s1      <= 1'b0;
            overflow_s1     <= 1'b0;
            underflow_s1    <= 1'b0;
            inexact_s1      <= 1'b0;
            valid_s2        <= 1'b0;
            mode_s2         <= {MODE_W{1'b0}};
            a_re_s2         <= 64'd0;
            a_im_s2         <= 64'd0;
            c_re_s2         <= 64'd0;
            c_im_s2         <= 64'd0;
            add_re_s2       <= 64'd0;
            add_im_s2       <= 64'd0;
            sub_re_s2       <= 64'd0;
            sub_im_s2       <= 64'd0;
            prod0_s2        <= 64'd0;
            prod1_s2        <= 64'd0;
            prod2_s2        <= 64'd0;
            prod3_s2        <= 64'd0;
            invalid_s2      <= 1'b0;
            overflow_s2     <= 1'b0;
            underflow_s2    <= 1'b0;
            inexact_s2      <= 1'b0;
            valid_out       <= 1'b0;
            y0_re           <= 64'd0;
            y0_im           <= 64'd0;
            y1_re           <= 64'd0;
            y1_im           <= 64'd0;
            status_invalid  <= 1'b0;
            status_overflow <= 1'b0;
            status_underflow <= 1'b0;
            status_inexact  <= 1'b0;
        end else begin
            valid_s1     <= valid_in;
            mode_s1      <= mode;
            a_re_s1      <= a_re;
            a_im_s1      <= a_im;
            b_re_s1      <= b_re;
            b_im_s1      <= b_im;
            c_re_s1      <= c_re;
            c_im_s1      <= c_im;
            w_re_s1      <= w_re;
            w_im_s1      <= w_im;
            add_re_s1    <= pre_add_re;
            add_im_s1    <= pre_add_im;
            sub_re_s1    <= pre_sub_re;
            sub_im_s1    <= pre_sub_im;
            invalid_s1   <= pre_add_re_inv | pre_add_im_inv |
                            pre_sub_re_inv | pre_sub_im_inv;
            overflow_s1  <= pre_add_re_ovf | pre_add_im_ovf |
                            pre_sub_re_ovf | pre_sub_im_ovf;
            underflow_s1 <= pre_add_re_udf | pre_add_im_udf |
                            pre_sub_re_udf | pre_sub_im_udf;
            inexact_s1   <= pre_add_re_inx | pre_add_im_inx |
                            pre_sub_re_inx | pre_sub_im_inx;

            valid_s2     <= valid_s1;
            mode_s2      <= mode_s1;
            a_re_s2      <= a_re_s1;
            a_im_s2      <= a_im_s1;
            c_re_s2      <= c_re_s1;
            c_im_s2      <= c_im_s1;
            add_re_s2    <= add_re_s1;
            add_im_s2    <= add_im_s1;
            sub_re_s2    <= sub_re_s1;
            sub_im_s2    <= sub_im_s1;
            prod0_s2     <= mul0_y;
            prod1_s2     <= mul1_y;
            prod2_s2     <= mul2_y;
            prod3_s2     <= mul3_y;
            invalid_s2   <= invalid_s1 | mul0_inv | mul1_inv | mul2_inv | mul3_inv;
            overflow_s2  <= overflow_s1 | mul0_ovf | mul1_ovf | mul2_ovf | mul3_ovf;
            underflow_s2 <= underflow_s1 | mul0_udf | mul1_udf | mul2_udf | mul3_udf;
            inexact_s2   <= inexact_s1 | mul0_inx | mul1_inx | mul2_inx | mul3_inx;

            valid_out        <= valid_s2;
            status_invalid   <= invalid_s2 | post_inv;
            status_overflow  <= overflow_s2 | post_ovf;
            status_underflow <= underflow_s2 | post_udf;
            status_inexact   <= inexact_s2 | post_inx;

            case (mode_s2)
                FE_MODE_CT_BFU_COMPLEX: begin
                    y0_re <= ct_y0_re;
                    y0_im <= ct_y0_im;
                    y1_re <= ct_y1_re;
                    y1_im <= ct_y1_im;
                end

                FE_MODE_GS_BFU_COMPLEX: begin
                    y0_re <= add_re_s2;
                    y0_im <= add_im_s2;
                    y1_re <= cmul_re;
                    y1_im <= cmul_im;
                end

                FE_MODE_FLOAT_ADD: begin
                    y0_re <= add_re_s2;
                    y0_im <= 64'd0;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_FLOAT_SUB: begin
                    y0_re <= sub_re_s2;
                    y0_im <= 64'd0;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_FLOAT_MUL: begin
                    y0_re <= prod0_s2;
                    y0_im <= 64'd0;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_COMPLEX_ADD: begin
                    y0_re <= add_re_s2;
                    y0_im <= add_im_s2;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_COMPLEX_SUB: begin
                    y0_re <= sub_re_s2;
                    y0_im <= sub_im_s2;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_COMPLEX_MUL: begin
                    y0_re <= cmul_re;
                    y0_im <= cmul_im;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_COMPLEX_SQR: begin
                    y0_re <= cmul_re;
                    y0_im <= cmul_im;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_COMPLEX_MAC: begin
                    y0_re <= mac_re;
                    y0_im <= mac_im;
                    y1_re <= cmul_re;
                    y1_im <= cmul_im;
                end

                default: begin
                    y0_re <= 64'd0;
                    y0_im <= 64'd0;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end
            endcase
        end
    end

endmodule
