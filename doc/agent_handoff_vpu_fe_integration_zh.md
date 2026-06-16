# SPUV3 VPU FE 集成工作交接文档

本文面向后续接手本仓库的 agent 或工程师，说明当前 SPUV3 RCE / Falcon f64 FE 扩展已经完成的工作、当前设计决策、代码入口、验证状态和后续接入真实 SPUV3 RTL 时需要修改的位置。

## 1. 当前目标

本项目目标是在现有 SPUV3 RCE 上加入 Falcon 所需的 f64 复数 FE 能力，使 SPUV3 不只覆盖 Kyber/Dilithium 这类整数 NTT 主导算法，也能覆盖 Falcon FFT/IFFT 路径。

当前设计定位：

- SPUV3 RCE 已经是 tightly-coupled crypto coprocessor，不是普通外设 IP。
- FE array 不替代 `spuv3_fpu_wrap`。标准 RV64F/D 浮点指令仍由标量 FPU 执行。
- FE array 是 VPU/PQC 路径上的 Falcon f64 complex/FFT 执行扩展。
- 第一版接入选择低面积、低侵入方案：FE 作为 VPU 多周期子执行单元，不通过 CSR 搬运 320-bit 数据，也不在第一版引入完整 local FFT buffer。

## 2. 第一版设计决策

### 2.1 接入路径

第一版 FE 接入路径如下：

```text
XPqc/VPU 汇编指令
  -> vpu_decode
  -> dec_info_bus / vpu_info
  -> vpu_op_dispatch
  -> vpu_exu
  -> vpu_fe_exu_adapter
  -> vpu_fe_unit
  -> reconfig_fe_f64_shared_array
```

这个方案复用现有 VPU 320-bit operand/result 数据通路、VPU register file、`busy/done/stall` 互锁和 ordered commit 模型。

### 2.2 新增 VPU FE 指令

第一版建议新增四条 VPU FE 指令：

| 指令 | 作用 | 是否写 VR |
| --- | --- | --- |
| `VFFELOADWIM` / `vffeloadwim` | 预加载 twiddle 虚部 `w_im` | 否 |
| `VFFESTART` / `vffestart` | 启动一次 FE butterfly 或 complex op | 否 |
| `VFFEREAD` / `vfferead` | 从 FE wrapper 读取一组 320-bit 结果 | 是 |
| `VFFECLEAR` / `vffeclear` | 清空 FE wrapper 内部状态 | 否 |

推荐汇编流程：

```text
vffeloadwim  v_tw_im
vffestart    v_a_re, v_a_im, v_b_re, v_b_im, v_tw_re
vfferead     v_y0_re, 0
vfferead     v_y0_im, 1
vfferead     v_y1_re, 2
vfferead     v_y1_im, 3
vffeclear
```

`vfferead` 的 `read_sel`：

```text
0 -> y0_re
1 -> y0_im
2 -> y1_re
3 -> y1_im
```

### 2.3 数据映射

当前 VPU EXU 可直接提供 5 个 320-bit operand，第一版映射为：

```text
operand_a_i -> a_re
operand_b_i -> a_im
operand_c_i -> b_re
operand_d_i -> b_im
operand_e_i -> w_re
```

`w_im` 是第六组 320-bit 数据，因此通过 `VFFELOADWIM` 先加载到 `vpu_fe_unit` 内部保持寄存器：

```text
VFFELOADWIM: operand_e_i -> w_im_hold
VFFESTART  : operand_e_i -> w_re, w_im_hold -> w_im
```

FE 计算完成后在 wrapper 内保持四组结果：

```text
y0_re
y0_im
y1_re
y1_im
```

之后通过 `VFFEREAD` 分四次写回 VR。

### 2.4 `vmask` 与 f64 lane

SPUV3 VPU 参数：

```text
ELEN    = 32
LaneNum = 10
VR宽度  = 320-bit
```

一个 f64 占两个 32-bit lane，因此一个 VR 最多容纳 5 个 f64 lane：

```text
f64 lane 0 -> bits [63:0]
f64 lane 1 -> bits [127:64]
f64 lane 2 -> bits [191:128]
f64 lane 3 -> bits [255:192]
f64 lane 4 -> bits [319:256]
```

重要约束：

