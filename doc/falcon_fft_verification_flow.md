# Falcon FFT/IFFT RTL Verification Flow

## Overview

This document describes how to use the Python golden model generator to verify
the RTL `reconfig_fe_f64` / `reconfig_fft_f64_shared_operator` against the
Falcon reference FFT/IFFT.

## Current Status

The repository now has three verification layers for Falcon f64 FFT/IFFT:

1. RTL operator smoke tests:
   - `tb_reconfig_fft_f64_operator.v`
   - `tb_reconfig_fft_f64_pipe_operator.v`
   - `tb_reconfig_fft_f64_shared_operator.v`
   - `tb_spuv3_vpu_fe_f64_wrap.v`

   These prove that the CT/GS butterfly operator paths run in simulation.

2. Python golden stage-vector verification:
   - `script/falcon_fft_golden.py` generates Falcon FFT/IFFT stage vectors.
   - `script/verify_fft_golden.py` verifies the generated stage vectors and
     the RTL-equivalent butterfly formulas.
   - `golden_vecs/` contains Falcon-512 (`logn=9`) FFT/IFFT vectors.
   - `golden_vecs_1024/` contains Falcon-1024 (`logn=10`) FFT/IFFT vectors.
   - `gm_rom_re.hex` and `gm_rom_im.hex` provide f64 GM twiddle ROM contents.

3. RTL stage/batch bring-up:
   - `rtl/falcon_fft_stage_ctrl.v` sequences all Falcon FFT/iFFT stages and
     5-lane batches.
   - `rtl/falcon_fft_addr_gen.v` generates Falcon reference-style a/b address
     pairs and GM table indexes for forward FFT and iFFT.
   - `rtl/falcon_fft_batch_exu.v` wraps the shared f64 BFU as a 5-lane batch
     datapath.
   - `rtl/falcon_fft_task_engine.v` connects stage control, per-lane address
     generation, batch execution, and load/store handshakes for the future
     local-buffer or DLM gather/scatter layer.
   - `rtl/falcon_fft_local_buffer.v` keeps f64 complex data in two local banks
     so consecutive stages can ping-pong without returning to main memory.
   - `rtl/falcon_fft_twiddle_cache.v` serves GM twiddles independently from
     the data buffer and can negate the imaginary component for iFFT.
   - `rtl/falcon_fft_buffered_engine.v` ties the task engine, local buffer,
     twiddle cache, and selectable shared/pipelined FE backend together.
   - `script/run_fft_batch_rtl_compare.py` feeds generated batch files into
     the RTL batch EXU and compares active lanes only.

Current verified command:

```bash
python script/verify_fft_golden.py --logn 9 --mode both
python script/run_fft_batch_rtl_compare.py --logn 9 --mode both
python script/run_fft_batch_rtl_compare.py --logn 10 --mode fft
python script/run_fft_batch_rtl_compare.py --logn 10 --mode ifft
python script/run_fft_batch_rtl_compare.py --logn 9 --mode both --backend pipe
python script/run_fft_buffered_final_compare.py --logn 9 --mode fft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 9 --mode ifft --backend pipe --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode fft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode ifft --backend pipe --max-abs 1e-11
```

Expected summary:

```text
Configurations: 22 total, 22 pass, 0 fail
Butterfly operations: 22528/22528 passed
[PASS] All golden vectors verified successfully.
TB_PASS falcon_fft_batch_compare cases=416
TB_PASS falcon_fft_batch_compare cases=468
TB_PASS falcon_fft_buffered_engine_smoke
TB_PASS falcon_fft_buffered_final_compare N=512 mode=0 backend=0 cycles=2690 max_abs=3.943512e-12
TB_PASS falcon_fft_buffered_final_compare N=512 mode=1 backend=1 cycles=1874 max_abs=3.101519e-12
TB_PASS falcon_fft_buffered_final_compare N=1024 mode=0 backend=0 cycles=6050 max_abs=0.000000e+00
TB_PASS falcon_fft_buffered_final_compare N=1024 mode=1 backend=1 cycles=4214 max_abs=0.000000e+00
```

