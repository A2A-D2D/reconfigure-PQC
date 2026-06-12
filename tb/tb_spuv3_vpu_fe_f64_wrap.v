`timescale 1ns/1ps

module tb_spuv3_vpu_fe_f64_wrap;
    localparam [63:0] F64_ZERO     = 64'h0000_0000_0000_0000;
    localparam [63:0] F64_NEG_ZERO = 64'h8000_0000_0000_0000;
    localparam [63:0] F64_025      = 64'h3fd0_0000_0000_0000;
    localparam [63:0] F64_050      = 64'h3fe0_0000_0000_0000;
    localparam [63:0] F64_100      = 64'h3ff0_0000_0000_0000;
    localparam [63:0] F64_150      = 64'h3ff8_0000_0000_0000;
    localparam [63:0] F64_NEG_050  = 64'hbfe0_0000_0000_0000;

    reg          clk;
    reg          rst_n;
    reg          valid_in;
    reg          ready_in;
    reg          inverse;
    reg  [31:0]  csr_vmask_i;
    reg  [319:0] va_re_vr_i;
    reg  [319:0] va_im_vr_i;
    reg  [319:0] vb_re_vr_i;
    reg  [319:0] vb_im_vr_i;
    reg  [319:0] tw_re_vr_i;
    reg  [319:0] tw_im_vr_i;

    wire         busy_len;
    wire         valid_out_len;
    wire         done_pulse_len;
    wire [319:0] va_re_vr_o_len;
    wire [319:0] va_im_vr_o_len;
    wire [319:0] vb_re_vr_o_len;
    wire [319:0] vb_im_vr_o_len;
    wire [4:0]   fe_lane_mask_len;
    wire         status_invalid_len;
    wire         status_overflow_len;
    wire         status_underflow_len;
    wire         status_inexact_len;

    wire         busy_bit;
    wire         valid_out_bit;
    wire         done_pulse_bit;
    wire [319:0] va_re_vr_o_bit;
    wire [319:0] va_im_vr_o_bit;
    wire [319:0] vb_re_vr_o_bit;
    wire [319:0] vb_im_vr_o_bit;
    wire [4:0]   fe_lane_mask_bit;
    wire         status_invalid_bit;
    wire         status_overflow_bit;
    wire         status_underflow_bit;
    wire         status_inexact_bit;

    integer errors;
    integer timeout;

    spuv3_vpu_fe_f64_wrap #(
        .VMASK_USE_BITMASK(0)
    ) dut_len (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .ready_in(ready_in),
        .inverse(inverse),
        .csr_vmask_i(csr_vmask_i),
        .va_re_vr_i(va_re_vr_i),
        .va_im_vr_i(va_im_vr_i),
        .vb_re_vr_i(vb_re_vr_i),
        .vb_im_vr_i(vb_im_vr_i),
        .tw_re_vr_i(tw_re_vr_i),
        .tw_im_vr_i(tw_im_vr_i),
        .busy(busy_len),
        .valid_out(valid_out_len),
        .done_pulse(done_pulse_len),
        .va_re_vr_o(va_re_vr_o_len),
        .va_im_vr_o(va_im_vr_o_len),
        .vb_re_vr_o(vb_re_vr_o_len),
        .vb_im_vr_o(vb_im_vr_o_len),
        .fe_lane_mask_o(fe_lane_mask_len),
        .status_invalid(status_invalid_len),
        .status_overflow(status_overflow_len),
        .status_underflow(status_underflow_len),
        .status_inexact(status_inexact_len)
    );

    spuv3_vpu_fe_f64_wrap #(
        .VMASK_USE_BITMASK(1)
    ) dut_bit (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .ready_in(ready_in),
        .inverse(inverse),
        .csr_vmask_i(csr_vmask_i),
        .va_re_vr_i(va_re_vr_i),
        .va_im_vr_i(va_im_vr_i),
        .vb_re_vr_i(vb_re_vr_i),
        .vb_im_vr_i(vb_im_vr_i),
        .tw_re_vr_i(tw_re_vr_i),
        .tw_im_vr_i(tw_im_vr_i),
        .busy(busy_bit),
        .valid_out(valid_out_bit),
        .done_pulse(done_pulse_bit),
        .va_re_vr_o(va_re_vr_o_bit),
        .va_im_vr_o(va_im_vr_o_bit),
        .vb_re_vr_o(vb_re_vr_o_bit),
        .vb_im_vr_o(vb_im_vr_o_bit),
        .fe_lane_mask_o(fe_lane_mask_bit),
        .status_invalid(status_invalid_bit),
        .status_overflow(status_overflow_bit),
        .status_underflow(status_underflow_bit),
        .status_inexact(status_inexact_bit)
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
            if (!((got == exp) || ((got == F64_ZERO) && (exp == F64_NEG_ZERO)) ||
                  ((got == F64_NEG_ZERO) && (exp == F64_ZERO)))) begin
                $display("TB_FAIL %0s got=%h exp=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task wait_valid_len;
        input [127:0] name;
        begin
            timeout = 0;
            while (!valid_out_len && timeout < 50) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!valid_out_len) begin
                $display("TB_FAIL %0s timeout", name);
                errors = errors + 1;
            end
        end
    endtask

    task wait_valid_bit;
        input [127:0] name;
        begin
            timeout = 0;
            while (!valid_out_bit && timeout < 50) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!valid_out_bit) begin
                $display("TB_FAIL %0s timeout", name);
                errors = errors + 1;
            end
        end
    endtask

    task wait_idle;
        begin
            timeout = 0;
            while ((busy_len || valid_out_len || busy_bit || valid_out_bit) &&
                   timeout < 50) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (busy_len || valid_out_len || busy_bit || valid_out_bit) begin
                $display("TB_FAIL idle timeout");
                errors = errors + 1;
            end
        end
    endtask

    task start_common;
        input [31:0] vmask;
        input case_inverse;
        begin
            @(negedge clk);
            csr_vmask_i = vmask;
            inverse     = case_inverse;
            valid_in    = 1'b1;
            @(negedge clk);
            valid_in    = 1'b0;
        end
    endtask

    initial begin
        clk          = 1'b0;
        rst_n        = 1'b0;
        valid_in     = 1'b0;
        ready_in     = 1'b1;
        inverse      = 1'b0;
        csr_vmask_i  = 32'd0;
        errors       = 0;
        timeout      = 0;
        va_re_vr_i   = bc(F64_100);
        va_im_vr_i   = bc(F64_ZERO);
        vb_re_vr_i   = bc(F64_050);
        vb_im_vr_i   = bc(F64_050);
        tw_re_vr_i   = bc(F64_100);
        tw_im_vr_i   = bc(F64_ZERO);

        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        start_common(32'd10, 1'b0);
        wait_valid_len("vmask10_len");
        if (fe_lane_mask_len != 5'b1_1111) begin
            $display("TB_FAIL VMASK=10 len mask got=%b", fe_lane_mask_len);
            errors = errors + 1;
        end
        check_word("vmask10_l4_va_re", va_re_vr_o_len[4*64 +: 64], F64_150);
        check_word("vmask10_l4_vb_im", vb_im_vr_o_len[4*64 +: 64], F64_NEG_050);
        wait_idle();

        start_common(32'd8, 1'b0);
        wait_valid_len("vmask8_len");
        if (fe_lane_mask_len != 5'b0_1111) begin
            $display("TB_FAIL VMASK=8 len mask got=%b", fe_lane_mask_len);
            errors = errors + 1;
        end
        check_word("vmask8_l3_va_re", va_re_vr_o_len[3*64 +: 64], F64_150);
        check_word("vmask8_l4_hold", va_re_vr_o_len[4*64 +: 64], F64_150);
        wait_idle();

        ready_in = 1'b0;
        start_common(32'd0, 1'b0);
        wait_valid_len("vmask0_len");
        if (done_pulse_len) begin
            $display("TB_FAIL done_pulse asserted before ready");
            errors = errors + 1;
        end
        if (!busy_len) begin
            $display("TB_FAIL VMASK=0 did not hold busy under backpressure");
            errors = errors + 1;
        end
        ready_in = 1'b1;
        #1;
        if (!done_pulse_len) begin
            $display("TB_FAIL done_pulse missing on ready release");
            errors = errors + 1;
        end
        @(posedge clk);
        #1;
        wait_idle();

        start_common(32'b0000_0000_0000_0000_0000_0000_1100_0011, 1'b0);
        wait_valid_bit("bitmask_pair");
        if (fe_lane_mask_bit != 5'b0_1001) begin
            $display("TB_FAIL bitmask pair mask got=%b", fe_lane_mask_bit);
            errors = errors + 1;
        end
        check_word("bitmask_l0_va_re", va_re_vr_o_bit[0*64 +: 64], F64_150);
        check_word("bitmask_l3_va_re", va_re_vr_o_bit[3*64 +: 64], F64_150);

        if (status_invalid_len || status_overflow_len ||
            status_underflow_len || status_inexact_len ||
            status_invalid_bit || status_overflow_bit ||
            status_underflow_bit || status_inexact_bit) begin
            $display("TB_FAIL status flags changed unexpectedly");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TB_PASS spuv3 vpu fe f64 wrapper cases");
        end else begin
            $display("TB_FAIL errors=%0d", errors);
        end
        $finish;
    end

    initial begin
        #10000;
        $display("TB_FAIL timeout");
        $finish;
    end

endmodule
