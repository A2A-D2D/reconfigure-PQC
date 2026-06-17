`timescale 1ns/1ps

// Micro-program ROM + decoder — wraps useq_core into a complete
// micro-sequencer with instruction memory.
//
// Instruction format (per useq_core interface):
//   opcode[1:0] : 0=EXEC, 1=LOOP_BEG, 2=LOOP_END, 3=HALT
//   loop_cnt    : iteration count (for LOOP_BEG)
//   loop_body   : body start PC (for LOOP_BEG)
//
// Extended instruction word (added by this module):
//   ae_mode[3:0]  : AE mode for EXEC instructions
//   rf_raddr[2:0] : RF read address
//   rf_waddr[2:0] : RF write address
//   rf_we          : RF write enable
//   imm_data[31:0] : immediate data (twiddle, const, etc.)
//
// Total instruction width = 2 + 8 + 5 + 4 + 3 + 3 + 1 + 32 = 58 bits

module useq_rom #(
    parameter AW      = 5,       // program address width (max 32 instructions)
    parameter LW      = 8,       // loop counter width
    parameter DEPTH   = 32,      // ROM depth
    parameter MODE_W  = 4
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,

    // ── ROM program interface (external load) ─────────────────────────
    input  wire [AW-1:0]        prog_addr,
    input  wire [57:0]          prog_data,     // 58-bit instruction
    input  wire                 prog_we,

    // ── Sequencer outputs ─────────────────────────────────────────────
    output wire                 done,
    output wire                 running,
    output wire [AW-1:0]        pc,
    output wire [LW-1:0]        iter,

    // ── Decoded instruction fields ────────────────────────────────────
    output wire [MODE_W-1:0]    ae_mode,
    output wire [2:0]           rf_raddr,
    output wire [2:0]           rf_waddr,
    output wire                 rf_we,
    output wire [31:0]          imm_data
);

    // ── ROM storage ───────────────────────────────────────────────────
    reg [57:0] rom [0:DEPTH-1];

    always @(posedge clk) begin
        if (prog_we)
            rom[prog_addr] <= prog_data;
    end

    // ── ROM read ──────────────────────────────────────────────────────
    wire [57:0] instr;
    assign instr = rom[pc];

    wire [1:0]   opcode;
    wire [LW-1:0] loop_cnt;
    wire [AW-1:0] loop_body;

    assign opcode    = instr[1:0];
    assign loop_cnt  = instr[9:2];
    assign loop_body = instr[14:10];
    assign ae_mode   = instr[18:15];
    assign rf_raddr  = instr[21:19];
    assign rf_waddr  = instr[24:22];
    assign rf_we     = instr[25];
    assign imm_data  = instr[57:26];

    // ── Sequencer core ────────────────────────────────────────────────
    useq_core #(.AW(AW), .LW(LW)) u_seq (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .opcode   (opcode),
        .loop_cnt (loop_cnt),
        .loop_body(loop_body),
        .pc       (pc),
        .done     (done),
        .running  (running),
        .iter     (iter)
    );

endmodule
