`timescale 1ns/1ps
// ============================================================================
// Module: spuv3_vpu_fe_mem_pack
// ============================================================================
// Purpose:
//   Adapt one SPUV3 320-bit VR/FE vector to the native 256-bit DLM/DPRAM row
//   width.  The f64 FE datapath consumes one 320-bit vector as five 64-bit
//   lanes, while SPUV3 memory is organized as 256-bit rows.  This module keeps
//   that packing rule explicit at the memory boundary.
//
// Load layout:
//   load_row0_i[255:0]  -> load_vr_o[255:0]    lanes 0..7
//   load_row1_i[ 63:0]  -> load_vr_o[319:256]  lanes 8..9
//   load_row1_i[255:64] is ignored by this vector load.
//
// Store layout:
//   store_vr_i[255:0]   -> store_row0_o[255:0]    full 256-bit row write
//   store_vr_i[319:256] -> store_row1_o[63:0]     partial row1 write
//   store_row1_old_i[255:64] is preserved in store_row1_o[255:64].
//
// Byte enables:
//   store_row0_be_o = 32'hffff_ffff: all row0 bytes active.
//   store_row1_be_o = 32'h0000_00ff: only row1 bytes [7:0] active.
//
// Integration note:
//   CSR registers are expected to configure addresses, length, mode, VMASK, and
//   start/status.  This module is the data-plane packer used after the memory
//   controller has fetched the required rows.  Keeping CSR control and memory
//   packing separate makes the FE wrapper independent of DLM/DPRAM byte-enable
//   policy.
// ============================================================================

module spuv3_vpu_fe_mem_pack (
    // Load path: DLM/DPRAM rows -> one VR/FE vector.
    input      [255:0] load_row0_i,
    input      [255:0] load_row1_i,

    // Store path: one VR/FE vector -> DLM/DPRAM rows.
    input      [319:0] store_vr_i,
    input      [255:0] store_row1_old_i,

    // Assembled vector used by the FE compute wrapper.
    output     [319:0] load_vr_o,

    // Row write data and byte enables returned to the memory controller.
    output     [255:0] store_row0_o,
    output     [255:0] store_row1_o,
    output     [31:0]  store_row0_be_o,
    output     [31:0]  store_row1_be_o
);

    // Load path: row0 supplies the lower 256 bits; row1 supplies the upper
    // 64 bits needed to complete the 320-bit FE vector.
    assign load_vr_o       = {load_row1_i[63:0], load_row0_i};

    // Store path: row0 is a full write.  Row1 is a read-modify-write merge so
    // adjacent data in row1[255:64] is not overwritten by this vector store.
    assign store_row0_o    = store_vr_i[255:0];
    assign store_row1_o    = {store_row1_old_i[255:64], store_vr_i[319:256]};

    // Byte-enable policy mirrors the two-row packing rule above.
    assign store_row0_be_o = 32'hffff_ffff;
    assign store_row1_be_o = 32'h0000_00ff;

endmodule