This means the Falcon FFT/IFFT golden model, RTL-equivalent CT/GS butterfly
formulas, 5-lane batch EXU, and local-buffered multi-stage engine are
consistent for Falcon-512 and Falcon-1024.  The buffered final-array checks
compare the full scalar `f[]` layout after all stages.

## Quick Start

```bash
# Falcon-512 FFT + IFFT golden vectors (N=512, logn=9)
python script/falcon_fft_golden.py --logn 9 --mode both --outdir ./golden_vecs

# Falcon-1024 FFT + IFFT, with Falcon-style polynomial input
python script/falcon_fft_golden.py --logn 10 --mode both \
    --input-type falcon_poly --outdir ./golden_vecs_1024

# Use Falcon official GM table instead of Python-generated
python script/falcon_fft_golden.py --logn 9 --mode both \
    --gm-re path/to/gm_rom_re.hex --gm-im path/to/gm_rom_im.hex

# Drive generated 5-lane batch vectors into RTL
python script/run_fft_batch_rtl_compare.py --logn 9 --mode both
python script/run_fft_batch_rtl_compare.py --logn 10 --mode fft
python script/run_fft_batch_rtl_compare.py --logn 10 --mode ifft
```

## Output Files

```
golden_vecs/
  fft_input.txt              # Test input array (f64 hex)
  fft_final.txt              # Final FFT output
  ifft_final.txt             # Final IFFT output
  fft_stages/
    stage_00_summary.txt     # All 128 butterfly pairs, human-readable
    stage_00_batch_000.hex   # Batch 0: 5-lane 320-bit hex vectors
    stage_00_batch_001.hex   # Batch 1
    ...
    stage_07_batch_025.hex   # Last batch of stage 7
  ifft_stages/
    stage_00_summary.txt     # IFFT stage 0 (outermost loop)
    ...
```

## RTL Batch Hex Format

Each `stage_SS_batch_BBB.hex` contains two 320-bit lines:

```
# va_re           va_im           vb_re           vb_im           tw_re           tw_im
<80 hex chars>  <80 hex chars>  <80 hex chars>  <80 hex chars>  <80 hex chars>  <80 hex chars>

# y0_re           y0_im           y1_re           y1_im
<80 hex chars>  <80 hex chars>  <80 hex chars>  <80 hex chars>
```

Each 80-char string encodes 5 x 64-bit f64 values, MSB-lane-first (lane 4 at
the left, lane 0 at the right).  This matches the SPUV3 `va_re_vr_i[319:0]`
etc. bit layout.

## Verification Flow

### Step 1: Verify single-lane butterfly (reconfig_fe_f64)

```python
from falcon_fft_golden import rtl_ct_butterfly, rtl_gs_butterfly

# Read RTL simulation output hex, compare against golden
(y0_re, y0_im), (y1_re, y1_im) = rtl_ct_butterfly(
    a_re, a_im, b_re, b_im, w_re, w_im)
```

### Step 2: Verify shared array (reconfig_fe_f64_shared_array)

Feed one batch from `stage_00_batch_000.hex` as 320-bit VR inputs.
After FE_LATENCY cycles, compare output against the `y0_*/y1_*` golden line.

For SPUV3-aligned testing, use the 5-lane wrapper path:

```text
stage_SS_batch_BBB.hex
  -> va/vb/tw 320-bit vectors
  -> spuv3_vpu_fe_f64_wrap
  -> reconfig_fft_f64_shared_operator
  -> y0/y1 320-bit vectors
  -> compare against golden y0/y1 line
```

The batch files are already packed as 5 x 64-bit lanes, matching one SPUV3
320-bit VR.  No extra lane repacking is needed at this boundary.

### Step 3: Verify stage/batch control and RTL batch EXU

