# Reconfigurable Arithmetic Element for Multi-Scheme PQC

A hardware accelerator supporting **ML-KEM** (FIPS 203), **ML-DSA** (FIPS 204), and **Falcon**
through a unified 16-mode reconfigurable arithmetic element (AE).

For a presentation-oriented top-level file map, see
[`TOP_LEVEL_STRUCTURE_zh.md`](TOP_LEVEL_STRUCTURE_zh.md).

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                    PQC Application                        │
│   ML-KEM (Kyber)  │  ML-DSA (Dilithium)  │  Falcon       │
└────────────────────┬─────────────────────┬───────────────┘
                     │                     │
           ┌─────────┴─────────┐  ┌────────┴────────┐
           │ reconfig_ntt_op   │  │ reconfig_fft_op  │  ← Operator level
           └────────┬──────────┘  └────────┬─────────┘
                    │                      │
           ┌────────┴──────────┐  ┌────────┴─────────┐
           │ reconfig_ae_array │  │ reconfig_fe_array │  ← Array level (32/8 lanes)
           │   (32 lanes)      │  │   (8 lanes)       │
           └────────┬──────────┘  └────────┬──────────┘
                    │                      │
           ┌────────┴──────────┐  ┌────────┴─────────┐
           │  reconfig_ae      │  │  reconfig_fe      │  ← Element level
           │  (16-mode ALU)    │  │  (10-mode FP ALU) │
           └───────────────────┘  └───────────────────┘
                    │                      │
           ┌────────┴──────────┐  ┌────────┴─────────┐
           │ barrett_reduce    │  │  Fixed-point MAC  │  ← Primitives
           │ montgomery_reduce │  │  (Q16.16 format)  │
           └───────────────────┘  └───────────────────┘