- `vmask=10` 表示 5 个 f64 lane 全开。
- `vmask=8` 只表示 4 个 f64 lane，适合 256-bit remap/BNPR 场景。
- FE wrapper 必须保证 inactive f64 lane 不保留旧值污染写回。

## 3. 当前已新增 RTL

### 3.1 `rtl/vpu_fe_unit.v`

用途：

- 持有 `reconfig_fe_f64_shared_array` 实例。
- 保存 `w_im_hold`。
- 保存四组 320-bit 结果：`y0_re_hold`、`y0_im_hold`、`y1_re_hold`、`y1_im_hold`。
- 根据 `CMD_READ` 和 `cmd_read_sel_i` 返回选中的 320-bit 结果。
- 按 `vmask` 屏蔽 inactive f64 lane，避免旧值污染。

命令编码：

```verilog
CMD_START    = 2'd0
CMD_LOAD_WIM = 2'd1
CMD_READ     = 2'd2
CMD_CLEAR    = 2'd3
```

关键语义：

- `CMD_LOAD_WIM` 只加载 `w_im`，不启动 FE。
- `CMD_START` 启动 FE。
- `CMD_READ` 返回一组 held result。
- `CMD_CLEAR` 清空内部 held state。

### 3.2 `rtl/vpu_fe_exu_adapter.v`

用途：

- 设计为放入真实 `vpu_exu`。
- 把 `operator_i == VFFE*` 的命中信号转换成 `vpu_fe_unit` command。
- 对外提供：
  - `fe_done_o`
  - `fe_stall_o`
  - `fe_result_o`
  - `fe_vreg_we_o`
  - `fe_flags_o`
  - `fe_busy_o`
  - `fe_result_valid_o`

关键语义：

- `VFFELOADWIM` 和 `VFFECLEAR` 是控制命令，可快速 done，不写 VR。
- `VFFESTART` 是多周期命令，stall 到 FE result valid，不写 VR。
- `VFFEREAD` 读取 held result，`fe_vreg_we_o` 只在 read 返回时拉高。
- adapter 内部用 inflight 状态处理 `valid_i` 只保持到 `done` 的流水线场景。

### 3.3 `rtl/filelist.f`

已经加入：

```text
rtl/vpu_fe_unit.v
rtl/vpu_fe_exu_adapter.v
```

## 4. 当前已新增 testbench

### 4.1 `tb/tb_vpu_fe_unit.v`

覆盖内容：

- `LOAD_WIM`
- `START`
- repeated `START` blocked
- 四路 `READ`
- `CLEAR`
- `vmask=8` inactive lane 清零

通过输出：

```text
TB_PASS vpu fe unit cases
```

### 4.2 `tb/tb_vpu_fe_exu_adapter.v`

覆盖内容：

- `LOAD_WIM` / `CLEAR` 一拍 done，不写 VR。
- `START` 多周期 stall/done，不写 VR。
- `READ` 返回结果并拉高 `fe_vreg_we_o`。
- 模拟真实 EXU 中 `valid_i` 持续到 `fe_done_o` 的行为。

通过输出：

```text
TB_PASS vpu fe exu adapter cases
```

### 4.3 已验证命令

```bash
iverilog -g2012 -o sim/tb_vpu_fe_unit.vvp \
  -f rtl/filelist.f tb/tb_vpu_fe_unit.v && \
  vvp sim/tb_vpu_fe_unit.vvp

iverilog -g2012 -o sim/tb_vpu_fe_exu_adapter.vvp \
  -f rtl/filelist.f tb/tb_vpu_fe_exu_adapter.v && \
  vvp sim/tb_vpu_fe_exu_adapter.vvp
```

## 5. 当前已更新文档

新增：

- `doc/vpu_fe_first_integration.md`
- `doc/vpu_fe_first_integration_zh.md`
- `doc/agent_handoff_vpu_fe_integration_zh.md`

已同步更新：

- `doc/architecture_design.md`
- `doc/SPUV3 RCE(Reconfiguable Crypto Engine) Reference Guide V1.md`
- `doc/reconfig_fe_f64_shared_array.md`
- `doc/falcon_fft_verification_flow_zh.md`
- `doc/report_summary.md`

注意：

- `doc/spuv3_fe_array_extension.md`
- `doc/spuv3_fe_array_extension_clean.md`

