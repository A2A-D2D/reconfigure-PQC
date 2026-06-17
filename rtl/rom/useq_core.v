`timescale 1ns/1ps

// Micro-sequencer core — programmable control unit for AE array.
//
// Executes a μProgram from an external instruction ROM (not included —
// the ROM + decode logic lives in the wrapper / testbench).  The core
// manages PC, a 4-level loop stack, and a done flag.
//
// Loop stack:  each level stores {start_pc, remaining_count}.
//   LOOP_BEG(cnt, body_pc):  push {body_pc, cnt-1} onto stack.
//   LOOP_END:                 if stack.top.count > 0:
//                                stack.top.count--;  PC = stack.top.body_pc
//                             else: pop stack;       PC++
//
// Parameters:
//   AW  — PC / address width (default 5 → 32 instructions max)
//   LW  — loop counter width (default 8 → 255 iterations max)

module useq_core #(
    parameter AW = 5,
    parameter LW = 8
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,       // pulse to begin execution at PC=0

    // Decoded instruction fields from ROM
    input  wire [1:0]       opcode,      // 0=EXEC, 1=LOOP_BEG, 2=LOOP_END, 3=HALT
    input  wire [LW-1:0]    loop_cnt,    // iteration count (for LOOP_BEG)
    input  wire [AW-1:0]    loop_body,   // body start PC (for LOOP_BEG)

    output reg  [AW-1:0]    pc,          // program counter → ROM address
    output reg               done,        // asserted when HALT is reached
    output reg               running,     // high while executing (not halted)
    output wire [LW-1:0]    iter          // current loop iteration (for addr calc)
);

    // Loop stack: 4 levels, each stores {valid, start_pc, remaining}
    reg                 lv_valid [0:3];
    reg  [AW-1:0]       lv_pc    [0:3];
    reg  [LW-1:0]       lv_cnt   [0:3];
    reg  [1:0]          sp;         // stack pointer (0 = empty, 1-4 = levels)

    wire                stack_full  = (sp == 2'd3);  // max 3 nested loops
    wire                stack_empty = (sp == 2'd0);

    // Current iteration = top-of-stack count (for address calculation)
    assign iter = stack_empty ? {LW{1'b0}} : lv_cnt[sp-1];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            pc      <= {AW{1'b0}};
            done    <= 1'b0;
            running <= 1'b0;
            sp      <= 2'd0;
            for (i = 0; i < 4; i = i + 1) begin
                lv_valid[i] <= 1'b0;
                lv_pc[i]    <= {AW{1'b0}};
                lv_cnt[i]   <= {LW{1'b0}};
            end
        end else begin
            if (start && !running) begin
                // Start execution
                pc      <= {AW{1'b0}};
                done    <= 1'b0;
                running <= 1'b1;
                sp      <= 2'd0;

            end else if (running && !done) begin
                case (opcode)
                    2'b00: begin  // EXEC — advance PC
                        pc <= pc + 1;
                    end

                    2'b01: begin  // LOOP_BEG
                        if (!stack_full && loop_cnt > 0) begin
                            lv_valid[sp] <= 1'b1;
                            lv_pc[sp]    <= loop_body;
                            lv_cnt[sp]   <= loop_cnt - 1;
                            sp           <= sp + 1;
                        end
                        pc <= loop_body;   // jump to body
                    end

                    2'b10: begin  // LOOP_END
                        if (!stack_empty && lv_cnt[sp-1] > 0) begin
                            // Continue looping
                            lv_cnt[sp-1] <= lv_cnt[sp-1] - 1;
                            pc           <= lv_pc[sp-1];
                        end else begin
                            // Exit loop
                            if (!stack_empty) begin
                                lv_valid[sp-1] <= 1'b0;
                                sp <= sp - 1;
                            end
                            pc <= pc + 1;
                        end
                    end

                    2'b11: begin  // HALT
                        done    <= 1'b1;
                        running <= 1'b0;
                    end

                    default: pc <= pc + 1;
                endcase
            end
        end
    end

endmodule
