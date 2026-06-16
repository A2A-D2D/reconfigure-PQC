`timescale 1ns/1ps
// ============================================================================
// Module: vpu_fe_unit
// ============================================================================
// Purpose:
//   Low-area VPU-facing wrapper for the Falcon f64 FE path.  This first
//   integration version avoids a full local FFT buffer and avoids adding
//   multiple VPU writeback ports.  It accepts one 320-bit vector command,
//   stores the four 320-bit FE result vectors internally, and returns one
//   selected result vector per READ command.
//
// Command model:
//   CMD_START    : start one FE vector operation.
//                  operand_a_i -> a_re_vec
//                  operand_b_i -> a_im_vec
//                  operand_c_i -> b_re_vec
//                  operand_d_i -> b_im_vec
//                  operand_e_i -> w_re_vec
//                  tw_im_hold  -> w_im_vec
//   CMD_LOAD_WIM : load operand_e_i into the internal w_im hold register.
//   CMD_READ     : return one held result selected by cmd_read_sel_i.
//   CMD_CLEAR    : clear the held-result valid bit and response state.
//
// This module is intended to sit inside vpu_exu behind the VPU operator decode.
// The surrounding vpu_exu adapter should map cmd_ready_o to stall_o and map
// rsp_valid_o/rsp_data_o to done_o/result_o for READ commands.
// ============================================================================

module vpu_fe_unit #(
    parameter VMASK_USE_BITMASK = 0,
    parameter FE_LATENCY        = 1
) (
    input                  clk,
    input                  rst_n,

    input                  cmd_valid_i,
    output                 cmd_ready_o,
    input      [1:0]       cmd_op_i,
    input      [3:0]       cmd_mode_i,
    input      [1:0]       cmd_read_sel_i,
    input      [31:0]      cmd_vmask_i,

    input      [319:0]     operand_a_i,
    input      [319:0]     operand_b_i,
    input      [319:0]     operand_c_i,
    input      [319:0]     operand_d_i,
    input      [319:0]     operand_e_i,

    output reg             rsp_valid_o,
    input                  rsp_ready_i,
    output reg [319:0]     rsp_data_o,
    output reg [1:0]       rsp_sel_o,
    output     [3:0]       rsp_flags_o,

    output                 busy_o,
    output reg             result_valid_o
);

    localparam LANES = 5;
    localparam IDX_W = 3;

    localparam [1:0] CMD_START    = 2'd0;
    localparam [1:0] CMD_LOAD_WIM = 2'd1;
    localparam [1:0] CMD_READ     = 2'd2;
    localparam [1:0] CMD_CLEAR    = 2'd3;

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_WAIT = 2'd1;

    reg [1:0]   state;
    reg         fe_valid_in;
    reg [3:0]   mode_hold;
    reg [4:0]   lane_mask_hold;
    reg [319:0] a_re_hold;
    reg [319:0] a_im_hold;
    reg [319:0] b_re_hold;
    reg [319:0] b_im_hold;
    reg [319:0] c_re_hold;
    reg [319:0] c_im_hold;
    reg [319:0] w_re_hold;
    reg [319:0] w_im_hold;
    reg [319:0] y0_re_hold;
    reg [319:0] y0_im_hold;
    reg [319:0] y1_re_hold;
    reg [319:0] y1_im_hold;
    reg         flag_invalid_hold;
    reg         flag_overflow_hold;
    reg         flag_underflow_hold;
    reg         flag_inexact_hold;

    reg [4:0] fe_lane_mask;
    integer lane_i;

    wire can_update_rsp;
    wire start_ready;
    wire load_wim_ready;
    wire read_ready;
    wire clear_ready;
    wire fe_busy;
    wire fe_valid_out;
    wire [319:0] fe_y0_re;
    wire [319:0] fe_y0_im;
    wire [319:0] fe_y1_re;
    wire [319:0] fe_y1_im;
    wire fe_invalid;
    wire fe_overflow;
    wire fe_underflow;
    wire fe_inexact;

    function [319:0] mask_vec;
        input [319:0] vec;
        input [4:0]   mask;
        integer mask_i;
        begin
            mask_vec = 320'd0;
            for (mask_i = 0; mask_i < LANES; mask_i = mask_i + 1) begin
                if (mask[mask_i]) begin
                    mask_vec[mask_i*64 +: 64] = vec[mask_i*64 +: 64];
                end
            end
        end
    endfunction

    assign can_update_rsp = (!rsp_valid_o) || rsp_ready_i;
    assign start_ready    = (state == ST_IDLE) && (!result_valid_o) &&
                            (!rsp_valid_o);
    assign load_wim_ready = (state == ST_IDLE);
    assign read_ready     = result_valid_o && can_update_rsp;
    assign clear_ready    = (state == ST_IDLE);

    assign cmd_ready_o =
        (cmd_op_i == CMD_START)    ? start_ready :
        (cmd_op_i == CMD_LOAD_WIM) ? load_wim_ready :
        (cmd_op_i == CMD_READ)     ? read_ready :
                                     clear_ready;

    assign busy_o = (state != ST_IDLE) || fe_busy;
    assign rsp_flags_o = {flag_invalid_hold, flag_overflow_hold,
                          flag_underflow_hold, flag_inexact_hold};

    always @(*) begin
        fe_lane_mask = 5'b00000;
        for (lane_i = 0; lane_i < LANES; lane_i = lane_i + 1) begin
            if (VMASK_USE_BITMASK != 0) begin
                fe_lane_mask[lane_i] =
                    cmd_vmask_i[lane_i*2] & cmd_vmask_i[lane_i*2 + 1];
            end else begin
                fe_lane_mask[lane_i] =
                    (cmd_vmask_i[4:0] >= ((lane_i + 1) * 2));
            end
        end
    end

    reconfig_fe_f64_shared_array #(
        .LANES(LANES),
        .MODE_W(4),
        .IDX_W(IDX_W),
        .FE_LATENCY(FE_LATENCY)
    ) u_shared_fe (
        .clk              (clk),
        .rst_n            (rst_n),
        .valid_in         (fe_valid_in),
        .ready_in         (1'b1),
        .lane_mask        (lane_mask_hold),
        .mode             (mode_hold),
        .a_re_vec         (a_re_hold),
        .a_im_vec         (a_im_hold),
        .b_re_vec         (b_re_hold),
        .b_im_vec         (b_im_hold),
        .c_re_vec         (c_re_hold),
        .c_im_vec         (c_im_hold),
        .w_re_vec         (w_re_hold),
        .w_im_vec         (w_im_hold),
        .busy             (fe_busy),
        .valid_out        (fe_valid_out),
        .y0_re_vec        (fe_y0_re),
        .y0_im_vec        (fe_y0_im),
        .y1_re_vec        (fe_y1_re),
        .y1_im_vec        (fe_y1_im),
        .status_invalid   (fe_invalid),
        .status_overflow  (fe_overflow),
        .status_underflow (fe_underflow),
        .status_inexact   (fe_inexact)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= ST_IDLE;
            fe_valid_in         <= 1'b0;
            mode_hold           <= 4'd0;
            lane_mask_hold      <= 5'd0;
            a_re_hold           <= 320'd0;
            a_im_hold           <= 320'd0;
            b_re_hold           <= 320'd0;
            b_im_hold           <= 320'd0;
            c_re_hold           <= 320'd0;
            c_im_hold           <= 320'd0;
            w_re_hold           <= 320'd0;
            w_im_hold           <= 320'd0;
            y0_re_hold          <= 320'd0;
            y0_im_hold          <= 320'd0;
            y1_re_hold          <= 320'd0;
            y1_im_hold          <= 320'd0;
            flag_invalid_hold   <= 1'b0;
            flag_overflow_hold  <= 1'b0;
            flag_underflow_hold <= 1'b0;
            flag_inexact_hold   <= 1'b0;
            rsp_valid_o         <= 1'b0;
            rsp_data_o          <= 320'd0;
            rsp_sel_o           <= 2'd0;
            result_valid_o      <= 1'b0;
        end else begin
            fe_valid_in <= 1'b0;

            if (rsp_valid_o && rsp_ready_i) begin
                rsp_valid_o <= 1'b0;
            end

            if (cmd_valid_i && cmd_ready_o) begin
                case (cmd_op_i)
                    CMD_START: begin
                        mode_hold           <= cmd_mode_i;
                        lane_mask_hold      <= fe_lane_mask;
                        a_re_hold           <= operand_a_i;
                        a_im_hold           <= operand_b_i;
                        b_re_hold           <= operand_c_i;
                        b_im_hold           <= operand_d_i;
                        c_re_hold           <= 320'd0;
                        c_im_hold           <= 320'd0;
                        w_re_hold           <= operand_e_i;
                        fe_valid_in         <= 1'b1;
                        state               <= ST_WAIT;
                        flag_invalid_hold   <= 1'b0;
                        flag_overflow_hold  <= 1'b0;
                        flag_underflow_hold <= 1'b0;
                        flag_inexact_hold   <= 1'b0;
                    end

                    CMD_LOAD_WIM: begin
                        w_im_hold <= operand_e_i;
                    end

                    CMD_READ: begin
                        rsp_valid_o <= 1'b1;
                        rsp_sel_o   <= cmd_read_sel_i;
                        case (cmd_read_sel_i)
                            2'd0: rsp_data_o <= y0_re_hold;
                            2'd1: rsp_data_o <= y0_im_hold;
                            2'd2: rsp_data_o <= y1_re_hold;
                            2'd3: rsp_data_o <= y1_im_hold;
                            default: rsp_data_o <= 320'd0;
                        endcase
                    end

                    CMD_CLEAR: begin
                        result_valid_o <= 1'b0;
                        rsp_valid_o    <= 1'b0;
                    end

                    default: begin
                    end
                endcase
            end

            if (fe_valid_out) begin
                y0_re_hold          <= mask_vec(fe_y0_re, lane_mask_hold);
                y0_im_hold          <= mask_vec(fe_y0_im, lane_mask_hold);
                y1_re_hold          <= mask_vec(fe_y1_re, lane_mask_hold);
                y1_im_hold          <= mask_vec(fe_y1_im, lane_mask_hold);
                flag_invalid_hold   <= fe_invalid;
                flag_overflow_hold  <= fe_overflow;
                flag_underflow_hold <= fe_underflow;
                flag_inexact_hold   <= fe_inexact;
                result_valid_o      <= 1'b1;
                state               <= ST_IDLE;
            end
        end
    end

endmodule
