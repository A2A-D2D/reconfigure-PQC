# SPUV3 RCE + FE 阵列扩展设计文档

## 1. 设计目标

本项目当前不再定位为一个脱离系统的独立算术处理器，而是定位为 **SPUV3 RCE(Reconfigurable Crypto Engine) 的 FE 阵列扩展原型**。SPUV3 已经具备 RV64IMFD 标量核心、BNPU、VPU、RSA accelerator、ILM/DLM/DPRAM、AHB 配置桥、SFR/CSR 和 XPqc 自定义指令体系。本设计在这个基础上补齐 Falcon 类算法所需的 f64 复数 FFT/IFFT 能力。

扩展目标是：在不破坏现有 SPUV3 编程模型和 BNPU/VPU 边界的前提下，给 VPU/PQC 路径增加一个可配置 FE array，使 RCE 从 Kyber/Dilithium 这类 NTT 主导算法，进一步覆盖 Falcon 的浮点复数路径。

SPUV3 现有能力与 FE 扩展的关系如下：

- RV64IMFD 核：继续负责程序控制、指针、循环、CSR/SFR 配置和 XPqc 指令发射。
- BNPU：继续负责大数、国密、传统模运算和部分对称密码路径。
- VPU：继续负责 Kyber/Dilithium 的向量模运算、NTT、系数归约、Keccak 相关向量任务。
- FE array：新增在 VPU/PQC 算术侧，负责 Falcon f64、复数乘法、FFT CT/GS butterfly、twiddle 乘法和局部 in-place 更新。
- 标准 FPU：仍然是 RV64F/D 标量浮点执行单元，不承担 Falcon 多 lane FFT 的主要吞吐路径。

设计重点不是固定实现某一个算法，而是把多种 PQC 方案共享的执行模式接入 SPUV3 的 task-level 执行框架：

- 模整数运算：模加、模减、模乘、Montgomery/Barrett 约减、NTT 蝶形。
- 浮点与复数运算：双精度加减乘、复数加减乘平方、FFT CT/GS 蝶形。
- 向量化执行：一组 lane 同时或分时处理多组系数。
- 任务级配置：通过 XPqc/CSR/SFR 下发 mode、mask、valid/ready 等执行语义。
- 面积与吞吐可调：同一类 FE 运算提供并行、流水、共享三种实现路径。

整体设计吸收可重构 PQC 处理器中的几个关键思想：算术 cluster、整数路径/浮点路径分工、任务级配置、in-place 写回、vector forwarding、以及用专用 cache 或 buffer 降低高带宽变换运算的数据搬运压力。具体集成时，以 SPUV3 已有 VPU/NTT 路径、VR/BNPR remap、DLM/DPRAM 访存、`spuv3_busy`/`spuv3_alg_done` 状态模型为边界。

## 1.1 SPUV3 RCE 基线覆盖

SPUV3 RCE Reference Guide 中的基线架构可以概括为：

```text
Host CPU / AHB
    |
    +-- AHB config bridge -> SFR / ILM / DLM config
    +-- AHB DPRAM bridge  -> DPRAM data exchange

SPUV3 subsystem
    |
    +-- RV64IMFD core: IF / ID / EX / WB
    +-- BNPU: 256-bit big-number and SM/ECC/AES style arithmetic
    +-- VPU: 320-bit vector register path for Kyber/Dilithium PQC tasks
    +-- RSA accelerator: DPRAM-coupled CRT path
    +-- ILM / DLM / DPRAM / CSR / SFR
```

现有 VPU 已经覆盖 Kyber/Dilithium 的 NTT、向量加减、系数归约、Keccak 辅助任务。FE array 扩展的必要性来自 Falcon：Falcon 的签名和密钥生成路径包含 fpr/f64 复数 FFT、iFFT、split/merge、LDL/Falcon tree 和 ffSampling 相关数值计算，仅靠现有标量 FPU 或整数 VPU 难以获得合适吞吐。

因此 FE array 的正确位置不是替换 `spuv3_fpu_wrap`，而是作为 VPU 旁路或 VPU 子执行单元接入：

