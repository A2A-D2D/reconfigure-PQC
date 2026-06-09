`timescale 1ns/1ps

module reconfig_ae_array #(
    parameter WORD_W = 32,
    parameter MODE_W = 3,
    parameter LANES  = 32
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         valid_in,
    input  wire [MODE_W-1:0]            mode,
    input  wire                         use_mod,
    input  wire [WORD_W-1:0]            modulus,
    input  wire [(2*WORD_W)-1:0]        mu,          // Barrett constant
    input  wire [(LANES*WORD_W)-1:0]    a_vec,
    input  wire [(LANES*WORD_W)-1:0]    b_vec,
    input  wire [(LANES*WORD_W)-1:0]    c_vec,
    input  wire [(LANES*WORD_W)-1:0]    w_vec,
    output wire                         valid_out,
    output wire [(LANES*WORD_W)-1:0]    y0_vec,
    output wire [(LANES*WORD_W)-1:0]    y1_vec
);

    genvar lane_idx;
    wire [LANES-1:0] lane_valid_out;

    generate
        for (lane_idx = 0; lane_idx < LANES; lane_idx = lane_idx + 1) begin : gen_ae_lane
            reconfig_ae #(
                .WORD_W(WORD_W),
                .MODE_W(MODE_W)
            ) u_ae (
                .clk       (clk),
                .rst_n     (rst_n),
                .valid_in  (valid_in),
                .mode      (mode),
                .use_mod   (use_mod),
                .modulus   (modulus),
                .mu        (mu),
                .a         (a_vec[(lane_idx*WORD_W) +: WORD_W]),
                .b         (b_vec[(lane_idx*WORD_W) +: WORD_W]),
                .c         (c_vec[(lane_idx*WORD_W) +: WORD_W]),
                .w         (w_vec[(lane_idx*WORD_W) +: WORD_W]),
                .valid_out (lane_valid_out[lane_idx]),
                .y0        (y0_vec[(lane_idx*WORD_W) +: WORD_W]),
                .y1        (y1_vec[(lane_idx*WORD_W) +: WORD_W])
            );
        end
    endgenerate

    assign valid_out = lane_valid_out[0];

endmodule
