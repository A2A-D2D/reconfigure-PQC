#!/usr/bin/env python3
"""
Falcon FFT/IFFT Golden Model Generator
========================================

Stage-level golden vector generator for RTL verification of the
reconfigurable f64 FE/FFT operator (reconfig_fe_f64 /
reconfig_fft_f64_shared_operator).

Produces per-stage, per-lane, per-butterfly expected input/output vectors so
that a stage-level RTL testbench can compare the FE operator output against
the golden reference lane-by-lane.

Key references:
  - Falcon round-3 Reference_Implementation/falcon512/falcon512int/fft.c
  - Falcon fpr.h: fpr = IEEE-754 binary64 (standard C double, bitwise identical)

Usage:
  # Falcon-512 FFT golden vectors
  python falcon_fft_golden.py --logn 9 --mode fft

  # Falcon-1024 IFFT golden vectors
  python falcon_fft_golden.py --logn 10 --mode ifft

  # Both directions, custom output dir
  python falcon_fft_golden.py --logn 9 --mode both --outdir ./golden_vecs/

  # Use external GM twiddle hex files (from Falcon reference build)
  python falcon_fft_golden.py --logn 9 --mode fft \\
      --gm-re gm_rom_re.hex --gm-im gm_rom_im.hex

Output files (per stage):
  stage_SS_batch_BBB.hex   -- RTL-ready 320-bit hex vectors (a,b,w -> y0,y1)
  stage_SS_summary.txt     -- all butterflies for stage S, human-readable
  fft_final.txt            -- final FFT array (f64 hex per element)
  ifft_final.txt           -- final IFFT array
"""

import struct
import cmath
import math
import argparse
import os
import sys
import random
from typing import List, Tuple, Optional

# ============================================================================
# IEEE-754 binary64 helpers
# ============================================================================

def f64_to_hex(v: float) -> str:
    """Python float -> 16-char hex (big-endian IEEE-754 binary64)."""
    return struct.pack('>d', v).hex()

def hex_to_f64(h: str) -> float:
    """16-char hex -> Python float."""
    return struct.unpack('>d', bytes.fromhex(h.strip()))[0]

def f64_bits(v: float) -> int:
    """Python float -> uint64 bit pattern."""
    return struct.unpack('>Q', struct.pack('>d', v))[0]

def bits_to_f64(u: int) -> float:
    """uint64 bit pattern -> Python float."""
    return struct.unpack('>d', struct.pack('>Q', u))[0]

# ============================================================================
# Complex arithmetic (matches RTL: falcon_f64_add / falcon_f64_mul exactly)
# ============================================================================

def cadd(ar, ai, br, bi):
    """Complex add: (ar + i*ai) + (br + i*bi)."""
    return ar + br, ai + bi

def csub(ar, ai, br, bi):
    """Complex sub: (ar + i*ai) - (br + i*bi)."""
    return ar - br, ai - bi

def cmul(ar, ai, br, bi):
    """
    Complex mul: (ar + i*ai) * (br + i*bi)
               = (ar*br - ai*bi) + i*(ar*bi + ai*br)
    """
    return ar*br - ai*bi, ar*bi + ai*br

def cconj(r, i):
    """Complex conjugate."""
    return r, -i

# ============================================================================
# Bit-reversal
# ============================================================================

def bit_rev(x: int, logn: int) -> int:
    """Bit-reverse x over logn bits."""
    r = 0
    for i in range(logn):
        if x & (1 << i):
            r |= (1 << (logn - 1 - i))
    return r

# ============================================================================
# GM twiddle table
#
# Falcon defines w = exp(i*pi/N) as a primitive 2N-th root of unity.
# GM[k] = w^(rev(k)) for k = 0..N-1.
#
# The C reference stores GM as: const fpr fpr_gm_tab[2*N] where
# entries 2*k and 2*k+1 hold the real and imaginary parts of GM[k].
# ============================================================================

def generate_gm_table(logn: int) -> List[Tuple[float, float]]:
    """
    Generate Falcon GM twiddle table from first principles.

    w = exp(i*pi/N) is a primitive 2N-th root of unity.
    GM[k] = w^(rev(k)) for k = 0..N-1.

    Returns list of N (re, im) pairs.
    """
    n = 1 << logn
    w = cmath.exp(1j * math.pi / n)
    gm = []
    for k in range(n):
        rk = bit_rev(k, logn)
        wk = w ** rk
        gm.append((wk.real, wk.imag))
    return gm


