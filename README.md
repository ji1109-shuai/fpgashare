# PH1P35 零件视觉识别

基于安路 PH1P35 与 SC500CS 的实时视觉工程，支持多目标零件形状/颜色识别、图像处理预览、曝光/增益控制及白平衡诊断。

当前为白平衡诊断版本，摄像头画面偏绿尚未确定完整根因；不能作为颜色已稳定通过的版本。

- TD 工程入口：`td_project/camera_to_dsi_display.al`。
- 源码、IP、引脚约束：`user_source/`。
- 功能仿真：`sim/README.md`。
- 当前状态和下一步：`HANDOFF.md`。
- 关键调试证据、硬件资料与历史记录：`docs/README.md`。
- 工程协作约定：`AGENTS.md`。
- 两人 Git/GitHub 操作指南：[分支开发、提交与 PR 合并](docs/GIT_COLLABORATION.md)。

保持 td_project 与 user_source 的同级目录关系。换电脑或路径后核对工程根路径和 TD/IP 工具版本。TD 编译、bit 生成及下载由用户进行；功能仿真不代替物理时序检查或上板验证。

仓库中部分 IP 和硬件参考资料来自开发板/芯片厂商，保留原有版权声明；本仓库没有给这些资料授予新的开源许可。