这两个文件当前读出为 `E-SafeNet/LOCK` 保护内容，不是普通 Markdown。不要直接 patch，除非先获得可编辑明文版本。

## 6. 真实 SPUV3 RTL 需要修改的位置

当前仓库没有真实 SPUV3 的完整 `vpu_pkg.sv`、`vpu_decode.sv`、`vpu_exu.sv`、`spuv3_defines.vh` 源码，只能基于用户粘贴片段给出接入点。后续接入真实工程时，按以下位置修改。

### 6.1 `vpu_pkg.sv`

增加 enum：

```systemverilog
VFFELOADWIM,
VFFESTART,
VFFEREAD,
VFFECLEAR,
```

如果 `vpu_instr_e` 目前是 `[5:0]` 且新增后超过 64 个值，需要扩成 `[6:0]`，并全工程检查硬编码的 operator 宽度。

### 6.2 `spuv3_defines.vh`

增加 VPU decinfo bit。若当前最后一个 VPU index 是 `SPU_DECINFO_GRP_WIDTH+50`，则可顺延：

```verilog
`define SPU_DECINFO_VPU_VFFELOADWIM (`SPU_DECINFO_GRP_WIDTH+51)
`define SPU_DECINFO_VPU_VFFESTART   (`SPU_DECINFO_GRP_WIDTH+52)
`define SPU_DECINFO_VPU_VFFEREAD    (`SPU_DECINFO_GRP_WIDTH+53)
`define SPU_DECINFO_VPU_VFFECLEAR   (`SPU_DECINFO_GRP_WIDTH+54)
`define SPU_DECINFO_VPU_BUS_WIDTH   (`SPU_DECINFO_GRP_WIDTH+55)
```

实际数字必须按真实最后一个 VPU bit 调整。

### 6.3 `vpu_decode.sv`

建议用一个空闲 `funct7`，通过 `funct3` 区分四条 FE 指令。示例：

```text
funct7 = 1001010
opcode = 0000101
funct3 = 000/001/010/011
```

需要增加：

- `MATCH/MASK`
- `dec_instr_vec_vffeloadwim`
- `dec_instr_vec_vffestart`
- `dec_instr_vec_vfferead`
- `dec_instr_vec_vffeclear`
- 合法指令 OR 项
- `vpu_instr_vec` 拼接项，如果真实代码使用
- `vpu_info[...]` 打包项

建议同时清理/检查真实 decode 中的风险：

- 重复 `MATCH/MASK` 名称。
- enum 名和 decode 名拼写不一致。
- `funct3/funct7/opcode` collision。
- `unique case` 末尾是否正确使用 `endcase`。
- `vpu_instr_vec` 宽度与拼接项数量是否一致。

### 6.4 `vpu_op_dispatch`

增加：

```systemverilog
vpu_info[`SPU_DECINFO_VPU_VFFELOADWIM] : vpu_op_dispatch = VFFELOADWIM;
vpu_info[`SPU_DECINFO_VPU_VFFESTART]   : vpu_op_dispatch = VFFESTART;
vpu_info[`SPU_DECINFO_VPU_VFFEREAD]    : vpu_op_dispatch = VFFEREAD;
vpu_info[`SPU_DECINFO_VPU_VFFECLEAR]   : vpu_op_dispatch = VFFECLEAR;
```

### 6.5 `vpu_exu.sv`

实例化 `vpu_fe_exu_adapter`。

需要新增命中信号：

```systemverilog
wire is_vffeloadwim = (operator_i == VFFELOADWIM);
wire is_vffestart   = (operator_i == VFFESTART);
wire is_vfferead    = (operator_i == VFFEREAD);
wire is_vffeclear   = (operator_i == VFFECLEAR);
```

需要接入：

- `done_mcyc`
- `op_mcyc_valid_en`
- `result_mcyc`
- VR write enable

推荐规则：

```systemverilog
assign done_mcyc = existing_done_mcyc | vffe_done;

assign op_mcyc_valid_en = existing_op_mcyc_valid_en
                         | ((operator_i == VFFESTART) & valid_i)
                         | ((operator_i == VFFEREAD)  & valid_i);
```

`result_mcyc` 增加：

```systemverilog
VFFEREAD: result_mcyc = vffe_result;
```

写回规则：

```systemverilog
assign vpu_reg_we_i = existing_vpu_reg_we_i | vffe_vreg_we;
```

`vffe_vreg_we` 只应在 `VFFEREAD` 返回有效结果时拉高。

### 6.6 写回 mux 风险

用户贴出的真实代码里有类似：

```verilog
assign vpu_reg_wdata_o = mem_vpu_rdata_i | vpu_reg_wdata_i;
```

这类 OR 合并数据通路有污染风险，建议改为明确 mux：

```verilog
assign vpu_reg_wdata_o = mem_vpu_rvalid_i ? mem_vpu_rdata_i : vpu_reg_wdata_i;
```

如果 memory load 和 VPU/FE result 可能同周期竞争，还需要定义写回优先级和冲突断言。

## 7. 当前验证覆盖状态

已覆盖：

### 7.1 基础 FE 层

- f64 FE reference 模式。
- f64 pipelined FE 模式。
- shared FE backpressure。
- shared FE `lane_mask` 局部更新。
- inactive lane 清零/屏蔽，避免旧结果污染。

### 7.2 FFT operator 层

- f64 FFT operator CT/GS 基本路径。
- shared 与 pipelined backend 下的 Falcon-512 FFT/IFFT batch 对照。
- shared 与 pipelined backend 下的 Falcon-1024 FFT/IFFT batch 对照。
- `golden_vecs/` batch 文件驱动 RTL batch EXU 的 active-lane 对照。

### 7.3 SPUV3 wrapper / VPU first integration 层

- `spuv3_vpu_fe_f64_wrap` 的 320-bit VR / VMASK 适配。
- `spuv3_vpu_fe_mem_pack` 的 256-bit DLM/DPRAM row 到 320-bit VR pack/unpack。
- `vpu_fe_unit` 的 `VFFELOADWIM / VFFESTART / VFFEREAD / VFFECLEAR` 控制流程。
- `vpu_fe_exu_adapter` 的 stall/done/result/writeback 行为。
- 非 READ 指令不写 VR，只有 `VFFEREAD` 写 VR。
- `vmask=8` partial f64 lane 与 `vmask=10` full 5-lane 行为。

### 7.4 Falcon golden / stage / buffered engine 层

- Falcon FFT/IFFT Python golden stage-vector 预验证。
- `falcon_fft_buffered_engine` 的本地 ping-pong buffer smoke test。
- Falcon-512 FFT/IFFT buffered final-array 对照，shared 与 pipe backend 均通过 `abs <= 1e-11`。
- Falcon-1024 FFT/IFFT buffered final-array 对照，shared 与 pipe backend 均 bit-exact 通过。

## 8. 并入真实 SPUV3 前还需要补的测试

### 8.1 Decode / assembler 层

- 四条 FE 指令 decode collision 测试。
- 汇编器/反汇编器 round-trip 测试。
- mnemonic、`funct7`、`funct3`、`opcode`、`read_sel` 编码一致性测试。
- 非法编码、保留 `funct3`、保留 `read_sel` 的 DUMMY 或异常行为测试。

### 8.2 EXU / commit 层

- FE task 与普通 VPU/BNPU 指令的 ordered commit 互锁。
- `VFFESTART` 多周期执行期间，后续相关指令不能误提交。
- `valid_out && !ready_in` 时 XPqc pipeline 不误提交、不覆盖 FE 结果。
- `VFFEREAD` 写回与 `mem_vpu_rvalid` 写回同周期时的优先级/mux 测试。
- pipeline flush、reset、`stop_on_reset` 场景下 FE busy/result hold 清理测试。

### 8.3 VPU register file / vmask 层

- `vmask=10` 时 5 个 f64 lane 全量写回。
- `vmask=8` 时只写 4 个 f64 lane，第 5 个 f64 lane 不污染。
- VR remap 到 BNPR 模式下，256-bit 数据和 320-bit FE 结果边界测试。
- 连续多次 `VFFESTART/VFFEREAD` 时 result hold 不串扰。

### 8.4 Memory / DLM / DPRAM 层

- 真实 DLM/DPRAM preload/drain 下的带宽、bank conflict 和吞吐测试。
- 256-bit DLM/DPRAM row 与 320-bit VR 间连续 load/store 对齐测试。
- Host 在 `spuv3_busy=1` 时禁止访问 DPRAM B 口的约束回归。
- DPRAM/ILM/DLM 时钟门控条件下 FE 指令序列回归。

### 8.5 FFT 性能优化层

- twiddle cache 地址越界测试。
- twiddle cache bank conflict 测试。
- 特殊 twiddle bypass：`1+0i`、`0+1i`、`-1+0i`、`0-1i`。
- FFT/IFFT permutation helper 与 local buffer ping-pong 切换测试。
- Falcon-512/1024 多 stage 真实指令流 end-to-end 测试。

## 9. 方案取舍

### 9.1 当前推荐方案

当前 first integration 推荐：

```text
LANES=5 / 320-bit VR 对齐
```

原因：

- 控制最简单。
- 不需要 512-bit 拼接。
- 和 VPU writeback 天然对齐。
- 面积更稳。
- 最适合真实 SPUV3 第一版落地。

### 9.2 其他方案

| 配置 | 说明 | 适用阶段 | 优点 | 代价/注意点 |
| --- | --- | --- | --- | --- |
| `LANES=5` | FE array / wrapper 直接匹配单个 320-bit VR，一拍最多处理 `5 x f64` lane | 第一版集成、真实 SPUV3 接入 | 控制最简单；不需要 512-bit 拼接；和 VPU 写回天然对齐；面积较小 | FFT batch 不是 2/4/8 的整齐分组，stage 调度要处理 5-lane batch 和尾 lane |
| `LANES=8 + 两拍 VR 搬运` | 保留 8-lane FE 后端，用两次 320-bit VR 读写拼成 512-bit FE batch | 复用早期 RTL 或性能评估阶段 | 复用已有 8-lane testbench；适合对比 full/shared FE 性能 | 需要拼接/拆分逻辑；多一次 VR 搬运；valid lane 和写回控制更复杂 |
| `FE local buffer` | 在 FE 旁增加 512-bit 或 banked buffer，FFT stage 在本地连续读写 | 性能优化阶段、完整 FFT/IFFT engine | 减少 VR/DLM 访问；适合 twiddle cache、permutation、in-place update | 面积增加；需要地址生成、bank conflict、preload/drain 和更多验证 |

## 10. 后续路线

建议按以下顺序推进：

1. 在真实 SPUV3 工程中加入 `vpu_fe_unit` 和 `vpu_fe_exu_adapter`。
2. 修改 `vpu_pkg.sv`、`spuv3_defines.vh`、`vpu_decode.sv`、`vpu_op_dispatch`。
3. 修改汇编器/反汇编器，支持四条 VPU FE 指令。
4. 修正 VPU 写回 OR 合并为 mux，并定义写回冲突优先级。
5. 增加 decode collision、EXU stall/done、汇编级 smoke test。
6. 将 `reconfig_fe_f64_shared_array` 的物理 lane 从 reference FE 切到 pipelined FE。
7. 增加 twiddle special-case bypass。
8. 增加 task descriptor、twiddle cache、本地 buffer 和 preload/drain。
9. 接入 Falcon FFT/IFFT 多 stage 真实指令流 end-to-end 验证。

## 11. 给后续 agent 的注意事项

- 不要把 FE 当作 `spuv3_fpu_wrap` 的替代品。
- 不要把 320-bit FE 数据通过 CSR 搬运作为第一版方案。
- 不要在第一版强行接入完整 `falcon_fft_buffered_engine`；它是后续性能路径。
- `VFFEREAD` 是唯一写 VR 的 FE 指令。
- `vmask=8` 不是 5 个 f64 lane，而是 4 个 f64 lane。
- shared FE 内部 inactive lane 保留旧值是局部更新语义；VPU wrapper 写回前必须清零或屏蔽 inactive lane。
- 真实 decode 表新增指令前必须做 collision 检查。
- 若 `vpu_instr_e` 超过 64 个枚举值，必须扩宽 enum 和所有相关 operator 宽度。
- `mem_vpu_rdata_i | vpu_reg_wdata_i` 这类 OR 写回合并需要改为 mux。
- `spuv3_fe_array_extension.md` 和 `spuv3_fe_array_extension_clean.md` 当前是受保护内容，不能直接按普通 Markdown 修改。