def load_gm_table(re_path: str, im_path: str) -> List[Tuple[float, float]]:
    """Load GM table from Falcon-generated hex files (one f64 per line)."""
    gm = []
    with open(re_path, 'r') as fr, open(im_path, 'r') as fi:
        for lr, li in zip(fr, fi):
            gm.append((hex_to_f64(lr), hex_to_f64(li)))
    return gm


def save_gm_table_hex(gm: List[Tuple[float, float]],
                      re_path: str, im_path: str):
    """Save GM table as hex files (one f64 hex per line)."""
    with open(re_path, 'w') as fr, open(im_path, 'w') as fi:
        for re, im in gm:
            fr.write(f64_to_hex(re) + '\n')
            fi.write(f64_to_hex(im) + '\n')


# ============================================================================
# Falcon FFT / iFFT  (exact match to C reference fft.c)
# ============================================================================

def falcon_fft(f: List[float], logn: int,
               gm: List[Tuple[float, float]]) -> List[List[float]]:
    """
    Forward FFT -- exact match to Falcon Zf(FFT) in fft.c.

    f layout: f[0..hn-1] = real parts, f[hn..n-1] = imag parts,
    stored in bit-reversed order.

    Algorithm (CT butterfly):
      t = N/2
      for stage u=1..logn-1, m=2,4,8,...,N/2:
          ht = t/2, hm = m/2
          for i1 in 0..hm-1:
              s = GM[m + i1]
              for j in j1..j1+ht-1  (where j1 = i1 * t):
                  x = f[j] + i*f[j+hn]
                  y = s * (f[j+ht] + i*f[j+ht+hn])
                  f[j]     = Re(x + y),  f[j+hn]  = Im(x + y)
                  f[j+ht]  = Re(x - y),  f[j+ht+hn] = Im(x - y)
          t = ht

    Returns: list of f snapshots, one per stage (logn-1 stages).
    """
    n = 1 << logn
    hn = n >> 1
    f = list(f)  # defensive copy
    stage_outputs = []

    t = hn
    u = 1
    m = 2

    while u < logn:
        ht = t >> 1
        hm = m >> 1

        for i1 in range(hm):
            j1 = i1 * t
            j2 = j1 + ht
            s_re, s_im = gm[m + i1]

            for j in range(j1, j2):
                x_re, x_im = f[j], f[j + hn]
                y_re, y_im = f[j + ht], f[j + ht + hn]
                # y = s * y
                y_re, y_im = cmul(y_re, y_im, s_re, s_im)
                # x + y
                f[j],     f[j + hn]      = cadd(x_re, x_im, y_re, y_im)
                # x - y
                f[j + ht], f[j + ht + hn] = csub(x_re, x_im, y_re, y_im)

        stage_outputs.append(list(f))
        t = ht
        u += 1
        m <<= 1

    return stage_outputs


