# SPUV3 VPU FE 第一版接入说明

本文记录 Falcon f64 FE 阵列接入 SPUV3 VPU/XPqc 路径的第一版方案。目标是先用低面积、低侵入方式打通指令、执行、写回和验证链路，不在第一版引入完整本地 FFT buffer，也不把 320-bit 向量数据通过 CSR 大量搬运。

## 1. 接入原则

第一版 FE 作为 VPU 的多周期子执行单元接入：

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

数据仍走现有 VPU 320-bit operand/result 通路。软件仍按 SPUV3 RCE 的既有模型工作：RV64 核负责循环、地址和配置，DLM/DPRAM 负责数据存取，VR/BNPR 保存中间向量，XPqc/VPU 指令触发计算。

第一版不建议把 FE 输入、输出做成一组 320-bit CSR，原因是：

- CSR 更适合少量控制参数，不适合每条 butterfly 搬运多组 320-bit 数据。
- CSR 搬运会增加指令数、总线扇出和时序压力。
- 现有 VPU operand/result 已经具备 320-bit 数据通路，复用它的代价最低。
- RCE 文档中的编程模型本来就是 XPqc load/compute/store，而不是 CSR 数据面搬运。

## 2. 新增 RTL 模块

当前原型新增两个模块：

- `rtl/vpu_fe_unit.v`
  - 持有共享 FE 实例。
  - 内部保存 `w_im`。
  - 内部保存四组 320-bit 结果：`y0_re`、`y0_im`、`y1_re`、`y1_im`。
  - 每次 `READ` 返回其中一组 320-bit 结果。

- `rtl/vpu_fe_exu_adapter.v`
  - 放在真实 `vpu_exu` 内部。
  - 把已解码的 FE 指令转换成 `vpu_fe_unit` command。
  - 对外暴露 `fe_done_o`、`fe_stall_o`、`fe_result_o`、`fe_vreg_we_o` 等信号。

第一版命令定义如下：

```verilog
localparam [1:0] CMD_START    = 2'd0;
localparam [1:0] CMD_LOAD_WIM = 2'd1;
localparam [1:0] CMD_READ     = 2'd2;
localparam [1:0] CMD_CLEAR    = 2'd3;
```

## 3. 新增 VPU 指令

建议新增 4 条内部 VPU FE 操作：

```systemverilog
// for Falcon f64 FE
VFFELOADWIM,
VFFESTART,
VFFEREAD,
VFFECLEAR,
```

含义如下：

| 指令 | 作用 | 是否写 VR |
| --- | --- | --- |
| `VFFELOADWIM` | 预加载 twiddle 虚部 `w_im` | 否 |
| `VFFESTART` | 启动一次 FE butterfly/complex op | 否 |
| `VFFEREAD` | 读取 FE 内部结果到 VR | 是 |
| `VFFECLEAR` | 清空 FE 内部状态 | 否 |

如果 `vpu_instr_e` 当前是：

```systemverilog
typedef enum logic [5:0] {
```

并且新增后超过 64 个枚举值，则需要扩成：

```systemverilog
typedef enum logic [6:0] {
```

注意这里的 6-bit 或 7-bit 是 VPU 内部 decoded operator 编号，不是指令编码里的 opcode。

## 4. 建议指令编码

建议第一版复用现有 VPU custom opcode，在一个空闲 `funct7` 组下用 `funct3` 区分四条 FE 指令。示例使用：

```text
funct7 = 1001010
opcode = 0000101
```

示例 `MATCH/MASK`：

```systemverilog
localparam [31:0] VFFELOADWIM_MATCH =
    32'b1001010_00000_00000_000_00000_0000101;
localparam [31:0] VFFELOADWIM_MASK  =
    32'b1111111_00000_00000_111_00000_1111111;

localparam [31:0] VFFESTART_MATCH =
    32'b1001010_00000_00000_001_00000_0000101;
localparam [31:0] VFFESTART_MASK  =
    32'b1111111_00000_00000_111_00000_1111111;

localparam [31:0] VFFEREAD_MATCH =
    32'b1001010_00000_00000_010_00000_0000101;
localparam [31:0] VFFEREAD_MASK  =
    32'b1111111_00000_00000_111_00000_1111111;

localparam [31:0] VFFECLEAR_MATCH =
    32'b1001010_00000_00000_011_00000_0000101;
localparam [31:0] VFFECLEAR_MASK  =
    32'b1111111_00000_00000_111_00000_1111111;
```

