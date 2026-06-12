# SPUV3 RCE FE 阵列扩展设计说明

## 1. 定位

SPUV3 RCE 已经是一套紧耦合密码协处理器，而不是普通外设 IP。它的基础能力包括 RV64IMFD 标量核心、BNPU、VPU、RSA accelerator、ILM/DLM/DPRAM、AHB 配置桥、SFR/CSR，以及面向密码算法的 XPqc 自定义指令。

本扩展的目标是在现有 SPUV3 RCE 上加入 FE 阵列，使 VPU/PQC 路径不仅支持 Kyber/Dilithium 这类 NTT 主导算法，也能覆盖 Falcon 所需的 f64 复数 FFT/iFFT 路径。

一句话定位：

```text
FE array = SPUV3 VPU/PQC 路径中的 Falcon f64/complex/FFT 专用执行阵列。
```

它不是标准 RISC-V FPU 的替代品。`spuv3_fpu_wrap` 仍然负责 RV64F/D 标量浮点指令，FE array 负责多 lane、任务级、复数模式的 Falcon FFT 运算。

## 2. SPUV3 基线与新增边界

SPUV3 Reference Guide 中的现有计算单元可以按功能分成四类：

| 单元 | 现有职责 | 与 FE 扩展的关系 |
|---|---|---|
| RV64IMFD core | 程序控制、地址计算、CSR/SFR 配置、XPqc 指令发射 | 保持不变，作为 FE task 的调度入口 |
| BNPU | 大数模运算、国密、ECC/AES/SM 系列相关算术 | 不替代 FE；可继续服务传统密码和大整数路径 |
| VPU | 320-bit 向量寄存器、Kyber/Dilithium NTT、向量加减、系数归约 | FE array 建议作为 VPU 的新增子执行路径 |
| RSA accelerator | 通过 DPRAM 协作完成 RSA CRT 运算 | 与 FE 基本独立，共享 DPRAM/时钟/状态约束 |

新增 FE array 后，SPUV3 的 PQC 覆盖范围从“现有 VPU/NTT 整数模域为主”扩展到：

- Kyber/ML-KEM：现有 VPU/NTT 路径。
- Dilithium/ML-DSA：现有 VPU/NTT + Keccak 辅助路径。
- Falcon：FE f64/complex FFT/iFFT 路径，必要时结合整数 NTT 或 hash/采样模块。

## 3. 推荐集成位置

FE array 推荐接在 `spuv3_exu` 的 XPqc/VPU dispatch 后面，作为 VPU 旁路或 VPU 子执行单元。

```text
spuv3_core
  |
  +-- IF / ID / EX / WB
              |
              +-- ALU / MULDIV / MEM / CSR
              +-- spuv3_fpu_wrap        # 标准 RV64F/D scalar FPU
              +-- BNPU pipeline
              +-- VPU integer pipeline  # Kyber/Dilithium NTT
              +-- FE array extension    # Falcon f64 FFT
```

这样做的好处是：

- 不污染标准 RV64F/D 指令语义。
- 复用 SPUV3 已有 XPqc 指令发射、寄存器准备、ordered commit 和 busy/done 体系。
- 和现有 VPU 的 PQC 数据路径靠近，便于复用 VR、DLM、DPRAM、vmask、NTT/FFT task 配置。
- 为后续把 NTT/FFT 都抽象成 coarse-grained task 留出统一接口。

## 4. FE 阵列功能

FE array 面向 Falcon 的 fpr/f64 复数运算。建议支持以下模式：

| 模式 | 功能 | 典型用途 |
|---|---|---|
| CT-BFU | `a + b*w`, `a - b*w` | FFT forward stage |
| GS-BFU | `(a+b)/2`, `(a-b)*w/2` 或对应 iFFT 形式 | IFFT/inverse stage |
| FLOAT-ADD/SUB/MUL | f64 标量基础运算 | bring-up、测试、局部数值任务 |
| COMPLEX-ADD/SUB | 复数加减 | split/merge、butterfly 前后级 |
| COMPLEX-MUL | 复数乘 twiddle | FFT/iFFT twiddle |
| COMPLEX-SQR | 复数平方 | Falcon tree / norm 类中间运算 |