def falcon_ifft(f: List[float], logn: int,
                gm: List[Tuple[float, float]]) -> List[List[float]]:
    """
    Inverse FFT -- exact match to Falcon Zf(iFFT) in fft.c.

    Algorithm (GS butterfly with CONJ(twiddle)):
      t = 1, m = N
      for u = logn..2:
          hm = m/2, dt = t*2
          for i1 in 0..hm-1:
              s = CONJ(GM[hm + i1])   <-- KEY: conjugate!
              for j in j1..j1+t-1  (where j1 = i1 * dt):
                  x = f[j] + i*f[j+hn]
                  y = f[j+t] + i*f[j+t+hn]
                  f[j]     = Re(x + y)
                  f[j+hn]  = Im(x + y)
                  diff = x - y
                  f[j+t]     = Re(s * diff)
                  f[j+t+hn]  = Im(s * diff)
          t = dt, m = hm

      Final: multiply all values by 2/N.

    IMPORTANT RTL IMPLICATION:
      The RTL GS butterfly does y1 = w * (a-b), NOT conj(w)*(a-b).
      For iFFT, the twiddle input to the RTL MUST be pre-conjugated.
      This golden model handles the conjugation internally (matching
      the C reference), so the output w_re/w_im in the golden vectors
      is the CONJUGATED value that should be fed to the RTL.
    """
    n = 1 << logn
    hn = n >> 1
    f = list(f)
    stage_outputs = []

    t = 1
    m = n

    for u in range(logn, 1, -1):
        hm = m >> 1
        dt = t << 1

        # Falcon C reference loop:
        #   for (i1 = 0, j1 = 0; j1 < hn; i1++, j1 += dt)
        # NOT "i1 < hm" -- the bound is j1 < hn.
        j1 = 0
        i1 = 0
        while j1 < hn:
            j2 = j1 + t
            # Falcon C reference: s = conj(GM[hm+i1])
            s_re, s_im = gm[hm + i1]
            s_im = -s_im   # <-- conjugate

            for j in range(j1, j2):
                x_re, x_im = f[j], f[j + hn]
                y_re, y_im = f[j + t], f[j + t + hn]

                # y0 = x + y
                f[j], f[j + hn] = cadd(x_re, x_im, y_re, y_im)

                # y1 = s * (x - y)   where s is conj(GM)
                diff_re, diff_im = csub(x_re, x_im, y_re, y_im)
                f[j + t], f[j + t + hn] = cmul(diff_re, diff_im, s_re, s_im)

            j1 += dt
            i1 += 1

        stage_outputs.append(list(f))
        t = dt
        m = hm

    # Final scale: multiply by 2/N  (Falcon divides by N/2)
    if logn > 0:
        scale = 2.0 / n
        for i in range(n):
            f[i] *= scale

    return stage_outputs


# ============================================================================
# Polynomial <-> FFT representation conversion
#
# Falcon stores a real polynomial f(x) = sum_{i=0}^{N-1} c_i x^i as an
# FFT representation where:
#   Re(F(w_j)) -> slot rev(j)/2
#   Im(F(w_j)) -> slot rev(j)/2 + N/2
# for j = 0..N/2-1.
# ============================================================================

def poly_to_fft(coeffs: List[float], logn: int) -> List[float]:
    """
    Convert a real polynomial (N coefficients c_0..c_{N-1}) to Falcon
    FFT representation format.

    Mapping (from Falcon spec / inner.h):
      For j in 0..N/2-1:
        f[rev(j) >> 1]        = c_{2*j}      (even coeff -> real part)
        f[(rev(j) >> 1) + N/2] = c_{2*j+1}   (odd coeff -> imag part)
    """
    n = 1 << logn
    hn = n >> 1
    f = [0.0] * n

    for j in range(hn):
        rj = bit_rev(j, logn)
        slot = rj >> 1
        f[slot] = coeffs[2 * j]
        f[slot + hn] = coeffs[2 * j + 1]

    return f


def fft_to_poly(f: List[float], logn: int) -> List[float]:
    """Reverse of poly_to_fft: extract polynomial coefficients from FFT array."""
    n = 1 << logn
    hn = n >> 1
    coeffs = [0.0] * n

    for j in range(hn):
        rj = bit_rev(j, logn)
        slot = rj >> 1
        coeffs[2 * j] = f[slot]
        coeffs[2 * j + 1] = f[slot + hn]

    return coeffs


# ============================================================================
# RTL Butterfly Operators
#
# These match the Verilog implementation in reconfig_fe_f64.v exactly:
#   CT (mode=0): y0 = a + b*w,   y1 = a - b*w
#   GS (mode=1): y0 = a + b,     y1 = (a-b) * w
# ============================================================================

def rtl_ct_butterfly(a_re, a_im, b_re, b_im, w_re, w_im):
    """
    RTL CT butterfly (FE_MODE_CT_BFU_COMPLEX = 4'd0):
      bw = b * w     (complex multiply)
      y0 = a + bw
      y1 = a - bw

    Returns ((y0_re, y0_im), (y1_re, y1_im)).
    """
    bw_re, bw_im = cmul(b_re, b_im, w_re, w_im)
    y0_re, y0_im = cadd(a_re, a_im, bw_re, bw_im)
    y1_re, y1_im = csub(a_re, a_im, bw_re, bw_im)
    return (y0_re, y0_im), (y1_re, y1_im)


