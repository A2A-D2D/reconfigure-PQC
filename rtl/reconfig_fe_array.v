`timescale 1ns/1ps

module reconfig_fe_array #(
    parameter WORD_W = 32,
    parameter FRAC_W = 16,
    parameter MODE_W = 4,
    parameter LANES  = 8
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       valid_in,
    input  wire [MODE_W-1:0]          mode,
    input  wire [(LANES*WORD_W)-1:0]  a_re_vec,
    input  wire [(LANES*WORD_W)-1:0]  a_im_vec,
    input  wire [(LANES*WORD_W)-1:0]  b_re_vec,
    input  wire [(LANES*WORD_W)-1:0]  b_im_vec,
    input  wire [(LANES*WORD_W)-1:0]  c_re_vec,
    input  wire [(LANES*WORD_W)-1:0]  c_im_vec,
    input  wire [(LANES*WORD_W)-1:0]  w_re_vec,
    input  wire [(LANES*WORD_W)-1:0]  w_im_vec,
    output wire                       valid_out,
    output wire [(LANES*WORD_W)-1:0]  y0_re_vec,
    output wire [(LANES*WORD_W)-1:0]  y0_im_vec,
    output wire [(LANES*WORD_W)-1:0]  y1_re_vec,
    output wire [(LANES*WORD_W)-1:0]  y1_im_vec
);

    genvar lane_idx;
    wire [LANES-1:0] lane_valid_out;

    generate
        for (lane_idx = 0; lane_idx < LANES; lane_idx = lane_idx + 1) begin : gen_fe_lane
            reconfig_fe #(
                .WORD_W(WORD_W),
                .FRAC_W(FRAC_W),
                .MODE_W(MODE_W)
            ) u_fe (
                .clk       (clk),
                .rst_n     (rst_n),
                .valid_in  (valid_in),
                .mode      (mode),
                .a_re      (a_re_vec[(lane_idx*WORD_W) +: WORD_W]),
                .a_im      (a_im_vec[(lane_idx*WORD_W) +: WORD_W]),
                .b_re      (b_re_vec[(lane_idx*WORD_W) +: WORD_W]),
                .b_im      (b_im_vec[(lane_idx*WORD_W) +: WORD_W]),
                .c_re      (c_re_vec[(lane_idx*WORD_W) +: WORD_W]),
                .c_im      (c_im_vec[(lane_idx*WORD_W) +: WORD_W]),
                .w_re      (w_re_vec[(lane_idx*WORD_W) +: WORD_W]),
                .w_im      (w_im_vec[(lane_idx*WORD_W) +: WORD_W]),
                .valid_out (lane_valid_out[lane_idx]),
                .y0_re     (y0_re_vec[(lane_idx*WORD_W) +: WORD_W]),
                .y0_im     (y0_im_vec[(lane_idx*WORD_W) +: WORD_W]),
                .y1_re     (y1_re_vec[(lane_idx*WORD_W) +: WORD_W]),
                .y1_im     (y1_im_vec[(lane_idx*WORD_W) +: WORD_W])
            );
        end
    endgenerate

    assign valid_out = lane_valid_out[0];

endmodule