```bash
iverilog -g2012 -o sim/tb_falcon_fft_addr_gen.vvp \
  -f rtl/filelist.f tb/tb_falcon_fft_addr_gen.v && \
  vvp sim/tb_falcon_fft_addr_gen.vvp

iverilog -g2012 -o sim/tb_falcon_fft_stage_ctrl.vvp \
  -f rtl/filelist.f tb/tb_falcon_fft_stage_ctrl.v && \
  vvp sim/tb_falcon_fft_stage_ctrl.vvp

iverilog -g2012 -o sim/tb_falcon_fft_task_engine_smoke.vvp \
  -f rtl/filelist.f tb/tb_falcon_fft_task_engine_smoke.v && \
  vvp sim/tb_falcon_fft_task_engine_smoke.vvp

iverilog -g2012 -o sim/tb_falcon_fft_buffered_engine_smoke.vvp \
  -f rtl/filelist.f tb/tb_falcon_fft_buffered_engine_smoke.v && \
  vvp sim/tb_falcon_fft_buffered_engine_smoke.vvp

python script/run_fft_batch_rtl_compare.py --logn 9 --mode both
python script/run_fft_batch_rtl_compare.py --logn 10 --mode fft
python script/run_fft_batch_rtl_compare.py --logn 10 --mode ifft
python script/run_fft_batch_rtl_compare.py --logn 9 --mode both --backend pipe

python script/run_fft_buffered_final_compare.py --logn 9 --mode fft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 9 --mode ifft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 9 --mode fft --backend pipe --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 9 --mode ifft --backend pipe --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode fft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode ifft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode fft --backend pipe --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode ifft --backend pipe --max-abs 1e-11
```

Current passing coverage:

```text
TB_PASS falcon_fft_addr_gen
TB_PASS falcon_fft_stage_ctrl
TB_PASS falcon_fft_task_engine_smoke
TB_PASS falcon_fft_buffered_engine_smoke
TB_PASS falcon_fft_batch_compare cases=416  # Falcon-512 FFT/IFFT
TB_PASS falcon_fft_batch_compare cases=468  # Falcon-1024 FFT/IFFT
TB_PASS falcon_fft_buffered_final_compare N=512 mode=0 backend=0
TB_PASS falcon_fft_buffered_final_compare N=512 mode=1 backend=0
TB_PASS falcon_fft_buffered_final_compare N=512 mode=0 backend=1
TB_PASS falcon_fft_buffered_final_compare N=512 mode=1 backend=1
TB_PASS falcon_fft_buffered_final_compare N=1024 mode=0 backend=0
TB_PASS falcon_fft_buffered_final_compare N=1024 mode=1 backend=0
TB_PASS falcon_fft_buffered_final_compare N=1024 mode=0 backend=1
TB_PASS falcon_fft_buffered_final_compare N=1024 mode=1 backend=1
```

The previous Falcon-1024 FFT buffered final-array `idx=0` mismatch is fixed.
Root cause: `falcon_fft_addr_gen` stored `n_val = 1 << logn` in an `ADDR_W`
wide register; for `logn=10`, `1024` overflowed the 10-bit internal value to
zero.  The internal `n_val` is now `ADDR_W+1` bits while output addresses remain
10-bit scalar indexes.

### Step 4: Verify multi-stage FFT pipeline (when built)

Feed `fft_input.txt` through the full pipeline.  After each stage, compare
the RF contents against the output of `falcon_fft()` for that stage.

### Step 5: Round-trip check

Run FFT then IFFT.  The output should match the input (error < 1e-12 for f64).

## Key IFFT Twiddle Convention

The Falcon C reference iFFT uses `conj(GM) * (a-b)` for the GS butterfly.
The RTL `reconfig_fe_f64` GS mode computes `w * (a-b)` with NO built-in conj.

**Therefore**: when using the RTL GS mode for IFFT, the twiddle input MUST be
pre-conjugated.  The golden vectors from `ifft_stages/` already provide the
conjugated twiddle in the `w_re`/`w_im` fields.

## Cross-reference against Falcon Official Implementation

The Python golden model matches the official Falcon `fft.c` (round-3) exactly:

| Falcon C function | Python function | Verified |
|---|---|---|
| `Zf(FFT)` | `falcon_fft()` | Round-trip pass |
| `Zf(iFFT)` | `falcon_ifft()` | Round-trip pass |
| CT butterfly | `rtl_ct_butterfly()` | Matches RTL `reconfig_fe_f64` mode=0 |
| GS butterfly | `rtl_gs_butterfly()` | Matches RTL `reconfig_fe_f64` mode=1 |
| GM table | `generate_gm_table()` | w = exp(i*pi/N), bit-reversed |
