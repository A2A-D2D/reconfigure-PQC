`timescale 1ns/1ps

// Reconfigurable AE Array — 32 fixed arithmetic elements.
//
// Flat 32-lane cluster matching the paper's Arithmetic Cluster.  Each
// lane is explicitly instantiated so that lane-specific wiring (carry
// chains, boundary conditions, heterogeneous mode assignments) can be
// added without fighting a generate loop.
//
// Bit layout (WORD_W=32, MODE_W=3):
//   mode_vec  [95:0]    lane N → bits [N*3+2 : N*3]
//   data_vec  [1023:0]  lane N → bits [N*32+31 : N*32]
//   acc_vec   [2047:0]  lane N → bits [N*64+63 : N*64]

module reconfig_ae_array
(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  valid_in,

    input  wire [95:0]           mode_vec,    // 32 lanes × 3 bit
    input  wire                  use_mod,
    input  wire [31:0]           modulus,
    input  wire [63:0]           mu,
    input  wire [4:0]            k_log2,

    input  wire [1023:0]         a_vec,
    input  wire [1023:0]         b_vec,
    input  wire [1023:0]         c_vec,
    input  wire [1023:0]         w_vec,

    output wire                  valid_out,
    output wire [1023:0]         y0_vec,
    output wire [1023:0]         y1_vec,

    input  wire                  acc_clr,
    output wire [2047:0]         acc_out_vec
);

    localparam WORD_W = 32;
    localparam MODE_W = 3;

    // ── lane valid-out wires ──
    wire v0,  v1,  v2,  v3,  v4,  v5,  v6,  v7;
    wire v8,  v9,  v10, v11, v12, v13, v14, v15;
    wire v16, v17, v18, v19, v20, v21, v22, v23;
    wire v24, v25, v26, v27, v28, v29, v30, v31;

    // ==================================================================
    // Lane  0
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_0 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[  2:  0]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[ 31:  0]), .b(b_vec[ 31:  0]),
        .c(c_vec[ 31:  0]), .w(w_vec[ 31:  0]),
        .valid_out(v0), .y0(y0_vec[ 31:  0]), .y1(y1_vec[ 31:  0]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[ 63:  0])
    );

    // ==================================================================
    // Lane  1
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_1 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[  5:  3]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[ 63: 32]), .b(b_vec[ 63: 32]),
        .c(c_vec[ 63: 32]), .w(w_vec[ 63: 32]),
        .valid_out(v1), .y0(y0_vec[ 63: 32]), .y1(y1_vec[ 63: 32]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[127: 64])
    );

    // ==================================================================
    // Lane  2
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_2 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[  8:  6]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[ 95: 64]), .b(b_vec[ 95: 64]),
        .c(c_vec[ 95: 64]), .w(w_vec[ 95: 64]),
        .valid_out(v2), .y0(y0_vec[ 95: 64]), .y1(y1_vec[ 95: 64]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[191:128])
    );

    // ==================================================================
    // Lane  3
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_3 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 11:  9]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[127: 96]), .b(b_vec[127: 96]),
        .c(c_vec[127: 96]), .w(w_vec[127: 96]),
        .valid_out(v3), .y0(y0_vec[127: 96]), .y1(y1_vec[127: 96]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[255:192])
    );

    // ==================================================================
    // Lane  4
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_4 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 14: 12]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[159:128]), .b(b_vec[159:128]),
        .c(c_vec[159:128]), .w(w_vec[159:128]),
        .valid_out(v4), .y0(y0_vec[159:128]), .y1(y1_vec[159:128]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[319:256])
    );

    // ==================================================================
    // Lane  5
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_5 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 17: 15]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[191:160]), .b(b_vec[191:160]),
        .c(c_vec[191:160]), .w(w_vec[191:160]),
        .valid_out(v5), .y0(y0_vec[191:160]), .y1(y1_vec[191:160]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[383:320])
    );

    // ==================================================================
    // Lane  6
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_6 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 20: 18]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[223:192]), .b(b_vec[223:192]),
        .c(c_vec[223:192]), .w(w_vec[223:192]),
        .valid_out(v6), .y0(y0_vec[223:192]), .y1(y1_vec[223:192]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[447:384])
    );

    // ==================================================================
    // Lane  7
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_7 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 23: 21]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[255:224]), .b(b_vec[255:224]),
        .c(c_vec[255:224]), .w(w_vec[255:224]),
        .valid_out(v7), .y0(y0_vec[255:224]), .y1(y1_vec[255:224]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[511:448])
    );

    // ==================================================================
    // Lane  8
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_8 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 26: 24]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[287:256]), .b(b_vec[287:256]),
        .c(c_vec[287:256]), .w(w_vec[287:256]),
        .valid_out(v8), .y0(y0_vec[287:256]), .y1(y1_vec[287:256]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[575:512])
    );

    // ==================================================================
    // Lane  9
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_9 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 29: 27]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[319:288]), .b(b_vec[319:288]),
        .c(c_vec[319:288]), .w(w_vec[319:288]),
        .valid_out(v9), .y0(y0_vec[319:288]), .y1(y1_vec[319:288]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[639:576])
    );

    // ==================================================================
    // Lane 10
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_10 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 32: 30]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[351:320]), .b(b_vec[351:320]),
        .c(c_vec[351:320]), .w(w_vec[351:320]),
        .valid_out(v10), .y0(y0_vec[351:320]), .y1(y1_vec[351:320]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[703:640])
    );

    // ==================================================================
    // Lane 11
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_11 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 35: 33]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[383:352]), .b(b_vec[383:352]),
        .c(c_vec[383:352]), .w(w_vec[383:352]),
        .valid_out(v11), .y0(y0_vec[383:352]), .y1(y1_vec[383:352]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[767:704])
    );

    // ==================================================================
    // Lane 12
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_12 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 38: 36]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[415:384]), .b(b_vec[415:384]),
        .c(c_vec[415:384]), .w(w_vec[415:384]),
        .valid_out(v12), .y0(y0_vec[415:384]), .y1(y1_vec[415:384]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[831:768])
    );

    // ==================================================================
    // Lane 13
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_13 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 41: 39]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[447:416]), .b(b_vec[447:416]),
        .c(c_vec[447:416]), .w(w_vec[447:416]),
        .valid_out(v13), .y0(y0_vec[447:416]), .y1(y1_vec[447:416]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[895:832])
    );

    // ==================================================================
    // Lane 14
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_14 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 44: 42]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[479:448]), .b(b_vec[479:448]),
        .c(c_vec[479:448]), .w(w_vec[479:448]),
        .valid_out(v14), .y0(y0_vec[479:448]), .y1(y1_vec[479:448]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[959:896])
    );

    // ==================================================================
    // Lane 15
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_15 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 47: 45]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[511:480]), .b(b_vec[511:480]),
        .c(c_vec[511:480]), .w(w_vec[511:480]),
        .valid_out(v15), .y0(y0_vec[511:480]), .y1(y1_vec[511:480]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1023:960])
    );

    // ==================================================================
    // Lane 16
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_16 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 50: 48]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[543:512]), .b(b_vec[543:512]),
        .c(c_vec[543:512]), .w(w_vec[543:512]),
        .valid_out(v16), .y0(y0_vec[543:512]), .y1(y1_vec[543:512]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1087:1024])
    );

    // ==================================================================
    // Lane 17
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_17 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 53: 51]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[575:544]), .b(b_vec[575:544]),
        .c(c_vec[575:544]), .w(w_vec[575:544]),
        .valid_out(v17), .y0(y0_vec[575:544]), .y1(y1_vec[575:544]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1151:1088])
    );

    // ==================================================================
    // Lane 18
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_18 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 56: 54]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[607:576]), .b(b_vec[607:576]),
        .c(c_vec[607:576]), .w(w_vec[607:576]),
        .valid_out(v18), .y0(y0_vec[607:576]), .y1(y1_vec[607:576]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1215:1152])
    );

    // ==================================================================
    // Lane 19
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_19 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 59: 57]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[639:608]), .b(b_vec[639:608]),
        .c(c_vec[639:608]), .w(w_vec[639:608]),
        .valid_out(v19), .y0(y0_vec[639:608]), .y1(y1_vec[639:608]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1279:1216])
    );

    // ==================================================================
    // Lane 20
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_20 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 62: 60]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[671:640]), .b(b_vec[671:640]),
        .c(c_vec[671:640]), .w(w_vec[671:640]),
        .valid_out(v20), .y0(y0_vec[671:640]), .y1(y1_vec[671:640]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1343:1280])
    );

    // ==================================================================
    // Lane 21
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_21 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 65: 63]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[703:672]), .b(b_vec[703:672]),
        .c(c_vec[703:672]), .w(w_vec[703:672]),
        .valid_out(v21), .y0(y0_vec[703:672]), .y1(y1_vec[703:672]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1407:1344])
    );

    // ==================================================================
    // Lane 22
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_22 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 68: 66]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[735:704]), .b(b_vec[735:704]),
        .c(c_vec[735:704]), .w(w_vec[735:704]),
        .valid_out(v22), .y0(y0_vec[735:704]), .y1(y1_vec[735:704]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1471:1408])
    );

    // ==================================================================
    // Lane 23
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_23 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 71: 69]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[767:736]), .b(b_vec[767:736]),
        .c(c_vec[767:736]), .w(w_vec[767:736]),
        .valid_out(v23), .y0(y0_vec[767:736]), .y1(y1_vec[767:736]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1535:1472])
    );

    // ==================================================================
    // Lane 24
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_24 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 74: 72]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[799:768]), .b(b_vec[799:768]),
        .c(c_vec[799:768]), .w(w_vec[799:768]),
        .valid_out(v24), .y0(y0_vec[799:768]), .y1(y1_vec[799:768]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1599:1536])
    );

    // ==================================================================
    // Lane 25
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_25 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 77: 75]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[831:800]), .b(b_vec[831:800]),
        .c(c_vec[831:800]), .w(w_vec[831:800]),
        .valid_out(v25), .y0(y0_vec[831:800]), .y1(y1_vec[831:800]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1663:1600])
    );

    // ==================================================================
    // Lane 26
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_26 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 80: 78]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[863:832]), .b(b_vec[863:832]),
        .c(c_vec[863:832]), .w(w_vec[863:832]),
        .valid_out(v26), .y0(y0_vec[863:832]), .y1(y1_vec[863:832]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1727:1664])
    );

    // ==================================================================
    // Lane 27
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_27 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 83: 81]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[895:864]), .b(b_vec[895:864]),
        .c(c_vec[895:864]), .w(w_vec[895:864]),
        .valid_out(v27), .y0(y0_vec[895:864]), .y1(y1_vec[895:864]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1791:1728])
    );

    // ==================================================================
    // Lane 28
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_28 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 86: 84]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[927:896]), .b(b_vec[927:896]),
        .c(c_vec[927:896]), .w(w_vec[927:896]),
        .valid_out(v28), .y0(y0_vec[927:896]), .y1(y1_vec[927:896]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1855:1792])
    );

    // ==================================================================
    // Lane 29
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_29 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 89: 87]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[959:928]), .b(b_vec[959:928]),
        .c(c_vec[959:928]), .w(w_vec[959:928]),
        .valid_out(v29), .y0(y0_vec[959:928]), .y1(y1_vec[959:928]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1919:1856])
    );

    // ==================================================================
    // Lane 30
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_30 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 92: 90]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[991:960]), .b(b_vec[991:960]),
        .c(c_vec[991:960]), .w(w_vec[991:960]),
        .valid_out(v30), .y0(y0_vec[991:960]), .y1(y1_vec[991:960]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[1983:1920])
    );

    // ==================================================================
    // Lane 31
    // ==================================================================
    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae_31 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .mode   (mode_vec[ 95: 93]), .use_mod(use_mod), .modulus(modulus),
        .mu(mu), .k_log2(k_log2),
        .a(a_vec[1023:992]), .b(b_vec[1023:992]),
        .c(c_vec[1023:992]), .w(w_vec[1023:992]),
        .valid_out(v31), .y0(y0_vec[1023:992]), .y1(y1_vec[1023:992]),
        .acc_clr(acc_clr), .acc_out(acc_out_vec[2047:1984])
    );

    // ── array-level valid (lane 0 drives it) ──
    assign valid_out = v0;

endmodule
