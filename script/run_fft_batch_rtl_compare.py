#!/usr/bin/env python3
"""
Generate and run a temporary Verilog testbench that feeds Falcon FFT/IFFT
golden batch vectors into falcon_fft_batch_exu.

The golden batch files contain inactive lanes in the final partial batch.  The
RTL is allowed to preserve or ignore inactive lanes, so this checker compares
only lanes covered by the per-batch active-lane count.
"""

import argparse
import os
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def parse_batch_file(path: Path, inverse: bool):
    active = None
    data_lines = []
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.search(r"lanes:\s+(\d+)\s+active", line)
        if m:
            active = int(m.group(1))
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        data_lines.append(line.split())
    if active is None or len(data_lines) != 2:
        raise ValueError(f"bad batch file format: {path}")
    if len(data_lines[0]) != 6 or len(data_lines[1]) != 4:
        raise ValueError(f"bad vector field count: {path}")
    return {
        "name": path.as_posix(),
        "inverse": 1 if inverse else 0,
        "active": active,
        "in": data_lines[0],
        "out": data_lines[1],
    }


def collect_cases(logn: int, mode: str):
    outdir = ROOT / ("golden_vecs_1024" if logn == 10 else "golden_vecs")
    modes = []
    if mode in ("fft", "both"):
        modes.append(("fft", False))
    if mode in ("ifft", "both"):
        modes.append(("ifft", True))

    cases = []
    for subdir, inverse in modes:
        stage_dir = outdir / f"{subdir}_stages"
        if not stage_dir.is_dir():
            raise FileNotFoundError(stage_dir)
        for path in sorted(stage_dir.glob("stage_*_batch_*.hex")):
            cases.append(parse_batch_file(path, inverse))
    return cases


