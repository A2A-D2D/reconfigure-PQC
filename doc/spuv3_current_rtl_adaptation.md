# SPUV3 Current RTL Adaptation Notes

This note records the current architecture-aligned RTL boundary for the SPUV3
FE extension.

## Compute Adapter

`rtl/spuv3_vpu_fe_f64_wrap.v` adapts the Falcon f64 shared FFT operator to
SPUV3-facing signals:

- `320-bit` VR inputs and outputs.
- `csr_vmask_i[31:0]` to 5-bit f64 FE lane mask conversion.
- `valid_in`, `ready_in`, `busy`, `valid_out`, and `done_pulse` task handshake.
- `inverse` selection for CT/GS butterfly mode.

The wrapper fixes the FE side to `5 x 64-bit` lanes, matching one SPUV3
`320-bit` VR.

## Memory Row Adapter

`rtl/spuv3_vpu_fe_mem_pack.v` adapts SPUV3 `256-bit` DLM/DPRAM rows to one
`320-bit` VR/FE vector:

```text
DLM/DPRAM row0[255:0] -> VR/FE[255:0]
DLM/DPRAM row1[ 63:0] -> VR/FE[319:256]
```

On store:

- row0 is fully written.
- row1 only writes byte lanes `[7:0]`.
- row1 `[255:64]` is merged from the old row1 value.

This keeps the FE compute wrapper independent from memory byte-enable policy
while preserving the SPUV3 `256-bit` memory organization.

## CSR Control Boundary

CSR registers are best kept as the control plane for this FE extension:

- configure source/destination DLM or DPRAM addresses;
- configure vector count, mode, `inverse`, and `csr_vmask_i`;
- trigger `start`, observe `busy`, `done_pulse`, and exception/status flags;
- optionally expose a debug path for small direct VR/FE register reads/writes.

Bulk FE operands should still use the memory/VR data path.  Sending every
320-bit operand through CSR load/store would make the CSR bus the throughput
bottleneck.  The intended split is therefore:

```text
CSR registers: task setup, trigger, status, debug
DLM/DPRAM rows: bulk operand and result movement
spuv3_vpu_fe_mem_pack: 256-bit row <-> 320-bit VR packing
spuv3_vpu_fe_f64_wrap: VMASK and compute-side FE adaptation
```

## Main Path

The intended integration path is:

```text
DLM/DPRAM rows
  -> spuv3_vpu_fe_mem_pack
  -> spuv3_vpu_fe_f64_wrap
  -> reconfig_fft_f64_shared_operator
  -> reconfig_fe_f64_shared_array
  -> reconfig_fe_f64
```

## Falcon FFT/IFFT Verification Boundary

Current RTL simulation covers the FE operator and SPUV3 wrapper boundary:

- `tb_reconfig_fft_f64_operator.v`
- `tb_reconfig_fft_f64_pipe_operator.v`
- `tb_reconfig_fft_f64_shared_operator.v`
- `tb_spuv3_vpu_fe_f64_wrap.v`
- `tb_spuv3_vpu_fe_mem_pack.v`

The Falcon parameter-level golden flow is provided separately:

```text
script/falcon_fft_golden.py
script/verify_fft_golden.py
golden_vecs/
golden_vecs_1024/
gm_rom_re.hex / gm_rom_im.hex
```

`python script/verify_fft_golden.py --logn 9 --mode both` verifies Falcon-512
FFT/IFFT stage vectors against the RTL-equivalent CT/GS butterfly formulas.
The current status is therefore:

```text
operator-level RTL:          simulated
SPUV3 wrapper-level RTL:     simulated
Falcon stage-vector golden:  generated and pre-verified
full multi-stage RTL FFT:    pending stage wrapper / testbench integration
```
