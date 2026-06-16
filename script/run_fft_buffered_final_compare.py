#!/usr/bin/env python3
"""
End-to-end final-array comparison for falcon_fft_buffered_engine.

The script converts golden_vecs/*_input.txt and *_final.txt into a temporary
Verilog testbench, preloads the local buffer through ext_* writes, runs the
buffered engine, and compares every f[] scalar in the final bank.
"""

import argparse
import os
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LINE_RE = re.compile(r"\[\s*(\d+)\]\s+re=0x([0-9a-fA-F]{16})\s+im=0x([0-9a-fA-F]{16})")


def parse_fft_array(path: Path, logn: int):
    n = 1 << logn
    hn = n >> 1
    values = [None] * n
    for line in path.read_text(encoding="utf-8").splitlines():
        m = LINE_RE.search(line)
        if not m:
            continue
        idx = int(m.group(1))
        if idx >= hn:
            raise ValueError(f"unexpected index {idx} in {path}")
        values[idx] = m.group(2).lower()
        values[idx + hn] = m.group(3).lower()
    missing = [i for i, v in enumerate(values) if v is None]
    if missing:
        raise ValueError(f"missing {len(missing)} values in {path}: first={missing[:5]}")
    return values


def golden_dir(logn: int):
    return ROOT / ("golden_vecs_1024" if logn == 10 else "golden_vecs")


