# FE 模块设计说明

## 设计定位

FE 表示 Floating/Field Element。它不是单纯的标量浮点加法器，而是面向复数域和 FFT/IFFT 数据流的可重构运算单元。

在可重构 arithmetic cluster 中，FE 负责：

- 复数 CT butterfly，用于 FFT 正向变换。
- 复数 GS butterfly，用于 IFFT 逆向变换。
- 标量 fixed-point / floating-style 加、减、乘。
- 复数加、减、乘、平方、乘加。
- 与 AE 阵列协作，将复数乘法中的实数 big-mul 路径外包或替换。

当前 RTL 使用 signed Q16.16 fixed-point 作为可综合原型。后续可把 `scale_product` 和乘法路径替换为真实 f64/fpr FPU 或 AE offload 接口。

## 接口假设

- 默认数据宽度为 32 bit。
- 默认小数位为 16 bit，即 Q16.16。
- 每个 FE lane 使用 `valid_in` / `valid_out` 流水接口。
- 固定 3 级流水。
- 输入包括复数 `a`、`b`、`c` 和 twiddle `w`。
- 输出 `y0`、`y1` 两个复数，适配 butterfly 类双输出。

## FE mode

| mode | 名称 | y0 | y1 |
|---:|---|---|---|
| 0 | CT-BFU(complex) | `a + b*w` | `a - b*w` |
| 1 | GS-BFU(complex) | `a + b` | `(a - b)*w` |
| 2 | FLOAT-ADD | `a_re + b_re` | `0` |
| 3 | FLOAT-SUB | `a_re - b_re` | `0` |
| 4 | FLOAT-MUL | `a_re * b_re` | `0` |
| 5 | COMPLEX-ADD | `a + b` | `0` |
| 6 | COMPLEX-SUB | `a - b` | `0` |
| 7 | COMPLEX-MUL | `a * b` | `0` |
| 8 | COMPLEX-SQR | `a * a` | `0` |
| 9 | COMPLEX-MAC | `a * b + c` | `a * b` |

## FFT operator

`reconfig_fft_operator.v` 是 FE array 的第一层调度外壳：

- 默认使用 8 个 FE lane。
- `inverse=0` 时选择 CT-BFU(complex)，表达 FFT 正向 butterfly。
- `inverse=1` 时选择 GS-BFU(complex)，表达 IFFT 逆向 butterfly。
- 输入向量为 `Va`、`Vb` 和 twiddle vector `Vc`。
- 输出向量为更新后的 `Va`、`Vb`。

当前 operator 只实现 lane 级并行 butterfly，没有实现完整多 stage permutation、twiddle ROM、buffer bank 和任务调度。后续应在这个外壳上继续增加 stage counter、input/output permutation 和 buffer 接口。

## 文件

- `rtl/reconfig_fe.v`：单个 FE lane。
- `rtl/reconfig_fe_array.v`：参数化 FE 阵列，默认 8 lane。
- `rtl/reconfig_fft_operator.v`：基于 FE array 的 FFT/IFFT butterfly operator。
- `tb/tb_reconfig_fe.v`：FE mode 自检 testbench。
- `tb/tb_reconfig_fft_operator.v`：FFT/IFFT operator 自检 testbench。
