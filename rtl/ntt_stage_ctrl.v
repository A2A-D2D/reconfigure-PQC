`timescale 1ns/1ps

// NTT Stage Controller — sequences through 8 NTT stages with batch looping.
//
// FSM:
//   IDLE (0) → LOAD (1) → STAGE_LOOP (2) → BATCH_EXEC (3) → DRAIN (4)
//      → CHECK (5) → [STAGE_LOOP | UNLOAD (6)] → DONE (7)
//
// Parameters:
//   N       — polynomial degree (256 for ML-KEM / ML-DSA / Falcon)
//   LANES   — parallel AE lanes (32)
//   N_STAGE — log2(N) (8 for N=256)
//
// Outputs:
//   stage[2:0]      — current NTT stage (0..7)
//   batch[1:0]      — batch within stage (0..3 for 32-lane, N=256)
//   tw_offset[6:0]  — twiddle ROM offset for current butterfly pair
//   sh_mode[1:0]    — shuffle network mode
//   sh_offset[4:0]  — shuffle XOR offset (= 1 << stage)
//   rf_raddr_a      — RF read address for operand a
//   rf_raddr_b      — RF read address for operand b (paired lane)
//   rf_waddr        — RF write address for results
//   ae_valid        — valid_in to AE array (1 cycle pulse per batch)
//   stage_start      — pulse at beginning of each stage
//   ntt_done         — asserted when all 8 stages complete

module ntt_stage_ctrl #(
    parameter N       = 256,
    parameter LANES   = 32,
    parameter N_STAGE = 8,
    parameter ADDR_W  = 5    // ceil(log2(N/LANES * depth_per_lane)) for RF addressing
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire             inverse,        // 0=forward NTT (CT), 1=inverse NTT (GS)

    // ── Current state ──
    output reg  [2:0]       stage,
    output reg  [2:0]       batch,
    output reg  [6:0]       tw_offset,      // twiddle ROM offset
    output reg  [1:0]       sh_mode,        // shuffle mode
    output reg  [6:0]       sh_offset,      // shuffle XOR offset (1 << stage, max 128)
    output reg  [ADDR_W-1:0] rf_raddr,      // RF read address (a operand)
    output reg  [ADDR_W-1:0] rf_waddr,      // RF write address

    // ── Control pulses ──
    output reg              ae_valid,       // AE array valid_in (1 cycle)
    output reg              stage_start,    // pulse at beginning of new stage
    output reg              load_en,        // coefficient load phase
    output reg              unload_en,      // result unload phase
    output reg              ntt_done,
    output reg              running
);

    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_LOAD   = 3'd1;
    localparam [2:0] S_STAGE  = 3'd2;
    localparam [2:0] S_BATCH  = 3'd3;
    localparam [2:0] S_DRAIN  = 3'd4;
    localparam [2:0] S_CHECK  = 3'd5;
    localparam [2:0] S_UNLOAD = 3'd6;
    localparam [2:0] S_DONE   = 3'd7;

    reg [2:0] state, next_state;
    reg [2:0] drain_cnt;
    reg [3:0] batch_cnt;     // count batches executed in current stage (0..BATCH_MAX-1)
    reg [3:0] stage_cnt;

    localparam [3:0] BATCH_MAX = N / LANES;  // 256/32 = 8 batches per stage
    localparam [3:0] PIPELINE_DELAY = 4'd4;   // 4 cycles from valid_in to valid_out

    // ── FSM sequential ────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            state       <= S_IDLE;
            stage       <= 3'd0;
            batch       <= 2'd0;
            tw_offset   <= 7'd0;
            sh_mode     <= 2'd0;
            sh_offset   <= 5'd0;
            rf_raddr    <= {ADDR_W{1'b0}};
            rf_waddr    <= {ADDR_W{1'b0}};
            ae_valid    <= 1'b0;
            stage_start <= 1'b0;
            load_en     <= 1'b0;
            unload_en   <= 1'b0;
            ntt_done    <= 1'b0;
            running     <= 1'b0;
            drain_cnt   <= 3'd0;
            batch_cnt   <= 3'd0;
            stage_cnt   <= 3'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    ae_valid    <= 1'b0;
                    stage_start <= 1'b0;
                    ntt_done    <= 1'b0;
                    running     <= 1'b0;
                    stage       <= 3'd0;
                    stage_cnt   <= 3'd0;
                    if (start) begin
                        state   <= S_LOAD;
                        running <= 1'b1;
                        load_en <= 1'b1;
                    end
                end

                S_LOAD: begin
                    // Coefficient load phase (external memory → RF)
                    // rf_raddr sequences 0..BATCH_MAX-1; controlled externally
                    load_en  <= 1'b0;
                    state    <= S_STAGE;
                    stage    <= 3'd0;
                    batch_cnt <= 3'd0;
                end

                S_STAGE: begin
                    // Configure shuffle for this stage
                    // Stage S: offset = 1 << S, mode = XOR
                    sh_offset  <= (5'd1 << stage_cnt);
                    sh_mode    <= 2'b01;        // XOR shuffle
                    stage      <= stage_cnt;
                    batch      <= 2'd0;
                    tw_offset  <= {4'd0, batch_cnt};  // base twiddle index
                    rf_raddr   <= {ADDR_W{1'b0}};     // base read addr
                    rf_waddr   <= {ADDR_W{1'b0}};     // base write addr
                    stage_start <= 1'b1;
                    batch_cnt   <= 3'd0;
                    state       <= S_BATCH;
                end

                S_BATCH: begin
                    stage_start <= 1'b0;
                    // Fire one AE batch: pulse valid_in for 1 cycle
                    ae_valid  <= 1'b1;
                    // Twiddle offset: base + batch offset
                    tw_offset <= {4'd0, batch_cnt};
                    rf_raddr  <= batch_cnt[ADDR_W-1:0];
                    rf_waddr  <= batch_cnt[ADDR_W-1:0];
                    batch      <= batch_cnt[1:0];
                    state      <= S_DRAIN;
                end

                S_DRAIN: begin
                    ae_valid  <= 1'b0;
                    // Wait for pipeline to drain
                    drain_cnt <= drain_cnt + 3'd1;
                    if (drain_cnt >= PIPELINE_DELAY - 1) begin
                        drain_cnt <= 3'd0;
                        state     <= S_CHECK;
                    end
                end

                S_CHECK: begin
                    if (batch_cnt < BATCH_MAX - 1) begin
                        batch_cnt <= batch_cnt + 3'd1;
                        state     <= S_BATCH;
                    end else begin
                        // All batches in this stage done
                        if (stage_cnt < N_STAGE - 1) begin
                            stage_cnt <= stage_cnt + 3'd1;
                            state     <= S_STAGE;
                        end else begin
                            state     <= S_UNLOAD;
                            unload_en <= 1'b1;
                        end
                    end
                end

                S_UNLOAD: begin
                    unload_en <= 1'b0;
                    state     <= S_DONE;
                    ntt_done  <= 1'b1;
                end

                S_DONE: begin
                    running  <= 1'b0;
                    ntt_done <= 1'b0;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