```text
spuv3_exu / XPqc dispatch
        |
        +-- BNPU pipeline
        +-- VPU integer/NTT pipeline
        +-- FE array extension       <- new
        +-- MEM / CSR / scalar FPU
```

这让软件仍然按照 SPUV3 的典型模型工作：RV64I 准备地址和循环，CSR 配置 `vmask`/模式/模数或 FE 参数，XPqc load 把数据送入 B/V/FE buffer，XPqc compute 发起 NTT/FFT task，XPqc store 写回 DLM/DPRAM。

## 2. 总体架构

当前工程按算术类型划分为现有整数 NTT 路径、FE、NTT/FFT operator、控制/存储辅助模块几类。放到 SPUV3 中时，整数模域能力应优先复用现有 VPU/NTT 模块，FE 是新增的浮点复数执行能力，operator 是 XPqc task 的硬件执行体。

```text
                  +-----------------------------------+
                  | SPUV3 XPqc / CSR / SFR control    |
                  | opcode, vmask, mode, cfg, status  |
                  +-----------------+-----------------+
                                    |
        +---------------------------+---------------------------+
        |                           |                           |
 +------+-------+           +-------+------+            +-------+------+
 | BNPU / RSA   |           | VPU NTT path |            | FE extension |
 | big-number   |           | integer NTT  |            | f64 FFT      |
 +------+-------+           +-------+------+            +-------+------+
                                |                           |
                         +------+-------+           +-------+------+
                         | NTT operator |           | FFT operator |
                         | CT / GS NTT  |           | CT / GS FFT  |
                         +------+-------+           +-------+------+
                                |                           |
                                +-------------+-------------+
                                              |
                                  VR / FE buffer / DLM
```

现有 VPU/NTT 路径负责整数与模域运算，适合 Kyber/Dilithium 的 NTT、点乘、模乘累加等任务。FE 负责 Falcon 等算法中的双精度浮点路径，尤其是 FFT、iFFT、复数乘法和 butterfly。NTT/FFT operator 是 task-level 封装，将现有整数变换路径和新增 FE 路径组织成 stage 级执行单元。

### 2.1 与 SPUV3 寄存器宽度的对齐

当前 FE array 原型默认 `LANES=8`，一组向量宽度为 `8 x 64 = 512 bit`。SPUV3 VPU 的 VR 逻辑宽度是 `320 bit`，也就是天然能容纳 `5 x 64 bit`。因此真正接入 SPUV3 时有三种可选策略：

| 策略 | 做法 | 优点 | 代价 |
|---|---|---|---|
| VR 对齐 | FE array 设置为 `LANES=5` | 和 320-bit VR 一拍对齐，控制简单 | FFT stage 的 radix 分组不一定最舒服 |
| 两拍搬运 | 保留 `LANES=8`，用两次 VR 读写组成 512-bit batch | 保留当前 RTL 并行度 | 需要 VPU/FE buffer 做拼接和 lane valid |
| 本地 FE buffer | 在 FE 旁加 512-bit 或 banked buffer | 最适合 FFT/IFFT 连续 stage 和 in-place 更新 | 面积增加，需要地址/冲突控制 |

工程上建议先采用“两拍搬运 + lane_mask”的方式验证功能，再根据面积和性能目标决定是否加入本地 FE buffer。

### 2.2 软件可见控制模型

FE 扩展建议沿用 SPUV3 的 XPqc 思路，而不是把每个 f64 add/mul 暴露成普通浮点指令。推荐的软件可见任务粒度是：

- `vfe.ctbfly`：Falcon FFT CT butterfly。
- `vfe.gsbfly`：Falcon IFFT/GS butterfly。
- `vfe.cmul`：复数乘法或 twiddle 乘法。
- `vfe.caddsub`：复数加减。
- `vfe.csqr`：复数平方。
- `vfe.mov/store/load`：VR、DLM、FE buffer 之间搬运。

这些指令可以映射到现有 VPU 类编码空间，也可以先通过 SFR/CSR command 方式 bring-up。无论采用哪种形式，硬件侧都应保留 `mode`、`inverse`、`lane_mask`、`valid_in`、`busy`、`valid_out`、`ready_in` 语义，便于后续接入 ordered commit 和 pipeline scoreboard。

## 3. 现有 VPU/NTT 整数路径

