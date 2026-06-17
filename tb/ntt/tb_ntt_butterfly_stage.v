`timescale 1ns/1ps

// P2: NTT butterfly with shuffle — fixed 32-lane AE array.
// Tests 4 active lanes (0-3) forming 2 butterfly pairs.

module tb_ntt_butterfly_stage;

    localparam WORD_W = 32;
    localparam MODE_W = 4;

    localparam [MODE_W-1:0] M_CT_BFU = 4'd0;

    reg                 clk, rst_n, valid_in;
    reg  [127:0]        mode_vec;
    reg                 use_mod;
    reg  [31:0]         modulus;
    reg  [63:0]         mu_val;
    reg  [31:0]         mu_mont;
    reg  [4:0]          k_val;
    reg  [1023:0]       a_vec, b_vec, c_vec, w_vec;
    wire                valid_out;
    wire [1023:0]       y0_vec, y1_vec;
    wire [2047:0]       acc_out;

    reg  [127:0]        shuf_in;       // 4 lanes × 32 bit
    wire [127:0]        shuf_out;
    reg  [1:0]          shuf_off, shuf_mode;

    reconfig_ae_array dut (
        .clk(clk),.rst_n(rst_n),.valid_in(valid_in),.mode_vec(mode_vec),
        .use_mod(use_mod),.modulus(modulus),.mu(mu_val),.mu_mont(mu_mont),.k_log2(k_val),
        .a_vec(a_vec),.b_vec(b_vec),.c_vec(c_vec),.w_vec(w_vec),
        .valid_out(valid_out),.y0_vec(y0_vec),.y1_vec(y1_vec),
        .acc_clr(1'b0),.acc_out_vec(acc_out)
    );

    // 4-lane shuffle for lanes 0-3 only
    shuffle_net #(.WORD_W(WORD_W),.LANES(4),.CLOG2(2)) u_shuf (
        .data_in(shuf_in),.offset(shuf_off),.mode(shuf_mode),.data_out(shuf_out)
    );

    always #5 clk = ~clk;

    wire [31:0] eb0 = shuf_out[  0*WORD_W +: WORD_W];
    wire [31:0] eb1 = shuf_out[  1*WORD_W +: WORD_W];
    wire [31:0] eb2 = shuf_out[  2*WORD_W +: WORD_W];
    wire [31:0] eb3 = shuf_out[  3*WORD_W +: WORD_W];

    // Route shuffle output to b_vec for lanes 0-3; other lanes get 0
    always @(*) begin
        b_vec = 1024'd0;
        b_vec[  0*WORD_W +: WORD_W] = eb0;
        b_vec[  1*WORD_W +: WORD_W] = eb1;
        b_vec[  2*WORD_W +: WORD_W] = eb2;
        b_vec[  3*WORD_W +: WORD_W] = eb3;
    end

    function [4:0] ck; input [31:0] q; integer i;
        begin ck=5'd0; for(i=31;i>=0;i=i-1) if(q[i]&&(ck==5'd0)) ck=i+1; end
    endfunction
    function [63:0] cmu; input [31:0] q; input [4:0] k; reg [95:0] n;
        begin if(k>0&&q>1) begin n=96'd0; n[2*k]=1'b1; cmu=n/q; end else cmu=64'd0; end
    endfunction
    function [31:0] ntt_top; input [31:0] a,b,w,q; reg [63:0] p;
        begin p=b*w; ntt_top=(a+(p%q))%q; end
    endfunction
    function [31:0] ntt_bot; input [31:0] a,b,w,q; reg [63:0] p; reg [31:0] pw;
        begin p=b*w; pw=p%q; ntt_bot=(a>=pw)?(a-pw):(a+q-pw)%q; end
    endfunction

    integer errors, tests;
    reg [31:0] ey0, ey1;

    task run_butterfly;
        input [31:0] a0,a1,a2,a3, w01,w23, q;
        begin
            // set up a_vec for lanes 0-3; routing: lane i a = a_i
            a_vec = 1024'd0;
            a_vec[0*WORD_W +: WORD_W] = a0;
            a_vec[1*WORD_W +: WORD_W] = a1;
            a_vec[2*WORD_W +: WORD_W] = a2;
            a_vec[3*WORD_W +: WORD_W] = a3;
            // w_vec: twiddle per pair
            w_vec = 1024'd0;
            w_vec[0*WORD_W +: WORD_W] = w01;
            w_vec[1*WORD_W +: WORD_W] = w01;
            w_vec[2*WORD_W +: WORD_W] = w23;
            w_vec[3*WORD_W +: WORD_W] = w23;
            c_vec = 1024'd0;

            // shuffle: route a of paired lane to b
            shuf_in = {a3,a2,a1,a0};
            shuf_mode = 2'b01;   // XOR
            shuf_off  = 2'd1;    // adjacent swap
            #1;
            // b_vec updated by always @(*)

            @(posedge clk);
            valid_in<=1'b1; use_mod<=1'b1; modulus<=q;
            k_val<=ck(q); mu_val<=cmu(q,ck(q));
            @(posedge clk); valid_in<=1'b0;
            repeat(5) @(posedge clk); #1;

            // verify pair (0,1)
            ey0 = ntt_top(a0,a1,w01,q);
            ey1 = ntt_bot(a0,a1,w01,q);
            tests=tests+2;
            if(y0_vec[0*WORD_W +: WORD_W]!==ey0) begin $display("FAIL y0_0=%0d exp=%0d",y0_vec[0*WORD_W+:32],ey0); errors=errors+1; end
            if(y1_vec[0*WORD_W +: WORD_W]!==ey1) begin $display("FAIL y1_0=%0d exp=%0d",y1_vec[0*WORD_W+:32],ey1); errors=errors+1; end
            else $display("PASS pair(0,1) q=%0d",q);

            // verify pair (2,3)
            ey0 = ntt_top(a2,a3,w23,q);
            ey1 = ntt_bot(a2,a3,w23,q);
            tests=tests+2;
            if(y0_vec[2*WORD_W +: WORD_W]!==ey0) begin $display("FAIL y0_2=%0d exp=%0d",y0_vec[2*WORD_W+:32],ey0); errors=errors+1; end
            if(y1_vec[2*WORD_W +: WORD_W]!==ey1) begin $display("FAIL y1_2=%0d exp=%0d",y1_vec[2*WORD_W+:32],ey1); errors=errors+1; end
            else $display("PASS pair(2,3) q=%0d",q);
        end
    endtask

    initial begin
        clk=1'b0; rst_n=1'b0; valid_in=1'b0; mode_vec=128'd0;
        use_mod=1'b0; modulus=0; mu_val=0; mu_mont=0; k_val=0;
        a_vec=0; b_vec=0; c_vec=0; w_vec=0;
        shuf_in=0; shuf_off=0; shuf_mode=0;
        errors=0; tests=0;

        repeat(4) @(posedge clk); rst_n=1'b1; repeat(2) @(posedge clk);
        mode_vec = {96{M_CT_BFU}};  // all lanes CT_BFU

        // Falcon q=12289
        $display("=== Falcon q=12289 ===");
        run_butterfly(1000,3000, 5000,8000, 7,11, 12289);

        // Kyber q=3329
        $display("=== Kyber q=3329 ===");
        run_butterfly(300,800, 1500,2000, 3,5, 3329);

        // Dilithium q=8380417
        $display("=== Dilithium q=8380417 ===");
        run_butterfly(2000000,8000000, 5000000,3000000, 1753,7, 8380417);

        if(errors==0) $display("TB_PASS all %0d checks", tests);
        else          $display("TB_FAIL %0d errors", errors);
        $finish;
    end

    initial begin repeat(500) @(posedge clk); $display("TB_FAIL timeout"); $finish; end

endmodule
