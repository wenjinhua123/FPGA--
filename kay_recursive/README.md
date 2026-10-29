# 1024 点递推 Kay

目录中保留已接好学长前端的 SysGen 模型、Black Box 源码、可搬运 ZIP、实测数据，以及一份直接调用模型的 MATLAB 比较脚本。

在 MATLAB R2021b + Model Composer / Vivado 2022.2 环境中运行：

```matlab
run('E:/FPGA/kay_recursive/run_real_data_kay.m')
```

脚本读取 `data_10dB_100MHz.dat` 的前 8192 个复数采样，再生成 100 MHz、10 dB 的模拟 I/Q，以及 20000 点、−1000 到 +1000 MHz 的线性调频 I/Q。三组数据分别送入 8 路 SysGen 模型；脚本对同一批 1024 点窗口计算 MATLAB 标准 Kay。测试输入结束后继续仿真 64 拍以排空流水线，只统计原始数据的完整窗口。脚本从首个非零输出开始比较均值和样本方差；线性调频还报告首末窗口频率及逐窗误差。均值单位 MHz，方差单位 MHz²。线性调频的首末完整窗口中心频率约为 −948.797 和 +948.897 MHz，因此 Kay 结果不会直接达到输入扫频的 ±1000 MHz 两端。修改脚本顶部 `groups` 可改变前两组联合仿真长度。运行需要 Model Composer 和 Vivado Simulator；脚本不会生成结果文件。

- `kay1024_recursive_demo.slx`：已连接的 SysGen 模型。
- `open_kay_demo.m`、`kay_demo_init.m`：模型打开与默认输入。
- `kay1024_phase_blackbox_config.m`、`kay1024_phase_blackbox.v`、`rtl/`：Black Box 配置和 Verilog。
- `tools/sync_sysgen_hub.m`：搬运后更新 Hub 路径和 3.2 ns 时钟。
- `export/kay_sysgen_portable.zip`：当前模型及全部运行依赖，解压整个 ZIP 后运行其中的 `open_kay_demo.m`。为保持交付包精简，ZIP 不含单独的比较脚本和约 8 MB 的实测数据。

输入每拍 8 路复数采样，每路 312.5 MHz。对外只输出 `freq_q20`（Fix32_20 MHz）；内部上电初始化并判断相位流与窗口是否就绪。首个完整窗口之前输出 0，之后连续输入时逐拍更新。输出端的 1 拍 Delay 给初始值 0 并明确采样周期。`build/` 是运行时缓存，也含修改前模型备份。
