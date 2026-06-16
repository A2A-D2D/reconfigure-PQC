# reconfig_fe_f64_shared_array 设计文档

## 1. 概述

`reconfig_fe_f64_shared_array` 是 Falcon PQC 算法中 FFT 蝶形运算的面积优化向量引擎。与 `reconfig_fe_f64_array`（8 路并行 FE）不同，本模块仅例化 **1 个** `reconfig_fe_f64` 物理通道，通过时间分复用的方式轮流服务最多 8 个逻辑 lane，将 FP64 运算单元数量降低 **87.5%**，同时保持与并行版本完全兼容的外部接口。

### 关键特性

| 特性 | 描述 |
|---|---|
| 时间分复用 | 1 个物理 FE lane 服务 8 个逻辑 lane |
| 面积优化 | FP64 运算单元从 ~272 个降至 ~34 个（-87.5%） |
| Lane 掩码 | `lane_mask` 按位使能，支持稀疏/部分 lane 处理 |
| 反压握手 | `valid_out` / `ready_in` 标准流控，零额外缓冲 |
| 流水线参数化 | `FE_LATENCY` 支持未来流水线化 FE，状态机自适应 |
| 零空闲周转 | 连续交易之间无死周期 |

---

## 2. 接口描述

### 2.1 参数

| 参数 | 默认值 | 描述 |
|---|---|---|
| `LANES` | 8 | 逻辑 lane 数量 |
| `MODE_W` | 4 | 模式信号位宽 |
| `IDX_W` | 4 | Lane 索引位宽，需满足 2^IDX_W ≥ LANES |
| `FE_LATENCY` | 1 | FE 模块的流水线延迟（cycle） |

### 2.2 端口

| 端口 | 方向 | 位宽 | 描述 |
|---|---|---|---|
| `clk` | I | 1 | 时钟 |
| `rst_n` | I | 1 | 异步复位（低有效） |
| `valid_in` | I | 1 | 输入数据有效，脉冲 1 拍 |
| `ready_in` | I | 1 | 下游就绪，高表示可接收输出 |
| `lane_mask` | I | LANES | Lane 使能掩码，bit[i]=1 则处理 lane i |
| `mode` | I | MODE_W | 运算模式（CT/GS/ADD/SUB/MUL/...） |
| `a_re_vec` | I | LANES×64 | Lane 向量 — A 实部 |
| `a_im_vec` | I | LANES×64 | Lane 向量 — A 虚部 |
| `b_re_vec` | I | LANES×64 | Lane 向量 — B 实部 |
| `b_im_vec` | I | LANES×64 | Lane 向量 — B 虚部 |
| `c_re_vec` | I | LANES×64 | Lane 向量 — C 实部 |
| `c_im_vec` | I | LANES×64 | Lane 向量 — C 虚部 |
| `w_re_vec` | I | LANES×64 | Lane 向量 — W 实部 |
| `w_im_vec` | I | LANES×64 | Lane 向量 — W 虚部 |
| `busy` | O | 1 | 模块忙，不接受新输入 |
| `valid_out` | O | 1 | 输出数据有效 |
| `y0_re_vec` | O | LANES×64 | 结果向量 — Y0 实部 |
| `y0_im_vec` | O | LANES×64 | 结果向量 — Y0 虚部 |
| `y1_re_vec` | O | LANES×64 | 结果向量 — Y1 实部 |
| `y1_im_vec` | O | LANES×64 | 结果向量 — Y1 虚部 |
| `status_*` | O | 1 | FP64 异常标志（invalid/overflow/underflow/inexact） |

---

## 3. 架构

### 3.1 顶层结构

