`timescale 1ns/1ps

// Configurable shuffle / permutation network for lane interconnect.
//
// Supports the three core NTT data-movement patterns:
//   PASSTHROUGH   — identity, data_out[i] = data_in[i]
//   XOR_SHUFFLE   — butterfly shuffle, data_out[i] = data_in[i ^ offset]
//   BIT_REVERSE   — bit-reversed addressing (final NTT reorder)
//   ROTATE        — cyclic rotation, data_out[i] = data_in[(i + offset) % LANES]
//
// Used between AE array output and input (or between array and register file)
// to route operands for the next NTT stage.

module shuffle_net #(
    parameter WORD_W = 32,
    parameter LANES  = 32,
    parameter CLOG2  = 5         // ceil(log2(LANES)), e.g. 5 for 32 lanes
) (
    input  wire [(LANES*WORD_W)-1:0] data_in,
    input  wire [CLOG2-1:0]          offset,     // XOR offset / rotate amount
    input  wire [1:0]                 mode,       // 0=passthrough, 1=xor_shuffle, 2=bit_reverse, 3=rotate
    output wire [(LANES*WORD_W)-1:0] data_out
);

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : gen_shuffle

            // ---- Compute source index for this destination lane ----
            wire [CLOG2-1:0] src_idx;

            // Bit-reverse function (combinational)
            function [CLOG2-1:0] bit_rev;
                input [CLOG2-1:0] idx;
                integer b;
                begin
                    bit_rev = {CLOG2{1'b0}};
                    for (b = 0; b < CLOG2; b = b + 1)
                        bit_rev[b] = idx[CLOG2-1 - b];
                end
            endfunction

            wire [CLOG2-1:0] idx_passthru;    // i
            wire [CLOG2-1:0] idx_xor;         // i ^ offset
            wire [CLOG2-1:0] idx_bitrev;      // bit_rev(i)
            wire [CLOG2-1:0] idx_rotate;      // (i - offset) mod LANES

            assign idx_passthru = i[CLOG2-1:0];
            assign idx_xor      = i[CLOG2-1:0] ^ offset;
            assign idx_bitrev   = bit_rev(i[CLOG2-1:0]);
            assign idx_rotate   = (i[CLOG2-1:0] - offset);   // wraps naturally in unsigned

            // Mux: select source index based on mode
            reg [CLOG2-1:0] src_idx_mux;
            always @(*) begin
                case (mode)
                    2'b00:   src_idx_mux = idx_passthru;
                    2'b01:   src_idx_mux = idx_xor;
                    2'b10:   src_idx_mux = idx_bitrev;
                    2'b11:   src_idx_mux = idx_rotate;
                    default: src_idx_mux = idx_passthru;
                endcase
            end

            assign src_idx = src_idx_mux;

            // Route: data_out[i] = data_in[src_idx]
            assign data_out[(i*WORD_W) +: WORD_W] = data_in[(src_idx*WORD_W) +: WORD_W];

        end
    endgenerate

endmodule
