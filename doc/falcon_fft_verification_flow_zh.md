# Falcon FFT/IFFT RTL 验证流程

## 1. 文档目的

本文说明当前工程如何验证 Falcon f64 FFT/IFFT RTL。验证范围覆盖 Python golden 模型、stage/batch 向量、5-lane RTL batch EXU，以及带本地 ping-pong buffer 的完整多 stage buffered engine。

当前验证目标不是只证明单个 BFU 正确，而是确认以下路径在 Falcon-512 与 Falcon-1024 参数下都能对齐 Falcon reference 行为：

- Falcon FFT/IFFT 地址生成。
- CT/GS butterfly 的 f64 复数运算。
- 5-lane、320-bit SPUV3 VR 风格 batch 数据格式。
- shared FE 与 pipelined FE 两种 backend。
- 本地双 bank buffer 的 stage-to-stage ping-pong。
- final-array 级别的完整 `f[]` 输出对照。

## 2. 当前验证层次

### 2.1 RTL operator smoke test

相关测试：

- `tb_reconfig_fft_f64_operator.v`
- `tb_reconfig_fft_f64_pipe_operator.v`
- `tb_reconfig_fft_f64_shared_operator.v`
- `tb_spuv3_vpu_fe_f64_wrap.v`

这一层证明 f64 CT/GS butterfly operator、shared FE、pipelined FE 以及 SPUV3 320-bit VR/VMASK wrapper 可以跑通基础仿真。

### 2.2 SPUV3 VPU FE first integration 验证

这一层验证 FE 作为 VPU 多周期子执行单元时的控制语义，而不是完整 Falcon stage loop。覆盖模块：

- `rtl/vpu_fe_unit.v`：shared FE、`w_im` 保持、四路结果保持和 `read_sel` 读回。
- `rtl/vpu_fe_exu_adapter.v`：`vpu_exu` 内部接入适配，提供 `fe_done_o`、`fe_stall_o`、`fe_result_o` 和 `fe_vreg_we_o`。

覆盖指令语义：

- `VFFELOADWIM`：加载 `w_im`，不写 VR。
- `VFFESTART`：启动 FE 运算，按多周期 busy/stall/done 处理，不写 VR。
- `VFFEREAD`：读取 `y0_re/y0_im/y1_re/y1_im`，是唯一写 VR 的 FE 指令。
- `VFFECLEAR`：清空内部状态，不写 VR。

同时验证 `vmask=8` 时 inactive f64 lane 不保留旧结果，避免通过 `VFFEREAD` 污染 VR。

### 2.3 Python golden stage-vector 验证

相关脚本与数据：

- `script/falcon_fft_golden.py`：生成 Falcon FFT/IFFT stage vectors。
- `script/verify_fft_golden.py`：验证 stage vectors 与 RTL 等价 butterfly 公式。
- `golden_vecs/`：Falcon-512，`logn=9`，包含 FFT/IFFT。
- `golden_vecs_1024/`：Falcon-1024，`logn=10`，包含 FFT/IFFT。
- `gm_rom_re.hex` / `gm_rom_im.hex`：f64 GM twiddle ROM 内容。

这一层的作用是把 Falcon 官方 `fft.c` 的数学行为转换成可喂给 RTL 的 batch 文件，并先在 Python 侧确认每个 butterfly 的输入输出一致。

### 2.4 RTL stage/batch 与 buffered engine 验证

相关 RTL：

- `rtl/falcon_fft_stage_ctrl.v`：遍历完整 FFT/IFFT stage 与 batch。
- `rtl/falcon_fft_addr_gen.v`：生成 Falcon reference 风格 a/b 地址和 GM index。
- `rtl/falcon_fft_batch_exu.v`：将 shared/pipe FE backend 封装成 5-lane batch datapath。
- `rtl/falcon_fft_task_engine.v`：连接 stage control、地址生成、batch EXU 与 load/store 握手。
- `rtl/falcon_fft_local_buffer.v`：双 bank f64 scalar buffer，保存 Falcon `f[]` 布局。
- `rtl/falcon_fft_twiddle_cache.v`：独立 twiddle cache，iFFT 时对虚部取负。
- `rtl/falcon_fft_buffered_engine.v`：完整 local-buffered FFT/IFFT engine。

相关脚本：

