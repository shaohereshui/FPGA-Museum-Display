# 安路赛题一｜无人值守博物馆智能显示屏

安路赛题一作品，基于 HX4S20C / EG4S20 的博物馆多媒体显示系统。
面向无人值守展陈，使用 FPGA 完成 TF 卡媒体读取、SDRAM 缓存、HDMI 输出与交互控制。

## 当前功能与状态

包含图片切换、自动轮播、音频播放、中文字幕、转场、图片适配、频谱/波形、音量/亮度/对比度调节、矩阵键盘、红外、光敏自动亮度及串口上位机。
HDMI 和上位机不显示 ADC 诊断信息，光敏自动亮度功能保留。
历史构建与仿真记录随包提供；实物 Flash 烧录、断电恢复和所有外设效果仍需用户现场确认。

## 目录

- `projects/tf_sdram_hdmi_media_extension_candidate/`：主工程、全部 RTL、ROM、PLL/SDRAM IP、引脚/时序约束和构建脚本。
- `projects/anlu_hdmi/`、`projects/hdmi_audio_probe/`：主工程引用的 HDMI、FIFO、TF/FAT32 和音频模块。
- `tools/`：Windows 上位机、串口协议、工程准备、构建和验证脚本。
- `evidence/`：SystemVerilog 测试源码、仿真数据及既有验证记录。
- `release/`：最终烧录文件、构建日志和时序报告，详见 [发布说明](release/README.md)。
- `reports/`：最终种子 23 的资源与时序报告。
- `hardware/`：[J1/J2 接线图](hardware/j1-j2-ir-keypad-light-wiring-style-v4.png)及 SVG 源文件。

`projects/`、`tools/`、`evidence/` 必须保持同级；本包不包含仿真编译缓存、失败构建、工具安装程序或 TF 卡图片/音乐素材。
编译需要的 ROM/HEX 和仿真输入数据已经包含，运行用的媒体需另备 TF 卡。

## 环境与上位机

Windows、Anlogic TD 6.2.1、器件 EG4S20BG256；仿真使用 ModelSim。
上位机使用系统自带 Windows PowerShell 5.1 / .NET WinForms，无需 Python。

双击 [Open_Admin_Console.cmd](tools/Open_Admin_Console.cmd)，选择板载 Type-C / CH340 的 COM 口并连接。
串口为 115200 / 8N1，无流控；驱动、TD 和 ModelSim 需自行安装。协议见 [UART_PROTOCOL.md](tools/UART_PROTOCOL.md)。
没有额外环境变量或密钥配置；TD、ModelSim 路径通过以下参数指定。

## 构建与验证

在解压后的本目录运行，替换工具路径为本机实际安装位置：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/test_admin_host.ps1
./tools/run_admin_checks.ps1 -ModelSimBin 'D:/modelsim_ase/win32aloem'
./tools/run_adc_checks.ps1 -ModelSimBin 'D:/modelsim_ase/win32aloem'
$project = ./tools/prepare_project.ps1 -Destination ./build_repro
./tools/build_v47.ps1 -TdExe 'D:/FPGA/tools/Anlogic/TD_6.2.1/bin/td_commands_prompt.exe' -PreparedProject $project
```

`build_repro` 必须不存在。准备脚本创建工程副本、重定位 `.al` 并检查工程引用。
构建脚本和重建输出沿用历史工程文件名，实际构建本仓库当前提交的源码。
构建脚本不会烧写板卡。直接使用已发布文件时请选择 [最终烧录文件](release/fpga_museum_v49_no_adc_display_20261029.bit)。

## 设计与限制

媒体经 TF/FAT32 读取与解析后进入 SDRAM/音频缓冲，再由 HDMI 视频/音频链路输出；按键、红外、光敏和 UART 汇入控制逻辑。
手动亮度约 30 秒无用户操作后恢复自动；状态轮询不延长超时。光敏改变视频像素亮度，不控制显示器背光。
最终种子 23 布线后 MSlice 4892/4900，BRAM 62/64、DSP 29/29；SWNS=+0.410 ns、HWNS=+0.024 ns，STA coverage=97.66%。资源接近满载，已有厂商警告保留。
旧 Python 上位机协议不适用；当前使用协议 v2。下一步为用户烧录并现场确认显示、声音、外设和断电重启。

本次只整理目录和提交说明，未修改 FPGA 或上位机功能代码，未增加兼容、兜底或降级逻辑。

## 提交前隐私检查

两份构建日志中的运行用户名和电脑名已替换为 `[REDACTED]`，其余构建结果保留。
已对包内文本检查账号、用户目录、联系方式和常见密钥格式，并检查 PNG 元数据；未发现用户联系方式或密钥。
保留厂商和第三方版权署名，以及不含用户标识的工程/工具路径。源码、测试、约束及 bit 文件保持不变。
公开仓库只包含本目录中的交付文件，不包含开发机工作区、账号配置或历史 Git 提交。仓库使用 GitHub 隐私邮箱提交。

## 仓库与使用

本仓库用于作品代码展示与比赛评审。第三方源码和 IP 的原有版权声明保留，使用时遵守相应权利与工具许可；本仓库未另行授予统一开源许可。

运行仿真产生的编译库、波形和重建输出通过 `.gitignore` 排除，已交付的源码、仿真输入、历史验证日志及发布报告保留。

首页和上位机使用作品名称；历史构建记录和技术文件名保留过程版本信息，用于校验和追溯。
