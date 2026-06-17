`timescale 1ns/1ps
// ============================================================================
// Module: falcon_fft_task_engine
// ============================================================================
// Purpose:
//   Task-level Falcon FFT/iFFT engine shell.  This module connects the full
//   stage/batch controller, per-lane address generators, and the 5-lane f64
//   batch EXU.  It is the boundary where a future local FE buffer or DLM
//   gather/scatter adapter should attach.
//
// Flow per batch:
//   1. falcon_fft_stage_ctrl emits stage_idx, pair_base_idx, lane_mask.
//   2. LANES instances of falcon_fft_addr_gen generate a/b/twiddle addresses.
//   3. External gather logic returns va/vb/tw vectors through load_ready_i.
//   4. falcon_fft_batch_exu computes CT or GS BFU results.
//   5. External scatter logic accepts y0/y1 vectors through store_ready_i.
//
// This is intentionally not a CSR data store.  CSR/task descriptor fields
// should configure start/inverse/logn and base addresses; polynomial data stays
// in DLM/DPRAM/VR/local FE buffer.
// ============================================================================

module falcon_fft_task_engine #(
    parameter LANES = 5,
    parameter LOGN_W = 4,
    parameter STAGE_W = 4,
    parameter ADDR_W = 10,
    parameter IDX_W = 3,
    parameter FE_LATENCY = 1,
    parameter BACKEND = 0
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire                 inverse,
    input  wire [LOGN_W-1:0]    logn,

    output wire                 busy,
    output wire                 done,

    output wire                 load_valid_o,
    input  wire                 load_ready_i,
    output wire [STAGE_W-1:0]   load_stage_idx_o,
    output wire [ADDR_W-1:0]    load_batch_idx_o,
    output wire [LANES-1:0]     load_lane_mask_o,
    output wire [LANES*ADDR_W-1:0] load_a_re_addr_o,
    output wire [LANES*ADDR_W-1:0] load_a_im_addr_o,
    output wire [LANES*ADDR_W-1:0] load_b_re_addr_o,
    output wire [LANES*ADDR_W-1:0] load_b_im_addr_o,
    output wire [LANES*ADDR_W-1:0] load_twiddle_addr_o,

    input  wire [LANES*64-1:0]  load_va_re_vec_i,
    input  wire [LANES*64-1:0]  load_va_im_vec_i,
    input  wire [LANES*64-1:0]  load_vb_re_vec_i,
    input  wire [LANES*64-1:0]  load_vb_im_vec_i,
    input  wire [LANES*64-1:0]  load_tw_re_vec_i,
    input  wire [LANES*64-1:0]  load_tw_im_vec_i,

    output wire                 store_valid_o,
    input  wire                 store_ready_i,
    output wire [STAGE_W-1:0]   store_stage_idx_o,
    output wire [ADDR_W-1:0]    store_batch_idx_o,
    output wire [LANES-1:0]     store_lane_mask_o,
    output wire [LANES*ADDR_W-1:0] store_a_re_addr_o,
    output wire [LANES*ADDR_W-1:0] store_a_im_addr_o,
    output wire [LANES*ADDR_W-1:0] store_b_re_addr_o,
    output wire [LANES*ADDR_W-1:0] store_b_im_addr_o,
    output wire [LANES*64-1:0]  store_y0_re_vec_o,
    output wire [LANES*64-1:0]  store_y0_im_vec_o,
    output wire [LANES*64-1:0]  store_y1_re_vec_o,
    output wire [LANES*64-1:0]  store_y1_im_vec_o,

    output wire                 status_invalid,
    output wire                 status_overflow,
    output wire                 status_underflow,
    output wire                 status_inexact
);

    localparam E_IDLE  = 2'd0;
    localparam E_LOAD  = 2'd1;
    localparam E_EXEC  = 2'd2;
    localparam E_STORE = 2'd3;

    reg [1:0] state;
    reg batch_done_pulse;
    reg exu_start;
    reg inverse_r;
    reg [STAGE_W-1:0] stage_idx_r;
    reg [ADDR_W-1:0] batch_idx_r;
    reg [ADDR_W-1:0] pair_base_idx_r;
    reg [LANES-1:0] lane_mask_r;
    reg [LANES*64-1:0] va_re_r;
    reg [LANES*64-1:0] va_im_r;
    reg [LANES*64-1:0] vb_re_r;
    reg [LANES*64-1:0] vb_im_r;
    reg [LANES*64-1:0] tw_re_r;
    reg [LANES*64-1:0] tw_im_r;

    wire ctrl_running;
    wire ctrl_done;
    wire ctrl_stage_start;
    wire ctrl_batch_valid;
    wire ctrl_inverse;
    wire [STAGE_W-1:0] ctrl_stage_idx;
    wire [ADDR_W-1:0] ctrl_batch_idx;
    wire [ADDR_W-1:0] ctrl_pair_base_idx;
    wire [LANES-1:0] ctrl_lane_mask;
    wire [ADDR_W-1:0] ctrl_pairs_per_stage;
    wire [ADDR_W-1:0] ctrl_batches_per_stage;
    wire ctrl_batch_ready;

    wire exu_busy;
    wire exu_done;
    wire [LANES*64-1:0] exu_y0_re;
    wire [LANES*64-1:0] exu_y0_im;
    wire [LANES*64-1:0] exu_y1_re;
    wire [LANES*64-1:0] exu_y1_im;

    assign ctrl_batch_ready = (state == E_IDLE) && ctrl_batch_valid;
    assign load_valid_o = (state == E_LOAD);
    assign store_valid_o = (state == E_STORE);
    assign busy = ctrl_running | (state != E_IDLE);
    assign done = ctrl_done;

    assign load_stage_idx_o = stage_idx_r;
    assign load_batch_idx_o = batch_idx_r;
    assign load_lane_mask_o = lane_mask_r;
    assign store_stage_idx_o = stage_idx_r;
    assign store_batch_idx_o = batch_idx_r;
    assign store_lane_mask_o = lane_mask_r;

    assign store_a_re_addr_o = load_a_re_addr_o;
    assign store_a_im_addr_o = load_a_im_addr_o;
    assign store_b_re_addr_o = load_b_re_addr_o;
    assign store_b_im_addr_o = load_b_im_addr_o;
    assign store_y0_re_vec_o = exu_y0_re;
    assign store_y0_im_vec_o = exu_y0_im;
    assign store_y1_re_vec_o = exu_y1_re;
    assign store_y1_im_vec_o = exu_y1_im;

    falcon_fft_stage_ctrl #(
        .LANES(LANES),
        .LOGN_W(LOGN_W),
        .STAGE_W(STAGE_W),
        .ADDR_W(ADDR_W)
    ) u_stage_ctrl (
        .clk               (clk),
        .rst_n             (rst_n),
        .start             (start),
        .inverse           (inverse),
        .logn              (logn),
        .batch_ready       (ctrl_batch_ready),
        .batch_done        (batch_done_pulse),
        .running           (ctrl_running),
        .done              (ctrl_done),
        .stage_start       (ctrl_stage_start),
        .batch_valid       (ctrl_batch_valid),
        .inverse_o         (ctrl_inverse),
        .stage_idx         (ctrl_stage_idx),
        .batch_idx         (ctrl_batch_idx),
        .pair_base_idx     (ctrl_pair_base_idx),
        .lane_mask         (ctrl_lane_mask),
        .pairs_per_stage   (ctrl_pairs_per_stage),
        .batches_per_stage (ctrl_batches_per_stage)
    );

    genvar lane_g;
    generate
        for (lane_g = 0; lane_g < LANES; lane_g = lane_g + 1) begin : g_addr
            wire [ADDR_W-1:0] lane_pair_idx;
            assign lane_pair_idx = pair_base_idx_r + lane_g;

            falcon_fft_addr_gen #(
                .LOGN_W(LOGN_W),
                .STAGE_W(STAGE_W),
                .ADDR_W(ADDR_W)
            ) u_addr_gen (
                .inverse      (inverse_r),
                .logn         (logn),
                .stage_idx    (stage_idx_r),
                .pair_idx     (lane_pair_idx),
                .a_re_addr    (load_a_re_addr_o[lane_g*ADDR_W +: ADDR_W]),
                .a_im_addr    (load_a_im_addr_o[lane_g*ADDR_W +: ADDR_W]),
                .b_re_addr    (load_b_re_addr_o[lane_g*ADDR_W +: ADDR_W]),
                .b_im_addr    (load_b_im_addr_o[lane_g*ADDR_W +: ADDR_W]),
                .twiddle_addr (load_twiddle_addr_o[lane_g*ADDR_W +: ADDR_W]),
                .pair_valid   ()
            );
        end
    endgenerate

    falcon_fft_batch_exu #(
        .LANES(LANES),
        .IDX_W(IDX_W),
        .FE_LATENCY(FE_LATENCY),
        .BACKEND(BACKEND)
    ) u_batch_exu (
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (exu_start),
        .inverse          (inverse_r),
        .lane_mask        (lane_mask_r),
        .va_re_vec        (va_re_r),
        .va_im_vec        (va_im_r),
        .vb_re_vec        (vb_re_r),
        .vb_im_vec        (vb_im_r),
        .tw_re_vec        (tw_re_r),
        .tw_im_vec        (tw_im_r),
        .busy             (exu_busy),
        .done             (exu_done),
        .y0_re_vec        (exu_y0_re),
        .y0_im_vec        (exu_y0_im),
        .y1_re_vec        (exu_y1_re),
        .y1_im_vec        (exu_y1_im),
        .status_invalid   (status_invalid),
        .status_overflow  (status_overflow),
        .status_underflow (status_underflow),
        .status_inexact   (status_inexact)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= E_IDLE;
            batch_done_pulse <= 1'b0;
            exu_start        <= 1'b0;
            inverse_r        <= 1'b0;
            stage_idx_r      <= {STAGE_W{1'b0}};
            batch_idx_r      <= {ADDR_W{1'b0}};
            pair_base_idx_r  <= {ADDR_W{1'b0}};
            lane_mask_r      <= {LANES{1'b0}};
            va_re_r          <= {(LANES*64){1'b0}};
            va_im_r          <= {(LANES*64){1'b0}};
            vb_re_r          <= {(LANES*64){1'b0}};
            vb_im_r          <= {(LANES*64){1'b0}};
            tw_re_r          <= {(LANES*64){1'b0}};
            tw_im_r          <= {(LANES*64){1'b0}};
        end else begin
            batch_done_pulse <= 1'b0;
            exu_start        <= 1'b0;

            case (state)
                E_IDLE: begin
                    if (ctrl_batch_valid) begin
                        inverse_r       <= ctrl_inverse;
                        stage_idx_r     <= ctrl_stage_idx;
                        batch_idx_r     <= ctrl_batch_idx;
                        pair_base_idx_r <= ctrl_batch_idx * LANES;
                        lane_mask_r     <= ctrl_lane_mask;
                        state           <= E_LOAD;
                    end
                end

                E_LOAD: begin
                    if (load_ready_i) begin
                        va_re_r   <= load_va_re_vec_i;
                        va_im_r   <= load_va_im_vec_i;
                        vb_re_r   <= load_vb_re_vec_i;
                        vb_im_r   <= load_vb_im_vec_i;
                        tw_re_r   <= load_tw_re_vec_i;
                        tw_im_r   <= load_tw_im_vec_i;
                        exu_start <= 1'b1;
                        state     <= E_EXEC;
                    end
                end

                E_EXEC: begin
                    if (exu_done) begin
                        state <= E_STORE;
                    end
                end

                E_STORE: begin
                    if (store_ready_i) begin
                        batch_done_pulse <= 1'b1;
                        state            <= E_IDLE;
                    end
                end

                default: begin
                    state <= E_IDLE;
                end
            endcase
        end
    end

endmodule