def rtl_gs_butterfly(a_re, a_im, b_re, b_im, w_re, w_im):
    """
    RTL GS butterfly (FE_MODE_GS_BFU_COMPLEX = 4'd1):
      y0 = a + b
      diff = a - b
      y1 = diff * w    (complex multiply)

    Returns ((y0_re, y0_im), (y1_re, y1_im)).

    !! IMPORTANT for iFFT:
    Falcon C reference does y1 = CONJ(GM) * (a-b).
    The RTL has no built-in conj. When using RTL GS mode for iFFT,
    the twiddle input MUST be pre-conjugated:
        w_re' =  gm_re
        w_im' = -gm_im
    The golden vectors output by extract_ifft_stage_vectors() already
    have the conjugated twiddle.
    """
    y0_re, y0_im = cadd(a_re, a_im, b_re, b_im)
    diff_re, diff_im = csub(a_re, a_im, b_re, b_im)
    y1_re, y1_im = cmul(diff_re, diff_im, w_re, w_im)
    return (y0_re, y0_im), (y1_re, y1_im)


# ============================================================================
# Butterfly vector data class
# ============================================================================

class ButterflyVector:
    """One butterfly operation: a, b, w -> y0, y1  (all f64 complex)."""
    __slots__ = ('stage', 'batch', 'lane', 'pair_idx',
                 'a_re', 'a_im', 'b_re', 'b_im', 'w_re', 'w_im',
                 'y0_re', 'y0_im', 'y1_re', 'y1_im')

    def __init__(self, stage, batch, lane, pair_idx,
                 a_re, a_im, b_re, b_im, w_re, w_im,
                 y0_re, y0_im, y1_re, y1_im):
        self.stage = stage
        self.batch = batch
        self.lane = lane
        self.pair_idx = pair_idx
        self.a_re = a_re;   self.a_im = a_im
        self.b_re = b_re;   self.b_im = b_im
        self.w_re = w_re;   self.w_im = w_im
        self.y0_re = y0_re; self.y0_im = y0_im
        self.y1_re = y1_re; self.y1_im = y1_im


# ============================================================================
# Stage vector extraction
# ============================================================================

def extract_fft_stage_vectors(
    f_before: List[float],
    logn: int,
    gm: List[Tuple[float, float]],
    stage_idx: int,
    lanes: int = 5
) -> List[ButterflyVector]:
    """
    Extract all butterfly pairs for one FFT stage.

    Follows Falcon fft.c indexing exactly.
    stage_idx is 0-indexed (0..logn-2).

    Returns list of ButterflyVector, grouped by (batch, lane).
    """
    n = 1 << logn
    hn = n >> 1

    # Compute (t, m, ht, hm) for this FFT stage.
    t_cur = hn
    m_cur = 2
    found = False
    for u in range(1, logn):
        ht_cur = t_cur >> 1
        hm_cur = m_cur >> 1
        if u - 1 == stage_idx:
            t, m, ht, hm = t_cur, m_cur, ht_cur, hm_cur
            found = True
            break
        t_cur = ht_cur
        m_cur <<= 1

    if not found:
        raise ValueError(f"FFT stage {stage_idx} out of range [0, {logn-2}]")

    vectors = []
    pair_idx = 0

    for i1 in range(hm):
        j1 = i1 * t
        j2 = j1 + ht
        s_re, s_im = gm[m + i1]

        for j in range(j1, j2):
            lane = pair_idx % lanes
            batch = pair_idx // lanes

            a_re, a_im = f_before[j],      f_before[j + hn]
            b_re, b_im = f_before[j + ht], f_before[j + ht + hn]
            w_re, w_im = s_re, s_im

            (y0_re, y0_im), (y1_re, y1_im) = rtl_ct_butterfly(
                a_re, a_im, b_re, b_im, w_re, w_im)

            vectors.append(ButterflyVector(
                stage_idx, batch, lane, pair_idx,
                a_re, a_im, b_re, b_im, w_re, w_im,
                y0_re, y0_im, y1_re, y1_im))
            pair_idx += 1

    return vectors


