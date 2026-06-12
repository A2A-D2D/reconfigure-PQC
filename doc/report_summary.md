# SPUV3 RCE FE 阵列扩展汇报总结

## 1. 项目背景

SPUV3 RCE 是面向密码算法加速的紧耦合协处理器，现有架构已经包含 RV64IMFD 标量核心、BNPU、VPU、RSA accelerator、ILM/DLM/DPRAM、AHB 配置桥、SFR/CSR 和 XPqc 自定义指令体系。

其中，VPU 已经面向 Kyber/Dilithium 等格密码算法提供整数向量和 NTT 相关能力；BNPU 负责大数、国密、ECC/AES/SM 系列相关算术；标准 FPU 负责 RV64F/D 标量浮点指令。

当前扩展的核心目标是：在不破坏 SPUV3 现有软件模型、寄存器体系和执行单元边界的前提下，新增 FE 阵列，使 SPUV3 RCE 能进一步覆盖 Falcon 所需的 f64 复数 FFT/IFFT 路径。

## 2. 核心判断

本阶段不建议再新增独立 AE 阵列。

原因是 SPUV3 目前已经有 VPU/NTT 相关模块，整数模域路径已经具备明确承载位置。如果再新增一套 AE array，会造成以下问题：

- 与现有 VPU/NTT 整数路径职责重复。
- 增加面积和调度复杂度。
- 让 XPqc 指令、VR 数据路径和 NTT pipeline 的边界变得不清楚。
- 对 Falcon 支持的关键缺口帮助有限。

因此，当前设计口径调整为：

```text
现有 VPU/NTT 路径：继续负责 Kyber/Dilithium 等整数模域任务
新增 FE 阵列：负责 Falcon f64/complex/FFT/IFFT 任务
```

也就是说，AE 只作为旧原型 RTL 或论文概念中的整数算术元素保留，不作为 SPUV3 当前新增扩展的重点。

## 3. 设计定位

FE 阵列是 SPUV3 VPU/PQC 路径中的 Falcon 浮点复数执行扩展。它不是标准 FPU 的替代品。

标准 FPU 与 FE 阵列的区别如下：

| 项目 | 标准 FPU | FE 阵列 |
|---|---|---|
| 指令语义 | RV64F/D 标量浮点指令 | XPqc/PQC task 指令 |
| 数据形态 | 单个 f32/f64 | 多 lane f64 complex vector |
| 运算粒度 | add/sub/mul/div/fma | butterfly、complex mul、FFT/IFFT stage |
| 控制方式 | 标准 EXU 流水线 | mode、lane_mask、twiddle、task descriptor |
| 目标 | ISA 完整性 | Falcon FFT 吞吐和能效 |

FE 阵列的价值不在于“再造一个 FPU”，而在于把多个 f64 add/mul 组织成 Falcon 需要的复数数据流，用 task 粒度减少指令数和数据搬运。

如果只是给 SPUV3 再塞入一个或多个通用 FPU，理论上也能执行 Falcon FFT，但工程上并不划算。Falcon 的热点不是孤立的 f64 加法或乘法，而是高度重复的复数 butterfly 和 twiddle 乘法。通用 FPU 需要用多条标量指令拼出一个复数 butterfly，FE 阵列则把它固化成一个 task。

FE 阵列相对“堆 FPU”的主要优势如下：

| 维度 | 多塞 FPU 的问题 | FE 阵列的优势 |
|---|---|---|
| 指令数 | 一个复数 butterfly 需要多条 fadd/fsub/fmul 指令和调度开销 | 一条 XPqc/VFE task 覆盖完整 butterfly 或 complex mul |
| 数据搬运 | f64 数据需要频繁进出 FPR/VR，软件负责重排实部虚部 | FE 直接按 complex lane 组织输入输出，适合 VR/FE buffer |
| Twiddle 访问 | FPU 不理解 twiddle 流和 FFT stage 访问模式 | FE wrapper 可接 twiddle cache、特殊 twiddle bypass 和 permutation |
| 面积利用率 | 通用 FPU 包含 div、sqrt、rounding modes、异常等通用逻辑，Falcon FFT 用不上很多功能 | FE 只保留 FFT/complex 数据流所需的 f64 add/mul 组合 |
| 控制压力 | 标量 FPU 指令会增加 EXU/commit/scoreboard 压力 | FE 以 coarse-grained task 进入 busy/done/ordered commit |
| 功耗 | 多条标量指令和寄存器读写导致更多切换 | `lane_mask`、shared FE、in-place gather 可减少无效 lane 和搬运 |
| 可扩展性 | 堆 FPU 只能提升标量浮点吞吐，无法天然表达 FFT stage | FE 可以扩展为 pipeline/shared/full array，并加入 local buffer |

