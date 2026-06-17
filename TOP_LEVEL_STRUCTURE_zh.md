# 顶层结构展示索引

本文用于汇报和接手时快速展示本仓库的顶层结构。它按工程视角整理文件，而不是替代 `rtl/filelist.f`。

## 1. 仓库入口

```text
可重构/
|-- rtl/                 RTL 源码和仿真编译 filelist
|-- tb/                  纯 Verilog/SystemVerilog testbench
|-- doc/                 架构、交接、验证和汇报文档
|-- script/              Falcon FFT golden 生成与 RTL 对比脚本
|-- golden_vecs/         Falcon-512 golden stage/input/final 数据
|-- golden_vecs_1024/    Falcon-1024 golden stage/input/final 数据
|-- archive/             早期 Q16.16 fixed-point 原型归档
|-- sim/                 本地仿真输出目录
|-- README.md            项目总览
`-- gm_rom_*.hex         Falcon twiddle/GM ROM 数据
```

## 2. 顶层功能视图

```text
PQC RCE 扩展原型
|
+-- 整数模域 / NTT 路径
|   +-- reconfig_ntt_pipeline
|   |   +-- ntt_stage_ctrl
|   |   +-- shuffle_net
|   |   +-- ae_regfile
|   |   `-- reconfig_ae
|   |       +-- barrett_reduce
|   |       `-- montgomery_reduce
|   `-- reconfig_ntt_operator
|
+-- Falcon f64 FE / FFT 路径
|   +-- reconfig_fft_f64_operator
|   |   `-- reconfig_fe_f64_array
|   |       `-- reconfig_fe_f64
|   +-- reconfig_fft_f64_pipe_operator
|   |   `-- reconfig_fe_f64_pipe_array
|   |       `-- reconfig_fe_f64_pipe
|   +-- reconfig_fft_f64_shared_operator
|   |   `-- reconfig_fe_f64_shared_array
|   |       `-- reconfig_fe_f64
|   `-- falcon_f64_add / falcon_f64_mul
|
+-- Falcon FFT task / buffered engine
|   +-- falcon_fft_buffered_engine
|   |   +-- falcon_fft_task_engine
|   |   |   +-- falcon_fft_stage_ctrl
|   |   |   +-- falcon_fft_addr_gen
|   |   |   `-- falcon_fft_batch_exu
|   |   +-- falcon_fft_local_buffer
|   |   `-- falcon_fft_twiddle_cache
|   `-- falcon_fft_batch_exu
|
+-- SPUV3 VPU first-integration wrapper
|   +-- vpu_fe_exu_adapter
|   |   `-- vpu_fe_unit
|   |       `-- reconfig_fe_f64_shared_array
|   +-- spuv3_vpu_fe_f64_wrap
|   |   `-- reconfig_fft_f64_shared_operator
|   `-- spuv3_vpu_fe_mem_pack
|
`-- 微码 / ROM 辅助
    +-- useq_rom
    |   `-- useq_core
    +-- twiddle_rom
    `-- scheme_rom
