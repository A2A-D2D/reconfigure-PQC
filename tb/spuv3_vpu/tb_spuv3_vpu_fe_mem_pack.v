`timescale 1ns/1ps

// ============================================================================
// Testbench: tb_spuv3_vpu_fe_mem_pack
// ============================================================================
// Purpose:
//   Self-checking testbench for the SPUV3 256-bit memory row to 320-bit FE/VR
//   vector packer.
//
// Covered behavior:
//   1. Load path packs {row1[63:0], row0[255:0]} into load_vr_o.
//   2. Store path sends store_vr_i[255:0] to row0.
//   3. Store path sends store_vr_i[319:256] to row1[63:0].
//   4. Store path preserves row1[255:64] from the old row1 value.
//   5. Byte enables match the intended full-row/partial-row write policy.
// ============================================================================

module tb_spuv3_vpu_fe_mem_pack;

    reg  [255:0] load_row0_i;
    reg  [255:0] load_row1_i;
    reg  [319:0] store_vr_i;
    reg  [255:0] store_row1_old_i;

    wire [319:0] load_vr_o;
    wire [255:0] store_row0_o;
    wire [255:0] store_row1_o;
    wire [31:0]  store_row0_be_o;
    wire [31:0]  store_row1_be_o;

    integer errors;

    spuv3_vpu_fe_mem_pack dut (
        .load_row0_i     (load_row0_i),
        .load_row1_i     (load_row1_i),
        .store_vr_i      (store_vr_i),
        .store_row1_old_i(store_row1_old_i),
        .load_vr_o       (load_vr_o),
        .store_row0_o    (store_row0_o),
        .store_row1_o    (store_row1_o),
        .store_row0_be_o (store_row0_be_o),
        .store_row1_be_o (store_row1_be_o)
    );

    task check256;
        input [127:0] name;
        input [255:0] got;
        input [255:0] exp;
        begin
            if (got !== exp) begin
                $display("TB_FAIL %0s got=%h exp=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check320;
        input [127:0] name;
        input [319:0] got;
        input [319:0] exp;
        begin
            if (got !== exp) begin
                $display("TB_FAIL %0s got=%h exp=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check32;
        input [127:0] name;
        input [31:0] got;
        input [31:0] exp;
        begin
            if (got !== exp) begin
                $display("TB_FAIL %0s got=%h exp=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;

        // Row0 carries FE/VR lanes 0..7.
        load_row0_i =
            256'h0707_0707_0606_0606_0505_0505_0404_0404_0303_0303_0202_0202_0101_0101_0000_0000;

        // Row1 carries FE/VR lanes 8..9 in bits [63:0].  The upper bits use
        // distinct markers so the load check catches accidental leakage.
        load_row1_i =
            256'hffff_ffff_eeee_eeee_dddd_dddd_cccc_cccc_bbbb_bbbb_aaaa_aaaa_0909_0909_0808_0808;

        // Store vector carries ten 32-bit lane patterns packed as one 320-bit
        // FE/VR payload.
        store_vr_i =
            320'h1414_1414_1313_1313_1212_1212_1111_1111_1010_1010_0f0f_0f0f_0e0e_0e0e_0d0d_0d0d_0c0c_0c0c_0b0b_0b0b;

        // Old row1 value is intentionally distinctive so the preserve check
        // catches any overwrite of row1[255:64].
        store_row1_old_i =
            256'hdead_beef_cafe_f00d_7654_3210_fedc_ba98_aaaa_5555_1234_5678_9999_9999_8888_8888;

        #1;

        check320("load_pack",
                 load_vr_o,
                 {load_row1_i[63:0], load_row0_i});

        check256("store_row0",
                 store_row0_o,
                 store_vr_i[255:0]);

        check256("store_row1_preserve",
                 store_row1_o,
                 {store_row1_old_i[255:64], store_vr_i[319:256]});

        check32("store_row0_be", store_row0_be_o, 32'hffff_ffff);
        check32("store_row1_be", store_row1_be_o, 32'h0000_00ff);

        if (store_row1_o[255:64] !== store_row1_old_i[255:64]) begin
            $display("TB_FAIL store_row1 upper bits were not preserved");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TB_PASS spuv3 vpu fe mem pack cases");
        end else begin
            $display("TB_FAIL errors=%0d", errors);
        end
        $finish;
    end

endmodule