在当前 SPUV3 RCE 语境下，不建议再把 AE 作为一个新的独立阵列来规划。论文里的 AE 可以理解为整数算术元素，但 SPUV3 已经有 VPU/NTT 相关模块承担这部分职责。因此本项目新增重点应放在 FE 阵列，整数模域路径优先复用现有 NTT/VPU 能力。

当前工程中仍保留了一组 AE 命名的原型 RTL，它们可以作为整数路径的验证参考或 standalone bring-up 模块：

- `reconfig_ae.v`
- `reconfig_ae_array.v`
- `reconfig_ae_rf.v`
- `barrett_reduce.v`
- `montgomery_reduce.v`

这些模块的设计思路是用一个可配置 datapath 支持多种整数运算模式。典型模式包括：

- CT butterfly
- GS butterfly
- modular add/sub
- modular multiplication
- Montgomery multiplication
- multiply-accumulate
- 64-bit big multiplication 相关模式

如果后续接入真实 SPUV3，不应再重复新增一套 AE array，而应把这些能力映射到已有 VPU/NTT pipeline，或者仅把其中缺失的小模块作为 NTT datapath 的局部补强。上层 `reconfig_ntt_operator` 仍可作为 NTT task 的参考封装，用于组织输入、twiddle 和输出。

## 4. FE 模块

FE 是浮点与复数执行单元，服务于 Falcon 风格的 FFT/fpr 路径。它与通用 FPU 的区别是：

- FPU 只关心 IEEE-754 基本运算，例如 add、sub、mul。
- FE 面向算法级复数模式，把 f64 add/mul 组合成 butterfly、complex mul、complex square、complex MAC。
- FE 不负责解码通用浮点指令，而是根据 mode 执行固定的 PQC 算术任务。
- FPU 无法天然表达 FFT stage、twiddle 流、lane_mask 和 in-place gather；FE 可以把这些控制固化成一个粗粒度 task。
- 对 Falcon FFT 而言，增加通用 FPU 会带来更多标量指令、FPR/VR 搬运和 commit 压力；FE 用复数 lane 数据流减少控制开销和无效寄存器读写。

当前 FE 分为四条路径。

### 4.1 定点 FE 原型

相关文件：

- `reconfig_fe.v`
- `reconfig_fe_array.v`
- `reconfig_fft_operator.v`

这是 Q16.16 定点复数 FE，用于早期 bring-up 和结构验证。它能表达 CT/GS butterfly 和复数运算，但不是 Falcon fpr 的最终精度路径。

### 4.2 f64 reference FE

相关文件：

- `falcon_f64_add.v`
- `falcon_f64_mul.v`
- `reconfig_fe_f64.v`
- `reconfig_fe_f64_array.v`
- `reconfig_fft_f64_operator.v`

`reconfig_fe_f64.v` 直接实例化多组 f64 add/mul helper，用组合方式生成所有模式的结果，再打一拍输出。这条路径功能直接、易验证，适合作为 correctness reference。

缺点是面积较大，因为每个 lane 内部复制了较多 f64 运算资源。

### 4.3 f64 pipelined FE

相关文件：

- `reconfig_fe_f64_pipe.v`
- `reconfig_fe_f64_pipe_array.v`
- `reconfig_fft_f64_pipe_operator.v`

这是当前更接近硬件微架构的 FE lane。内部按三段组织：

```text
stage 1: pre-add / pre-sub
stage 2: four f64 multipliers for complex product
stage 3: post-add / post-sub / MAC
```

特点：

- 每拍可接收一笔 FE 操作。
- 输出延迟为 2 个周期。
- 复数乘法使用 4 个 f64 multiplier。
- 比 reference FE 更适合时序收敛。
- 保持与 reference FE 相同的 mode 语义。

这条路径适合高吞吐 FFT stage。

### 4.4 f64 shared FE

相关文件：

- `reconfig_fe_f64_shared_array.v`
- `reconfig_fft_f64_shared_operator.v`

shared FE 是面积优化版本。它只实例化一个物理 FE lane，通过时间复用处理多个逻辑 lane。

核心机制：

