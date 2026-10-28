# 1024 点递推 Kay

目录中保留已接好学长前端的 SysGen 模型、Black Box 源码、可搬运 ZIP、实测数据，以及一份直接调用模型的 MATLAB 比较脚本。

在 MATLAB R2021b + Model Composer / Vivado 2022.2 环境中运行：

```matlab
run('E:/FPGA/kay_recursive/run_real_data_kay.m')
```

脚本读取 `data_10dB_100MHz.dat` 的前 8192 个复数采样，再生成一组 100 MHz、10 dB 的模拟 I/Q。两组数据分别送入 8 路 SysGen 模型；脚本对同一批 1024 点窗口计算 MATLAB 标准 Kay，只在 `kay_valid=1` 时比较输出频率的均值和样本方差。均值单位 MHz，方差单位 MHz²。修改脚本顶部 `groups` 可改变联合仿真长度。运行需要 Model Composer 和 Vivado Simulator；脚本不会生成结果文件。

- `kay1024_recursive_demo.slx`：已连接的 SysGen 模型。
- `open_kay_demo.m`、`kay_demo_init.m`：模型打开与默认输入。
- `kay1024_phase_blackbox_config.m`、`kay1024_phase_blackbox.v`、`rtl/`：Black Box 配置和 Verilog。
- `tools/sync_sysgen_hub.m`：搬运后更新 Hub 路径和 3.2 ns 时钟。
- `export/kay_sysgen_portable.zip`：模型及全部运行依赖，解压整个 ZIP 后运行其中的 `open_kay_demo.m`。

输入每拍 8 路复数采样，每路 312.5 MHz。`freq_q20` 为 Fix32_20 MHz，仅在 `valid_out=1` 时使用。`build/` 是运行时生成的缓存，关闭占用它的 MATLAB 后可删除。