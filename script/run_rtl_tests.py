#!/usr/bin/env python3
"""
Run repository RTL testbenches through Icarus Verilog.

This script is the common entry point for the static testbenches under tb/.
It compiles each selected testbench with rtl/filelist.f, runs vvp, and treats
non-zero exits or TB_FAIL/FAIL markers in the log as failures.
"""

import argparse
import fnmatch
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL_FILELIST = ROOT / "rtl" / "filelist.f"
KEEP_DIR = ROOT / "sim" / "script_runs"


TESTS = [
    ("ae", "tb_mlkem_ae", "tb/ae/tb_mlkem_ae.v"),
    ("ae", "tb_mlkem_ae_detail", "tb/ae/tb_mlkem_ae_detail.v"),
    ("ae", "tb_mldsa_ae", "tb/ae/tb_mldsa_ae.v"),
    ("ae", "tb_mldsa_ae_detail", "tb/ae/tb_mldsa_ae_detail.v"),
    ("ae", "tb_reconfig_ae", "tb/ae/tb_reconfig_ae.v"),
    ("ae", "tb_reconfig_ae_array", "tb/ae/tb_reconfig_ae_array.v"),
    ("ntt", "tb_reconfig_ntt_operator", "tb/ntt/tb_reconfig_ntt_operator.v"),
    ("ntt", "tb_reconfig_ntt_operator_detail", "tb/ntt/tb_reconfig_ntt_operator_detail.v"),
    ("ntt", "tb_ntt_butterfly_stage", "tb/ntt/tb_ntt_butterfly_stage.v"),
    ("ntt", "tb_ntt_multistage_rf", "tb/ntt/tb_ntt_multistage_rf.v"),
    ("ntt", "tb_pqc_integration", "tb/ntt/tb_pqc_integration.v"),
    ("ntt", "tb_useq_ntt", "tb/ntt/tb_useq_ntt.v"),
    ("falcon_fe", "tb_reconfig_fe_f64", "tb/falcon_fe/tb_reconfig_fe_f64.v"),
    ("falcon_fe", "tb_reconfig_fe_f64_pipe", "tb/falcon_fe/tb_reconfig_fe_f64_pipe.v"),
    ("falcon_fe", "tb_reconfig_fe_f64_shared_array", "tb/falcon_fe/tb_reconfig_fe_f64_shared_array.v"),
    ("falcon_fe", "tb_reconfig_fe_f64_shared_array_lanes5", "tb/falcon_fe/tb_reconfig_fe_f64_shared_array_lanes5.v"),
    ("falcon_fe", "tb_reconfig_fft_f64_operator", "tb/falcon_fe/tb_reconfig_fft_f64_operator.v"),
    ("falcon_fe", "tb_reconfig_fft_f64_pipe_operator", "tb/falcon_fe/tb_reconfig_fft_f64_pipe_operator.v"),
    ("falcon_fe", "tb_reconfig_fft_f64_shared_operator", "tb/falcon_fe/tb_reconfig_fft_f64_shared_operator.v"),
    ("falcon_fft", "tb_falcon_fft_addr_gen", "tb/falcon_fft/tb_falcon_fft_addr_gen.v"),
    ("falcon_fft", "tb_falcon_fft_stage_ctrl", "tb/falcon_fft/tb_falcon_fft_stage_ctrl.v"),
    ("falcon_fft", "tb_falcon_fft_task_engine_smoke", "tb/falcon_fft/tb_falcon_fft_task_engine_smoke.v"),
    ("falcon_fft", "tb_falcon_fft_buffered_engine_smoke", "tb/falcon_fft/tb_falcon_fft_buffered_engine_smoke.v"),
    ("spuv3_vpu", "tb_vpu_fe_unit", "tb/spuv3_vpu/tb_vpu_fe_unit.v"),
    ("spuv3_vpu", "tb_vpu_fe_exu_adapter", "tb/spuv3_vpu/tb_vpu_fe_exu_adapter.v"),
    ("spuv3_vpu", "tb_spuv3_vpu_fe_f64_wrap", "tb/spuv3_vpu/tb_spuv3_vpu_fe_f64_wrap.v"),
    ("spuv3_vpu", "tb_spuv3_vpu_fe_mem_pack", "tb/spuv3_vpu/tb_spuv3_vpu_fe_mem_pack.v"),
    ("misc", "tb_shuffle_net", "tb/misc/tb_shuffle_net.v"),
    ("misc", "tb_wide_mul", "tb/misc/tb_wide_mul.v"),
]