- `script/run_fft_batch_rtl_compare.py`：把 golden batch 文件喂给 RTL batch EXU，只比较 active lanes。
- `script/run_fft_buffered_final_compare.py`：预装 local buffer，运行完整 buffered engine，最后逐 scalar 比较最终 bank 的 `f[]`。

## 3. 快速生成 golden 数据

```bash
# Falcon-512 FFT + IFFT golden vectors
python script/falcon_fft_golden.py --logn 9 --mode both --outdir ./golden_vecs

# Falcon-1024 FFT + IFFT golden vectors，使用 Falcon 风格多项式输入
python script/falcon_fft_golden.py --logn 10 --mode both \
    --input-type falcon_poly --outdir ./golden_vecs_1024

# 如果要使用外部 GM 表
python script/falcon_fft_golden.py --logn 9 --mode both \
    --gm-re path/to/gm_rom_re.hex --gm-im path/to/gm_rom_im.hex
```

## 4. Golden 输出文件结构

```text
golden_vecs/
  fft_input.txt              # 输入数组，f64 hex
  fft_final.txt              # 最终 FFT 输出
  ifft_final.txt             # 最终 IFFT 输出
  fft_stages/
    stage_00_summary.txt     # stage 0 的所有 butterfly pair，人可读
    stage_00_batch_000.hex   # stage 0 batch 0，5-lane 320-bit hex vector
    stage_00_batch_001.hex
    ...
  ifft_stages/
    stage_00_summary.txt
    ...
```

Falcon-1024 使用 `golden_vecs_1024/`，结构相同，但每个 stage 有 256 个 butterfly pair，也就是 52 个 5-lane batch。

## 5. Batch Hex 格式

每个 `stage_SS_batch_BBB.hex` 包含两组 320-bit 行：

```text
# va_re           va_im           vb_re           vb_im           tw_re           tw_im
<80 hex chars>  <80 hex chars>  <80 hex chars>  <80 hex chars>  <80 hex chars>  <80 hex chars>

# y0_re           y0_im           y1_re           y1_im
<80 hex chars>  <80 hex chars>  <80 hex chars>  <80 hex chars>
```

每个 80 hex 字符串表示 `5 x 64-bit` f64 lane，按 MSB-lane-first 排列：最左边是 lane 4，最右边是 lane 0。这个布局和 SPUV3 `va_re_vr_i[319:0]` 等 320-bit VR 信号一致。

## 6. 推荐验证命令

### 6.1 Golden 公式验证

```bash
python script/verify_fft_golden.py --logn 9 --mode both
python script/verify_fft_golden.py --logn 10 --mode both --quick
```

当前已验证结果：

```text
logn=9:  22/22 configs pass, 22528/22528 butterflies pass
logn=10: 16/16 configs pass, 36864/36864 butterflies pass
```

### 6.2 RTL 基础 smoke test

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
```

通过标志：

```text
TB_PASS falcon_fft_addr_gen
TB_PASS falcon_fft_stage_ctrl
TB_PASS falcon_fft_task_engine_smoke
TB_PASS falcon_fft_buffered_engine_smoke
```

### 6.3 SPUV3 VPU FE first integration

```bash
iverilog -g2012 -o sim/tb_vpu_fe_unit.vvp \
  -f rtl/filelist.f tb/tb_vpu_fe_unit.v && \
  vvp sim/tb_vpu_fe_unit.vvp

iverilog -g2012 -o sim/tb_vpu_fe_exu_adapter.vvp \
  -f rtl/filelist.f tb/tb_vpu_fe_exu_adapter.v && \
  vvp sim/tb_vpu_fe_exu_adapter.vvp
```

当前已验证输出：

```text
TB_PASS vpu fe unit cases
TB_PASS vpu fe exu adapter cases
```

### 6.4 RTL batch EXU 对照

```bash
python script/run_fft_batch_rtl_compare.py --logn 9 --mode both --backend shared
python script/run_fft_batch_rtl_compare.py --logn 9 --mode both --backend pipe
python script/run_fft_batch_rtl_compare.py --logn 10 --mode fft --backend shared
python script/run_fft_batch_rtl_compare.py --logn 10 --mode fft --backend pipe
python script/run_fft_batch_rtl_compare.py --logn 10 --mode ifft --backend shared
python script/run_fft_batch_rtl_compare.py --logn 10 --mode ifft --backend pipe
```

当前通过结果：

```text
Falcon-512 FFT/IFFT:  416 batch cases pass
Falcon-1024 FFT/IFFT: 468 batch cases pass
```

### 6.5 Buffered Engine Final-Array 对照

```bash
python script/run_fft_buffered_final_compare.py --logn 9 --mode fft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 9 --mode ifft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 9 --mode fft --backend pipe --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 9 --mode ifft --backend pipe --max-abs 1e-11