```

## Pipeline

```
Cycle 0       Cycle 1         Cycle 2          Cycle 3
┌─────────┐   ┌──────────┐   ┌────────────┐   ┌──────────┐
│ S0       │   │ S1        │   │ S2          │   │ Output    │
│ Input    │──▶│ Multiply   │──▶│ Barrett/    │──▶│ Mode      │
│ Reduce   │   │ 4×32×32   │   │ Montgomery  │   │ Select    │
│ a±b pre  │   │ parallel  │   │ Reduce      │   │ valid_out │
└─────────┘   └──────────┘   └────────────┘   └──────────┘
```

- **Latency**: 4 clock cycles (40 ns @ 100 MHz)
- **Throughput**: 1 operation/cycle (fully pipelined, no bubbles)
- **Peak throughput**: 32 lanes × 2 outputs/cycle = 64 results/cycle

## File List

### RTL — Arithmetic Core

| File | Description |
|------|-------------|
| [`rtl/ntt/reconfig_ae.v`](rtl/ntt/reconfig_ae.v) | 16-mode reconfigurable AE (Barrett + Montgomery reduction) |
| [`rtl/ntt/reconfig_ae_array.v`](rtl/ntt/reconfig_ae_array.v) | 32-lane flat AE cluster |
| [`rtl/ntt/reconfig_ae_rf.v`](rtl/ntt/reconfig_ae_rf.v) | AE + local register file wrapper |
| [`rtl/ntt/barrett_reduce.v`](rtl/ntt/barrett_reduce.v) | Barrett modular reduction |
| [`rtl/ntt/montgomery_reduce.v`](rtl/ntt/montgomery_reduce.v) | Montgomery modular reduction (addition variant) |
| [`rtl/ntt/ae_regfile.v`](rtl/ntt/ae_regfile.v) | Per-lane register file (2-read, 1-write) |

### RTL — Fixed-Point / Falcon (FFT)

| File | Description |
|------|-------------|
| [`rtl/spuv3_vpu/spuv3_vpu_fe_f64_wrap.v`](rtl/spuv3_vpu/spuv3_vpu_fe_f64_wrap.v) | 320-bit vector register adapter for Falcon f64 FFT |
| [`rtl/spuv3_vpu/spuv3_vpu_fe_mem_pack.v`](rtl/spuv3_vpu/spuv3_vpu_fe_mem_pack.v) | 256-bit memory row packer for 320-bit vector data |
| [`rtl/falcon_fft/falcon_fft_stage_ctrl.v`](rtl/falcon_fft/falcon_fft_stage_ctrl.v) | Falcon FFT/iFFT stage and batch task controller |
| [`rtl/falcon_fft/falcon_fft_addr_gen.v`](rtl/falcon_fft/falcon_fft_addr_gen.v) | Falcon forward/iFFT butterfly address and GM index generator |
| [`rtl/falcon_fft/falcon_fft_batch_exu.v`](rtl/falcon_fft/falcon_fft_batch_exu.v) | 5-lane batch EXU wrapper around the shared f64 BFU |
| [`rtl/falcon_fft/falcon_fft_task_engine.v`](rtl/falcon_fft/falcon_fft_task_engine.v) | Task-level FFT engine shell with load/execute/store handshakes |
| [`rtl/falcon_fft/falcon_fft_local_buffer.v`](rtl/falcon_fft/falcon_fft_local_buffer.v) | Two-bank local f64 complex buffer for stage-to-stage ping-pong |
| [`rtl/falcon_fft/falcon_fft_twiddle_cache.v`](rtl/falcon_fft/falcon_fft_twiddle_cache.v) | Independent lane-wide GM twiddle cache with iFFT conjugation |
| [`rtl/falcon_fft/falcon_fft_buffered_engine.v`](rtl/falcon_fft/falcon_fft_buffered_engine.v) | Buffered FFT engine tying task control, local buffer, twiddle cache, and FE backend |
| [`rtl/falcon_fe/reconfig_fft_f64_shared_operator.v`](rtl/falcon_fe/reconfig_fft_f64_shared_operator.v) | Area-oriented f64 FFT operator using shared FE |
| [`rtl/falcon_fe/reconfig_fe_f64_shared_array.v`](rtl/falcon_fe/reconfig_fe_f64_shared_array.v) | Shared f64 FE array with lane mask and backpressure |
| [`rtl/falcon_fe/reconfig_fft_f64_pipe_operator.v`](rtl/falcon_fe/reconfig_fft_f64_pipe_operator.v) | Higher-throughput pipelined f64 FFT operator |
| [`rtl/falcon_fe/reconfig_fft_f64_operator.v`](rtl/falcon_fe/reconfig_fft_f64_operator.v) | Reference f64 FFT operator |

### RTL — NTT Operator

| File | Description |
|------|-------------|
| [`rtl/ntt/reconfig_ntt_operator.v`](rtl/ntt/reconfig_ntt_operator.v) | NTT operator (wraps 32-lane AE array) |

### RTL — Infrastructure

| File | Description |
|------|-------------|
| [`rtl/ntt/shuffle_net.v`](rtl/ntt/shuffle_net.v) | Shuffle network for NTT data permutation |
| [`rtl/rom/useq_core.v`](rtl/rom/useq_core.v) | Micro-sequencer core |

### Verification

| File | Description |
|------|-------------|
| [`tb/ae/tb_mlkem_ae.v`](tb/ae/tb_mlkem_ae.v) | ML-KEM (FIPS 203) arithmetic verification |
| [`tb/ae/tb_mldsa_ae.v`](tb/ae/tb_mldsa_ae.v) | ML-DSA (FIPS 204) arithmetic verification |
| [`tb/ntt/tb_reconfig_ntt_operator.v`](tb/ntt/tb_reconfig_ntt_operator.v) | NTT operator 32-lane verification (Falcon q=12289) |
| [`tb/spuv3_vpu/tb_spuv3_vpu_fe_f64_wrap.v`](tb/spuv3_vpu/tb_spuv3_vpu_fe_f64_wrap.v) | Vector register adapter verification |
| [`tb/spuv3_vpu/tb_spuv3_vpu_fe_mem_pack.v`](tb/spuv3_vpu/tb_spuv3_vpu_fe_mem_pack.v) | 256-bit memory row to 320-bit vector pack/unpack verification |
| [`tb/falcon_fft/tb_falcon_fft_addr_gen.v`](tb/falcon_fft/tb_falcon_fft_addr_gen.v) | Falcon FFT/iFFT address generator verification |
| [`tb/falcon_fft/tb_falcon_fft_stage_ctrl.v`](tb/falcon_fft/tb_falcon_fft_stage_ctrl.v) | Falcon-512 stage/batch controller verification |
| [`tb/falcon_fft/tb_falcon_fft_task_engine_smoke.v`](tb/falcon_fft/tb_falcon_fft_task_engine_smoke.v) | Task engine load/execute/store smoke verification |
| [`tb/falcon_fft/tb_falcon_fft_buffered_engine_smoke.v`](tb/falcon_fft/tb_falcon_fft_buffered_engine_smoke.v) | Local-buffered FFT engine smoke verification |
| [`tb/falcon_fe/tb_reconfig_fft_f64_shared_operator.v`](tb/falcon_fe/tb_reconfig_fft_f64_shared_operator.v) | Shared f64 FFT operator verification |
| [`tb/falcon_fe/tb_reconfig_fe_f64_shared_array.v`](tb/falcon_fe/tb_reconfig_fe_f64_shared_array.v) | Shared f64 FE array verification |

### Archived Q16.16 Fixed-Point Prototype

The early Q16.16 FE/FFT prototype has been moved to
[`archive/q16_16_fixed_point`](archive/q16_16_fixed_point). It is kept for
bring-up reference, but it is no longer part of the architecture-aligned main
RTL file list.

## 16-Mode Reconfigurable AE

All modes operate on `WORD_W=32` with 3-stage pipeline. `MODE_W=4`.

### Baseline Modes (0–7): Barrett-based NTT / Polynomial Arithmetic

| Mode | Name | Operation | Use Case |
|:----:|------|-----------|----------|
| 0 | `CT_BFU` | `y0=a+b·w`, `y1=a−b·w` (mod q) | Forward NTT butterfly |
| 1 | `GS_BFU` | `y0=a+b`, `y1=(a−b)·w` (mod q) | Inverse NTT butterfly |
| 2 | `MUL_ADD` | `y0=a·b+c`, `y1=a·b` (mod q) | Point-wise MAC |
| 3 | `ADD_MUL` | `y0=(a+b)·c`, `y1=a+b` (mod q) | Base multiplication component |
| 4 | `ADD_SUB` | `y0=a+b`, `y1=a−b` (mod q) | Polynomial add/sub |
| 5 | `BIG_MUL` | `y0=lo(a·b)`, `y1=hi(a·b)` | Big-integer multiply (64-bit result) |
| 6 | `MUL_ACC` | `acc += a·b`, `y0/y1 = a·b` | Long-chain dot-product accumulation |
| 7 | `ACC_RD` | `y0=acc_lo`, `y1=acc_hi` | Accumulator readback |

### Extended Modes (8–15): Montgomery, Dual-Path, Lazy

| Mode | Name | Operation | Use Case |
|:----:|------|-----------|----------|
| 8 | `MONT_MUL` | `y0=MontRed(a·b)`, `y1=raw_lo` | Kyber/Dilithium base multiplication |
| 9 | `MUL_SUB` | `y0=a·b−c`, `y1=a·b` (mod q) | Differential point-wise multiply |
| 10 | `MADD_MSUB` | `y0=a·b+c`, `y1=a·b−c` (mod q) | Symmetric polynomial evaluation |
| 11 | `MACC_W` | `y0=a·b+w`, `y1=a·b` (mod q) | Twiddle-factor MAC |
| 12 | `SQUARE` | `y0=a²`, `y1=b·w` (mod q) | Squaring + parallel multiply |
| 13 | `CT_LAZY` | `y0=a+b·w`, `y1=a−b·w` (no mod) | Lazy-reduction NTT strategy |
| 14 | `COND_RED` | `y0=reduce(a)`, `y1=reduce(b)` | Conditional coefficient reduction |
| 15 | `PASSTHRU` | `y0=a`, `y1=b` | Data passthrough / debug |

## PQC Scheme Mapping

| Operation | ML-KEM | ML-DSA | Falcon |
|-----------|:------:|:------:|:------:|
| Forward NTT (CT) | mode 0 | mode 0 | mode 0 |
| Inverse NTT (GS) | mode 1 | mode 1 | mode 1 |
| Point-wise MAC | mode 2,6 | mode 2,6 | — |
| Base Mul (Montgomery) | mode 8 | mode 8 | — |
| Matrix-vector MAC | mode 2 | mode 2,9,10,11 | — |
| Polynomial Add/Sub | mode 4 | mode 4 | — |
| Squaring | mode 12 | mode 12 | — |
| Lazy Reduction | mode 13 | mode 13 | — |
| Conditional Reduce | mode 14 | mode 14 | — |
| Complex FFT | — | — | `reconfig_fe` (Q16.16) |

## Parameters

| PQC Scheme | Modulus q | Bit Width | Barrett μ | Montgomery q_inv |
|------------|-----------|-----------|-----------|-------------------|
| ML-KEM (Kyber-512/768/1024) | 3329 | 12 | `2²⁴ / 3329` | `−3329⁻¹ mod 2³²` |
| ML-DSA (Dilithium-2/3/5) | 8380417 | 23 | `2⁴⁶ / 8380417` | `−8380417⁻¹ mod 2³²` |
| Falcon-512/1024 | 12289 | 14 | `2²⁸ / 12289` | `−12289⁻¹ mod 2³²` |

## Verification Results

Current RTL testbenches pass for the implemented arithmetic operators,
wrapper-level Falcon f64 paths, and the Falcon FFT stage/batch/address control
layer.  Golden batch files are now driven into RTL at the 5-lane batch EXU
boundary with active-lane comparison.  The local-buffered multi-stage RTL engine
now passes final-array comparison for Falcon-512 and Falcon-1024 FFT/IFFT.

```
ML-KEM (FIPS 203, q=3329):    30/30 checks passed
ML-DSA (FIPS 204, q=8380417): 28/28 checks passed
Falcon NTT (q=12289):         64/64 lane-results (2 cases × 32 lanes)
Fixed-Point FE:               10/10 modes passed
FFT Operator:                 2/2 cases (8 lanes each)
Falcon FFT/IFFT golden:        logn=9 both modes, 22528/22528 butterflies
Falcon RTL batch compare:      shared+pipe backends, logn=9 FFT/IFFT 416 cases, logn=10 FFT/IFFT 468 cases
Falcon buffered final compare: logn=9 FFT/IFFT abs <= 1e-11, logn=10 FFT/IFFT bit-exact
```

### Tested Arithmetic Operations
- ✅ CT/GS NTT butterflies (modes 0,1)
- ✅ Barrett-based point-wise multiply and MAC (modes 2,3,4)
- ✅ Montgomery modular multiplication (mode 8)
- ✅ Multiply-subtract, dual-path, twiddle-MAC (modes 9,10,11)
- ✅ Square (mode 12)
- ✅ Lazy reduction NTT (mode 13)
- ✅ Conditional coefficient reduction (mode 14)
- ✅ 64-bit multiply-accumulate chain (modes 5,6,7)
- ✅ Complex fixed-point CT/GS butterflies (FE modes 0,1)
- ✅ Complex multiply, square, MAC (FE modes 2–9)
- ✅ Falcon f64 CT/GS operator smoke tests
- ✅ Falcon FFT/IFFT Python golden stage-vector checks (`logn=9`)
- ✅ Falcon FFT stage/address controller and active-lane RTL batch compare
- ✅ Local ping-pong buffer, twiddle cache, and buffered task-engine smoke path
- ✅ Full multi-stage Falcon-512/Falcon-1024 FFT/IFFT RTL final-array comparison

## Toolchain

The verification flow is script-first.  Users should not need to type raw
`iverilog` commands for normal regressions.

Required tools:

| Tool | Purpose |
|------|---------|
| Python 3 | Golden generation, regression orchestration, temporary TB generation |
| Icarus Verilog `iverilog` | Verilog/SystemVerilog compilation |
| Icarus runtime `vvp` | Simulation execution |

The Python scripts use the standard library only.  No `numpy`, `scipy`, or
`matplotlib` dependency is required.

Check the local toolchain:

```bash
python --version
iverilog -V
vvp -V
```

## Simulation

All static testbenches under `tb/` are driven by:

```bash
python script/run_rtl_tests.py --list
python script/run_rtl_tests.py                 # representative smoke suite
python script/run_rtl_tests.py --suite all     # all static RTL testbenches
```

Useful category filters:

```bash
python script/run_rtl_tests.py --category ae
python script/run_rtl_tests.py --category ntt
python script/run_rtl_tests.py --category falcon_fe
python script/run_rtl_tests.py --category falcon_fft
python script/run_rtl_tests.py --category spuv3_vpu
```

Useful name filters:

```bash
python script/run_rtl_tests.py --pattern "tb_vpu_fe_*"
python script/run_rtl_tests.py --pattern "*shared*"
```

By default, compiled `.vvp` files and logs are created in a temporary directory
and removed.  To keep artifacts:

```bash
python script/run_rtl_tests.py --suite all --keep
```

Kept artifacts go under `sim/script_runs/`.

### Falcon Golden And RTL Compare Scripts

Golden vector generation:

```bash
python script/falcon_fft_golden.py --logn 9 --mode both --outdir ./golden_vecs
python script/falcon_fft_golden.py --logn 10 --mode both --outdir ./golden_vecs_1024
```

Python-only pre-verification:

```bash
python script/verify_fft_golden.py --logn 9 --mode both
python script/verify_fft_golden.py --logn 10 --mode both
```

Falcon FFT batch vectors against RTL batch EXU:

```bash
python script/run_fft_batch_rtl_compare.py --logn 9 --mode both --backend shared
python script/run_fft_batch_rtl_compare.py --logn 9 --mode both --backend pipe
python script/run_fft_batch_rtl_compare.py --logn 10 --mode both --backend shared
python script/run_fft_batch_rtl_compare.py --logn 10 --mode both --backend pipe
```

Buffered engine final-array checks:

```bash
python script/run_fft_buffered_final_compare.py --logn 9 --mode fft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 9 --mode ifft --backend pipe --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode fft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode ifft --backend pipe --max-abs 1e-11
```

## NTT Performance

| Metric | Value |
|--------|-------|
| Polynomial degree (n) | 256 |
| NTT stages | 8 (log₂ 256) |
| Butterflies per stage | 128 |
| Parallel lanes | 32 |
| Batches per stage | 4 |
| Cycles per stage | ~7–10 |
| **Cycles per full NTT** | **~80–96** |
| **Time @ 100 MHz** | **~0.8–1.0 µs** |
| Forward + Inverse NTT | ~2.0 µs |
| Throughput @ 100 MHz | ~500K NTT/s |

## Key Design Decisions

1. **Flat 32-lane instantiation** instead of generate loops — enables heterogeneous lane wiring, carry chains, and per-lane mode assignment for future extensions.

2. **Addition-variant Montgomery reduction** — replaces subtraction variant for cleaner hardware path and same correctness for odd q.

3. **3-level conditional subtraction** in S0 reduction — valid for inputs up to ~4×q, handles typical PQC coefficient ranges without strict external pre-reduction.

4. **Unified accumulator (P4)** — 64-bit multiply-accumulate register shared across all lanes, enables long-chain dot products without external memory.

5. **Mode-based pipeline** — all parameters (`use_mod`, `modulus`, `mu`, `mu_mont`, `k_log2`) propagate through the 3-stage pipeline, allowing mode-per-cycle reconfiguration.

## References

- Montgomery, "Modular Multiplication Without Trial Division", Math. Comp. 1985
- Barrett, "Implementing the RSA Public Key Encryption Scheme on a Standard DSP", CRYPTO 1986
- FIPS 203: Module-Lattice-Based Key-Encapsulation Mechanism (ML-KEM)
- FIPS 204: Module-Lattice-Based Digital Signature Standard (ML-DSA)
- Falcon: Fast-Fourier Lattice-based Compact Signatures over NTRU (Round 3)
