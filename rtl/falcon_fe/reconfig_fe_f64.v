`timescale 1ns/1ps
// Module: reconfig_fe_f64
// Purpose: Falcon-oriented double-precision FE lane for FFT butterflies and
// complex fpr arithmetic.  The datapath is combinational through the local
// f64 helpers and registered at the output for a simple valid pulse contract.

module reconfig_fe_f64 #(
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

    wire [63:0] add_re;
    wire [63:0] add_im;
    wire [63:0] sub_re;
    wire [63:0] sub_im;
    wire        add_re_inv;
    wire        add_re_ovf;
    wire        add_re_udf;
    wire        add_re_inx;
    wire        add_im_inv;
    wire        add_im_ovf;
    wire        add_im_udf;
    wire        add_im_inx;
    wire        sub_re_inv;
    wire        sub_re_ovf;
    wire        sub_re_udf;
    wire        sub_re_inx;
    wire        sub_im_inv;
    wire        sub_im_ovf;
    wire        sub_im_udf;
    wire        sub_im_inx;

    wire [63:0] ab_rr;
    wire [63:0] ab_ii;
    wire [63:0] ab_ri;
    wire [63:0] ab_ir;
    wire [63:0] cmul_re;
    wire [63:0] cmul_im;
    wire        ab_rr_inv;
    wire        ab_rr_ovf;
    wire        ab_rr_udf;
    wire        ab_rr_inx;
    wire        ab_ii_inv;
    wire        ab_ii_ovf;
    wire        ab_ii_udf;
    wire        ab_ii_inx;
    wire        ab_ri_inv;
    wire        ab_ri_ovf;
    wire        ab_ri_udf;
    wire        ab_ri_inx;
    wire        ab_ir_inv;
    wire        ab_ir_ovf;
    wire        ab_ir_udf;
    wire        ab_ir_inx;
    wire        cmul_re_inv;
    wire        cmul_re_ovf;
    wire        cmul_re_udf;
    wire        cmul_re_inx;
    wire        cmul_im_inv;
    wire        cmul_im_ovf;
    wire        cmul_im_udf;
    wire        cmul_im_inx;

    wire [63:0] aa_rr;
    wire [63:0] aa_ii;
    wire [63:0] aa_ri;
    wire [63:0] sqr_re;
    wire [63:0] sqr_im;
    wire        aa_rr_inv;
    wire        aa_rr_ovf;
    wire        aa_rr_udf;
    wire        aa_rr_inx;
    wire        aa_ii_inv;
    wire        aa_ii_ovf;
    wire        aa_ii_udf;
    wire        aa_ii_inx;
    wire        aa_ri_inv;
    wire        aa_ri_ovf;
    wire        aa_ri_udf;
    wire        aa_ri_inx;
    wire        sqr_re_inv;
    wire        sqr_re_ovf;
    wire        sqr_re_udf;
    wire        sqr_re_inx;
    wire        sqr_im_inv;
    wire        sqr_im_ovf;
    wire        sqr_im_udf;
    wire        sqr_im_inx;

    wire [63:0] bw_rr;
    wire [63:0] bw_ii;
    wire [63:0] bw_ri;
    wire [63:0] bw_ir;
    wire [63:0] bw_re;
    wire [63:0] bw_im;
    wire        bw_rr_inv;
    wire        bw_rr_ovf;
    wire        bw_rr_udf;
    wire        bw_rr_inx;
    wire        bw_ii_inv;
    wire        bw_ii_ovf;
    wire        bw_ii_udf;
    wire        bw_ii_inx;
    wire        bw_ri_inv;
    wire        bw_ri_ovf;
    wire        bw_ri_udf;
    wire        bw_ri_inx;
    wire        bw_ir_inv;
    wire        bw_ir_ovf;
    wire        bw_ir_udf;
    wire        bw_ir_inx;
    wire        bw_re_inv;
    wire        bw_re_ovf;
    wire        bw_re_udf;
    wire        bw_re_inx;
    wire        bw_im_inv;
    wire        bw_im_ovf;
    wire        bw_im_udf;
    wire        bw_im_inx;

    wire [63:0] ct_y0_re;
    wire [63:0] ct_y0_im;
    wire [63:0] ct_y1_re;
    wire [63:0] ct_y1_im;
    wire        ct_y0_re_inv;
    wire        ct_y0_re_ovf;
    wire        ct_y0_re_udf;
    wire        ct_y0_re_inx;
    wire        ct_y0_im_inv;
    wire        ct_y0_im_ovf;
    wire        ct_y0_im_udf;
    wire        ct_y0_im_inx;
    wire        ct_y1_re_inv;
    wire        ct_y1_re_ovf;
    wire        ct_y1_re_udf;
    wire        ct_y1_re_inx;
    wire        ct_y1_im_inv;
    wire        ct_y1_im_ovf;
    wire        ct_y1_im_udf;
    wire        ct_y1_im_inx;

    wire [63:0] diffw_rr;
    wire [63:0] diffw_ii;
    wire [63:0] diffw_ri;
    wire [63:0] diffw_ir;
    wire [63:0] gs_y1_re;
    wire [63:0] gs_y1_im;
    wire        diffw_rr_inv;
    wire        diffw_rr_ovf;
    wire        diffw_rr_udf;
    wire        diffw_rr_inx;
    wire        diffw_ii_inv;
    wire        diffw_ii_ovf;
    wire        diffw_ii_udf;
    wire        diffw_ii_inx;
    wire        diffw_ri_inv;
    wire        diffw_ri_ovf;
    wire        diffw_ri_udf;
    wire        diffw_ri_inx;
    wire        diffw_ir_inv;
    wire        diffw_ir_ovf;
    wire        diffw_ir_udf;
    wire        diffw_ir_inx;
    wire        gs_y1_re_inv;
    wire        gs_y1_re_ovf;
    wire        gs_y1_re_udf;
    wire        gs_y1_re_inx;
    wire        gs_y1_im_inv;
    wire        gs_y1_im_ovf;
    wire        gs_y1_im_udf;
    wire        gs_y1_im_inx;

    wire [63:0] mac_re;
    wire [63:0] mac_im;
    wire        mac_re_inv;
    wire        mac_re_ovf;
    wire        mac_re_udf;
    wire        mac_re_inx;
    wire        mac_im_inv;
    wire        mac_im_ovf;
    wire        mac_im_udf;
    wire        mac_im_inx;

    wire any_invalid;
    wire any_overflow;
    wire any_underflow;
    wire any_inexact;

    falcon_f64_add u_add_re (
        .a(a_re), .b(b_re), .sub(1'b0), .y(add_re),
        .invalid(add_re_inv), .overflow(add_re_ovf),
        .underflow(add_re_udf), .inexact(add_re_inx)
    );

    falcon_f64_add u_add_im (
        .a(a_im), .b(b_im), .sub(1'b0), .y(add_im),
        .invalid(add_im_inv), .overflow(add_im_ovf),
        .underflow(add_im_udf), .inexact(add_im_inx)
    );

    falcon_f64_add u_sub_re (
        .a(a_re), .b(b_re), .sub(1'b1), .y(sub_re),
        .invalid(sub_re_inv), .overflow(sub_re_ovf),
        .underflow(sub_re_udf), .inexact(sub_re_inx)
    );

    falcon_f64_add u_sub_im (
        .a(a_im), .b(b_im), .sub(1'b1), .y(sub_im),
        .invalid(sub_im_inv), .overflow(sub_im_ovf),
        .underflow(sub_im_udf), .inexact(sub_im_inx)
    );

    falcon_f64_mul u_ab_rr (
        .a(a_re), .b(b_re), .y(ab_rr),
        .invalid(ab_rr_inv), .overflow(ab_rr_ovf),
        .underflow(ab_rr_udf), .inexact(ab_rr_inx)
    );

    falcon_f64_mul u_ab_ii (
        .a(a_im), .b(b_im), .y(ab_ii),
        .invalid(ab_ii_inv), .overflow(ab_ii_ovf),
        .underflow(ab_ii_udf), .inexact(ab_ii_inx)
    );

    falcon_f64_mul u_ab_ri (
        .a(a_re), .b(b_im), .y(ab_ri),
        .invalid(ab_ri_inv), .overflow(ab_ri_ovf),
        .underflow(ab_ri_udf), .inexact(ab_ri_inx)
    );

    falcon_f64_mul u_ab_ir (
        .a(a_im), .b(b_re), .y(ab_ir),
        .invalid(ab_ir_inv), .overflow(ab_ir_ovf),
        .underflow(ab_ir_udf), .inexact(ab_ir_inx)
    );

    falcon_f64_add u_cmul_re (
        .a(ab_rr), .b(ab_ii), .sub(1'b1), .y(cmul_re),
        .invalid(cmul_re_inv), .overflow(cmul_re_ovf),
        .underflow(cmul_re_udf), .inexact(cmul_re_inx)
    );

    falcon_f64_add u_cmul_im (
        .a(ab_ri), .b(ab_ir), .sub(1'b0), .y(cmul_im),
        .invalid(cmul_im_inv), .overflow(cmul_im_ovf),
        .underflow(cmul_im_udf), .inexact(cmul_im_inx)
    );

    falcon_f64_mul u_aa_rr (
        .a(a_re), .b(a_re), .y(aa_rr),
        .invalid(aa_rr_inv), .overflow(aa_rr_ovf),
        .underflow(aa_rr_udf), .inexact(aa_rr_inx)
    );

    falcon_f64_mul u_aa_ii (
        .a(a_im), .b(a_im), .y(aa_ii),
        .invalid(aa_ii_inv), .overflow(aa_ii_ovf),
        .underflow(aa_ii_udf), .inexact(aa_ii_inx)
    );

    falcon_f64_mul u_aa_ri (
        .a(a_re), .b(a_im), .y(aa_ri),
        .invalid(aa_ri_inv), .overflow(aa_ri_ovf),
        .underflow(aa_ri_udf), .inexact(aa_ri_inx)
    );

    falcon_f64_add u_sqr_re (
        .a(aa_rr), .b(aa_ii), .sub(1'b1), .y(sqr_re),
        .invalid(sqr_re_inv), .overflow(sqr_re_ovf),
        .underflow(sqr_re_udf), .inexact(sqr_re_inx)
    );

    falcon_f64_add u_sqr_im (
        .a(aa_ri), .b(aa_ri), .sub(1'b0), .y(sqr_im),
        .invalid(sqr_im_inv), .overflow(sqr_im_ovf),
        .underflow(sqr_im_udf), .inexact(sqr_im_inx)
    );

    falcon_f64_mul u_bw_rr (
        .a(b_re), .b(w_re), .y(bw_rr),
        .invalid(bw_rr_inv), .overflow(bw_rr_ovf),
        .underflow(bw_rr_udf), .inexact(bw_rr_inx)
    );

    falcon_f64_mul u_bw_ii (
        .a(b_im), .b(w_im), .y(bw_ii),
        .invalid(bw_ii_inv), .overflow(bw_ii_ovf),
        .underflow(bw_ii_udf), .inexact(bw_ii_inx)
    );

    falcon_f64_mul u_bw_ri (
        .a(b_re), .b(w_im), .y(bw_ri),
        .invalid(bw_ri_inv), .overflow(bw_ri_ovf),
        .underflow(bw_ri_udf), .inexact(bw_ri_inx)
    );

    falcon_f64_mul u_bw_ir (
        .a(b_im), .b(w_re), .y(bw_ir),
        .invalid(bw_ir_inv), .overflow(bw_ir_ovf),
        .underflow(bw_ir_udf), .inexact(bw_ir_inx)
    );

    falcon_f64_add u_bw_re (
        .a(bw_rr), .b(bw_ii), .sub(1'b1), .y(bw_re),
        .invalid(bw_re_inv), .overflow(bw_re_ovf),
        .underflow(bw_re_udf), .inexact(bw_re_inx)
    );

    falcon_f64_add u_bw_im (
        .a(bw_ri), .b(bw_ir), .sub(1'b0), .y(bw_im),
        .invalid(bw_im_inv), .overflow(bw_im_ovf),
        .underflow(bw_im_udf), .inexact(bw_im_inx)
    );

    falcon_f64_add u_ct_y0_re (
        .a(a_re), .b(bw_re), .sub(1'b0), .y(ct_y0_re),
        .invalid(ct_y0_re_inv), .overflow(ct_y0_re_ovf),
        .underflow(ct_y0_re_udf), .inexact(ct_y0_re_inx)
    );

    falcon_f64_add u_ct_y0_im (
        .a(a_im), .b(bw_im), .sub(1'b0), .y(ct_y0_im),
        .invalid(ct_y0_im_inv), .overflow(ct_y0_im_ovf),
        .underflow(ct_y0_im_udf), .inexact(ct_y0_im_inx)
    );

    falcon_f64_add u_ct_y1_re (
        .a(a_re), .b(bw_re), .sub(1'b1), .y(ct_y1_re),
        .invalid(ct_y1_re_inv), .overflow(ct_y1_re_ovf),
        .underflow(ct_y1_re_udf), .inexact(ct_y1_re_inx)
    );

    falcon_f64_add u_ct_y1_im (
        .a(a_im), .b(bw_im), .sub(1'b1), .y(ct_y1_im),
        .invalid(ct_y1_im_inv), .overflow(ct_y1_im_ovf),
        .underflow(ct_y1_im_udf), .inexact(ct_y1_im_inx)
    );

    falcon_f64_mul u_diffw_rr (
        .a(sub_re), .b(w_re), .y(diffw_rr),
        .invalid(diffw_rr_inv), .overflow(diffw_rr_ovf),
        .underflow(diffw_rr_udf), .inexact(diffw_rr_inx)
    );

    falcon_f64_mul u_diffw_ii (
        .a(sub_im), .b(w_im), .y(diffw_ii),
        .invalid(diffw_ii_inv), .overflow(diffw_ii_ovf),
        .underflow(diffw_ii_udf), .inexact(diffw_ii_inx)
    );

    falcon_f64_mul u_diffw_ri (
        .a(sub_re), .b(w_im), .y(diffw_ri),
        .invalid(diffw_ri_inv), .overflow(diffw_ri_ovf),
        .underflow(diffw_ri_udf), .inexact(diffw_ri_inx)
    );

    falcon_f64_mul u_diffw_ir (
        .a(sub_im), .b(w_re), .y(diffw_ir),
        .invalid(diffw_ir_inv), .overflow(diffw_ir_ovf),
        .underflow(diffw_ir_udf), .inexact(diffw_ir_inx)
    );

    falcon_f64_add u_gs_y1_re (
        .a(diffw_rr), .b(diffw_ii), .sub(1'b1), .y(gs_y1_re),
        .invalid(gs_y1_re_inv), .overflow(gs_y1_re_ovf),
        .underflow(gs_y1_re_udf), .inexact(gs_y1_re_inx)
    );

    falcon_f64_add u_gs_y1_im (
        .a(diffw_ri), .b(diffw_ir), .sub(1'b0), .y(gs_y1_im),
        .invalid(gs_y1_im_inv), .overflow(gs_y1_im_ovf),
        .underflow(gs_y1_im_udf), .inexact(gs_y1_im_inx)
    );

    falcon_f64_add u_mac_re (
        .a(cmul_re), .b(c_re), .sub(1'b0), .y(mac_re),
        .invalid(mac_re_inv), .overflow(mac_re_ovf),
        .underflow(mac_re_udf), .inexact(mac_re_inx)
    );

    falcon_f64_add u_mac_im (
        .a(cmul_im), .b(c_im), .sub(1'b0), .y(mac_im),
        .invalid(mac_im_inv), .overflow(mac_im_ovf),
        .underflow(mac_im_udf), .inexact(mac_im_inx)
    );

    assign any_invalid =
        add_re_inv | add_im_inv | sub_re_inv | sub_im_inv |
        ab_rr_inv | ab_ii_inv | ab_ri_inv | ab_ir_inv |
        cmul_re_inv | cmul_im_inv |
        aa_rr_inv | aa_ii_inv | aa_ri_inv | sqr_re_inv | sqr_im_inv |
        bw_rr_inv | bw_ii_inv | bw_ri_inv | bw_ir_inv |
        bw_re_inv | bw_im_inv |
        ct_y0_re_inv | ct_y0_im_inv | ct_y1_re_inv | ct_y1_im_inv |
        diffw_rr_inv | diffw_ii_inv | diffw_ri_inv | diffw_ir_inv |
        gs_y1_re_inv | gs_y1_im_inv | mac_re_inv | mac_im_inv;

    assign any_overflow =
        add_re_ovf | add_im_ovf | sub_re_ovf | sub_im_ovf |
        ab_rr_ovf | ab_ii_ovf | ab_ri_ovf | ab_ir_ovf |
        cmul_re_ovf | cmul_im_ovf |
        aa_rr_ovf | aa_ii_ovf | aa_ri_ovf | sqr_re_ovf | sqr_im_ovf |
        bw_rr_ovf | bw_ii_ovf | bw_ri_ovf | bw_ir_ovf |
        bw_re_ovf | bw_im_ovf |
        ct_y0_re_ovf | ct_y0_im_ovf | ct_y1_re_ovf | ct_y1_im_ovf |
        diffw_rr_ovf | diffw_ii_ovf | diffw_ri_ovf | diffw_ir_ovf |
        gs_y1_re_ovf | gs_y1_im_ovf | mac_re_ovf | mac_im_ovf;

    assign any_underflow =
        add_re_udf | add_im_udf | sub_re_udf | sub_im_udf |
        ab_rr_udf | ab_ii_udf | ab_ri_udf | ab_ir_udf |
        cmul_re_udf | cmul_im_udf |
        aa_rr_udf | aa_ii_udf | aa_ri_udf | sqr_re_udf | sqr_im_udf |
        bw_rr_udf | bw_ii_udf | bw_ri_udf | bw_ir_udf |
        bw_re_udf | bw_im_udf |
        ct_y0_re_udf | ct_y0_im_udf | ct_y1_re_udf | ct_y1_im_udf |
        diffw_rr_udf | diffw_ii_udf | diffw_ri_udf | diffw_ir_udf |
        gs_y1_re_udf | gs_y1_im_udf | mac_re_udf | mac_im_udf;

    assign any_inexact =
        add_re_inx | add_im_inx | sub_re_inx | sub_im_inx |
        ab_rr_inx | ab_ii_inx | ab_ri_inx | ab_ir_inx |
        cmul_re_inx | cmul_im_inx |
        aa_rr_inx | aa_ii_inx | aa_ri_inx | sqr_re_inx | sqr_im_inx |
        bw_rr_inx | bw_ii_inx | bw_ri_inx | bw_ir_inx |
        bw_re_inx | bw_im_inx |
        ct_y0_re_inx | ct_y0_im_inx | ct_y1_re_inx | ct_y1_im_inx |
        diffw_rr_inx | diffw_ii_inx | diffw_ri_inx | diffw_ir_inx |
        gs_y1_re_inx | gs_y1_im_inx | mac_re_inx | mac_im_inx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out        <= 1'b0;
            y0_re            <= 64'd0;
            y0_im            <= 64'd0;
            y1_re            <= 64'd0;
            y1_im            <= 64'd0;
            status_invalid   <= 1'b0;
            status_overflow  <= 1'b0;
            status_underflow <= 1'b0;
            status_inexact   <= 1'b0;
        end else begin
            valid_out        <= valid_in;
            status_invalid   <= any_invalid;
            status_overflow  <= any_overflow;
            status_underflow <= any_underflow;
            status_inexact   <= any_inexact;

            case (mode)
                FE_MODE_CT_BFU_COMPLEX: begin
                    y0_re <= ct_y0_re;
                    y0_im <= ct_y0_im;
                    y1_re <= ct_y1_re;
                    y1_im <= ct_y1_im;
                end

                FE_MODE_GS_BFU_COMPLEX: begin
                    y0_re <= add_re;
                    y0_im <= add_im;
                    y1_re <= gs_y1_re;
                    y1_im <= gs_y1_im;
                end

                FE_MODE_FLOAT_ADD: begin
                    y0_re <= add_re;
                    y0_im <= 64'd0;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_FLOAT_SUB: begin
                    y0_re <= sub_re;
                    y0_im <= 64'd0;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_FLOAT_MUL: begin
                    y0_re <= ab_rr;
                    y0_im <= 64'd0;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_COMPLEX_ADD: begin
                    y0_re <= add_re;
                    y0_im <= add_im;
                    y1_re <= 64'd0;
                    y1_im <= 64'd0;
                end

                FE_MODE_COMPLEX_SUB: begin
                    y0_re <= sub_re;
                    y0_im <= sub_im;
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
                    y0_re <= sqr_re;
                    y0_im <= sqr_im;
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