当前 RTL 中已有三档 FE 实现：

| RTL | 定位 |
|---|---|
| `reconfig_fe_f64.v` | reference FE，便于功能对照 |
| `reconfig_fe_f64_pipe.v` | 三段流水 FE lane，适合高吞吐 |
| `reconfig_fe_f64_shared_array.v` | 单物理 FE lane 时间复用，面积优先 |

SPUV3 集成时可以用同一套 mode 语义，按产品配置选择不同后端。

## 5. 与 VPU/VR 的数据宽度关系

SPUV3 VPU 的 VR 是 320-bit，天然可容纳 `5 x 64-bit` f64 lane。当前 FE 原型默认 `LANES=8`，也就是 `512-bit` 输入/输出向量。

这个宽度差异是集成时最重要的接口问题之一。推荐保留三种配置路径：

| 配置 | 说明 | 适用阶段 |
|---|---|---|
| `LANES=5` | FE array 直接匹配单个 320-bit VR | 最小集成、控制简单 |
| `LANES=8` + 两拍 VR 搬运 | 两次 VR 读写拼成 512-bit FE batch，配合 `lane_mask` 管理尾 lane | 复用当前 RTL，适合快速 bring-up |
| FE local buffer | 在 FE 旁增加 512-bit 或 banked buffer，FFT stage 内部连续读写 | 性能优化阶段 |

短期建议：先使用 `LANES=8` + `lane_mask`，让 RTL 原型和现有 testbench 尽量不变。SPUV3 VPU 每次发起 FE task 时，由控制逻辑把 VR/DLM 数据搬入 FE hold registers；结果写回时按 lane tag 聚合，再分次写回 VR 或 DLM。

长期建议：增加 FE local buffer/twiddle cache，让多级 FFT/iFFT 在本地完成若干 stage 后再回写，减少 DLM/VR 带宽压力。

## 6. 控制与指令模型

FE 不建议暴露成细粒度 “fadd/fmul” 指令集合。它应该沿用 SPUV3 的 XPqc 设计风格，以任务级指令为主。

推荐指令抽象：

```text
vfe.ld       # DLM/DPRAM/VR -> FE buffer
vfe.st       # FE buffer -> DLM/DPRAM/VR
vfe.ctbfly   # FFT CT butterfly
vfe.gsbfly   # IFFT/GS butterfly
vfe.cmul     # complex multiplication
vfe.caddsub  # complex add/sub
vfe.csqr     # complex square
vfe.perm     # FFT/iFFT permutation helper
```

也可以先通过 SFR/CSR 方式 bring-up：

```text
FE_CFG:
  mode
  inverse
  lane_mask
  source_bank
  dest_bank
  twiddle_base

FE_STATUS:
  busy
  valid_out
  error/overflow/reserved
```

无论最终采用 XPqc 编码还是 SFR command，硬件内部建议保留当前 RTL 的握手语义：

```text
valid_in && !busy:
    接收一笔 FE task

busy:
    FE 正在执行，或结果等待下游 ready

valid_out:
    输出向量完整有效

valid_out && ready_in:
    下游接收结果，FE 可以释放并接收下一笔 task
```

这个模型能自然接入 SPUV3 的 ordered commit：XPqc 指令发出后等待 FE `valid_out` 或 task done，再按顺序回送 commit。

## 7. 存储与数据流

FE 阵列的数据流应尽量贴合 SPUV3 现有 DLM/DPRAM/VR 模型：

```text
DPRAM / DLM
    |
XPqc load
    |
VR or FE local buffer
    |
FE array
    |
in-place output gather
    |
VR or FE local buffer
    |
XPqc store
    |
DPRAM / DLM
```

Falcon FFT/iFFT 对数据搬运很敏感，后续性能优化重点不应只放在 f64 multiplier 数量上，还要关注：

