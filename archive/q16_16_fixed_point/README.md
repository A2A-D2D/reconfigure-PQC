# Q16.16 Fixed-Point FE Prototype Archive

This folder keeps the early fixed-point FE/FFT prototype for bring-up and
structure reference. It is intentionally outside the main RTL file list because
the architecture-aligned SPUV3/Falcon path now uses the f64 FE modules under
`rtl/`.

## Contents

- `rtl/reconfig_fe.v`: single Q16.16 fixed-point FE lane.
- `rtl/reconfig_fe_array.v`: fixed-point FE lane array.
- `rtl/reconfig_fft_operator.v`: fixed-point FFT butterfly operator.
- `tb/tb_reconfig_fe.v`: FE lane self-checking testbench.
- `tb/tb_reconfig_fft_operator.v`: fixed-point FFT operator testbench.
- `doc/fe_design_notes.md`: original notes for the fixed-point FE prototype.
- `sim/*.vvp`: archived compiled simulation artifacts.

## Build

From the repository root:

```bash
iverilog -g2001 -o archive/q16_16_fixed_point/sim/tb_reconfig_fe.vvp \
  archive/q16_16_fixed_point/rtl/reconfig_fe.v \
  archive/q16_16_fixed_point/tb/tb_reconfig_fe.v && \
  vvp archive/q16_16_fixed_point/sim/tb_reconfig_fe.vvp

iverilog -g2001 -o archive/q16_16_fixed_point/sim/tb_reconfig_fft_operator.vvp \
  archive/q16_16_fixed_point/rtl/reconfig_fe.v \
  archive/q16_16_fixed_point/rtl/reconfig_fe_array.v \
  archive/q16_16_fixed_point/rtl/reconfig_fft_operator.v \
  archive/q16_16_fixed_point/tb/tb_reconfig_fft_operator.v && \
  vvp archive/q16_16_fixed_point/sim/tb_reconfig_fft_operator.vvp
```