def emit_verilog(cases, out_path: Path, backend: int):
    n = len(cases)
    lines = []
    lines.append("`timescale 1ns/1ps")
    lines.append("")
    lines.append("module tb_falcon_fft_batch_compare_auto;")
    lines.append("    localparam LANES = 5;")
    lines.append(f"    localparam NUM_CASES = {n};")
    lines.append("    localparam [63:0] F64_ZERO = 64'h0000_0000_0000_0000;")
    lines.append("    localparam [63:0] F64_NEG_ZERO = 64'h8000_0000_0000_0000;")
    lines.append("    reg clk, rst_n, start, inverse;")
    lines.append("    reg [LANES-1:0] lane_mask;")
    lines.append("    reg [319:0] va_re, va_im, vb_re, vb_im, tw_re, tw_im;")
    lines.append("    wire busy, done;")
    lines.append("    wire [319:0] y0_re, y0_im, y1_re, y1_im;")
    lines.append("    wire status_invalid, status_overflow, status_underflow, status_inexact;")
    lines.append("    reg case_inverse [0:NUM_CASES-1];")
    lines.append("    integer case_active [0:NUM_CASES-1];")
    lines.append("    reg [319:0] in0 [0:NUM_CASES-1];")
    lines.append("    reg [319:0] in1 [0:NUM_CASES-1];")
    lines.append("    reg [319:0] in2 [0:NUM_CASES-1];")
    lines.append("    reg [319:0] in3 [0:NUM_CASES-1];")
    lines.append("    reg [319:0] in4 [0:NUM_CASES-1];")
    lines.append("    reg [319:0] in5 [0:NUM_CASES-1];")
    lines.append("    reg [319:0] exp0 [0:NUM_CASES-1];")
    lines.append("    reg [319:0] exp1 [0:NUM_CASES-1];")
    lines.append("    reg [319:0] exp2 [0:NUM_CASES-1];")
    lines.append("    reg [319:0] exp3 [0:NUM_CASES-1];")
    lines.append("    integer errors, idx, lane, waits;")
    lines.append("")
    lines.append("    falcon_fft_batch_exu #(")
    lines.append(f"        .BACKEND({backend})")
    lines.append("    ) dut (")
    lines.append("        .clk(clk), .rst_n(rst_n), .start(start), .inverse(inverse),")
    lines.append("        .lane_mask(lane_mask), .va_re_vec(va_re), .va_im_vec(va_im),")
    lines.append("        .vb_re_vec(vb_re), .vb_im_vec(vb_im), .tw_re_vec(tw_re),")
    lines.append("        .tw_im_vec(tw_im), .busy(busy), .done(done),")
    lines.append("        .y0_re_vec(y0_re), .y0_im_vec(y0_im), .y1_re_vec(y1_re),")
    lines.append("        .y1_im_vec(y1_im), .status_invalid(status_invalid),")
    lines.append("        .status_overflow(status_overflow), .status_underflow(status_underflow),")
    lines.append("        .status_inexact(status_inexact)")
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
    lines.append("    task check_lane;")
    lines.append("        input [319:0] got;")
    lines.append("        input [319:0] exp;")
    lines.append("        input integer lane_id;")
    lines.append("        input [8*16-1:0] name;")
    lines.append("        begin")
    lines.append("            if (!words_equal(got[lane_id*64 +: 64], exp[lane_id*64 +: 64])) begin")
    lines.append("                $display(\"TB_FAIL case=%0d lane=%0d %0s got=%h exp=%h\",")
    lines.append("                         idx, lane_id, name, got[lane_id*64 +: 64], exp[lane_id*64 +: 64]);")
    lines.append("                errors = errors + 1;")
    lines.append("            end")
    lines.append("        end")
    lines.append("    endtask")
    lines.append("")
    lines.append("    initial begin")
    for i, c in enumerate(cases):
        lines.append(f"        case_inverse[{i}] = 1'b{c['inverse']}; case_active[{i}] = {c['active']};")
        for k, token in enumerate(c["in"]):
            lines.append(f"        in{k}[{i}] = 320'h{token};")
        for k, token in enumerate(c["out"]):
            lines.append(f"        exp{k}[{i}] = 320'h{token};")
    lines.append("    end")
    lines.append("")
    lines.append("    initial begin")
    lines.append("        clk = 1'b0; rst_n = 1'b0; start = 1'b0; inverse = 1'b0;")
    lines.append("        lane_mask = 5'b0; va_re = 0; va_im = 0; vb_re = 0; vb_im = 0; tw_re = 0; tw_im = 0;")
    lines.append("        errors = 0;")
    lines.append("        repeat (3) @(negedge clk); rst_n = 1'b1;")
    lines.append("        for (idx = 0; idx < NUM_CASES; idx = idx + 1) begin")
    lines.append("            inverse = case_inverse[idx];")
    lines.append("            lane_mask = 5'b0;")
    lines.append("            for (lane = 0; lane < LANES; lane = lane + 1) begin")
    lines.append("                lane_mask[lane] = (lane < case_active[idx]);")
    lines.append("            end")
    lines.append("            va_re = in0[idx]; va_im = in1[idx]; vb_re = in2[idx];")
    lines.append("            vb_im = in3[idx]; tw_re = in4[idx]; tw_im = in5[idx];")
    lines.append("            @(negedge clk); start = 1'b1;")
    lines.append("            @(negedge clk); start = 1'b0;")
    lines.append("            waits = 0;")
    lines.append("            while (!done && waits < 80) begin")
    lines.append("                @(posedge clk); #1; waits = waits + 1;")
    lines.append("            end")
    lines.append("            if (!done) begin")
    lines.append("                $display(\"TB_FAIL timeout case=%0d\", idx); errors = errors + 1;")
    lines.append("            end")
    lines.append("            for (lane = 0; lane < case_active[idx]; lane = lane + 1) begin")
    lines.append("                check_lane(y0_re, exp0[idx], lane, \"y0_re\");")
    lines.append("                check_lane(y0_im, exp1[idx], lane, \"y0_im\");")
    lines.append("                check_lane(y1_re, exp2[idx], lane, \"y1_re\");")
    lines.append("                check_lane(y1_im, exp3[idx], lane, \"y1_im\");")
    lines.append("            end")
    lines.append("        end")
    lines.append("        if (errors == 0) $display(\"TB_PASS falcon_fft_batch_compare cases=%0d\", NUM_CASES);")
    lines.append("        else $display(\"TB_FAIL errors=%0d cases=%0d\", errors, NUM_CASES);")
    lines.append("        $finish;")
    lines.append("    end")
    lines.append("")
    lines.append("endmodule")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--logn", type=int, default=9, choices=(9, 10))
    ap.add_argument("--mode", choices=("fft", "ifft", "both"), default="both")
    ap.add_argument("--backend", choices=("shared", "pipe"), default="shared")
    ap.add_argument("--keep-tb", action="store_true")
    args = ap.parse_args()

    cases = collect_cases(args.logn, args.mode)
    sim_dir = ROOT / "sim"
    sim_dir.mkdir(exist_ok=True)
    backend = 0 if args.backend == "shared" else 1
    stem = f"tb_falcon_fft_batch_compare_logn{args.logn}_{args.mode}_{args.backend}_{os.getpid()}"
    tb_path = sim_dir / f"{stem}.v"
    out_path = sim_dir / f"{stem}.vvp"
    emit_verilog(cases, tb_path, backend)

    cmd_compile = ["iverilog", "-g2012", "-o", str(out_path), "-f", str(ROOT / "rtl" / "filelist.f"), str(tb_path)]
    subprocess.check_call(cmd_compile, cwd=ROOT)
    subprocess.check_call(["vvp", str(out_path)], cwd=ROOT)

    if not args.keep_tb:
        for path in (tb_path, out_path):
            try:
                path.unlink()
            except OSError:
                pass


if __name__ == "__main__":
    main()