- `lane_mask` 指示本次 task 需要处理哪些 lane。
- 有效 lane 被顺序 issue 到共享 FE。
- `tag_pipe` 跟踪 lane index，保证结果写回到正确 slice。
- `y*_vec` 输出寄存器同时作为 gather buffer。
- inactive lane 不清零、不覆盖，保留原输出。
- `ready_in` 提供下游背压，防止结果未被接收时被下一笔覆盖。

共享 FE 的数据流如下：

```text
input vector
    |
    | lock once
    v
hold registers
    |
    | issue active lanes only
    v
single FE lane
    |
    | result + tag
    v
y*_vec output slice
    |
valid_out / ready_in
```

这种结构的意义是：不需要临时 FIFO，不需要最后整体搬运输出。每个 lane 的结果直接写入最终输出向量。最后一个 active lane 写入时，整个 vector 已经可用。

## 5. NTT 与 FFT Operator

NTT 和 FFT 都是多 stage 的变换运算，适合做成 coarse-grained task。

### 5.1 NTT 路径

相关文件：

- `reconfig_ntt_operator.v`
- `reconfig_ntt_pipeline.v`
- `ntt_stage_ctrl.v`
- `twiddle_rom.v`
- `scheme_rom.v`

NTT operator 代表现有 VPU/NTT 整数路径中的 task 级封装，用于完成模域 butterfly。当前支持 CT/GS 方向切换，并使用模数、Montgomery/Barrett 参数配置不同模域。接入 SPUV3 时，它更适合作为 VPU NTT pipeline 的参考结构，而不是新增一套并列 AE 阵列。

### 5.2 FFT 路径

相关文件：

- `reconfig_fft_operator.v`
- `reconfig_fft_f64_operator.v`
- `reconfig_fft_f64_pipe_operator.v`
- `reconfig_fft_f64_shared_operator.v`

FFT operator 调用 FE 完成复数 butterfly。

```text
inverse = 0 -> CT butterfly
inverse = 1 -> GS butterfly
```

现有三种 f64 FFT operator 对应三种面积/吞吐选择：

| Operator | FE backend | 适用场景 |
|---|---|---|
| `reconfig_fft_f64_operator` | reference FE array | 功能基准，便于对照 |
| `reconfig_fft_f64_pipe_operator` | pipelined FE array | 高吞吐 FFT |
| `reconfig_fft_f64_shared_operator` | shared FE array | 面积优先，支持 mask/backpressure |

## 6. 任务级配置

当前设计已经具备几类 task-level 配置信号：

- `mode`：选择 FE 或现有 VPU/NTT 路径的具体运算模式。
- `inverse`：选择 CT/GS butterfly。
- `lane_mask`：选择当前 task 的 active lane。
- `valid_in`：提交一个 task 或 vector batch。
- `busy`：表示单元不能接收新任务。
- `valid_out`：表示输出结果有效。
- `ready_in`：下游接收结果，用于背压。

shared FE 的握手语义如下：

```text
valid_in && !busy:
    接收新任务，锁存输入向量和配置

busy:
    正在执行，或结果 pending 且下游未 ready

valid_out:
    输出向量完整有效

valid_out && !ready_in:
    保持输出，不接收新任务

valid_out && ready_in:
    释放结果，允许下一笔任务
```

这种接口适合后续接入 task scheduler 或微码控制器。

## 7. In-place 输出聚合

shared FE 中 `y0_re_vec/y0_im_vec/y1_re_vec/y1_im_vec` 不只是普通输出寄存器，也承担结果聚合器的角色。

每当共享 FE lane 输出一个结果：

```verilog
y0_re_vec[tag * 64 +: 64] <= lane_y0_re;
```

结果会直接写到最终输出向量的对应 lane slice。这样避免了传统结构中的：

- 临时结果 FIFO
- gather buffer
- 最后一拍 copy 到 output register

加入 `lane_mask` 后，inactive lane 不会被覆盖，因此输出寄存器还能支持局部 in-place 更新。

这对应了 vector forwarding 的思想：结果尽量直接进入下一个任务可见的位置，减少无意义搬运。

## 8. 面积、吞吐与功耗权衡

当前 FE 有三档实现：

