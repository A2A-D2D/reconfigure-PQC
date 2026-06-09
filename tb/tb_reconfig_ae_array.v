`timescale 1ns/1ps

// P1: reconfig_ae_array per-lane mode — 32-lane fixed array.
// Tests heterogeneous mode assignment across 4 selected lanes (0-3)
// while other lanes are driven with zeros.

module tb_reconfig_ae_array;

    localparam WORD_W = 32;
    localparam MODE_W = 3;
    localparam LANES  = 32;

    localparam [MODE_W-1:0] M_CT_BFU  = 3'd0;
    localparam [MODE_W-1:0] M_GS_BFU  = 3'd1;
    localparam [MODE_W-1:0] M_MUL_ADD = 3'd2;
    localparam [MODE_W-1:0] M_ADD_MUL = 3'd3;
    localparam [MODE_W-1:0] M_ADD_SUB = 3'd4;
    localparam [MODE_W-1:0] M_BIG_MUL = 3'd5;

    reg                 clk, rst_n, valid_in;
    reg  [95:0]         mode_vec;
    reg                 use_mod;
    reg  [31:0]         modulus;
    reg  [63:0]         mu_barrett;
    reg  [4:0]          k_log2;
    reg  [1023:0]       a_vec, b_vec, c_vec, w_vec;
    wire                valid_out;
    wire [1023:0]       y0_vec, y1_vec;
    wire [2047:0]       acc_out_vec;

    reconfig_ae_array dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .mode_vec(mode_vec),
        .use_mod(use_mod), .modulus(modulus), .mu(mu_barrett), .k_log2(k_log2),
        .a_vec(a_vec), .b_vec(b_vec), .c_vec(c_vec), .w_vec(w_vec),
        .valid_out(valid_out), .y0_vec(y0_vec), .y1_vec(y1_vec),
        .acc_clr(1'b0), .acc_out_vec(acc_out_vec)
    );

    always #5 clk = ~clk;

    integer errors, tests;
    reg [31:0] exp_y0, exp_y1;

    // helper: set one lane's slice in a 1024-bit vector
    function [1023:0] set_lane;
        input integer ln; input [31:0] val;
        begin
            set_lane = {1024{1'b0}};
            set_lane[ln*32 +: 32] = val;
        end
    endfunction

    function [95:0] set_mode;
        input integer ln; input [2:0] m;
        begin
            set_mode = {96{1'b0}};
            set_mode[ln*3 +: 3] = m;
        end
    endfunction

    function [4:0] ck; input [31:0] q; integer i;
        begin ck=5'd0; for(i=31;i>=0;i=i-1) if(q[i]&&(ck==5'd0)) ck=i+1; end
    endfunction
    function [63:0] cmu; input [31:0] q; input [4:0] k; reg [95:0] n;
        begin if(k>0&&q>1) begin n=96'd0; n[2*k]=1'b1; cmu=n/q; end else cmu=64'd0; end
    endfunction
    function [31:0] ref_red; input [63:0] v; input [31:0] q; input en;
        begin ref_red = (en&&q!=0) ? v%q : v[31:0]; end
    endfunction
    function [31:0] ref_add; input [31:0] l,r,q; input en;
        begin ref_add=ref_red({31'd0,({1'b0,l}+{1'b0,r})},q,en); end
    endfunction
    function [31:0] ref_sub; input [31:0] l,r,q; input en;
        begin if(en&&q!=0) ref_sub=(l>=r)?(l-r):(l+q-r)%q; else ref_sub=l-r; end
    endfunction

    task ref_ae;
        input [2:0]  m; input [31:0] a,b,c,w,q; input en;
        output [31:0] y0,y1;
        reg [31:0] ar,br,cr,wr;
        reg [63:0] pm,pb,pa,ps;
        begin
            ar=ref_red({32'd0,a},q,en); br=ref_red({32'd0,b},q,en);
            cr=ref_red({32'd0,c},q,en); wr=ref_red({32'd0,w},q,en);
            pm=ar*br; pb=br*wr; pa=ref_add(ar,br,q,en)*cr; ps=ref_sub(ar,br,q,en)*wr;
            case(m)
                M_CT_BFU:  begin y0=ref_add(ar,ref_red(pb,q,en),q,en); y1=ref_sub(ar,ref_red(pb,q,en),q,en); end
                M_GS_BFU:  begin y0=ref_add(ar,br,q,en); y1=ref_red(ps,q,en); end
                M_MUL_ADD: begin y0=ref_add(ref_red(pm,q,en),cr,q,en); y1=ref_red(pm,q,en); end
                M_ADD_MUL: begin y0=ref_red(pa,q,en); y1=ref_add(ar,br,q,en); end
                M_ADD_SUB: begin y0=ref_add(ar,br,q,en); y1=ref_sub(ar,br,q,en); end
                M_BIG_MUL: begin y0=pm[31:0]; y1=pm[63:32]; end
                default:   begin y0=0; y1=0; end
            endcase
        end
    endtask

    task check_lane;
        input integer ln; input [2:0] m;
        input [31:0] a,b,c,w,q; input en;
        reg [31:0] ey0,ey1,dy0,dy1;
        begin
            ref_ae(m,a,b,c,w,q,en,ey0,ey1);
            dy0 = y0_vec[ln*32 +: 32];
            dy1 = y1_vec[ln*32 +: 32];
            tests=tests+2;
            if(dy0!==ey0) begin $display("FAIL lane%0d y0=%0d exp=%0d",ln,dy0,ey0); errors=errors+1; end
            if(dy1!==ey1) begin $display("FAIL lane%0d y1=%0d exp=%0d",ln,dy1,ey1); errors=errors+1; end
        end
    endtask

    initial begin
        clk=1'b0; rst_n=1'b0; valid_in=1'b0; mode_vec=96'd0; use_mod=1'b0;
        modulus=0; mu_barrett=0; k_log2=0; a_vec=0; b_vec=0; c_vec=0; w_vec=0;
        errors=0; tests=0;

        repeat(4) @(posedge clk); rst_n=1'b1; repeat(2) @(posedge clk);

        // ── Test 1: Heterogeneous — 4 lanes, 4 different modes, Falcon q=12289 ──
        $display("=== Heterogeneous 4-lane test ===");
        mode_vec = set_mode(0,M_CT_BFU) | set_mode(1,M_GS_BFU)
                 | set_mode(2,M_MUL_ADD) | set_mode(3,M_ADD_MUL);
        a_vec = set_lane(0,1000) | set_lane(1,9000) | set_lane(2,77) | set_lane(3,100);
        b_vec = set_lane(0,3000) | set_lane(1,5000) | set_lane(2,91) | set_lane(3,200);
        c_vec = set_lane(2,123)   | set_lane(3,33);
        w_vec = set_lane(0,7)     | set_lane(1,11);
        @(posedge clk);
        valid_in<=1'b1; use_mod<=1'b1; modulus<=32'd12289;
        k_log2<=ck(12289); mu_barrett<=cmu(12289,ck(12289));
        @(posedge clk); valid_in<=1'b0;
        repeat(5) @(posedge clk); #1;

        check_lane(0,M_CT_BFU,  1000,3000,0,7,12289,1);
        check_lane(1,M_GS_BFU,  9000,5000,0,11,12289,1);
        check_lane(2,M_MUL_ADD, 77,91,123,0,12289,1);
        check_lane(3,M_ADD_MUL, 100,200,33,0,12289,1);

        // ── Test 2: Broadcast SIMD — all test lanes CT_BFU, Kyber q=3329 ──
        $display("=== SIMD broadcast test ===");
        mode_vec = set_mode(0,M_CT_BFU) | set_mode(1,M_CT_BFU)
                 | set_mode(2,M_CT_BFU) | set_mode(3,M_CT_BFU);
        a_vec = set_lane(0,300)|set_lane(1,800)|set_lane(2,1500)|set_lane(3,2000);
        b_vec = set_lane(0,800)|set_lane(1,300)|set_lane(2,2000)|set_lane(3,1500);
        w_vec = set_lane(0,3)|set_lane(1,5)|set_lane(2,3)|set_lane(3,5);
        c_vec = 0;
        @(posedge clk);
        valid_in<=1'b1; modulus<=3329; k_log2<=ck(3329); mu_barrett<=cmu(3329,ck(3329));
        @(posedge clk); valid_in<=1'b0;
        repeat(5) @(posedge clk); #1;

        check_lane(0,M_CT_BFU,300,800,0,3,3329,1);
        check_lane(1,M_CT_BFU,800,300,0,5,3329,1);
        check_lane(2,M_CT_BFU,1500,2000,0,3,3329,1);
        check_lane(3,M_CT_BFU,2000,1500,0,5,3329,1);

        if(errors==0)
            $display("TB_PASS all %0d lane checks (P1 fixed 32-lane array)", tests);
        else
            $display("TB_FAIL %0d errors in %0d checks", errors, tests);
        $finish;
    end

    initial begin repeat(500) @(posedge clk); $display("TB_FAIL timeout"); $finish; end

endmodule