因此，FE 阵列的合理性不是“它能做 FPU 做不了的单个运算”，而是“它用更少的控制和搬运成本完成 Falcon FFT 这种结构化任务”。这也是它相比简单增加 FPU 更适合作为 SPUV3 RCE 扩展的原因。

## 4. 总体架构

推荐集成关系如下：

```text
spuv3_exu / XPqc dispatch
        |
        +-- BNPU pipeline
        +-- VPU integer/NTT pipeline
        +-- FE array extension
        +-- MEM / CSR / scalar FPU
```

软件侧仍按 SPUV3 原有模型工作：

```text
1. RV64I 准备地址、循环计数和任务参数
2. CSR/SFR 配置 vmask、mode、twiddle_base、lane_mask
3. XPqc load 将数据从 DLM/DPRAM 搬入 VR 或 FE buffer
4. XPqc compute 发起 NTT/FFT task
5. XPqc store 将结果写回 DLM/DPRAM
```

硬件侧通过 FE wrapper 对接：

```text
spuv3_vpu_fe_wrap
    |
    +-- XPqc decode / CSR config adapter
    +-- VR/DLM read packer
    +-- twiddle read/cache adapter
    +-- reconfig_fft_f64_*_operator
    +-- output unpacker / writeback / commit
```

## 5. FE 阵列功能范围

FE 阵列面向 Falcon 的 fpr/f64 复数计算，建议支持以下任务级模式：

| 模式 | 功能 | 用途 |
|---|---|---|
| CT-BFU | `a + b*w`, `a - b*w` | FFT forward stage |
| GS-BFU | inverse butterfly | IFFT / inverse stage |
| COMPLEX-MUL | 复数乘 twiddle | FFT/IFFT twiddle |
| COMPLEX-ADD/SUB | 复数加减 | split/merge、butterfly 前后级 |
| COMPLEX-SQR | 复数平方 | Falcon tree / norm 中间计算 |
| FLOAT-ADD/SUB/MUL | f64 基础操作 | bring-up、测试、局部数值任务 |

当前 RTL 已形成三种 FE 后端：

| 后端 | 文件 | 定位 |
|---|---|---|
| reference FE | `reconfig_fe_f64.v` | 功能基准，便于验证 |
| pipelined FE | `reconfig_fe_f64_pipe.v` | 高吞吐、较好时序 |
| shared FE | `reconfig_fe_f64_shared_array.v` | 面积优先，单物理 FE 复用多个逻辑 lane |

## 6. 面积控制思路

面积控制的核心策略是：不重复建设整数 AE 阵列，同时对 FE 提供共享实现。

当前 shared FE 的关键机制包括：

- 一个物理 FE lane 时间复用多个逻辑 lane。
- `lane_mask` 跳过无效 lane，减少无意义计算。
- 输出寄存器直接作为结果聚合器，避免额外 FIFO 或最终 copy。
- `ready_in` 支持背压，避免结果未被接收时被覆盖。
- inactive lane 保持原值，支持局部 in-place 更新。

这种结构适合先补齐 Falcon 算法覆盖，再根据性能目标逐步增加并行 lane 数。

## 7. 数据宽度与存储问题

SPUV3 VPU 的 VR 宽度是 320-bit，天然可容纳 `5 x 64-bit` f64 lane。当前 FE 原型常用 `LANES=8`，也就是 512-bit 向量。

因此接入时有三种选择：