| 实现 | 面积 | 吞吐 | 延迟 | 用途 |
|---|---:|---:|---:|---|
| reference FE array | 高 | 高 | 低 | 功能基准 |
| pipelined FE array | 中高 | 高 | 固定 2 拍 | 高性能 FFT |
| shared FE array | 低 | 中低 | 与 active lane 数相关 | 面积优先 |

shared FE 的优化点：

- 一个物理 FE lane 服务多个逻辑 lane。
- `lane_mask` 跳过无效 lane，减少周期和切换。
- 不清零整向量输出，减少寄存器翻转。
- 输出寄存器直接聚合结果，减少额外 buffer。
- `ready_in` 背压避免为了安全再加一层 output FIFO。

## 9. 文件结构

关键 RTL 文件：

```text
rtl/
  # legacy / reference integer prototypes, not the new SPUV3 extension focus
  reconfig_ae.v
  reconfig_ae_array.v

  # existing integer transform path reference
  reconfig_ntt_operator.v
  reconfig_ntt_pipeline.v

  # new FE extension focus
  falcon_f64_add.v
  falcon_f64_mul.v
  reconfig_fe_f64.v
  reconfig_fe_f64_array.v
  reconfig_fe_f64_pipe.v
  reconfig_fe_f64_pipe_array.v
  reconfig_fe_f64_shared_array.v

  reconfig_fft_f64_operator.v
  reconfig_fft_f64_pipe_operator.v
  reconfig_fft_f64_shared_operator.v
```

关键 testbench：

```text
tb/
  tb_reconfig_ae.v
  tb_reconfig_ntt_operator.v
  tb_reconfig_fe.v
  tb_reconfig_fe_f64.v
  tb_reconfig_fe_f64_pipe.v
  tb_reconfig_fe_f64_shared_array.v
  tb_reconfig_fft_f64_operator.v
  tb_reconfig_fft_f64_pipe_operator.v
  tb_reconfig_fft_f64_shared_operator.v
```

## 10. 验证状态

当前已经通过的主要测试包括：

- 整数/NTT 基本模式测试
- NTT operator CT/GS 测试
- 定点 FE 测试
- f64 reference FE 测试
- f64 pipelined FE 测试
- f64 FFT operator 测试
- f64 shared FE 测试
- shared FE backpressure 测试
- shared FE lane_mask partial update 测试

典型通过输出：

```text
TB_PASS all f64 FE cases
TB_PASS all pipelined f64 FE cases
TB_PASS all shared f64 FFT operator cases
TB_PASS all 2 NTT operator cases
TB_PASS  All tests passed
```

此外，新增 RTL 与 testbench 已按纯 Verilog-2001 规则检查。

## 11. 后续优化方向

后续可以继续推进以下方向：

1. 将 `reconfig_fe_f64_shared_array` 的共享 lane 从 reference FE 切换到 pipelined FE。
2. 增加 twiddle special-case bypass，例如 `1+0i`、`0+1i`、`-1+0i`、`0-1i`。
3. 给 FFT/NTT stage 加更完整的 input/output permutation network。
4. 引入 arithmetic cache，专门存 twiddle，减少主 buffer 端口压力。
5. 增加 task descriptor，包括 mode、lane_mask、source/destination bank、streaming 标志。
6. 将 FE operator 接入 SPUV3 VPU/XPqc task scheduler，并复用现有 NTT 调度路径。
7. 增加更完整的 Falcon FFT/iFFT stage-level test。

## 12. 总结

当前设计已经形成了一个可作为 SPUV3 RCE FE 扩展基础的 PQC 算术原型：

- 现有 VPU/NTT 路径覆盖整数和模域运算。
- FE 扩展覆盖 Falcon 所需的 f64 与复数运算。
- NTT/FFT operator 将 lane 级算术组织成可接入 XPqc 的 task 级变换。
- shared FE 提供面积优先路径。
- pipelined FE 提供吞吐优先路径。
- `lane_mask`、`ready_in`、in-place 输出聚合让设计更适合接入 SPUV3 的 VPU/FE task 流。

这个结构后续应优先向 `spuv3_vpu_fe_wrap`、VR/DLM pack-unpack、twiddle cache、XPqc 指令编码和 Falcon FFT/iFFT stage 级验证演进，而不是停留在单个算术单元。