python script/run_fft_buffered_final_compare.py --logn 10 --mode fft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode ifft --backend shared --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode fft --backend pipe --max-abs 1e-11
python script/run_fft_buffered_final_compare.py --logn 10 --mode ifft --backend pipe --max-abs 1e-11
```

当前通过结果：

```text
Falcon-512 FFT  shared: PASS, abs <= 1e-11
Falcon-512 IFFT shared: PASS, abs <= 1e-11
Falcon-512 FFT  pipe:   PASS, abs <= 1e-11
Falcon-512 IFFT pipe:   PASS, abs <= 1e-11

Falcon-1024 FFT  shared: PASS, bit-exact
Falcon-1024 IFFT shared: PASS, bit-exact
Falcon-1024 FFT  pipe:   PASS, bit-exact
Falcon-1024 IFFT pipe:   PASS, bit-exact
```

## 7. Falcon-1024 idx=0 Mismatch 定位结论

此前 Falcon-1024 FFT buffered final-array 有一个 `idx=0` mismatch。定位后确认不是数值误差，也不是 shared/pipe FE backend 的问题，而是地址生成器内部位宽问题。

根因：

```verilog
n_val = 1 << logn;
```

当 `logn=10` 时，`1 << 10 = 1024`，需要 11 bit 表示。原先 `n_val` 只有 `ADDR_W=10` bit，导致 1024 被截断成 0。这样 Falcon-1024 下地址生成器的内部判断和地址计算会退化，最终在 buffered final-array 对照中表现为 `idx=0` mismatch。

修复方式：

```verilog
reg [ADDR_W:0] n_val;
```

输出地址仍然保持 10-bit，因为 Falcon-1024 的合法 scalar index 是 `0..1023`；只是内部保存 `N=1024` 时需要多 1 bit。

同时 `falcon_fft_task_engine.v` 中 `pair_base_idx_r` 由 `ctrl_batch_idx * LANES` 生成，保证 batch index 与 pair base 在同一个握手点对齐。

## 8. IFFT Twiddle 约定

Falcon C reference 的 iFFT 使用：

```text
conj(GM) * (a - b)
```

RTL 的 GS mode 计算的是：

```text
w * (a - b)
```

RTL 内部不自动做 conjugate。因此 iFFT 输入 RTL 的 twiddle 必须提前共轭，也就是虚部取负。当前 `falcon_fft_twiddle_cache.v` 在 `conj_i=1` 时会对 twiddle imaginary component 取负；Python golden 的 `ifft_stages/` 也已经按这个约定输出 twiddle。

## 9. 与 Falcon 官方实现的对应关系

| Falcon C reference | Python golden | RTL/验证含义 |
|---|---|---|
| `Zf(FFT)` | `falcon_fft()` | forward FFT stage/final 对照 |
| `Zf(iFFT)` | `falcon_ifft()` | inverse FFT stage/final 对照 |
| CT butterfly | `rtl_ct_butterfly()` | RTL mode 0 |
| GS butterfly | `rtl_gs_butterfly()` | RTL mode 1 |
| GM table | `generate_gm_table()` / ROM hex | twiddle cache 输入 |

## 10. 当前结论

当前工程已经不只是 BFU 级验证，而是覆盖到完整 Falcon FFT/IFFT 流程：

- Falcon-512 与 Falcon-1024 都有 golden vectors。
- FFT 与 IFFT 都完成 RTL batch 级对照。
- shared 与 pipelined FE backend 都完成 final-array 对照。
- Falcon-1024 `idx=0` mismatch 已关闭。
- buffered engine 已证明可以在本地 buffer 内连续跑完整 stage loop。
- SPUV3 VPU FE first integration 已覆盖 FE wrapper、EXU adapter、四条 FE 指令语义和 partial lane 写回边界。

下一步更偏系统集成：把 `falcon_fft_buffered_engine` 接入 SPUV3 VPU/XPqc task scheduler，并用真实 DLM/DPRAM preload/drain 路径统计带宽、bank conflict 与吞吐。