def extract_ifft_stage_vectors(
    f_before: List[float],
    logn: int,
    gm: List[Tuple[float, float]],
    stage_idx: int,
    lanes: int = 5
) -> List[ButterflyVector]:
    """
    Extract all butterfly pairs for one IFFT stage.

    Follows Falcon fft.c iFFT indexing exactly.
    stage_idx is 0-indexed (0..logn-2, where stage 0 = outer loop u=logn).

    The twiddle is CONJ(GM[hm+i1]), matching the C reference.
    The output w_re/w_im is the CONJUGATED value that should be fed
    to the RTL GS butterfly.
    """
    n = 1 << logn
    hn = n >> 1

    # Compute (t_cur, m_cur, hm_cur) for the current stage.
    t_cur = 1
    m_cur = n
    found = False
    stage_count = 0
    for u in range(logn, 1, -1):
        hm_cur = m_cur >> 1
        dt_cur = t_cur << 1
        if stage_count == stage_idx:
            dt, hm, t_small = dt_cur, hm_cur, t_cur
            found = True
            break
        t_cur = dt_cur
        m_cur = hm_cur
        stage_count += 1

    if not found:
        raise ValueError(f"IFFT stage {stage_idx} out of range [0, {logn-2}]")

    vectors = []
    pair_idx = 0

    # Falcon C reference loop:
    #   for (i1 = 0, j1 = 0; j1 < hn; i1++, j1 += dt)
    # NOT "i1 < hm".
    j1 = 0
    i1 = 0
    while j1 < hn:
        j2 = j1 + t_small
        # Falcon iFFT uses CONJ(GM)
        s_re, s_im = gm[hm + i1]
        s_im = -s_im  # conjugate

        for j in range(j1, j2):
            lane = pair_idx % lanes
            batch = pair_idx // lanes

            a_re, a_im = f_before[j],              f_before[j + hn]
            b_re, b_im = f_before[j + t_small],    f_before[j + t_small + hn]
            w_re, w_im = s_re, s_im

            (y0_re, y0_im), (y1_re, y1_im) = rtl_gs_butterfly(
                a_re, a_im, b_re, b_im, w_re, w_im)

            vectors.append(ButterflyVector(
                stage_idx, batch, lane, pair_idx,
                a_re, a_im, b_re, b_im, w_re, w_im,
                y0_re, y0_im, y1_re, y1_im))
            pair_idx += 1

        j1 += dt
        i1 += 1

    return vectors


# ============================================================================
# Test input generators
# ============================================================================

def make_test_input_impulse(logn: int) -> List[float]:
    """Impulse-like input with non-trivial structure."""
    n = 1 << logn
    hn = n >> 1
    f = [0.0] * n
    f[0] = 1.0
    if hn > 1:
        f[1] = 0.5
    if hn > 2:
        f[hn] = 0.25
    return f


def make_test_input_ramp(logn: int) -> List[float]:
    """Ramp: f[j] = j/100, f[j+hn] = (j+1)/200."""
    n = 1 << logn
    hn = n >> 1
    f = [0.0] * n
    for j in range(hn):
        f[j] = j / 100.0
        f[j + hn] = (j + 1) / 200.0
    return f


def make_test_input_random(logn: int, seed: int = 42) -> List[float]:
    """Random values in [-1, 1]."""
    n = 1 << logn
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def make_test_input_falcon_poly(logn: int) -> List[float]:
    """
    Generate FFT-format input from synthetic polynomial coefficients.
    Mimics Falcon key coefficients (small integers in [-12, 12]).
    """
    n = 1 << logn
    rng = random.Random(12345)
    coeffs = [float(rng.randint(-12, 12)) for _ in range(n)]
    return poly_to_fft(coeffs, logn)


# ============================================================================
# Output formatters
# ============================================================================

def format_320bit_complex(re_vals: List[float], im_vals: List[float],
                          lanes: int = 5) -> Tuple[str, str]:
    """
    Return (re_hex_320, im_hex_320) strings.

    Each string is lanes*16 hex chars (lanes x 64-bit f64),
    MSB-first lane ordering (lane[lanes-1] at the left).
    """
    re_parts = []
    im_parts = []
    for i in range(lanes - 1, -1, -1):
        if i < len(re_vals):
            re_parts.append(f64_to_hex(re_vals[i]))
            im_parts.append(f64_to_hex(im_vals[i]))
        else:
            re_parts.append('0' * 16)
            im_parts.append('0' * 16)
    return ''.join(re_parts), ''.join(im_parts)


def format_fft_array(f: List[float], logn: int) -> str:
    """Format full FFT array as hex for human inspection."""
    n = 1 << logn
    hn = n >> 1
    lines = []
    for j in range(hn):
        re = f64_bits(f[j])
        im = f64_bits(f[j + hn])
        lines.append(f"  [{j:4d}] re=0x{re:016x}  im=0x{im:016x}")
    return '\n'.join(lines)


