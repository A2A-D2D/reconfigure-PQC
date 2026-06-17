`timescale 1ns/1ps

module tb_reconfig_fe_f64_shared_array_lanes5;
    localparam LANES  = 5;
    localparam IDX_W  = 3;
    localparam MODE_W = 4;

    localparam [MODE_W-1:0] FE_MODE_FLOAT_SUB = 4'd3;

    localparam [63:0] F64_ZERO  = 64'h0000_0000_0000_0000;
    localparam [63:0] F64_0125  = 64'h3fc0_0000_0000_0000;
    localparam [63:0] F64_025   = 64'h3fd0_0000_0000_0000;
    localparam [63:0] F64_0375  = 64'h3fd8_0000_0000_0000;
    localparam [63:0] F64_050   = 64'h3fe0_0000_0000_0000;
    localparam [63:0] F64_0625  = 64'h3fe4_0000_0000_0000;
    localparam [63:0] F64_100   = 64'h3ff0_0000_0000_0000;

    reg                     clk;
    reg                     rst_n;
    reg                     valid_in;
    reg                     ready_in;
    reg  [LANES-1:0]        lane_mask;
    reg  [MODE_W-1:0]       mode;
    reg  [LANES*64-1:0]     a_re_vec;
    reg  [LANES*64-1:0]     a_im_vec;
    reg  [LANES*64-1:0]     b_re_vec;
    reg  [LANES*64-1:0]     b_im_vec;
    reg  [LANES*64-1:0]     c_re_vec;
    reg  [LANES*64-1:0]     c_im_vec;
    reg  [LANES*64-1:0]     w_re_vec;
    reg  [LANES*64-1:0]     w_im_vec;

    wire                    busy;
    wire                    valid_out;
    wire [LANES*64-1:0]     y0_re_vec;
    wire [LANES*64-1:0]     y0_im_vec;
    wire [LANES*64-1:0]     y1_re_vec;
    wire [LANES*64-1:0]     y1_im_vec;
    wire                    status_invalid;
    wire                    status_overflow;
    wire                    status_underflow;
    wire                    status_inexact;

    integer errors;
    integer timeout;

    reconfig_fe_f64_shared_array #(
        .LANES(LANES),
        .MODE_W(MODE_W),
        .IDX_W(IDX_W),
        .FE_LATENCY(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .ready_in(ready_in),
        .lane_mask(lane_mask),
        .mode(mode),
        .a_re_vec(a_re_vec),
        .a_im_vec(a_im_vec),
        .b_re_vec(b_re_vec),
        .b_im_vec(b_im_vec),
        .c_re_vec(c_re_vec),
        .c_im_vec(c_im_vec),
        .w_re_vec(w_re_vec),
        .w_im_vec(w_im_vec),
        .busy(busy),
        .valid_out(valid_out),
        .y0_re_vec(y0_re_vec),
        .y0_im_vec(y0_im_vec),
        .y1_re_vec(y1_re_vec),
        .y1_im_vec(y1_im_vec),
        .status_invalid(status_invalid),
        .status_overflow(status_overflow),
        .status_underflow(status_underflow),
        .status_inexact(status_inexact)
    );

    always #5 clk = ~clk;

    function [LANES*64-1:0] bc;
        input [63:0] val;
        integer k;
        begin
            for (k = 0; k < LANES; k = k + 1) begin
                bc[k*64 +: 64] = val;
            end
        end
    endfunction

    task check_word;
        input [127:0] name;
        input [63:0] got;
        input [63:0] exp;
        begin
            if (got != exp) begin
                $display("TB_FAIL %0s got=%h exp=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task wait_valid;
        input [127:0] name;
        begin
            timeout = 0;
            while (!valid_out && timeout < 50) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!valid_out) begin
                $display("TB_FAIL %0s timeout", name);
                errors = errors + 1;
            end
        end
    endtask

    task wait_idle;
        begin
            timeout = 0;
            while ((busy || valid_out) && timeout < 50) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (busy || valid_out) begin
                $display("TB_FAIL idle timeout");
                errors = errors + 1;
            end
        end
    endtask

    task start;
        input [LANES-1:0] mask;
        input [LANES*64-1:0] a_vec;
        begin
            @(negedge clk);
            mode       = FE_MODE_FLOAT_SUB;
            lane_mask  = mask;
            a_re_vec   = a_vec;
            a_im_vec   = bc(F64_ZERO);
            b_re_vec   = bc(F64_ZERO);
            b_im_vec   = bc(F64_ZERO);
            c_re_vec   = bc(F64_ZERO);
            c_im_vec   = bc(F64_ZERO);
            w_re_vec   = bc(F64_ZERO);
            w_im_vec   = bc(F64_ZERO);
            valid_in   = 1'b1;
            @(negedge clk);
            valid_in   = 1'b0;
            lane_mask  = {LANES{1'b1}};
        end
    endtask

    initial begin
        clk       = 1'b0;
        rst_n     = 1'b0;
        valid_in  = 1'b0;
        ready_in  = 1'b1;
        lane_mask = {LANES{1'b1}};
        mode      = FE_MODE_FLOAT_SUB;
        errors    = 0;
        timeout   = 0;
        a_re_vec  = {(LANES*64){1'b0}};
        a_im_vec  = {(LANES*64){1'b0}};
        b_re_vec  = {(LANES*64){1'b0}};
        b_im_vec  = {(LANES*64){1'b0}};
        c_re_vec  = {(LANES*64){1'b0}};
        c_im_vec  = {(LANES*64){1'b0}};
        w_re_vec  = {(LANES*64){1'b0}};
        w_im_vec  = {(LANES*64){1'b0}};

        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        a_re_vec[0*64 +: 64] = F64_0125;
        a_re_vec[1*64 +: 64] = F64_025;
        a_re_vec[2*64 +: 64] = F64_0375;
        a_re_vec[3*64 +: 64] = F64_050;
        a_re_vec[4*64 +: 64] = F64_0625;

        start(5'b1_1111, a_re_vec);
        wait_valid("lanes5_full");
        check_word("lane0", y0_re_vec[0*64 +: 64], F64_0125);
        check_word("lane1", y0_re_vec[1*64 +: 64], F64_025);
        check_word("lane2", y0_re_vec[2*64 +: 64], F64_0375);
        check_word("lane3", y0_re_vec[3*64 +: 64], F64_050);
        check_word("lane4", y0_re_vec[4*64 +: 64], F64_0625);
        wait_idle();

        start(5'b1_0101, bc(F64_100));
        wait_valid("lanes5_masked");
        check_word("mask_lane0", y0_re_vec[0*64 +: 64], F64_100);
        check_word("mask_lane1_hold", y0_re_vec[1*64 +: 64], F64_025);
        check_word("mask_lane2", y0_re_vec[2*64 +: 64], F64_100);
        check_word("mask_lane3_hold", y0_re_vec[3*64 +: 64], F64_050);
        check_word("mask_lane4", y0_re_vec[4*64 +: 64], F64_100);
        wait_idle();

        ready_in = 1'b0;
        start(5'b0_0000, bc(F64_050));
        wait_valid("lanes5_zero_mask");
        if (!busy) begin
            $display("TB_FAIL zero mask did not hold busy under backpressure");
            errors = errors + 1;
        end
        ready_in = 1'b1;
        @(posedge clk);
        #1;
        if (busy || valid_out) begin
            $display("TB_FAIL zero mask release failed");
            errors = errors + 1;
        end
        if (status_invalid || status_overflow || status_underflow || status_inexact) begin
            $display("TB_FAIL zero mask status flags changed");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TB_PASS lanes5 shared f64 FE cases");
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