```
                    ┌─────────────────────────────────────────┐
valid_in ──────────▶│                                         │──▶ busy
ready_in ──────────▶│         控制 & 握手逻辑                  │──▶ valid_out
lane_mask ─────────▶│                                         │
mode ──────────────▶│  ┌─────────┐  ┌──────────────────────┐  │
                    │  │  Hold   │  │   Tag Pipeline       │  │
a_re_vec[LANES×64]─▶│  │  Regs   │  │  [0:FE_LATENCY-1]    │  │──▶ y0_re_vec
a_im_vec ──────────▶│  │ (8×8×64)│  │  valid + lane_idx    │  │──▶ y0_im_vec
b_re_vec ──────────▶│  │         │  │                      │  │──▶ y1_re_vec
b_im_vec ──────────▶│  │ 一次锁存 │  │  ①路由 ②校验 ③泄洪    │  │──▶ y1_im_vec
c_re_vec ──────────▶│  │ 逐lane  │  └──────────────────────┘  │
c_im_vec ──────────▶│  │ 读出    │                             │──▶ status_*
w_re_vec ──────────▶│  └────┬────┘                             │
w_im_vec ──────────▶│       │                                  │
                    │  ┌────▼─────────────────────────────┐    │
                    │  │     reconfig_fe_f64  (×1 only)   │    │
                    │  │     组合 FP64 运算数据通路         │    │
                    │  └────┬─────────────────────────────┘    │
                    │       │ y0_re/im, y1_re/im (64b each)    │
                    └───────┼──────────────────────────────────┘
                            │
             输出寄存器 y*_vec 同时是：
              - 结果聚合目标（按 lane 索引写入）
              - 反压缓冲器（ready_in=0 时保持数据）
```

### 3.2 状态机

```
                         ┌──────────┐
          reset ────────▶│ ST_IDLE  │◀──────────────┐
                         │ (1'b0)   │               │
                         └────┬─────┘               │
                              │                     │
              valid_in=1 &    │                     │
              |lane_mask=1 &  │                     │
              (!result_       │                     │
              pending|ready)  │                     │
                              ▼                     │
                         ┌──────────┐               │
                         │ ST_RUN   │───────────────┘
                         │ (1'b1)   │  last capture →
                         └──────────┘  result_pending=1
                               │         state=ST_IDLE
                               │
                         next_active_sel == NO_LANE
                         → lane_valid_in 保持 0
                         → tag 流水线自然泄洪
                         → last capture 自动触发终止
```

- **2 状态 FSM**：无 DRAIN 状态，泄洪由 tag 流水线隐式处理
- **计算与握手解耦**：`result_pending` 块独立于 case 语句运行

---

## 4. 核心设计要点

### 4.1 时间分复用

ST_IDLE 时，全部 8×64-bit 输入向量一次性锁存到 Hold 寄存器组。ST_RUN 时逐周期读出单个 lane 的数据送入共享 FE：

```
Cycle 0: 锁存全部 8 路输入，发出 lane[first_active]
Cycle 1: 捕获上一拍结果，发出 lane[next_active(issue_idx)]
...
Cycle K: next_active_sel == NO_LANE → 停止发出，等待流水线泄洪
Cycle K+FE_LATENCY: 捕获最后一个结果 → result_pending=1
```

仅被 `lane_mask` 使能的 lane 参与处理，未使能的 lane 在其输出位置保留旧值。

### 4.2 Tag 流水线

```
lane_valid_in ──▶ tag_valid_pipe[0] ──▶ tag_valid_pipe[1] ──▶ ... ──▶ tag_valid_pipe[FE_LATENCY-1]
lane_issue_idx─▶ tag_pipe[0]       ──▶ tag_pipe[1]       ──▶ ... ──▶ tag_pipe[FE_LATENCY-1]
                                                                             │
                                                              ┌──────────────┘
                                                              ▼
                                           if (lane_valid_out && tag_valid_pipe[end]) begin
                                               y*_vec[tag_pipe[end]*64 +: 64] <= FE输出;
                                               if (tag_pipe[end] == last_active_idx) → 终止
                                           end
```

Tag 流水线同时承担三个职责：

| 职责 | 实现 | 说明 |
|---|---|---|
| **① 结果路由** | `tag_pipe[k]` 存 lane 索引 | 直接将 FE 输出写入正确的 `y*_vec` slice |
| **② 有效鉴别** | `tag_valid_pipe[k]` | 区分真实结果和流水线噪声 |
| **③ 流水线泄洪** | tag 自然移位 + `tag_valid` 衰减 | 无需计数器或 DRAIN 状态 |

