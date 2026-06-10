`timescale 1ns/1ps

module reconfig_fe #(
    parameter WORD_W = 32,
    parameter FRAC_W = 16,
    parameter MODE_W = 4
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      valid_in,
    input  wire [MODE_W-1:0]         mode,
    input  wire signed [WORD_W-1:0]  a_re,
    input  wire signed [WORD_W-1:0]  a_im,
    input  wire signed [WORD_W-1:0]  b_re,
    input  wire signed [WORD_W-1:0]  b_im,
    input  wire signed [WORD_W-1:0]  c_re,
    input  wire signed [WORD_W-1:0]  c_im,
    input  wire signed [WORD_W-1:0]  w_re,
    input  wire signed [WORD_W-1:0]  w_im,
    output reg                       valid_out,
    output reg signed [WORD_W-1:0]   y0_re,
    output reg signed [WORD_W-1:0]   y0_im,
    output reg signed [WORD_W-1:0]   y1_re,
    output reg signed [WORD_W-1:0]   y1_im
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

    reg valid_s0;
    reg valid_s1;
    reg valid_s2;
    reg [MODE_W-1:0] mode_s0;
    reg [MODE_W-1:0] mode_s1;
    reg [MODE_W-1:0] mode_s2;

    reg signed [WORD_W-1:0] a_re_s0;
    reg signed [WORD_W-1:0] a_im_s0;
    reg signed [WORD_W-1:0] b_re_s0;
    reg signed [WORD_W-1:0] b_im_s0;
    reg signed [WORD_W-1:0] c_re_s0;
    reg signed [WORD_W-1:0] c_im_s0;
    reg signed [WORD_W-1:0] w_re_s0;
    reg signed [WORD_W-1:0] w_im_s0;

    reg signed [WORD_W-1:0] a_re_s1;
    reg signed [WORD_W-1:0] a_im_s1;
    reg signed [WORD_W-1:0] c_re_s1;
    reg signed [WORD_W-1:0] c_im_s1;

    reg signed [WORD_W-1:0] add_re_s1;
    reg signed [WORD_W-1:0] add_im_s1;
    reg signed [WORD_W-1:0] sub_re_s1;
    reg signed [WORD_W-1:0] sub_im_s1;

    reg signed [(2*WORD_W)-1:0] ab_rr_s1;
    reg signed [(2*WORD_W)-1:0] ab_ii_s1;
    reg signed [(2*WORD_W)-1:0] ab_ri_s1;
    reg signed [(2*WORD_W)-1:0] ab_ir_s1;
    reg signed [(2*WORD_W)-1:0] aa_rr_s1;
    reg signed [(2*WORD_W)-1:0] aa_ii_s1;
    reg signed [(2*WORD_W)-1:0] aa_ri_s1;
    reg signed [(2*WORD_W)-1:0] bw_rr_s1;
    reg signed [(2*WORD_W)-1:0] bw_ii_s1;
    reg signed [(2*WORD_W)-1:0] bw_ri_s1;
    reg signed [(2*WORD_W)-1:0] bw_ir_s1;
    reg signed [(2*WORD_W)-1:0] subw_rr_s1;
    reg signed [(2*WORD_W)-1:0] subw_ii_s1;
    reg signed [(2*WORD_W)-1:0] subw_ri_s1;
    reg signed [(2*WORD_W)-1:0] subw_ir_s1;

    reg signed [WORD_W-1:0] a_re_s2;
    reg signed [WORD_W-1:0] a_im_s2;
    reg signed [WORD_W-1:0] c_re_s2;
    reg signed [WORD_W-1:0] c_im_s2;
    reg signed [WORD_W-1:0] add_re_s2;
    reg signed [WORD_W-1:0] add_im_s2;
    reg signed [WORD_W-1:0] sub_re_s2;
    reg signed [WORD_W-1:0] sub_im_s2;
    reg signed [(2*WORD_W)-1:0] ab_rr_s2;
    reg signed [(2*WORD_W)-1:0] ab_ii_s2;
    reg signed [(2*WORD_W)-1:0] ab_ri_s2;
    reg signed [(2*WORD_W)-1:0] ab_ir_s2;
    reg signed [(2*WORD_W)-1:0] aa_rr_s2;
    reg signed [(2*WORD_W)-1:0] aa_ii_s2;
    reg signed [(2*WORD_W)-1:0] aa_ri_s2;
    reg signed [(2*WORD_W)-1:0] bw_rr_s2;
    reg signed [(2*WORD_W)-1:0] bw_ii_s2;
    reg signed [(2*WORD_W)-1:0] bw_ri_s2;
    reg signed [(2*WORD_W)-1:0] bw_ir_s2;
    reg signed [(2*WORD_W)-1:0] subw_rr_s2;
    reg signed [(2*WORD_W)-1:0] subw_ii_s2;
    reg signed [(2*WORD_W)-1:0] subw_ri_s2;
    reg signed [(2*WORD_W)-1:0] subw_ir_s2;

    function signed [WORD_W-1:0] scale_product;
        input signed [(2*WORD_W)-1:0] value;
        reg signed [(2*WORD_W)-1:0] shifted;
        begin
            shifted = value >>> FRAC_W;
            scale_product = shifted[WORD_W-1:0];
        end
    endfunction

    function signed [WORD_W-1:0] complex_mul_re;
        input signed [(2*WORD_W)-1:0] rr;
        input signed [(2*WORD_W)-1:0] ii;
        begin
            complex_mul_re = scale_product(rr - ii);
        end
    endfunction

    function signed [WORD_W-1:0] complex_mul_im;
        input signed [(2*WORD_W)-1:0] ri;
        input signed [(2*WORD_W)-1:0] ir;
        begin
            complex_mul_im = scale_product(ri + ir);
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            valid_s0 <= 1'b0;
            mode_s0  <= {MODE_W{1'b0}};
            a_re_s0  <= {WORD_W{1'b0}};
            a_im_s0  <= {WORD_W{1'b0}};
            b_re_s0  <= {WORD_W{1'b0}};
            b_im_s0  <= {WORD_W{1'b0}};
            c_re_s0  <= {WORD_W{1'b0}};
            c_im_s0  <= {WORD_W{1'b0}};
            w_re_s0  <= {WORD_W{1'b0}};
            w_im_s0  <= {WORD_W{1'b0}};
        end else begin
            valid_s0 <= valid_in;
            mode_s0  <= mode;
            a_re_s0  <= a_re;
            a_im_s0  <= a_im;
            b_re_s0  <= b_re;
            b_im_s0  <= b_im;
            c_re_s0  <= c_re;
            c_im_s0  <= c_im;
            w_re_s0  <= w_re;
            w_im_s0  <= w_im;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            valid_s1 <= 1'b0;
            mode_s1  <= {MODE_W{1'b0}};
            a_re_s1  <= {WORD_W{1'b0}};
            a_im_s1  <= {WORD_W{1'b0}};
            c_re_s1  <= {WORD_W{1'b0}};
            c_im_s1  <= {WORD_W{1'b0}};
            add_re_s1 <= {WORD_W{1'b0}};
            add_im_s1 <= {WORD_W{1'b0}};
            sub_re_s1 <= {WORD_W{1'b0}};
            sub_im_s1 <= {WORD_W{1'b0}};
            ab_rr_s1 <= {(2*WORD_W){1'b0}};
            ab_ii_s1 <= {(2*WORD_W){1'b0}};
            ab_ri_s1 <= {(2*WORD_W){1'b0}};
            ab_ir_s1 <= {(2*WORD_W){1'b0}};
            aa_rr_s1 <= {(2*WORD_W){1'b0}};
            aa_ii_s1 <= {(2*WORD_W){1'b0}};
            aa_ri_s1 <= {(2*WORD_W){1'b0}};
            bw_rr_s1 <= {(2*WORD_W){1'b0}};
            bw_ii_s1 <= {(2*WORD_W){1'b0}};
            bw_ri_s1 <= {(2*WORD_W){1'b0}};
            bw_ir_s1 <= {(2*WORD_W){1'b0}};
            subw_rr_s1 <= {(2*WORD_W){1'b0}};
            subw_ii_s1 <= {(2*WORD_W){1'b0}};
            subw_ri_s1 <= {(2*WORD_W){1'b0}};
            subw_ir_s1 <= {(2*WORD_W){1'b0}};
        end else begin
            valid_s1 <= valid_s0;
            mode_s1  <= mode_s0;
            a_re_s1  <= a_re_s0;
            a_im_s1  <= a_im_s0;
            c_re_s1  <= c_re_s0;
            c_im_s1  <= c_im_s0;
            add_re_s1 <= a_re_s0 + b_re_s0;
            add_im_s1 <= a_im_s0 + b_im_s0;
            sub_re_s1 <= a_re_s0 - b_re_s0;
            sub_im_s1 <= a_im_s0 - b_im_s0;
            ab_rr_s1 <= a_re_s0 * b_re_s0;
            ab_ii_s1 <= a_im_s0 * b_im_s0;
            ab_ri_s1 <= a_re_s0 * b_im_s0;
            ab_ir_s1 <= a_im_s0 * b_re_s0;
            aa_rr_s1 <= a_re_s0 * a_re_s0;
            aa_ii_s1 <= a_im_s0 * a_im_s0;
            aa_ri_s1 <= a_re_s0 * a_im_s0;
            bw_rr_s1 <= b_re_s0 * w_re_s0;
            bw_ii_s1 <= b_im_s0 * w_im_s0;
            bw_ri_s1 <= b_re_s0 * w_im_s0;
            bw_ir_s1 <= b_im_s0 * w_re_s0;
            subw_rr_s1 <= (a_re_s0 - b_re_s0) * w_re_s0;
            subw_ii_s1 <= (a_im_s0 - b_im_s0) * w_im_s0;
            subw_ri_s1 <= (a_re_s0 - b_re_s0) * w_im_s0;
            subw_ir_s1 <= (a_im_s0 - b_im_s0) * w_re_s0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            valid_s2 <= 1'b0;
            mode_s2  <= {MODE_W{1'b0}};
            a_re_s2  <= {WORD_W{1'b0}};
            a_im_s2  <= {WORD_W{1'b0}};
            c_re_s2  <= {WORD_W{1'b0}};
            c_im_s2  <= {WORD_W{1'b0}};
            add_re_s2 <= {WORD_W{1'b0}};
            add_im_s2 <= {WORD_W{1'b0}};
            sub_re_s2 <= {WORD_W{1'b0}};
            sub_im_s2 <= {WORD_W{1'b0}};
            ab_rr_s2 <= {(2*WORD_W){1'b0}};
            ab_ii_s2 <= {(2*WORD_W){1'b0}};
            ab_ri_s2 <= {(2*WORD_W){1'b0}};
            ab_ir_s2 <= {(2*WORD_W){1'b0}};
            aa_rr_s2 <= {(2*WORD_W){1'b0}};
            aa_ii_s2 <= {(2*WORD_W){1'b0}};
            aa_ri_s2 <= {(2*WORD_W){1'b0}};
            bw_rr_s2 <= {(2*WORD_W){1'b0}};
            bw_ii_s2 <= {(2*WORD_W){1'b0}};
            bw_ri_s2 <= {(2*WORD_W){1'b0}};
            bw_ir_s2 <= {(2*WORD_W){1'b0}};
            subw_rr_s2 <= {(2*WORD_W){1'b0}};
            subw_ii_s2 <= {(2*WORD_W){1'b0}};
            subw_ri_s2 <= {(2*WORD_W){1'b0}};
            subw_ir_s2 <= {(2*WORD_W){1'b0}};
        end else begin
            valid_s2 <= valid_s1;
            mode_s2  <= mode_s1;
            a_re_s2  <= a_re_s1;
            a_im_s2  <= a_im_s1;
            c_re_s2  <= c_re_s1;
            c_im_s2  <= c_im_s1;
            add_re_s2 <= add_re_s1;
            add_im_s2 <= add_im_s1;
            sub_re_s2 <= sub_re_s1;
            sub_im_s2 <= sub_im_s1;
            ab_rr_s2 <= ab_rr_s1;
            ab_ii_s2 <= ab_ii_s1;
            ab_ri_s2 <= ab_ri_s1;
            ab_ir_s2 <= ab_ir_s1;
            aa_rr_s2 <= aa_rr_s1;
            aa_ii_s2 <= aa_ii_s1;
            aa_ri_s2 <= aa_ri_s1;
            bw_rr_s2 <= bw_rr_s1;
            bw_ii_s2 <= bw_ii_s1;
            bw_ri_s2 <= bw_ri_s1;
            bw_ir_s2 <= bw_ir_s1;
            subw_rr_s2 <= subw_rr_s1;
            subw_ii_s2 <= subw_ii_s1;
            subw_ri_s2 <= subw_ri_s1;
            subw_ir_s2 <= subw_ir_s1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            valid_out <= 1'b0;
            y0_re <= {WORD_W{1'b0}};
            y0_im <= {WORD_W{1'b0}};
            y1_re <= {WORD_W{1'b0}};
            y1_im <= {WORD_W{1'b0}};
        end else begin
            valid_out <= valid_s2;
            case (mode_s2)
                FE_MODE_CT_BFU_COMPLEX: begin
                    y0_re <= a_re_s2 + complex_mul_re(bw_rr_s2, bw_ii_s2);
                    y0_im <= a_im_s2 + complex_mul_im(bw_ri_s2, bw_ir_s2);
                    y1_re <= a_re_s2 - complex_mul_re(bw_rr_s2, bw_ii_s2);
                    y1_im <= a_im_s2 - complex_mul_im(bw_ri_s2, bw_ir_s2);
                end
                FE_MODE_GS_BFU_COMPLEX: begin
                    y0_re <= add_re_s2;
                    y0_im <= add_im_s2;
                    y1_re <= complex_mul_re(subw_rr_s2, subw_ii_s2);
                    y1_im <= complex_mul_im(subw_ri_s2, subw_ir_s2);
                end
                FE_MODE_FLOAT_ADD: begin
                    y0_re <= add_re_s2;
                    y0_im <= {WORD_W{1'b0}};
                    y1_re <= {WORD_W{1'b0}};
                    y1_im <= {WORD_W{1'b0}};
                end
                FE_MODE_FLOAT_SUB: begin
                    y0_re <= sub_re_s2;
                    y0_im <= {WORD_W{1'b0}};
                    y1_re <= {WORD_W{1'b0}};
                    y1_im <= {WORD_W{1'b0}};
                end
                FE_MODE_FLOAT_MUL: begin
                    y0_re <= scale_product(ab_rr_s2);
                    y0_im <= {WORD_W{1'b0}};
                    y1_re <= {WORD_W{1'b0}};
                    y1_im <= {WORD_W{1'b0}};
                end
                FE_MODE_COMPLEX_ADD: begin
                    y0_re <= add_re_s2;
                    y0_im <= add_im_s2;
                    y1_re <= {WORD_W{1'b0}};
                    y1_im <= {WORD_W{1'b0}};
                end
                FE_MODE_COMPLEX_SUB: begin
                    y0_re <= sub_re_s2;
                    y0_im <= sub_im_s2;
                    y1_re <= {WORD_W{1'b0}};
                    y1_im <= {WORD_W{1'b0}};
                end
                FE_MODE_COMPLEX_MUL: begin
                    y0_re <= complex_mul_re(ab_rr_s2, ab_ii_s2);
                    y0_im <= complex_mul_im(ab_ri_s2, ab_ir_s2);
                    y1_re <= {WORD_W{1'b0}};
                    y1_im <= {WORD_W{1'b0}};
                end
                FE_MODE_COMPLEX_SQR: begin
                    y0_re <= complex_mul_re(aa_rr_s2, aa_ii_s2);
                    y0_im <= scale_product(aa_ri_s2 <<< 1);
                    y1_re <= {WORD_W{1'b0}};
                    y1_im <= {WORD_W{1'b0}};
                end
                FE_MODE_COMPLEX_MAC: begin
                    y0_re <= complex_mul_re(ab_rr_s2, ab_ii_s2) + c_re_s2;
                    y0_im <= complex_mul_im(ab_ri_s2, ab_ir_s2) + c_im_s2;
                    y1_re <= complex_mul_re(ab_rr_s2, ab_ii_s2);
                    y1_im <= complex_mul_im(ab_ri_s2, ab_ir_s2);
                end
                default: begin
                    y0_re <= {WORD_W{1'b0}};
                    y0_im <= {WORD_W{1'b0}};
                    y1_re <= {WORD_W{1'b0}};
                    y1_im <= {WORD_W{1'b0}};
                end
            endcase
        end
    end

endmodule
