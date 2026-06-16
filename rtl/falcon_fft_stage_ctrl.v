`timescale 1ns/1ps
// ============================================================================
// Module: falcon_fft_stage_ctrl
// ============================================================================
// Purpose:
//   Coarse-grained Falcon FFT/iFFT stage and batch controller.  It sequences
//   the full transform process around a vector butterfly datapath; it does not
//   store polynomial data by itself.
//
// Contract:
//   - start launches one complete FFT/iFFT transform task.
//   - batch_valid identifies the next LANES-wide butterfly batch.
//   - batch_ready accepts that batch.
//   - batch_done tells the controller that the datapath has written the batch.
//   - done pulses after all stages and batches complete.
//
// For Falcon-512:
//   logn=9, pairs/stage=128, LANES=5 -> 26 batches/stage.
// For Falcon-1024:
//   logn=10, pairs/stage=256, LANES=5 -> 52 batches/stage.
// ============================================================================

module falcon_fft_stage_ctrl #(
    parameter LANES = 5,
    parameter LOGN_W = 4,
    parameter STAGE_W = 4,
    parameter ADDR_W = 10
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire                 inverse,
    input  wire [LOGN_W-1:0]    logn,
    input  wire                 batch_ready,
    input  wire                 batch_done,

    output reg                  running,
    output reg                  done,
    output reg                  stage_start,
    output reg                  batch_valid,
    output reg                  inverse_o,
    output reg  [STAGE_W-1:0]   stage_idx,
    output reg  [ADDR_W-1:0]    batch_idx,
    output reg  [ADDR_W-1:0]    pair_base_idx,
    output reg  [LANES-1:0]     lane_mask,
    output reg  [ADDR_W-1:0]    pairs_per_stage,
    output reg  [ADDR_W-1:0]    batches_per_stage
);

    localparam S_IDLE = 2'd0;
    localparam S_ISSUE = 2'd1;
    localparam S_WAIT = 2'd2;
    localparam S_DONE = 2'd3;

    reg [1:0] state;
    reg [ADDR_W-1:0] next_pair_base;
    reg [ADDR_W-1:0] active_left;
    reg [ADDR_W-1:0] stage_last;
    integer lane_i;

    always @(*) begin
        pairs_per_stage  = ({ {(ADDR_W-1){1'b0}}, 1'b1 } << (logn - 2));
        batches_per_stage = (pairs_per_stage + LANES - 1) / LANES;
        stage_last       = logn - 2;
        next_pair_base   = batch_idx * LANES;
        active_left      = pairs_per_stage - next_pair_base;

        lane_mask = {LANES{1'b0}};
        for (lane_i = 0; lane_i < LANES; lane_i = lane_i + 1) begin
            lane_mask[lane_i] = (lane_i < active_left);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            running       <= 1'b0;
            done          <= 1'b0;
            stage_start   <= 1'b0;
            batch_valid   <= 1'b0;
            inverse_o     <= 1'b0;
            stage_idx     <= {STAGE_W{1'b0}};
            batch_idx     <= {ADDR_W{1'b0}};
            pair_base_idx <= {ADDR_W{1'b0}};
        end else begin
            done        <= 1'b0;
            stage_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    running     <= 1'b0;
                    batch_valid <= 1'b0;
                    if (start) begin
                        running       <= 1'b1;
                        inverse_o     <= inverse;
                        stage_idx     <= {STAGE_W{1'b0}};
                        batch_idx     <= {ADDR_W{1'b0}};
                        pair_base_idx <= {ADDR_W{1'b0}};
                        stage_start   <= 1'b1;
                        state         <= S_ISSUE;
                    end
                end

                S_ISSUE: begin
                    batch_valid   <= 1'b1;
                    pair_base_idx <= next_pair_base;
                    if (batch_valid && batch_ready) begin
                        batch_valid <= 1'b0;
                        state       <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (batch_done) begin
                        if (batch_idx < batches_per_stage - 1'b1) begin
                            batch_idx <= batch_idx + 1'b1;
                            state     <= S_ISSUE;
                        end else if (stage_idx < stage_last) begin
                            stage_idx   <= stage_idx + 1'b1;
                            batch_idx   <= {ADDR_W{1'b0}};
                            stage_start <= 1'b1;
                            state       <= S_ISSUE;
                        end else begin
                            state <= S_DONE;
                        end
                    end
                end

                S_DONE: begin
                    running     <= 1'b0;
                    batch_valid <= 1'b0;
                    done        <= 1'b1;
                    state       <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