def emit_verilog(logn: int, mode: str, backend: int, max_ulp: int, max_abs: float,
                 input_values, expected_values, out_path: Path):
    n = 1 << logn
    max_cycles = 200000 if backend == 0 else 100000
    inverse = 1 if mode == "ifft" else 0

    lines = []
    lines.append("`timescale 1ns/1ps")
    lines.append("")
    lines.append("module tb_falcon_fft_buffered_final_compare_auto;")
    lines.append(f"    localparam N = {n};")
    lines.append(f"    localparam LOGN = {logn};")
    lines.append(f"    localparam BACKEND = {backend};")
    lines.append(f"    localparam MAX_CYCLES = {max_cycles};")
    lines.append(f"    localparam [63:0] MAX_ULP = 64'd{max_ulp};")
    lines.append(f"    real MAX_ABS;")
    lines.append("    localparam [63:0] F64_ZERO = 64'h0000_0000_0000_0000;")
    lines.append("    localparam [63:0] F64_NEG_ZERO = 64'h8000_0000_0000_0000;")
    lines.append("    reg clk, rst_n, start, inverse;")
    lines.append("    reg [3:0] logn;")
    lines.append("    reg ext_we, ext_bank;")
    lines.append("    reg [9:0] ext_addr;")
    lines.append("    reg [63:0] ext_re_i, ext_im_i;")
    lines.append("    wire [63:0] ext_re_o, ext_im_o;")
    lines.append("    wire busy, done, final_bank;")
    lines.append("    wire status_invalid, status_overflow, status_underflow, status_inexact;")
    lines.append("    reg [63:0] input_mem [0:N-1];")
    lines.append("    reg [63:0] exp_mem [0:N-1];")
    lines.append("    integer i, cycles, errors;")
    lines.append("    reg [63:0] delta;")
    lines.append("    reg [63:0] max_delta;")
    lines.append("    real abs_err;")
    lines.append("    real max_abs_err;")
    lines.append("")
    lines.append("    falcon_fft_buffered_engine #(")
    lines.append("        .N(1024),")
    lines.append("        .BACKEND(BACKEND)")
    lines.append("    ) dut (")
    lines.append("        .clk(clk), .rst_n(rst_n), .start(start), .inverse(inverse), .logn(logn),")
    lines.append("        .ext_we(ext_we), .ext_bank(ext_bank), .ext_addr(ext_addr),")
    lines.append("        .ext_re_i(ext_re_i), .ext_im_i(ext_im_i),")
    lines.append("        .ext_re_o(ext_re_o), .ext_im_o(ext_im_o),")
    lines.append("        .busy(busy), .done(done), .final_bank_o(final_bank),")
    lines.append("        .status_invalid(status_invalid), .status_overflow(status_overflow),")
    lines.append("        .status_underflow(status_underflow), .status_inexact(status_inexact)")
    lines.append("    );")
    lines.append("")
    lines.append("    always #5 clk = ~clk;")
    lines.append("")
    lines.append("    function words_equal;")
    lines.append("        input [63:0] got;")
    lines.append("        input [63:0] exp;")
    lines.append("        begin")
    lines.append("            words_equal = (got == exp) ||")
    lines.append("                (got == F64_ZERO && exp == F64_NEG_ZERO) ||")
    lines.append("                (got == F64_NEG_ZERO && exp == F64_ZERO);")
    lines.append("        end")
    lines.append("    endfunction")
    lines.append("")
    lines.append("    function [63:0] ordered_bits;")
    lines.append("        input [63:0] bits;")
    lines.append("        begin")
    lines.append("            ordered_bits = bits[63] ? ~bits : (bits ^ 64'h8000_0000_0000_0000);")
    lines.append("        end")
    lines.append("    endfunction")
    lines.append("")
    lines.append("    function [63:0] ulp_delta;")
    lines.append("        input [63:0] a;")
    lines.append("        input [63:0] b;")
    lines.append("        reg [63:0] oa;")
    lines.append("        reg [63:0] ob;")
    lines.append("        begin")
    lines.append("            oa = ordered_bits(a);")
    lines.append("            ob = ordered_bits(b);")
    lines.append("            ulp_delta = (oa >= ob) ? (oa - ob) : (ob - oa);")
    lines.append("        end")
    lines.append("    endfunction")
    lines.append("")
    lines.append("    function real abs_real;")
    lines.append("        input real v;")
    lines.append("        begin")
    lines.append("            abs_real = (v < 0.0) ? -v : v;")
    lines.append("        end")
    lines.append("    endfunction")
    lines.append("")
    lines.append("    initial begin")
    for i, v in enumerate(input_values):
        lines.append(f"        input_mem[{i}] = 64'h{v};")
    for i, v in enumerate(expected_values):
        lines.append(f"        exp_mem[{i}] = 64'h{v};")
    lines.append("    end")
    lines.append("")
    lines.append("    initial begin")
    lines.append("        clk = 1'b0; rst_n = 1'b0; start = 1'b0;")
    lines.append(f"        inverse = 1'b{inverse}; logn = LOGN[3:0];")
    lines.append("        ext_we = 1'b0; ext_bank = 1'b0; ext_addr = 10'd0;")
    lines.append("        ext_re_i = 64'd0; ext_im_i = 64'd0;")
    lines.append(f"        MAX_ABS = {max_abs:.17e};")
    lines.append("        cycles = 0; errors = 0; max_delta = 64'd0; max_abs_err = 0.0;")
    lines.append("        repeat (3) @(negedge clk); rst_n = 1'b1;")
    lines.append("")
    lines.append("        for (i = 0; i < N; i = i + 1) begin")
    lines.append("            @(negedge clk);")
    lines.append("            ext_we = 1'b1; ext_bank = 1'b0; ext_addr = i[9:0];")
    lines.append("            ext_re_i = input_mem[i]; ext_im_i = 64'd0;")
    lines.append("        end")
    lines.append("        @(negedge clk); ext_we = 1'b0;")
    lines.append("")
    lines.append("        start = 1'b1;")
    lines.append("        @(negedge clk); start = 1'b0;")
    lines.append("        while (!done && cycles < MAX_CYCLES) begin")
    lines.append("            @(posedge clk); cycles = cycles + 1;")
    lines.append("        end")
    lines.append("        if (!done) begin")
    lines.append("            $display(\"TB_FAIL timeout waiting final compare done\");")
    lines.append("            errors = errors + 1;")
    lines.append("        end")
    lines.append("        if (status_invalid || status_overflow) begin")
    lines.append("            $display(\"TB_FAIL status invalid=%0d overflow=%0d\", status_invalid, status_overflow);")
    lines.append("            errors = errors + 1;")
    lines.append("        end")
    lines.append("")
    lines.append("        ext_bank = final_bank; ext_we = 1'b0;")
    lines.append("        for (i = 0; i < N; i = i + 1) begin")
    lines.append("            ext_addr = i[9:0]; #1;")
    lines.append("            delta = ulp_delta(ext_re_o, exp_mem[i]);")
    lines.append("            if (delta > max_delta) max_delta = delta;")
    lines.append("            abs_err = abs_real($bitstoreal(ext_re_o) - $bitstoreal(exp_mem[i]));")
    lines.append("            if (abs_err > max_abs_err) max_abs_err = abs_err;")
    lines.append("            if (!(words_equal(ext_re_o, exp_mem[i]) || delta <= MAX_ULP || abs_err <= MAX_ABS)) begin")
    lines.append("                if (errors < 20) begin")
    lines.append("                    $display(\"TB_FAIL idx=%0d got=%h exp=%h ulp=%0d abs=%e\", i, ext_re_o, exp_mem[i], delta, abs_err);")
    lines.append("                    if (i == 0) $display(\"TB_DEBUG final_bank=%0d bank0_0=%h bank1_0=%h\", final_bank, dut.u_local_buffer.bank0[0], dut.u_local_buffer.bank1[0]);")
    lines.append("                end")
    lines.append("                errors = errors + 1;")
    lines.append("            end")
    lines.append("        end")
    lines.append("        if (errors == 0) begin")
    lines.append("            $display(\"TB_PASS falcon_fft_buffered_final_compare N=%0d mode=%0d backend=%0d cycles=%0d max_ulp=%0d max_abs=%e\", N, inverse, BACKEND, cycles, max_delta, max_abs_err);")
    lines.append("        end else begin")
    lines.append("            $display(\"TB_FAIL final_compare errors=%0d N=%0d mode=%0d backend=%0d\", errors, N, inverse, BACKEND);")
    lines.append("        end")
    lines.append("        $finish;")
    lines.append("    end")
    lines.append("endmodule")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--logn", type=int, default=9, choices=(9, 10))
    ap.add_argument("--mode", choices=("fft", "ifft"), default="fft")
    ap.add_argument("--backend", choices=("shared", "pipe"), default="shared")
    ap.add_argument("--max-ulp", type=int, default=0)
    ap.add_argument("--max-abs", type=float, default=0.0)
    ap.add_argument("--keep-tb", action="store_true")
    args = ap.parse_args()

    gdir = golden_dir(args.logn)
    input_path = gdir / "fft_input.txt"
    final_path = gdir / f"{args.mode}_final.txt"
    if not final_path.is_file():
        raise FileNotFoundError(final_path)

    input_values = parse_fft_array(input_path, args.logn)
    expected_values = parse_fft_array(final_path, args.logn)
    backend = 0 if args.backend == "shared" else 1

    sim_dir = ROOT / "sim"
    sim_dir.mkdir(exist_ok=True)
    stem = f"tb_falcon_fft_buffered_final_logn{args.logn}_{args.mode}_{args.backend}_{os.getpid()}"
    tb_path = sim_dir / f"{stem}.v"
    out_path = sim_dir / f"{stem}.vvp"
    emit_verilog(args.logn, args.mode, backend, args.max_ulp, args.max_abs,
                 input_values, expected_values, tb_path)

    subprocess.check_call(
        ["iverilog", "-g2012", "-o", str(out_path), "-f", str(ROOT / "rtl" / "filelist.f"), str(tb_path)],
        cwd=ROOT,
    )
    subprocess.check_call(["vvp", str(out_path)], cwd=ROOT)

    if not args.keep_tb:
        for path in (tb_path, out_path):
            try:
                path.unlink()
            except OSError:
                pass


if __name__ == "__main__":
    main()
