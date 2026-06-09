`timescale 1ns/1ps

// Testbench for shuffle_net — standalone verification of all 4 modes.

module tb_shuffle_net;

    localparam WORD_W = 32;
    localparam LANES  = 8;      // small for readable debug output
    localparam CLOG2  = 3;      // ceil(log2(8))

    reg  [(LANES*WORD_W)-1:0] data_in;
    reg  [CLOG2-1:0]          offset;
    reg  [1:0]                mode;
    wire [(LANES*WORD_W)-1:0] data_out;

    shuffle_net #(
        .WORD_W(WORD_W),
        .LANES (LANES),
        .CLOG2 (CLOG2)
    ) dut (
        .data_in (data_in),
        .offset  (offset),
        .mode    (mode),
        .data_out(data_out)
    );

    integer errors, tests, i;
    reg [CLOG2-1:0] exp_src[0:LANES-1];
    reg [WORD_W-1:0] exp_val;
    reg ok;

    // Compute expected source index for each destination
    function [CLOG2-1:0] bit_rev;
        input [CLOG2-1:0] idx;
        integer b;
        begin
            bit_rev = {CLOG2{1'b0}};
            for (b = 0; b < CLOG2; b = b + 1)
                bit_rev[b] = idx[CLOG2-1 - b];
        end
    endfunction

    task check_mode;
        input [1:0]   t_mode;
        input [CLOG2-1:0] t_offset;
        input [255:0] name;     // descriptive string
        reg [CLOG2-1:0] expected_idx;
        begin
            mode   = t_mode;
            offset = t_offset;
            #1;  // let combinational logic settle

            for (i = 0; i < LANES; i = i + 1) begin
                case (t_mode)
                    2'b00: expected_idx = i[CLOG2-1:0];
                    2'b01: expected_idx = i[CLOG2-1:0] ^ t_offset;
                    2'b10: expected_idx = bit_rev(i[CLOG2-1:0]);
                    2'b11: expected_idx = (i[CLOG2-1:0] - t_offset);
                    default: expected_idx = i[CLOG2-1:0];
                endcase

                exp_val = data_out[(i*WORD_W) +: WORD_W];
                tests = tests + 1;

                if (exp_val !== data_in[(expected_idx*WORD_W) +: WORD_W]) begin
                    $display("FAIL mode=%0d offset=%0d dst[%0d]=%0d expected src[%0d]=%0d",
                             t_mode, t_offset, i, exp_val,
                             expected_idx, data_in[(expected_idx*WORD_W) +: WORD_W]);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        tests  = 0;

        // Load distinct values into each lane for easy tracing
        for (i = 0; i < LANES; i = i + 1)
            data_in[(i*WORD_W) +: WORD_W] = 32'd1000 + i;

        #10;

        // ---- Test 1: PASSTHROUGH ----
        $display("=== Test PASSTHROUGH ===");
        check_mode(2'b00, 3'd0, "passthrough");

        // ---- Test 2: XOR_SHUFFLE with various offsets ----
        $display("=== Test XOR_SHUFFLE ===");
        check_mode(2'b01, 3'd1, "xor offset=1");    // adjacent swap
        check_mode(2'b01, 3'd2, "xor offset=2");    // stride-2
        check_mode(2'b01, 3'd4, "xor offset=4");    // stride-4
        check_mode(2'b01, 3'd0, "xor offset=0");    // identity
        check_mode(2'b01, 3'd7, "xor offset=7");    // max offset

        // ---- Test 3: BIT_REVERSE ----
        $display("=== Test BIT_REVERSE ===");
        check_mode(2'b10, 3'd0, "bit_rev");

        // ---- Test 4: ROTATE ----
        $display("=== Test ROTATE ===");
        check_mode(2'b11, 3'd1, "rotate +1");
        check_mode(2'b11, 3'd3, "rotate +3");
        check_mode(2'b11, 3'd7, "rotate +7 (= -1)");

        // ---- Report ----
        if (errors == 0)
            $display("TB_PASS all %0d shuffle checks", tests);
        else
            $display("TB_FAIL %0d errors in %0d checks", errors, tests);

        $finish;
    end

endmodule
