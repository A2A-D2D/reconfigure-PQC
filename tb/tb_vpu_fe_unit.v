`timescale 1ns/1ps

module tb_vpu_fe_unit;
    localparam [1:0] CMD_START    = 2'd0;
    localparam [1:0] CMD_LOAD_WIM = 2'd1;
    localparam [1:0] CMD_READ     = 2'd2;
    localparam [1:0] CMD_CLEAR    = 2'd3;

    localparam [3:0] FE_MODE_CT_BFU_COMPLEX = 4'd0;

    localparam [63:0] F64_ZERO     = 64'h0000_0000_0000_0000;
    localparam [63:0] F64_NEG_ZERO = 64'h8000_0000_0000_0000;
    localparam [63:0] F64_050      = 64'h3fe0_0000_0000_0000;
    localparam [63:0] F64_100      = 64'h3ff0_0000_0000_0000;
    localparam [63:0] F64_150      = 64'h3ff8_0000_0000_0000;
    localparam [63:0] F64_NEG_050  = 64'hbfe0_0000_0000_0000;

    reg          clk;
    reg          rst_n;
    reg          cmd_valid_i;
    wire         cmd_ready_o;
    reg  [1:0]   cmd_op_i;
    reg  [3:0]   cmd_mode_i;
    reg  [1:0]   cmd_read_sel_i;
    reg  [31:0]  cmd_vmask_i;
    reg  [319:0] operand_a_i;
    reg  [319:0] operand_b_i;
    reg  [319:0] operand_c_i;
    reg  [319:0] operand_d_i;
    reg  [319:0] operand_e_i;
    wire         rsp_valid_o;
    reg          rsp_ready_i;
    wire [319:0] rsp_data_o;
    wire [1:0]   rsp_sel_o;
    wire [3:0]   rsp_flags_o;
    wire         busy_o;
    wire         result_valid_o;

    integer errors;
    integer timeout;

    vpu_fe_unit dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_valid_i    (cmd_valid_i),
        .cmd_ready_o    (cmd_ready_o),
        .cmd_op_i       (cmd_op_i),
        .cmd_mode_i     (cmd_mode_i),
        .cmd_read_sel_i (cmd_read_sel_i),
        .cmd_vmask_i    (cmd_vmask_i),
        .operand_a_i    (operand_a_i),
        .operand_b_i    (operand_b_i),
        .operand_c_i    (operand_c_i),
        .operand_d_i    (operand_d_i),
        .operand_e_i    (operand_e_i),
        .rsp_valid_o    (rsp_valid_o),
        .rsp_ready_i    (rsp_ready_i),
        .rsp_data_o     (rsp_data_o),
        .rsp_sel_o      (rsp_sel_o),
        .rsp_flags_o    (rsp_flags_o),
        .busy_o         (busy_o),
        .result_valid_o (result_valid_o)
    );

    always #5 clk = ~clk;

    function [319:0] bc;
        input [63:0] val;
        integer k;
        begin
            for (k = 0; k < 5; k = k + 1) begin
                bc[k*64 +: 64] = val;
            end
        end
    endfunction

    task check_word;
        input [127:0] name;
        input [63:0] got;
        input [63:0] exp;
        begin
            if (!((got == exp) ||
                  ((got == F64_ZERO) && (exp == F64_NEG_ZERO)) ||
                  ((got == F64_NEG_ZERO) && (exp == F64_ZERO)))) begin
                $display("TB_FAIL %0s got=%h exp=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task issue_cmd;
        input [1:0] op;
        input [1:0] read_sel;
        begin
            @(negedge clk);
            cmd_op_i       = op;
            cmd_read_sel_i = read_sel;
            cmd_valid_i    = 1'b1;
            #1;
            if (!cmd_ready_o) begin
                $display("TB_FAIL command not ready op=%0d", op);
                errors = errors + 1;
            end
            @(negedge clk);
            cmd_valid_i = 1'b0;
        end
    endtask

    task wait_result;
        begin
            timeout = 0;
            while (!result_valid_o && timeout < 100) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!result_valid_o) begin
                $display("TB_FAIL timeout waiting result_valid_o");
                errors = errors + 1;
            end
        end
    endtask

    task read_result;
        input [1:0] sel;
        begin
            issue_cmd(CMD_READ, sel);
            timeout = 0;
            while (!rsp_valid_o && timeout < 10) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!rsp_valid_o) begin
                $display("TB_FAIL timeout waiting rsp_valid sel=%0d", sel);
                errors = errors + 1;
            end
            if (rsp_sel_o != sel) begin
                $display("TB_FAIL rsp_sel got=%0d exp=%0d", rsp_sel_o, sel);
                errors = errors + 1;
            end
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk            = 1'b0;
        rst_n          = 1'b0;
        cmd_valid_i    = 1'b0;
        cmd_op_i       = CMD_CLEAR;
        cmd_mode_i     = FE_MODE_CT_BFU_COMPLEX;
        cmd_read_sel_i = 2'd0;
        cmd_vmask_i    = 32'd10;
        operand_a_i    = bc(F64_100);
        operand_b_i    = bc(F64_ZERO);
        operand_c_i    = bc(F64_050);
        operand_d_i    = bc(F64_050);
        operand_e_i    = bc(F64_ZERO);
        rsp_ready_i    = 1'b1;
        errors         = 0;
        timeout        = 0;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        operand_e_i = bc(F64_ZERO);
        issue_cmd(CMD_LOAD_WIM, 2'd0);

        operand_e_i = bc(F64_100);
        issue_cmd(CMD_START, 2'd0);

        @(negedge clk);
        cmd_op_i    = CMD_START;
        cmd_valid_i = 1'b1;
        #1;
        if (cmd_ready_o) begin
            $display("TB_FAIL start accepted while FE busy");
            errors = errors + 1;
        end
        @(negedge clk);
        cmd_valid_i = 1'b0;

        wait_result();

        read_result(2'd0);
        check_word("y0_re_l0", rsp_data_o[0*64 +: 64], F64_150);
        check_word("y0_re_l4", rsp_data_o[4*64 +: 64], F64_150);

        read_result(2'd1);
        check_word("y0_im_l0", rsp_data_o[0*64 +: 64], F64_050);
        check_word("y0_im_l4", rsp_data_o[4*64 +: 64], F64_050);

        read_result(2'd2);
        check_word("y1_re_l0", rsp_data_o[0*64 +: 64], F64_050);
        check_word("y1_re_l4", rsp_data_o[4*64 +: 64], F64_050);

        read_result(2'd3);
        check_word("y1_im_l0", rsp_data_o[0*64 +: 64], F64_NEG_050);
        check_word("y1_im_l4", rsp_data_o[4*64 +: 64], F64_NEG_050);

        if (rsp_flags_o != 4'b0000) begin
            $display("TB_FAIL unexpected flags %b", rsp_flags_o);
            errors = errors + 1;
        end

        issue_cmd(CMD_CLEAR, 2'd0);
        if (result_valid_o) begin
            $display("TB_FAIL result_valid_o not cleared");
            errors = errors + 1;
        end

        cmd_vmask_i = 32'd8;
        operand_e_i = bc(F64_100);
        issue_cmd(CMD_START, 2'd0);
        wait_result();
        read_result(2'd0);
        check_word("vmask8_y0_re_l3", rsp_data_o[3*64 +: 64], F64_150);
        check_word("vmask8_y0_re_l4", rsp_data_o[4*64 +: 64], F64_ZERO);

        if (errors == 0) begin
            $display("TB_PASS vpu fe unit cases");
        end else begin
            $display("TB_FAIL errors=%0d", errors);
        end
        $finish;
    end

    initial begin
        #20000;
        $display("TB_FAIL timeout");
        $finish;
    end

endmodule
