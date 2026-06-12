# Reconfigurable Arithmetic Element for Multi-Scheme PQC

A hardware accelerator supporting **ML-KEM** (FIPS 203), **ML-DSA** (FIPS 204), and **Falcon**
through a unified 16-mode reconfigurable arithmetic element (AE).

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
| [`rtl/reconfig_ae.v`](rtl/reconfig_ae.v) | 16-mode reconfigurable AE (Barrett + Montgomery reduction) |
| [`rtl/reconfig_ae_array.v`](rtl/reconfig_ae_array.v) | 32-lane flat AE cluster |
| [`rtl/reconfig_ae_rf.v`](rtl/reconfig_ae_rf.v) | AE + local register file wrapper |
| [`rtl/barrett_reduce.v`](rtl/barrett_reduce.v) | Barrett modular reduction |
| [`rtl/montgomery_reduce.v`](rtl/montgomery_reduce.v) | Montgomery modular reduction (addition variant) |
| [`rtl/ae_regfile.v`](rtl/ae_regfile.v) | Per-lane register file (2-read, 1-write) |

### RTL — Fixed-Point / Falcon (FFT)

| File | Description |
|------|-------------|
| [`rtl/spuv3_vpu_fe_f64_wrap.v`](rtl/spuv3_vpu_fe_f64_wrap.v) | SPUV3 320-bit VR / VMASK adapter for Falcon f64 FFT |
| [`rtl/reconfig_fft_f64_shared_operator.v`](rtl/reconfig_fft_f64_shared_operator.v) | Area-oriented f64 FFT operator using shared FE |
| [`rtl/reconfig_fe_f64_shared_array.v`](rtl/reconfig_fe_f64_shared_array.v) | Shared f64 FE array with lane mask and backpressure |
| [`rtl/reconfig_fft_f64_pipe_operator.v`](rtl/reconfig_fft_f64_pipe_operator.v) | Higher-throughput pipelined f64 FFT operator |
| [`rtl/reconfig_fft_f64_operator.v`](rtl/reconfig_fft_f64_operator.v) | Reference f64 FFT operator |

### RTL — NTT Operator

| File | Description |
|------|-------------|
| [`rtl/reconfig_ntt_operator.v`](rtl/reconfig_ntt_operator.v) | NTT operator (wraps 32-lane AE array) |

### RTL — Infrastructure

| File | Description |
|------|-------------|
| [`rtl/shuffle_net.v`](rtl/shuffle_net.v) | Shuffle network for NTT data permutation |
| [`rtl/useq_core.v`](rtl/useq_core.v) | Micro-sequencer core |

### Verification

| File | Description |
|------|-------------|
| [`tb/tb_mlkem_ae.v`](tb/tb_mlkem_ae.v) | ML-KEM (FIPS 203) arithmetic verification |
| [`tb/tb_mldsa_ae.v`](tb/tb_mldsa_ae.v) | ML-DSA (FIPS 204) arithmetic verification |
| [`tb/tb_reconfig_ntt_operator.v`](tb/tb_reconfig_ntt_operator.v) | NTT operator 32-lane verification (Falcon q=12289) |
| [`tb/tb_spuv3_vpu_fe_f64_wrap.v`](tb/tb_spuv3_vpu_fe_f64_wrap.v) | SPUV3 VMASK/VR adapter verification |
| [`tb/tb_reconfig_fft_f64_shared_operator.v`](tb/tb_reconfig_fft_f64_shared_operator.v) | Shared f64 FFT operator verification |
| [`tb/tb_reconfig_fe_f64_shared_array.v`](tb/tb_reconfig_fe_f64_shared_array.v) | Shared f64 FE array verification |

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

All testbenches pass with 100% coverage across all modes and PQC parameter sets.

```
ML-KEM (FIPS 203, q=3329):    30/30 checks passed
ML-DSA (FIPS 204, q=8380417): 28/28 checks passed
Falcon NTT (q=12289):         64/64 lane-results (2 cases × 32 lanes)
Fixed-Point FE:               10/10 modes passed
FFT Operator:                 2/2 cases (8 lanes each)
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

## Simulation

Requires [Icarus Verilog](http://iverilog.icarus.com/) (or any Verilog simulator).

```bash
# ML-KEM
iverilog -g2012 -o sim/tb_mlkem_ae.vvp \
  rtl/barrett_reduce.v rtl/montgomery_reduce.v rtl/reconfig_ae.v \
  tb/tb_mlkem_ae.v && vvp sim/tb_mlkem_ae.vvp

# ML-DSA
iverilog -g2012 -o sim/tb_mldsa_ae.vvp \
  rtl/barrett_reduce.v rtl/montgomery_reduce.v rtl/reconfig_ae.v \
  tb/tb_mldsa_ae.v && vvp sim/tb_mldsa_ae.vvp

# NTT Operator (Falcon)
iverilog -g2012 -o sim/tb_ntt_op.vvp \
  rtl/barrett_reduce.v rtl/montgomery_reduce.v rtl/reconfig_ae.v \
  rtl/reconfig_ae_array.v rtl/reconfig_ntt_operator.v \
  tb/tb_reconfig_ntt_operator.v && vvp sim/tb_ntt_op.vvp

# SPUV3 f64 FE adapter
iverilog -g2001 -o sim/tb_spuv3_vpu_fe_f64_wrap.vvp \
  rtl/falcon_f64_add.v rtl/falcon_f64_mul.v rtl/reconfig_fe_f64.v \
  rtl/reconfig_fe_f64_shared_array.v rtl/reconfig_fft_f64_shared_operator.v \
  rtl/spuv3_vpu_fe_f64_wrap.v tb/tb_spuv3_vpu_fe_f64_wrap.v && \
  vvp sim/tb_spuv3_vpu_fe_f64_wrap.vvp
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
