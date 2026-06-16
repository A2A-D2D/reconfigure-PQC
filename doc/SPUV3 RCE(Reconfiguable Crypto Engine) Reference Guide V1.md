# SPUV3 RCE(Reconfiguable Crypto Engine) Reference Guide V1

**Copyright 2026 Shandong Exponent Semiconductor CO., Ltd. / Sansec Technology CO., Ltd.**

---

## 文档变更记录

| 版本 | 日期 | 主要内容 | 作者 |
| --- | --- | --- | --- |
| 1.0 | 2025-08 | 初稿：顶层架构总览、模块层次、BNPU/VPU 指令集、访存系统、CSR 映射、RSA 加速器 | Jia |
| 1.1 | 2025-09 | 汇编器增加 `#define` 预处理支持；补充 RV64F/D 完整浮点指令及 FPU 62 路 one-hot 指令表 | Jia |
| 1.2 | 2026-04 | PQC 指令重新编码（避免与 RV64F/D 冲突）；完善 VPU 第 1–6 类编码表；补充综合时序报告 | Jia |
| 1.3 | 2026-05 | 补充 BNPU 完整机器码模板（含 E/F/G 格式）；新增调用约定、VMASK 所有权、汇编语法规范 | Jia |
| 1.4 | 2026-05 | 新增长跳转与函数调用说明：确认 JALR/AUIPC RTL 支持，论证 ILM 128KB 下 jal 足够无需 call 伪指令 | Jia |
| 1.5 | 2026-05 | 非对齐 256-bit Load/Store（bnsw/bnlw/vlevx/vsevx, offset 0–31）；VPU coeffi 共享 buffer 合并（面积 -143K μm²）；M/H 分支预测差异；更新综合面积；cfgkit 配置工具链 | Jia |
| 1.6 | 2026-05 | LLVM xpqc 编译器适配：VPU/BNPU/SYM 完整 MC 层汇编+反汇编（131,333 条指令逐字节一致）；C 寄存器（c0-c31, CC）独立定义；`SPUV3_LLVM_HOME` 工具链部署规范；LLVM 适用性分析 | Jia |
| 1.7 | 2026-06 | 子系统顶层接口与时钟规范：完整端口信号表（核心控制+AHB 配置桥+DPRAM 桥+test\_mode）、4 时钟域架构、时钟供给纪律、DPRAM 双口共享与 `gnrl_async_clkmux` 异步安全切换、上电启动 12 步流程、SFR 寄存器详解、使用注意事项与约束 | Jia |
| 1.8-draft | 2026-06 | Falcon f64 FE first integration 草案：新增 VPU FE 指令、320-bit VR 到 f64 lane 映射、`vmask` 语义、FE wrapper 多周期接入和第一版验证边界 | Codex |

---

## 目录

