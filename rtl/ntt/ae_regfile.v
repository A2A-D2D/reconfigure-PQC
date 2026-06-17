`timescale 1ns/1ps

// Per-lane register file — 2 read ports, 1 write port.
//
// Used to store intermediate coefficients, twiddle factors, and
// accumulated results during multi-stage NTT / polynomial arithmetic.
// Combinational read (addr → data in same cycle), synchronous write.
//
// Parameters:
//   DEPTH  — number of entries (default 8, addr width = 3)
//   WORD_W — data width (default 32)

module ae_regfile #(
    parameter WORD_W = 32,
    parameter DEPTH  = 8,
    parameter ADDR_W = 3        // ceil(log2(DEPTH))
) (
    input  wire                  clk,
    input  wire                  rst_n,

    // Read port A (combinational)
    input  wire [ADDR_W-1:0]     raddr_a,
    output wire [WORD_W-1:0]     rdata_a,

    // Read port B (combinational)
    input  wire [ADDR_W-1:0]     raddr_b,
    output wire [WORD_W-1:0]     rdata_b,

    // Write port (synchronous)
    input  wire [ADDR_W-1:0]     waddr,
    input  wire [WORD_W-1:0]     wdata,
    input  wire                  we
);

    // Register file storage
    reg [WORD_W-1:0] rf [0:DEPTH-1];

    // Synchronous write
    integer wi;
    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            for (wi = 0; wi < DEPTH; wi = wi + 1)
                rf[wi] <= {WORD_W{1'b0}};
        end else begin
            if (we)
                rf[waddr] <= wdata;
        end
    end

    // Combinational reads
    assign rdata_a = rf[raddr_a];
    assign rdata_b = rf[raddr_b];

endmodule
