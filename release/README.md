# 安路赛题一｜作品发布说明

作品支持五图切换、自动轮播、音频播放、音量/亮度/对比度调节、图片缩放适配、三种转场、频谱/波形、中文字幕，以及矩阵键盘、红外、光敏和串口上位机交互。

## 当前状态

作品已完成 TD 构建、时序检查、RTL 仿真、上位机检查和实物验收。Flash 烧录、断电重启恢复、HDMI 音画输出及各外设功能均已验证通过，详见 [成果验收记录](../docs/acceptance.md)。

- [最终烧录文件](fpga_museum_v49_no_adc_display_20261029.bit)，662236 字节，使用 BitWizard 的 Program Flash 烧录。
- SHA-256：`EC811943202F789E12964209EA967996BA6FE7976F1EA777082A2ADC45194D2B`。
- [构建日志](build.log)、[时序结果](media_phy.ts)、[详细时序](media_pr.timing)、[构建阶段校验记录](validation.json)。构建阶段记录保留当时的原始状态；最终实物完成情况以成果验收记录为准。

## 管理控制台

[打开管理控制台](../tools/Open_Admin_Console.cmd)，选择板卡实际 COM 口并连接。Type-C / CH340，115200 8N1，FPGA RX=F12、TX=D12；使用协议版本 2。支持切图、轮播、参数调节、音频控制、中文字幕发送和状态回读。

## 验证与实现

- 六组 ADC、手动超时、按键、遥控、红外和菜单回归通过；UART 控制仿真、菜单显示检查与上位机自检通过。
- 实物完成 Flash 固化与断电重启验证，图片、音频、字幕、转场、缩放适配、可视化及外设交互验收通过。
- 最终布局种子 23 完成 bitgen；SWNS=0.410 ns、HWNS=0.024 ns、STNS/HTNS=0，STA coverage=97.66%，ADC 时钟 13.500 MHz。布局后 4896/4900 MSlice、62/64 BRAM、29/29 DSP；布线后 4892 MSlice。已有厂商警告保留，不声称零警告或全部路径覆盖。
- 发布文件与通过的构建 bit 的 SHA-256 一致，78 个源码、ROM、约束和构建脚本与构建副本一致。

检查记录：[像素与菜单仿真](../evidence/tb_menu_values_checked.log)、[真实 UART 仿真](../evidence/admin_control.log)、[原六组回归](../evidence/adc_simulation_results.json)、[上位机自检](../evidence/host_self_test.log)、[GUI 记录](../evidence/gui_check.json)。[源码与构建命令](../README.md)。

## 接线与运行

红外：**VCC=J1-29 / 3.3 V，GND=J1-30 / GND**；信号线 `S=J1-2`，`ir_rx` 约束为 FPGA N4。完整连接见 [J1/J2 接线图](../hardware/j1-j2-ir-keypad-light-wiring-style-v4.png)。

图片和音乐仍由 TF 卡提供。手动亮度约 30 秒无用户操作后恢复自动；状态轮询不延长超时。光敏接线 A=J2-29、B=J1-16、C=J2-30，ADC 时钟保持 13.5 MHz。旧 Python 管理员协议不适用。