| 方案 | 做法 | 适用阶段 |
|---|---|---|
| `LANES=5` | FE array 直接匹配单个 320-bit VR | 最小集成、控制简单 |
| `LANES=8` + 两拍搬运 | 两次 VR 读写拼成 512-bit FE batch | 快速复用当前 RTL |
| FE local buffer | 在 FE 旁增加 512-bit 或 banked buffer | FFT/IFFT 性能优化 |

短期建议采用 `LANES=8` + `lane_mask`，快速复用现有 RTL 和 testbench。长期建议增加 FE local buffer 与 twiddle cache，减少多 stage FFT/IFFT 对 VR/DLM 的带宽压力。

## 8. 当前阶段成果

当前工程已经完成以下原型和文档工作：

- 梳理 SPUV3 RCE 基线，明确 FE 阵列是 VPU/PQC 路径扩展。
- 调整设计口径：现有 VPU/NTT 负责整数模域，不再重复新增 AE 阵列。
- 实现 f64 reference FE、pipelined FE、shared FE 三种后端。
- 实现 f64 FFT operator 的 reference、pipeline、shared 三种封装。
- shared FE 支持 `lane_mask`、`ready_in`、busy/valid、直接输出聚合。
- 补充 SPUV3 FE 阵列扩展设计文档和架构说明。

已有验证重点包括：

- f64 FE reference 模式。
- f64 pipelined FE 模式。
- shared FE backpressure。
- shared FE `lane_mask` 局部更新。
- f64 FFT operator CT/GS 基本路径。
- NTT operator CT/GS 基本路径。

## 9. 关键风险

后续真正并入 SPUV3 时，需要重点关注以下风险：

| 风险 | 说明 | 建议 |
|---|---|---|
| VR 宽度不匹配 | SPUV3 VR 为 320-bit，当前 FE 原型常用 512-bit | 先做 pack/unpack wrapper，再评估 `LANES=5` |
| 数据搬运瓶颈 | FFT/IFFT 多 stage 会频繁访问向量和 twiddle | 增加 FE local buffer 和 twiddle cache |
| 指令接口未收敛 | 当前 FE 仍是原型接口 | 先用 SFR/CSR command bring-up，再固化 XPqc VFE 指令 |
| commit 互锁 | FE task 多周期，需与 SPUV3 ordered commit 对齐 | 在 wrapper 中加入 busy/done/ready 互锁 |
| 数值验证不足 | Falcon f64 FFT 对精度和舍入敏感 | 引入 Falcon FFT/IFFT stage 级参考模型 |

## 10. 下一步计划

建议按以下顺序推进：

1. 新增 `spuv3_vpu_fe_wrap`，把现有 FE operator 包装成 SPUV3 可接入接口。
2. 实现 VR/DLM 到 FE 输入向量的 pack/unpack。
3. 先支持 `LANES=8` + `lane_mask`，保证当前 RTL 快速进入系统 bring-up。
4. 增加 `LANES=5` 配置测试，评估与 320-bit VR 单拍对齐的代价。
5. 将 shared FE 的物理 lane 从 reference FE 切换为 pipelined FE，降低 critical path。
6. 增加 twiddle cache、特殊 twiddle bypass 和 FFT/IFFT permutation helper。
7. 把 SFR/CSR command 收敛为正式 XPqc VFE 指令编码。
8. 用 Falcon FFT/IFFT 多 stage 测试验证端到端正确性。

## 11. 汇报结论

本阶段的设计结论是：SPUV3 RCE 已经有较完整的整数模域和 NTT 基础，因此当前扩展不应重复建设 AE 阵列，而应聚焦新增 FE 阵列，补齐 Falcon 的 f64 复数 FFT/IFFT 能力。

该方案的优势是：

- 复用现有 VPU/NTT，减少面积和调度重复。
- 新增 FE 直接对准 Falcon 的关键缺口。
- 保留 reference、pipeline、shared 三档实现，便于在面积和性能之间取舍。
- 延续 SPUV3 的 XPqc、CSR/SFR、VR/DLM/DPRAM 和 ordered commit 模型。

最终目标是把 SPUV3 从“面向 Kyber/Dilithium 的整数向量 RCE”，扩展为“同时覆盖 NTT 与 Falcon FFT 的可重构 PQC RCE”。
