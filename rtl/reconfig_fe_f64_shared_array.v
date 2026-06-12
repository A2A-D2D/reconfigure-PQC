`timescale 1ns/1ps
// Module: reconfig_fe_f64_shared_array
// Purpose: area-controlled Falcon f64 FE vector engine. One f64 FE lane is
// time-multiplexed across LANES entries. The output vector registers are also
// the gather buffer; ready_in adds backpressure so downstream blocks can hold
// the result without it being overwritten by the next batch.

module reconfig_fe_f64_shared_array #(
    parameter LANES      = 8,
    parameter MODE_W     = 4,
    parameter IDX_W      = 4,
    parameter FE_LATENCY = 1
) (
    input                       clk,
    input                       rst_n,
    input                       valid_in,
    input                       ready_in,
    input      [LANES-1:0]      lane_mask,
    input      [MODE_W-1:0]     mode,
    input      [LANES*64-1:0]   a_re_vec,
    input      [LANES*64-1:0]   a_im_vec,
    input      [LANES*64-1:0]   b_re_vec,
    input      [LANES*64-1:0]   b_im_vec,
    input      [LANES*64-1:0]   c_re_vec,
    input      [LANES*64-1:0]   c_im_vec,
    input      [LANES*64-1:0]   w_re_vec,
    input      [LANES*64-1:0]   w_im_vec,
    output reg                  busy,
    output reg                  valid_out,
    output reg [LANES*64-1:0]   y0_re_vec,
    output reg [LANES*64-1:0]   y0_im_vec,
    output reg [LANES*64-1:0]   y1_re_vec,
    output reg [LANES*64-1:0]   y1_im_vec,
    output reg                  status_invalid,
    output reg                  status_overflow,
    output reg                  status_underflow,
    output reg                  status_inexact
);

    localparam ST_IDLE = 1'b0;
    localparam ST_RUN  = 1'b1;
    localparam [IDX_W-1:0] LANES_VALUE = LANES;
    localparam [IDX_W-1:0] LAST_LANE   = LANES - 1;
    localparam [IDX_W:0] NO_LANE = LANES;

    reg                   state;
    reg                   result_pending;
    reg [IDX_W-1:0]       issue_idx;
    reg [IDX_W-1:0]       lane_issue_idx;
    reg [IDX_W-1:0]       last_active_idx;
    reg [MODE_W-1:0]      mode_hold;
    reg [LANES-1:0]       lane_mask_hold;
    reg [LANES*64-1:0]    a_re_hold;
    reg [LANES*64-1:0]    a_im_hold;
    reg [LANES*64-1:0]    b_re_hold;
    reg [LANES*64-1:0]    b_im_hold;
    reg [LANES*64-1:0]    c_re_hold;
    reg [LANES*64-1:0]    c_im_hold;
    reg [LANES*64-1:0]    w_re_hold;
    reg [LANES*64-1:0]    w_im_hold;
    reg [63:0]            lane_a_re;
    reg [63:0]            lane_a_im;
    reg [63:0]            lane_b_re;
    reg [63:0]            lane_b_im;
    reg [63:0]            lane_c_re;
    reg [63:0]            lane_c_im;
    reg [63:0]            lane_w_re;
    reg [63:0]            lane_w_im;
    reg                   lane_valid_in;
    reg                   tag_valid_pipe [0:FE_LATENCY-1];
    reg [IDX_W-1:0]       tag_pipe       [0:FE_LATENCY-1];
    reg [IDX_W:0]         first_active_sel;
    reg [IDX_W:0]         next_active_sel;

    wire                  lane_valid_out;
    wire [63:0]           lane_y0_re;
    wire [63:0]           lane_y0_im;
    wire [63:0]           lane_y1_re;
    wire [63:0]           lane_y1_im;
    wire                  lane_invalid;
    wire                  lane_overflow;
    wire                  lane_underflow;
    wire                  lane_inexact;

    integer pipe_i;

    function [IDX_W:0] next_active_lane;
        input [IDX_W-1:0] start_idx;
        input [LANES-1:0] mask;
        integer lane_i;
        reg found;
        begin
            found = 1'b0;
            next_active_lane = NO_LANE;
            for (lane_i = 0; lane_i < LANES; lane_i = lane_i + 1) begin
                if (!found && (lane_i >= start_idx) && mask[lane_i]) begin
                    next_active_lane = lane_i;
                    found = 1'b1;
                end
            end
        end
    endfunction

    function [IDX_W-1:0] last_active_lane;
        input [LANES-1:0] mask;
        integer lane_i;
        begin
            last_active_lane = {IDX_W{1'b0}};
            for (lane_i = 0; lane_i < LANES; lane_i = lane_i + 1) begin
                if (mask[lane_i]) begin
                    last_active_lane = lane_i[IDX_W-1:0];
                end
            end
        end
    endfunction

    reconfig_fe_f64 #(
        .MODE_W(MODE_W)
    ) u_shared_lane (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(lane_valid_in),
        .mode(mode_hold),
        .a_re(lane_a_re),
        .a_im(lane_a_im),
        .b_re(lane_b_re),
        .b_im(lane_b_im),
        .c_re(lane_c_re),
        .c_im(lane_c_im),
        .w_re(lane_w_re),
        .w_im(lane_w_im),
        .valid_out(lane_valid_out),
        .y0_re(lane_y0_re),
        .y0_im(lane_y0_im),
        .y1_re(lane_y1_re),
        .y1_im(lane_y1_im),
        .status_invalid(lane_invalid),
        .status_overflow(lane_overflow),
        .status_underflow(lane_underflow),
        .status_inexact(lane_inexact)
    );

    always @(*) begin
        first_active_sel = next_active_lane({IDX_W{1'b0}}, lane_mask);
        next_active_sel  = next_active_lane(issue_idx, lane_mask_hold);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            result_pending   <= 1'b0;
            issue_idx        <= {IDX_W{1'b0}};
            lane_issue_idx   <= {IDX_W{1'b0}};
            last_active_idx  <= {IDX_W{1'b0}};
            mode_hold        <= {MODE_W{1'b0}};
            lane_mask_hold   <= {LANES{1'b0}};
            a_re_hold        <= {(LANES*64){1'b0}};
            a_im_hold        <= {(LANES*64){1'b0}};
            b_re_hold        <= {(LANES*64){1'b0}};
            b_im_hold        <= {(LANES*64){1'b0}};
            c_re_hold        <= {(LANES*64){1'b0}};
            c_im_hold        <= {(LANES*64){1'b0}};
            w_re_hold        <= {(LANES*64){1'b0}};
            w_im_hold        <= {(LANES*64){1'b0}};
            lane_a_re        <= 64'd0;
            lane_a_im        <= 64'd0;
            lane_b_re        <= 64'd0;
            lane_b_im        <= 64'd0;
            lane_c_re        <= 64'd0;
            lane_c_im        <= 64'd0;
            lane_w_re        <= 64'd0;
            lane_w_im        <= 64'd0;
            lane_valid_in    <= 1'b0;
            busy             <= 1'b0;
            valid_out        <= 1'b0;
            y0_re_vec        <= {(LANES*64){1'b0}};
            y0_im_vec        <= {(LANES*64){1'b0}};
            y1_re_vec        <= {(LANES*64){1'b0}};
            y1_im_vec        <= {(LANES*64){1'b0}};
            status_invalid   <= 1'b0;
            status_overflow  <= 1'b0;
            status_underflow <= 1'b0;
            status_inexact   <= 1'b0;
            for (pipe_i = 0; pipe_i < FE_LATENCY; pipe_i = pipe_i + 1) begin
                tag_valid_pipe[pipe_i] <= 1'b0;
                tag_pipe[pipe_i]       <= {IDX_W{1'b0}};
            end
        end else begin
            if (result_pending) begin
                if (ready_in) begin
                    result_pending <= 1'b0;
                    valid_out      <= 1'b0;
                    busy           <= 1'b0;
                end else begin
                    valid_out      <= 1'b1;
                    busy           <= 1'b1;
                end
            end

            if (lane_valid_out && tag_valid_pipe[FE_LATENCY-1]) begin
                y0_re_vec[tag_pipe[FE_LATENCY-1]*64 +: 64] <= lane_y0_re;
                y0_im_vec[tag_pipe[FE_LATENCY-1]*64 +: 64] <= lane_y0_im;
                y1_re_vec[tag_pipe[FE_LATENCY-1]*64 +: 64] <= lane_y1_re;
                y1_im_vec[tag_pipe[FE_LATENCY-1]*64 +: 64] <= lane_y1_im;
                status_invalid   <= status_invalid | lane_invalid;
                status_overflow  <= status_overflow | lane_overflow;
                status_underflow <= status_underflow | lane_underflow;
                status_inexact   <= status_inexact | lane_inexact;
                if (tag_pipe[FE_LATENCY-1] == last_active_idx) begin
                    result_pending <= 1'b1;
                    valid_out      <= 1'b1;
                    busy           <= !ready_in;
                    state          <= ST_IDLE;
                end
            end

            for (pipe_i = FE_LATENCY-1; pipe_i > 0; pipe_i = pipe_i - 1) begin
                tag_valid_pipe[pipe_i] <= tag_valid_pipe[pipe_i-1];
                tag_pipe[pipe_i]       <= tag_pipe[pipe_i-1];
            end
            tag_valid_pipe[0] <= lane_valid_in;
            tag_pipe[0]       <= lane_issue_idx;

            lane_valid_in <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (valid_in && (|lane_mask) && (!result_pending || ready_in)) begin
                        state            <= ST_RUN;
                        busy             <= 1'b1;
                        result_pending   <= 1'b0;
                        valid_out        <= 1'b0;
                        mode_hold        <= mode;
                        lane_mask_hold   <= lane_mask;
                        last_active_idx  <= last_active_lane(lane_mask);
                        a_re_hold        <= a_re_vec;
                        a_im_hold        <= a_im_vec;
                        b_re_hold        <= b_re_vec;
                        b_im_hold        <= b_im_vec;
                        c_re_hold        <= c_re_vec;
                        c_im_hold        <= c_im_vec;
                        w_re_hold        <= w_re_vec;
                        w_im_hold        <= w_im_vec;
                        issue_idx        <= first_active_sel[IDX_W-1:0] +
                                            {{(IDX_W-1){1'b0}}, 1'b1};
                        lane_issue_idx   <= first_active_sel[IDX_W-1:0];
                        lane_a_re        <= a_re_vec[first_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_a_im        <= a_im_vec[first_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_b_re        <= b_re_vec[first_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_b_im        <= b_im_vec[first_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_c_re        <= c_re_vec[first_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_c_im        <= c_im_vec[first_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_w_re        <= w_re_vec[first_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_w_im        <= w_im_vec[first_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_valid_in    <= 1'b1;
                        status_invalid   <= 1'b0;
                        status_overflow  <= 1'b0;
                        status_underflow <= 1'b0;
                        status_inexact   <= 1'b0;
                    end else if (valid_in && (!result_pending || ready_in)) begin
                        state            <= ST_IDLE;
                        busy             <= !ready_in;
                        result_pending   <= 1'b1;
                        valid_out        <= 1'b1;
                        lane_valid_in    <= 1'b0;
                        mode_hold        <= mode;
                        lane_mask_hold   <= {LANES{1'b0}};
                        last_active_idx  <= {IDX_W{1'b0}};
                        status_invalid   <= 1'b0;
                        status_overflow  <= 1'b0;
                        status_underflow <= 1'b0;
                        status_inexact   <= 1'b0;
                    end
                end

                ST_RUN: begin
                    if (next_active_sel != NO_LANE) begin
                        lane_issue_idx <= next_active_sel[IDX_W-1:0];
                        lane_a_re      <= a_re_hold[next_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_a_im      <= a_im_hold[next_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_b_re      <= b_re_hold[next_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_b_im      <= b_im_hold[next_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_c_re      <= c_re_hold[next_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_c_im      <= c_im_hold[next_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_w_re      <= w_re_hold[next_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_w_im      <= w_im_hold[next_active_sel[IDX_W-1:0]*64 +: 64];
                        lane_valid_in  <= 1'b1;
                        issue_idx      <= next_active_sel[IDX_W-1:0] +
                                          {{(IDX_W-1){1'b0}}, 1'b1};
                    end
                end

                default: begin
                    state         <= ST_IDLE;
                    busy          <= 1'b0;
                    lane_valid_in <= 1'b0;
                end
            endcase
        end
    end

endmodule