# ============================================================================
# Main golden generation
# ============================================================================

def run_golden_generation(logn: int, mode: str, gm: List[Tuple[float, float]],
                          outdir: str, lanes: int = 5,
                          test_inputs: Optional[List[float]] = None):
    """
    Generate golden vectors for FFT and/or IFFT.

    Args:
        logn: log2(N), 9 for Falcon-512, 10 for Falcon-1024.
        mode: 'fft', 'ifft', or 'both'.
        gm: GM twiddle table.
        outdir: output directory for golden files.
        lanes: RTL lane count (5 for SPUV3).
        test_inputs: optional custom input array (FFT-format).
    """
    n = 1 << logn
    hn = n >> 1
    n_stages = logn - 1  # first iteration is a no-op in Falcon FFT

    os.makedirs(outdir, exist_ok=True)

    if test_inputs is None:
        test_inputs = make_test_input_random(logn, seed=0xFE64)

    # Save input array
    with open(os.path.join(outdir, 'fft_input.txt'), 'w') as fh:
        fh.write(format_fft_array(test_inputs, logn))
        fh.write('\n')

    results = {}

    directions = []
    if mode in ('fft', 'both'):
        directions.append(('fft', False))
    if mode in ('ifft', 'both'):
        directions.append(('ifft', True))

    for direction, inverse in directions:
        label = 'IFFT' if inverse else 'FFT'

        print(f"\n{'='*60}")
        print(f"  {label} -- logN={logn}, N={n}, stages={n_stages}, lanes={lanes}")
        print(f"{'='*60}")

        # Run full FFT/IFFT, capturing stage snapshots
        f_work = list(test_inputs)
        if inverse:
            stage_snapshots = falcon_ifft(f_work, logn, gm)
        else:
            stage_snapshots = falcon_fft(f_work, logn, gm)

        # falcon_fft()/falcon_ifft() defensively copy their input and return
        # per-stage snapshots.  The last snapshot is the true final array.
        if stage_snapshots:
            f_final = stage_snapshots[-1]
        else:
            f_final = list(test_inputs)

        # stage_snapshots[s] = f AFTER stage s
        # f_before[0] = test_inputs
        # f_after[0]  = stage_snapshots[0]

        stage_dir = os.path.join(outdir, f'{direction}_stages')
        os.makedirs(stage_dir, exist_ok=True)

        total_pairs = 0
        all_vectors = []

        for s in range(n_stages):
            f_before = test_inputs if s == 0 else stage_snapshots[s - 1]

            if inverse:
                vecs = extract_ifft_stage_vectors(
                    f_before, logn, gm, s, lanes=lanes)
            else:
                vecs = extract_fft_stage_vectors(
                    f_before, logn, gm, s, lanes=lanes)

            total_pairs += len(vecs)
            all_vectors.extend(vecs)

            max_batch = max(v.batch for v in vecs) if vecs else 0

            # Write human-readable stage summary
            sum_path = os.path.join(stage_dir, f'stage_{s:02d}_summary.txt')
            with open(sum_path, 'w') as fh:
                fh.write(f"# Stage {s} -- {label}  ({len(vecs)} pairs, "
                         f"{max_batch + 1} batches)\n")
                if not inverse:
                    fh.write(f"# FFT: m={2<<s}, t={hn>>(s+1)}\n\n")
                else:
                    fh.write(f"# IFFT: stage u=logn-{s}..logn-{s+1}, "
                             f"t={1<<s}, dt={1<<(s+1)}\n\n")

                # Column header
                header = (f"{'pair':>5} {'bat':>4} {'ln':>3}  "
                          f"{'a_re':>18} {'a_im':>18}  "
                          f"{'b_re':>18} {'b_im':>18}  "
                          f"{'w_re':>18} {'w_im':>18}  "
                          f"{'y0_re':>18} {'y0_im':>18}  "
                          f"{'y1_re':>18} {'y1_im':>18}")
                fh.write(header + '\n')
                fh.write('-' * len(header) + '\n')

                for v in vecs:
                    fh.write(
                        f"{v.pair_idx:5d} {v.batch:4d} {v.lane:3d}  "
                        f"0x{f64_bits(v.a_re):016x} 0x{f64_bits(v.a_im):016x}  "
                        f"0x{f64_bits(v.b_re):016x} 0x{f64_bits(v.b_im):016x}  "
                        f"0x{f64_bits(v.w_re):016x} 0x{f64_bits(v.w_im):016x}  "
                        f"0x{f64_bits(v.y0_re):016x} 0x{f64_bits(v.y0_im):016x}  "
                        f"0x{f64_bits(v.y1_re):016x} 0x{f64_bits(v.y1_im):016x}\n"
                    )

            # Write per-batch RTL-ready hex files
            for b in range(max_batch + 1):
                bvecs = [v for v in vecs if v.batch == b]
                bpath = os.path.join(stage_dir,
                                     f'stage_{s:02d}_batch_{b:03d}.hex')
                with open(bpath, 'w') as fh:
                    fh.write(f"# Stage {s} Batch {b} -- {label}\n")
                    fh.write(f"# lanes: {len(bvecs)} active in this batch\n\n")

                    # Fill lane arrays
                    a_re_v = [0.0] * lanes
                    a_im_v = [0.0] * lanes
                    b_re_v = [0.0] * lanes
                    b_im_v = [0.0] * lanes
                    w_re_v = [0.0] * lanes
                    w_im_v = [0.0] * lanes
                    y0_re_v = [0.0] * lanes
                    y0_im_v = [0.0] * lanes
                    y1_re_v = [0.0] * lanes
                    y1_im_v = [0.0] * lanes

                    for v in bvecs:
                        a_re_v[v.lane]  = v.a_re
                        a_im_v[v.lane]  = v.a_im
                        b_re_v[v.lane]  = v.b_re
                        b_im_v[v.lane]  = v.b_im
                        w_re_v[v.lane]  = v.w_re
                        w_im_v[v.lane]  = v.w_im
                        y0_re_v[v.lane] = v.y0_re
                        y0_im_v[v.lane] = v.y0_im
                        y1_re_v[v.lane] = v.y1_re
                        y1_im_v[v.lane] = v.y1_im

                    # RTL 320-bit format: one line = 5 x 64-bit hex
                    a_re_hex, a_im_hex = format_320bit_complex(a_re_v, a_im_v, lanes)
                    b_re_hex, b_im_hex = format_320bit_complex(b_re_v, b_im_v, lanes)
                    w_re_hex, w_im_hex = format_320bit_complex(w_re_v, w_im_v, lanes)
                    y0_re_hex, y0_im_hex = format_320bit_complex(y0_re_v, y0_im_v, lanes)
                    y1_re_hex, y1_im_hex = format_320bit_complex(y1_re_v, y1_im_v, lanes)

                    fh.write("# va_re           va_im           vb_re           vb_im           tw_re           tw_im\n")
                    fh.write(f"{a_re_hex} {a_im_hex} {b_re_hex} {b_im_hex} {w_re_hex} {w_im_hex}\n\n")
                    fh.write("# y0_re           y0_im           y1_re           y1_im\n")
                    fh.write(f"{y0_re_hex} {y0_im_hex} {y1_re_hex} {y1_im_hex}\n")

            print(f"  Stage {s:2d}: {len(vecs):4d} pairs, "
                  f"{max_batch + 1:3d} batches  OK")

        # Save final output
        final_path = os.path.join(outdir, f'{direction}_final.txt')
        with open(final_path, 'w') as fh:
            fh.write(f"# {label} Final Output -- {n} values\n")
            fh.write(f"# Layout: f[0..{hn-1}] = real, f[{hn}..{n-1}] = imag\n\n")
            fh.write(format_fft_array(f_final, logn))
            fh.write('\n')

        results[direction] = {
            'n_stages': n_stages,
            'total_pairs': total_pairs,
            'final': list(f_final),
            'vectors': all_vectors,
        }

        print(f"\n  Total: {total_pairs} butterfly pairs across {n_stages} stages")
        print(f"  Final output: {final_path}")

    # Cross-check: FFT then IFFT should recover original
    if mode == 'both':
        fft_final = results['fft']['final']
        ifft_test = list(fft_final)
        falcon_ifft(ifft_test, logn, gm)

        max_err = 0.0
        for i in range(n):
            err = abs(ifft_test[i] - test_inputs[i])
            if err > max_err:
                max_err = err

        print(f"\n  Round-trip check (FFT->IFFT): max |error| = {max_err:.2e}")
        if max_err < 1e-12:
            print(f"  [PASS] Round-trip passes (error < 1e-12)")
        else:
            print(f"  [WARN] Round-trip error may be significant")

    return results