**关键时序**：tag 捕获在 case 块之前，读取 `lane_valid_in` / `lane_issue_idx` 的**寄存器旧值**（NBA 语义）。这保证 tag 和 FE 看到的数据严格同步——两者都经历相同的寄存器延迟。

### 4.3 Lane 掩码

`lane_mask` 位宽 `LANES`，bit[i]=1 表示 lane i 参与当前运算。

**两个组合函数**在 always @(*) 中持续计算：

- `next_active_lane(start_idx, mask)`：从 `start_idx` 开始向右搜索第一个使能的 lane，返回 `NO_LANE`（=LANES）表示再无活跃 lane
- `last_active_lane(mask)`：找到最后一个使能的 lane，作为终止条件

ST_IDLE 中 `first_active_sel` 决定第一个发送的 lane；ST_RUN 中 `next_active_sel` 决定后续发送的 lane。未使能的 lane 完全跳过，其对应的输出寄存器保留旧值（不清零）。

接入 SPUV3 VPU 时需要在外层 wrapper 中额外处理 inactive lane。`reconfig_fe_f64_shared_array` 保留旧值是为了支持局部更新语义，但 VPU FE first integration 的读回结果会直接写入 320-bit VR，因此 wrapper 应在捕获结果时按 `vmask` 对 inactive f64 lane 清零，避免旧结果通过 `VFFEREAD` 写回寄存器文件。

SPUV3 VPU 的 VR 宽度为 320-bit，即 10 个 32-bit lane。f64 数据每个 lane 占两个 32-bit lane：

```text
f64 lane 0 -> bits [63:0]
f64 lane 1 -> bits [127:64]
f64 lane 2 -> bits [191:128]
f64 lane 3 -> bits [255:192]
f64 lane 4 -> bits [319:256]
```

因此 `vmask=10` 表示 5 个 f64 lane 全开，`vmask=8` 只表示 4 个 f64 lane。第一版 `vpu_fe_unit` 使用 320-bit 输入输出，并将 `vmask` 转换为 f64 lane mask 后驱动 shared FE。

**稀疏掩码示例**：`lane_mask = 8'b1000_0101`（lane 0, 2, 7 使能）

```
Cycle 0: first_active=0 → 发出 lane 0, issue_idx=1
Cycle 1: next_active(1, mask)=2 → 发出 lane 2, issue_idx=3
Cycle 2: next_active(3, mask)=7 → 发出 lane 7, issue_idx=8
Cycle 3: next_active(8, mask)=NO_LANE → 停止发出
...     tag 流水线泄洪...
Cycle 3+FE_LATENCY: 捕获 lane 7 结果 → 终止
```

仅 3 个 lane 参与运算，输出向量中 lane 0/2/7 更新，其余保持旧值。

**特殊场景**：

| lane_mask | 行为 |
|---|---|
| `8'b0000_0000` | ST_IDLE 拒绝 valid_in（`|lane_mask` 为假），busy 不拉高 |
| `8'b0000_0001` | 仅处理 lane 0，1 次发送 + FE_LATENCY 泄洪 |
| `8'b1111_1111` | 全 lane 处理，等价于无掩码模式 |

### 4.4 反压握手

```
                ┌──────────────────────────────────┐
                │         result_pending            │
                │                                  │
  LAST_LANE ───▶│  result_pending <= 1             │
  捕获          │  valid_out      <= 1             │
                │  busy           <= !ready_in     │
                │  state          <= ST_IDLE       │
                └────────┬─────────────────────────┘
                         │
                ┌────────▼─────────────────────────┐
                │  if (result_pending) begin        │
                │    if (ready_in) → 清理握手状态   │
                │    else         → valid_out/busy  │
                │                     保持置位      │
                │  end                              │
                └──────────────────────────────────┘
```

