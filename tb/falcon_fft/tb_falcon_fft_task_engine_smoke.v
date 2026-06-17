`timescale 1ns/1ps

module tb_falcon_fft_task_engine_smoke;
    localparam LANES = 5;
    localparam [63:0] F64_ZERO = 64'h0000_0000_0000_0000;

    reg clk;
    reg rst_n;
    reg start;
    reg inverse;
    reg [3:0] logn;
    reg load_ready;
    reg store_ready;
    wire busy;
    wire done;
    wire load_valid;
    wire [3:0] load_stage_idx;
    wire [9:0] load_batch_idx;
    wire [LANES-1:0] load_lane_mask;
    wire [LANES*10-1:0] load_a_re_addr;
    wire [LANES*10-1:0] load_a_im_addr;
    wire [LANES*10-1:0] load_b_re_addr;
    wire [LANES*10-1:0] load_b_im_addr;
    wire [LANES*10-1:0] load_twiddle_addr;
    wire store_valid;
    wire [3:0] store_stage_idx;
    wire [9:0] store_batch_idx;
    wire [LANES-1:0] store_lane_mask;
    wire [LANES*10-1:0] store_a_re_addr;
    wire [LANES*10-1:0] store_a_im_addr;
    wire [LANES*10-1:0] store_b_re_addr;
    wire [LANES*10-1:0] store_b_im_addr;
    wire [LANES*64-1:0] store_y0_re;
    wire [LANES*64-1:0] store_y0_im;
    wire [LANES*64-1:0] store_y1_re;
    wire [LANES*64-1:0] store_y1_im;
    wire status_invalid;
    wire status_overflow;
    wire status_underflow;
    wire status_inexact;

    integer load_count;
    integer store_count;
    integer errors;
    integer cycles;

    falcon_fft_task_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .inverse(inverse),
        .logn(logn),
        .busy(busy),
        .done(done),
        .load_valid_o(load_valid),
        .load_ready_i(load_ready),
        .load_stage_idx_o(load_stage_idx),
        .load_batch_idx_o(load_batch_idx),
        .load_lane_mask_o(load_lane_mask),
        .load_a_re_addr_o(load_a_re_addr),
        .load_a_im_addr_o(load_a_im_addr),
        .load_b_re_addr_o(load_b_re_addr),
        .load_b_im_addr_o(load_b_im_addr),
        .load_twiddle_addr_o(load_twiddle_addr),
        .load_va_re_vec_i({LANES{F64_ZERO}}),
        .load_va_im_vec_i({LANES{F64_ZERO}}),
        .load_vb_re_vec_i({LANES{F64_ZERO}}),
        .load_vb_im_vec_i({LANES{F64_ZERO}}),
        .load_tw_re_vec_i({LANES{F64_ZERO}}),
        .load_tw_im_vec_i({LANES{F64_ZERO}}),
        .store_valid_o(store_valid),
        .store_ready_i(store_ready),
        .store_stage_idx_o(store_stage_idx),
        .store_batch_idx_o(store_batch_idx),
        .store_lane_mask_o(store_lane_mask),
        .store_a_re_addr_o(store_a_re_addr),
        .store_a_im_addr_o(store_a_im_addr),
        .store_b_re_addr_o(store_b_re_addr),
        .store_b_im_addr_o(store_b_im_addr),
        .store_y0_re_vec_o(store_y0_re),
        .store_y0_im_vec_o(store_y0_im),
        .store_y1_re_vec_o(store_y1_re),
        .store_y1_im_vec_o(store_y1_im),
        .status_invalid(status_invalid),
        .status_overflow(status_overflow),
        .status_underflow(status_underflow),
        .status_inexact(status_inexact)
    );

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_count <= 0;
            store_count <= 0;
        end else begin
            if (load_valid && load_ready) begin
                load_count <= load_count + 1;
                if (load_lane_mask != 5'b00011) begin
                    $display("TB_FAIL load lane_mask=%b", load_lane_mask);
                    errors = errors + 1;
                end
            end
            if (store_valid && store_ready) begin
                store_count <= store_count + 1;
                if (store_lane_mask != 5'b00011) begin
                    $display("TB_FAIL store lane_mask=%b", store_lane_mask);
                    errors = errors + 1;
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        inverse = 1'b0;
        logn = 4'd3;
        load_ready = 1'b1;
        store_ready = 1'b1;
        errors = 0;
        cycles = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        while (!done && cycles < 300) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!done) begin
            $display("TB_FAIL timeout waiting task done");
            errors = errors + 1;
        end
        if (load_count != 2 || store_count != 2) begin
            $display("TB_FAIL load_count=%0d store_count=%0d exp=2/2",
                     load_count, store_count);
            errors = errors + 1;
        end
        if (errors == 0) begin
            $display("TB_PASS falcon_fft_task_engine_smoke");
        end else begin
            $display("TB_FAIL errors=%0d", errors);
        end
        $finish;
    end
endmodule
