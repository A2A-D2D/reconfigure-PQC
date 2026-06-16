`timescale 1ns/1ps
// ============================================================================
// Module: vpu_fe_exu_adapter
// ============================================================================
// Purpose:
//   Glue logic for integrating vpu_fe_unit into an existing vpu_exu style
//   pipeline.  The real project can generate the four is_vffe* inputs from
//   operator_i == VFFE*.  This adapter then exposes the same kind of
//   done/stall/result signals used by existing multi-cycle VPU operations.
//
// Expected mapping in vpu_exu:
//   is_vffeloadwim_i = (operator_i == VFFELOADWIM)
//   is_vffestart_i   = (operator_i == VFFESTART)
//   is_vfferead_i    = (operator_i == VFFEREAD)
//   is_vffeclear_i   = (operator_i == VFFECLEAR)
//
// Only VFFEREAD writes the VPU register file.  LOADWIM, START, and CLEAR are
// control commands and should not assert the VPU vector write enable.
// ============================================================================

module vpu_fe_exu_adapter #(
    parameter VMASK_USE_BITMASK = 0,
    parameter FE_LATENCY        = 1
) (
    input              clk,
    input              rst_n,

    input              valid_i,
    input              is_vffeloadwim_i,
    input              is_vffestart_i,
    input              is_vfferead_i,
    input              is_vffeclear_i,

    input      [3:0]   fe_mode_i,
    input      [1:0]   fe_read_sel_i,
    input      [31:0]  cfg_vmask_i,

    input      [319:0] operand_a_i,
    input      [319:0] operand_b_i,
    input      [319:0] operand_c_i,
    input      [319:0] operand_d_i,
    input      [319:0] operand_e_i,

    output             fe_done_o,
    output             fe_stall_o,
    output     [319:0] fe_result_o,
    output             fe_vreg_we_o,
    output     [3:0]   fe_flags_o,
    output             fe_busy_o,
    output             fe_result_valid_o
);

    localparam [1:0] CMD_START    = 2'd0;
    localparam [1:0] CMD_LOAD_WIM = 2'd1;
    localparam [1:0] CMD_READ     = 2'd2;
    localparam [1:0] CMD_CLEAR    = 2'd3;

    wire is_fe_op;
    wire cmd_ready;
    wire rsp_valid;
    wire [319:0] rsp_data;
    wire [1:0] rsp_sel;
    wire [1:0] cmd_op;
    wire cmd_fire;
    wire rsp_fire;
    wire loadwim_done;
    wire clear_done;
    wire start_done;
    wire read_done;

    reg start_inflight;
    reg read_inflight;

    assign is_fe_op = is_vffeloadwim_i | is_vffestart_i |
                      is_vfferead_i | is_vffeclear_i;

    assign cmd_op =
        is_vffeloadwim_i ? CMD_LOAD_WIM :
        is_vfferead_i    ? CMD_READ :
        is_vffeclear_i   ? CMD_CLEAR :
                           CMD_START;

    assign cmd_fire = valid_i & is_fe_op & cmd_ready &
                      !start_inflight & !read_inflight &
                      !(is_vfferead_i && rsp_valid);

    assign rsp_fire = rsp_valid & read_done;

    assign loadwim_done = valid_i & is_vffeloadwim_i & cmd_ready &
                          !start_inflight & !read_inflight;
    assign clear_done   = valid_i & is_vffeclear_i & cmd_ready &
                          !start_inflight & !read_inflight;
    assign start_done   = valid_i & is_vffestart_i & start_inflight &
                          fe_result_valid_o;
    assign read_done    = valid_i & is_vfferead_i & rsp_valid;

    assign fe_done_o    = loadwim_done | clear_done | start_done | read_done;
    assign fe_stall_o   = valid_i & is_fe_op & !fe_done_o;
    assign fe_result_o  = is_vfferead_i ? rsp_data : 320'd0;
    assign fe_vreg_we_o = read_done;

    vpu_fe_unit #(
        .VMASK_USE_BITMASK(VMASK_USE_BITMASK),
        .FE_LATENCY(FE_LATENCY)
    ) u_vpu_fe_unit (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_valid_i    (cmd_fire),
        .cmd_ready_o    (cmd_ready),
        .cmd_op_i       (cmd_op),
        .cmd_mode_i     (fe_mode_i),
        .cmd_read_sel_i (fe_read_sel_i),
        .cmd_vmask_i    (cfg_vmask_i),
        .operand_a_i    (operand_a_i),
        .operand_b_i    (operand_b_i),
        .operand_c_i    (operand_c_i),
        .operand_d_i    (operand_d_i),
        .operand_e_i    (operand_e_i),
        .rsp_valid_o    (rsp_valid),
        .rsp_ready_i    (rsp_fire),
        .rsp_data_o     (rsp_data),
        .rsp_sel_o      (rsp_sel),
        .rsp_flags_o    (fe_flags_o),
        .busy_o         (fe_busy_o),
        .result_valid_o (fe_result_valid_o)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_inflight <= 1'b0;
            read_inflight  <= 1'b0;
        end else begin
            if (cmd_fire && is_vffestart_i) begin
                start_inflight <= 1'b1;
            end else if (fe_result_valid_o) begin
                start_inflight <= 1'b0;
            end

            if (cmd_fire && is_vfferead_i) begin
                read_inflight <= 1'b1;
            end else if (rsp_valid) begin
                read_inflight <= 1'b0;
            end
        end
    end

endmodule