- `result_pending=1` 时，`valid_out` 持续为高直到 `ready_in=1`
- `busy` 在 `ready_in=0` 期间保持高，阻止上游发送新数据覆盖输出
- 无需额外缓冲——`y*_vec` 输出寄存器本身就是保持寄存器
- ST_IDLE 条件 `!result_pending || ready_in` 支持"同拍收旧发新"

### 4.5 FE_LATENCY 参数化

`FE_LATENCY` 参数控制 tag 流水线深度。当前 `reconfig_fe_f64` 为 1 周期延迟，未来流水线化后只需修改此参数即可：

| FE_LATENCY | Tag 深度 | 总延迟（8 lane 全使能） |
|---|---|---|
| 1 | 1 级 | 11 cycles |
| 2 | 2 级 | 12 cycles |
| 3 | 3 级 | 13 cycles |

状态机无需任何修改——泄洪时间由 tag 流水线自然移位自动匹配。

---

## 5. 时序协议

### 5.1 单次交易

```
         ┌──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐
 clk     │  │  │  │  │  │  │  │  │  │  │  │  │  │
         └──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘
         ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
 valid_in  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
         ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
         ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
 busy      ░░░░███████████████████████████████░░░░░░
         ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
         ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
 valid_out ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░████░░░
         ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
         ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
 ready_in ████████████████████████████████████████████
         ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
         ├─── ST_IDLE ──┼────────── ST_RUN ──────────┼─┤
                       ▲                             ▲
                  valid_in 锁存               LAST_LANE 捕获
                  全部 lane 数据              valid_out 脉冲
```

### 5.2 反压时序

```
         ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
 valid_out ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░████████████████░░░
         ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
         ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
 ready_in ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█████████████
         ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
         ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
 busy      ░░░░░░░░░░░░░░░░░░░░░░░░░░░██████████████████░░░░
         ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
                        ▲                        ▲
                   LAST_LANE 捕获          ready_in 拉高
                   result_pending=1        握手完成
                   valid_out 持续高         busy 释放
                   busy 持续高
```

- `valid_out` 保持高直到 `ready_in` 应答
- `busy` 在反压期间保持高，阻止新交易覆盖输出数据
- `y*_vec` 数据在整个反压期间稳定保持

### 5.3 连续交易（零空闲周转）

```
 ready_in=1 时，上一笔 valid_out 和下一笔 valid_in 可在相邻周期：
 
 Cycle N:   LAST_LANE 捕获 → result_pending=1, valid_out=1, busy=0, state=ST_IDLE
 Cycle N+1: result_pending=1, ready_in=1 → result_pending≤0, valid_out≤0
            同时 valid_in=1（ST_IDLE 条件满足）→ 启动新交易
```

---

## 6. 面积与性能

### 6.1 面积对比

| 资源 | `reconfig_fe_f64_array` (×8) | `reconfig_fe_f64_shared_array` (×1) | 节省 |
|---|---|---|---|
| `falcon_f64_add` | 176 | 22 | **87.5%** |
| `falcon_f64_mul` | 96 | 12 | **87.5%** |
| Hold 寄存器 | 0 | 4096 FF | — |
| 控制逻辑 | 0 | ~300 FF + ~200 LUT | — |
| **总 FP64 单元** | **272** | **34** | **87.5%** |

### 6.2 延迟

全 lane 使能（`lane_mask = 8'b1111_1111`），FE_LATENCY=1：

| 阶段 | 周期数 |
|---|---|
| ST_IDLE 锁存 + 发出 lane 0 | 1 |
| 剩余 7 个 lane 发出 | 7 |
| 流水线泄洪（最后一个结果） | FE_LATENCY = 1 |
| **总计（valid_in → valid_out）** | **9 cycles** |

通用公式：`Total = 1 + (active_lane_count - 1) + FE_LATENCY`

### 6.3 吞吐

- 单 lane 吞吐：1 结果/周期（FE 持续满载）
- 向量吞吐：`LANES / (LANES + FE_LATENCY)` 向量/周期（全使能时约 0.89）
- 连续交易：零空闲周转（ready_in=1 时）

---

## 7. 使用示例

### 7.1 全 lane CT Butterfly

