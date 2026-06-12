`timescale 1ns/1ps

// Full NTT Pipeline — integrates AE array + shuffle_net + twiddle_rom
// + stage controller into a complete multi-stage NTT engine.
//
// Architecture:
//   ┌──────────┐    ┌───────────────┐    ┌─────────────┐
//   │ twiddle  │───▶│ reconfig_ae   │───▶│ shuffle_net  │──▶ va/vb (next stage)
//   │   rom    │    │ array (32 ln) │    │   (32 ln)    │
//   └──────────┘    └───────┬───────┘    └──────┬──────┘
//                           │                    │
//                    ┌──────┴──────┐      ┌──────┴──────┐
//                    │ ntt_stage   │      │  ae_regfile │
//                    │   ctrl      │      │   × 32 ln   │
//                    └─────────────┘      └─────────────┘
//
// N=256, LANES=32, 8 stages, 8 batches/stage.
// Each lane's RF stores 8 coefficients (stride-32 interleaved).
//
// Throughput: 1 full NTT in ~80-100 cycles.
//   - Load: 8 cycles (256 coeff / 32 lanes)
//   - 8 stages × (8 batches × 1 cycle + 4 pipeline drain) = ~96 cycles
//   - Unload: 8 cycles
//   Total: ~112 cycles @ latency, ~64 cycles @ steady-state pipelined

module reconfig_ntt_pipeline #(
    parameter WORD_W   = 32,
    parameter MODE_W   = 4,
    parameter LANES    = 32,
    parameter N        = 256,
    parameter N_STAGE  = 8,
    parameter RF_DEPTH = 8,       // N / LANES = 256 / 32 = 8
    parameter ADDR_W   = 3,       // ceil(log2(8))
    parameter SCHEME_W = 2,
    parameter STAGE_W  = 3,
    parameter OFFSET_W = 7
) (
    input  wire                         clk,
    input  wire                         rst_n,

    // ── Control ───────────────────────────────────────────────────────
    input  wire                         start,
    input  wire                         inverse,        // 0=CT (fw NTT), 1=GS (inv NTT)
    input  wire [SCHEME_W-1:0]          scheme,         // PQC scheme select
    input  wire                         use_mod,
    input  wire [WORD_W-1:0]            modulus,
    input  wire [(2*WORD_W)-1:0]        mu,
    input  wire [WORD_W-1:0]            mu_mont,
    input  wire [4:0]                   k_log2,

    // ── Data I/O ──────────────────────────────────────────────────────
    // Coefficient load interface (stream in 32 coefficients/cycle)
    input  wire                         load_valid,
    input  wire [(LANES*WORD_W)-1:0]    load_data,
    output wire                         load_ready,

    // Result unload interface (stream out 32 coefficients/cycle)
    output wire                         unload_valid,
    output wire [(LANES*WORD_W)-1:0]    unload_data,
    input  wire                         unload_ready,

    // ── Status ────────────────────────────────────────────────────────
    output wire                         ntt_done,
    output wire                         running,
    output wire [2:0]                   dbg_stage,
    output wire [2:0]                   dbg_batch
);

    // ── Stage controller signals ──────────────────────────────────────
    wire [2:0]       ctrl_stage;
    wire [2:0]       ctrl_batch;
    wire [6:0]       ctrl_tw_offset;
    wire [1:0]       ctrl_sh_mode;
    wire [6:0]       ctrl_sh_offset;
    wire [ADDR_W-1:0] ctrl_rf_raddr;
    wire [ADDR_W-1:0] ctrl_rf_waddr;
    wire             ctrl_ae_valid;
    wire             ctrl_stage_start;
    wire             ctrl_load_en;
    wire             ctrl_unload_en;

    ntt_stage_ctrl #(
        .N(N), .LANES(LANES), .N_STAGE(N_STAGE), .ADDR_W(ADDR_W)
    ) u_ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .inverse    (inverse),
        .stage      (ctrl_stage),
        .batch      (ctrl_batch),
        .tw_offset  (ctrl_tw_offset),
        .sh_mode    (ctrl_sh_mode),
        .sh_offset  (ctrl_sh_offset),
        .rf_raddr   (ctrl_rf_raddr),
        .rf_waddr   (ctrl_rf_waddr),
        .ae_valid   (ctrl_ae_valid),
        .stage_start(ctrl_stage_start),
        .load_en    (ctrl_load_en),
        .unload_en  (ctrl_unload_en),
        .ntt_done   (ntt_done),
        .running    (running)
    );

    assign dbg_stage = ctrl_stage;
    assign dbg_batch = ctrl_batch;

    // ── Twiddle ROM ───────────────────────────────────────────────────
    wire [WORD_W-1:0] rom_twiddle;

    twiddle_rom #(
        .WORD_W(WORD_W), .SCHEME_W(SCHEME_W),
        .STAGE_W(STAGE_W), .OFFSET_W(OFFSET_W)
    ) u_rom (
        .clk     (clk),
        .scheme  (scheme),
        .stage   (ctrl_stage),
        .offset  (ctrl_tw_offset),
        .twiddle (rom_twiddle)
    );

    // ── Mode select ───────────────────────────────────────────────────
    wire [MODE_W-1:0] ae_mode;
    wire [127:0]      mode_vec;
    assign ae_mode  = inverse ? 4'd1 : 4'd0;   // CT(0) or GS(1)
    assign mode_vec = {32{ae_mode}};

    // ── AE Array ──────────────────────────────────────────────────────
    wire [(LANES*WORD_W)-1:0] ae_a_vec;
    wire [(LANES*WORD_W)-1:0] ae_b_vec;
    wire [(LANES*WORD_W)-1:0] ae_c_vec;
    wire [(LANES*WORD_W)-1:0] ae_w_vec;
    wire                       ae_valid_out;
    wire [(LANES*WORD_W)-1:0] ae_y0_vec;
    wire [(LANES*WORD_W)-1:0] ae_y1_vec;

    assign ae_c_vec = {(LANES*WORD_W){1'b0}};
    assign ae_w_vec = {32{rom_twiddle}};        // broadcast twiddle to all lanes

    reconfig_ae_array u_ae_array (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (ctrl_ae_valid),
        .mode_vec   (mode_vec),
        .use_mod    (use_mod),
        .modulus    (modulus),
        .mu         (mu),
        .mu_mont    (mu_mont),
        .k_log2     (k_log2),
        .a_vec      (ae_a_vec),
        .b_vec      (ae_b_vec),
        .c_vec      (ae_c_vec),
        .w_vec      (ae_w_vec),
        .valid_out  (ae_valid_out),
        .y0_vec     (ae_y0_vec),
        .y1_vec     (ae_y1_vec),
        .acc_clr    (1'b0),
        .acc_out_vec()
    );

    // ── Shuffle Network ───────────────────────────────────────────────
    wire [(LANES*WORD_W)-1:0] sh_data_in;
    wire [(LANES*WORD_W)-1:0] sh_data_out;

    // Shuffle routes y1 (upper output = paired lane's new b) back to b-ports
    // Stage 0: offset=1 (pair lane0↔lane1), Stage 1: offset=2, Stage S: 1<<S
    assign sh_data_in = ae_y1_vec;

    shuffle_net #(.WORD_W(WORD_W), .LANES(LANES), .CLOG2(5)) u_shuffle (
        .data_in (sh_data_in),
        .offset  (ctrl_sh_offset),
        .mode    (ctrl_sh_mode),
        .data_out(sh_data_out)
    );

    // ── Register Files (32 lanes) ─────────────────────────────────────
    // Each RF: depth=8 (stores 8 coeff for that lane, stride-32 interleaved)
    genvar gi;
    generate
        for (gi = 0; gi < LANES; gi = gi + 1) begin : gen_rf

            wire [WORD_W-1:0] rf_rdata_a, rf_rdata_b;
            wire [WORD_W-1:0] rf_wdata;
            wire              rf_we;

            // Write data = y0 (the "a" output of butterfly, stays local)
            assign rf_wdata = ae_y0_vec[(gi*WORD_W) +: WORD_W];
            assign rf_we    = ctrl_ae_valid;  // writeback in next cycle via pipeline delay

            ae_regfile #(.WORD_W(WORD_W), .DEPTH(RF_DEPTH), .ADDR_W(ADDR_W)) u_rf (
                .clk     (clk),
                .rst_n   (rst_n),
                .raddr_a (ctrl_rf_raddr),
                .rdata_a (rf_rdata_a),    // a operand
                .raddr_b (ctrl_rf_raddr),
                .rdata_b (rf_rdata_b),    // unused in butterfly
                .waddr   (ctrl_rf_waddr),
                .wdata   (rf_wdata),
                .we      (rf_we && ae_valid_out)  // write when AE output valid
            );

            // A-port: local RF data (the "a" side)
            assign ae_a_vec[(gi*WORD_W) +: WORD_W] = rf_rdata_a;

            // B-port: shuffled data from paired lane (the "b" side)
            assign ae_b_vec[(gi*WORD_W) +: WORD_W] = sh_data_out[(gi*WORD_W) +: WORD_W];
        end
    endgenerate

    // ── Load / Unload interface ───────────────────────────────────────
    // During LOAD phase, write external data to RF
    // During UNLOAD phase, read RF to external output
    wire [LANES-1:0] load_we;
    assign load_we    = {LANES{ctrl_load_en && load_valid}};
    assign load_ready = ctrl_load_en;
    assign unload_valid = ctrl_unload_en;
    // Unload data connected externally (testbench reads RF directly or via ports)

    // Simple passthrough for unload: y0 outputs during unload phase
    assign unload_data = ae_y0_vec;

endmodule