```

## 3. RTL 文件分组

### 3.1 SPUV3 VPU FE 接入层

| 文件 | 展示说明 |
| --- | --- |
| `rtl/spuv3_vpu/vpu_fe_exu_adapter.v` | 放入真实 `vpu_exu` 的适配层，输出 `done/stall/result/vreg_we` |
| `rtl/spuv3_vpu/vpu_fe_unit.v` | VPU-facing FE 命令单元，处理 `LOAD_WIM/START/READ/CLEAR` |
| `rtl/spuv3_vpu/spuv3_vpu_fe_f64_wrap.v` | 320-bit VR / `vmask` 到 f64 shared FFT operator 的 wrapper |
| `rtl/spuv3_vpu/spuv3_vpu_fe_mem_pack.v` | 256-bit DLM/DPRAM row 与 320-bit VR 的 pack/unpack |

### 3.2 Falcon f64 FE / FFT 后端

| 文件 | 展示说明 |
| --- | --- |
| `rtl/falcon_fe/reconfig_fe_f64.v` | reference f64 complex FE |
| `rtl/falcon_fe/reconfig_fe_f64_pipe.v` | pipelined f64 FE |
| `rtl/falcon_fe/reconfig_fe_f64_array.v` | reference FE 多 lane array |
| `rtl/falcon_fe/reconfig_fe_f64_pipe_array.v` | pipelined FE 多 lane array |
| `rtl/falcon_fe/reconfig_fe_f64_shared_array.v` | 面积优先 shared FE array，支持 lane mask/backpressure |
| `rtl/falcon_fe/reconfig_fft_f64_operator.v` | reference FFT operator |
| `rtl/falcon_fe/reconfig_fft_f64_pipe_operator.v` | pipelined FFT operator |
| `rtl/falcon_fe/reconfig_fft_f64_shared_operator.v` | shared FE FFT operator |
| `rtl/falcon_fe/falcon_f64_add.v` | f64 加法 primitive |
| `rtl/falcon_fe/falcon_f64_mul.v` | f64 乘法 primitive |

### 3.3 Falcon FFT task engine

| 文件 | 展示说明 |
| --- | --- |
| `rtl/falcon_fft/falcon_fft_buffered_engine.v` | task engine、local buffer、twiddle cache 和 FE batch EXU 顶层组合 |
| `rtl/falcon_fft/falcon_fft_task_engine.v` | load/execute/store task shell |
| `rtl/falcon_fft/falcon_fft_stage_ctrl.v` | Falcon FFT/IFFT stage 和 batch 控制 |
| `rtl/falcon_fft/falcon_fft_addr_gen.v` | butterfly address 和 GM index 生成 |
| `rtl/falcon_fft/falcon_fft_batch_exu.v` | 5-lane batch EXU，封装 shared/pipe FFT operator |
| `rtl/falcon_fft/falcon_fft_local_buffer.v` | stage-to-stage ping-pong local buffer |
| `rtl/falcon_fft/falcon_fft_twiddle_cache.v` | lane-wide twiddle cache，支持 iFFT conjugation |

### 3.4 整数 AE / NTT 路径

| 文件 | 展示说明 |
| --- | --- |
| `rtl/ntt/reconfig_ae.v` | 16-mode integer AE，Barrett/Montgomery 模运算 |
| `rtl/ntt/reconfig_ae_array.v` | 32-lane AE array |
| `rtl/ntt/reconfig_ae_rf.v` | AE + local register file wrapper |
| `rtl/ntt/ae_regfile.v` | per-lane register file |
| `rtl/ntt/reconfig_ntt_operator.v` | NTT operator wrapper |
| `rtl/ntt/reconfig_ntt_pipeline.v` | 多 stage NTT pipeline |
| `rtl/ntt/ntt_stage_ctrl.v` | NTT stage 控制 |
| `rtl/ntt/shuffle_net.v` | NTT 数据重排网络 |
| `rtl/ntt/barrett_reduce.v` | Barrett reduction |
| `rtl/ntt/montgomery_reduce.v` | Montgomery reduction |

### 3.5 ROM / 微码辅助

| 文件 | 展示说明 |
| --- | --- |
| `rtl/rom/useq_core.v` | micro-sequencer core |
| `rtl/rom/useq_rom.v` | micro-sequencer ROM wrapper |
| `rtl/rom/twiddle_rom.v` | twiddle ROM |
| `rtl/rom/scheme_rom.v` | scheme parameter ROM |

## 4. 验证文件分组

### 4.1 VPU FE first integration

| Testbench | 覆盖点 |
| --- | --- |
| `tb/spuv3_vpu/tb_vpu_fe_unit.v` | `LOAD_WIM/START/READ/CLEAR`、result hold、`vmask=8` inactive lane 清零 |
| `tb/spuv3_vpu/tb_vpu_fe_exu_adapter.v` | EXU adapter 的 `stall/done/result/vreg_we` 行为 |
| `tb/spuv3_vpu/tb_spuv3_vpu_fe_f64_wrap.v` | 320-bit VR wrapper 和 f64 lane mask |
| `tb/spuv3_vpu/tb_spuv3_vpu_fe_mem_pack.v` | 256-bit memory row 到 320-bit VR 的 pack/unpack |

### 4.2 Falcon FE / FFT

| Testbench | 覆盖点 |
| --- | --- |
| `tb/falcon_fe/tb_reconfig_fe_f64.v` | reference f64 FE |
| `tb/falcon_fe/tb_reconfig_fe_f64_pipe.v` | pipelined f64 FE |
| `tb/falcon_fe/tb_reconfig_fe_f64_shared_array.v` | shared FE array |
| `tb/falcon_fe/tb_reconfig_fe_f64_shared_array_lanes5.v` | 5-lane shared FE |
| `tb/falcon_fe/tb_reconfig_fft_f64_operator.v` | reference FFT operator |
| `tb/falcon_fe/tb_reconfig_fft_f64_pipe_operator.v` | pipelined FFT operator |
| `tb/falcon_fe/tb_reconfig_fft_f64_shared_operator.v` | shared FFT operator |
| `tb/falcon_fft/tb_falcon_fft_addr_gen.v` | FFT/IFFT address 生成 |
| `tb/falcon_fft/tb_falcon_fft_stage_ctrl.v` | stage/batch 控制 |
| `tb/falcon_fft/tb_falcon_fft_task_engine_smoke.v` | task engine smoke |
| `tb/falcon_fft/tb_falcon_fft_buffered_engine_smoke.v` | buffered engine smoke |

### 4.3 整数 AE / NTT

| Testbench | 覆盖点 |
| --- | --- |
| `tb/ae/tb_mlkem_ae.v` | ML-KEM AE arithmetic |
| `tb/ae/tb_mlkem_ae_detail.v` | ML-KEM detail cases |
| `tb/ae/tb_mldsa_ae.v` | ML-DSA AE arithmetic |
| `tb/ae/tb_mldsa_ae_detail.v` | ML-DSA detail cases |
| `tb/ae/tb_reconfig_ae.v` | single AE |
| `tb/ae/tb_reconfig_ae_array.v` | AE array |
| `tb/ntt/tb_reconfig_ntt_operator.v` | NTT operator |
| `tb/ntt/tb_reconfig_ntt_operator_detail.v` | NTT detail cases |
| `tb/ntt/tb_ntt_butterfly_stage.v` | NTT butterfly stage |
| `tb/ntt/tb_ntt_multistage_rf.v` | multi-stage RF |
| `tb/ntt/tb_pqc_integration.v` | PQC integration smoke |

## 5. 展示推荐路径

汇报时建议按下面顺序讲，听众最容易建立全局图：

1. `README.md`：项目总览和已有验证结果。
2. `doc/report_summary.md`：SPUV3 RCE FE 阵列扩展的汇报口径。
3. 本文件：顶层目录、RTL 分组和主要模块层级。
4. `doc/vpu_fe_first_integration_zh.md`：第一版接入真实 SPUV3 的修改点。
5. `doc/agent_handoff_vpu_fe_integration_zh.md`：后续接手清单。

## 6. 常用验证入口

```bash
# Static RTL testbenches
python script/run_rtl_tests.py --list
python script/run_rtl_tests.py
python script/run_rtl_tests.py --suite all
python script/run_rtl_tests.py --category spuv3_vpu

