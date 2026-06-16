`timescale 1ns/1ps

module tb_falcon_fft_stage_ctrl;
    localparam LANES = 5;

    reg             clk;
    reg             rst_n;
    reg             start;
    reg             inverse;
    reg  [3:0]      logn;
    reg             batch_ready;
    reg             batch_done;
    wire            running;
    wire            done;
    wire            stage_start;
    wire            batch_valid;
    wire            inverse_o;
    wire [3:0]      stage_idx;
    wire [9:0]      batch_idx;
    wire [9:0]      pair_base_idx;
    wire [LANES-1:0] lane_mask;
    wire [9:0]      pairs_per_stage;
    wire [9:0]      batches_per_stage;

    integer accepted_batches;
    integer stage_start_count;
    integer errors;
    integer cycles;

    falcon_fft_stage_ctrl #(
        .LANES(LANES)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .start             (start),
        .inverse           (inverse),
        .logn              (logn),
        .batch_ready       (batch_ready),
        .batch_done        (batch_done),
        .running           (running),
        .done              (done),
        .stage_start       (stage_start),
        .batch_valid       (batch_valid),
        .inverse_o         (inverse_o),
        .stage_idx         (stage_idx),
        .batch_idx         (batch_idx),
        .pair_base_idx     (pair_base_idx),
        .lane_mask         (lane_mask),
        .pairs_per_stage   (pairs_per_stage),
        .batches_per_stage (batches_per_stage)
    );

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accepted_batches <= 0;
            stage_start_count <= 0;
            batch_done <= 1'b0;
        end else begin
            batch_done <= 1'b0;
            if (stage_start) begin
                stage_start_count <= stage_start_count + 1;
            end
            if (batch_valid && batch_ready) begin
                accepted_batches <= accepted_batches + 1;
                batch_done <= 1'b1;

                if (pair_base_idx != batch_idx * LANES) begin
                    $display("TB_FAIL pair_base mismatch batch=%0d pair_base=%0d",
                             batch_idx, pair_base_idx);
                    errors = errors + 1;
                end
                if ((batch_idx == batches_per_stage - 1) && (lane_mask != 5'b00111)) begin
                    $display("TB_FAIL last Falcon-512 lane_mask=%b", lane_mask);
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
        logn = 4'd9;
        batch_ready = 1'b1;
        errors = 0;
        cycles = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        while (!done && cycles < 2000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!done) begin
            $display("TB_FAIL timeout waiting done");
            errors = errors + 1;
        end
        if (accepted_batches != 208) begin
            $display("TB_FAIL accepted_batches=%0d exp=208", accepted_batches);
            errors = errors + 1;
        end
        if (stage_start_count != 8) begin
            $display("TB_FAIL stage_start_count=%0d exp=8", stage_start_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TB_PASS falcon_fft_stage_ctrl");
        end else begin
            $display("TB_FAIL errors=%0d", errors);
        end
        $finish;
    end
endmodule
