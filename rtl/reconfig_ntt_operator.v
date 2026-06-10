`timescale 1ns/1ps

module reconfig_ntt_operator (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          valid_in,
    input  wire          inverse,
    input  wire          use_mod,
    input  wire          acc_clr,
    input  wire [31:0]   modulus,
    input  wire [63:0]   mu,
    input  wire [31:0]   mu_mont,
    input  wire [4:0]    k_log2,
    input  wire [1023:0] va_vec,
    input  wire [1023:0] vb_vec,
    input  wire [1023:0] twiddle_vec,
    output wire          valid_out,
    output wire [1023:0] va_out_vec,
    output wire [1023:0] vb_out_vec,
    output wire [2047:0] acc_out_vec
);

    localparam [3:0] AE_MODE_CT_BFU = 4'd0;
    localparam [3:0] AE_MODE_GS_BFU = 4'd1;

    wire [3:0]    lane_mode;
    wire [127:0]  mode_vec;
    wire [1023:0] zero_vec;

    assign lane_mode = inverse ? AE_MODE_GS_BFU : AE_MODE_CT_BFU;
    assign mode_vec  = {32{lane_mode}};
    assign zero_vec  = 1024'd0;

    reconfig_ae_array u_ae_array (
        .clk         (clk),
        .rst_n       (rst_n),
        .valid_in    (valid_in),
        .mode_vec    (mode_vec),
        .use_mod     (use_mod),
        .modulus     (modulus),
        .mu          (mu),
        .mu_mont     (mu_mont),
        .k_log2      (k_log2),
        .a_vec       (va_vec),
        .b_vec       (vb_vec),
        .c_vec       (zero_vec),
        .w_vec       (twiddle_vec),
        .valid_out   (valid_out),
        .y0_vec      (va_out_vec),
        .y1_vec      (vb_out_vec),
        .acc_clr     (acc_clr),
        .acc_out_vec (acc_out_vec)
    );

endmodule
