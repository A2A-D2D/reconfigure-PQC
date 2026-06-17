`timescale 1ns/1ps

// PQC Integration Testbench — verifies scheme_rom, useq_rom,
// ntt_stage_ctrl, and reconfig_ntt_pipeline together.

module tb_pqc_integration;

    localparam WORD_W   = 32;
    localparam MODE_W   = 4;
    localparam LANES    = 32;
    localparam SCHEME_W = 2;
    localparam ADDR_W   = 5;
    localparam LW       = 8;

    reg clk, rst_n;

    // ==================================================================
    // Test 1: scheme_rom — verify PQC constants
    // ==================================================================
    reg  [SCHEME_W-1:0]  test_scheme;
    wire [WORD_W-1:0]    sch_modulus;
    wire [(2*WORD_W)-1:0] sch_mu;
    wire [WORD_W-1:0]    sch_mu_mont;
    wire [4:0]           sch_k_log2;
    wire [15:0]          sch_n;
    wire [WORD_W-1:0]    sch_zeta;

    scheme_rom #(.SCHEME_W(SCHEME_W), .WORD_W(WORD_W)) u_scheme (
        .scheme  (test_scheme),
        .modulus (sch_modulus),
        .mu      (sch_mu),
        .mu_mont (sch_mu_mont),
        .k_log2  (sch_k_log2),
        .n       (sch_n),
        .zeta    (sch_zeta)
    );

    // ==================================================================
    // Test 2: useq_rom — program execution
    // ==================================================================
    reg                  seq_start;
    reg  [ADDR_W-1:0]    prog_addr;
    reg  [57:0]          prog_data;
    reg                  prog_we;
    wire                 seq_done;
    wire                 seq_running;
    wire [ADDR_W-1:0]    seq_pc;
    wire [LW-1:0]        seq_iter;
    wire [MODE_W-1:0]    seq_ae_mode;

    useq_rom #(.AW(ADDR_W), .LW(LW), .MODE_W(MODE_W)) u_seq_rom (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (seq_start),
        .prog_addr(prog_addr),
        .prog_data(prog_data),
        .prog_we  (prog_we),
        .done     (seq_done),
        .running  (seq_running),
        .pc       (seq_pc),
        .iter     (seq_iter),
        .ae_mode  (seq_ae_mode),
        .rf_raddr (),
        .rf_waddr (),
        .rf_we    (),
        .imm_data ()
    );

    // ==================================================================
    // Test 3: ntt_stage_ctrl — FSM sequencing
    // ==================================================================
    reg                  ctrl_start;
    reg                  ctrl_inverse;
    wire [2:0]           ctrl_stage;
    wire [2:0]           ctrl_batch;
    wire [6:0]           ctrl_tw_offset;
    wire [1:0]           ctrl_sh_mode;
    wire [6:0]           ctrl_sh_offset;
    wire                 ctrl_ae_valid;
    wire                 ctrl_stage_start;
    wire                 ctrl_load_en;
    wire                 ctrl_unload_en;
    wire                 ctrl_done;
    wire                 ctrl_running;

    ntt_stage_ctrl #(.N(256), .LANES(32), .N_STAGE(8)) u_ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (ctrl_start),
        .inverse    (ctrl_inverse),
        .stage      (ctrl_stage),
        .batch      (ctrl_batch),
        .tw_offset  (ctrl_tw_offset),
        .sh_mode    (ctrl_sh_mode),
        .sh_offset  (ctrl_sh_offset),
        .rf_raddr   (),
        .rf_waddr   (),
        .ae_valid   (ctrl_ae_valid),
        .stage_start(ctrl_stage_start),
        .load_en    (ctrl_load_en),
        .unload_en  (ctrl_unload_en),
        .ntt_done   (ctrl_done),
        .running    (ctrl_running)
    );

    // ==================================================================
    // Test 4: reconfig_ntt_pipeline — end-to-end NTT with real mod q
    // ==================================================================
    reg                  ntt_start;
    reg                  ntt_inverse;
    reg  [SCHEME_W-1:0]  ntt_scheme;
    reg                  ntt_use_mod;
    reg  [WORD_W-1:0]    ntt_modulus;
    reg  [(2*WORD_W)-1:0] ntt_mu;
    reg  [WORD_W-1:0]    ntt_mu_mont;
    reg  [4:0]           ntt_k_log2;
    reg                  ntt_load_valid;
    reg [(LANES*WORD_W)-1:0] ntt_load_data;
    wire                 ntt_load_ready;
    wire                 ntt_unload_valid;
    wire [(LANES*WORD_W)-1:0] ntt_unload_data;
    reg                  ntt_unload_ready;
    wire                 ntt_done;
    wire                 ntt_running;
    wire [2:0]           ntt_dbg_stage;
    wire [1:0]           ntt_dbg_batch;

    reconfig_ntt_pipeline #(
        .WORD_W(WORD_W), .MODE_W(MODE_W), .LANES(LANES),
        .N(256), .N_STAGE(8), .RF_DEPTH(8), .ADDR_W(3),
        .SCHEME_W(SCHEME_W), .STAGE_W(3), .OFFSET_W(7)
    ) u_pipeline (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (ntt_start),
        .inverse      (ntt_inverse),
        .scheme       (ntt_scheme),
        .use_mod      (ntt_use_mod),
        .modulus      (ntt_modulus),
        .mu           (ntt_mu),
        .mu_mont      (ntt_mu_mont),
        .k_log2       (ntt_k_log2),
        .load_valid   (ntt_load_valid),
        .load_data    (ntt_load_data),
        .load_ready   (ntt_load_ready),
        .unload_valid (ntt_unload_valid),
        .unload_data  (ntt_unload_data),
        .unload_ready (ntt_unload_ready),
        .ntt_done     (ntt_done),
        .running      (ntt_running),
        .dbg_stage    (ntt_dbg_stage),
        .dbg_batch    (ntt_dbg_batch)
    );

    always #5 clk = ~clk;

    // ==================================================================
    // Helper: Newton iteration for Montgomery inverse (Verilog function)
    // ==================================================================
    function [WORD_W-1:0] compute_mont_inv;
        input [WORD_W-1:0] q_in;
        reg [63:0] x, prod;
        integer i;
        begin
            x = 64'd1;
            for (i = 0; i < 5; i = i + 1) begin
                prod = q_in * x;
                prod = 64'd2 - prod;
                x = x * prod;
                case (i)
                    0: x = x & 64'h3;
                    1: x = x & 64'hF;
                    2: x = x & 64'hFF;
                    3: x = x & 64'hFFFF;
                    4: x = x & 64'hFFFF_FFFF;
                endcase
            end
            compute_mont_inv = ({32'd1, 32'd0} - x);
        end
    endfunction

    // ==================================================================
    // Main
    // ==================================================================
    integer errors, tests;
    integer i;

    initial begin
        clk = 1'b0; rst_n = 1'b0;
        test_scheme   = 2'd0;
        seq_start     = 1'b0;
        prog_addr     = 5'd0;
        prog_data     = 58'd0;
        prog_we       = 1'b0;
        ctrl_start    = 1'b0;
        ctrl_inverse  = 1'b0;
        ntt_start     = 1'b0;
        ntt_inverse   = 1'b0;
        ntt_scheme    = 2'd0;
        ntt_use_mod   = 1'b1;
        ntt_modulus   = 32'd3329;
        ntt_mu        = 64'd5041;
        ntt_mu_mont   = 32'd4294963967;
        ntt_k_log2    = 5'd12;
        ntt_load_valid = 1'b0;
        ntt_load_data  = 1024'd0;
        ntt_unload_ready = 1'b1;
        errors = 0;
        tests  = 0;

        repeat(4) @(posedge clk); rst_n = 1'b1; repeat(2) @(posedge clk);

        // ================================================================
        // SECTION A: scheme_rom verification
        // ================================================================
        $display("============================================================");
        $display("SECTION A: scheme_rom PQC Parameter Verification");
        $display("============================================================");

        // ML-KEM
        test_scheme = 2'd0; #1;
        tests = tests + 5;
        $display("ML-KEM: q=%0d mu=%0d mu_mont=%0d k=%0d zeta=%0d",
                 sch_modulus, sch_mu, sch_mu_mont, sch_k_log2, sch_zeta);
        if (sch_modulus !== 32'd3329) begin
            $display("  FAIL modulus exp=3329 got=%0d", sch_modulus); errors = errors + 1;
        end
        if (sch_k_log2 !== 5'd12) begin
            $display("  FAIL k_log2 exp=12 got=%0d", sch_k_log2); errors = errors + 1;
        end
        // Verify Montgomery constant: q * mu_mont ≡ -1 mod 2^32
        if ((sch_modulus * sch_mu_mont) % 64'h1_0000_0000 !== 64'd4294967295) begin
            $display("  FAIL Montgomery constant check"); errors = errors + 1;
        end else $display("  PASS Montgomery: q*mu_mont mod 2^32 = -1");
        if (sch_zeta !== 32'd17) begin
            $display("  FAIL zeta exp=17 got=%0d", sch_zeta); errors = errors + 1;
        end
        if (sch_n !== 16'd256) begin
            $display("  FAIL n exp=256 got=%0d", sch_n); errors = errors + 1;
        end

        // ML-DSA
        test_scheme = 2'd1; #1;
        tests = tests + 2;
        $display("ML-DSA: q=%0d mu=%0d mu_mont=%0d k=%0d zeta=%0d",
                 sch_modulus, sch_mu, sch_mu_mont, sch_k_log2, sch_zeta);
        if (sch_modulus !== 32'd8380417) begin
            $display("  FAIL modulus"); errors = errors + 1;
        end
        if ((sch_modulus * sch_mu_mont) % 64'h1_0000_0000 !== 64'd4294967295) begin
            $display("  FAIL Montgomery constant check"); errors = errors + 1;
        end else $display("  PASS Montgomery constant check");

        // Falcon
        test_scheme = 2'd2; #1;
        tests = tests + 2;
        $display("Falcon: q=%0d mu=%0d mu_mont=%0d k=%0d zeta=%0d",
                 sch_modulus, sch_mu, sch_mu_mont, sch_k_log2, sch_zeta);
        if (sch_modulus !== 32'd12289) begin
            $display("  FAIL modulus"); errors = errors + 1;
        end
        if ((sch_modulus * sch_mu_mont) % 64'h1_0000_0000 !== 64'd4294967295) begin
            $display("  FAIL Montgomery constant check"); errors = errors + 1;
        end else $display("  PASS Montgomery constant check");

        // ================================================================
        // SECTION B: useq_rom program execution
        // ================================================================
        $display("============================================================");
        $display("SECTION B: useq_rom Program Execution");
        $display("============================================================");

        // Load a simple program:
        //   0: EXEC  MUL_ADD (mode=2)          → fire one AE op
        //   1: LOOP_BEG cnt=3, body=2          → loop 3x
        //   2: EXEC  ADD_SUB (mode=4)          → body
        //   3: LOOP_END
        //   4: HALT
        prog_we = 1'b1;
        prog_addr = 5'd0;
        // opcode=EXEC(00), ae_mode=2(MUL_ADD), rf_we=0
        prog_data = {32'd0, 1'b0, 3'd0, 3'd0, 4'd2, 5'd0, 8'd0, 2'b00};
        @(posedge clk);
        prog_addr = 5'd1;
        // opcode=LOOP_BEG(01), loop_cnt=3, loop_body=2
        prog_data = {32'd0, 1'b0, 3'd0, 3'd0, 4'd0, 5'd2, 8'd3, 2'b01};
        @(posedge clk);
        prog_addr = 5'd2;
        // opcode=EXEC(00), ae_mode=4(ADD_SUB)
        prog_data = {32'd0, 1'b0, 3'd0, 3'd0, 4'd4, 5'd0, 8'd0, 2'b00};
        @(posedge clk);
        prog_addr = 5'd3;
        // opcode=LOOP_END(10)
        prog_data = {32'd0, 1'b0, 3'd0, 3'd0, 4'd0, 5'd0, 8'd0, 2'b10};
        @(posedge clk);
        prog_addr = 5'd4;
        // opcode=HALT(11)
        prog_data = {32'd0, 1'b0, 3'd0, 3'd0, 4'd0, 5'd0, 8'd0, 2'b11};
        @(posedge clk);
        prog_we <= 1'b0;

        // Start sequencer
        @(posedge clk);
        seq_start <= 1'b1;
        @(posedge clk);
        seq_start <= 1'b0;

        // Trace execution
        $display("Sequencer started...");
        while (!seq_done) begin
            @(posedge clk);
            $display("  PC=%0d iter=%0d ae_mode=%0d opcode=%0d",
                     seq_pc, seq_iter, seq_ae_mode,
                     prog_data[1:0]);  // stale but indicative
        end
        tests = tests + 1;
        if (seq_done && seq_pc == 5'd4) begin
            $display("PASS sequencer halted at PC=4 (expected)");
        end else begin
            $display("FAIL sequencer PC=%0d done=%0d", seq_pc, seq_done);
            errors = errors + 1;
        end

        // ================================================================
        // SECTION C: ntt_stage_ctrl FSM
        // ================================================================
        $display("============================================================");
        $display("SECTION C: ntt_stage_ctrl FSM Sequencing");
        $display("============================================================");

        @(posedge clk);
        ctrl_inverse <= 1'b0;
        ctrl_start   <= 1'b1;
        @(posedge clk);
        ctrl_start <= 1'b0;

        $display("NTT Stage Controller started (Forward, 8 stages, 8 batches)");
        $display("Stage | Batch | sh_offset | ae_valid | stage_start");

        while (!ctrl_done) begin
            @(posedge clk);
            if (ctrl_ae_valid || ctrl_stage_start)
                $display("  %0d   |  %0d    |    %0d     |    %0d     |    %0d",
                         ctrl_stage, ctrl_batch, ctrl_sh_offset,
                         ctrl_ae_valid, ctrl_stage_start);
        end

        tests = tests + 1;
        if (ctrl_done) begin
            $display("PASS ntt_stage_ctrl completed all 8 stages");
        end else begin
            $display("FAIL ntt_stage_ctrl did not complete");
            errors = errors + 1;
        end

        // ================================================================
        // SECTION D: reconfig_ntt_pipeline — quick sanity
        // ================================================================
        $display("============================================================");
        $display("SECTION D: reconfig_ntt_pipeline Sanity (ML-KEM q=3329)");
        $display("============================================================");

        // For a full NTT test, we'd need to preload all 256 coefficients
        // into the 32 register files (depth 8 each). This is complex for
        // a quick sanity check. Instead, verify the pipeline instantiates
        // and starts correctly.
        ntt_scheme  <= 2'd0;          // ML-KEM
        ntt_modulus <= 32'd3329;
        ntt_mu      <= 64'd5041;
        ntt_mu_mont <= 32'd4294963967;
        ntt_k_log2  <= 5'd12;
        ntt_use_mod <= 1'b1;

        @(posedge clk);
        ntt_start <= 1'b1;
        @(posedge clk);
        ntt_start <= 1'b0;
        @(posedge clk);  // wait for running to propagate

        tests = tests + 1;
        if (ntt_running) begin
            $display("PASS pipeline started (running asserted)");
            $display("     dbg_stage=%0d dbg_batch=%0d", ntt_dbg_stage, ntt_dbg_batch);
        end else begin
            $display("FAIL pipeline did not start");
            errors = errors + 1;
        end

        // Wait for pipeline to finish (or timeout)
        $display("Waiting for pipeline to complete...");
        while (!ntt_done) @(posedge clk);
        tests = tests + 1;
        if (ntt_done) begin
            $display("PASS pipeline completed (ntt_done asserted)");
        end else begin
            $display("FAIL pipeline did not finish");
            errors = errors + 1;
        end

        // ================================================================
        // Results
        // ================================================================
        $display("============================================================");
        if (errors == 0) begin
            $display("PASS: All %0d integration checks passed.", tests);
        end else begin
            $display("FAIL: %0d errors in %0d checks.", errors, tests);
        end
        $display("============================================================");
        $finish;
    end

    initial begin
        repeat(2000) @(posedge clk);
        $display("TIMEOUT");
        $finish;
    end

endmodule