# Falcon golden / RTL batch compare
python script/verify_fft_golden.py --logn 9 --mode both
python script/run_fft_batch_rtl_compare.py --logn 9 --mode both --backend both
python script/run_fft_buffered_final_compare.py --logn 10 --mode both
```

## 7. 当前物理分组规则

RTL 已按功能分到以下子目录：

- `rtl/ntt/`：整数 AE、NTT pipeline、shuffle 和模约简。
- `rtl/falcon_fe/`：f64 FE primitive、FE array 和 FFT operator。
- `rtl/falcon_fft/`：Falcon FFT task、buffer、twiddle cache 和 batch EXU。
- `rtl/spuv3_vpu/`：SPUV3 VPU first-integration wrapper 和 adapter。
- `rtl/rom/`：micro-sequencer、twiddle 和 scheme ROM。

Testbench 已按同样主题分到以下子目录：

- `tb/ae/`
- `tb/ntt/`
- `tb/falcon_fe/`
- `tb/falcon_fft/`
- `tb/spuv3_vpu/`
- `tb/misc/`

`rtl/filelist.f` 是 RTL 编译入口，Python 脚本统一通过它调用 Icarus Verilog。
`golden_vecs/`、`golden_vecs_1024/`、`gm_rom_im.hex`、`gm_rom_re.hex` 仍保留在仓库根目录，避免影响 golden 生成和 ROM 读入默认路径。