1.  [项目概述](#1-%E9%A1%B9%E7%9B%AE%E6%A6%82%E8%BF%B0)
    
2.  [顶层架构](#2-%E9%A1%B6%E5%B1%82%E6%9E%B6%E6%9E%84)
    
    *   2.1 [端口信号列表](#21-%E7%AB%AF%E5%8F%A3%E4%BF%A1%E5%8F%B7%E5%88%97%E8%A1%A8)
        
        *   2.1.1 [核心控制信号](#211-%E6%A0%B8%E5%BF%83%E6%8E%A7%E5%88%B6%E4%BF%A1%E5%8F%B7)
            
        *   2.1.2 [AHB 配置桥](#212-ahb-%E9%85%8D%E7%BD%AE%E6%A1%A5hxxx--%E4%B8%BB%E5%86%85%E5%AD%98%E6%8E%A5%E5%8F%A3)
            
        *   2.1.3 [AHB DPRAM 桥](#213-ahb-dpram-%E6%A1%A5dpramhxxx--%E6%95%B0%E6%8D%AE%E4%BA%A4%E6%8D%A2%E6%8E%A5%E5%8F%A3)
            
    *   2.2 [时钟域架构](#22-%E6%97%B6%E9%92%9F%E5%9F%9F%E6%9E%B6%E6%9E%84)
        
    *   2.3 [DPRAM 双端口共享与时钟切换](#23-dpram-%E5%8F%8C%E7%AB%AF%E5%8F%A3%E5%85%B1%E4%BA%AB%E4%B8%8E%E6%97%B6%E9%92%9F%E5%88%87%E6%8D%A2)
        
    *   2.4 [内存映射汇总](#24-%E5%86%85%E5%AD%98%E6%98%A0%E5%B0%84%E6%B1%87%E6%80%BB)
        
    *   2.5 [上电启动完整流程](#25-%E4%B8%8A%E7%94%B5%E5%90%AF%E5%8A%A8%E5%AE%8C%E6%95%B4%E6%B5%81%E7%A8%8B)
        
    *   2.6 [SFR 寄存器详解](#26-sfr-%E5%AF%84%E5%AD%98%E5%99%A8%E8%AF%A6%E8%A7%A3)
        
    *   2.7 [使用注意事项与约束](#27-%E4%BD%BF%E7%94%A8%E6%B3%A8%E6%84%8F%E4%BA%8B%E9%A1%B9%E4%B8%8E%E7%BA%A6%E6%9D%9F)
        
3.  [模块层次结构](#3-%E6%A8%A1%E5%9D%97%E5%B1%82%E6%AC%A1%E7%BB%93%E6%9E%84)
    
4.  [RISC-V 标准核心 (RV64IMFD)](#4-risc-v-%E6%A0%87%E5%87%86%E6%A0%B8%E5%BF%83-rv64imfd)
    
    *   4.1 [流水线结构](#41-%E6%B5%81%E6%B0%B4%E7%BA%BF%E7%BB%93%E6%9E%84)
        
    *   4.2 [取指单元 IFU](#42-%E5%8F%96%E6%8C%87%E5%8D%95%E5%85%83-ifu)
        
    *   4.3 [指令译码单元 IDU](#43-%E6%8C%87%E4%BB%A4%E8%AF%91%E7%A0%81%E5%8D%95%E5%85%83-idu)
        
    *   4.4 [执行单元 EXU](#44-%E6%89%A7%E8%A1%8C%E5%8D%95%E5%85%83-exu)
        
    *   4.5 [寄存器文件](#45-%E5%AF%84%E5%AD%98%E5%99%A8%E6%96%87%E4%BB%B6)
        
    *   4.6 [浮点处理单元 FPU](#46-%E6%B5%AE%E7%82%B9%E5%A4%84%E7%90%86%E5%8D%95%E5%85%83-fpu)
        
    *   4.7 [RV64IMFD 指令集](#47-rv64imfd-%E6%8C%87%E4%BB%A4%E9%9B%86)
        
    *   4.8 [CSR 寄存器映射](#48-csr-%E5%AF%84%E5%AD%98%E5%99%A8%E6%98%A0%E5%B0%84)
        
5.  [大数处理单元 BNPU](#5-%E5%A4%A7%E6%95%B0%E5%A4%84%E7%90%86%E5%8D%95%E5%85%83-bnpu)
    
    *   5.1 [BNPU 架构](#51-bnpu-%E6%9E%B6%E6%9E%84)
        
    *   5.2 [BNPU 指令格式与编码](#52-bnpu-%E6%8C%87%E4%BB%A4%E6%A0%BC%E5%BC%8F%E4%B8%8E%E7%BC%96%E7%A0%81)
        
    *   5.3 [BNPU 指令详细说明](#53-bnpu-%E6%8C%87%E4%BB%A4%E8%AF%A6%E7%BB%86%E8%AF%B4%E6%98%8E)
        
6.  [向量处理单元 VPU](#6-%E5%90%91%E9%87%8F%E5%A4%84%E7%90%86%E5%8D%95%E5%85%83-vpu)
    
    *   6.1 [VPU 架构](#61-vpu-%E6%9E%B6%E6%9E%84)
        
    *   6.2 [VPU 寄存器文件](#62-vpu-%E5%AF%84%E5%AD%98%E5%99%A8%E6%96%87%E4%BB%B6)
        
    *   6.3 [VPU 指令编码规则](#63-vpu-%E6%8C%87%E4%BB%A4%E7%BC%96%E7%A0%81%E8%A7%84%E5%88%99)
        
    *   6.4 [VPU 指令完整编码表](#64-vpu-%E6%8C%87%E4%BB%A4%E5%AE%8C%E6%95%B4%E7%BC%96%E7%A0%81%E8%A1%A8)
        
7.  [RSA 硬件加速器](#7-rsa-%E7%A1%AC%E4%BB%B6%E5%8A%A0%E9%80%9F%E5%99%A8)
    
8.  [存储系统](#8-%E5%AD%98%E5%82%A8%E7%B3%BB%E7%BB%9F)
    
9.  [AHB 接口与总线桥](#9-ahb-%E6%8E%A5%E5%8F%A3%E4%B8%8E%E6%80%BB%E7%BA%BF%E6%A1%A5)
    
10.  [状态机与控制逻辑](#10-%E7%8A%B6%E6%80%81%E6%9C%BA%E4%B8%8E%E6%8E%A7%E5%88%B6%E9%80%BB%E8%BE%91)
    
11.  [LLVM 编译器适配](#11-llvm-%E7%BC%96%E8%AF%91%E5%99%A8%E9%80%82%E9%85%8D)
    
12.  [汇编器与工具链](#12-%E6%B1%87%E7%BC%96%E5%99%A8%E4%B8%8E%E5%B7%A5%E5%85%B7%E9%93%BE)
    
13.  [仿真环境](#13-%E4%BB%BF%E7%9C%9F%E7%8E%AF%E5%A2%83)
    
14.  [综合报告](#14-%E7%BB%BC%E5%90%88%E6%8A%A5%E5%91%8A)
    
15.  [主要宏定义与可配置参数](#15-%E4%B8%BB%E8%A6%81%E5%AE%8F%E5%AE%9A%E4%B9%89%E4%B8%8E%E5%8F%AF%E9%85%8D%E7%BD%AE%E5%8F%82%E6%95%B0)
    
16.  [cfgkit 配置工具框架](#16-cfgkit-%E9%85%8D%E7%BD%AE%E5%B7%A5%E5%85%B7%E6%A1%86%E6%9E%B6)
    

---

## 1. 项目概述

SPUV3 是一款面向密码算法加速的**DSA处理器**，实现完整的 **RV64IMFD** 指令集，并在标准 RISC-V 标量核之上集成两套领域专用计算引擎：

*   **BNPU（Big Number Processing Unit）**：大数模运算与对称密码加速，支持 SM1/SM3/SM4/SM7 等国密算法以及 256-bit 模乘、模加、模减、模逆运算。
    
*   **VPU（Vector Processing Unit）**：面向后量子密码（PQC）的向量引擎，支持 Kyber/Dilithium 等格密码所需的 NTT、向量加减、系数归约等操作。
    

此外，独立的 **RSA 硬件加速器**（`rsa_pku_ctrl_top`）通过共享的 DPRAM 与主核协作，完成 RSA 1024/2048 CRT 运算。

> **编码说明**：BNPU 和 VPU 扩展指令编码空间与 RISC-V 标准**完全不兼容**，须使用专用汇编器 `as/src/dcf_spu_as_cmd.py` 生成机器码。RTL 源文件中以 `spuv3_` 开头的命名系历史遗留，不影响当前版本所指代的 SPUV3 架构。

### 主要特性

| 特性 | 规格 |
| --- | --- |
| ISA | RV64IMFD（单发射，in-order） |
| 流水线深度 | 4 级（IF → ID → EX → WB） |
| 分支预测 | SPUV3-M：关闭（`BranchPredictor=0`）；SPUV3-H：静态分支预测 + BPU |
| 通用寄存器 | 32 × 64-bit GPR (x0–x31) |
| 浮点寄存器 | 32 × 64-bit FPR (f0–f31) |
| 大数寄存器 | 64 × 256-bit BNPR (b0–b63) |
| 向量寄存器 | 32 × 320-bit VR (v0–v31)（实体 9×320-bit，其余通过 BNPR remap 实现） |
| ILM | 128 KB（32-bit 宽） |
| DLM | 64 KB（256-bit 宽） |
| DPRAM | 32 KB（256-bit 双端口，用于与主机 CPU 交换数据） |
| RSA RAM | 16 KB（划分自 DPRAM 区域） |
| 外部接口 | 双 AHB-Lite（主内存桥 + DPRAM 桥） |
| 综合工艺 | 55nm / 28nm |
| 典型频率 | 100 MHz @ 55nm，600 MHz @ 28nm |

### 架构设计理念

SPUV3 定位为**同 die 紧耦合密码协处理器**（coprocessor），而非独立 SoC 或共享主 CPU 流水线的功能单元。这一选择基于以下工程判断：

**为什么不做"共享主 CPU 流水线"？** 300+ 条 XPqc 自定义指令延迟差异巨大——`vpqcadd16` 单周期，`sm2_padd` 几百周期，`vkybrejuni` NTT 批处理几千周期。强行塞进主流水线会让主 CPU 在每一条长延迟 XPqc 指令上停等，丧失乱序核的吞吐优势。

**为什么不做"独立 IP + AXI 总线"？** AXI 协议头开销大、延迟高（~50 cycle 起步），不适合细粒度 crypto kernel 调用。SPUV3 通过专用 coprocessor port 与主核通信，dispatch 延迟压到个位数 cycle——XPqc 指令对主核重命名/ROB 看来就像普通 ALU 指令，按程序顺序 commit，不需要显式 fence。

**典型编程模型**（主 CPU 视角）：

```plaintext
主 CPU:
  1. RV64I 指令准备数据指针、循环计数
  2. csrrw 配置 vmask / BNPCFG / NTTQ 等 CSR
  3. XPqc load 指令把数据从 DLM/DPRAM 搬到 B/V 寄存器
  4. 执行 XPqc 计算序列（NTT 蝶形 / SM2 点乘 / Keccak 压缩等）
  5. XPqc store 指令把结果回写 DLM/DPRAM

SPUV3 侧:
  - 接收 coprocessor port 上的指令 + 源寄存器
  - 内部 RA + 多管线调度执行（BNPU/VPU/RSA 独立管线）
  - 按程序顺序回送 commit 信号给主核
  - 不抛异常、不报错（裸机设计保证操作合法）

```

### 密码算法家族与指令映射

SPUV3 的 BNPU/VPU/SYM/SBOX/RSA 五大执行单元覆盖四大密码算法家族：

| 算法家族 | 典型算法 | 主要执行单元 | 代表性指令 |
| --- | --- | --- | --- |
| **PQC 格密码** | Kyber-512/768/1024, Dilithium-2/3/5 | VPU | `vpqcadd32`, `vpqcmrdc32`, `vkybrejuni`, `vdilichknrmv1`, `xorv3vx`, `nttarithvx` |
| **PQC 哈希** | SHA-3, SHAKE-128/256, Keccak-f\[1600\] | VPU + BNPU | `vdilikeccakshf`, `vdilipwr2rud`, `vdilirejuni` |
| **国密 SM 系列** | SM1, SM2, SM3, SM4, SM7, SM9 | BNPU + SYM + SBOX | `sm3rd`, `sm4e_ecb`, `sm1e_kg`, `tadd`, `ssrol`, `sbox.lh8` |
| **传统密码** | AES-128/256, ECC P-256/P-384, RSA-1024/2048 | BNPU + RSA | `mulmod`, `summod`, `invmod`; RSA 通过 CSR 接口独立调度 |

> 总计 ~300 条自定义指令。详细编码表见第 5 节（BNPU）与第 6 节（VPU）。

### Falcon f64 FE first integration 扩展草案

Falcon 的 FFT/IFFT 热点是 f64 复数 butterfly 与 twiddle 乘法。第一版扩展建议不把 FE 做成独立 AXI IP，也不通过 CSR 搬运 320-bit 数据，而是作为 VPU/XPqc 路径中的多周期子执行单元接入。这样可以复用现有 VPU register file、XPqc decode/dispatch、ordered commit 和 DLM/DPRAM 数据流。

推荐新增四条 VPU FE 指令：

| 指令 | 作用 | 写回行为 |
| --- | --- | --- |
| `vffeloadwim` | 预加载 twiddle 虚部 `w_im` 到 FE wrapper 内部保持寄存器 | 不写 VR |
| `vffestart` | 以 `a_re/a_im/b_re/b_im/w_re` 启动一次 FE butterfly 或 complex op | 不写 VR |
| `vfferead` | 根据 `read_sel` 读取 FE wrapper 内部结果 | 写 VR |
| `vffeclear` | 清空 FE wrapper 内部状态 | 不写 VR |

第一版推荐汇编顺序：

```text
vffeloadwim  v_tw_im
vffestart    v_a_re, v_a_im, v_b_re, v_b_im, v_tw_re
vfferead     v_y0_re, 0
vfferead     v_y0_im, 1
vfferead     v_y1_re, 2
vfferead     v_y1_im, 3
vffeclear
```

`vfferead` 的 `read_sel` 编码为：`0 -> y0_re`、`1 -> y0_im`、`2 -> y1_re`、`3 -> y1_im`。`vffestart` 和 `vfferead` 按长时延 VPU 指令处理，参与 `busy/done/stall` 互锁；只有 `vfferead` 可以拉高 VPU register write enable。

SPUV3 VPU 的逻辑 VR 宽度是 320-bit，即 10 个 32-bit lane。FE 使用 f64 数据时，一个 f64 lane 占两个 32-bit lane，因此一个 VR 最多容纳 5 个 f64 lane：

```text
f64 lane i -> 32-bit lane {2*i, 2*i+1}
vmask = 10 -> 5 个 f64 lane 全开
vmask = 8  -> 4 个 f64 lane，适合 256-bit remap/BNPR 模式
```

第一版 FE wrapper 应保证 inactive f64 lane 不产生旧值污染。后续如果引入 FE local buffer、twiddle cache 或 streaming preload/drain，应保持上述软件可见指令语义不变，只在内部提升吞吐。

---

## 2. 顶层架构

![spuv3_arch.png](https://alidocs.oss-cn-zhangjiakou.aliyuncs.com/res/Mp7ld7bZooWyMOBQ/img/077d82d8-4fc8-48fc-804c-99b6ee37186b.png)

SPUV3 以 `spuv3_subsystem` 为顶层集成模块，对外暴露以下接口：**核心控制信号**、**AHB 配置桥**（主内存）、**AHB DPRAM 桥**（数据交换）、**SRAM 时钟**、**存储器密钥**。以下详细说明每个信号的用法、时序和约束。

### 2.1 端口信号列表

#### 2.1.1 核心控制信号

| 信号 | 方向 | 宽度 | 时钟域 | 描述 |
| --- | --- | --- | --- | --- |
| `clk` | I | 1 | — | Core 主时钟。SPU 核、VPU、BNPU、RSA 加速器等所有内部逻辑均工作于此域。 |
| `rst_n` | I | 1 | `clk` | 系统复位（低有效）。复位所有内部状态。 |
| `stop_on_reset` | I | 1 | `clk` | **一次性**上电 hang 信号。默认 HIGH：系统挂起，允许通过 AHB 配置 ILM/DLM。外部拉 LOW 后释放复位，core 开始取指执行。再次拉高无效。 |
| `spuv3_ilm_clk` | I | 1 | — | ILM SRAM 专用时钟。 |
| `spuv3_dlm_clk` | I | 1 | — | DLM SRAM 专用时钟。 |
| `spuv3_busy` | O | 1 | `clk` | HIGH = SPU 正在执行算法。此时必须给 core、ILM、DLM、DPRAM 双口及所有被调用加速器供给时钟。 |
| `spuv3_alg_done` | O | 1 | `clk` | 算法完成中断。内部硬件拉高，软件通过写 SFR INT 清零。 `alg_done = done_int & int_en`。 |
| `spuv3_mstatus` | O | 32 | `clk` | 系统状态字：`[31]`\=done, `[30]`\=start, `[29:8]`\=result\_len/addr 等, `[7:0]`\=opcode（最多 256 种算法）。 |
| `ram_key[15:0]` | I | 16 | `clk` | DPRAM/内部 RAM 加密密钥（`SPUV3_MEM_ENC_ENABLE_OUTER` 时使用，否则接 0）。 |
| `rom_key[15:0]` | I | 16 | `clk` | ILM ROM 加密密钥（`SPUV3_MEM_ENC_ENABLE_OUTER` 时使用，否则接 0）。 |
| `test_mode` | I | 1 | — | DFT 测试模式。旁路 `gnrl_async_clkmux` 内部的 clock gate，时钟直通。正常运行时接 0。 |

#### 2.1.2 AHB 配置桥（`Hxxx`）— 主内存接口

用于 `stop_on_reset` 期间配置 ILM/DLM，以及运行时读写 SFR 寄存器。

| 信号 | 方向 | 宽度 | 时钟域 | 描述 |
| --- | --- | --- | --- | --- |
| `hclk` | I | 1 | — | AHB 总线时钟。**要求与** `**clk**` **同步**（同源 PLL）。 |
| `hresetn` | I | 1 | `hclk` | AHB 总线复位。 |
| `hsel` | I | 1 | `hclk` | AHB 从设备选择。 |
| `hready` | I | 1 | `hclk` | AHB 传输就绪。 |
| `haddr[23:0]` | I | 24 | `hclk` | AHB 字节地址。 |
| `hwrite` | I | 1 | `hclk` | 1=写, 0=读。 |
| `htrans[1:0]` | I | 2 | `hclk` | AHB 传输类型。 |
| `hsize[2:0]` | I | 3 | `hclk` | 传输位宽：0=8b, 1=16b, 2=32b。 |
| `hburst[2:0]` | I | 3 | `hclk` | AHB burst 类型。 |
| `hprot[3:0]` | I | 4 | `hclk` | 保护控制。 |
| `hwdata[31:0]` | I | 32 | `hclk` | 写数据。 |
| `hrdata[31:0]` | O | 32 | `hclk` | 读数据。 |
| `hreadyout` | O | 1 | `hclk` | 设备就绪。 |
| `hresp` | O | 1 | `hclk` | 传输响应（0=OK, 1=ERROR）。 |

#### 2.1.3 AHB DPRAM 桥（`DPRAMHxxx`）— 数据交换接口

Port B 通道，用于 Host CPU ↔ SPUV3 输入/输出数据搬运（通常由 DMA 驱动）。**所有时钟同源**（同一 PLL，允许整数分频），`gnrl_async_clkmux` 在同步模式下提供 glitch-free 时钟切换。

| 信号 | 方向 | 宽度 | 时钟域 | 描述 |
| --- | --- | --- | --- | --- |
| `dpram_hclk` | I | 1 | — | DPRAM AHB 总线时钟。**必须与** `**clk**` **同源**。 |
| `dpram_hresetn` | I | 1 | `dpram_hclk` | DPRAM AHB 总线复位。 |
| `dpram_hsel` | I | 1 | `dpram_hclk` | AHB 从设备选择。 |
| `dpram_hready` | I | 1 | `dpram_hclk` | AHB 传输就绪。 |
| `dpram_haddr[23:0]` | I | 24 | `dpram_hclk` | AHB 字节地址。**必须 32-bit 对齐**（低 2 位 = 0）。 |
| `dpram_hwrite` | I | 1 | `dpram_hclk` | 1=写, 0=读。 |
| `dpram_htrans[1:0]` | I | 2 | `dpram_hclk` | AHB 传输类型。 |
| `dpram_hsize[2:0]` | I | 3 | `dpram_hclk` | 传输位宽（典型 32-bit）。 |
| `dpram_hburst[2:0]` | I | 3 | `dpram_hclk` | AHB burst 类型。 |
| `dpram_hprot[3:0]` | I | 4 | `dpram_hclk` | 保护控制。 |
| `dpram_hwdata[31:0]` | I | 32 | `dpram_hclk` | 写数据。 |
| `dpram_hrdata[31:0]` | O | 32 | `dpram_hclk` | 读数据（含 1 拍 AHB bridge 延迟 + 1 拍 DPRAM 读延迟）。 |
| `dpram_hreadyout` | O | 1 | `dpram_hclk` | 设备就绪。 |
| `dpram_hresp` | O | 1 | `dpram_hclk` | 传输响应。 |

### 2.2 时钟域架构

SPUV3 subsystem 包含 **4 个时钟输入，全部来自同一时钟源**（同一 PLL，允许整数分频）：

```plaintext
            ┌──────────────────────────────────────--┐
            │        单一同步时钟域（同源 PLL）        │
            │                                        │
            │  clk (600MHz max)  ← Core / RSA / VPU  │
            │  hclk              ← AHB Config Bridge │
            │  dpram_hclk        ← AHB DPRAM Bridge  │
            │  spuv3_ilm_clk     ← ILM SRAM          │
            │  spuv3_dlm_clk     ← DLM SRAM          │
            │                                        │
            │  所有时钟同源 → STA 可分析跨域路径        │
            │  → 无需 CDC 同步器                      │
            └──────────────────────────────────────--┘

```

**设计原理**：SPUV3 挂载在 Host CPU 的总线上，所有 AHB 接口共享 Host 总线时钟（或其整数分频）。不存在独立时钟源，因此不存在真正的异步时钟域。

**RTL 实现规则**（`spuv3_subsystem.v:19-22`）：

```verilog
// Clock Policy: All clocks (clk, spuv3_ilm_clk, spuv3_dlm_clk, hclk, dpram_hclk)
// must be from the same PLL source with integer frequency ratios.
// STA covers all cross-domain timing paths — no CDC synchronizers needed.
// Each clock domain uses its own reset: clk→rst_n, hclk→hresetn, dpram_hclk→dpram_hresetn.

```

**跨域信号汇总**（均经 STA 验证，无需同步器）：

| 信号 | 方向 | 位宽 | 时钟周期 | STA 安全性 |
| --- | --- | --- | --- | --- |
| `spuv3_cfg_en` | hclk→clk | 1-bit | 单 hclk 周期脉冲 | ✅ STA 保证 setup/hold |
| `spuv3_busy` | hclk→clk | 1-bit | 电平信号 | ✅ 同源，clock MUX sync mode |
| `spuv3_mstatus_o[31:0]` | clk→hclk | 32-bit | 多 bit 总线 | ✅ 同源整数分频 |
| `spuv3_cfg_clr` (=mstatus\[31\]) | clk→hclk | 1-bit | strobe 信号 | ✅ STA 保证 |
| RSA DPRAM B 接口 | clk→clk | 全位宽 | busy=1 时 B 口 = clk | ✅ 完全同步 |

#### 时钟约束表

| 时钟 | 同源要求 | 典型频率 (28nm) | 说明 |
| --- | --- | --- | --- |
| `clk` | — 主时钟 | 600 MHz | Core 基准。来自 PLL ÷2 (1.2GHz source)。 |
| `spuv3_ilm_clk` | **同源** | 600 MHz（或 ÷2=300MHz） | ILM SRAM。通常与 `clk` 同频或整数分频。 |
| `spuv3_dlm_clk` | **同源** | 600 MHz（或 ÷2=300MHz） | DLM SRAM。通常与 `clk` 同频或整数分频。 |
| `hclk` | **同源** | 150–300 MHz | AHB 配置桥。28nm AHB 上限 ~300MHz，来自同一 PLL 的较低分频。 |
| `dpram_hclk` | **同源** | 150–300 MHz | DPRAM AHB 桥。Host 总线时钟，来自同一 PLL。 |

> **"同源"的含义**：所有时钟由同一个 PLL 生成，频率为整数倍关系。STA（静态时序分析）可以覆盖所有跨域时序路径。与"异步"（独立时钟源，频率/相位无确定关系）根本不同。

#### 时钟供给纪律

| 系统状态 | 必须供给时钟的模块 | 原因 |
| --- | --- | --- |
| `spuv3_busy=1`（算法执行中） | `clk`, `spuv3_ilm_clk`, `spuv3_dlm_clk`, `dpram_hclk`, `hclk` | Core 执行 + 加速器访问 DPRAM + AHB 配置桥（状态机） |
| `spuv3_busy=0`（空闲） | `**hclk**`（必须）、`clk`（建议保持） | FSM 在 `hclk` 域，等待 Host 写 SFR 启动；`clk` 需运行以接收 `cfg_enable` 脉冲。`spuv3_ilm_clk`/`spuv3_dlm_clk`/`dpram_hclk` 可按功耗门控。 |

### 2.3 DPRAM 双端口共享与时钟切换

系统 DPRAM（32 KB, 256-bit 真双端口）被 3 方共享。所有时钟同源，`gnrl_async_clkmux` 配置为**同步模式**提供 glitch-free 时钟切换：

```plaintext
Port A (clk域)                    Port B (同源时钟域)
   ┌──────┴──────┐                ┌──────┴──────┐
 SPU Core    RSA Accel         RSA Accel    Host CPU (AHB)
(clk)       (clk)             (clk)        (dpram_hclk, 同源)
     ↓           ↓                ↓              ↓
  ┌─────────────────┐      ┌─────────────────────────┐
  │ rsa_ram_ena ?   │      │ gnrl_async_clkmux       │
  │   RSA : SPU     │      │ ASYNC_CLK_MUX = "no"    │
  └────────┬────────┘      │ select = spuv3_busy     │
           ↓               │ clk0=dpram_hclk         │
      DPRAM Port A         │ clk1=clk                │
      (clk)                └──────────┬──────────────┘
                                      ↓
                                 DPRAM Port B
                           (clk when busy,
                            dpram_hclk when idle)

```

#### Port A MUX

```verilog
assign dpram_en_a = rsa_ram_ena | spu_dpram_en_a;  // RSA 优先

```

*   SPU Core 和 RSA 共享 `clk` 域 → 完全同步
    
*   RSA 忙碌时（`rsa_ctrl_busy=1`），SPU Core **禁止**访问 DPRAM Port A
    
*   硬件含仿真断言 (`spuv3_subsystem.v:969`)：违反时 `$finish`
    

#### Port B MUX + `gnrl_async_clkmux`（同步模式）

```verilog
// 数据通路 MUX（组合逻辑）
assign dpram_en_b = rsa_ram_enb | ahb_dpram_en_b;   // RSA 优先

// 时钟 MUX（同步模式 — glitch-free 门控，无握手延迟）
gnrl_async_clkmux #(.ASYNC_CLK_MUX("no")) u_dpram_b_clkmux (
    .clk_in0 (dpram_hclk),    // idle: Host AHB 时钟（同源）
    .clk_in1 (clk),           // busy: Core 时钟（同源）
    .select  (spuv3_busy),
    .clk_out (dpram_clk_b_int)
);

```

**工作原理**：

*   `busy=0`（空闲）：B 口时钟 = `dpram_hclk`。Host CPU 通过 AHB 读写 DPRAM。
    
*   `busy=1`（忙碌）：B 口时钟 = `clk`。RSA 加速器访问 B 口，与 Port A 完全同域。
    
*   同步模式下时钟切换无握手延迟——`gcK` latch 门控确保无毛刺。
    

**应用层保证**（Host 软件必须遵守）：

1.  Host CPU **仅在** `spuv3_alg_done` 中断后或算法未启动前访问 DPRAM B 口
    
2.  算法运行期间（`spuv3_busy=1`），Host **不得**访问 DPRAM B 口
    

### 2.4 内存映射汇总

#### 2.4.1 SPU Core 数据总线视角（哈佛架构）

```plaintext
0x0000_0000 ─────────── DLM (64 KB, 256-bit)
0x0001_0000 ─────────── DPRAM Port A (32 KB, 256-bit)
                        ├─ RSA 工作区（低 16 KB）
                        └─ 通用数据区

```

#### 2.4.2 AHB 配置桥视角（Host → ILM/DLM/SFR）

```plaintext
0x0000_0000 ─────────── ILM (128 KB, 32-bit)
                          stop_on_reset=1 时可写
0x0002_0000 ─────────── DLM (64 KB, AHB 32→256-bit 转换)
                          stop_on_reset=1 时可写
0x0003_0000 ─────────── SFR_CFG (mstatus 映射)
0x0003_0004 ─────────── SFR_CFG_INT (中断控制)

```

#### 2.4.3 AHB DPRAM 桥视角（Host → 数据交换）

```plaintext
0x0000_0000 ─────────── DPRAM Port B (32 KB)
0x0000_8000 ─────────── (越界)

```
> **注意**：AHB 侧 DPRAM 地址从 0 开始独立编址，与 SPU Core 数据总线地址空间不同。Host 侧的 `dpram_haddr=0` 对应 DPRAM 物理第 0 行。

### 2.5 上电启动完整流程

```plaintext
时序图（文字版）:

1. 上电
   │  clk 运行，rst_n=0, stop_on_reset=1 (默认 HIGH)
   │  系统处于 hang 状态
   ▼
2. 释放复位
   │  rst_n → 1
   │  stop_on_reset 保持为 1
   │  AHB 配置桥可用（hclk 时钟域）
   ▼
3. AHB 配置 ILM（固件）
   │  haddr = 0x0000_0000 ~ 0x0001_FFFF
   │  hwrite=1, 逐 32-bit 写入固件
   ▼
4. AHB 配置 DLM（常数/初始化数据）
   │  haddr = 0x0002_0000 ~ 0x0002_FFFF
   │  hwrite=1, 逐 32-bit 写入
   ▼
5. AHB 配置 DPRAM（算法输入数据）
   │  通过 DPRAM AHB 桥: dpram_haddr = 0x0000_0000 ~
   │  dpram_hwrite=1, 逐 32-bit 写入
   │  （可选：也可在步骤 7 之后、步骤 8 之前由 DMA 写入）
   ▼
6. 释放 stop_on_reset
   │  stop_on_reset → 0
   │  Core 复位释放，PC=0，开始取指
   │  ⚠️ stop_on_reset 此后失效，再拉高无效
   ▼
7. 配置中断使能（可选）
   │  haddr = SFR_CFG_INT_BASE_ADDR
   │  hwdata = 0x0000_0001 (int_en=1)
   ▼
8. 启动算法
   │  haddr = SFR_CFG_BASE_ADDR
   │  hwdata = {2'h0, result_len[21:0], opcode[7:0]}
   │  spuv3_busy → 1
   ▼
9. 等待完成
   │  方式 A: 轮询 spuv3_mstatus[31] 或 SFR_CFG
   │  方式 B: 等待 spuv3_alg_done 中断
   ▼
10. 读取结果
    │  dpram_haddr = 0x0000_0000 ~ （DPRAM B 口）
    │  hwrite=0, 逐 32-bit 读出结果
    ▼
11. 清除中断（如使用中断方式）
    │  haddr = SFR_CFG_INT_BASE_ADDR
    │  hwdata = 0x0000_0003 (int_en=1, clear=1)
    │  spuv3_alg_done → 0
    │  spuv3_busy → 0
    ▼
12. 可回到步骤 8 再次启动（无需重新配置 ILM/DLM）

```

### 2.6 SFR 寄存器详解

| 地址偏移 | 寄存器 | 位域 | 访问 | 描述 |
| --- | --- | --- | --- | --- |
| `SFR_CFG_BASE_ADDR` | `spuv3_cfg` | `[31]`\=done, `[30]`\=start, `[29:8]`\=result\_len, `[7:0]`\=opcode | RW | `spuv3_mstatus` 的 AHB 映射。写 `[30]=1` 启动算法。 |
| `SFR_CFG_INT_BASE_ADDR` | `spuv3_cfg_int` | `[0]`\=int\_en, `[1]`\=done\_int | RW | 中断控制。写 `0x1` 使能中断，`0x0` 关闭，`0x3` 清除中断。 |

**中断逻辑**：

```verilog
spuv3_alg_done = spuv3_done_int & spuv3_int_en;  // bit1 & bit0

```

`spuv3_done_int` 由硬件在算法完成时自动置 1。Host 通过写 `0x3` 清零（同时保持 int\_en=1）。

### 2.7 使用注意事项与约束

#### 必须遵守

1.  `**stop_on_reset**` **仅一次有效**：仅在系统首次上电后拉低起效。后续再拉高系统无反应。不能用于"暂停/恢复"。
    
2.  **时钟供给纪律**：`spuv3_busy=1` 时，`clk`、`spuv3_ilm_clk`、`spuv3_dlm_clk`、`dpram_hclk`、`hclk` **必须**全部运行。空闲时必须保持 `hclk`（FSM 和 AHB 配置桥依赖此时钟），`clk` 建议保持（接收 `cfg_enable` 脉冲启动算法）。
    
3.  **DPRAM B 口访问时序**：Host CPU **仅**在 `spuv3_alg_done` 后或算法启动前访问 DPRAM B 口。算法运行期间访问行为未定义（AHB bridge 可能不响应）。
    
4.  **RSA + SPU Core 互斥**：RSA 忙碌（`rsa_ctrl_busy=1`）时，SPU Core **不得**访问 DPRAM Port A。硬件含断言保护。
    
5.  **AHB 配置仅在** `**stop_on_reset=1**` **时可写 ILM/DLM**：`stop_on_reset=0` 后，AHB 对 ILM/DLM 的写操作被忽略（`h_sel_ilm`/`h_sel_dlm` 均为 0）。
    
6.  **所有时钟必须同源**：所有时钟（`clk`, `hclk`, `dpram_hclk`, `spuv3_ilm_clk`, `spuv3_dlm_clk`）须来自同一 PLL。允许整数分频，但不得使用独立时钟源。
    
7.  **每个时钟域使用各自的复位**：`clk` 域使用 `rst_n`，`hclk` 域使用 `hresetn`，`dpram_hclk` 域使用 `dpram_hresetn`。不得混用。RTL 中所有 `always` 块已按此规则统一。
    
8.  **DPRAM AHB 地址对齐**：`dpram_haddr` 低 2 位应为 0（32-bit 对齐）。内部通过 `mem_addr[2:0]` 做 256-bit 子字段选择。
    

#### 推荐做法

1.  仿真时将 `clk`, `spuv3_ilm_clk`, `spuv3_dlm_clk`, `hclk`, `dpram_hclk` 全部接同一个时钟源（如现有 `spuv3_system_tb.sv` 的做法），简化调试。
    
2.  真实芯片中所有时钟来自同一 PLL，`gnrl_async_clkmux` 同步模式处理 B 口时钟切换。
    
3.  用 `spuv3_busy` 作为时钟门控的使能信号——当 busy=1 时确保所有依赖时钟开启；busy=0 时可关闭 `dpram_hclk` 和 `spuv3_dlm_clk` 等以省功耗。
    
4.  算法结果 readback 后应通过写 `0x3` 到 SFR\_CFG\_INT 清除中断，为下一次启动做好准备。
    

#### 禁止行为

*   ❌ 在 `spuv3_busy=1` 期间通过 AHB 访问 DPRAM B 口
    
*   ❌ 在 RSA 忙碌期间让 SPU Core 访问 DPRAM Port A
    
*   ❌ `stop_on_reset` 拉低后再次拉高
    
*   ❌ 在 `stop_on_reset=0` 后通过 AHB 配置桥写 ILM/DLM
    

---

## 3. 模块层次结构

```plaintext
spuv3_subsystem                顶层集成模块
├── spuv3_core                 SPUV3 处理器核心
│   ├── spuv3_ifu              取指单元
│   ├── spuv3_idu              指令译码单元（含 BNPU/VPU 扩展译码）
│   ├── spuv3_exu              执行单元（ALU / MULDIV / FPU / BNAU / SYM / MEM）
│   ├── spuv3_bnregfile        64×256-bit 大数寄存器堆
│   ├── spuv3_fpu_wrap         FPU（RV64F/D）
│   ├── spuv3_csr_reg          CSR 寄存器组
│   └── vpu_top                VPU（PQC 向量引擎，Kyber/Dilithium）
├── spuv3_mems                 片上存储（ILM 128 KB / DLM 64 KB / DPRAM 32 KB）
├── atcrambrg200 (×2)          AHB-to-SRAM 桥（主内存桥 + DPRAM 桥）
├── spuv3_cfg_sfr              SFR 配置寄存器
└── rsa_pku_ctrl_top           RSA 公钥加速器

```
---

## 4. RISC-V 标准核心 (RV64IMFD)

### 4.1 流水线结构

SPUV3 main 实现了**单发射、顺序执行**的 4 级流水线：

```plaintext
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Stage 1 │    │  Stage 2 │    │  Stage 3 │    │  Stage 4 │
│    IF    │ →  │    ID    │ →  │    EX    │ →  │    WB    │
│  (IFU)   │    │  (IDU)   │    │  (EXU)   │    │ (commit) │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
     ↕               ↕               ↕
 spuv3_ifu     spuv3_bp_stage  spuv3_idu_exu
               (IF/ID buffer)  (ID/EX buffer)

```

*   **停顿控制**：4 个停顿点（PC/IF/ID/EX），由 `spuv3_pipe_ctrl` 模块管理
    
*   **冲刷**：控制流冲突（分支误预测、跳转）时全流水线冲刷并重定向 PC
    
*   **数据前递**：EX 阶段结果直接前递到 ID 寄存器读出口，消除 RAW 停顿
    
*   **BNPU/VPU 长时延指令**：通过 EX 阶段握手停顿（handshake）等待多周期运算完成
    

### 4.2 取指单元 IFU

文件：`rtl/spuv3_ifu.v`

**功能**：

*   3 状态 FSM：`S_RESET` → `S_FETCH` → `S_VALID`
    
*   连续顺序取指，输出 32-bit 指令到流水线
    
*   接收分支预测结果（`prdt_taken_i` / `prdt_addr_i`）并发起投机取指
    
*   接收流水线冲刷信号（`flush_i` / `flush_addr_i`）恢复正确 PC
    
*   与 ILM 通过 req/gnt/rvalid 握手接口交互（吞吐量 1 指令/拍）
    

**接口**：

*   指令总线：`instr_req_o`, `instr_addr_o[31:0]`, `instr_rdata_i[31:0]`
    
*   向 IDU：`inst_o[31:0]`, `pc_o[31:0]`, `inst_valid_o`
    

### 4.3 指令译码单元 IDU

文件：`rtl/spuv3_idu.v`

**功能**：

*   完整的 RV64IMFD 指令译码，生成 `SPU_DECINFO` 多比特控制总线
    
*   同时对 BNPU 扩展指令（8-bit opcode 格式）和 VPU 扩展指令译码
    
*   浮点指令通过 `FloatDecodeModule.sv` 生成 62-bit one-hot 信号传递给 FPU wrap
    
*   寄存器读端口：rs1/rs2/rs3（GPR），bnrs1/bnrs2/bnrs3（BNPR），vs1~vs5（VR），fpu\_rs1/rs2/rs3（FPR）
    
*   立即数生成：I/S/B/U/J 型立即数符号扩展到 64-bit
    
*   `spuv3_bp_stage` 在 ID 阶段根据 JALR/JAL/BEQ 等指令做静态分支预测
    

**译码信息总线**（`SPU_DECINFO`，最大宽度由 VPU 组决定）：

| 位域 | 含义 |
| --- | --- |
| `[3:0]` | 指令组别：ALU=1, BJP=2, MULDIV=3, CSR=4, MEM=5, SYS=6, BN=7, VPU=8 |
| 后续 bit | 组内 one-hot 操作码 |

### 4.4 执行单元 EXU

文件：`rtl/spuv3_exu.v`

**功能概览**：

| 子单元 | 文件 | 功能 |
| --- | --- | --- |
| ALU | `spuv3_exu_alu_datapath.v` | 64-bit 加减、逻辑、移位、比较；LUI/AUIPC；SEXTW/ADDIW 等 W 型指令 |
| MULDIV | `spuv3_exu_muldiv.v` | RV64M 乘除法；单周期乘法器 + 多周期除法器 |
| SYM | `spuv3_exu_sym.v` | 单周期对称密码辅助：TADD/TANDXOR/TNANDXOR/RR64L/RR64H/SSROL/SRO/SSRO |
| BNAU | `spuv3_exu_bnau_*.v` | 256-bit 模运算；SM1/SM3/SM4/SM7 密码轮函数 |
| MEM | `spuv3_exu_mem.v` | 字节/半字/字/双字加载存储；256-bit 大数访存；向量访存 |
| FPU | `spuv3_fpu_wrap.sv` | 单/双精度浮点 |
| VPU | `vpu/vpu_top.sv` | 格密码向量运算（详见第6节） |
| COMMIT | `spuv3_exu_commit.v` | 写回 GPR/FPR/BNPR/VR；更新 mstatus；控制流重定向 |

**EXU CSR 配置输入**（影响 BNPU 和 VPU 行为）：

*   `csr_bnpcfg_i[255:0]`：BNPU 模数 P（素数）
    
*   `csr_bnmmcfg_i[255:0]`：BNPU Montgomery 参数
    
*   `csr_bnrrcfg_i[255:0]`：BNPU Montgomery R²
    
*   `csr_nttq_i/nttqinv_i/nttimm_i[31:0]`：VPU NTT 模数及参数
    
*   `csr_vmask_i[31:0]`：向量操作掩码
    
*   `csr_coeffi0~31_i[255:0]`：PQC 算法系数（32 组，每组 256-bit）
    

### 4.5 寄存器文件

| 寄存器堆 | 文件 | 深度 | 宽度 | 读端口 / 写端口 |
| --- | --- | --- | --- | --- |
| GPR | `spuv3_rvregfile.v` | 32 | 64-bit | 3R / 1W |
| FPR | `spuv3_fpregfile.v` | 32 | 64-bit | 3R / 1W |
| BNPR | `spuv3_bnregfile.v` | 64 | 256-bit | 3R / 1W（+VPU remap 接口） |
| VR（vregfile） | `vpu/vpu_vregfile.sv` | 9（实体） | 320-bit | 5R / 1W |

**向量寄存器复用机制**（宏 `SPUV3_VREGFILE_REMAP2BNREG`）：

*   v0~v8：独立物理 vregfile，完整 320-bit 宽度
    
*   v9~v31：映射到 BNPR b32~b63（利用 BNPR 的 256-bit 存储，320-bit 有效宽度仅 256-bit，高 64-bit 补零）
    
*   读取时按寄存器地址判断来源：地址 < 9 取 vregfile，地址 ≥ 9 且 remap 使能时取 bnregfile
    

**⚠️ b0 与 v0 的关键区别**（影响记分板与写回逻辑）：

| 寄存器 | 行为 | 写操作 | 读操作 |
| --- | --- | --- | --- |
| `b0` | 硬连线 256-bit 常量 0（类似 RISC-V `x0`） | 静默丢弃，不更新寄存器 | 始终返回 0 |
| `v0` | 普通可读写寄存器 | 正常生效 | 返回当前值 |

*   `bn_isboard(0)` 始终钉为 `true`（b0 永远可读，不需等待写回），向 b0 写入时**不清除**记分板位
    
*   `vpu_isboard(0)` 按普通方式处理（v0 有真实写回）
    

### 4.6 浮点处理单元 FPU

文件：`rtl/spuv3_fpu_wrap.sv`, `rtl/FloatDecodeModule.sv`

通过 `spuv3_fpu_wrap.sv` 封装后集成到 EXU。

**支持精度**：单精度（SP, 32-bit）/ 双精度（DP, 64-bit）

**支持舍入模式**（FRM CSR）：

| 值 | 模式 | 说明 |
| --- | --- | --- |
| 000 | RNE | Round to Nearest, ties to Even |
| 001 | RTZ | Round towards Zero |
| 010 | RDN | Round Down（towards -∞） |
| 011 | RUP | Round Up（towards +∞） |
| 100 | RMM | Round to Nearest, ties to Max Magnitude |
| 111 | DYN | Dynamic（从指令 rm 字段选择） |

**FPU 异常标志**（FFLAGS CSR）：`NV`（无效操作）| `DZ`（除零）| `OF`（溢出）| `UF`（下溢）| `NX`（不精确）

**62-bit one-hot 浮点指令索引**（`FloatDecodeModule` 输出 `inst_oh[61:0]`）：

| 位 | 指令 | 位 | 指令 | 位 | 指令 |
| --- | --- | --- | --- | --- | --- |
| 0 | FADD.S | 20 | FLW | 40 | FEQ.D |
| 1 | FSUB.S | 21 | FSW | 41 | FLT.D |
| 2 | FMUL.S | 22 | FMADD.S | 42 | FLE.D |
| 3 | FDIV.S | 23 | FMSUB.S | 43 | FCLASS.D |
| 4 | FSQRT.S | 24 | FNMSUB.S | 44 | FCVT.D.W |
| 5 | FSGNJ.S | 25 | FNMADD.S | 45 | FCVT.D.WU |
| 6 | FSGNJN.S | 26 | FADD.D | 46 | FLD |
| 7 | FSGNJX.S | 27 | FSUB.D | 47 | FSD |
| 8 | FMIN.S | 28 | FMUL.D | 48 | FMADD.D |
| 9 | FMAX.S | 29 | FDIV.D | 49 | FMSUB.D |
| 10 | FCVT.W.S | 30 | FSQRT.D | 50 | FNMSUB.D |
| 11 | FCVT.WU.S | 31 | FSGNJ.D | 51 | FNMADD.D |
| 12 | FMV.X.W | 32 | FSGNJN.D | 52 | FCVT.L.S |
| 13 | FEQ.S | 33 | FSGNJX.D | 53 | FCVT.LU.S |
| 14 | FLT.S | 34 | FMIN.D | 54 | FCVT.S.L |
| 15 | FLE.S | 35 | FMAX.D | 55 | FCVT.S.LU |
| 16 | FCLASS.S | 36 | FCVT.S.D | 56 | FCVT.L.D |
| 17 | FCVT.S.W | 37 | FCVT.D.S | 57 | FCVT.LU.D |
| 18 | FCVT.S.WU | 38 | FCVT.W.D | 58 | FMV.X.D |
| 19 | FMV.W.X | 39 | FCVT.WU.D | 59 | FCVT.D.L |
| — | — | — | — | 60 | FCVT.D.LU |
| — | — | — | — | 61 | FMV.D.X |

### 4.7 RV64IMFD 指令集

RV64IMFD 各扩展的完整指令编码、语义及时序约束详见：

> _The RISC-V Instruction Set Manual, Volume I: Unprivileged ISA, Document Version 20191213_

SPUV3 实现覆盖以下标准子集：**RV64I**（基础整数）、**RV64M**（乘除法）、**RV64F**（单精度浮点）、**RV64D**（双精度浮点）。不支持 C 扩展（压缩指令）。

### 4.8 CSR 寄存器映射

| CSR 地址 | 名称 | R/W | 说明 |
| --- | --- | --- | --- |
| `0x001` | FFLAGS | RW | 浮点异常标志（NV/DZ/OF/UF/NX） |
| `0x002` | FRM | RW | 浮点舍入模式 |
| `0x003` | FCSR | RW | 浮点控制状态寄存器（FFLAGS + FRM） |
| `0x004` | TRACE\_PRINT\_FLOAT | — | 仿真：打印浮点值（仅TRACE模式） |
| `0x005` | TRACE\_PRINT\_DOUBLE | — | 仿真：打印双精度值（仅TRACE模式） |
| `0x110` | DCSR | RW | 向量寄存器调试打印控制 |
| `0x200` | MSTATUS | RW | 处理器状态；bit\[31\]=算法完成标志 |
| `0x201` | LPMD | RW | 低功耗模式控制 |
| `0x202` | HAD | RW | 硬件辅助调试 |
| `0x300` | BNPCFG | RW（BN） | BNPU 模数 P（256-bit，素数）⚠️ 地址与 RISC-V mstatus(0x300) 冲突，SPU 优先 |
| `0x400` | BNMMCFG | RW（BN） | BNPU Montgomery 参数（256-bit） |
| `0x500` | BNRRCFG | RW（BN） | BNPU Montgomery R²（256-bit） |
| `0x600` | NTTQ | RW（GPR） | VPU NTT 模数 q |
| `0x601` | NTTQINV | RW（GPR） | VPU NTT q⁻¹ |
| `0x602` | NTTIMM | RW（GPR） | VPU NTT 立即数参数 |
| `0x603`~`0x622` | COEFFI0~COEFFI31 | RW（VR） | PQC 算法系数（各 256-bit，共 32 组） |
| `0x623` | RSA\_CSR | RW（BN） | RSA 控制字（启动/配置） |
| `0x624` | RSA\_ND | RW（BN） | RSA N·(-N⁻¹) mod 2¹²⁸（128-bit） |
| `0x625` | RSA\_SEGEN | RW（BN） | RSA 种子使能 |
| `0x626` | RSA\_FLAG | RW（BN） | RSA 标志位 |
| `0x627` | RSA\_LOOPS | RW（BN） | RSA 循环次数（12-bit） |
| `0x628` | RSA\_TO\_MONT\_LEN | RW（BN） | Montgomery 转入长度（11-bit） |
| `0x629` | RSA\_TO\_MONT\_ADDR | RW（BN） | Montgomery 转入起始地址（12-bit） |
| `0x62A` | RSA\_DB\_LEN | RW（BN） | RSA 数据块长度（11-bit） |
| `0x62B` | RSA\_DB\_ADDR | RW（BN） | RSA 数据块起始地址（12-bit） |
| `0x62C` | RSA\_FROM\_MONT\_LEN | RW（BN） | Montgomery 转出长度（11-bit） |
| `0x62D` | RSA\_FROM\_MONT\_ADDR | RW（BN） | Montgomery 转出地址（12-bit） |
| `0x62E` | RSA\_AD\_LEN | RW（BN） | RSA 附加数据长度（11-bit） |
| `0x62F` | RSA\_AD\_ADDR | RW（BN） | RSA 附加数据地址（12-bit） |
| `0x700` | VMASK | RW（GPR） | 向量操作掩码（32-bit） |
| `0xB00` | CYCLE | RO | 周期计数器（mcycle） |

> **注意 — RVC 不支持**：SPUV3 不实现 RISC-V C 扩展（压缩指令）。BNPU 指令的 `inst[1:0]` 可以为 `00` 或 `10`，若开启 RVC 会被误识别为 16-bit 压缩指令，导致 PC 计算错误。

> **CSR 地址冲突说明**：SPU 的 BNPCFG（`0x300`）与 RISC-V 标准 mstatus（`0x300`）地址相同。硬件优先将 `0x300` 路由给 BNPCFG，标准 mstatus 无效。FPU CSR（`0x001~0x003`）沿用标准 RISC-V 地址，由标准 CSR 块处理。

---

## 5. 大数处理单元 BNPU

### 5.1 BNPU 架构

BNPU 是 SPUV3 中与 RV64IMFD 核紧密耦合的**大数算术加速引擎**。

**主要特性**：

*   **寄存器文件**：64 个 256-bit 大数寄存器（b0~b63），文件 `rtl/spuv3_bnregfile.v`，地址宽度 6-bit
    
*   **模运算**：基于 Montgomery 算法的 256-bit 模乘、模加、模减、模逆
    
*   **国密对称密码**：硬件实现 SM1/SM3/SM4/SM7 各轮函数（含 ECB/CBC 模式及密钥扩展）
    
*   **BN 访存**：支持从 DLM 加载/存储 256-bit 大数，以及按 128-bit 半段（H0/H1）和 64-bit 四分之一段（Q0~Q3）加载存储
    
*   **移位与逻辑**：bnsll（左移）、bnsrl（右移）、bnor（按位或）
    
*   **位反转**：brevi（256-bit 位序反转）
    

**使用前 CSR 配置**（必须设置）：

```asm
# 设置模数 P（256-bit）写入 BNPCFG
csrrw zero, 0x300, b_P

# 设置 Montgomery 参数写入 BNMMCFG、BNRRCFG
csrrw zero, 0x400, b_MM
csrrw zero, 0x500, b_RR

```

### 5.2 BNPU 指令格式与编码

BNPU 采用**自定义 32-bit 固定长度编码**，与 RISC-V 标准指令集完全独立。opcode 字段固定占据 `[7:0]`（8 bit），其余 24 bit 按指令类别进行操作数编码。以下 7 种格式均从 `as/src/dcf_spu_as_cmd.py` 的机器码生成逻辑提取，为汇编器权威定义。

所有寄存器索引均为无符号整数（BN 寄存器 b0–b63 以 6 bit 表示，GPR x0–x31 以 5–8 bit 表示，具体见各格式）。

---

#### 格式 A：计算双操作数（rd, rs1）

```plaintext
 31      24 23      16 15       8  7       0
┌──────────┬──────────┬──────────┬──────────┐
│ 00000000 │ rs1[7:0] │  rd[7:0] │  op[7:0] │
└──────────┴──────────┴──────────┴──────────┘

```

汇编语法：`inst rd, rs1`　　适用：invmod、inz、bnmv

---

#### 格式 B：计算三操作数（rd, rs1, rs2）

```plaintext
 31      24 23      16 15       8  7       0
┌──────────┬──────────┬──────────┬──────────┐
│ rs2[7:0] │ rs1[7:0] │  rd[7:0] │  op[7:0] │
└──────────┴──────────┴──────────┴──────────┘

```

汇编语法：`inst rd, rs1, rs2`　　适用：mulmod、summod、difmod、bnsll、bnsrl、bnor

---

#### 格式 C：SM 密码四操作数（rd, rs1, rs2, rs3）

```plaintext
 31   26 25   20 19   14 13    8  7       0
┌───────┬───────┬───────┬───────┬──────────┐
│rs3[5:0]│rs2[5:0]│rs1[5:0]│ rd[5:0]│  op[7:0] │
└───────┴───────┴───────┴───────┴──────────┘

```

汇编语法：`inst rd, rs1, rs2, rs3`　　适用：sm3rd、sm4/sm1/sm7 各 ecb/cbc 轮函数（13 条）

---

#### 格式 D：密钥扩展单操作数（rs2）

```plaintext
 31   26 25   20 19   14 13    8  7       0
┌───────┬───────┬───────┬───────┬──────────┐
│000000 │rs2[5:0]│000000 │000000 │  op[7:0] │
└───────┴───────┴───────┴───────┴──────────┘

```

汇编语法：`inst rs2`　　适用：sm4e\_kg、sm4d\_kg、sm7e\_kg、sm7d\_kg

---

#### 格式 D2：SM1 密钥扩展双操作数（rs2, rs3）

```plaintext
 31   26 25   20 19   14 13    8  7       0
┌───────┬───────┬───────┬───────┬──────────┐
│rs3[5:0]│rs2[5:0]│000000 │000000 │  op[7:0] │
└───────┴───────┴───────┴───────┴──────────┘

```

汇编语法：`inst rs2, rs3`　　适用：sm1e\_kg、sm1d\_kg

---

#### 格式 E：BN 访存加载（rd\_bn ← DLM）

```plaintext
 31      20 19   14 13    8  7       0
┌──────────┬───────┬───────┬──────────┐
│ imm[11:0]│rs1[5:0]│ rd[5:0]│  op[7:0] │
└──────────┴───────┴───────┴──────────┘

```

汇编语法：`inst rd, imm(rs1_gpr)`，imm 为 12-bit 有符号偏移量；rs1 为 GPR 基地址寄存器，rd 为 BNPR 目的寄存器。 适用：bnlw、bnlwh0、bnlwh1、bnlwq0–q3；特例：brevi 亦使用此格式（rs1/rd 均为 BNPR，imm 固定为 0）

---

#### 格式 F：BN 访存存储（rs2\_bn → DLM）

```plaintext
 31      20 19   14 13    8  7       0
┌──────────┬───────┬───────┬──────────┐
│ imm[11:0]│rs2[5:0]│rs1[5:0]│  op[7:0] │
└──────────┴───────┴───────┴──────────┘

```

汇编语法：`inst rs2, imm(rs1_gpr)`，rs2 为 BNPR 数据源，rs1 为 GPR 基地址寄存器。 适用：bnsw、bnswh0、bnswh1、bnswq0–q3

---

#### 格式 G：BN–GPR 互传

```plaintext
 31      24 23      16 15       8  7       0
┌──────────┬──────────┬──────────┬──────────┐
│ rs2[7:0] │ 00000000 │  rd[7:0] │  op[7:0] │
└──────────┴──────────┴──────────┴──────────┘

```

汇编语法：`inst rd, rs2`　　适用：mvb2g（rd=GPR，rs2=BNPR）、mvg2b（rd=BNPR，rs2=GPR）

---

**格式汇总**

| 格式 | 布局（MSB→LSB） | 典型汇编语法 |
| --- | --- | --- |
| A | \`0x00 | rs1\[7:0\] |
| B | \`rs2\[7:0\] | rs1\[7:0\] |
| C | \`rs3\[5:0\] | rs2\[5:0\] |
| D | \`0\[5:0\] | rs2\[5:0\] |
| D2 | \`rs3\[5:0\] | rs2\[5:0\] |
| E | \`imm12 | rs1\_gpr\[5:0\] |
| F | \`imm12 | rs2\_bn\[5:0\] |
| G | \`rs2\[7:0\] | 0x00 |

### 5.3 BNPU 指令详细说明

以下机器码模板中，`op` 列为十六进制 opcode 字节（位于 `[7:0]`）；模板列展示完整 32-bit 编码结构，各字段以 `_` 分隔。

#### 5.3.1 模运算指令（格式 B / A）

| 助记符 | op | 格式 | 32-bit 机器码模板 `[31:0]` | 功能 |
| --- | --- | --- | --- | --- |
| `mulmod rd, rs1, rs2` | `0x02` | B | `rs2[7:0]_rs1[7:0]_rd[7:0]_00000010` | rd = (rs1 × rs2) mod P，256-bit Montgomery 模乘 |
| `summod rd, rs1, rs2` | `0x04` | B | `rs2[7:0]_rs1[7:0]_rd[7:0]_00000100` | rd = (rs1 + rs2) mod P，256-bit 模加 |
| `difmod rd, rs1, rs2` | `0x06` | B | `rs2[7:0]_rs1[7:0]_rd[7:0]_00000110` | rd = (rs1 − rs2) mod P，256-bit 模减 |
| `invmod rd, rs1` | `0x08` | A | `00000000_rs1[7:0]_rd[7:0]_00001000` | rd = rs1⁻¹ mod P，256-bit 模逆（多周期） |

#### 5.3.2 大数移动与逻辑指令（格式 A / B）

| 助记符 | op | 格式 | 32-bit 机器码模板 `[31:0]` | 功能 |
| --- | --- | --- | --- | --- |
| `inz rd, rs1` | `0x0A` | A | `00000000_rs1[7:0]_rd[7:0]_00001010` | 非零检测：rd\_bn 及 GPR 目标写入 (rs1 ≠ 0) |
| `bnmv rd, rs1` | `0x0C` | A | `00000000_rs1[7:0]_rd[7:0]_00001100` | rd = rs1，256-bit 寄存器间数据搬移 |
| `bnsll rd, rs1, rs2` | `0x12` | B | `rs2[7:0]_rs1[7:0]_rd[7:0]_00010010` | rd = rs1 << rs2\[7:0\]，256-bit 逻辑左移 |
| `bnsrl rd, rs1, rs2` | `0x60` | B | `rs2[7:0]_rs1[7:0]_rd[7:0]_01100000` | rd = rs1 >> rs2\[7:0\]，256-bit 逻辑右移 |
| `bnor rd, rs1, rs2` | `0x62` | B | `rs2[7:0]_rs1[7:0]_rd[7:0]_01100010` | rd = rs1 \| rs2，256-bit 按位或 |
| `brevi rd, 0(rs1)` | `0x5E` | E | `000000000000_rs1[5:0]_rd[5:0]_01011110` | rd = bit\_reverse(rs1)，256-bit 位序逐位反转；rs1/rd 均为 BNPR，imm 固定为 0 |

#### 5.3.3 BN–GPR 互传指令（格式 G）

| 助记符 | op | 格式 | 32-bit 机器码模板 `[31:0]` | 功能 |
| --- | --- | --- | --- | --- |
| `mvb2g rd_gpr, rs2_bn` | `0x36` | G | `rs2[7:0]_00000000_rd[7:0]_00110110` | rd\_GPR = rs2\_BN\[63:0\]，BNPR 低 64-bit → GPR |
| `mvg2b rd_bn, rs2_gpr` | `0x38` | G | `rs2[7:0]_00000000_rd[7:0]_00111000` | rd\_BN\[63:0\] = rs2\_GPR，GPR 64-bit → BNPR 低段，高位清零 |

#### 5.3.4 BN 访存指令（格式 E / F）

访存指令使用 12-bit 有符号字节偏移量，rs1\_gpr 为 GPR 基地址寄存器（使用汇编 ABI 名称或 x0–x31）。

> **非对齐 256-bit 访问**（2026-05-21 新增）：`bnlw` / `bnsw` 全字变体支持任意字节偏移（0–31）的非对齐访问，硬件通过两拍 FSM（`S_WAIT_READ_BN_UA` / `S_WAIT_WRITE_BN_UA`）自动完成跨行数据的 barrel shift 拼接。`bnlwh0/h1`、`bnswh0/h1`、`bnlwq0–q3`、`bnswq0–q3` 仅支持对齐访问。

| 助记符 | op | 格式 | 32-bit 机器码模板 `[31:0]` | 传输宽度 | 映射位段 |
| --- | --- | --- | --- | --- | --- |
| `bnlw rd, imm(rs1)` | `0x0E` | E | `imm[11:0]_rs1[5:0]_rd[5:0]_00001110` | 256-bit | rd\[255:0\] ← DLM |
| `bnsw rs2, imm(rs1)` | `0x10` | F | `imm[11:0]_rs2[5:0]_rs1[5:0]_00010000` | 256-bit | rs2\[255:0\] → DLM |
| `bnlwh0 rd, imm(rs1)` | `0x3A` | E | `imm[11:0]_rs1[5:0]_rd[5:0]_00111010` | 128-bit | rd\[255:128\] ← DLM（高半段 H0） |
| `bnswh0 rs2, imm(rs1)` | `0x3C` | F | `imm[11:0]_rs2[5:0]_rs1[5:0]_00111100` | 128-bit | rs2\[255:128\] → DLM（高半段 H0） |
| `bnlwh1 rd, imm(rs1)` | `0x3E` | E | `imm[11:0]_rs1[5:0]_rd[5:0]_00111110` | 128-bit | rd\[127:0\] ← DLM（低半段 H1） |
| `bnswh1 rs2, imm(rs1)` | `0x40` | F | `imm[11:0]_rs2[5:0]_rs1[5:0]_01000000` | 128-bit | rs2\[127:0\] → DLM（低半段 H1） |
| `bnlwq0 rd, imm(rs1)` | `0x42` | E | `imm[11:0]_rs1[5:0]_rd[5:0]_01000010` | 64-bit | rd\[63:0\] ← DLM（Q0） |
| `bnswq0 rs2, imm(rs1)` | `0x44` | F | `imm[11:0]_rs2[5:0]_rs1[5:0]_01000100` | 64-bit | rs2\[63:0\] → DLM（Q0） |
| `bnlwq1 rd, imm(rs1)` | `0x46` | E | `imm[11:0]_rs1[5:0]_rd[5:0]_01000110` | 64-bit | rd\[127:64\] ← DLM（Q1） |
| `bnswq1 rs2, imm(rs1)` | `0x48` | F | `imm[11:0]_rs2[5:0]_rs1[5:0]_01001000` | 64-bit | rs2\[127:64\] → DLM（Q1） |
| `bnlwq2 rd, imm(rs1)` | `0x4A` | E | `imm[11:0]_rs1[5:0]_rd[5:0]_01001010` | 64-bit | rd\[191:128\] ← DLM（Q2） |
| `bnswq2 rs2, imm(rs1)` | `0x4C` | F | `imm[11:0]_rs2[5:0]_rs1[5:0]_01001100` | 64-bit | rs2\[191:128\] → DLM（Q2） |
| `bnlwq3 rd, imm(rs1)` | `0x4E` | E | `imm[11:0]_rs1[5:0]_rd[5:0]_01001110` | 64-bit | rd\[255:192\] ← DLM（Q3） |
| `bnswq3 rs2, imm(rs1)` | `0x50` | F | `imm[11:0]_rs2[5:0]_rs1[5:0]_01010000` | 64-bit | rs2\[255:192\] → DLM（Q3） |

#### 5.3.5 SM 密码轮函数（格式 C）

每条指令处理一个分组密码轮，四个操作数均为 BNPR。

| 助记符 | op | 32-bit 机器码模板 `[31:0]` | 功能 |
| --- | --- | --- | --- |
| `sm3rd rd, rs1, rs2, rs3` | `0x14` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00010100` | SM3 压缩函数一轮迭代 |
| `sm4e_ecb rd, rs1, rs2, rs3` | `0x16` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00010110` | SM4 ECB 加密轮函数 |
| `sm4e_cbc rd, rs1, rs2, rs3` | `0x18` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00011000` | SM4 CBC 加密轮函数 |
| `sm4d_ecb rd, rs1, rs2, rs3` | `0x1A` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00011010` | SM4 ECB 解密轮函数 |
| `sm4d_cbc rd, rs1, rs2, rs3` | `0x1C` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00011100` | SM4 CBC 解密轮函数 |
| `sm1e_ecb rd, rs1, rs2, rs3` | `0x1E` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00011110` | SM1 ECB 加密轮函数 |
| `sm1e_cbc rd, rs1, rs2, rs3` | `0x20` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00100000` | SM1 CBC 加密轮函数 |
| `sm1d_ecb rd, rs1, rs2, rs3` | `0x22` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00100010` | SM1 ECB 解密轮函数 |
| `sm1d_cbc rd, rs1, rs2, rs3` | `0x24` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00100100` | SM1 CBC 解密轮函数 |
| `sm7e_ecb rd, rs1, rs2, rs3` | `0x26` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00100110` | SM7 ECB 加密轮函数 |
| `sm7e_cbc rd, rs1, rs2, rs3` | `0x28` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00101000` | SM7 CBC 加密轮函数 |
| `sm7d_ecb rd, rs1, rs2, rs3` | `0x2A` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00101010` | SM7 ECB 解密轮函数 |
| `sm7d_cbc rd, rs1, rs2, rs3` | `0x2C` | `rs3[5:0]_rs2[5:0]_rs1[5:0]_rd[5:0]_00101100` | SM7 CBC 解密轮函数 |

#### 5.3.6 密钥扩展指令（格式 D / D2）

| 助记符 | op | 格式 | 32-bit 机器码模板 `[31:0]` | 功能 |
| --- | --- | --- | --- | --- |
| `sm4e_kg rs2` | `0x56` | D | `000000_rs2[5:0]_000000_000000_01010110` | SM4 加密密钥扩展，轮密钥写入 rs2 |
| `sm4d_kg rs2` | `0x58` | D | `000000_rs2[5:0]_000000_000000_01011000` | SM4 解密密钥扩展 |
| `sm7e_kg rs2` | `0x5A` | D | `000000_rs2[5:0]_000000_000000_01011010` | SM7 加密密钥扩展 |
| `sm7d_kg rs2` | `0x5C` | D | `000000_rs2[5:0]_000000_000000_01011100` | SM7 解密密钥扩展 |
| `sm1e_kg rs2, rs3` | `0x52` | D2 | `rs3[5:0]_rs2[5:0]_000000_000000_01010010` | SM1 加密密钥扩展，rs3 为辅助参数 |
| `sm1d_kg rs2, rs3` | `0x54` | D2 | `rs3[5:0]_rs2[5:0]_000000_000000_01010100` | SM1 解密密钥扩展 |

#### EXU SYM 单元：辅助对称密码指令（单周期，结果写回 GPR）

SYM 单元共 **8 条有效指令**，使用 RISC-V 自定义 opcode 空间，在 `spuv3_exu_sym.v` 中单周期完成。

> **GPR 位宽约定**：SYM 指令操作 64-bit 通用寄存器（x0–x31），但 **仅使用低 32 位数据**。硬件在 EXU 阶段自动截断高 32 位，软件无需额外处理。

| 指令 | opcode | 格式 | 操作数 | 功能 |
| --- | --- | --- | --- | --- |
| `tadd rd, rs1, rs2, rs3` | `1010111` (0x57) | R4-type | rd, rs1, rs2, rs3 (GPR) | 加法（结合进位追踪） |
| `tandxor rd, rs1, rs2, rs3` | `1010111` (0x57) | R4-type | rd, rs1, rs2, rs3 (GPR) | (a AND b) XOR c |
| `tnandxor rd, rs1, rs2, rs3` | `1010111` (0x57) | R4-type | rd, rs1, rs2, rs3 (GPR) | NOT(a AND b) XOR c |
| `rr64l rd, rs1, rs2, rs3` | `1010111` (0x57) | R4-type | rd, rs1, rs2, rs3 (GPR) | 64-bit 循环右移（低段） |
| `rr64h rd, rs1, rs2, rs3` | `0001011` (0x0B) | R4-type | rd, rs1, rs2, rs3 (GPR) | 64-bit 循环右移（高段） |
| `ssrol rd, imm20` | `1110111` (0x77) | U-type | rd (GPR), imm20 | 多轮 SM4 密钥流生成 |
| `ssro rd, imm20` | `1111011` (0x7B) | U-type | rd (GPR), imm20 | 多步异或旋转 |
| `sro rd, rs1, imm12` | `0101011` (0x2B) | I-type | rd, rs1 (GPR), imm12 | 单次异或旋转（SM3/SM4 辅助） |

---

## 6. 向量处理单元 VPU

### 6.1 VPU 架构

VPU 是 SPUV3 针对**后量子密码（PQC）算法**设计的向量加速引擎，作为 `vpu_top` 模块内嵌于 `spuv3_core`。

**主要参数**（`rtl/vpu/vpu_top.sv`）：

*   `ELEN = 32`：每 lane 元素宽度 32-bit
    
*   `LaneNum = 10`：并行 lane 数（总向量宽度 = 10 × 32 = **320-bit**）
    
*   `VEC_REG_NUM = 32`：逻辑向量寄存器数（v0~v31）
    

**算法支持**：

*   Kyber（CRYSTALS-Kyber，格密码 KEM）：NTT/INTT、压缩/解压缩、CBD 采样、拒绝采样
    
*   Dilithium（CRYSTALS-Dilithium，格密码签名）：ChkNorm、Power2Round、多项式打包/解包
    
*   通用 PQC：Barrett 归约、Montgomery 归约、16/32-bit 向量加减法
    

**流水线**：VPU 内部每条指令 **2 拍执行**（含寄存器读和计算两拍），以避免综合关键路径。

**与主核交互**：

*   IDU 识别 VPU 指令 → 将指令和操作数（vs1~vs5，rs1，rs2）发送给 VPU
    
*   VPU 通过 `vpu_mem_req` 接口访问 DLM/DPRAM（128-bit 对齐）
    
*   VPU 分支（bgeuvx/bequvx/bneuvx/bltuvx）结果反馈给 IFU 进行 PC 重定向
    
*   VPU 写回通过 `scalar_rd_we_o` / `vd_we_o` 更新 GPR / vregfile
    

### 6.2 VPU 寄存器文件

文件：`rtl/vpu/vpu_vregfile.sv`

*   **物理 vregfile**：v0~v8，共 9 个 320-bit 寄存器，5 个读端口 + 1 个写端口
    
*   **BN remap 区（v9~v31）**：映射到 BNPR b32~b63，使用 BNPR 的 256-bit 存储（有效宽度 256-bit，高 64-bit 补零）
    
*   **写仲裁**：`vpu_vregfile_bnreg_remap_en = vpu_vregfile_remap2bnreg AND (waddr >= SPUV3_VREGFILE_320BIT_NUM)`
    
*   **读仲裁**：`rdata = (remap2bnreg AND raddr >= 9) ? bnreg_data : vregfile_data`
    

### 6.3 VPU 指令编码规则

VPU 指令均为标准 32-bit 长度，使用 RISC-V 保留的自定义 opcode 空间。来自 `rtl/vpu/vpu_decode.sv` 的实际掩码匹配逻辑定义如下 6 类：

**RISC-V 指令位域**（统一参考）：

```plaintext
[31:25] funct7 | [24:20] rs2 | [19:15] rs1 | [14:12] funct3 | [11:7] rd | [6:0] opcode

```

| 类别 | 掩码（MASK，十六进制） | 匹配字段 |
| --- | --- | --- |
| 1 | `0xfe00707f` | funct7 + funct3 + opcode |
| 2 | `0x0000707f` | funct3 + opcode（funct7/rs 全用于操作数） |
| 3 | `0xfe00007f` | funct7 + opcode（funct3=000） |
| 4 | `0xfff0707f` | funct7 + rs2固定=00000 + funct3 + opcode |
| 5 | `0x0300007f` | funct7\[26:25\] + opcode |
| 6 | `0x0000_0_7f 即检查rd[0]` | rd\[0\] + opcode |

### 6.4 VPU 指令完整编码表

以下所有编码均来自 `rtl/vpu/vpu_decode.sv`，为硬件实际使用的权威定义。

#### 第 1 类：funct7 + funct3 + opcode（掩码 `0xfe00707f`）

| 指令 | funct7 \[31:25\] | funct3 \[14:12\] | opcode \[6:0\] | 机器码（32-bit 二进制模板） | 功能说明 |
| --- | --- | --- | --- | --- | --- |
| `vkybecd12 vd, vs1, vs2` | `1001000` | `000` | `0000101` | `1001000_rs2_rs1_000_rd_0000101` | Kyber 编码（Encode 12-bit） |
| `vkybdcd12 vd, vs1, vs2` | `1001000` | `001` | `0000101` | `1001000_rs2_rs1_001_rd_0000101` | Kyber 解码（Decode 12-bit） |
| `vdilichknrmv1 vd, rs1` | `1001000` | `010` | `0000101` | `1001000_00000_rs1_010_rd_0000101` | Dilithium CheckNorm v1；B 阈值由 GPR rs1 低 32-bit 指定，结果（0/1）写入 vd |
| `vdilichknrmv2 vd, rs1` | `1001000` | `011` | `0000101` | `1001000_00000_rs1_011_rd_0000101` | Dilithium CheckNorm v2；与 v1 相同接口，对应不同拒绝条件（γ2−β 等），结果写入 vd |
| `vand vd, vs1, vs2` | `1001000` | `100` | `0000101` | `1001000_rs2_rs1_100_rd_0000101` | 320-bit 向量按位 AND |
| `vor vd, vs1, vs2` | `1001000` | `101` | `0000101` | `1001000_rs2_rs1_101_rd_0000101` | 320-bit 向量按位 OR |
| `vxor vd, vs1, vs2` | `1001000` | `110` | `0000101` | `1001000_rs2_rs1_110_rd_0000101` | 320-bit 向量按位 XOR |
| `vpqcadd16 vd, vs1, vs2` | `1001000` | `111` | `0000101` | `1001000_rs2_rs1_111_rd_0000101` | 向量 16-bit 元素模加（加模数 q） |
| `vpqcadd32 vd, vs1, vs2` | `1000100` | `000` | `0001001` | `1000100_rs2_rs1_000_rd_0001001` | 向量 32-bit 元素模加 |
| `vpqcmrdc16 vd, vs1, vs2` | `1000100` | `001` | `0001001` | `1000100_rs2_rs1_001_rd_0001001` | 向量 16-bit Montgomery 归约 |
| `vpqcmrdc32 vd, vs1, vs2` | `1000100` | `010` | `0001001` | `1000100_rs2_rs1_010_rd_0001001` | 向量 32-bit Montgomery 归约 |
| `vpqcbrtrdc vd, vs1, vs2` | `1000100` | `011` | `0001001` | `1000100_rs2_rs1_011_rd_0001001` | 向量 Barrett 归约 |
| `vpqcshf16 vd, vs1, vs2` | `1000100` | `100` | `0001001` | `1000100_rs2_rs1_100_rd_0001001` | 向量 16-bit 系数移位 |
| `vpqcshf32 vd, vs1, vs2` | `1000100` | `101` | `0001001` | `1000100_rs2_rs1_101_rd_0001001` | 向量 32-bit 系数移位 |
| `xorv2rcvx vd, vs1, vs2` | `1000100` | `110` | `0001001` | `1000100_rs2_rs1_110_rd_0001001` | 向量 XOR 再编码（xorv2rc） |
| `vpqcsub16 vd, vs1, vs2` | `1000100` | `111` | `0001001` | `1000100_rs2_rs1_111_rd_0001001` | 向量 16-bit 元素模减 |
| `vdilicaddq vd, vs1` | `1000010` | `001` | `0001101` | `1000010_00000_vs1_001_vd_0001101` | Dilithium 条件加 Q：若 vs1 元素为负则加模数 Q（Q 取自 CSR NTTQ），vs1→vd，单周期 |
| `vdilirdc32 vd, vs1` | `1000010` | `010` | `0001101` | `1000010_00000_vs1_010_vd_0001101` | Dilithium 32-bit Barrett 归约；256-bit vs1→vd，多周期 |
| `vpqcsub32 vd, vs1, vs2` | `1000010` | `011` | `0001101` | `1000010_rs2_rs1_011_rd_0001101` | 向量 32-bit 元素模减 |

#### 第 2 类：funct3 + opcode（掩码 `0x0000707f`，funct7/rs 字段用作操作数）

| 指令 | funct3 \[14:12\] | opcode \[6:0\] | 功能说明 |
| --- | --- | --- | --- |
| `vlevx vd, offset(rs1)` | `000` | `0010001` | 向量加载（DLM，VMASK=8 支持非对齐 offset 0–31，VMASK=10 仅 offset 0/8/16/24） |
| `vlcc vd, csr_addr` | `001` | `0010001` | 从 CSR 加载 256-bit 系数到向量寄存器 |
| `vsevx vs2, offset(rs1)` | `010` | `0010001` | 向量存储到 DLM（VMASK=8 支持非对齐 offset 0–31） |
| `vscc csr_addr, vs1` | `011` | `0010001` | 向量寄存器写入 CSR |
| `vsetvlix rd, rs1` | `100` | `0010001` | 设置向量活跃长度（AVL） |
| `rxorvvx vd, vs1, imm` | `101` | `0010001` | 向量旋转 XOR（rotate-XOR，向量×向量） |
| `xornavivx vd, vs1, imm` | `110` | `0010001` | 向量 XOR-NAVI（导航异或辅助） |
| `bgeuvx rs1, rs2, offset` | `111` | `0010001` | 向量元素无符号 ≥ 比较分支 |
| `bequvx rs1, rs2, offset` | `000` | `0010101` | 向量元素无符号 = 比较分支 |
| `bneuvx rs1, rs2, offset` | `001` | `0010101` | 向量元素无符号 ≠ 比较分支 |
| `bltuvx rs1, rs2, offset` | `010` | `0010101` | 向量元素无符号 < 比较分支 |
| `vshuffnttvx imm12` | `011` | `0010101` | NTT 系数重排（shuffle NTT）；预留指令，RTL 中 MATCH/MASK 已定义 |
| `vkybcbd imm12` | `100` | `0010101` | Kyber CBD 采样（中心二项分布，eta 由 imm 指定） |
| `vkybcps imm12` | `101` | `0010101` | Kyber 压缩（Compress，d 位由 imm 指定） |
| `vkybdcps imm12` | `110` | `0010101` | Kyber 解压缩（Decompress，d 位由 imm 指定） |
| `vdiliclg imm12` | `111` | `0010101` | Dilithium PolyChallenge\_Gen（tau 由 imm 指定） |
| `vdilipwr2rud imm12` | `000` | `0011001` | Dilithium Power2Round |
| `vdilipack imm12` | `001` | `0011001` | Dilithium 多项式比特打包（bitpack） |
| `vdiliunpack imm12` | `010` | `0011001` | Dilithium 多项式比特解包（bitunpack） |
| `vslli vd, vs1, shamt` | `011` | `0011001` | 向量各元素逻辑左移立即数 |
| `vsrli vd, vs1, shamt` | `100` | `0011001` | 向量各元素逻辑右移立即数 |
| `vdilirejuni` | `101` | `0011001` | Dilithium 拒绝均匀采样（Rej Uniform）；输入 32×256-bit 来自 COEFFI CSR，q 取自 NTTQ CSR，输出写回 COEFFI CSR；约 258–281 周期 |
| `vdilirejunieta imm12` | `110` | `0011001` | Dilithium η 域拒绝采样（Rej Uniform Eta）；eta 由 imm\[2:0\] 指定（2 或 4），输入来自 COEFFI CSR，输出写回 COEFFI CSR；约 258–281 周期 |
| `vdilikeccakshf imm` | `111` | `0011001` | Dilithium Keccak shuffle；17×256-bit 来自 COEFFI CSR，imm\[3:0\] 选模式（0=shake256 排列），输出 20×256-bit 到 COEFFI CSR |

#### 第 3 类：funct7 + opcode（掩码 `0xfe00007f`）

| 指令 | funct7 \[31:25\] | opcode \[6:0\] | 功能说明 |
| --- | --- | --- | --- |
| `vaddvx vd, vs1, vs2` | `0000100` | `0000101` | 向量 32-bit lane-wise 加法（vd\[i\] = vs1\[i\] + vs2\[i\]） |
| `xorrvvx vd, vs1, vs2` | `0001000` | `0000101` | 向量 XOR-RR（轮旋转异或，v×v） |
| `vkybrejuni` | `0001100` | `0000101` | Kyber 拒绝均匀采样（Rejection Uniform Sampling） |
| `vkybcpsmsg` | `0010000` | `0000101` | Kyber 消息压缩（Compress Message） |
| `vkybdcpsmsg` | `0010100` | `0000101` | Kyber 消息解压缩（Decompress Message） |

#### 第 4 类：funct7 + rs2固定=00000 + funct3 + opcode（掩码 `0xfff0707f`）

| 指令 | funct7 \[31:25\] | rs2 \[24:20\] | funct3 \[14:12\] | opcode \[6:0\] | 功能说明 |
| --- | --- | --- | --- | --- | --- |
| `vmvvx vd, rs1` | `0011000` | `00000` | `000` | `0000101` | 广播标量 GPR 到向量寄存器所有 lane |
| `vmvvcc vd, rs1` | `0011100` | `00000` | `000` | `0000101` | 向量寄存器内容写入 CSR |
| `vmvccv vd, rs1` | `0100000` | `00000` | `000` | `0000101` | CSR 内容读入向量寄存器 |

#### 第 5 类：funct7\[26:25\] + opcode（掩码 `0x0300007f`）

| 指令 | funct7\[26:25\] | opcode \[6:0\] | 功能说明 |
| --- | --- | --- | --- |
| `xorv3vx vd, vs1, vs2, vs3` | `01`（bit26=0, bit25=1） | `0000101` | 三路向量 XOR；vs3 索引编码于 funct7\[31:27\]（5-bit） |
| `nttarithvx vd, vs1, vs2, vs3` | `10`（bit26=1, bit25=0） | `0000101` | NTT 算术运算；预留指令，RTL 中 MATCH/MASK 已定义，vs3 编码于 funct7\[31:27\] |

#### 第 6 类：rd\[0\] + opcode（掩码检查位 7 和低 7 位）

| 指令 | rd\[0\]（bit7） | opcode \[6:0\] | 格式 | 功能说明 |
| --- | --- | --- | --- | --- |
| `vpqccoeff rd, imm20` | `0` | `0000001` | U-type | 加载 20-bit 立即数到 PQC 系数向量寄存器（rd 为偶数寄存器） |

---

## 7. RSA 硬件加速器

文件：`rtl/spuv3_rsa/`

### 模块构成

```plaintext
rsa_pku_ctrl_top
├── rsa_pku_ctrl    控制状态机（Montgomery 模幂算法调度）
├── rsa_pku_logic   模幂逻辑控制
├── rsa_core        模乘核心
├── rsa_mac         模乘累加器（128-bit）
└── rsa_add         128-bit 模加法器

```

### 工作方式

RSA 加速器通过 **CSR 接口**与 SPUV3 主核通信，使用 **DPRAM** 作为数据工作区：

1.  **配置阶段**：通过 CSR 写入 RSA 参数（N·(-N⁻¹)、循环次数、数据地址、长度等）
    
2.  **数据准备**：将大数操作数写入 DPRAM 指定偏移
    
3.  **启动**：写 `RSA_CSR`（`0x623`）触发 `rsa_pku_ctrl_top` 开始 Montgomery 模幂
    
4.  **等待**：读 `RSA_CSR` 或等待 `rsa_done2csr` 信号
    
5.  **读取结果**：从 DPRAM 读出运算结果
    

### DPRAM 接口（双端口仲裁）

| 端口 | 使用方 | 优先级 | 冲突处理 |
| --- | --- | --- | --- |
| Port A | RSA 控制器 优先 / SPUV3 核心（次） | RSA | 软件保证 RSA 运行时主核不访问 DPRAM |
| Port B | RSA 控制器 优先 / AHB 主机 CPU（次） | RSA | 软件保证 RSA 运行时主机不写 DPRAM |

**RSA RAM 地址映射**：RSA 控制器使用 7-bit 地址（128-bit 粒度），经过地址转换映射到 256-bit 宽的 DPRAM（低位 `rsa_addra[0]` 选择高/低 128-bit 半段）。

### 支持算法

*   **RSA-1024 CRT**（从最新固件 `firmware/` 中验证）
    
*   **RSA-2048 CRT**
    
*   通用 Montgomery 模幂（密钥长度由 CSR 参数控制）
    

---

## 8. 存储系统

### 哈佛架构

SPUV3 采用哈佛存储架构：**指令总线（ILM）** 与 **数据总线（DLM/DPRAM）** 物理独立。

### 核心侧数据总线地址空间

```plaintext
地址范围（SPU 核数据总线视角）     大小      说明
0x0000_0000 ~ 0x0000_FFFF        64 KB    DLM（数据本地存储器，256-bit 宽）
0x0001_0000 ~ 0x0001_7FFF        32 KB    DPRAM Port A（SPU 核访问区）
                                           其中前 16 KB 为 RSA 工作区

```

### AHB 主内存桥（主机侧）地址空间

```plaintext
地址范围（AHB 主机侧）             大小      说明
0x0000_0000 ~ 0x0001_FFFF       128 KB    ILM（指令存储器，32-bit 宽，仅 stop_on_reset 模式可写）
0x0002_0000 ~ 0x0002_FFFF        64 KB    DLM（数据存储器，AHB 32-bit→内部 256-bit 转换）
SFR_CFG_BASE_ADDR + 0             4 B      spuv3_cfg（启动控制）
SFR_CFG_BASE_ADDR + 4             4 B      spuv3_cfg_int（中断控制）

```

（SFR\_CFG\_BASE\_ADDR = ILM\_SIZE\_BYTE + DLM\_SIZE\_BYTE = 0x0003\_0000）

### AHB DPRAM 桥（主机侧）地址空间

```plaintext
地址范围                           大小      说明
0x0000_0000 ~ 0x0000_7FFF        32 KB    DPRAM Port B（主机读写，用于 SPU↔主机 CPU 数据交换）

```

### 各存储器规格

| 存储器 | 配置宏 | 默认大小 | 总线宽度 | 位于模块 |
| --- | --- | --- | --- | --- |
| ILM | `SPUV3_ILM_SIZE_KB` | 128 KB | 32-bit | `spuv3_mems → rom.v` |
| DLM | `SPUV3_DLM_SIZE_KB` | 64 KB | 256-bit | `spuv3_mems → ram.v` |
| DPRAM | `SPUV3_DPRAM_SIZE_KB` | 32 KB | 256-bit（双端口） | `spuv3_mems` |
| RSA RAM | `SPUV3_RSA_RAM_SIZE_KB` | 16 KB | 128-bit（RSA侧） | DPRAM 地址划分 |

### AHB → 256-bit DLM/DPRAM 地址对齐

主机 CPU 以 32-bit AHB 总线访问 256-bit 宽的 DLM/DPRAM 时，通过 `mem_addr[2:0]`（3-bit 子字段选择器，对应 8 个 32-bit 段）将 32-bit 数据写入或读出 256-bit 宽度的正确字节位置：

```verilog
// 写入时按子字段展开写字节使能
wire [31:0] dlm_web_extend = {32{mem_addr_index00}} & {28'b0, ~mem_web}
                           | {32{mem_addr_index04}} & {24'b0, ~mem_web, 4'b0}
                           ...
                           | {32{mem_addr_index1c}} & {~mem_web, 28'b0};
// 读出时按 d1 寄存器的子字段选择 32-bit
wire [31:0] dlm_ram_dout_sel = {32{mem_addr_index00_d1}} & dlm_ram_dout[31:0]
                              | {32{mem_addr_index04_d1}} & dlm_ram_dout[63:32]
                              ...;

```

### 存储器安全

*   `SPUV3_MEM_ENC_ENABLE_INNER`（默认开启）：内部存储数据加密
    
*   `SPUV3_MEM_ENC_ENABLE_OUTER`（可选）：外部接口（AHB）侧数据加密，使用 `ram_key[15:0]` / `rom_key[15:0]`
    

**数据字节序约定**（所有密码算法）：

*   Key 和 IV：按定义长度字节逆序存放
    
*   分组数据：按分组长度字节逆序存放
    

### LSU 非对齐 256-bit Load/Store（2026-05-21 新增）

`bnsw` / `bnlw` / `vlevx` (VMASK=8) / `vsevx` (VMASK=8) 支持任意字节偏移（0–31）的非对齐 256-bit 访问，硬件通过 FSM 自动完成跨行数据的 barrel shift 拼接，无需软件对齐处理。

| 指令 | 条件 | FSM 状态 | 周期 |
| --- | --- | --- | --- |
| `bnlw` / `vlevx` 非对齐 | `mem_addr[4:0] ≠ 0` | `S_WAIT_READ_BN_UA` / `S_WAIT_READ_VPU`（扩展为 2 tick） | 3 |
| `bnsw` / `vsevx` 非对齐 | `mem_addr[4:0] ≠ 0` | `S_WAIT_WRITE_BN_UA` / `S_WAIT_WRITE_VPU`（扩展为 2 tick） | 2 |
| 对齐访问 | `mem_addr[4:0] = 0` | 原有对齐路径 | load 2 / store 1 |

**数据路径**：

*   **Load**：tick0 读对齐地址 → tick1 读对齐地址+0x20，barrel shift `{row_next, row_curr} >> (offset*8)` 拼接结果
    
*   **Store**：tick0 写对齐地址（数据 `<< offset*8`, BE = `0xFFFFFFFF << offset`）→ tick1 写对齐地址+0x20（数据 `>> (32-offset)*8`, BE = `0xFFFFFFFF >> (32-offset)`）
    

所有改动集中在 `rtl/spuv3_exu_mem.v`。非对齐支持仅限 256-bit 全字操作；`bnswh/bnlwh/bnswq/bnlwq` 变体、VMASK=10 模式不支持非对齐。

---

## 9. AHB 接口与总线桥

文件：`rtl/top/atcrambrg200.v`

> **📌 详细的 AHB 端口信号列表、时钟约束、内存映射见** [**2.1 端口信号列表**](#21-%E7%AB%AF%E5%8F%A3%E4%BF%A1%E5%8F%B7%E5%88%97%E8%A1%A8) **及子节。**

### 主内存 AHB 桥（u\_spuv3\_cfgbrg）

**功能**：将 AHB-Lite 总线协议转换为 SRAM 片选接口，覆盖 ILM/DLM/SFR 配置区。

**参数配置**：

```verilog
DATA_WIDTH      = 32
MIN_WDATA_WIDTH = 8
ADDR_WIDTH      = 24
MEM_SIZE_KB     = 256  // MAIN_MEM_SIZE_KB
OOR_ERR_EN      = 1    // Out-of-Range 错误使能

```

**stop\_on\_reset 机制**：

*   `stop_on_reset=1`：允许主机通过 AHB 直接访问 ILM/DLM（调试/初始化模式）
    
*   `stop_on_reset=0`：ILM/DLM 仅由 SPUV3 核访问，AHB 访问不可用
    

### DPRAM AHB 桥（u\_spuv3\_dprambrg）

相同 `atcrambrg200` 模块，时钟域为 `dpram_hclk`（与 `clk` 同源），仅映射 DPRAM Port B。

DPRAM B 口时钟由 `gnrl_async_clkmux`（同步模式）动态切换：`busy=0` 时用 `dpram_hclk`（Host 访问），`busy=1` 时用 `clk`（RSA 加速器访问）。详见 [2.3 DPRAM 双端口共享与时钟切换](#23-dpram-%E5%8F%8C%E7%AB%AF%E5%8F%A3%E5%85%B1%E4%BA%AB%E4%B8%8E%E6%97%B6%E9%92%9F%E5%88%87%E6%8D%A2)。

### SFR 配置寄存器（spuv3\_cfg\_sfr）

| 地址 | 寄存器 | 位含义 |
| --- | --- | --- |
| `SFR_CFG_BASE_ADDR + 0` | `spuv3_cfg` | bit\[30\]=alg\_start（写 1 启动 SPUV3 算法） |
| `SFR_CFG_BASE_ADDR + 4` | `spuv3_cfg_int` | bit\[0\]=int\_en（中断使能），bit\[1\]=done\_int（完成标志） |

---

## 10. 状态机与控制逻辑

> **📌 上电启动完整 12 步流程见** [**2.5 上电启动完整流程**](#25-%E4%B8%8A%E7%94%B5%E5%90%AF%E5%8A%A8%E5%AE%8C%E6%95%B4%E6%B5%81%E7%A8%8B)**。时钟供给纪律见** [**2.2 时钟域架构**](#22-%E6%97%B6%E9%92%9F%E5%9F%9F%E6%9E%B6%E6%9E%84)**。**

### 系统级 FSM（spuv3\_subsystem）

时钟域：`hclk`（AHB 侧）

```plaintext
IDLE ──(alg_start & running)──> SPUV3_CFG ──(1 cycle)──> SPUV3_WORKING
  ↑                                                            │
  └──────────────────── SPUV3_DONE ←──(mstatus[31]=1)────────┘

```

| 状态 | 输出信号 | 说明 |
| --- | --- | --- |
| IDLE | `spuv3_busy=0`, `spuv3_ready=1` | 等待启动 |
| SPUV3\_CFG | `cfg_enable=1`（1拍脉冲） | 向 SPUV3 核发送启动配置 |
| SPUV3\_WORKING | `spuv3_busy=1` | SPUV3 核正在执行算法 |
| SPUV3\_DONE | 触发 `spuv3_alg_done` 中断（若使能） | 算法完成，下一拍转回 IDLE |

**算法启动完整序列**：

```plaintext
1. 主机写 ILM/DLM/DPRAM（stop_on_reset=1 模式）
2. 主机写 spuv3_cfg（SFR）：bit[30]=1
3. SPUV3_CFG 状态：cfg_enable 脉冲 → SPUV3 核从 0x0 开始执行
4. SPUV3 核执行算法，结果写回 DLM/DPRAM
5. 算法完成后：mstatus[31]=1 → SPUV3_DONE → 触发中断
6. 主机读 DPRAM 取结果

```
---

## 11. LLVM 编译器适配

SPUV3 标准开发流程使用 Python 专用汇编器（第 12 节）。为支持 C 与汇编混合链接、ELF 统一测试回归，SPUV3 同时维护一套基于 LLVM 19 的 RISC-V 后端扩展（`xpqc`），完整支持 VPU、BNPU、SYM/SBOX 全部自定义指令。

本章既是架构参考，也是**开发者操作教程**：从 LLVM 源码修改到工具链构建、从固件预处理到 C+汇编混合编译、从本地开发到跨平台发布，每一步都有完整的命令和解释。

### 11.1 架构概述

LLVM xpqc 扩展仅在 **MC 层**（汇编器 + 反汇编器）实现，不涉及代码生成与指令选择。LLVM 在此的角色是**指令翻译 → ELF 链接 → hex 提取**，而不是优化编译器。

```plaintext
固件 .s 源码
  │
  ├── spu_preprocess_llvm.py    ← #define→.equ, label 去重, cN 保留
  │
  ├── clang -c (xpqc 扩展)      ← 汇编 → .o
  │
  ├── lld + linker script       ← 链接 → .elf（统一标量+VPU+BNPU+C）
  │
  └── llvm-objdump -d           ← 提取 hex → ILM/DLM

```

### 11.2 支持的指令集与寄存器

| 指令组 | 数量 | 编码空间 |
| --- | --- | --- |
| RV64IMFD（标准） | ~200 条 | inst\[1:0\]=11 |
| VPU 向量 | ~47 条 | inst\[1:0\]=01，7-bit opcode |
| BNPU 大数 | ~55 条 | inst\[1:0\]=xx，8-bit opcode |
| SYM/SBOX 对称 | ~18 条 | inst\[1:0\]=11，复用标准格式 |
| CSR 扩展 | 6 条 | B/V 寄存器 CSR 读写 |

| 寄存器组 | 汇编名 | 数量 | 宽度 | LLVM TableGen 类 |
| --- | --- | --- | --- | --- |
| GPR | `x0`–`x31` | 32 | 64-bit | `GPR` |
| FPR | `f0`–`f31` | 32 | 64-bit | `FPR64` |
| V（VPU 向量） | `v0`–`v31` | 32 | 320-bit | `VR` |
| C（CC 系数缓存） | `c0`–`c31` | 32 | 256-bit | `CCReg` |
| B（BNPU 大数） | `b0`–`b63` | 64 | 256-bit | `BNPUReg`（6-bit 编码） |

---

### 11.3 Step-by-Step：如何从零搭建 LLVM xpqc 开发环境

本节带你从 LLVM 源码克隆到第一次成功汇编 VPU 指令。每一步都可以直接复制执行。

#### 11.3.1 克隆 LLVM 源码

```bash
cd ~
git clone --depth 1 --branch llvmorg-19.1.0 \
    https://github.com/llvm/llvm-project.git
# 源码目录：~/llvm-project/llvm/

```
> **注意**：不要用 `--depth 1` 之外的 shallow clone 选项，有些 LLVM 子模块需要完整 tag。

#### 11.3.2 配置 CMake（仅构建 RISCV target）

```bash
cd ~/llvm-project
cmake -G Ninja -S llvm -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="RISCV" \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_DOCS=OFF

```

关键参数解释：

*   `LLVM_TARGETS_TO_BUILD="RISCV"`：只编译 RISC-V 后端，节省 80% 编译时间
    
*   `LLVM_ENABLE_PROJECTS="clang;lld"`：需要 clang 做汇编、lld 做链接
    
*   `-G Ninja`：ninja 比 make 快 2-3x
    

#### 11.3.3 首次构建

```bash
ninja -C build clang llvm-mc llvm-objdump lld

```

构建完成后验证：

```bash
build/bin/llvm-mc --version
# LLVM version 19.1.0

build/bin/llvm-mc -triple=riscv64 -show-encoding <<< "add x1, x2, x3"
# add x1, x2, x3   encoding: [0x33,0x80,0x62,0x00]

```
---

### 11.4 Step-by-Step：如何向 LLVM 添加 xpqc 扩展

这是核心开发流程。以添加 VPU 指令集为例，展示完整的 6 步流程。每一步修改后都需要 `ninja -C build llvm-mc` 重新编译验证。

#### 11.4.1 注册 xpqc 扩展特性

**文件**：`llvm/lib/Target/RISCV/RISCVFeatures.td`（在文件末尾添加）

```tablegen
// SPU-RCE xpqc extension
def FeatureVendorXPqc
    : SubtargetFeature<"xpqc", "HasVendorXPqc", "true",
                       "'XPqc' (PQC accelerator extension by SPU-RCE)">;

def HasVendorXPqc : Predicate<"Subtarget->hasVendorXPqc()">,
                    AssemblerPredicate<(all_of FeatureVendorXPqc),
                                       "'XPqc' extension">;

```

**文件**：`llvm/lib/Support/RISCVISAUtils.cpp`

在扩展名字符串表中添加一行：

```cpp
{"xpqc", {0, 0}}, // SPU-RCE PQC accelerator (custom)

```

**验证**：重新编译后，`--mattr=+xpqc` 应被识别：

```bash
ninja -C build llvm-mc
echo "vand v0, v1, v2" | build/bin/llvm-mc -triple=riscv64 -mattr=+xpqc -show-encoding 2>&1
# 预期输出：error: instruction use requires an option to be enabled
# （说明扩展已识别，只是还没定义指令）

```

#### 11.4.2 定义 V/C/B 寄存器

**文件**：`llvm/lib/Target/RISCV/RISCVRegisterInfo.td`

在文件末尾添加所有 XPqc 专用寄存器：

```tablegen
// SPU VPU 向量寄存器 v0-v31（320-bit，5-bit 编码）
foreach Index = 0-31 in {

  def VRVPU#Index : RISCVReg<Index, "v"#Index, [ ]>;

}

def VRegPQC : RegisterClass<"RISCV", [untyped], 320,
    (sequence "VRVPU%u", 0, 31)> { let Size = 320; }

// SPU 系数缓存寄存器 c0-c31（256-bit，5-bit 编码）
foreach Index = 0-31 in {

  def C#Index : RISCVReg<Index, "c"#Index, [ ]>;

}

def CCReg : RegisterClass<"RISCV", [untyped], 256,
    (sequence "C%u", 0, 31)> { let Size = 256; }

// SPU BNPU 大数寄存器 b0-b63（256-bit，6-bit 编码）
// 注意：标准 RISCVReg 只支持 5-bit 编码，BNPU 需要自定义 RISCVReg6 类
let Namespace = "RISCV" in {

  class RISCVReg6<bits<6> Enc, string n, list<string> alt = [ ]> : Register<n> {

    let HWEncoding{5-0} = Enc;
    let AltNames = alt;
  }
}

foreach Index = 0-63 in {

  def BN#Index : RISCVReg6<Index, "b"#Index, [ ]>;

}

def BNPUReg : RISCVRegisterClass<[untyped], 256, (add
    (sequence "BN%u", 0, 15), (sequence "BN%u", 16, 31),
    (sequence "BN%u", 32, 47), (sequence "BN%u", 48, 63))> { let Size = 256; }

```

#### 11.4.3 创建自定义指令格式类

**新建文件**：`llvm/lib/Target/RISCV/RISCVInstrFormatsXPqc.td`

VPU 指令使用 `inst[1:0]=01`（非标准 32-bit 编码），不能复用 LLVM 的 `RVInstR`/`RVInstI` 等标准格式类（它们依赖 `RISCVOpcode`，hardcode `inst[1:0]=11`）。必须创建独立的格式类：

```tablegen
//===-- RISCVInstrFormatsXPqc.td - XPqc VPU Custom Formats -*- tablegen -*-===//

// R-type: funct7 + rs2 + rs1 + funct3 + rd + opcode
class XPqcInstR<bits<7> funct7, bits<3> funct3, bits<7> opcode,
                dag outs, dag ins, string opcodestr, string argstr>

    : RVInst<outs, ins, opcodestr, argstr, [ ], InstFormatR> {

  bits<5> rs2; bits<5> rs1; bits<5> rd;
  let Inst{31-25} = funct7; let Inst{24-20} = rs2; let Inst{19-15} = rs1;
  let Inst{14-12} = funct3; let Inst{11-7} = rd;   let Inst{6-0} = opcode;
  let hasSideEffects = 0; let mayLoad = 0; let mayStore = 0;
}

// R-type with rs2=0 enforced (2-operand: rd, rs1) — Class 4
class XPqcInstR2<bits<7> funct7, bits<3> funct3, bits<7> opcode,
                 dag outs, dag ins, string opcodestr, string argstr>

    : RVInst<outs, ins, opcodestr, argstr, [ ], InstFormatR> {

  bits<5> rs1; bits<5> rd;
  let Inst{31-25} = funct7; let Inst{24-20} = 0; let Inst{19-15} = rs1;
  let Inst{14-12} = funct3; let Inst{11-7} = rd;  let Inst{6-0} = opcode;
  let hasSideEffects = 0; let mayLoad = 0; let mayStore = 0;
}

// 0-operand R-type — Class 3
class XPqcInstR0<bits<7> funct7, bits<3> funct3, bits<7> opcode, string opcodestr>

    : RVInst<(outs), (ins), opcodestr, "", [ ], InstFormatR> {

  let Inst{31-25} = funct7; let Inst{24-20} = 0; let Inst{19-15} = 0;
  let Inst{14-12} = funct3; let Inst{11-7} = 0;   let Inst{6-0} = opcode;
  let hasSideEffects = 1;
}

// 4-operand (vs3 in funct7[31:27]) — Class 5
class XPqcInstR4<bits<2> f7low, bits<7> opcode,
                 dag outs, dag ins, string opcodestr, string argstr>

    : RVInst<outs, ins, opcodestr, argstr, [ ], InstFormatR> {

  bits<5> vs3; bits<5> rs2; bits<5> rs1; bits<5> rd;
  let Inst{31-27} = vs3;  let Inst{26-25} = f7low; let Inst{24-20} = rs2;
  let Inst{19-15} = rs1;  let Inst{14-12} = 0;      let Inst{11-7} = rd;
  let Inst{6-0} = opcode;
}

// I-type load — Class 2
class XPqcInstILoad<bits<3> funct3, bits<7> opcode,
                    dag outs, dag ins, string opcodestr, string argstr>

    : RVInst<outs, ins, opcodestr, argstr, [ ], InstFormatI> {

  bits<12> imm12; bits<5> rs1; bits<5> rd;
  let Inst{31-20} = imm12; let Inst{19-15} = rs1;
  let Inst{14-12} = funct3; let Inst{11-7} = rd; let Inst{6-0} = opcode;
  let mayLoad = 1;
}

// I-type ALU — Class 2
class XPqcInstIALU<bits<3> funct3, bits<7> opcode,
                   dag outs, dag ins, string opcodestr, string argstr>

    : RVInst<outs, ins, opcodestr, argstr, [ ], InstFormatI> {

  bits<12> imm12; bits<5> rs1; bits<5> rd;
  let Inst{31-20} = imm12; let Inst{19-15} = rs1;
  let Inst{14-12} = funct3; let Inst{11-7} = rd; let Inst{6-0} = opcode;
}

// I-type no destination (CSR/internal state write) — Class 2
class XPqcInstINord<bits<3> funct3, bits<7> opcode,
                    dag outs, dag ins, string opcodestr, string argstr>

    : RVInst<outs, ins, opcodestr, argstr, [ ], InstFormatI> {

  bits<12> imm12;
  let Inst{31-20} = imm12; let Inst{19-15} = 0;
  let Inst{14-12} = funct3; let Inst{11-7} = 0; let Inst{6-0} = opcode;
  let hasSideEffects = 1;
}

// VPU store (LINEAR format: imm[11:0] + rs2 + funct3 + rs1 + opcode)
class XPqcInstS<bits<3> funct3, bits<7> opcode,
                dag outs, dag ins, string opcodestr, string argstr>

    : RVInst<outs, ins, opcodestr, argstr, [ ], InstFormatI> {

  bits<12> imm12; bits<5> rs2; bits<5> rs1;
  let Inst{31-20} = imm12; let Inst{19-15} = rs2;
  let Inst{14-12} = funct3; let Inst{11-7} = rs1; let Inst{6-0} = opcode;
  let mayStore = 1;
}

// B-type branch — Class 2
class XPqcInstB<bits<3> funct3, bits<7> opcode,
                dag outs, dag ins, string opcodestr, string argstr>

    : RVInst<outs, ins, opcodestr, argstr, [ ], InstFormatB> {

  bits<13> imm13; bits<5> rs2; bits<5> rs1;
  let Inst{31} = imm13{12};    let Inst{30-25} = imm13{10-5};
  let Inst{24-20} = rs2;       let Inst{19-15} = rs1;
  let Inst{14-12} = funct3;    let Inst{11-8} = imm13{4-1};
  let Inst{7} = imm13{11};     let Inst{6-0} = opcode;
  let isBranch = 1; let isTerminator = 1;
}

// U-type — Class 6
class XPqcInstU<bits<7> opcode, dag outs, dag ins, string opcodestr, string argstr>

    : RVInst<outs, ins, opcodestr, argstr, [ ], InstFormatOther> {

  bits<20> imm20; bits<5> rd;
  let Inst{31-12} = imm20; let Inst{11-7} = rd; let Inst{6-0} = opcode;
}

```

#### 11.4.4 定义全部 VPU/BNPU/SYM 指令

**新建文件**：`llvm/lib/Target/RISCV/RISCVInstrInfoXPqc.td`

这是指令定义的核心文件。以几条有代表性的指令为例：

```tablegen
include "RISCVInstrFormatsXPqc.td"

let Predicates = [HasVendorXPqc] in {

// --- Class 1: R-type 3-operand ---
def VAND : XPqcInstR<0b1001000, 0b100, 0b0000101,
    (outs VR:$rd), (ins VR:$rs1, VR:$rs2), "vand", "$rd, $rs1, $rs2">;

// --- Class 4: R-type 2-operand (CC 寄存器指令) ---
def VMVVCC : XPqcInstR2<0b0011100, 0b000, 0b0000101,
    (outs VR:$rd), (ins CCReg:$rs1), "vmvvcc", "$rd, $rs1">;

def VMVCCV : XPqcInstR2<0b0100000, 0b000, 0b0000101,
    (outs CCReg:$rd), (ins VR:$rs1), "vmvccv", "$rd, $rs1">;

// --- Class 3: 0-operand ---
def VKYBREJUNI : XPqcInstR0<0b0001100, 0b000, 0b0000101, "vkybrejuni">;

// --- Class 2-I-load: load to CC ---
def VLCC : XPqcInstILoad<0b001, 0b0010001,
    (outs CCReg:$rd), (ins GPR:$rs1, simm12:$imm12),
    "vlcc", "$rd, ${imm12}(${rs1})">;

// --- Class 2-S: store from CC (线性格式) ---
def VSCC : XPqcInstS<0b011, 0b0010001,
    (outs), (ins CCReg:$rs2, GPR:$rs1, simm12:$imm12),
    "vscc", "$rs2, ${imm12}(${rs1})">;

// --- Class 5: 4-operand ---
def XORV3VX : XPqcInstR4<0b01, 0b0000101,
    (outs VR:$rd), (ins VR:$rs1, VR:$rs2, VR:$vs3),
    "xorv3vx", "$rd, $rs1, $rs2, $vs3">;

// --- Class 6: U-type ---
def VPQCOEFF : XPqcInstU<0b0000001,
    (outs VR:$rd), (ins uimm20:$imm20),
    "vpqccoeff", "$rd, $imm20">;

} // HasVendorXPqc

```

**新建文件**：`llvm/lib/Target/RISCV/RISCVInstrFormatsBNPU.td` 和 `RISCVInstrInfoBNPU.td`

BNPU 使用 8-bit opcode + 6-bit 寄存器编码，共 7 种格式（详见第 5.2 节）。LLVM 中的实现模式与 VPU 相同，主要区别是自定义 `RISCVReg6` 寄存器类和 8-bit opcode 的解码器。

**注册新文件**：在 `llvm/lib/Target/RISCV/RISCVInstrInfo.td` 末尾添加：

```tablegen
include "RISCVInstrFormatsXPqc.td"
include "RISCVInstrInfoXPqc.td"
include "RISCVInstrFormatsBNPU.td"
include "RISCVInstrInfoBNPU.td"

```

#### 11.4.5 适配反汇编器

**文件**：`llvm/lib/Target/RISCV/Disassembler/RISCVDisassembler.cpp`

VPU 指令使用 `inst[1:0]=01`，标准 RISC-V 反汇编器将其路由到压缩指令解码器。需要修改 `getInstruction()`：

```cpp
// 在 getInstruction() 中，inst[1:0] != 11 时：
if ((Bytes[0] & 0b11) != 0b11) {
    // xpqc 32-bit 指令优先于压缩指令
    if (STI.hasFeature(RISCV::FeatureVendorXPqc) && Bytes.size() >= 4) {
        DecodeStatus Result = getInstruction32(MI, Size, Bytes, Address, CS);
        if (Result == MCDisassembler::Success) return Result;
    }
    return getInstruction16(MI, Size, Bytes, Address, CS);
}

```

同时手写两个自定义解码函数（VPU/BNPU 指令不在 TableGen 自动生成的解码表中）：

*   `decodeXPqc32()` — 覆盖全部 7-bit opcode VPU 指令，switch-case 匹配 opcode + funct3/funct7
    
*   `decodeBNPU32()` — 覆盖全部 8-bit opcode BNPU 指令
    

解码器中还需提供 `AddCReg` 和 `AddVReg` lambda、以及 `DecodeCCRegRegisterClass` / `DecodeBNPURegRegisterClass` 等寄存器解码函数。

#### 11.4.6 互斥检查

**文件**：`llvm/lib/TargetParser/RISCVISAInfo.cpp`

XPqc 编码占用了大量 RISC-V 标准扩展的 opcode 空间，必须与以下扩展互斥：

| 扩展 | 互斥原因 |
| --- | --- |
| **A** | XPqc 占用 atomic 操作 opcode 空间 |
| **C** | XPqc BNPU 指令 `inst[1:0]` 可为 `00`/`10`，若开启 C 扩展会被误识别为 16-bit 压缩指令 |
| **V**（RVV） | XPqc 占用 OP-V (0x57) RVV opcode 空间 |
| **Zba/Zbb/Zbc/Zbs** | XPqc 占用 OP-32 funct7 子空间 |
| **Zbkb/Zbkc/Zbkx** | XPqc 占用 scalar crypto 编码 |
| **Zk/Zkn/Zknd/Zkne/Zknh** | 同上，scalar crypto 整体冲突 |
| **Zks/Zksed/Zksh/Zkr/Zkt** | 同上 |
| **Zicond** | XPqc 占用 conditional move 编码 |
| **Zfa/Zfh/Zfhmin/Zfbfmin** | XPqc 占用 FP 扩展编码 |
| **Zvbb/Zvbc/Zvfh/Zvfhmin** | 同 V（RVV 子集冲突） |
| **Zvkb/Zvkg/Zvkn/Zvks/Zvkt** | 同 V |

设计原则：XPqc 是一个 "subset profile"——SPUV3 不是通用 RVV/标量加密兼容核，使用者预期就是为密码算法编程，不指望跑标准 RVV/Zk 代码。

在 `checkDependency()` 函数中实现：

```cpp
// xpqc uses the same opcode space as standard C/V/A/etc.
// Must be mutually exclusive to prevent decode conflicts.
if (HasExt("xpqc")) {
    for (auto ext : {"a", "c", "v", "zba", "zbb", "zbc", "zbs",
        "zbkb", "zbkc", "zbkx", "zk", "zkn", "zknd", "zkne", "zknh",
        "zks", "zksed", "zksh", "zkr", "zkt", "zicond", "zfa", "zfh",
        "zfhmin", "zfbfmin", "zvbb", "zvbc", "zvfh", "zvfhmin",
        "zvkb", "zvkg", "zvkn", "zvks", "zvkt"})
        if (HasExt(ext)) return false;
}

```

验证：

```bash
# 应报错——xpqc 与标准 V 扩展互斥
clang --target=riscv64 -march=rv64imv_xpqc -c test.s
# error: 'xpqc' extension is incompatible with 'v'

```

#### 11.4.7 增量构建与验证

每次修改 `.td` 或 `.cpp` 文件后：

```bash
cd ~/llvm-project
ninja -C build llvm-mc llvm-objdump    # 只编译有变化的文件

# 验证汇编
echo 'vmvvcc v0, c1' | build/bin/llvm-mc -triple=riscv64 -mattr=+xpqc -show-encoding
# encoding: [0x05,0x80,0x00,0x38]

# 验证反汇编
echo '0x05 0x80 0x00 0x38' | build/bin/llvm-mc -triple=riscv64 -mattr=+xpqc -disassemble
# vmvvcc v0, c1

# 与 Python 汇编器对比
python3 as/src/dcf_spu_as_cmd.py --stdin <<< "vmvvcc v0, c1"

```
---

### 11.5 跨平台工具链构建

修改 LLVM 源码后，有两种方式使用工具链：

*   **本地开发**：直接用 `~/llvm-project/build/bin/`（ninja 增量编译，改完即用）
    
*   **跨平台发布**：用容器编译 portable release 包
    

#### 11.5.1 构建脚本组织

```plaintext
~/llvm-project/scripts/
├── build_toolchain.sh         Linux portable（CentOS 7+, glibc ≥ 2.17）
└── build_toolchain_mingw.sh   Windows 交叉编译（x86_64-w64-mingw32）

```

#### 11.5.2 Linux Portable 构建（`build_toolchain.sh`）

**原理**：使用 podman + `manylinux2014` 镜像（CentOS 7 + glibc 2.17 + GCC 10），在容器内部编译 LLVM。因为容器内的 glibc 版本是老版本，编译出的二进制链接到 glibc 2.17，在任何 CentOS 7/Rocky 8/9/Ubuntu 18+ 上都能运行。

**执行**：

```bash
# 安装 podman（首次，WSL 推荐 podman，不需 daemon）
sudo apt install podman

# 运行构建（~20 分钟，首次需拉取 manylinux2014 镜像 ~2 分钟）
bash ~/llvm-project/scripts/build_toolchain.sh

```

**内部过程**：

```plaintext
manylinux2014 容器内：
  1. 安装 cmake 3.29（从 GitHub 下载，容器 yum cmake 3.17 太老）
  2. 安装 ninja-build（yum）
  3. 启用 devtoolset-10（GCC 10）
  4. cmake -S /src/llvm -B build （/src 是宿主机 ~/llvm-project 的只读挂载）
  5. ninja clang lld llvm-objdump llvm-size llvm-nm llvm-objcopy
  6. ninja install → /tmp/install
  7. tar czf → /out/llvm-xpqc-19.1-centos7.tar.gz（/out 是宿主机 toolchains/ 目录）

```

**产物**：

```plaintext
~/llvm-project/toolchains/llvm-xpqc-19.1-centos7.tar.gz  (~844 MB)
解压后: bin/ lib/ include/ 三个目录，开箱即用

```

#### 11.5.3 Windows 交叉编译（`build_toolchain_mingw.sh`）

使用 Fedora 40 容器 + MinGW 交叉编译器，分两阶段：

1.  **Stage 1**：构建 Linux 原生 TableGen 等构建工具（~10 分钟）
    
2.  **Stage 2**：用 `x86_64-w64-mingw32` 交叉编译 Windows 二进制（~20 分钟）
    

产物需附带 MinGW 运行时 DLL（`libstdc++-6.dll`、`libgcc_s_seh-1.dll`、`libwinpthread-1.dll`），脚本自动复制到 `install/bin/`。

---

### 11.6 固件集成教程：SPU 汇编 → LLVM C+汇编混合编译

SPUV3 固件原本只用 Python 汇编器独立编译。要将固件和 C 测试代码集成到单个 ELF，需要经过以下完整流程。

#### 11.6.1 预处理：Python 汇编语法 → LLVM 兼容格式

**脚本**：`scripts/spu_preprocess_llvm.py`

由于 Python 汇编器和 LLVM clang 对 `.s` 文件的语法要求不同，需要预处理脚本：

| 差异点 | Python 汇编器 | LLVM clang 要求 | 预处理操作 |
| --- | --- | --- | --- |
| CSR 地址宏 | `#define MSTATUS 0x200`（注释行） | 不识别 `#define` | 转换为 `.equ MSTATUS, 0x200` |
| 段声明 | 无（隐含 `.text`） | 必须显式声明 | 自动插入 `.section .firmware.text, "ax"` |
| 行尾逗号 | `bnmv b6, b56,\n bnmv b7, b57` | 行尾逗号导致两行合并 | `re.sub(r',[ \t]*\n', ...)` |
| 连续空格 | 多处 | 无要求但影响可读性 | 规范化到单个空格 |
| 重复标签 | `mlkem_encap_xxx:` 出现多次（dec 固件） | 不允许重复 | 保留最后出现，之前的加 `_dup` 后缀 |
| C 寄存器 | `c0-c31`（CC 寄存器） | LLVM 已原生支持 `c0-c31` | 不再转换（v1.6 之前 `c\d+ → v\d+`） |

**使用**：

```bash
python3 scripts/spu_preprocess_llvm.py firmware/mlkem512_keypair.s firmware_pp.s \
    --section=.firmware.text

```

`--section` 参数指定固件代码段名（默认为 `.text`）。使用独立段名（如 `.firmware.text`）是为了在链接脚本中精确控制固件代码的布局。

#### 11.6.2 链接脚本设计

**文件**：`ctests/mlkem512_c/test.ld`

混合固件+C 的 ELF 使用哈佛架构的内存布局：

```ld
MEMORY {
    ILM (rx)  : ORIGIN = 0x00000000, LENGTH = 128K
    DLM (rw)  : ORIGIN = 0x00800000, LENGTH = 64K
}

SECTIONS {
    /* === ILM: 指令段 === */
    .init      : { crt0.o(.init) } >ILM
    .text      : { *(.text) } >ILM
    .firmware.text : { *(.firmware.text) } >ILM

    /* === DLM: 数据段 === */
    .firmware.rodata (NOLOAD) : {
        . = ABSOLUTE(ORIGIN(DLM) + 0x6000);   /* 固件预留 24KB */
    } >DLM
    .fw_save_area (NOLOAD) : ALIGN(32) {
        PROVIDE(__fw_save_area = .);
        . += 128;                              /* 16 个 callee-saved reg */
        PROVIDE(__fw_save_area_end = .);
    } >DLM
    .data : ALIGN(32) { *(.data .data.*) } >DLM
    .rodata : ALIGN(8) { *(.rodata .rodata.*) } >DLM
    .bss (NOLOAD) : ALIGN(8) { *(.bss .bss.*) } >DLM
}

```

关键点：

*   `0x6000`（24KB）：固件 workspace 预留。固件将 DLM 低 24KB 用作 const 数据区 + 临时变量 + 栈。若固件增大，修改此值即可
    
*   `__fw_save_area`：链接器导出的符号，C 和固件都通过它访问寄存器保存区，不硬编码地址
    
*   `.firmware.rodata` 段标为 `NOLOAD`：仅声明地址但不加载数据，实际数据由 `const.hex` 提供
    

#### 11.6.3 C ↔ 固件寄存器上下文切换

**问题**：固件 `start:` 入口会清零全部 GPR（x1-x31）、BNPU 寄存器（b0-b63）、VPU 寄存器（v0-v31）。C 调用固件后，所有寄存器上下文丢失，`ret` 无法返回到 C。

**方案**：在 `.fw_save_area`（链接器管理的 128B 区域）保存/恢复 16 个 callee-saved 寄存器。

**C 端**（`fw_wrapper.S`）——调用前保存：

```asm
call_firmware:
    la t0, __fw_save_area
    sd ra,   0(t0); sd sp,   8(t0); sd gp,  16(t0); sd tp,  24(t0)
    sd s0,  32(t0); sd s1,  40(t0); ...          ; sd s11,120(t0)
    call start          # 跳入固件
    ret                 # 固件不返回到这里，直接 j 到 C label

```

**固件端**——完成后恢复并跳回：

```asm
func_over_return_to_c:
    la   t6, __fw_save_area
    ld ra,    0(t6); ld sp,    8(t6); ld gp,   16(t6); ld tp,   24(t6)
    ld s0,   32(t6); ld s1,   40(t6); ...            ; ld s11, 120(t6)
    j global_lable_post_spu_asm    # 直接跳回 C 标签，不用 ret

```

**C 端**（`mlkem512_c.c`）——用标签标记返回点：

```c
extern void call_firmware(void);

asm volatile(".globl global_lable_pre_spu_asm\n"
             "global_lable_pre_spu_asm:\n");
call_firmware();
asm volatile(".globl global_lable_post_spu_asm\n"
             "global_lable_post_spu_asm:\n");

```

注意事项：

*   **t0-t6/a0-a7 不需要保存**：这些是 caller-saved，编译器在 `call_firmware()` 调用前后自动处理
    
*   **不能用 inline asm 保存寄存器**：固件 `j` 到 C label 绕过了编译器的恢复代码路径，inline asm 的 clobber list 只对 asm 块本身有效
    
*   **固件必须用** `**j**` **而不是** `**ret**`：固件的 `ra` 已被清零
    
*   **sp 必须恢复**：否则返回 C 后 `dcf_printf` 等函数的栈操作挂死
    
*   **固件中的 MSTATUS done 写必须注释掉**：否则仿真在固件内就结束，C 的 golden 比对不会执行
    

#### 11.6.4 完整构建流程（`ctests/mlkem512_c/build.sh`）

```plaintext
Phase 1: spu_preprocess_llvm.py  →  firmware_pp.s
Phase 2: 拷贝 C 源码 + fw_wrapper.S + printf.c + _stubs.c
Phase 3: clang -c 编译所有 .c / .S / .s 文件
         (CFLAGS: --target=riscv64 -march=rv64imfd_zicsr_zifencei_xpqc
                  -ffreestanding -nostdlib -fno-builtin)
Phase 4: lld -T test.ld *.o -o mlkem512_c.elf
Phase 5: llvm-objdump 提取 hex
         ├── ILM: .init + .text + .firmware.text → ilm.hex (32-bit words, little-endian)
         └── DLM: const.hex + zero pad + C .data/.rodata → dlm.hex (256-bit rows, 字节对翻转)
Phase 6: 拷贝 hex 到 ctests/ + sim/ + tb/mlkem_regress/

```

**DLM hex 自动对齐**：

```python
# 从 ELF .data VMA 自动推算固件预留区域大小
data_vma = read_elf_section(".data").vma
reserved = data_vma - dlm_base   # = 0x6080（含 const + zero pad）
c_data_offset = reserved // 32    # DLM row 起始位置

```

**字节对翻转**：`$readmemh` 加载 256-bit 宽内存时，左端 hex 对应高字节地址，因此每行 64 hex 字符需按字节对翻转（`pairs.reverse()`）。

**参数化构建**：支持所有 9 个 ML-KEM 变体：

```bash
bash build.sh \
    ../tb/mlkem768_enc/mlkem768_enc.s \          # 固件源码
    ../tb/mlkem768_enc/data.hex \                # 输入数据
    ../tb/mlkem768_enc/result.txt \              # golden
    ../tb/mlkem768_enc/const.hex                 # 固件常量

```
---

### 11.7 环境脚本详解

#### 11.7.1 `SourceMe` — 开发环境入口

```bash
source SourceMe   # 在 spuv3 工程根目录执行

```

导出变量：

*   `SPUV3_LLVM_HOME`：LLVM xpqc 工具链安装路径（默认 `~/toolchains/llvm-xpqc-19.1`）
    
*   `DESIGN_ENV_HOME`：spuv3 工程根目录
    
*   `PYTHONPATH`：附加 `cfgkit/`
    

所有 SPUV3 脚本通过 `${SPUV3_LLVM_HOME:-$HOME/llvm-project/build}` 查找 LLVM，未设置时自动 fallback 到本地构建目录。

#### 11.7.2 `scripts/spu_preprocess_llvm.py` — 固件预处理

```bash
python3 scripts/spu_preprocess_llvm.py <input.s> <output.s> [--section NAME]

```

将 Python 汇编器语法的 `.s` 文件转换为 LLVM clang 可接受的格式。

#### 11.7.3 `scripts/llvm_assemble.sh` — 单文件快速汇编

```bash
bash scripts/llvm_assemble.sh firmware.s output.hex [output.dis]

```

完整管道：预处理 → clang 编译 → lld 链接 → objdump 提取 hex → 可选反汇编。

#### 11.7.4 `scripts/ctest_llvm.sh` — C 程序快速编译

```bash
bash scripts/ctest_llvm.sh coremark    # 编译 ctests/coremark/ → 生成 ilm.hex/dlm.hex

```

#### 11.7.5 `scripts/mlkem_regress.sh` — 回归测试

```bash
bash scripts/mlkem_regress.sh    # 构建 + 仿真全部 9 个 ML-KEM 测试

```

每个测试自动：构建 ELF → 拷贝 data/result → 运行 simv → golden 比对 → PASS/FAIL。

#### 11.7.6 `sim/Makefile` — 仿真集成

`LLVM=1` 开关切换 LLVM 工具链 vs Python 汇编器：

```bash
cd sim
make simv                              # 编译 RTL（首次自动编译）
make mlkem                             # mlkem512_keypair 构建+仿真
make mlkem_regress                     # 全部 9 个测试
LLVM=1 make rand_count COUNT=1 APP=mlkem1024_keypair   # LLVM 工具链

```

Makefile 中关键变量：

```makefile
LLVM_HOME ?= $(or $(SPUV3_LLVM_HOME),$(HOME)/llvm-project/build)
LLVM_CLANG := $(LLVM_HOME)/bin/clang

```

#### 11.7.7 `as/tools/test_vpu_llvm.sh` — VPU 指令全量测试

```bash
bash as/tools/test_vpu_llvm.sh   # 48 条 VPU 指令：汇编 → 反汇编 → 编码验证 → 互斥检查

```

#### 11.7.8 `as/tools/compare_llvm_vs_python.sh` — 逐指令交叉验证

```bash
bash as/tools/compare_llvm_vs_python.sh   # 70 个固件文件，131,333 条指令逐字节对比

```
---

### 11.8 工具链部署规范

#### 11.8.1 `SPUV3_LLVM_HOME` 环境变量

```plaintext
开发流程：
  source SourceMe                             → 自动设置
  export SPUV3_LLVM_HOME=/opt/llvm-xpqc      → 手动覆盖
  不设置                                      → fallback 到 ~/llvm-project/build

```

#### 11.8.2 多版本共存

```plaintext
~/toolchains/
├── llvm-xpqc-19.1-centos7/       # CentOS 7 兼容版
├── llvm-xpqc-19.1/               # 源码 build（仅本机）
└── llvm-xpqc-20.x-centos7/       # 未来版本

```

切换版本只需修改 `SourceMe` 中的一行 `export SPUV3_LLVM_HOME=...` 或 export 环境变量。

#### 11.8.3 源码修改后的更新流程

```bash
# 1. 修改 ~/llvm-project/ 源码
vim ~/llvm-project/llvm/lib/Target/RISCV/RISCVInstrInfoXPqc.td

# 2. 本地验证
cd ~/llvm-project && ninja -C build llvm-mc llvm-objdump clang lld
echo 'vmvvcc v0, c1' | build/bin/llvm-mc -triple=riscv64 -mattr=+xpqc -show-encoding

# 3. spuv3 工程验证
source ~/spuv3_main_llvm_test/SourceMe
bash ctests/mlkem512_c/build.sh

# 4. 发布 release
bash ~/llvm-project/scripts/build_toolchain.sh    # ~20 min
tar xzf ~/llvm-project/toolchains/llvm-xpqc-19.1-centos7.tar.gz \
    -C ~/toolchains/llvm-xpqc-19.1

```
---

### 11.9 关键文件索引

| 文件 | 内容 | 开发者何时修改 |
| --- | --- | --- |
| `llvm/lib/Target/RISCV/RISCVFeatures.td` | `FeatureVendorXPqc` 扩展定义 | 新增扩展或修改特性 |
| `llvm/lib/Target/RISCV/RISCVRegisterInfo.td` | V/C/B 寄存器定义（VRVPU0-31, C0-31, BN0-63） | 新增寄存器组 |
| `llvm/lib/Target/RISCV/RISCVInstrFormatsXPqc.td` | VPU 9 种自定义格式类 | 新增编码格式 |
| `llvm/lib/Target/RISCV/RISCVInstrInfoXPqc.td` | VPU+SYM/SBOX+CSR 全部指令 | **最常修改**——新增指令 |
| `llvm/lib/Target/RISCV/RISCVInstrFormatsBNPU.td` | BNPU 7 种格式（A-G） | 新增 BNPU 编码格式 |
| `llvm/lib/Target/RISCV/RISCVInstrInfoBNPU.td` | BNPU 全部指令 | 新增 BNPU 指令 |
| `llvm/lib/Target/RISCV/RISCVInstrInfo.td` | include 新文件入口 | 新增 .td 文件后注册 |
| `llvm/lib/Target/RISCV/Disassembler/RISCVDisassembler.cpp` | decodeXPqc32/decodeBNPU32/AddCReg | 新增指令反汇编 |
| `llvm/lib/TargetParser/RISCVISAInfo.cpp` | xpqc 互斥检查 | 扩展冲突关系变化 |
| `scripts/spu_preprocess_llvm.py` | 固件预处理 | 汇编器语法差异变化 |
| `scripts/llvm_assemble.sh` | 单文件快速汇编 | — |
| `scripts/ctest_llvm.sh` | C 程序编译 | — |
| `scripts/mlkem_regress.sh` | 回归测试入口 | 新增测试算法 |
| `ctests/mlkem512_c/build.sh` | C+固件混合构建 | 链接布局变化 |
| `ctests/mlkem512_c/test.ld` | 链接脚本 | 内存分区调整 |
| `ctests/mlkem512_c/fw_wrapper.S` | C↔固件寄存器保存 | 调用约定变化 |
| `sim/Makefile` | 仿真集成（LLVM=1 开关） | 构建目标变化 |
| `SourceMe` | `SPUV3_LLVM_HOME` 导出 | 工具链路径变化 |

### 11.10 常见问题

| 症状 | 原因 | 解决 |
| --- | --- | --- |
| `llvm-mc: unknown instruction` | 没有传 `-mattr=+xpqc` | 所有 clang/llvm-mc 命令必须带 `-march=rv64imfd_zicsr_zifencei_xpqc` 或 `-mattr=+xpqc` |
| `error: instruction use requires` | 扩展已注册但指令未定义 | 检查 RISCVInstrInfoXPqc.td 语法，确认 `let Predicates = [HasVendorXPqc]` |
| `DecodeCCRegRegisterClass was not declared` | TableGen 自动生成了解码表条目但缺少手写函数 | 在 RISCVDisassembler.cpp 添加对应的 `Decode*RegisterClass` 函数 |
| 反汇编输出 `v0` 而不是 `c0` | 旧版 llvm-objdump 未重新编译 | `ninja -C build llvm-objdump`（反汇编器和 llvm-mc 是独立二进制） |
| `clang -c` 成功但 `llvm-mc -filetype=obj` 失败 | VPU 指令使用 InstFormatOther，llvm-mc -filetype=obj 路径不支持 | 坚持用 clang -c + lld 路线 |
| VPU store 编码与 Python 不同 | LLVM 用了标准 S-type 分割立即数格式，SPU 用线性格式 | 自定义 XPqcInstS 为 `imm[11:0]+rs2+funct3+rs1+opcode` |
| 预处理后 `bnmv b6, b56,` + `bnmv b7, b57` 被连成一行 | `re.sub(r',\s*$', ...)` 中 `\s` 匹配了 `\n` | 改为 `re.sub(r',[ \t]*\n', '\n', ...)` |
| 固件返回 C 后 printf crash | 固件清零了 sp/gp | 固件必须从 `__fw_save_area` 恢复全部 callee-saved 寄存器 |
| `dcf_printf` 写 DPRAM 覆盖 seed 数据 | DPRAM en 信号未限制地址范围 | 加 `(data_addr_o >= DLM_SIZE_BYTE) & (data_addr_o < DLM_SIZE_BYTE + DPRAM_SIZE_BYTE)` 检查 |
| `__firmware_dlm_reserved = 0x2000` 实际链接出 0x8000 | lld 变量求值 bug（4x） | 直接硬编码到 section 定义 |
| 回归全部 PASS 但改 data 仍 PASS | golden 比对只比一行（mstatus\[29:0\]=1） | 改为遍历 golden 文件实际行数 |

> **完整实现记录与调试日志**：详见 `docs/superpowers/specs/2026-05-25-llvm-spu-full-implementation.md`

### 11.11 LLVM 迁移分阶段策略与工作量评估

当前 LLVM xpqc 扩展已完成 **MC 层全覆盖**（~330 条指令的汇编+反汇编，131,333 条逐字节验证）。如果未来需要进一步推进到 **Clang builtins + codegen**（让编译器自动从 C 生成 XPqc 指令），可参考以下分阶段策略。

#### 11.11.1 工程量评估

| 维度 | 当前状态（MC 层） | 完整产品级（MC + codegen + builtins） |
| --- | --- | --- |
| 指令覆盖 | ~330 条（100%） | ~330 条 |
| TableGen 代码量 | ~2,000 行（已完成） | 4,000–6,000 行 |
| Clang builtins | 0 | ~300 个（与指令 1:1） |
| lit 测试用例 | ~50 个（MC 编码验证） | 600–900 个 |
| 工作量（1 名开发） | 已完成 | 3–6 个月（MVP: 通用+1 家族） |
| 工作量（3 人团队） | — | 3–4 个月 |

#### 11.11.2 探索性分阶段路线

如果继续推进 LLVM 集成深度，关键设计是**任意阶段停下都有可用产物**：

```plaintext
Phase 0 (1 周)   : fork llvm-project, 跑通全量构建, GO/NO-GO 评估
Phase 1 (2 周)   : ISA 声明 + mutex 检查（已完成）
Phase 2-3 (4-6 周) : B/V 寄存器 + 全部指令 MC 层 + 反汇编（已完成）
         ↓
    决策点 1：替代 Python 汇编器是否成立？ → 当前状态：✅ 成立
         ↓
Phase 4 (2 周)   : Clang builtins（__builtin_riscv_pqc_*）
Phase 5 (1 周)   : Inline asm 约束（"Br"/"Vr" 寄存器约束字符串）
Phase 6 (17 周)  : 按算法家族分批实现 codegen pattern
  ├── 6a 通用 ~40 条 (3 周)
  ├── 6b 格密 ~80 条 (4 周)
  ├── 6c 哈希 ~50 条 (3 周)
  ├── 6d 国密 ~80 条 (4 周)
  └── 6e 传统 ~50 条 (3 周)
         ↓
    决策点 2：是否产品化（需要 codegen 自动生成 XPqc 指令）？
         ↓
Phase 7 (1 周)   : Driver/链接器（clang --target=riscv64 -march=..._xpqc 一站式）
Phase 8 (持续)   : 维护策略选择（Fork vs 上游）

```
> **当前建议**：停在 Phase 2-3（MC 层全完成）。MC 层已经覆盖了 100% 的使用场景——固件用 LLVM 汇编 `.s` 文件、链接 ELF、反汇编调试。Clang builtins 和 codegen 的增量收益远小于增量成本（详见第 12 节"为何 SPU 不适用于 LLVM"的完整分析）。

### 11.12 Clang Builtins 与 Inline Asm 路线（Phase 4-5，参考）

> 以下内容为**未来参考**，当前 SPUV3 工程不走此路线。

#### Builtins 开发流（Phase 4）

如果需要 C 代码中直接调用 XPqc 指令：

```c
// clang/include/clang/Basic/BuiltinsRISCVXPqc.def
TARGET_BUILTIN(__builtin_riscv_pqc_bxor, "V32ScV32ScV32Sc", "nc", "xpqc")

// 用户 C 代码
typedef __attribute__((__vector_size__(32))) signed char b_reg_t;
b_reg_t result = __builtin_riscv_pqc_bxor(a, b);

```

实现涉及 5 个文件的修改链：

```plaintext
clang/include/clang/Basic/BuiltinsRISCVXPqc.def  ← builtin 声明
clang/lib/Sema/SemaChecking.cpp                   ← 类型检查
clang/lib/CodeGen/CGBuiltin.cpp                   ← IR 生成
llvm/include/llvm/IR/IntrinsicsRISCV.td           ← intrinsic 声明
llvm/lib/Target/RISCV/RISCVInstrInfoXPqc.td       ← intrinsic → 指令 pattern

```

#### Inline Asm 约束（Phase 5）

```c
b_reg_t result, a, b;
asm volatile ("pqc.bxor %0, %1, %2"
              : "=Br"(result)     // B 寄存器约束（自定义字符串）
              : "Br"(a), "Br"(b));

```

PPhase 4-5 的核心难点：

*   **V 寄存器 320-bit 是 LLVM illegal type**：`v40i8` 不走标准 legalization，需要全程用 builtin 包裹（不暴露 raw vector type 给 IR），或走 inline-asm-only 路线
    
*   **多 def 指令**（如 SM2 padd 3-out）TableGen 表达困难：需要 PseudoInst + custom expansion
    
*   **CSR runtime 配置影响指令语义**：vmask/modreg 改变指令行为，编译器无法静态分析——需要 inline asm + memory clobber 强制保守调度
    

### 11.13 维护策略：Fork vs 上游

| 维度 | Fork（推荐当前路线） | 上游到 LLVM 主线 |
| --- | --- | --- |
| 维护成本 | 每季度 LLVM rebase ~1-2 周 | 免维护，社区负责 |
| 改动自由度 | 完全自由，节奏自控 | 受社区 review 节奏限制（6-18 个月） |
| IP 保密 | ISA 设计不公开 | **必须公开全部 ISA 编码** |
| 适用场景 | 内部产品快速迭代 | 产品稳定后对外开源 |

**推荐路径**：先 Fork 内部维护 → 产品上线 6-12 个月后 ISA 稳定 → 选择性上游通用部分（如 B/V 寄存器类、CSR 接口），保留敏感算法指令（SM-series 等）私有。

参考：CORE-V、T-Head、SiFive 均成功上游过 vendor 扩展，路径成熟。但这些都是 ISA 已公开的商业/学术项目，与 SPU 的 IP 保护需求有本质区别。

### 11.14 关键风险与缓解

| 风险 | 严重度 | 缓解措施 |
| --- | --- | --- |
| 6-bit 寄存器编码（BNPU b0-b63）超出 TableGen 标准模板 | 中 | 已解决：自定义 `RISCVReg6` 类 + `let HWEncoding{5-0} = Enc` |
| VPU inst\[1:0\]=01 非标准 32-bit 编码 | 中 | 已解决：自定义 `XPqcInstR/I/S/B/U` 格式类，直接设 `Inst{6-0}` |
| V 寄存器 320-bit 是 LLVM illegal type | 高 | 当前不涉及 codegen；如需推进则走 inline-asm-only 或 builtin 包裹路线 |
| 多 def 指令 TableGen 表达困难 | 中 | 可用 PseudoInst + custom expansion；不影响 MC 层 |
| CSR runtime 配置（vmask/modreg）影响指令语义 | 高 | 用 inline asm + memory clobber 强制保守调度；MC 层无影响 |
| 公司是否允许 LLVM fork 内部维护 | 致命 | 已确认：允许（xpqc 扩展在当前 fork 中运行良好） |
| LLVM 主线 rebase 冲突 | 中 | 定制修改集中在 5 个文件 + 4 个新建文件，隔离度高，冲突面小 |
| ~330 条指令维护成本 | 中 | 已全部完成 MC 层（TableGen + 解码器）；新增指令 < 30 行/条，季度 rebase 冲突面小 |

### 11.15 参考项目

| 项目 | 参考价值 |
| --- | --- |
| [CORE-V LLVM](https://github.com/openhwgroup/corev-llvm-project) | vendor 扩展上游全过程，CV.MAC / CV.HWLOOP 指令实现 |
| [T-Head LLVM](https://github.com/T-head-Semi/llvm-project) | 国内厂商 vendor 扩展上游案例（XTHeadBa/Cmo/FMemIdx） |
| SiFive XSfvqmacc (`llvm/lib/Target/RISCV/RISCVInstrInfoXSfvqmacc.td`) | 自定义 vector/matrix 操作 .td 范例 |
| [Berkeley RoCC](https://github.com/chipsalliance/rocket-chip) | coprocessor port 编程模型 reference |
| [LLVM 后端入门](https://llvm.org/docs/WritingAnLLVMBackend.html) | TableGen 基础与指令描述 |
| [RISC-V Vector Intrinsic 文档](https://github.com/riscv-non-isa/rvv-intrinsic-doc) | builtin 命名约定与组织 |

## 12. 汇编器与工具链

### 专用汇编器

文件：`as/src/dcf_spu_as_cmd.py`（Python 3）

SPUV3 专用汇编器，将汇编源码翻译为两个 hex 文件：

*   `*_ilm.hex`：32-bit 宽指令 hex（加载到 ILM）
    
*   `*_dlm.hex`：256-bit 宽数据 hex（加载到 DLM）
    

**使用方式**：

```bash
python3 as/src/dcf_spu_as_cmd.py -i firmware/algo.s -o firmware/algo

```

**支持的全部指令集**：

*   完整 RV64IMFD（含全部浮点指令，支持可选舍入模式字段 `rne/rtz/rdn/rup/rmm/dyn`）
    
*   全部 BNPU 扩展指令（约 50 条，详见第 5 节）
    
*   全部 VPU 扩展指令（约 47 条，详见第 6 节）
    
*   CSR 指令（支持 `#define` 宏替换）
    

**汇编器寄存器 ABI 名称**：

```plaintext
整数：zero/ra/sp/gp/tp/t0-t6/s0-s11/a0-a7，或 x0-x31
浮点：ft0-ft11/fs0-fs11/fa0-fa7，或 f0-f31
大数：b0-b63
向量：v0-v31

```

### SPU 调用约定（汇编内部函数调用）

所有 SPU 汇编函数应遵循以下统一约定，以便例程之间可以自由调用：

**调用者保存（可被被调用函数修改，调用前如需保留则调用者自行入栈）**： `t0–t6`、`a0–a7`

**被调用者保存（必须在函数出入口保存/恢复）**： `s0–s11`、`ra`——在函数 prologue 保存，epilogue 恢复

**数据寄存器（RV64 GPR 不可见）**： `b0–b63`（BNPU，256-bit）、`v0–v31`（VPU 向量）

实践中大多数 SPU 例程将全部活跃数据保存在 BNPU/VPU 寄存器及 DTCM 中，`t` 系列寄存器仅用于循环计数和地址运算。因此通常只需保存 `ra`（如果发起子调用）和 `s0`（如果用作帧指针）。

```asm
keccak_1600:
    addi sp, sp, -32
    sw s0, 28(sp)       # 保存被调用者保存的 s0
    sw ra, 24(sp)       # 保存 ra（本函数内有 jal 子调用）
    addi s0, sp, 32

    li x5, 0            # x5 = t0: 循环计数器，调用者保存，无需手动保存
keccak_round:
    xorv3vx v6, v0, v1, v2   # VPU 指令——不影响 GP 寄存器
    bne x5, x6, keccak_round

    lw ra, 24(sp)       # 恢复
    lw s0, 28(sp)
    addi sp, sp, 32
    ret

```

### VMASK 所有权约定

`csrrwi x0, 0x700, N`（写 VMASK）是全局副作用，影响所有 VPU 向量操作的 lane 掩码。

*   **被调用者在调用期间拥有 VMASK**：在函数入口必须设置所需的 VMASK 值
    
*   **调用者不能假设 VMASK 跨调用保持不变**：若调用者在调用后需要特定 VMASK 值，必须在调用前用 `csrr` 保存并在调用后用 `csrw` 恢复
    

### 长跳转与函数调用

SPUV3 的 ILM 为 128 KB，所有函数调用和跳转目标均在 `jal` 的 ±1 MB 范围内，因此**直接使用** `**jal**` **即可，不需要** `**call**` **伪指令**：

```asm
    jal ra, target_func    # ra = PC+4, PC = target_func

```

ARM/Linux 等通用处理器需要 `call`（`auipc + jalr` 组合）是为了突破 ±1 MB 限制访问更大的地址空间，SPUV3 不存在此场景。

**RTL 层面对长跳转的支持**：SPUV3 完整实现了 `AUIPC` 和 `JALR` 的译码、调度、执行及写回通路（详见 `spuv3_idu.v:630-632`、`spuv3_exu_dispatch.v:297-505`、`spuv3_exu_alu_datapath.v:113-216`）。若未来 ILM 扩容导致目标超出 `jal` 范围，可手动展开为：

```asm
    # 等效于 call target，target 为 32-bit 绝对地址
    # 设 target[31:12] = HI, target[11:0] = LO
    # 若 LO 符号位为 1 (LO >= 0x800)，则 HI 需 +1，LO 需 -0x1000
    auipc t0, HI             # t0 = PC + sext(HI << 12)
    jalr  ra, t0, LO         # PC = t0 + sext(LO), ra = PC+4

```

AUIPC 写 t0 在 EX 末尾，JALR 读 t0 在 ID 阶段。SPUV3 流水线支持 EX→ID 转发，AUIPC 与 JALR 可背靠背执行，无需插入 `nop`。

### 汇编语法注意事项

1.  **不要在函数名之外使用** `**<>**`（汇编器对 `<>` 有特定的函数声明语义）
    
2.  **标签必须单独占一行**：`LABEL:` 之后不得有尾注释，例如：
    

```asm
# 正确
loop_start:
    addi t0, t0, 1

# 错误（会导致标签解析失败）
loop_start:   # loop begins here
    addi t0, t0, 1

```

### RV64IMFD GCC 工具链（标准 C 程序）

对于纯 RV64IMFD 部分，可使用标准 RISC-V GCC 编译链接：

```bash
riscv64-unknown-elf-gcc -march=rv64imfd -mabi=lp64d \
    -nostdlib -T linker.ld -O2 -o main.elf main.c
riscv64-unknown-elf-objcopy -O ihex main.elf main.hex

```

编译生成的 `.hex` 文件加载到 ILM，调用 BNPU/VPU 算法函数时通过特殊汇编指令（专用汇编器生成）或内联汇编实现。

### 为何不使用宏汇编C（GCC + inline asm）

SPUV3 固件**全部采用纯汇编**（`.s` 文件 + `dcf_spu_as_cmd.py`），而非 GCC + `vpu_instr.h` / `bnpu_instr.h` 宏内联汇编的"宏汇编C"风格。以下是背景说明。

#### 宏汇编C 的实现原理

宏汇编C 中，BNPU/VPU 指令以 `asm volatile(".word %0" : : "i"(INST(...)))` 形式内联。GCC 把宏展开结果当作一个 32-bit 整型立即数直接写入指令流，完全不理解其语义：

```c
#define XORV3VX(vd, vs1, vs2, vs3) \
    asm volatile(".word %0" : : "i" (VPU_RTYPE(0x05, vd, 0, vs1, vs2, (0b01 | (vs3)<<2))))

```

表面上像 C，实质仍是汇编——VPU/BNPU 指令数量与纯汇编完全相同，多出的只是 GCC 的包裹层。

#### 核心限制：所有操作数必须是编译期常量

`"i"` 约束要求 GCC 在编译时就将整个 32-bit 机器码算出常数，因此：

```c
int vd = get_target_reg();     // ❌ error: asm operand is not a constant
VSLLI(vd, 1, 64);

for (int s = 0; s < 8; s++) {
    VSLLI(0, 0, s * 16);       // ❌ 's' is not a constant expression
}

int offset = addr_table[i];
_VLEVX(0, 10, offset, base);   // ❌ offset must be a constant

```

唯一的运行时传值通道是通过 GPR（`"r"` 约束）传地址，但 GPR 索引本身仍是编译期决定，无法动态化。纯汇编无此限制——动态偏移只需折入 GPR：`add x10, x10, x12; vlevx v0, 0x0(x10)`。

#### 不选宏汇编C的理由

| 维度 | 纯汇编 | 宏汇编C |
| --- | --- | --- |
| **可读性** | `xorv3vx v6, v0, v1, v2` | `XORV3VX(6, 0, 1, 2)` + 多行 `register` 绑定，读 GPR 的指令更晦涩 |
| **寄存器可控性** | 完全控制 | GCC 不感知 v/b 寄存器，跨函数调用时有隐式状态破坏风险 |
| **运行时灵活性** | 偏移/shift 量可动态折入 GPR | 操作数全为编译期常量，无法动态化 |
| **性能** | 精确控制 prologue/epilogue | GCC 保守策略多保存寄存器，约 **−5%～−15%** 额外开销 |
| **调试** | PC 直接对应源码行 | `.word` 失去可追溯性，需手工还原宏展开 |

**ABI 陷阱**：GCC 遵循 RISC-V ABI，不感知 `v0–v31` / `b0–b63`——这些是 GCC 不可见的"隐藏状态"。当 C 函数调用另一个 C 函数时，GCC 不知道 VPU/BNPU 寄存器需要保存，可能导致跨调用的静默数据损坏。纯汇编中程序员完全决定哪些寄存器跨调用有效，无此风险。

**迁移成本**：SPUV3 现有约 73 个算法固件文件，其中约 80% 是 BNPU/VPU 自定义指令——无论哪种方式都必须走自定义汇编器或 `.word` 宏，可读性改善极其有限。仅剩 20% 的 RV64IMFD 标量控制流可用 C 语法简化，但这部分并不是维护瓶颈。存量代码全量迁移约需 **4–5 人年**，投入产出严重不平衡。

**适合用 GCC 的唯一场景**：`ctests/` 目录下的**纯 RV64IMFD 标量单元测试**（不涉及 VPU/BNPU），可正常使用 GCC 编译。

> **结论**：宏汇编C 不是纯汇编与 C 的中间路线，而是两者缺点的并集——保留了汇编的低可读性，同时引入了 GCC 的 ABI 约束、不可控优化与编译期常量限制。SPUV3 固件坚持使用纯汇编。

### 为何 SPU 不适用于 LLVM

虽然 SPUV3 项目已完成 LLVM xpqc 扩展的 MC 层适配（第 11 节），使得 LLVM 可以汇编全部自定义指令并链接为 ELF，但 LLVM **绝不**是 SPU 固件的主流构建工具。核心原因在于 LLVM 缺乏对自定义架构资源的语义理解，其价值在本项目中极其有限。

#### 核心矛盾：90% 汇编 vs 编译器

SPUV3 软件栈 90% 是自定义指令（BNPU/VPU/RSA）汇编固件。LLVM 的核心价值在于 C/C++ 代码优化——但对一组编译器完全无法理解的自定义指令，它退化成一个**指令翻译机器码的工具**，和一个 Python 脚本做的事情完全一样。

#### LLVM 无法理解 SPU 架构语义

| LLVM 擅长的 | SPU 的现实 |
| --- | --- |
| 自动分配 RV64 寄存器，保存/恢复调用现场 | 自定义架构寄存器（b0-b63、v0-v31、c0-c31）没有 ABI 语义，LLVM 完全不知道它们的存在，自动压栈入栈、自动保存恢复全都不可能 |
| 优化访存顺序、向量化 | BNPU/VPU 通过 CSR 操作，LLVM 无法建模流水线延迟和访存约束 |
| 内联、循环展开、死代码删除 | 自定义汇编里的 `bnmv b0, b0` 是寄存器清零惯用法，LLVM 优化可能删掉"看似无用"的指令 |
| 完整工具链：stdlib、stdio、libc | bare-metal 环境下全缺失，需要手写 `stdlib.h`、`string.h`、`stdio.h` stub — 只引不用 |
| C 代码安全 | 裸机 C 直接写 CSR、访问 MMIO、操作绝对地址，类型安全形同虚设 |

#### C 算法在 SPU 上性能差

SPU 是单发射顺序核 @100MHz。纯 C 实现加密算法和手写 BNPU/VPU 汇编的性能差距通常在 10-100x。拿 C 跑 ML-KEM keypair 性能数据没有工程意义——业界都清楚这种场景必须汇编优化。

#### LLVM 带来的实际代价远大于收益

1.  **工具链编译维护负担**：从源码编译 LLVM（x86\_64 + RISCV + xpqc），产出 1GB+ build 目录；跨平台（CentOS 7 / Windows / WSL）要分别容器化编译，需要处理 yum 源、glibc 版本、MinGW DLL 等问题，时间成本远超实际用途
    
2.  **除 Python 汇编器外增加额外路径**：原来只需 `dcf_spu_as_cmd.py` 一个脚本就能把 `.s` 翻译成 hex；现在增加了 LLVM 预处理、编译、链接三条额外路径，debug 时不清楚是哪一层的错误
    
3.  **版本锁定风险**：LLVM 19 和 xpqc 扩展是定制版本，上游 LLVM 不包含 xpqc 指令；每次 cherry-pick 上游变更都要手动解决冲突
    
4.  **不支持指令优化**：标准 RV64IMFD 指令能被 LLVM 优化，但 BNPU/VPU 指令对编译器完全不透明——循环内的 `bnmv` 不会被内联展开，`vxorv3vx` 的数据依赖延迟不会被调度器重排
    

#### 什么场景 LLVM 有意义

*   需要编译大量 C/C++ 算法（非加密核心，而是控制/调度/测试逻辑）
    
*   需要用 C 的 `dcf_printf` 打印调试信息（LLVM 集成的主要动机之一）
    
*   需要统一 ELF 结构来做回归测试 golden 比对
    

在这些场景下，LLVM 是辅助工具，不是核心编译引擎。固件本身的构建（`.s` → 机器码）不依赖 LLVM。

#### 总结

> SPU 的软件栈本质是**自定义架构寄存器的汇编手工优化**。LLVM 缺乏对 BNPU/VPU 架构寄存器的语义理解，无法自动保存恢复、无法建模流水线、无法优化访存。LLVM 在这里只是一个"指令翻译机器码"的过程，Python 汇编器一个脚本就干完了，不存在 LLVM 工具链交叉编译、跨平台兼容等额外问题。用 LLVM 的唯一理由是**把少量 C 代码和固件链接成单个 ELF**，方便测试和回归。但这不是必须的——hex 拼接同样能达到目的。

---

## 13. 仿真环境

### 目录结构

```plaintext
sim/               仿真脚本、Makefile、波形输出
tb/                Testbench（各算法顶层仿真台）
firmware/          汇编固件源码（.s → .hex）
firmware_dcf05/    DCF05 版本固件
ctests/            C 语言单元测试
riscv-tests/       RISC-V 标准指令集测试套件（用于验证 RV64IMFD）

```

### 仿真指令（VCS，在 `sim/` 目录下运行）

```bash
cd sim

# 汇编 + 编译 RTL + 运行仿真
make sim APP=<testname>           # 例：APP=sm4_enc_ecb

# 仅汇编固件
make firmware APP=<testname>

# 仅编译 RTL（固件已就绪时）
make comp APP=<testname>

# 运行已汇编固件（不重新编译）
./simv

# 随机回归测试
make rand_count COUNT=10 APP=spuv3_final_firmware_dev

# 运行 regress.py 中全部用例
make regress

# RV64IMFD ISA 合规性测试
make install && make regress_isa

# 查看波形（Verdi）
make wave

# 运行 C 程序测试
make ctest APP=test

# 固件加密（ILM 32-bit LFSR，DLM 256-bit LFSR）
make firmware_enc APP=<testname>

# 清理
make clean

```

**C 程序编译（RV64IMFD 裸机）**：

```bash
cd ctests
make all dump app=<appname>       # 生成 .elf、.hex、反汇编
# 回到 sim/：
python3 ../scripts/hex32to64.py ../ctests/ilm.hex ../ctests/ilm.hex
make comp APP=<ctestname>         # 以 RV_TEST 宏运行

```

### 关键仿真控制宏

```verilog
`define TRACE           // 开启详细调试打印（内存映射、断言、FSDB 波形）
`define VREG_TRACE_HEX  // 向量寄存器以 Hex 格式打印
`define RV_TEST         // 运行 RISC-V 标准测试模式（关闭部分 SPU 特有断言）
// 可选：
// `define VREG_TRACE_GROUP_32   // 按 32-bit 分组打印
// `define VREG_TRACE_GROUP_16   // 按 16-bit 分组打印
// `define VREG_TRACE_SIGNED     // 有符号格式打印

```

### 性能参考数据

| 算法 | 时钟周期 | 说明 |
| --- | --- | --- |
| SM4 ECB 一次分组加密 | ~5620 cycles | BNPU 执行模式 |
| CoreMark | 3 CoreMark/MHz | RV64IMFD 标准核 |

---

## 14. 综合报告

以下数据来自项目根目录综合报告文件。

### 55nm 工艺（目标 100 MHz）

| 指标 | 数值 | 报告文件 |
| --- | --- | --- |
| 总面积 | **1.4399 mm²** | `SPUV3MH_55nm面积报告整理_1.4399mm2.pdf` |
| 主要配置 | RV64IMFD + BNPU + VPU + FPU + RSA | — |

### 28nm 工艺（目标 600 MHz）

| 指标 | 数值 | 备注 |
| --- | --- | --- |
| 总面积 | **0.6721 mm²**（1,333.6 kGates） | 2026-05-21 综合，含非对齐访存 + VPU coeffi 共享 buffer |
| 总面积（优化前） | 0.8074 mm²（1,601.9 kGates） | 2026-05-09 综合，VPU coeffi 独立寄存器 |
| 单 NAND2 面积 | 0.504 μm² | SMIC HPC ssg0p81vm40c |
| 详细分层报告 | `doc/syn_rpt/SPUV3_AREA_20260521_28NM_SSG0P81VM40C.html` | — |
| 差异分析 | `doc/syn_rpt/SPUV3_AREA_DIFF_20260519_to_20260521.html` | — |

详细分层面积、时序路径、功耗报告见根目录 `spuv3_rsa_single_dpram_pqc_*.txt`、`report_area_*.txt` 系列文件，以及 `SPUV3_RSA_PQC_*.html` / `*.pdf`。

---

## 15. 主要宏定义与可配置参数

### `spuv3_defines.vh` 全局宏

| 宏 | 默认值 | 说明 |
| --- | --- | --- |
| `SPUV3_ILM_SIZE_KB` | `128` | ILM 大小（KB） |
| `SPUV3_DLM_SIZE_KB` | `64` | DLM 大小（KB） |
| `SPUV3_RSA_RAM_SIZE_KB` | `16` | RSA 工作 RAM（从 DPRAM 划分，KB） |
| `SPUV3_DPRAM_SIZE_KB` | `32` | DPRAM 总大小（KB） |
| `SPUV3_MAIN_MEM_SIZE_KB` | `256` | AHB 主内存桥地址空间（KB，需 ≥ ILM+DLM+SFR） |
| `SPUV3_VREGFILE_REMAP2BNREG` | 已定义 | 开启 v9~v31 → BNPR remap（节省面积） |
| `SPUV3_VREGFILE_320BIT_NUM` | `9` | 物理 vregfile 中实体 320-bit 寄存器数量 |
| `SPUV3_MEM_ENC_ENABLE_OUTER` | 未定义 | 开启外部总线数据加密 |
| `SPUV3_MEM_ENC_ENABLE_INNER` | 已定义 | 内部存储加密（始终开启） |
| `SPUV3_CSR_IMM_RISCV_COMPLIANCE` | 未定义 | CSR 立即数使用标准 zimm 行为 |
| `TRACE` | 未定义 | 开启仿真详细调试输出 |
| `SPU_RESET_ADDR` | `32'h00000000` | CPU 复位后的 PC 初始值 |
| `SPU_GPR_REG_WIDTH` | `32` | GPR 地址宽度（5-bit = 32 个寄存器） |

### Verilog 顶层参数（`spuv3_core`）

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `BranchPredictor` | `1` | 1=开启静态分支预测，0=关闭 |
| `ELEN` | `32` | VPU 元素位宽（bit） |
| `LaneNum` | `10` | VPU 并行 lane 数（总向量宽 = ELEN × LaneNum = 320-bit） |
| `VEC_REG_NUM` | `32` | VPU 逻辑向量寄存器数量（最大 32） |

### `spuv3_bnregfile` 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `ADDR_WIDTH` | `6` | BN 寄存器地址宽度（支持 64 个寄存器） |
| `DATA_WIDTH` | `256` | BN 寄存器数据宽度（256-bit） |
| `NUM_REGISTERS` | `64` | BN 寄存器总数 |

---

## 16. cfgkit 配置工具框架

cfgkit 是 SPUV3 RCE IP 的配置与打包工具套件，管理 SPUV3-M 和 SPUV3-H 两个变体的功能配置，并提供从 RTL 源目录到加密交付包的完整工具链。

### 16.1 目录结构

```plaintext
cfgkit/
├── spuv3.kconfig        Kconfig 菜单定义（算法、内存、VPU 配置项）
├── gen_spuv3_config.py  配置生成器：.config → rtl/spuv3_config.vh
├── pack_spuv3.py        打包工具：RTL 加密打包 / 客户侧解密
├── Makefile.kconfig     可 include 到子目录 Makefile 的配置目标片段
├── rce_v3.ipenc         RSA-OAEP 加密后的 RTL 交付包（对外发布时生成）
├── PrivateKey           RSA-2048 私钥（内部持有，禁止对外发布）
└── requirement.txt      Python 依赖（kconfiglib, pycryptodome, tqdm）

```

相关目录：

```plaintext
configs/
├── spuv3_m.config       SPUV3-M 预设（55nm/100MHz）
└── spuv3_h.config       SPUV3-H 预设（28nm/600MHz）

gen/rtl/                 客户侧 make genrtl* 的解包输出目录
rtl/spuv3_config.vh      自动生成的 Verilog 宏定义头文件

```

### 16.2 双侧工作流

```plaintext
内部开发侧                                  客户侧
─────────────────────────────               ──────────────────────────────
source SourceMe                             source SourceMe
         │                                           │
         ▼                                           ▼
make menuconfig / config_m / config_h       make menuconfig / config_m / config_h
         │                                           │
         ▼                                           ▼
.config + rtl/spuv3_config.vh              .config
         │
         ▼
make pack
         │
         ▼
cfgkit/rce_v3.ipenc ─────────────────────► make genrtl_m / genrtl_h / genrtl
                      交付给客户                      │
                                                      ▼
                                             gen/rtl/（已配置的 RTL）
                                             └── spuv3_config.vh（自动生成）

```

### 16.3 Kconfig 配置项总览

配置菜单由 `cfgkit/spuv3.kconfig` 定义，通过 `make menuconfig` 进行交互式配置：

![spuv3_rce_cfgkit.png](https://alidocs.oss-cn-zhangjiakou.aliyuncs.com/res/Mp7ld7bZooWyMOBQ/img/12a5c75e-6e47-4b8e-bfab-b08e27fcef06.png)

| 配置键 | 描述 | SPUV3-M | SPUV3-H |
| --- | --- | --- | --- |
| `CFG_BNMOD_ARITH` | BNPU 大数模运算加速器 | y | y |
| `CFG_SM1_SUPPORT` | SM1 对称密码加速 | y | y |
| `CFG_SM3_SUPPORT` | SM3 杂凑算法加速 | y | y |
| `CFG_SM4_SUPPORT` | SM4 对称密码加速 | y | y |
| `CFG_SM7_SUPPORT` | SM7 密码加速 | y | y |
| `CFG_SYM_CRYPTO_ACC` | 对称密码加速器（TADD/SBOX 等） | y | y |
| `CFG_RSA_SUPPORT` | RSA 硬件加速器 | y | y |
| `CFG_RSA_M` | RSA-M 配置（55nm 版） | y | — |
| `CFG_RSA_H` | RSA-H 配置（28nm 版） | — | y |
| `CFG_VPU_SUPPORT` | VPU 向量处理单元（PQC） | y | y |
| `CFG_FPU_SUPPORT` | FPU 浮点处理单元 | y | y |
| `CFG_ILM_SIZE_KB` | ILM 大小（KB） | 128 | 256 |
| `CFG_DLM_SIZE_KB` | DLM 大小（KB） | 64 | 128 |
| `CFG_DPRAM_SIZE_KB` | DPRAM 大小（KB） | 32 | 64 |
| `CFG_RSA_RAM_SIZE_KB` | RSA 工作 RAM（KB） | 16 | 32 |
| `CFG_VREGFILE_REMAP` | v9–v31 → BNPR remap（节省面积） | y | — |
| `CFG_VREGFILE_320BIT_NUM` | 物理 320-bit VR 数量 | 9 | 9 |
| `CFG_MEM_ENC_INNER` | 内部存储加密 | y | y |
| `CFG_MEM_ENC_OUTER` | 外部总线加密 | — | — |
| `CFG_CSR_RISCV_COMPLIANCE` | CSR 立即数 RISC-V 兼容模式 | — | — |

各配置项经 `gen_spuv3_config.py` 转换后，映射到 `rtl/spuv3_config.vh` 中的 `SPUV3_*` 宏：

| 配置键 | 生成宏 |
| --- | --- |
| `CFG_RSA_SUPPORT` | ``define SPUV3_RSA_SUPPORT` |
| `CFG_ILM_SIZE_KB` | ``define SPUV3_ILM_SIZE_KB 128` |
| `CFG_VREGFILE_REMAP` | ``define SPUV3_VREGFILE_REMAP2BNREG` |
| _(自动推导)_ | ``define SPUV3_MAIN_MEM_SIZE_KB 256` （next\_pow2(ILM+DLM+8)） |

### 16.4 Makefile 目标

在项目根目录运行 `make help` 查看所有目标。

**配置目标（内部开发侧）**

| 目标 | 说明 |
| --- | --- |
| `make menuconfig` | 打开交互式配置菜单，保存后自动生成 `rtl/spuv3_config.vh` |
| `make config_m` | 应用 SPUV3-M 预设（55nm/100MHz，RSA-M，ILM 128KB） |
| `make config_h` | 应用 SPUV3-H 预设（28nm/600MHz，RSA-H，ILM 256KB） |
| `make genconfig` | 从当前 `.config` 重新生成 `rtl/spuv3_config.vh`（不打开菜单） |

**打包加密（内部 → 对外交付）**

| 目标 | 说明 |
| --- | --- |
| `make build_dist` | 将 `gen_spuv3_config.py` 编译为 Cython 原生二进制 `cfgkit/gen_spuv3_config`（保护源码） |
| `make pack` | 将 `rtl/` 打包并 RSA-OAEP 加密，输出 `cfgkit/rce_v3.ipenc` |

**解密生成（客户侧）**

| 目标 | 说明 |
| --- | --- |
| `make genrtl_m` | 解密 `rce_v3.ipenc` + 应用 SPUV3-M 配置，输出 `gen/rtl/` |
| `make genrtl_h` | 解密 `rce_v3.ipenc` + 应用 SPUV3-H 配置，输出 `gen/rtl/` |
| `make genrtl` | 解密 `rce_v3.ipenc` + 使用当前 `.config`，输出 `gen/rtl/` |

### 16.5 生成文件说明

| 文件 | 生成时机 | 说明 |
| --- | --- | --- |
| `rtl/spuv3_config.vh` | `make config_m / config_h / genconfig / menuconfig` | Verilog 宏定义头，被 `rtl/spuv3_defines.vh` include |
| `.config` | `make config_m / config_h / menuconfig` | 当前激活的 Kconfig 配置快照（标准 `CONFIG_` 前缀格式） |
| `cfgkit/gen_spuv3_config` | `make build_dist` | Cython 原生二进制，对外发布时替代 `.py` 脚本 |
| `cfgkit/rce_v3.ipenc` | `make pack` | RSA-2048 OAEP 加密的 RTL 交付包（200-byte 明文块 / 256-byte 密文块） |
| `gen/rtl/` | `make genrtl*` | 客户侧解包后的 RTL 输出目录（含自动生成的 `spuv3_config.vh`） |

### 16.6 快速上手

**内部开发侧**

```bash
# 初始化环境（将 cfgkit/ 加入 PYTHONPATH）
source SourceMe

# 切换到 SPUV3-M 配置并生成 rtl/spuv3_config.vh
make config_m

# 交互式调整配置
make menuconfig

# 检查生成的 Verilog 头文件
cat rtl/spuv3_config.vh

# 编译 gen_spuv3_config.py → 原生二进制（Cython，对外发布前执行）
make build_dist   # → cfgkit/gen_spuv3_config

# 打包加密，准备对外交付
make pack         # → cfgkit/rce_v3.ipenc

```

**客户侧**

```bash
source SourceMe

# 一键：解密 rce_v3.ipenc + 应用 M 配置 → gen/rtl/
make genrtl_m

# 一键：解密 rce_v3.ipenc + 应用 H 配置 → gen/rtl/
make genrtl_h

# 自定义配置：先 menuconfig，再 genrtl
make menuconfig
make genrtl

```

### 16.7 依赖安装

**内部开发环境**（开发侧所有功能）：

```bash
pip install -r cfgkit/requirement.txt
# 包含：cython kconfiglib pycryptodome tqdm

```

**客户侧环境**（仅需配置与解包）：

```bash
pip install kconfiglib tqdm pycryptodome

```

### 16.8 源码保护说明

| 工具 | 安全性 | 说明 |
| --- | --- | --- |
| 直接发布 `.py` 源文件 | ❌ | 源码完全暴露 |
| PyInstaller（无加密） | ❌ | pyinstxtractor + uncompyle6 可还原字节码 |
| PyInstaller `--key`（已在 6.0+ 移除） | ⚠️ | Blowfish 加密字节码，密钥嵌入二进制，仍可破解 |
| **Cython** `**--embed**` **+ GCC**（本项目方案） | ✅ | Python 编译为 C 再编译为机器码，无字节码，逆向难度等同于 C 程序 |

Cython 编译后二进制的安全特性：

*   不含任何 Python 字节码（`.pyc`）
    
*   宏映射表（`BOOL_ITEMS` / `INT_ITEMS`）编译为 C 字符串常量，分散在 `.rodata` 段中，无结构化上下文
    
*   经 `strip` 去除符号表，进一步提高静态分析难度
    
*   运行时需要目标机器安装 Python 3.x（链接 `libpython`），但源码不可恢复
    

> **交付清单**（对外发布时**不含** `.py` 源文件）：**严禁发布**：`cfgkit/PrivateKey`（RSA-2048 私钥）、`cfgkit/gen_spuv3_config.py`（Python 源码）

---

_文档版本：1.6_

_发布日期：2026-05-27_

_作者：Jeremy / Shandong Exponent Semiconductor_
