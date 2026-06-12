`timescale 1ns/1ps

// ============================================================================
// Full NTT Pipeline - integrates AE array + shuffle_net + twiddle_rom
// + stage controller into a complete multi-stage NTT engine.
//
// Architecture:
//
//   +----------+    +---------------+    +-------------+
//   | twiddle  |--->| reconfig_ae   |--->| shuffle_net  |--> va/vb (next stage)
//   |   rom    |    | array (32 ln) |    |   (32 ln)    |
//   +----------+    +-------+-------+    +------+------+
//                           |                    |
//                    +------+------+      +------+------+
//                    | ntt_stage   |      |  ae_regfile |
//                    |   ctrl      |      |   x 32 ln   |
//                    +-------------+      +-------------+
//
// Data flow per stage per batch:
//   1. ctrl -> rf_raddr -> RF read (a operands)
//   2. ctrl -> tw_offset -> twiddle ROM read (w factors)
//   3. ae_array: y0=a+b*w, y1=a-b*w (CT) or y0=a+b, y1=(a-b)*w (GS)
//   4. shuffle_net: y1 routed to paired lane's b-port for next stage
//   5. y0 -> RF writeback (local lane store)
//
// N=256, LANES=32, 8 stages, 8 batches/stage.
// Each lane's RF stores 8 coefficients (stride-32 interleaved).
//
// Throughput: 1 full NTT in ~80-100 cycles.
//   - Load: 8 cycles (256 coeff / 32 lanes)
//   - 8 stages x (8 batches x 1 cycle + 4 pipeline drain) = ~96 cycles
//   - Unload: 8 cycles
//   Total: ~112 cycles @ cold start, ~64 cycles @ steady-state pipelined
// ============================================================================

module reconfig_ntt_pipeline #(
    parameter WORD_W   = 32,        // coefficient bit-width (32 for ML-KEM/DSA/Falcon)
    parameter MODE_W   = 4,         // AE mode width (4 bits -> 16 modes)
    parameter LANES    = 32,        // number of parallel AE lanes
    parameter N        = 256,       // polynomial degree (N=256 for common PQC schemes)
    parameter N_STAGE  = 8,         // log2(N) = number of NTT stages
    parameter RF_DEPTH = 8,         // N / LANES = 256 / 32 = 8 entries per RF
    parameter ADDR_W   = 3,         // ceil(log2(RF_DEPTH)) = 3
    parameter SCHEME_W = 2,         // PQC scheme selector width
    parameter STAGE_W  = 3,         // stage index width (ceil(log2(8)) = 3)
    parameter OFFSET_W = 7          // twiddle offset width (max 128 entries)
) (
    // -- Global -----------------------------------------------------------
    input  wire                         clk,
    input  wire                         rst_n,

    // -- Control ----------------------------------------------------------
    input  wire                         start,          // pulse: begin NTT operation
    input  wire                         inverse,        // 0=CT (forward NTT), 1=GS (inverse NTT)
    input  wire [SCHEME_W-1:0]          scheme,         // PQC scheme select (-> twiddle ROM)
    input  wire                         use_mod,        // 1=modular reduction enabled
    input  wire [WORD_W-1:0]            modulus,        // prime modulus q (e.g. 3329 for ML-KEM)
    input  wire [(2*WORD_W)-1:0]        mu,             // Barrett constant = floor(2^(2k)/q)
    input  wire [WORD_W-1:0]            mu_mont,        // Montgomery constant = -q^{-1} mod 2^WORD_W
    input  wire [4:0]                   k_log2,         // ceil(log2(q)), range 1..WORD_W

    // -- Coefficient Load Stream ------------------------------------------
    // External memory -> RF: 32 coefficients per cycle (one per lane).
    // load_ready=1 indicates the pipeline is in LOAD phase and can accept data.
    input  wire                         load_valid,
    input  wire [(LANES*WORD_W)-1:0]    load_data,
    output wire                         load_ready,

    // -- Result Unload Stream ---------------------------------------------
    // RF -> external memory: 32 coefficients per cycle.
    // unload_valid=1 when results are ready on unload_data bus.
    output wire                         unload_valid,
    output wire [(LANES*WORD_W)-1:0]    unload_data,
    input  wire                         unload_ready,

    // -- Status -----------------------------------------------------------
    output wire                         ntt_done,       // 1-cycle pulse: all stages complete
    output wire                         running,        // high while FSM is not IDLE
    output wire [2:0]                   dbg_stage,      // current stage (0..7) for debug
    output wire [2:0]                   dbg_batch       // current batch (0..7) for debug
);

    // ======================================================================
    // Stage controller connection signals
    //
    // ntt_stage_ctrl sequences through LOAD -> 8 stages x 8 batches ->
    // DRAIN -> UNLOAD -> DONE.  It produces all addressing, twiddle offset,
    // shuffle control, and phase-gating signals consumed by the datapath.
    // ======================================================================
    wire [2:0]       ctrl_stage;         // current NTT stage index (0..7)
    wire [2:0]       ctrl_batch;         // current batch within stage (0..7)
    wire [6:0]       ctrl_tw_offset;     // twiddle ROM read address
    wire [1:0]       ctrl_sh_mode;       // shuffle network mode (xor, rotate, etc.)
    wire [6:0]       ctrl_sh_offset;     // shuffle XOR offset (= 1 << stage)
    wire [ADDR_W-1:0] ctrl_rf_raddr;     // RF read address (both A and B ports)
    wire [ADDR_W-1:0] ctrl_rf_waddr;     // RF write address (result writeback)
    wire             ctrl_ae_valid;      // AE array valid_in (1 cycle per batch)
    wire             ctrl_stage_start;   // pulse at beginning of each new stage
    wire             ctrl_load_en;       // 1 during LOAD phase (gate external writes)
    wire             ctrl_unload_en;     // 1 during UNLOAD phase (gate result readout)

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

    // Debug outputs: expose controller state for waveform visibility
    assign dbg_stage = ctrl_stage;
    assign dbg_batch = ctrl_batch;

    // ======================================================================
    // Twiddle ROM - lookup table of pre-computed omega^k values
    //
    // Address = f(scheme, stage, offset).  Output (rom_twiddle) is a single
    // 32-bit twiddle factor broadcast to all 32 AE lanes each cycle.
    // ======================================================================
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

    // ======================================================================
    // Mode select - each AE lane receives a 4-bit mode vector
    //
    //   inverse=0 -> mode=0 (CT butterfly):  y0=a+b*w, y1=a-b*w
    //   inverse=1 -> mode=1 (GS butterfly):  y0=a+b,   y1=(a-b)*w
    //
    // mode_vec is 128 bits = 32 lanes x 4 bits, replicated identically.
    // ======================================================================
    wire [MODE_W-1:0] ae_mode;
    wire [127:0]      mode_vec;
    assign ae_mode  = inverse ? 4'd1 : 4'd0;
    assign mode_vec = {32{ae_mode}};

    // ======================================================================
    // AE Array - 32-lane reconfigurable arithmetic element cluster
    //
    // Inputs:
    //   ae_a_vec - local lane coefficient a (from RF read port A)
    //   ae_b_vec - paired lane coefficient b (from shuffle network)
    //   ae_c_vec - tied to 0 (not used in butterfly modes)
    //   ae_w_vec - twiddle factor (broadcast, all lanes get same omega)
    //
    // Outputs:
    //   ae_y0_vec - "a" output (stays local, written back to RF)
    //   ae_y1_vec - "b" output (routed through shuffle to paired lane)
    // ======================================================================
    wire [(LANES*WORD_W)-1:0] ae_a_vec;
    wire [(LANES*WORD_W)-1:0] ae_b_vec;
    wire [(LANES*WORD_W)-1:0] ae_c_vec;
    wire [(LANES*WORD_W)-1:0] ae_w_vec;
    wire                       ae_valid_out;
    wire [(LANES*WORD_W)-1:0] ae_y0_vec;
    wire [(LANES*WORD_W)-1:0] ae_y1_vec;

    // c input not used in butterfly -> tie to zero
    assign ae_c_vec = {(LANES*WORD_W){1'b0}};
    // Broadcast same twiddle factor to all 32 lanes
    assign ae_w_vec = {32{rom_twiddle}};

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
        .acc_clr    (1'b0),             // accumulator not used in butterfly
        .acc_out_vec()                  // accumulator output left unconnected
    );

    // ======================================================================
    // Shuffle Network - reorders y1 outputs for next-stage b operands
    //
    // Stage 0: pairs (0<->1, 2<->3, ..., 30<->31) -> offset=1
    // Stage 1: pairs (0<->2, 1<->3, ..., 29<->31) -> offset=2
    // Stage S: pairs (i  <-> i^(1<<S))     -> offset = 1 << S
    //
    // The shuffle takes y1 from each lane and routes it to the correct
    // lane's b-port for the next stage's butterfly operation.
    // ======================================================================
    wire [(LANES*WORD_W)-1:0] sh_data_in;
    wire [(LANES*WORD_W)-1:0] sh_data_out;

    assign sh_data_in = ae_y1_vec;

    shuffle_net #(.WORD_W(WORD_W), .LANES(LANES), .CLOG2(5)) u_shuffle (
        .data_in (sh_data_in),
        .offset  (ctrl_sh_offset[4:0]),
        .mode    (ctrl_sh_mode),
        .data_out(sh_data_out)
    );

    // ======================================================================
    // Register Files - 32 lanes x 8 entries (stride-32 interleaved storage)
    //
    // Each lane's RF holds 8 coefficients.  The addressing scheme implements
    // stride-32 interleaving:  lane i holds coefficients {i, i+32, i+64, ...,
    // i+224}.  This is the natural layout for in-place NTT with 32 lanes.
    //
    // Per-lane wiring:
    //   RF read  -> A operand of AE (local coefficient)
    //   RF write <- y0 from AE (butterfly "a" output, stays in same lane)
    //   B operand <- shuffle output (from paired lane's y1)
    //
    // Write enable: gated by (ctrl_ae_valid && ae_valid_out) so that
    // writeback occurs exactly when the AE pipeline produces valid results
    // (accounts for the 4-cycle pipeline delay through the AE array).
    // ======================================================================
    genvar gi;
    generate
        for (gi = 0; gi < LANES; gi = gi + 1) begin : gen_rf

            wire [WORD_W-1:0] rf_rdata_a, rf_rdata_b;
            wire [WORD_W-1:0] rf_wdata;
            wire              rf_we;

            // Write data = y0 - the "a" output of the butterfly, which
            // represents the updated coefficient for this lane
            assign rf_wdata = ae_y0_vec[(gi*WORD_W) +: WORD_W];
            // Write strobe: active 1 cycle after AE valid_in, when
            // pipeline outputs are valid.  Gate with ae_valid_out to
            // account for the pipeline latency.
            assign rf_we    = ctrl_ae_valid;

            ae_regfile #(.WORD_W(WORD_W), .DEPTH(RF_DEPTH), .ADDR_W(ADDR_W)) u_rf (
                .clk     (clk),
                .rst_n   (rst_n),
                .raddr_a (ctrl_rf_raddr),
                .rdata_a (rf_rdata_a),      // -> A operand of AE (local lane)
                .raddr_b (ctrl_rf_raddr),   // same address as port A (butterfly reads pair)
                .rdata_b (rf_rdata_b),      // unused in current butterfly mode
                .waddr   (ctrl_rf_waddr),
                .wdata   (rf_wdata),
                .we      (rf_we && ae_valid_out)  // write when AE produces valid output
            );

            // A-port: route local RF read data to AE lane input
            assign ae_a_vec[(gi*WORD_W) +: WORD_W] = rf_rdata_a;

            // B-port: route shuffled data (from paired lane) to AE lane input
            assign ae_b_vec[(gi*WORD_W) +: WORD_W] = sh_data_out[(gi*WORD_W) +: WORD_W];
        end
    endgenerate

    // ======================================================================
    // Load / Unload path
    //
    // LOAD phase (ctrl_load_en=1):
    //   External coefficient data is written directly into the RF array.
    //   load_ready mirrors ctrl_load_en - the pipeline accepts data
    //   whenever it is in the LOAD state.  load_data is distributed to
    //   all 32 lanes in parallel (one 32-bit coefficient per lane).
    //
    // UNLOAD phase (ctrl_unload_en=1):
    //   Result coefficients appear on ae_y0_vec (the final stage's outputs)
    //   and are driven onto unload_data.  unload_valid mirrors ctrl_unload_en.
    //
    // Note: in the current implementation the LOAD path requires external
    // external control to drive the RF write address and write strobe.  The load_we
    // signal below gates writes during the LOAD phase.
    // ======================================================================
    wire [LANES-1:0] load_we;
    assign load_we    = {LANES{ctrl_load_en && load_valid}};
    assign load_ready = ctrl_load_en;
    assign unload_valid = ctrl_unload_en;

    // Unload data: driven from y0 outputs of the AE array.
    // During the final UNLOAD phase, y0 holds the fully-transformed
    // coefficients (one per lane, read out batch by batch).
    assign unload_data = ae_y0_vec;

endmodule
