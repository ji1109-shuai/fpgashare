# 整机显示增强升级（2026-11-02）

## 工程范围和当前状态

用户确认的唯一整机工程是 `D:/fpgashare/fpgashare (4)/fpgashare`，入口为本目录的 `td_project/camera_to_dsi_display.al`。根目录 `D:/fpgashare` 的单独视觉 bit 缺少整机功能，不是本次交付，不得用于替代整机。

本轮只升级模式 7 的显示处理及其比较开关。保留本整机既有电机、AE5、15 项菜单、四类批次计数、NG/ACK/清场保护、AWB、安路图标和确认目标的框/标签。216 项修改前输入中只有四份生产 RTL 变化；约束、引脚、图标与字体 ROM 保持不变。顶层中菜单、电机和计数器模块逐字保持不变。

构建和完整 CSI 闭环验证已完成，37/37 项本轮功能验收通过。归档 bit 为 `release_archive/visual_20261102/camera_to_dsi_display_visual.bit`，本工程默认 `td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit` 已于20:11:42同步。最终证据见 `sim/visual_upgrade_20261102_validation/verification.json`。没有上板实测。

## 增强内容

原模式 7 只有带噪声门限的小幅局部锐化，在金属件拍屏中不明显。本轮保留这一级并串接亮度 S 曲线和色差增强：

1. 3×3 Gaussian 基底与中心亮度做差，软噪声门限抑制微小起伏，细节偏移限幅 ±24，并按 RGB 共同余量限制，避免锐化级单通道先裁剪。
2. 以 `Y=(R+2G+B)/4` 形成亮度。64/128/192 处分段，默认 DETAIL=2 对应输出 24/128/232，中间调明暗差拉开，暗端/亮端斜率降低。黑白端保持 0/255。
3. 在新亮度上回加 1.25 倍原色差，所有输出通道限制在 0～255。它会使金属表面明暗和色差更显眼；强档可能增加暗部压缩和饱和色裁剪，不称作颜色测量校准。

实现使用移位、加法和寄存流水，无新的全帧缓存。只有 ENHN 增加一拍，其余 RGB/GRAY/SOBEL/EDGE/BIN/ERODE/DILATE 的既有像素节奏保留。行回放与 DDR 帧边界沿用原结构，增加的一拍通过 ENHN 数据和标记一起传递。

显示增强位于 AWB 和识别/测光分支之后，不反馈给 AE/AWB/分类/计数。AEY 的物理目标仍为整机原有 152±8；不能用增强后的屏幕亮度直接当作测光 AEY，也不能声称增强提高了识别准确率。

## 操作

- 菜单 VIEW 选 ENHN（默认模式 7）。
- DETAIL=0：完整原图旁路；1：轻；2：默认；3：强。DETAIL 同时控制局部锐化和曲线强度，已有菜单位置不变。
- NOISE=0～15，默认 4。它只控制局部锐化的软门限，不控制整幅 S 曲线。平坦背景颗粒明显时适当提高。
- SW1 拨到逻辑 1：同帧左半原图、右半增强，VIEW 显示 SPLIT。拨到 0：整幅增强，显示 ENHN。其他模式像素不受 SW1 影响。开关在帧首生效，不在帧中切割参数。
- SW4 仍是菜单开关，K1/K2 仍为选择，K3/K4 仍为当前项目减/加或确认。SW1 不接电机按键路径。

## 效果证据及展示用语

`sim/visual_upgrade_20261102_validation/photo_strength_comparison.png` 是用户螺丝拍屏照片裁剪后送入生产 RTL 的离线输出，左上原图、右上轻档、左下默认档、右下强档。875,520 个 RGB 像素与独立 Python 整数模型逐点一致。它不是新 bit 上板照片，无法覆盖相机噪声、真实光照变化和显示器响应。

建议展示时用 SW1 做同帧比较，并说明：

> 系统在实时视频显示支路采用带噪声门限的局部细节增强，结合分段亮度 S 曲线和色差增强，突出金属零件的螺纹、边缘与表面明暗层次。增强强度可调，支持同帧原图/增强分屏比较。识别与计数继续使用独立的原有处理支路。

不声称“恢复已经过曝丢失的纹理”“任意照明均有效”“消除运动模糊”“识别率已提高”。原普通照明宽阴影的 kind10 形状失败仍是历史已知限制，本轮没有修改其识别算法。

## 验证和交付入口

- 核心回归：`sim/visual_core_final_20261102_validation`，亮度全灰阶/彩色立方/饱和限幅/旁路、24 组增强参数与分屏、菜单、电机停止、计数/跟踪、AE目标/按键、两种 UI 读延迟。
- 视频回归：`sim/visual_video_final_20261102_validation`，8 种完整 720p 模式、OSD、确认目标标签、三帧紧消隐与末行 DDR 阻塞、彩色 ENHN 分屏。
- AE I²C 定向回归：`sim/visual_ae_final_20261102_validation`。
- 完整 CSI→ISP→AE→I²C 且 ENHN 开启：`sim/visual_csi_20261102_validation/tb_ae_csi_enhance.log`。
- 真实照片 RTL：`sim/visual_photo_20261102_validation/tb_industrial_photo.log`。
- 独立工程构建：`td_project/camera_to_dsi_display_Runs/visual_r1_build_20261102_191216.json`。
- 最终核验工具：`tools/verification/verify_visual.py`；默认 run 安全同步工具：`tools/promote_visual.ps1`。二者使用本轮独立目录，保留旧 industrial 交付。

本轮 TD 已于 2026-11-02 19:42:55 完成。原 SDC 下最终 Setup +0.004ns、Hold +0.020ns，TNS 和违例端点均为 0；Routing DRC 完成且通过，无实现 ERROR/FATAL。Slice 19993/21216、LUT6 19505/21216、ERAM 80/108、DSP 22/40；STA 覆盖 94.70%。66 项构建输入和 ROM 哈希未变。Setup 余量仅 4ps，很小，不能推广为任意约束/板况均已验证。

原始 run、归档及默认 run 的 bit SHA256 为 `AD5A84BC4AEEDE8F9164F38C1981E5120D8F3A99C7CE4C14E7848145A10620F4`。完整 CSI→RAW→ISP→AE→实际 I²C 闭环共67帧：第55帧AEY152/EXP1282/GAIN112锁定，随后降低光照到AEY24，继续12帧没有新增曝光或增益写入；这是合成光学模型的功能验证，不能当作真实相机上板结果。

旧默认 run 完整保存在 `syn_1_before_visual_20261102_201142` 和 `phy_1_before_visual_20261102_201142`。覆盖前默认 bit 实际 SHA256 为 `99F2BF01E68CDF8222AC781BAFF0CEF9297A8B0696DAF64B5304F9E1AD6A1251`，不以历史文档的归档 hash 冒充当时默认文件。

UI两拍读延迟首次仿真出现一次未知相机像素，原因未确定；加入诊断后独立重跑及最终五帧全套均通过，未因此修改生产RTL。原失败日志保留于 `sim/visual_core_r2_20261102_validation`，最终通过日志在 `sim/visual_core_final_20261102_validation`。

物理时序必须以最终 Setup/Hold WNS、TNS、违例端点和 DRC 报告为准，功能仿真不能替代。旧接口/调试探针提示及原 SDC 时序覆盖限制不因本轮显示增强而消失。