- twiddle factor 是否本地缓存。
- FFT stage 的输入/输出 permutation 是否避免全量搬运。
- 是否支持 in-place 更新。
- 是否支持 lane_mask 跳过无效 lane。
- 是否能在 `valid_out` 与下一笔 `valid_in` 之间实现低空泡切换。

当前 `reconfig_fe_f64_shared_array.v` 的输出寄存器已经兼任结果聚合器：

```verilog
y0_re_vec[tag * 64 +: 64] <= lane_y0_re;
```

这意味着每个 lane 的输出直接写入最终向量 slice，不需要额外 FIFO 或最后的整体 copy。该特性适合接入 SPUV3 的 vector forwarding 思路。

## 8. 与 FPU 的区别

SPUV3 已有 RV64F/D FPU，但 Falcon 仍然需要 FE array，原因是两者的抽象层级不同。

| 项目 | 标准 FPU | FE array |
|---|---|---|
| 指令语义 | RV64F/D 标量浮点指令 | XPqc/PQC task 指令 |
| 数据形态 | 单个 f64/f32 | 多 lane f64 complex vector |
| 运算粒度 | add/sub/mul/div/fma 等基础操作 | butterfly、complex mul、FFT/iFFT stage |
| 控制方式 | 标准 EXU 流水线 | mode/lane_mask/twiddle/task descriptor |
| 目标 | ISA 完整性和标量计算 | Falcon FFT 吞吐与能效 |

因此，FE array 的设计原则不是“再造一个 FPU”，而是把多个 f64 add/mul 组织成 Falcon 需要的固定数据流，并在任务级减少指令数和数据搬运。

如果用增加通用 FPU 的方式支持 Falcon，虽然功能上可行，但会把 FFT/IFFT 拆成大量标量 f64 指令，带来较高的指令发射、寄存器读写、scoreboard 和 commit 压力。FE array 的优势在于直接把 Falcon 的结构化复数运算变成硬件 task：

| 维度 | 增加通用 FPU | FE array |
|---|---|---|
| 任务粒度 | 标量 fadd/fsub/fmul | CT/GS butterfly、complex mul、FFT stage |
| 数据组织 | 软件维护实部/虚部和寄存器重排 | 硬件按 complex lane 组织数据 |
| Twiddle 支持 | 普通 load + 标量乘法 | 可接 twiddle cache 和特殊值 bypass |
| 面积效率 | 包含 Falcon FFT 不常用的通用 FPU 逻辑 | 面向 f64 add/mul/complex datapath 裁剪 |
| 控制开销 | 多条指令、多次 commit | 一条 XPqc/VFE task 对应一个粗粒度计算 |
| 功耗 | 标量寄存器和控制切换较多 | `lane_mask`、shared FE、in-place gather 减少无效切换 |

所以 FE array 的目标不是替代标量 FPU 的 ISA 功能，而是在 Falcon FFT 这类重复、规则、高带宽任务上提供更好的面积效率和吞吐/控制比。

## 9. 面积与性能选项

FE array 可以按产品目标配置为三档：

| 配置 | 物理资源 | 性能 | 面积 |
|---|---|---|---|
| full parallel FE array | 每个 lane 都有 FE | 最高 | 最大 |
| pipelined FE array | 每个 lane 三段流水 | 高吞吐，时序更稳 | 中高 |
| shared FE array | 一个物理 FE 复用多个逻辑 lane | 吞吐较低 | 最小 |

对 SPUV3 这类 RCE 来说，shared FE 很有意义：Falcon 虽然需要 f64 FFT，但在完整产品里还要同时容纳 BNPU、VPU、RSA、DLM/DPRAM 和控制逻辑。用 shared FE 可以先把算法覆盖范围补齐，再根据实际 Falcon 性能目标逐步增加 lane 数。

## 10. 状态、时钟与系统约束

FE 扩展应遵守 SPUV3 Reference Guide 中的系统约束：

