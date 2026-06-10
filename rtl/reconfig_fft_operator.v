`timescale 1ns/1ps

module reconfig_fft_operator #(
    parameter WORD_W = 32,
    parameter FRAC_W = 16,
    parameter MODE_W = 4,
    parameter LANES  = 8
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       valid_in,
    input  wire                       inverse,
    input  wire [(LANES*WORD_W)-1:0]  va_re_vec,
    input  wire [(LANES*WORD_W)-1:0]  va_im_vec,
    input  wire [(LANES*WORD_W)-1:0]  vb_re_vec,
    input  wire [(LANES*WORD_W)-1:0]  vb_im_vec,
    input  wire [(LANES*WORD_W)-1:0]  tw_re_vec,
    input  wire [(LANES*WORD_W)-1:0]  tw_im_vec,
    output wire                       valid_out,
    output wire [(LANES*WORD_W)-1:0]  va_out_re_vec,
    output wire [(LANES*WORD_W)-1:0]  va_out_im_vec,
    output wire [(LANES*WORD_W)-1:0]  vb_out_re_vec,
    output wire [(LANES*WORD_W)-1:0]  vb_out_im_vec
);

    localparam [MODE_W-1:0] FE_MODE_CT_BFU_COMPLEX = 4'd0;
    localparam [MODE_W-1:0] FE_MODE_GS_BFU_COMPLEX = 4'd1;

    wire [MODE_W-1:0] fe_mode;
    wire [(LANES*WORD_W)-1:0] zero_vec;

    assign fe_mode  = inverse ? FE_MODE_GS_BFU_COMPLEX : FE_MODE_CT_BFU_COMPLEX;
    assign zero_vec = {(LANES*WORD_W){1'b0}};

    reconfig_fe_array #(
        .WORD_W(WORD_W),
        .FRAC_W(FRAC_W),
        .MODE_W(MODE_W),
        .LANES (LANES)
    ) u_fe_array (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .mode      (fe_mode),
        .a_re_vec  (va_re_vec),
        .a_im_vec  (va_im_vec),
        .b_re_vec  (vb_re_vec),
        .b_im_vec  (vb_im_vec),
        .c_re_vec  (zero_vec),
        .c_im_vec  (zero_vec),
        .w_re_vec  (tw_re_vec),
        .w_im_vec  (tw_im_vec),
        .valid_out (valid_out),
        .y0_re_vec (va_out_re_vec),
        .y0_im_vec (va_out_im_vec),
        .y1_re_vec (vb_out_re_vec),
        .y1_im_vec (vb_out_im_vec)
    );

endmodule
