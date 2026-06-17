`timescale 1ns/1ps

// Testbench: reconfig_fe_f64_shared_array
// Focus: verify lane-position correctness, state machine termination,
//        back-to-back operation, and zero-contamination.

module tb_reconfig_fe_f64_shared_array;
    localparam LANES  = 8;
    localparam IDX_W  = 4;
    localparam MODE_W = 4;
    localparam FE_LAT = 1;

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

    // Falcon f64 constants
    localparam [63:0] F64_ZERO     = 64'h0000_0000_0000_0000;
    localparam [63:0] F64_NEG_ZERO = 64'h8000_0000_0000_0000;
    localparam [63:0] F64_0125     = 64'h3fc0_0000_0000_0000;  // 0.125
    localparam [63:0] F64_025      = 64'h3fd0_0000_0000_0000;  // 0.25
    localparam [63:0] F64_0375     = 64'h3fd8_0000_0000_0000;  // 0.375
    localparam [63:0] F64_050      = 64'h3fe0_0000_0000_0000;  // 0.5
    localparam [63:0] F64_0625     = 64'h3fe4_0000_0000_0000;  // 0.625
    localparam [63:0] F64_075      = 64'h3fe8_0000_0000_0000;  // 0.75
    localparam [63:0] F64_0875     = 64'h3fec_0000_0000_0000;  // 0.875
    localparam [63:0] F64_100      = 64'h3ff0_0000_0000_0000;  // 1.0
    localparam [63:0] F64_150      = 64'h3ff8_0000_0000_0000;  // 1.5
    localparam [63:0] F64_NEG_050  = 64'hbfe0_0000_0000_0000;  // -0.5

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
    integer ln;

    reconfig_fe_f64_shared_array #(
        .LANES(LANES), .MODE_W(MODE_W), .IDX_W(IDX_W), .FE_LATENCY(FE_LAT)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .ready_in(ready_in),
        .lane_mask(lane_mask), .mode(mode),
        .a_re_vec(a_re_vec), .a_im_vec(a_im_vec),
        .b_re_vec(b_re_vec), .b_im_vec(b_im_vec),
        .c_re_vec(c_re_vec), .c_im_vec(c_im_vec),
        .w_re_vec(w_re_vec), .w_im_vec(w_im_vec),
        .busy(busy), .valid_out(valid_out),
        .y0_re_vec(y0_re_vec), .y0_im_vec(y0_im_vec),
        .y1_re_vec(y1_re_vec), .y1_im_vec(y1_im_vec),
        .status_invalid(status_invalid),
        .status_overflow(status_overflow),
        .status_underflow(status_underflow),
        .status_inexact(status_inexact)
    );

    always #5 clk = ~clk;  // 100MHz

    // ???? Broadcast: fill all LANES with the same 64-bit value ????
    function [LANES*64-1:0] bc;
        input [63:0] val;
        integer k;
        begin
            for (k = 0; k < LANES; k = k + 1)
                bc[k*64 +: 64] = val;
        end
    endfunction

    // ???? check one 64-bit word (tolerate +/-0) ????
    task check_word;
        input [255:0] msg;
        input [63:0]  got;
        input [63:0]  exp;
        begin
            if (!((got == exp) || ((got == F64_ZERO) && (exp == F64_NEG_ZERO)) ||
                  ((got == F64_NEG_ZERO) && (exp == F64_ZERO)))) begin
                $display("  FAIL %0s: got=%h exp=%h", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    // ???? drive inputs, pulse valid_in for 1 cycle ????
    task drive;
        input [MODE_W-1:0] dmode;
        input [LANES*64-1:0] da_re, da_im;
        input [LANES*64-1:0] db_re, db_im;
        input [LANES*64-1:0] dc_re, dc_im;
        input [LANES*64-1:0] dw_re, dw_im;
        begin
            @(negedge clk);
            mode      = dmode;
            lane_mask = {LANES{1'b1}};
            a_re_vec  = da_re;
            a_im_vec  = da_im;
            b_re_vec  = db_re;
            b_im_vec  = db_im;
            c_re_vec  = dc_re;
            c_im_vec  = dc_im;
            w_re_vec  = dw_re;
            w_im_vec  = dw_im;
            valid_in  = 1'b1;
            @(negedge clk);
            valid_in  = 1'b0;
        end
    endtask

    task drive_masked;
        input [MODE_W-1:0] dmode;
        input [LANES-1:0] dmask;
        input [LANES*64-1:0] da_re, da_im;
        input [LANES*64-1:0] db_re, db_im;
        input [LANES*64-1:0] dc_re, dc_im;
        input [LANES*64-1:0] dw_re, dw_im;
        begin
            @(negedge clk);
            mode      = dmode;
            lane_mask = dmask;
            a_re_vec  = da_re;
            a_im_vec  = da_im;
            b_re_vec  = db_re;
            b_im_vec  = db_im;
            c_re_vec  = dc_re;
            c_im_vec  = dc_im;
            w_re_vec  = dw_re;
            w_im_vec  = dw_im;
            valid_in  = 1'b1;
            @(negedge clk);
            valid_in  = 1'b0;
            lane_mask = {LANES{1'b1}};
        end
    endtask

    // ???? wait for valid_out with timeout ????
    task wait_valid_out;
        input [255:0] test_name;
        integer timeout;
        begin
            timeout = 0;
            while (!valid_out && timeout < 50) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!valid_out) begin
                $display("FAIL %0s: timeout waiting for valid_out", test_name);
                errors = errors + 1;
            end
        end
    endtask

    // ???? wait for busy to deassert ????
    task wait_ready;
        integer timeout;
        begin
            timeout = 0;
            while ((busy || valid_out) && timeout < 50) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
        end
    endtask

    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    // Test 1: Lane position ??each lane has a distinct a_re, b_re=0
    //          FLOAT_ADD ??y0 = a + b = a (since b=0)
    //          Verify each lane's output is at the correct bit-slice.
    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    task test_lane_position;
        reg [63:0] exp_val;
        reg [63:0] got_val;
        reg [63:0] lane_distinct [0:7];
        integer ln;
        begin
            $display("=== Test 1: Lane Position (FLOAT_ADD, distinct a_re per lane) ===");

            // Build per-lane a_re vector manually
            a_re_vec[  0*64 +: 64] = F64_0125;  // lane0: 0.125
            a_re_vec[  1*64 +: 64] = F64_025;   // lane1: 0.25
            a_re_vec[  2*64 +: 64] = F64_0375;  // lane2: 0.375
            a_re_vec[  3*64 +: 64] = F64_050;   // lane3: 0.5
            a_re_vec[  4*64 +: 64] = F64_0625;  // lane4: 0.625
            a_re_vec[  5*64 +: 64] = F64_075;   // lane5: 0.75
            a_re_vec[  6*64 +: 64] = F64_0875;  // lane6: 0.875
            a_re_vec[  7*64 +: 64] = F64_100;   // lane7: 1.0

            // Save expected values
            lane_distinct[0] = F64_0125;
            lane_distinct[1] = F64_025;
            lane_distinct[2] = F64_0375;
            lane_distinct[3] = F64_050;
            lane_distinct[4] = F64_0625;
            lane_distinct[5] = F64_075;
            lane_distinct[6] = F64_0875;
            lane_distinct[7] = F64_100;

            a_im_vec = bc(F64_ZERO);
            b_re_vec = bc(F64_ZERO);
            b_im_vec = bc(F64_ZERO);
            c_re_vec = bc(F64_ZERO);
            c_im_vec = bc(F64_ZERO);
            w_re_vec = bc(F64_ZERO);
            w_im_vec = bc(F64_ZERO);

            drive(FE_MODE_FLOAT_ADD,
                  a_re_vec, a_im_vec, b_re_vec, b_im_vec,
                  c_re_vec, c_im_vec, w_re_vec, w_im_vec);

            wait_valid_out("test1");

            if (valid_out) begin
                for (ln = 0; ln < LANES; ln = ln + 1) begin
                    got_val = y0_re_vec[ln*64 +: 64];
                    exp_val = lane_distinct[ln];
                    $display("  Lane %0d: y0_re=%h (exp=%h)%s",
                             ln, got_val, exp_val,
                             (got_val == exp_val) ? "" : "  <-- MISMATCH");
                    if (got_val != exp_val) errors = errors + 1;
                end
                // verify y0_im, y1_re, y1_im are zero
                for (ln = 0; ln < LANES; ln = ln + 1) begin
                    if (y0_im_vec[ln*64 +: 64] != F64_ZERO &&
                        y0_im_vec[ln*64 +: 64] != F64_NEG_ZERO) begin
                        $display("  FAIL Lane %0d y0_im: got=%h exp=0", ln, y0_im_vec[ln*64 +: 64]);
                        errors = errors + 1;
                    end
                end
            end

            wait_ready();
        end
    endtask

    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    // Test 2: CT Butterfly ??all lanes same known data
    //   a=(1.0,0) b=(0.5,0.5) w=(1.0,0) ??y0=(1.5,0.5) y1=(0.5,-0.5)
    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    task test_ct_bfu_uniform;
        integer ln;
        begin
            $display("=== Test 2: CT Butterfly (all %0d lanes same data) ===", LANES);

            drive(FE_MODE_CT_BFU_COMPLEX,
                  bc(F64_100),  bc(F64_ZERO),     // a
                  bc(F64_050),  bc(F64_050),      // b
                  bc(F64_ZERO), bc(F64_ZERO),     // c
                  bc(F64_100),  bc(F64_ZERO));    // w

            wait_valid_out("test2");

            if (valid_out) begin
                for (ln = 0; ln < LANES; ln = ln + 1) begin
                    check_word("y0_re", y0_re_vec[ln*64 +: 64], F64_150);
                    check_word("y0_im", y0_im_vec[ln*64 +: 64], F64_050);
                    check_word("y1_re", y1_re_vec[ln*64 +: 64], F64_050);
                    check_word("y1_im", y1_im_vec[ln*64 +: 64], F64_NEG_050);
                end
            end
            if (errors == 0) $display("  All %0d lanes OK", LANES);

            wait_ready();
        end
    endtask

    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    // Test 3: GS Butterfly
    //   a=(1.0,0.5) b=(0.5,-0.5) w=(1.0,0) ??y0=(1.5,0) y1=(0.5,1.0)
    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    task test_gs_bfu_uniform;
        integer ln;
        begin
            $display("=== Test 3: GS Butterfly (all %0d lanes same data) ===", LANES);

            drive(FE_MODE_GS_BFU_COMPLEX,
                  bc(F64_100),     bc(F64_050),      // a
                  bc(F64_050),     bc(F64_NEG_050),   // b
                  bc(F64_ZERO),    bc(F64_ZERO),      // c
                  bc(F64_100),     bc(F64_ZERO));     // w

            wait_valid_out("test3");

            if (valid_out) begin
                for (ln = 0; ln < LANES; ln = ln + 1) begin
                    check_word("y0_re", y0_re_vec[ln*64 +: 64], F64_150);
                    check_word("y0_im", y0_im_vec[ln*64 +: 64], F64_ZERO);
                    check_word("y1_re", y1_re_vec[ln*64 +: 64], F64_050);
                    check_word("y1_im", y1_im_vec[ln*64 +: 64], F64_100);
                end
            end
            if (errors == 0) $display("  All %0d lanes OK", LANES);

            wait_ready();
        end
    endtask

    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    // Test 4: Back-to-back ??two transactions in a row
    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    task test_back_to_back;
        integer ln;
        begin
            $display("=== Test 4: Back-to-back transactions ===");

            // Txn 1: FLOAT_ADD with per-lane data
            a_re_vec[  0*64 +: 64] = F64_0125;
            a_re_vec[  1*64 +: 64] = F64_025;
            a_re_vec[  2*64 +: 64] = F64_0375;
            a_re_vec[  3*64 +: 64] = F64_050;
            a_re_vec[  4*64 +: 64] = F64_0625;
            a_re_vec[  5*64 +: 64] = F64_075;
            a_re_vec[  6*64 +: 64] = F64_0875;
            a_re_vec[  7*64 +: 64] = F64_100;

            drive(FE_MODE_FLOAT_ADD,
                  a_re_vec, bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO),
                  bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO));

            wait_valid_out("test4_txn1");
            if (valid_out && y0_re_vec[0*64 +: 64] != F64_0125) begin
                $display("  FAIL txn1 lane0: got=%h exp=%h", y0_re_vec[0*64 +: 64], F64_0125);
                errors = errors + 1;
            end
            if (valid_out && y0_re_vec[7*64 +: 64] != F64_100) begin
                $display("  FAIL txn1 lane7: got=%h exp=%h", y0_re_vec[7*64 +: 64], F64_100);
                errors = errors + 1;
            end

            wait_ready();

            // Txn 2: COMPLEX_ADD a=(0.5,0.25) + b=(0.25,0.5) = (0.75,0.75)
            @(negedge clk);
            mode      = FE_MODE_COMPLEX_ADD;
            a_re_vec  = bc(F64_050);
            a_im_vec  = bc(F64_025);
            b_re_vec  = bc(F64_025);
            b_im_vec  = bc(F64_050);
            c_re_vec  = bc(F64_ZERO);
            c_im_vec  = bc(F64_ZERO);
            w_re_vec  = bc(F64_ZERO);
            w_im_vec  = bc(F64_ZERO);
            valid_in  = 1'b1;
            @(negedge clk);
            valid_in  = 1'b0;

            wait_valid_out("test4_txn2");
            if (valid_out) begin
                for (ln = 0; ln < LANES; ln = ln + 1) begin
                    if (y0_re_vec[ln*64 +: 64] != F64_075 ||
                        y0_im_vec[ln*64 +: 64] != F64_075) begin
                        $display("  FAIL txn2 lane%0d: got y0=(%h,%h) exp (0.75,0.75)",
                                 ln, y0_re_vec[ln*64 +: 64], y0_im_vec[ln*64 +: 64]);
                        errors = errors + 1;
                    end
                end
            end
            if (errors == 0) $display("  Back-to-back OK");

            wait_ready();
        end
    endtask

    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    // Test 5: Zero contamination ??only lane 0 & 7 have data
    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    task test_no_cross_contamination;
        integer ln;
        begin
            $display("=== Test 5: No cross-lane contamination ===");

            // Only lane 0 and 7 get non-zero; all others zero
            a_re_vec = bc(F64_ZERO);
            a_re_vec[0*64 +: 64] = F64_100;
            a_re_vec[7*64 +: 64] = F64_050;

            // FLOAT_SUB: y0 = a - b. With b=0 ??y0 = a
            drive(FE_MODE_FLOAT_SUB,
                  a_re_vec, bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO),
                  bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO));

            wait_valid_out("test5");

            if (valid_out) begin
                for (ln = 0; ln < LANES; ln = ln + 1) begin
                    if (ln == 0)
                        check_word("lane0", y0_re_vec[0*64 +: 64], F64_100);
                    else if (ln == 7)
                        check_word("lane7", y0_re_vec[7*64 +: 64], F64_050);
                    else
                        check_word("laneX", y0_re_vec[ln*64 +: 64], F64_ZERO);
                end
            end
            if (errors == 0) $display("  No contamination");

            wait_ready();
        end
    endtask

    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    // Main
    // ???????????????????????????????????????????????????????????????????????????????????????????????????
    task test_ready_backpressure;
        integer hold_i;
        begin
            $display("=== Test 6: ready_in backpressure ===");

            ready_in = 1'b0;
            drive(FE_MODE_FLOAT_SUB,
                  bc(F64_050), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO),
                  bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO));

            wait_valid_out("test6");

            for (hold_i = 0; hold_i < 3; hold_i = hold_i + 1) begin
                @(posedge clk);
                #1;
                if (!valid_out) begin
                    $display("  FAIL ready hold: valid_out dropped");
                    errors = errors + 1;
                end
                if (!busy) begin
                    $display("  FAIL ready hold: busy dropped while ready_in=0");
                    errors = errors + 1;
                end
                check_word("ready_hold_lane0", y0_re_vec[0*64 +: 64], F64_050);
                check_word("ready_hold_lane7", y0_re_vec[7*64 +: 64], F64_050);
            end

            ready_in = 1'b1;
            @(posedge clk);
            #1;
            if (valid_out) begin
                $display("  FAIL ready release: valid_out still high");
                errors = errors + 1;
            end
            if (busy) begin
                $display("  FAIL ready release: busy still high");
                errors = errors + 1;
            end
            if (errors == 0) $display("  Ready backpressure OK");
        end
    endtask

    task test_lane_mask_preserve;
        reg [LANES*64-1:0] masked_a;
        begin
            $display("=== Test 7: lane_mask preserves inactive lanes ===");

            drive(FE_MODE_FLOAT_SUB,
                  bc(F64_025), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO),
                  bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO));
            wait_valid_out("test7_seed");
            wait_ready();

            masked_a = bc(F64_ZERO);
            masked_a[0*64 +: 64] = F64_100;
            masked_a[7*64 +: 64] = F64_050;

            drive_masked(FE_MODE_FLOAT_SUB, 8'b1000_0001,
                         masked_a, bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO),
                         bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO));
            wait_valid_out("test7_masked");

            check_word("mask_lane0", y0_re_vec[0*64 +: 64], F64_100);
            check_word("mask_lane3_hold", y0_re_vec[3*64 +: 64], F64_025);
            check_word("mask_lane7", y0_re_vec[7*64 +: 64], F64_050);

            if (errors == 0) $display("  Lane mask preserve OK");
            wait_ready();
        end
    endtask

    task test_zero_mask_done;
        begin
            $display("=== Test 8: zero lane_mask completes without lane issue ===");

            drive(FE_MODE_FLOAT_SUB,
                  bc(F64_025), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO),
                  bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO));
            wait_valid_out("test8_seed");
            wait_ready();

            drive_masked(FE_MODE_FLOAT_SUB, {LANES{1'b0}},
                         bc(F64_100), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO),
                         bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO), bc(F64_ZERO));
            wait_valid_out("test8_zero_mask");

            check_word("zero_mask_lane0_hold", y0_re_vec[0*64 +: 64], F64_025);
            check_word("zero_mask_lane7_hold", y0_re_vec[7*64 +: 64], F64_025);
            if (status_invalid || status_overflow || status_underflow || status_inexact) begin
                $display("  FAIL zero mask status flags changed");
                errors = errors + 1;
            end

            if (errors == 0) $display("  Zero lane_mask completion OK");
            wait_ready();
        end
    endtask

    initial begin
        clk       = 1'b0;
        rst_n     = 1'b0;
        valid_in  = 1'b0;
        ready_in  = 1'b1;
        lane_mask = {LANES{1'b1}};
        mode      = 4'd0;
        errors    = 0;
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
        repeat (2) @(posedge clk);

        $display("========================================");
        $display(" reconfig_fe_f64_shared_array  Testbench");
        $display(" LANES=%0d  FE_LATENCY=%0d", LANES, FE_LAT);
        $display("========================================");

        test_lane_position();
        test_ct_bfu_uniform();
        test_gs_bfu_uniform();
        test_back_to_back();
        test_no_cross_contamination();
        test_ready_backpressure();
        test_lane_mask_preserve();
        test_zero_mask_done();

        $display("========================================");
        if (errors == 0) begin
            $display(" TB_PASS  All tests passed");
        end else begin
            $display(" TB_FAIL  errors=%0d", errors);
        end
        $display("========================================");
        $finish;
    end

    // Timeout
    initial begin
        #20000;
        $display("TB_FAIL timeout (20us)");
        $finish;
    end

endmodule
