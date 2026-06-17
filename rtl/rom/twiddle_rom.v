`timescale 1ns/1ps

// PQC Twiddle Factor ROM — parameterized.
//
// Stores precomputed NTT twiddle factors for up to 3 PQC schemes.
// Each scheme occupies a 256-entry region in the ROM (128 base twiddles
// for stage 0 + 128 for stage-dependent stride access).
//
// Addressing:
//   scheme[1:0] : selects PQC scheme (0=ML-KEM, 1=ML-DSA, 2=Falcon)
//   stage[2:0]  : NTT stage 0..7
//   offset[6:0] : pair index within stage (0..127, stride-compressed)
//
// Internal stride logic:
//   For stage S, the actual twiddle = base_twiddle[(offset << S) & 0x7F]
//   (powers of zeta^(2S+1), zeta^(2S+3), ... for forward NTT)
//
// ROM content loaded from external hex file via $readmemh in simulation,
// or initialized via top-level parameter array for synthesis.

module twiddle_rom #(
    parameter WORD_W   = 32,
    parameter SCHEME_W = 2,     // supports 4 schemes
    parameter STAGE_W  = 3,     // 8 stages
    parameter OFFSET_W = 7,     // 128 entries per stage-0
    parameter DEPTH    = 1024   // 4 schemes × 256 entries
) (
    input  wire                       clk,
    input  wire [SCHEME_W-1:0]        scheme,
    input  wire [STAGE_W-1:0]         stage,
    input  wire [OFFSET_W-1:0]        offset,
    output reg  [WORD_W-1:0]          twiddle
);

    // ── ROM storage ───────────────────────────────────────────────────
    reg [WORD_W-1:0] rom [0:DEPTH-1];

    // ── Address calculation ───────────────────────────────────────────
    // Base address = scheme * 256
    // Within scheme: store 128 stage-0 twiddles at [0:127]
    //                store expanded twiddles at [128:255] if needed
    // For stage S: twiddle index = offset * (1 << S) % 128 (if stride access)
    // Simplified: ROM stores all 128 stage-0 base twiddles.
    //             Stage S uses every (1<<S)-th entry starting at 0.

    wire [OFFSET_W:0] stride;
    assign stride = (offset << stage);   // offset * 2^stage

    wire [OFFSET_W-1:0] twiddle_idx;
    assign twiddle_idx = stride[OFFSET_W-1:0] % 128;  // mod 128

    wire [SCHEME_W+OFFSET_W-1:0] rom_addr;
    assign rom_addr = {scheme, twiddle_idx};

    // ── Combinational read (registered for timing) ────────────────────
    always @(posedge clk) begin
        twiddle <= rom[rom_addr];
    end

    // ── Simulation initialization (overridden by top-level in synth) ──
    // In synthesis, the ROM is loaded via external means (flash, OTP, etc.)
    `ifdef SIMULATION
    initial begin
        $readmemh("twiddle_rom.hex", rom);
    end
    `endif

endmodule
