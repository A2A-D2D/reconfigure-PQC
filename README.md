# 可重构

这是一个面向后量子密码计算的可重构运算原型工程。核心目标不是为某一个算法写死专用 datapath，而是把常见运算抽象成可配置、可并行、可复用的计算单元阵列，让不同算法通过 `mode`、参数和调度选择同一组硬件资源。

## 设计理念

后量子密码算法虽然参数和数学结构不同，但底层会反复出现几类高频运算：

- 模加、模减、模乘、butterfly。
- 多精度整数乘法和乘加。
- 复数加减、复数乘、FFT butterfly。
- 不同 lane 数量下的向量化 coefficient 处理。

因此本工程把运算层拆成两类单元：

- AE: Arithmetic Element，处理整数域和模域中的系数级运算。
- FE: Floating/Field Element，处理复数域、FFT 风格和固定点/浮点风格运算。

AE 和 FE 都使用简单的 valid 流水接口，并提供 array wrapper。上层调度器可以把一组 coefficient 或 complex value 分发到多个 lane 中并行执行，从而形成可重构的 arithmetic cluster。

## AE 是什么

AE 是整数/模运算单元，适合处理 prime field、binary/integer datapath 和 NTT 类运算中的系数级操作。

当前 `reconfig_ae` 支持：

- `CT-BFU`: Cooley-Tukey butterfly，输出 `a + b*w` 和 `a - b*w`。
- `GS-BFU`: Gentleman-Sande butterfly，输出 `a + b` 和 `(a - b)*w`。
- `MUL-ADD`: 输出 `a*b + c` 和 `a*b`。
- `ADD-MUL`: 输出 `(a+b)*c` 和 `a+b`。
- `ADD-SUB`: 输出 `a+b` 和 `a-b`。
- `BIG-MUL`: 输出 64-bit 乘积的低 32 bit 和高 32 bit。

`reconfig_ae_array` 默认实例化 32 个 AE lane，适合 coefficient-level 并行。

## FE 是什么

FE 是复数/固定点运算单元，适合处理 FFT、complex butterfly、复数乘加和后续可替换为浮点 FPU 的运算路径。

当前 `reconfig_fe` 使用 signed Q16.16 fixed-point 表达复数值，支持：

- `CADD`: 复数加。
- `CSUB`: 复数减。
- `CMUL`: 复数乘。
- `CMAC`: 复数乘加。
- `FFT-BFU`: 输出 `a + b*w` 和 `a - b*w`。
- `SCALAR-MUL`: 复数乘实数标量。

`reconfig_fe_array` 默认实例化 8 个 FE lane，适合向量化 FFT/complex datapath。

## 文件结构

- `rtl/reconfig_ae.v`: 单 lane AE。
- `rtl/reconfig_ae_array.v`: AE 阵列，默认 32 lane。
- `rtl/reconfig_fe.v`: 单 lane FE。
- `rtl/reconfig_fe_array.v`: FE 阵列，默认 8 lane。
- `rtl/barrett_reduce.v`: Barrett 模约减模块，供后续替换通用 `%` 路径。
- `rtl/filelist.f`: RTL filelist。
- `tb/tb_reconfig_ae.v`: AE 自检 testbench。
- `tb/tb_reconfig_fe.v`: FE 自检 testbench。
- `doc/ae_design_notes.md`: AE 设计说明。
- `doc/fe_design_notes.md`: FE 设计说明。

## 快速仿真

AE:

```powershell
iverilog -g2001 -o sim/tb_reconfig_ae.vvp rtl/reconfig_ae.v tb/tb_reconfig_ae.v
vvp sim/tb_reconfig_ae.vvp
```

期望输出：

```text
TB_PASS all 7 cases
```

FE:

```powershell
iverilog -g2001 -o sim/tb_reconfig_fe.vvp rtl/reconfig_fe.v tb/tb_reconfig_fe.v
vvp sim/tb_reconfig_fe.vvp
```

期望输出：

```text
TB_PASS all 6 FE cases
```

## 后续方向

- 增加统一配置寄存器和任务描述格式。
- 增加 AE/FE 共享乘法资源或 offload 接口。
- 将 FE 的 Q16.16 fixed-point datapath 扩展为目标浮点格式。
- 增加 top-level arithmetic cluster，把 AE array、FE array、buffer 和 scheduler 接起来。
