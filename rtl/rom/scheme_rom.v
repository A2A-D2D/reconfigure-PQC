`timescale 1ns/1ps

// PQC Scheme Parameter ROM — stores Barrett/Montgomery constants
// for up to 4 PQC schemes.
//
// Scheme encoding:
//   0 = ML-KEM  (FIPS 203, q=3329)
//   1 = ML-DSA  (FIPS 204, q=8380417)
//   2 = Falcon  (q=12289)
//   3 = reserved
//
// Output parameters per scheme:
//   modulus    [31:0]   — prime modulus q
//   mu         [63:0]   — Barrett constant floor(2^(2k) / q)
//   mu_mont    [31:0]   — Montgomery constant -q^{-1} mod 2^32
//   k_log2     [4:0]    — ceil(log2(q))
//   n          [15:0]   — polynomial degree (256)
//   zeta       [31:0]   — primitive N-th root of unity

module scheme_rom #(
    parameter SCHEME_W = 2,
    parameter WORD_W   = 32,
    parameter N_SCHEME = 3      // 0=ML-KEM, 1=ML-DSA, 2=Falcon
) (
    input  wire [SCHEME_W-1:0]   scheme,
    output wire [WORD_W-1:0]     modulus,
    output wire [(2*WORD_W)-1:0] mu,
    output wire [WORD_W-1:0]     mu_mont,
    output wire [4:0]            k_log2,
    output wire [15:0]           n,
    output wire [WORD_W-1:0]     zeta
);

    // ==================================================================
    // ML-KEM (FIPS 203): q = 3329
    //   k = ceil(log2(3329)) = 12
    //   mu = floor(2^24 / 3329) = 5041
    //   mu_mont = -3329^{-1} mod 2^32 = 4294963967 (= 2^32 - 3327)
    //   zeta = 17 (primitive 256-th root)
    // ==================================================================
    localparam [WORD_W-1:0]     KEM_Q     = 32'd3329;
    localparam [(2*WORD_W)-1:0] KEM_MU    = 64'd5039;        // 2^24 / 3329
    localparam [WORD_W-1:0]     KEM_MU_M  = 32'd2488732927;  // -3329^{-1} mod 2^32
    localparam [4:0]            KEM_K     = 5'd12;
    localparam [WORD_W-1:0]     KEM_ZETA  = 32'd17;

    // ==================================================================
    // ML-DSA (FIPS 204): q = 8380417
    //   k = ceil(log2(8380417)) = 23
    //   mu = floor(2^46 / 8380417) = 8396807
    //   mu_mont = -8380417^{-1} mod 2^32 = 4236238847
    //   zeta = 1753 (primitive 512-th root)
    // ==================================================================
    localparam [WORD_W-1:0]     DSA_Q     = 32'd8380417;
    localparam [(2*WORD_W)-1:0] DSA_MU    = 64'd8396807;      // 2^46 / 8380417
    localparam [WORD_W-1:0]     DSA_MU_M  = 32'd4236238847;   // -8380417^{-1} mod 2^32
    localparam [4:0]            DSA_K     = 5'd23;
    localparam [WORD_W-1:0]     DSA_ZETA  = 32'd1753;

    // ==================================================================
    // Falcon: q = 12289
    //   k = ceil(log2(12289)) = 14
    //   mu = floor(2^28 / 12289) = 21846
    //   mu_mont = -12289^{-1} mod 2^32 = 4143984639
    //   zeta = 7 (primitive 512-th root mod 12289)
    // ==================================================================
    localparam [WORD_W-1:0]     FAL_Q     = 32'd12289;
    localparam [(2*WORD_W)-1:0] FAL_MU    = 64'd21843;        // 2^28 / 12289
    localparam [WORD_W-1:0]     FAL_MU_M  = 32'd4143984639;   // -12289^{-1} mod 2^32
    localparam [4:0]            FAL_K     = 5'd14;
    localparam [WORD_W-1:0]     FAL_ZETA  = 32'd7;

    // ==================================================================
    // Mux output based on scheme select
    // ==================================================================
    reg [WORD_W-1:0]     modulus_r;
    reg [(2*WORD_W)-1:0] mu_r;
    reg [WORD_W-1:0]     mu_mont_r;
    reg [4:0]            k_log2_r;
    reg [WORD_W-1:0]     zeta_r;

    always @(*) begin
        case (scheme)
            2'd0: begin  // ML-KEM
                modulus_r = KEM_Q;
                mu_r      = KEM_MU;
                mu_mont_r = KEM_MU_M;
                k_log2_r  = KEM_K;
                zeta_r    = KEM_ZETA;
            end
            2'd1: begin  // ML-DSA
                modulus_r = DSA_Q;
                mu_r      = DSA_MU;
                mu_mont_r = DSA_MU_M;
                k_log2_r  = DSA_K;
                zeta_r    = DSA_ZETA;
            end
            2'd2: begin  // Falcon
                modulus_r = FAL_Q;
                mu_r      = FAL_MU;
                mu_mont_r = FAL_MU_M;
                k_log2_r  = FAL_K;
                zeta_r    = FAL_ZETA;
            end
            default: begin
                modulus_r = {WORD_W{1'b0}};
                mu_r      = {(2*WORD_W){1'b0}};
                mu_mont_r = {WORD_W{1'b0}};
                k_log2_r  = 5'd0;
                zeta_r    = {WORD_W{1'b0}};
            end
        endcase
    end

    assign modulus = modulus_r;
    assign mu      = mu_r;
    assign mu_mont = mu_mont_r;
    assign k_log2  = k_log2_r;
    assign n       = 16'd256;       // all PQC schemes use n=256
    assign zeta    = zeta_r;

endmodule