真正落地前需要先确认该 `funct7/funct3/opcode` 组合没有和现有 VPU 指令冲突。

## 5. `spuv3_defines.vh` 修改

在 VPU decinfo bit 定义后面新增四个 bit。假设当前最后一个 VPU decinfo bit 是 `SPU_DECINFO_GRP_WIDTH+50`，则可以加：

```systemverilog
`define SPU_DECINFO_VPU_VFFELOADWIM (`SPU_DECINFO_GRP_WIDTH+51)
`define SPU_DECINFO_VPU_VFFESTART   (`SPU_DECINFO_GRP_WIDTH+52)
`define SPU_DECINFO_VPU_VFFEREAD    (`SPU_DECINFO_GRP_WIDTH+53)
`define SPU_DECINFO_VPU_VFFECLEAR   (`SPU_DECINFO_GRP_WIDTH+54)
`define SPU_DECINFO_VPU_BUS_WIDTH   (`SPU_DECINFO_GRP_WIDTH+55)
```

如果真实文件里最后一个 VPU bit 不是 `+50`，则按实际最后 index 顺延。

## 6. `vpu_decode.sv` 修改

需要增加 decode wire/output：

```systemverilog
logic dec_instr_vec_vffeloadwim;
logic dec_instr_vec_vffestart;
logic dec_instr_vec_vfferead;
logic dec_instr_vec_vffeclear;
```

并增加匹配逻辑：

```systemverilog
assign dec_instr_vec_vffeloadwim =
    (instr_i & VFFELOADWIM_MASK) == VFFELOADWIM_MATCH;
assign dec_instr_vec_vffestart =
    (instr_i & VFFESTART_MASK) == VFFESTART_MATCH;
assign dec_instr_vec_vfferead =
    (instr_i & VFFEREAD_MASK) == VFFEREAD_MATCH;
assign dec_instr_vec_vffeclear =
    (instr_i & VFFECLEAR_MASK) == VFFECLEAR_MATCH;
```

还需要把它们加入：

- 合法指令 OR 逻辑。
- VPU 指令向量拼接，如果真实文件使用 `vpu_instr_vec`。
- decode 输出端口，如果 `vpu_decode` 把每条指令单独输出。
- `vpu_info[...]` 打包逻辑。

建议同步检查现有 `vpu_decode.sv`：

- 是否有重复的 `MATCH/MASK` 名称。
- 是否有 `funct3` 或 `funct7` 冲突。
- 是否有拼写不一致，例如 enum 名和 decode 名不同。
- `unique case` 对应结尾是否为 `endcase`。
- `vpu_instr_vec` 的宽度和拼接项数量是否一致。

## 7. decinfo 打包修改

在把 decode 结果写入 `vpu_info` 的地方新增：

```systemverilog
vpu_info[`SPU_DECINFO_VPU_VFFELOADWIM] = dec_instr_vec_vffeloadwim;
vpu_info[`SPU_DECINFO_VPU_VFFESTART]   = dec_instr_vec_vffestart;
vpu_info[`SPU_DECINFO_VPU_VFFEREAD]    = dec_instr_vec_vfferead;
vpu_info[`SPU_DECINFO_VPU_VFFECLEAR]   = dec_instr_vec_vffeclear;
```

如果项目中 `dec_info_bus` 是按固定宽度拼接的，也要同步扩宽。

## 8. `vpu_op_dispatch` 修改

在 `vpu_info[...]` 转 `vpu_op_dispatch` 的地方新增：

```systemverilog
// Falcon f64 FE
vpu_info[`SPU_DECINFO_VPU_VFFELOADWIM] : vpu_op_dispatch = VFFELOADWIM;
vpu_info[`SPU_DECINFO_VPU_VFFESTART]   : vpu_op_dispatch = VFFESTART;
vpu_info[`SPU_DECINFO_VPU_VFFEREAD]    : vpu_op_dispatch = VFFEREAD;
vpu_info[`SPU_DECINFO_VPU_VFFECLEAR]   : vpu_op_dispatch = VFFECLEAR;
```

这个 `vpu_op_dispatch` 继续连接到 `vpu_exu.operator_i`。

## 9. `vpu_exu.sv` 接入方式

在 `vpu_exu` 内部生成 FE 指令命中信号：

```systemverilog
wire is_vffeloadwim = (operator_i == VFFELOADWIM);
wire is_vffestart   = (operator_i == VFFESTART);
wire is_vfferead    = (operator_i == VFFEREAD);
wire is_vffeclear   = (operator_i == VFFECLEAR);
```

实例化 adapter：

```systemverilog
wire         vffe_done;
wire         vffe_stall;
wire [319:0] vffe_result;
wire         vffe_vreg_we;
wire [3:0]   vffe_flags;
wire         vffe_busy;
wire         vffe_result_valid;

vpu_fe_exu_adapter u_vpu_fe_exu_adapter (
    .clk              (clk),
    .rst_n            (rst_n),
    .valid_i          (valid_i),
    .is_vffeloadwim_i (is_vffeloadwim),
    .is_vffestart_i   (is_vffestart),
    .is_vfferead_i    (is_vfferead),
    .is_vffeclear_i   (is_vffeclear),
    .fe_mode_i        (imm12_i[5:2]),
    .fe_read_sel_i    (imm12_i[1:0]),
    .cfg_vmask_i      (cfg_vmask_i),
    .operand_a_i      (operand_a_i),
    .operand_b_i      (operand_b_i),
    .operand_c_i      (operand_c_i),
    .operand_d_i      (operand_d_i),
    .operand_e_i      (operand_e_i),
    .fe_done_o        (vffe_done),
    .fe_stall_o       (vffe_stall),
    .fe_result_o      (vffe_result),
    .fe_vreg_we_o     (vffe_vreg_we),
    .fe_flags_o       (vffe_flags),
    .fe_busy_o         (vffe_busy),
    .fe_result_valid_o(vffe_result_valid)
);
```

把 FE 接入多周期 done：

```systemverilog
assign done_mcyc = existing_done_mcyc | vffe_done;
```

把 `VFFESTART` 和 `VFFEREAD` 加入多周期 valid enable：

```systemverilog
assign op_mcyc_valid_en = existing_op_mcyc_valid_en
                         | ((operator_i == VFFESTART) & valid_i)
                         | ((operator_i == VFFEREAD)  & valid_i);
```

在 `result_mcyc` 里加入：

```systemverilog
VFFEREAD: begin
    result_mcyc = vffe_result;
end
```

写回规则：

```systemverilog
assign vpu_reg_we_i = existing_vpu_reg_we_i | vffe_vreg_we;
```

其中 `vffe_vreg_we` 只会在 `VFFEREAD` 返回有效结果时拉高。`VFFELOADWIM`、`VFFESTART`、`VFFECLEAR` 都不能写 VR。

## 10. 数据映射

第一版 FE 输入映射：

```text
operand_a_i -> a_re
operand_b_i -> a_im
operand_c_i -> b_re
operand_d_i -> b_im
operand_e_i -> w_re
```

由于当前 VPU EXU 只有 5 个 320-bit operand 输入，没有第 6 个 320-bit operand 给 `w_im`，因此 `w_im` 使用单独指令提前加载：

```text
VFFELOADWIM: operand_e_i -> w_im_hold
```

FE 内部保存四组结果：

```text
y0_re
y0_im
y1_re
y1_im
```

`VFFEREAD` 通过 `read_sel` 选择一组结果写回 VR：

```text
read_sel = 0 -> y0_re
read_sel = 1 -> y0_im
read_sel = 2 -> y1_re
read_sel = 3 -> y1_im
```

## 11. `vmask` 语义

SPUV3 VPU 参数为：

```text
ELEN    = 32
LaneNum = 10
VR宽度  = 320-bit
```

一个 f64 占两个 32-bit lane，因此：

```text
vmask = 10 -> 5 个 f64 lane
vmask = 8  -> 4 个 f64 lane，也就是 256-bit 模式
```

FE 满 5-lane f64 并行时应使用 `vmask=10`。如果使用 `vmask=8`，第五个 f64 lane 必须被 mask 掉，结果不能保留旧值。

## 12. 汇编使用流程

建议第一版使用如下指令序列：

```text
vffeloadwim  v_tw_im
vffestart    v_a_re, v_a_im, v_b_re, v_b_im, v_tw_re
vfferead     v_y0_re, 0
vfferead     v_y0_im, 1
vfferead     v_y1_re, 2
vfferead     v_y1_im, 3
vffeclear
```

其中：

- `vffeloadwim` 是控制指令，不写目标 VR。
- `vffestart` 是计算启动指令，不写目标 VR。
- `vfferead` 是结果读取指令，会写目标 VR。
- `vffeclear` 是状态清理指令，不写目标 VR。

## 13. 建议同步修正的写回问题

如果真实代码里存在类似逻辑：

```verilog
assign vpu_reg_wdata_o = mem_vpu_rdata_i | vpu_reg_wdata_i;
```

建议改成 mux：

```verilog
assign vpu_reg_wdata_o = mem_vpu_rvalid_i ? mem_vpu_rdata_i : vpu_reg_wdata_i;
```

数据通路不建议用 OR 合并。只要 memory load 数据和 VPU 结果同时存在非零位，就可能污染写回值。FE 接入后写回路径更多，这个问题更容易暴露。

## 14. 验证计划

第一版建议按以下顺序验证：

```text
1. VPU decode collision test
2. VFFELOADWIM 单指令测试
3. VFFESTART busy/stall/done 测试
4. VFFEREAD 四路结果读回测试
5. VFFECLEAR 状态清空测试
6. 非 READ 指令不写 VR 测试
7. vmask=8 partial lane 测试
8. vmask=10 full 5-lane f64 测试
9. 汇编级 smoke test
10. Falcon FFT stage-vector 对照
11. Falcon FFT/IFFT final-array 对照
```

当前仓库中的 adapter 层已覆盖：

```text
LOAD_WIM
START
READ
CLEAR
非 READ 不写 VR
READ 才写 VR
vmask partial lane
```

## 15. 其他文档需要同步修改的地方

### 15.1 `doc/architecture_design.md`

建议修改或补充以下内容：

1. 在“FE 扩展建议沿用 SPUV3 XPqc 思路”附近补一节“第一版 VPU FE 指令接入”。
   - 明确第一版不是完整 task engine，也不是 FE local buffer 版本。
   - 明确第一版使用 `VFFELOADWIM`、`VFFESTART`、`VFFEREAD`、`VFFECLEAR` 四条指令。
   - 明确 `VFFEREAD` 是唯一写 VR 的 FE 指令。

2. 在“VR 对齐 / 两拍搬运 / 本地 FE buffer”表格后增加当前选择。
   - 当前第一版选择应描述为“VR 对齐 + 内部结果保持 + 分次 readback”。
   - 需要说明 `LANES=5` 对齐 320-bit VR，或在当前 shared FE wrapper 中只启用有效 f64 lanes。

3. 在 `vmask` 或 lane mask 相关描述中补充：
   - `vmask=10` 表示 5 个 f64 lane。
   - `vmask=8` 只表示 4 个 f64 lane，适合 256-bit remap/BNPR 模式。

4. 在后续优化方向中区分第一版和第二版：
   - 第一版：指令接入 + FE adapter + VR readback。
   - 第二版：task descriptor、twiddle cache、本地 buffer、streaming preload/drain。

### 15.2 `doc/SPUV3 RCE(Reconfiguable Crypto Engine) Reference Guide V1.md`

这份是 SPUV3 RCE 参考手册，建议以“扩展章节”方式补充，不要直接重写原有架构描述。

建议新增或修改：

1. 在 VPU/XPqc 指令章节增加 Falcon FE 扩展小节。
   - 列出四条新增指令的 mnemonic、作用、源操作数、目的寄存器、是否写回。
   - 说明 `VFFEREAD` 的 `read_sel` 编码。

2. 在 VPU register file 章节补充 f64 lane 映射。
   - 320-bit VR = 10 个 32-bit lane = 5 个 f64 lane。
   - f64 lane `i` 对应 32-bit lane `{2*i, 2*i+1}`。
   - `vmask=10` 与 `vmask=8` 的区别。

3. 在 CSR/SFR 配置章节补充 FE 配置边界。
   - `vmask` 仍复用现有 VPU 配置。
   - 第一版不新增 320-bit FE 数据 CSR。
   - 可预留 FE status/flags CSR，但第一版可以仅作为 debug/status，不作为数据搬运路径。

4. 在 programming model 章节增加 Falcon FFT butterfly 示例。
   - 展示 `vffeloadwim -> vffestart -> vfferead x4 -> vffeclear`。
   - 说明 ordered commit 下 `VFFESTART/VFFEREAD` 作为多周期 VPU 指令处理。

5. 在 memory/DLM/DPRAM 章节补充数据布局建议。
   - Falcon 复数数组建议按 real/imag 分离或按 stage 访问模式组织。
   - 第一版通过 VR 搬运，暂不要求 FE 本地 buffer。
   - 第二版再引入 preload/drain 和 bank conflict 统计。

### 15.3 `doc/spuv3_fe_array_extension.md`

这份文档已经偏 FE 扩展设计，建议补充当前第一版集成边界：

- 增加“低面积 first integration”小节。
- 把原先偏完整 FE array / task engine 的描述标成后续版本。
- 加入 `vpu_fe_unit`、`vpu_fe_exu_adapter` 两个模块的位置和接口职责。
- 明确当前不使用大 local buffer。

### 15.4 `doc/reconfig_fe_f64_shared_array.md`

建议补充：

- SPUV3 320-bit wrapper 使用方式。
- lane mask 与 `vmask` 的换算。
- `w_im` 为什么需要单独 preload。
- inactive lane 必须清零，避免旧结果污染。

### 15.5 `doc/falcon_fft_verification_flow_zh.md`

建议补充新验证层级：

```text
SPUV3 VPU FE first integration 层:
  vpu_fe_unit
  vpu_fe_exu_adapter
  VFFELOADWIM / VFFESTART / VFFEREAD / VFFECLEAR
```

并把当前新增测试加入已验证命令列表：

```text
tb_vpu_fe_unit
tb_vpu_fe_exu_adapter
```

### 15.6 `doc/report_summary.md`

建议在总结里增加一句当前决策：

```text
第一版 SPUV3 接入采用 VPU 多周期子执行单元方案，不采用 CSR 数据面搬运，也不在第一版引入完整本地 FFT buffer。
```

这样报告里能清楚解释为什么当前方案面积更稳、接入风险更低。

## 16. 后续版本边界

第一版完成后，再考虑以下优化：

1. 把 shared FE lane 从 reference FE 切到 pipelined FE。
2. 增加 twiddle special-case bypass。
3. 增加正式 task descriptor。
4. 增加 FE local buffer 或 twiddle cache。
5. 接入真实 DLM/DPRAM preload/drain。
6. 增加 bank conflict、吞吐和 stall 统计。
7. 将 Falcon FFT/IFFT stage/batch 调度并入 SPUV3 VPU/XPqc scheduler。

第一版的价值是先把硬件接口、指令语义、写回边界和验证链路固定下来。只要这条链路稳定，后续加 buffer/cache/task engine 都是在同一个软件可见模型下增强性能。