- 工作在 `clk` 核心时钟域，不引入额外异步 CDC。
- 当 `spuv3_busy=1` 时，FE、VPU、DLM、DPRAM 相关时钟必须按系统要求供给。
- FE 的 busy/done 需要并入 SPUV3 内部执行状态，不能让 Host 在算法运行期间破坏 DPRAM B 口访问约束。
- 若 FE 增加本地 SRAM/cache，需要纳入 test mode、clock gate 和 reset 策略。
- 若 FE 通过 SFR 暴露状态，读写语义应与现有 `spuv3_cfg`/`spuv3_cfg_int` 风格保持一致。

## 11. 当前 RTL 对应关系

当前工程中的文件可以映射为 SPUV3 FE 扩展的原型模块：

```text
rtl/
  falcon_f64_add.v                  # f64 helper
  falcon_f64_mul.v                  # f64 helper
  reconfig_fe_f64.v                 # reference FE lane
  reconfig_fe_f64_pipe.v            # pipelined FE lane
  reconfig_fe_f64_array.v           # parallel FE array
  reconfig_fe_f64_pipe_array.v      # pipelined FE array
  reconfig_fe_f64_shared_array.v    # shared FE array
  reconfig_fft_f64_operator.v       # reference FFT operator
  reconfig_fft_f64_pipe_operator.v  # pipelined FFT operator
  reconfig_fft_f64_shared_operator.v# shared FFT operator
```

这些模块目前还是独立原型接口。下一步如果要真正并入 SPUV3，需要增加一层 wrapper：

```text
spuv3_vpu_fe_wrap
    |
    +-- XPqc decode / CSR config adapter
    +-- VR/DLM read packer
    +-- twiddle read/cache adapter
    +-- reconfig_fft_f64_*_operator
    +-- output unpacker / writeback / commit
```

## 12. 验证计划

当前已覆盖的验证重点：

- f64 FE reference 模式。
- f64 pipelined FE 模式。
- shared FE 的 backpressure。
- shared FE 的 `lane_mask` 局部更新。
- f64 FFT operator CT/GS 基本路径。

并入 SPUV3 前还需要补的测试：

- VR 320-bit 到 FE 512-bit 的两拍 pack/unpack。
- `LANES=5` 配置下的 FE array。
- FE task 与 VPU/BNPU 指令的 ordered commit 互锁。
- `valid_out && !ready_in` 时 XPqc pipeline 不误提交。
- twiddle cache 地址越界、bank 冲突和特殊 twiddle bypass。
- Falcon FFT/iFFT 多 stage 端到端参考模型比对。

## 13. 推荐路线

建议按以下顺序推进：

1. 保留当前 FE RTL，新增 `spuv3_vpu_fe_wrap`，先用 SFR/CSR command 方式接入。
2. 实现 VR/DLM 到 FE 输入向量的 pack/unpack，优先支持 `LANES=8` + `lane_mask`。
3. 增加 `LANES=5` 参数配置测试，评估与 320-bit VR 单拍对齐的代价。
4. 将 shared FE 的物理 lane 从 reference FE 切换为 pipelined FE，降低 critical path。
5. 增加 twiddle cache 和 FFT permutation helper。
6. 把 command 方式收敛为正式 XPqc VFE 指令编码，并接入 LLVM/assembler。
7. 用 Falcon FFT/iFFT stage 级测试验证数值正确性和吞吐。

## 14. 总结

FE 阵列扩展的价值在于把 SPUV3 RCE 从“Kyber/Dilithium 友好的整数向量处理器”推进到“覆盖 NTT 与 Falcon FFT 的可重构 PQC 处理器”。它应当继承 SPUV3 的 tight-coupled coprocessor 思路，通过 XPqc/CSR/SFR 发起 coarse-grained task，而不是退化成一组细粒度浮点指令。

从系统角度看，FE array 的关键不是单个 f64 乘法器，而是：

- 放在 VPU/PQC 路径上的正确位置。
- 和 320-bit VR、DLM/DPRAM、twiddle 数据流对齐。
- 用 `lane_mask`、in-place gather 和 backpressure 控制面积与搬运。
- 保留 reference、pipeline、shared 三档实现，按面积和吞吐需求配置。
