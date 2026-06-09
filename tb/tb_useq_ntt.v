`timescale 1ns/1ps

// P5: Micro-sequencer demonstration.
//
// useq_core drives a single AE through a 3-iteration multiply-accumulate
// loop, then reads the accumulator.  The μProgram ROM is embedded in
// the testbench (combinational decode).
//
// μProgram:
//   0: LOOP_BEG  cnt=3  body=1
//   1: EXEC  MUL_ACC                    // acc += a*b
//   2: LOOP_END                         // loop 3x, then fall through
//   3: EXEC  ACC_RD                     // read acc → y0,y1
//   4: HALT
//
// The testbench supplies different (a,b) pairs on each iteration via a
// simple counter, simulating external data feeding.

module tb_useq_ntt;

    localparam WORD_W = 32;
    localparam MODE_W = 3;
    localparam AW     = 5;    // sequencer address width
    localparam LW     = 8;    // loop counter width

    localparam [MODE_W-1:0] M_MUL_ACC = 3'd6;
    localparam [MODE_W-1:0] M_ACC_RD  = 3'd7;

    // ---- μProgram ROM ----
    // Opcode encoding: 0=EXEC, 1=LOOP_BEG, 2=LOOP_END, 3=HALT
    reg [1:0]   rom_op  [0:15];
    reg [LW-1:0] rom_lcnt[0:15];
    reg [AW-1:0] rom_body[0:15];
    reg [MODE_W-1:0] rom_mode[0:15];

    initial begin
        // 0: LOOP_BEG cnt=3, body at PC=1
        rom_op  [0] = 2'b01; rom_lcnt[0] = 8'd3; rom_body[0] = 5'd1; rom_mode[0] = 3'd0;
        // 1: EXEC MUL_ACC
        rom_op  [1] = 2'b00; rom_lcnt[1] = 8'd0; rom_body[1] = 5'd0; rom_mode[1] = M_MUL_ACC;
        // 2: LOOP_END
        rom_op  [2] = 2'b10; rom_lcnt[2] = 8'd0; rom_body[2] = 5'd0; rom_mode[2] = 3'd0;
        // 3: EXEC ACC_RD
        rom_op  [3] = 2'b00; rom_lcnt[3] = 8'd0; rom_body[3] = 5'd0; rom_mode[3] = M_ACC_RD;
        // 4: HALT
        rom_op  [4] = 2'b11; rom_lcnt[4] = 8'd0; rom_body[4] = 5'd0; rom_mode[4] = 3'd0;
        // 5-15: unused
    end

    // ---- Sequencer core ----
    reg                 clk, rst_n, start;
    wire [1:0]          opcode;
    wire [LW-1:0]       loop_cnt;
    wire [AW-1:0]       loop_body;
    wire [AW-1:0]       pc;
    wire                done, running;
    wire [LW-1:0]       iter;

    // ROM read (combinational)
    assign opcode    = rom_op[pc];
    assign loop_cnt  = rom_lcnt[pc];
    assign loop_body = rom_body[pc];

    useq_core #(.AW(AW), .LW(LW)) u_seq (
        .clk(clk), .rst_n(rst_n), .start(start),
        .opcode(opcode), .loop_cnt(loop_cnt), .loop_body(loop_body),
        .pc(pc), .done(done), .running(running), .iter(iter)
    );

    // ---- AE under sequencer control ----
    reg                  valid_in;
    reg  [MODE_W-1:0]    ae_mode;
    reg                  acc_clr;
    reg  [WORD_W-1:0]    a, b;
    wire                 valid_out;
    wire [WORD_W-1:0]    y0, y1;
    wire [(2*WORD_W)-1:0] acc_out;

    reconfig_ae #(.WORD_W(WORD_W), .MODE_W(MODE_W)) u_ae (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .mode(ae_mode),
        .use_mod(1'b0), .modulus(32'd0), .mu(64'd0), .k_log2(5'd0),
        .a(a), .b(b), .c(32'd0), .w(32'd0),
        .valid_out(valid_out), .y0(y0), .y1(y1),
        .acc_clr(acc_clr), .acc_out(acc_out)
    );

    always #5 clk = ~clk;

    // ---- Test data generator ----
    // Supplies different (a,b) each iteration: (2,3), (4,5), (6,7)
    // Expected acc = 2*3 + 4*5 + 6*7 = 6 + 20 + 42 = 68
    reg [1:0] iter_prev;
    reg       new_iter;

    always @(posedge clk) begin
        if (rst_n == 1'b0) begin
            iter_prev <= 2'd0;
            new_iter  <= 1'b0;
        end else begin
            new_iter <= (iter[1:0] != iter_prev);  // detect iteration change
            iter_prev <= iter[1:0];
        end
    end

    // Combinational: drive a,b based on current iteration
    always @(*) begin
        case (iter[1:0])
            2'd0: begin a = 32'd2;  b = 32'd3;  end   // 2*3 = 6
            2'd1: begin a = 32'd4;  b = 32'd5;  end   // 4*5 = 20
            2'd2: begin a = 32'd6;  b = 32'd7;  end   // 6*7 = 42
            default: begin a = 32'd0; b = 32'd0; end
        endcase
    end

    // ---- Sequencer → AE control glue ----
    // When the sequencer is at an EXEC instruction, fire valid_in.
    // acc_clr is asserted on the FIRST iteration of the loop.
    reg clear_next;

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            valid_in   <= 1'b0;
            ae_mode    <= 3'd0;
            acc_clr    <= 1'b0;
            clear_next <= 1'b0;
        end else begin
            if (running && opcode == 2'b00) begin  // EXEC
                ae_mode  <= rom_mode[pc];
                // acc_clr on first EXEC of the program
                if (pc == 5'd1 && iter == 8'd2)   // first iteration (iter=loop_cnt-1=2)
                    acc_clr <= 1'b1;
                else
                    acc_clr <= 1'b0;
                valid_in <= 1'b1;
            end else begin
                valid_in <= 1'b0;
            end
        end
    end

    // ---- Main test sequence ----
    integer errors, tests;
    reg [63:0] exp_acc;

    initial begin
        clk = 1'b0; rst_n = 1'b0; start = 1'b0;
        valid_in = 1'b0; ae_mode = 3'd0; acc_clr = 1'b0;
        a = 0; b = 0; clear_next = 1'b0;
        errors = 0; tests = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Start the sequencer
        $display("=== P5: Micro-Sequencer MUL_ACC Loop ===");
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // Wait for done
        while (!done) @(posedge clk);
        $display("Sequencer halted at PC=%0d", pc);

        // Wait for final ACC_RD pipeline to drain
        repeat (6) @(posedge clk);
        #1;

        // Verify accumulator: 2*3 + 4*5 + 6*7 = 6 + 20 + 42 = 68
        exp_acc = 64'd6 + 64'd20 + 64'd42;
        tests = tests + 1;
        if (acc_out !== exp_acc) begin
            $display("FAIL acc_out=%0d expected %0d", acc_out, exp_acc);
            errors = errors + 1;
        end else begin
            $display("PASS acc_out = %0d", acc_out);
        end

        // Verify ACC_RD readback
        tests = tests + 1;
        if ({y1, y0} !== exp_acc) begin
            $display("FAIL ACC_RD: {y1,y0}=%h expected %h", {y1, y0}, exp_acc);
            errors = errors + 1;
        end else begin
            $display("PASS ACC_RD: {y1,y0} = %0d", {y1, y0});
        end

        if (errors == 0)
            $display("TB_PASS all %0d checks (P5 micro-sequencer)", tests);
        else
            $display("TB_FAIL %0d errors in %0d checks", errors, tests);
        $finish;
    end

    initial begin repeat(600) @(posedge clk); $display("TB_FAIL timeout"); $finish; end

endmodule
