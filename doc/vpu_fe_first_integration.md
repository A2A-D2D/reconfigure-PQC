# VPU FE first integration notes

This note records the low-area first integration path for the Falcon f64 FE
inside the existing VPU EXU.  The design does not add a full local FFT buffer
and does not add extra VPU register-file write ports.

## New RTL blocks

- `rtl/vpu_fe_unit.v`
  - Owns the shared FE instance.
  - Holds `tw_im`.
  - Holds four 320-bit results: `y0_re`, `y0_im`, `y1_re`, `y1_im`.
  - Returns one selected 320-bit result per READ command.

- `rtl/vpu_fe_exu_adapter.v`
  - Intended to sit inside the real `vpu_exu`.
  - Converts decoded FE operation hits into `vpu_fe_unit` commands.
  - Exposes `fe_done_o`, `fe_stall_o`, `fe_result_o`, and `fe_vreg_we_o`.

## Suggested package additions

Add four internal VPU operations to `vpu_pkg::vpu_instr_e`.
If the enum is close to 64 entries, widen it from `[5:0]` to `[6:0]`.

```systemverilog
    // for Falcon f64 FE
    VFFELOADWIM,
    VFFESTART,
    VFFEREAD,
    VFFECLEAR,
```

## Suggested instruction encodings

Use one unused `funct7` group under the existing VPU custom opcode.
The example below uses `funct7=1001010`, `opcode=0000101`.

```systemverilog
localparam [31:0] VFFELOADWIM_MATCH =
    32'b1001010_00000_00000_000_00000_0000101;
localparam [31:0] VFFELOADWIM_MASK  =
    32'b1111111_00000_00000_111_00000_1111111;

localparam [31:0] VFFESTART_MATCH =
    32'b1001010_00000_00000_001_00000_0000101;
localparam [31:0] VFFESTART_MASK  =
    32'b1111111_00000_00000_111_00000_1111111;

localparam [31:0] VFFEREAD_MATCH =
    32'b1001010_00000_00000_010_00000_0000101;
localparam [31:0] VFFEREAD_MASK  =
    32'b1111111_00000_00000_111_00000_1111111;

localparam [31:0] VFFECLEAR_MATCH =
    32'b1001010_00000_00000_011_00000_0000101;
localparam [31:0] VFFECLEAR_MASK  =
    32'b1111111_00000_00000_111_00000_1111111;
```

Then add decode wires, output assignments, legal-instruction OR terms, and
`vpu_info` bits for the four FE operations.

## Suggested decinfo additions

If the last VPU decinfo index is `SPU_DECINFO_GRP_WIDTH+50`, add:

```systemverilog
`define SPU_DECINFO_VPU_VFFELOADWIM (`SPU_DECINFO_GRP_WIDTH+51)
`define SPU_DECINFO_VPU_VFFESTART   (`SPU_DECINFO_GRP_WIDTH+52)
`define SPU_DECINFO_VPU_VFFEREAD    (`SPU_DECINFO_GRP_WIDTH+53)
`define SPU_DECINFO_VPU_VFFECLEAR   (`SPU_DECINFO_GRP_WIDTH+54)
`define SPU_DECINFO_VPU_BUS_WIDTH   (`SPU_DECINFO_GRP_WIDTH+55)
```

Adjust the numbers if the real file has more VPU bits.

## Dispatch additions

Add these cases where `vpu_info[...]` becomes `vpu_op_dispatch`.

```systemverilog
        // Falcon f64 FE
        vpu_info[`SPU_DECINFO_VPU_VFFELOADWIM] : vpu_op_dispatch = VFFELOADWIM;
        vpu_info[`SPU_DECINFO_VPU_VFFESTART]   : vpu_op_dispatch = VFFESTART;
        vpu_info[`SPU_DECINFO_VPU_VFFEREAD]    : vpu_op_dispatch = VFFEREAD;
        vpu_info[`SPU_DECINFO_VPU_VFFECLEAR]   : vpu_op_dispatch = VFFECLEAR;
```

## EXU integration sketch

Instantiate `vpu_fe_exu_adapter` inside `vpu_exu`.

```systemverilog
wire is_vffeloadwim = (operator_i == VFFELOADWIM);
wire is_vffestart   = (operator_i == VFFESTART);
wire is_vfferead    = (operator_i == VFFEREAD);
wire is_vffeclear   = (operator_i == VFFECLEAR);

wire         vffe_done;
wire         vffe_stall;
wire [319:0] vffe_result;
wire         vffe_vreg_we;
wire [3:0]   vffe_flags;
wire         vffe_busy;
wire         vffe_result_valid;

vpu_fe_exu_adapter u_vpu_fe_exu_adapter (
    .clk              (clk),
    .rst_n            (rst_n),
    .valid_i          (valid_i),
    .is_vffeloadwim_i (is_vffeloadwim),
    .is_vffestart_i   (is_vffestart),
    .is_vfferead_i    (is_vfferead),
    .is_vffeclear_i   (is_vffeclear),
    .fe_mode_i        (imm12_i[5:2]),
    .fe_read_sel_i    (imm12_i[1:0]),
    .cfg_vmask_i      (cfg_vmask_i),
    .operand_a_i      (operand_a_i),
    .operand_b_i      (operand_b_i),
    .operand_c_i      (operand_c_i),
    .operand_d_i      (operand_d_i),
    .operand_e_i      (operand_e_i),
    .fe_done_o        (vffe_done),
    .fe_stall_o       (vffe_stall),
    .fe_result_o      (vffe_result),
    .fe_vreg_we_o     (vffe_vreg_we),
    .fe_flags_o       (vffe_flags),
    .fe_busy_o         (vffe_busy),
    .fe_result_valid_o(vffe_result_valid)
);
```

Add `vffe_done` to the multi-cycle done OR and add the FE operations to the
multi-cycle valid-enable OR.

```systemverilog
assign done_mcyc = existing_done_mcyc | vffe_done;

assign op_mcyc_valid_en = existing_op_mcyc_valid_en
                         | ((operator_i == VFFESTART) & valid_i)
                         | ((operator_i == VFFEREAD)  & valid_i);
```

Add `VFFEREAD` to `result_mcyc`.

```systemverilog
VFFEREAD: begin
    result_mcyc = vffe_result;
end
```

Only `VFFEREAD` should write a VPU register.

```systemverilog
assign vpu_reg_we_i = existing_vpu_reg_we_i | vffe_vreg_we;
```

`VFFELOADWIM`, `VFFESTART`, and `VFFECLEAR` are control commands and should not
assert the vector register write enable.

## Suggested assembly flow

```text
vffeloadwim  v_tw_im
vffestart    v_a_re, v_a_im, v_b_re, v_b_im, v_tw_re
vfferead     v_y0_re, 0
vfferead     v_y0_im, 1
vfferead     v_y1_re, 2
vfferead     v_y1_im, 3
vffeclear
```

