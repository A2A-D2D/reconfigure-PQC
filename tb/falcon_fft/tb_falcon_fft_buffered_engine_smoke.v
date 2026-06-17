`timescale 1ns/1ps

module tb_falcon_fft_buffered_engine_smoke;
    localparam [63:0] F64_ZERO = 64'h0000_0000_0000_0000;

    reg clk;
    reg rst_n;
    reg start;
    reg inverse;
    reg [3:0] logn;
    reg ext_we;
    reg ext_bank;
    reg [9:0] ext_addr;
    reg [63:0] ext_re_i;
    reg [63:0] ext_im_i;
    wire [63:0] ext_re_o;
    wire [63:0] ext_im_o;
    wire busy;
    wire done;
    wire final_bank;
    wire status_invalid;
    wire status_overflow;
    wire status_underflow;
    wire status_inexact;

    integer i;
    integer cycles;
    integer errors;

    falcon_fft_buffered_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .inverse(inverse),
        .logn(logn),
        .ext_we(ext_we),
        .ext_bank(ext_bank),
        .ext_addr(ext_addr),
        .ext_re_i(ext_re_i),
        .ext_im_i(ext_im_i),
        .ext_re_o(ext_re_o),
        .ext_im_o(ext_im_o),
        .busy(busy),
        .done(done),
        .final_bank_o(final_bank),
        .status_invalid(status_invalid),
        .status_overflow(status_overflow),
        .status_underflow(status_underflow),
        .status_inexact(status_inexact)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        inverse = 1'b0;
        logn = 4'd3;
        ext_we = 1'b0;
        ext_bank = 1'b0;
        ext_addr = 10'd0;
        ext_re_i = F64_ZERO;
        ext_im_i = F64_ZERO;
        cycles = 0;
        errors = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Preload all values used by logn=3 into bank 0.
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            ext_we = 1'b1;
            ext_bank = 1'b0;
            ext_addr = i[9:0];
            ext_re_i = F64_ZERO;
            ext_im_i = F64_ZERO;
        end
        @(negedge clk);
        ext_we = 1'b0;

        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        while (!done && cycles < 500) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!done) begin
            $display("TB_FAIL timeout waiting buffered engine done");
            errors = errors + 1;
        end
        if (final_bank != 1'b0) begin
            $display("TB_FAIL final_bank=%0d exp=0", final_bank);
            errors = errors + 1;
        end
        if (status_invalid || status_overflow) begin
            $display("TB_FAIL unexpected status invalid=%0d overflow=%0d",
                     status_invalid, status_overflow);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TB_PASS falcon_fft_buffered_engine_smoke");
        end else begin
            $display("TB_FAIL errors=%0d", errors);
        end
        $finish;
    end
endmodule