# ============================================================================
# RTL verification helper
# ============================================================================

def check_rtl_butterfly(a_re, a_im, b_re, b_im, w_re, w_im,
                         y0_re, y0_im, y1_re, y1_im,
                         inverse: bool, tol: float = 1e-15):
    """
    Verify one RTL butterfly output against Python golden.
    Returns (pass, err_y0, err_y1, golden_tuple).
    """
    if inverse:
        (gy0_re, gy0_im), (gy1_re, gy1_im) = rtl_gs_butterfly(
            a_re, a_im, b_re, b_im, w_re, w_im)
    else:
        (gy0_re, gy0_im), (gy1_re, gy1_im) = rtl_ct_butterfly(
            a_re, a_im, b_re, b_im, w_re, w_im)

    def rel_err(a, b):
        return abs(a - b) / max(1.0, abs(a), abs(b))

    e_y0 = max(rel_err(y0_re, gy0_re), rel_err(y0_im, gy0_im))
    e_y1 = max(rel_err(y1_re, gy1_re), rel_err(y1_im, gy1_im))

    ok = e_y0 < tol and e_y1 < tol
    return ok, e_y0, e_y1, (gy0_re, gy0_im, gy1_re, gy1_im)


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='Falcon FFT/IFFT Golden Model Generator for RTL Verification')
    parser.add_argument('--logn', type=int, default=9,
                        help='log2(N): 9=Falcon-512, 10=Falcon-1024 (default: 9)')
    parser.add_argument('--mode', choices=['fft', 'ifft', 'both'], default='both',
                        help='Which transform to generate (default: both)')
    parser.add_argument('--outdir', type=str, default='./golden_vecs',
                        help='Output directory (default: ./golden_vecs)')
    parser.add_argument('--lanes', type=int, default=5,
                        help='RTL FE lane count (default: 5 for SPUV3)')
    parser.add_argument('--gm-re', type=str, default=None,
                        help='External GM real-part hex file')
    parser.add_argument('--gm-im', type=str, default=None,
                        help='External GM imag-part hex file')
    parser.add_argument('--seed', type=int, default=0xFE64,
                        help='Random seed for test input (default: 0xFE64)')
    parser.add_argument('--input-type',
                        choices=['random', 'impulse', 'ramp', 'falcon_poly'],
                        default='random', help='Test input type')
    parser.add_argument('--save-gm', action='store_true',
                        help='Save generated GM table as hex files')
    args = parser.parse_args()

    n = 1 << args.logn

    # Load or generate GM table
    if args.gm_re and args.gm_im:
        print(f"Loading GM table from {args.gm_re}, {args.gm_im}")
        gm = load_gm_table(args.gm_re, args.gm_im)
        print(f"  Loaded {len(gm)} entries")
    else:
        print(f"Generating GM table for logN={args.logn} (N={n})")
        gm = generate_gm_table(args.logn)
        print(f"  Generated {len(gm)} entries")

    if args.save_gm:
        save_gm_table_hex(gm, 'gm_rom_re.hex', 'gm_rom_im.hex')
        print("  Saved gm_rom_re.hex, gm_rom_im.hex")

    # Generate test input
    input_map = {
        'random':      lambda: make_test_input_random(args.logn, args.seed),
        'impulse':     lambda: make_test_input_impulse(args.logn),
        'ramp':        lambda: make_test_input_ramp(args.logn),
        'falcon_poly': lambda: make_test_input_falcon_poly(args.logn),
    }
    test_input = input_map[args.input_type]()

    print(f"Test input: {args.input_type}, seed={args.seed}")
    print(f"Output directory: {args.outdir}")

    results = run_golden_generation(
        args.logn, args.mode, gm, args.outdir,
        lanes=args.lanes, test_inputs=test_input)

    print(f"\n{'='*60}")
    print("  Golden generation complete.")
    print(f"  Output: {args.outdir}/")
    for d in (['fft'] if args.mode in ('fft', 'both') else []) + \
             (['ifft'] if args.mode in ('ifft', 'both') else []):
        print(f"    {d}_stages/  -- per-stage golden vectors")
        print(f"    {d}_final.txt -- final FFT array")
    print(f"    fft_input.txt -- test input array")
    print(f"{'='*60}")


if __name__ == '__main__':
    main()