```verilog
// 8 路 CT Butterfly，下游始终就绪
assign ready_in = 1'b1;
assign lane_mask = 8'b1111_1111;
assign mode = 4'd0;  // CT_BFU

// 填充各 lane 的 a/b/w 数据
// ...

// 发起交易
valid_in = 1'b1;
@(posedge clk);
valid_in = 1'b0;

// 等待完成
while (!valid_out) @(posedge clk);

// 读取结果：y0_re_vec, y0_im_vec, y1_re_vec, y1_im_vec
```

### 7.2 稀疏 lane + 反压

```verilog
// 仅处理 lane 0, 3, 7
assign lane_mask = 8'b1000_1001;
assign ready_in = downstream_ready;  // 下游可能随时 stall

valid_in = 1'b1;
@(posedge clk);
valid_in = 1'b0;

// valid_out 可能持续多拍（如果下游 stall）
while (!valid_out) @(posedge clk);

// 仅 lane 0/3/7 的结果有效，其余 lane 保留旧值
```

### 7.3 参数化配置

```verilog
// 未来流水线化 FE（3 周期延迟）
reconfig_fe_f64_shared_array #(
    .LANES(8),
    .MODE_W(4),
    .IDX_W(4),
    .FE_LATENCY(3)  // 匹配流水线化 FE 的延迟
) u_fe_array (...);
```

### 7.4 SPUV3 VPU FE first integration

第一版 SPUV3 VPU 接入使用两个 wrapper：

| 模块 | 作用 |
| --- | --- |
| `vpu_fe_unit` | 持有 shared FE、`w_im` 保持寄存器和四组结果保持寄存器 |
| `vpu_fe_exu_adapter` | 放在 `vpu_exu` 内，将 VPU FE 指令转换为 FE command/stall/done/writeback |

VPU EXU 当前可直接提供 5 个 320-bit operand，分别映射为：

```text
operand_a_i -> a_re
operand_b_i -> a_im
operand_c_i -> b_re
operand_d_i -> b_im
operand_e_i -> w_re
```

`w_im` 是第六组 320-bit 数据，第一版通过 `VFFELOADWIM` 提前加载到 `vpu_fe_unit` 内部：

```text
VFFELOADWIM: operand_e_i -> w_im_hold
VFFESTART  : 使用 operand_e_i 作为 w_re，并使用 w_im_hold 作为 w_im
```

计算完成后，wrapper 保存：

```text
y0_re
y0_im
y1_re
y1_im
```

软件通过 `VFFEREAD read_sel` 分四次读回结果，只有 `VFFEREAD` 写 VR。`VFFELOADWIM`、`VFFESTART`、`VFFECLEAR` 均为控制类操作，不写 VR。

---

## 8. 限制与注意事项

1. **最大 LANES**：受 `IDX_W` 限制，默认 `IDX_W=4` 支持最多 16 lane。超过需调整参数。
2. **lane_mask=0**：ST_IDLE 拒绝交易（`|lane_mask` 为假），`busy` 不拉高。上游可重试。
3. **输出部分更新**：仅 `lane_mask` 使能的 lane 输出被更新。未使能的 lane 保留上一次交易的值（不清零）。若需全零输出，应在交易前手动清零 `y*_vec` 可改为在 ST_IDLE 清零。
4. **FE_LATENCY 兼容性**：当前 `reconfig_fe_f64` 为 1 周期延迟。若替换为流水线版本，仅需修改参数。
5. **FP64 状态累积**：`status_*` 是所有活跃 lane 的 OR 结果。若任意 lane 产生异常，对应标志置位。

---

## 9. 文件列表

| 文件 | 说明 |
|---|---|
| `rtl/reconfig_fe_f64_shared_array.v` | 本模块 |
| `rtl/reconfig_fe_f64.v` | 单 lane FE（被例化） |
| `rtl/falcon_f64_add.v` | FP64 加法器（依赖） |
| `rtl/falcon_f64_mul.v` | FP64 乘法器（依赖） |
| `tb/tb_reconfig_fe_f64_shared_array.v` | 测试平台 |
