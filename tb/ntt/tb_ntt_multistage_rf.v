`timescale 1ns/1ps

// Multi-stage NTT test with per-lane register files (P3).
// 2-lane, Falcon field q=12289.  Shows RF load, butterfly with shuffle,
// cross-lane write, and 2nd butterfly from RF — all without external
// memory reload between stages.

module tb_ntt_multistage_rf;

    localparam WORD_W = 32;
    localparam MODE_W = 4;
    localparam DEPTH  = 4;
    localparam ADDR_W = 2;
    localparam LANES  = 2;
    localparam CLOG2  = 1;

    localparam [MODE_W-1:0] M_CT_BFU  = 4'd0;
    localparam [MODE_W-1:0] M_ADD_SUB = 4'd4;

    reg                  clk, rst_n, valid_in, use_mod;
    reg  [WORD_W-1:0]    modulus;
    reg  [(2*WORD_W)-1:0] mu_val;
    reg  [WORD_W-1:0]    mu_mont;
    reg  [4:0]           k_val;

    // Lane 0
    reg  [MODE_W-1:0]    m_0;
    reg  [WORD_W-1:0]    ea_0, ec_0, ew_0;
    wire [WORD_W-1:0]    eb_0;              // driven by assign (shuffle output)
    reg  [ADDR_W-1:0]    ra0_0, ra1_0, wa_0;
    reg                  ua_0, ub_0, we_0, ws_0;
    wire                 vo_0;
    wire [WORD_W-1:0]    y0_0, y1_0, rda_0, rdb_0;

    // Lane 1
    reg  [MODE_W-1:0]    m_1;
    reg  [WORD_W-1:0]    ea_1, ec_1, ew_1;
    wire [WORD_W-1:0]    eb_1;              // driven by assign (shuffle output)
    reg  [ADDR_W-1:0]    ra0_1, ra1_1, wa_1;
    reg                  ua_1, ub_1, we_1, ws_1;
    wire                 vo_1;
    wire [WORD_W-1:0]    y0_1, y1_1, rda_1, rdb_1;

    // Shuffle
    reg  [1:0]           sh_mode;
    reg  [CLOG2-1:0]     sh_off;
    wire [(LANES*WORD_W)-1:0] sh_in, sh_out;

    // Shuffle b-port routing:  during load (load_mode=1), force b=0.
    // Otherwise, b comes from paired lane's a-data via shuffle.
    reg load_mode;
    reg [WORD_W-1:0] load_val;     // value being loaded into RF
    wire [WORD_W-1:0] eb0_shuf, eb1_shuf;

    assign sh_in   = {rda_1, rda_0};
    assign eb0_shuf = sh_out[0*WORD_W +: WORD_W];
    assign eb1_shuf = sh_out[1*WORD_W +: WORD_W];
    assign eb_0    = load_mode ? 32'd0 : eb0_shuf;
    assign eb_1    = load_mode ? 32'd0 : eb1_shuf;

    // DUTs
    reconfig_ae_rf #(.WORD_W(WORD_W),.MODE_W(MODE_W),.DEPTH(DEPTH),.ADDR_W(ADDR_W)) u0 (
        .clk(clk),.rst_n(rst_n),.valid_in(valid_in),.mode(m_0),
        .use_mod(use_mod),.modulus(modulus),.mu(mu_val),.mu_mont(mu_mont),.k_log2(k_val),
        .ext_a(ea_0),.ext_b(eb_0),.ext_c(ec_0),.ext_w(ew_0),
        .rf_raddr_a(ra0_0),.rf_raddr_b(ra1_0),
        .use_rf_a(ua_0),.use_rf_b(ub_0),
        .rf_waddr(wa_0),.rf_we(we_0),.rf_wsel(ws_0),
        .valid_out(vo_0),.y0(y0_0),.y1(y1_0),
        .acc_clr(1'b0),.acc_out(),
        .rf_rdata_a(rda_0),.rf_rdata_b(rdb_0)
    );
    reconfig_ae_rf #(.WORD_W(WORD_W),.MODE_W(MODE_W),.DEPTH(DEPTH),.ADDR_W(ADDR_W)) u1 (
        .clk(clk),.rst_n(rst_n),.valid_in(valid_in),.mode(m_1),
        .use_mod(use_mod),.modulus(modulus),.mu(mu_val),.mu_mont(mu_mont),.k_log2(k_val),
        .ext_a(ea_1),.ext_b(eb_1),.ext_c(ec_1),.ext_w(ew_1),
        .rf_raddr_a(ra0_1),.rf_raddr_b(ra1_1),
        .use_rf_a(ua_1),.use_rf_b(ub_1),
        .rf_waddr(wa_1),.rf_we(we_1),.rf_wsel(ws_1),
        .valid_out(vo_1),.y0(y0_1),.y1(y1_1),
        .acc_clr(1'b0),.acc_out(),
        .rf_rdata_a(rda_1),.rf_rdata_b(rdb_1)
    );
    shuffle_net #(.WORD_W(WORD_W),.LANES(LANES),.CLOG2(CLOG2)) sh (
        .data_in(sh_in),.offset(sh_off),.mode(sh_mode),.data_out(sh_out)
    );

    always #5 clk = ~clk;

    function [4:0] ck; input [31:0] q; integer i;
        begin ck=5'd0; for(i=31;i>=0;i=i-1) if(q[i]&&(ck==5'd0)) ck=i+1; end
    endfunction
    function [63:0] cmu; input [31:0] q; input [4:0] k; reg [95:0] n;
        begin if(k>0&&q>1) begin n=96'd0; n[2*k]=1'b1; cmu=n/q; end else cmu=64'd0; end
    endfunction

    integer errors, tests;

    // ---- Pipeline helpers ----
    // Fire one operation:  assert valid_in for 1 cycle, wait 4 for result.
    task fire_op;
        begin
            @(posedge clk);
            valid_in <= 1'b1;
            @(posedge clk);
            valid_in <= 1'b0;
            repeat (3) @(posedge clk);  // pipeline drain
        end
    endtask

    // Load a value into a lane's RF by running ADD-SUB(a=val,b=0) → y0=val
    task load;
        input integer ln;     // 0 or 1
        input [ADDR_W-1:0] ad;
        input [WORD_W-1:0]  vl;
        begin
            load_mode <= 1'b1;   // bypass shuffle, force b=0
            @(posedge clk);
            if (ln == 0) begin
                m_0 <= M_ADD_SUB; ea_0 <= vl;
                ua_0<=1'b0; ub_0<=1'b0; we_0<=1'b1; wa_0<=ad; ws_0<=1'b0;
            end else begin
                m_1 <= M_ADD_SUB; ea_1 <= vl;
                ua_1<=1'b0; ub_1<=1'b0; we_1<=1'b1; wa_1<=ad; ws_1<=1'b0;
            end
            valid_in <= 1'b1;
            @(posedge clk);      // AE captures S0 (H)
            valid_in <= 1'b0;
            // valid_in→valid_s0→valid_s1→valid_s2→valid_out: 5 posedge total
            repeat (5) @(posedge clk);  // I,J,K,L,M — valid_out fires at M
            we_0 <= 1'b0; we_1 <= 1'b0;
            load_mode <= 1'b0;
        end
    endtask

    // Drive a butterfly: both lanes CT_BFU, a from RF[aa], b from shuffle
    task butterfly;
        input [ADDR_W-1:0] aa;          // RF addr for a operand
        input [WORD_W-1:0]  tw;          // twiddle factor
        input               wb_l0;       // writeback lane0 y0 → RF[?]
        input [ADDR_W-1:0] wba0;
        begin
            @(posedge clk);
            m_0 <= M_CT_BFU; m_1 <= M_CT_BFU;
            ua_0 <= 1'b1; ra0_0 <= aa;   // a from RF
            ub_0 <= 1'b0;                // b from ext (shuffle)
            ua_1 <= 1'b1; ra0_1 <= aa;
            ub_1 <= 1'b0;
            ew_0 <= tw; ew_1 <= tw;
            ec_0 <= 32'd0; ec_1 <= 32'd0;
            we_0 <= wb_l0 ? 1'b1 : 1'b0;
            wa_0 <= wba0; ws_0 <= 1'b0;  // write y0
            we_1 <= 1'b0;
            valid_in <= 1'b1;
            @(posedge clk);      // AE captures S0
            valid_in <= 1'b0;
            // 5 cycles: S0→S1→S2→out reg → valid_out visible
            repeat (5) @(posedge clk);
            we_0 <= 1'b0;
        end
    endtask

    initial begin
        clk=1'b0; rst_n=1'b0; valid_in=1'b0; use_mod=1'b0;
        modulus=32'd0; mu_val=64'd0; mu_mont=32'd0; k_val=5'd0;
        m_0=0; m_1=0; ea_0=0; ec_0=0; ew_0=0;
        ea_1=0; ec_1=0; ew_1=0;
        ra0_0=0; ra1_0=0; wa_0=0; ua_0=0; ub_0=0; we_0=0; ws_0=0;
        ra0_1=0; ra1_1=0; wa_1=0; ua_1=0; ub_1=0; we_1=0; ws_1=0;
        sh_mode=0; sh_off=0;
        load_mode=1'b0; load_val=32'd0;
        errors=0; tests=0;

        repeat (4) @(posedge clk); rst_n=1'b1; repeat (2) @(posedge clk);

        use_mod=1'b1; modulus=32'd12289; k_val=ck(modulus); mu_val=cmu(modulus,k_val);
        sh_mode <= 2'b01; sh_off <= 1'd1;  // XOR offset=1

        // === Load coefficients ===
        $display("=== P3: Register File Multi-Stage NTT ===");
        load(0, 2'd0, 32'd1000);
        load(1, 2'd0, 32'd3000);
        $display("LOAD: lane0 RF[0]=%0d  lane1 RF[0]=%0d", rda_0, rda_1);

        // === Stage 1: butterfly offset=1, w=7 ===
        // Write y0_0 (new_a0) to lane0 RF[0]
        butterfly(2'd0, 32'd7, 1'b1, 2'd0);
        #1;  // let outputs settle
        $display("STAGE1: y0_0=%0d (expect 9711)  y1_0=%0d (expect 4578)", y0_0, y1_0);
        tests=tests+2;
        if(y0_0!==32'd9711) begin $display("FAIL y0_0"); errors=errors+1; end
        if(y1_0!==32'd4578) begin $display("FAIL y1_0"); errors=errors+1; end

        // Cross-lane: write lane0 y1 → lane1 RF[0] (new_a1)
        load(1, 2'd0, y1_0);
        $display("XFER: lane1 RF[0]=%0d (expect 4578)", rda_1);
        tests=tests+2;
        if(rda_0!==32'd9711) begin $display("FAIL lane0 RF[0]"); errors=errors+1; end
        if(rda_1!==32'd4578) begin $display("FAIL lane1 RF[0]"); errors=errors+1; end

        // === Stage 2: second butterfly from register file, w=3 ===
        // Both lanes read RF[0], shuffle routes paired data to b-port
        butterfly(2'd0, 32'd3, 1'b1, 2'd1);  // write y0_0 → RF[1]
        #1;
        $display("STAGE2: y0_0=%0d (expect 11156)  y1_0=%0d (expect 8266)", y0_0, y1_0);
        tests=tests+2;
        if(y0_0!==32'd11156) begin $display("FAIL y0_0 stage2"); errors=errors+1; end
        if(y1_0!==32'd8266) begin $display("FAIL y1_0 stage2"); errors=errors+1; end

        if(errors==0)
            $display("TB_PASS all %0d checks (P3 multi-stage NTT with RF)", tests);
        else
            $display("TB_FAIL %0d errors in %0d checks", errors, tests);
        $finish;
    end

    initial begin repeat(500) @(posedge clk); $display("TB_FAIL timeout"); $finish; end

endmodule