SMOKE_TEST_NAMES = {
    "tb_mlkem_ae",
    "tb_reconfig_ntt_operator",
    "tb_reconfig_fe_f64_shared_array_lanes5",
    "tb_falcon_fft_addr_gen",
    "tb_falcon_fft_stage_ctrl",
    "tb_vpu_fe_unit",
    "tb_vpu_fe_exu_adapter",
    "tb_spuv3_vpu_fe_f64_wrap",
    "tb_spuv3_vpu_fe_mem_pack",
}


def require_tool(name: str) -> None:
    if shutil.which(name) is None:
        raise SystemExit(f"missing required tool: {name}")


def selected_tests(args):
    tests = TESTS
    if args.suite == "smoke":
        tests = [t for t in tests if t[1] in SMOKE_TEST_NAMES]
    if args.category:
        wanted = set(args.category)
        tests = [t for t in tests if t[0] in wanted]
    if args.pattern:
        patterns = args.pattern
        tests = [
            t for t in tests
            if any(fnmatch.fnmatch(t[1], p) or fnmatch.fnmatch(t[2], p) for p in patterns)
        ]
    return tests


def has_fail_marker(text: str) -> bool:
    fail_markers = ("TB_FAIL", "FAIL:", "[FAIL]", " failed", "FAILED")
    return any(marker in text for marker in fail_markers)


def run_one(category: str, name: str, tb_rel: str, args) -> bool:
    tb_path = ROOT / tb_rel
    if not tb_path.is_file():
        print(f"[MISS] {name}: {tb_rel}")
        return False

    if args.keep:
        KEEP_DIR.mkdir(parents=True, exist_ok=True)
        out_path = KEEP_DIR / f"{name}.vvp"
        log_path = KEEP_DIR / f"{name}.log"
        return run_compile_and_vvp(category, name, tb_path, out_path, log_path, args)

    with tempfile.TemporaryDirectory(prefix=f"{name}_") as tmp:
        tmp_dir = Path(tmp)
        out_path = tmp_dir / f"{name}.vvp"
        log_path = tmp_dir / f"{name}.log"
        return run_compile_and_vvp(category, name, tb_path, out_path, log_path, args)


def run_compile_and_vvp(category: str, name: str, tb_path: Path, out_path: Path,
                        log_path: Path, args) -> bool:
    compile_cmd = [
        "iverilog", "-g2012",
        "-o", str(out_path),
        "-f", str(RTL_FILELIST),
        str(tb_path),
    ]
    print(f"[RUN ] {category:10s} {name}")
    if args.verbose:
        print("       " + " ".join(compile_cmd))

    compile_proc = subprocess.run(
        compile_cmd,
        cwd=ROOT,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if compile_proc.returncode != 0:
        log_path.write_text(compile_proc.stdout, encoding="utf-8")
        print(f"[FAIL] {name}: compile failed")
        if args.verbose:
            print(compile_proc.stdout)
        return False

    run_proc = subprocess.run(
        ["vvp", str(out_path)],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    log_path.write_text(run_proc.stdout, encoding="utf-8")
    failed = run_proc.returncode != 0 or has_fail_marker(run_proc.stdout)
    if failed:
        print(f"[FAIL] {name}: simulation failed")
        if args.verbose:
            print(run_proc.stdout)
        return False

    pass_line = next((line for line in run_proc.stdout.splitlines()
                      if "TB_PASS" in line or line.startswith("PASS:")), "")
    suffix = f" - {pass_line}" if pass_line else ""
    print(f"[PASS] {name}{suffix}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Run RTL testbenches via rtl/filelist.f")
    parser.add_argument("--suite", choices=("smoke", "all"), default="smoke",
                        help="smoke runs representative tests; all runs every static tb")
    parser.add_argument("--category", action="append",
                        choices=sorted({t[0] for t in TESTS}),
                        help="filter by category; can be provided multiple times")
    parser.add_argument("--pattern", action="append",
                        help="glob filter matched against test name or path")
    parser.add_argument("--list", action="store_true",
                        help="list selected tests without running")
    parser.add_argument("--keep", action="store_true",
                        help="keep compiled vvp and logs under sim/script_runs/")
    parser.add_argument("--stop-on-fail", action="store_true",
                        help="stop after the first failing test")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    require_tool("iverilog")
    require_tool("vvp")

    tests = selected_tests(args)
    if args.list:
        for category, name, tb_rel in tests:
            print(f"{category:10s} {name:40s} {tb_rel}")
        return 0

    if not tests:
        print("No tests selected.")
        return 1

    passed = 0
    failed = 0
    for category, name, tb_rel in tests:
        ok = run_one(category, name, tb_rel, args)
        if ok:
            passed += 1
        else:
            failed += 1
            if args.stop_on_fail:
                break

    total = passed + failed
    print(f"\nSummary: {passed}/{total} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
