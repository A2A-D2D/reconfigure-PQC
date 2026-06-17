`timescale 1ns/1ps

module tb_vpu_fe_exu_adapter;
    localparam [3:0] FE_MODE_CT_BFU_COMPLEX = 4'd0;

    localparam [63:0] F64_ZERO     = 64'h0000_0000_0000_0000;
    localparam [63:0] F64_NEG_ZERO = 64'h8000_0000_0000_0000;
    localparam [63:0] F64_050      = 64'h3fe0_0000_0000_0000;
    localparam [63:0] F64_100      = 64'h3ff0_0000_0000_0000;
    localparam [63:0] F64_150      = 64'h3ff8_0000_0000_0000;
    localparam [63:0] F64_NEG_050  = 64'hbfe0_0000_0000_0000;

    reg          clk;
    reg          rst_n;
    reg          valid_i;
    reg          is_vffeloadwim_i;
    reg          is_vffestart_i;
    reg          is_vfferead_i;
    reg          is_vffeclear_i;
    reg  [3:0]   fe_mode_i;
    reg  [1:0]   fe_read_sel_i;
    reg  [31:0]  cfg_vmask_i;
    reg  [319:0] operand_a_i;
    reg  [319:0] operand_b_i;
    reg  [319:0] operand_c_i;
    reg  [319:0] operand_d_i;
    reg  [319:0] operand_e_i;
    wire         fe_done_o;
    wire         fe_stall_o;
    wire [319:0] fe_result_o;
    wire         fe_vreg_we_o;
    wire [3:0]   fe_flags_o;
    wire         fe_busy_o;
    wire         fe_result_valid_o;

    integer errors;
    integer timeout;

    vpu_fe_exu_adapter dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .valid_i          (valid_i),
        .is_vffeloadwim_i (is_vffeloadwim_i),
        .is_vffestart_i   (is_vffestart_i),
        .is_vfferead_i    (is_vfferead_i),
        .is_vffeclear_i   (is_vffeclear_i),
        .fe_mode_i        (fe_mode_i),
        .fe_read_sel_i    (fe_read_sel_i),
        .cfg_vmask_i      (cfg_vmask_i),
        .operand_a_i      (operand_a_i),
        .operand_b_i      (operand_b_i),
        .operand_c_i      (operand_c_i),
        .operand_d_i      (operand_d_i),
        .operand_e_i      (operand_e_i),
        .fe_done_o        (fe_done_o),
        .fe_stall_o       (fe_stall_o),
        .fe_result_o      (fe_result_o),
        .fe_vreg_we_o     (fe_vreg_we_o),
        .fe_flags_o       (fe_flags_o),
        .fe_busy_o        (fe_busy_o),
        .fe_result_valid_o(fe_result_valid_o)
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

    task clear_ops;
        begin
            is_vffeloadwim_i = 1'b0;
            is_vffestart_i   = 1'b0;
            is_vfferead_i    = 1'b0;
            is_vffeclear_i   = 1'b0;
        end
    endtask

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

    task issue_one_cycle;
        input [1:0] op_sel;
        begin
            @(negedge clk);
            clear_ops();
            valid_i = 1'b1;
            case (op_sel)
                2'd0: is_vffeloadwim_i = 1'b1;
                2'd1: is_vffeclear_i   = 1'b1;
                default: is_vffeclear_i = 1'b1;
            endcase
            @(posedge clk);
            #1;
            if (!fe_done_o || fe_stall_o || fe_vreg_we_o) begin
                $display("TB_FAIL one-cycle op done=%b stall=%b we=%b",
                         fe_done_o, fe_stall_o, fe_vreg_we_o);
                errors = errors + 1;
            end
            @(negedge clk);
            valid_i = 1'b0;
            clear_ops();
        end
    endtask

    task issue_start_and_wait;
        begin
            @(negedge clk);
            clear_ops();
            is_vffestart_i = 1'b1;
            valid_i        = 1'b1;

            timeout = 0;
            while (!fe_done_o && timeout < 100) begin
                @(posedge clk);
                #1;
                if (!fe_stall_o && !fe_done_o) begin
                    $display("TB_FAIL START dropped stall before done");
                    errors = errors + 1;
                end
                timeout = timeout + 1;
            end
            if (!fe_done_o) begin
                $display("TB_FAIL START timeout");
                errors = errors + 1;
            end
            if (fe_vreg_we_o) begin
                $display("TB_FAIL START asserted vreg write");
                errors = errors + 1;
            end
            @(negedge clk);
            valid_i = 1'b0;
            clear_ops();
        end
    endtask

    task issue_read_and_check;
        input [1:0] sel;
        input [63:0] exp_l0;
        input [63:0] exp_l4;
        begin
            @(negedge clk);
            clear_ops();
            fe_read_sel_i = sel;
            is_vfferead_i = 1'b1;
            valid_i       = 1'b1;

            timeout = 0;
            while (!fe_done_o && timeout < 20) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!fe_done_o) begin
                $display("TB_FAIL READ timeout sel=%0d", sel);
                errors = errors + 1;
            end
            if (!fe_vreg_we_o) begin
                $display("TB_FAIL READ missing vreg write sel=%0d", sel);
                errors = errors + 1;
            end
            check_word("read_l0", fe_result_o[0*64 +: 64], exp_l0);
            check_word("read_l4", fe_result_o[4*64 +: 64], exp_l4);
            @(negedge clk);
            valid_i = 1'b0;
            clear_ops();
        end
    endtask

    initial begin
        clk              = 1'b0;
        rst_n            = 1'b0;
        valid_i          = 1'b0;
        clear_ops();
        fe_mode_i        = FE_MODE_CT_BFU_COMPLEX;
        fe_read_sel_i    = 2'd0;
        cfg_vmask_i      = 32'd10;
        operand_a_i      = bc(F64_100);
        operand_b_i      = bc(F64_ZERO);
        operand_c_i      = bc(F64_050);
        operand_d_i      = bc(F64_050);
        operand_e_i      = bc(F64_ZERO);
        errors           = 0;
        timeout          = 0;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        operand_e_i = bc(F64_ZERO);
        issue_one_cycle(2'd0);

        operand_e_i = bc(F64_100);
        issue_start_and_wait();

        issue_read_and_check(2'd0, F64_150, F64_150);
        issue_read_and_check(2'd1, F64_050, F64_050);
        issue_read_and_check(2'd2, F64_050, F64_050);
        issue_read_and_check(2'd3, F64_NEG_050, F64_NEG_050);

        issue_one_cycle(2'd1);
        if (fe_result_valid_o) begin
            $display("TB_FAIL CLEAR did not clear result_valid");
            errors = errors + 1;
        end

        if (fe_flags_o != 4'b0000) begin
            $display("TB_FAIL unexpected flags %b", fe_flags_o);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TB_PASS vpu fe exu adapter cases");
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
