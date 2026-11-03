# 功能仿真

## 2026-11-03 批次错误蜂鸣回归

当前工程仍为 `(4)/fpgashare`。新增 `tb_batch_buzzer` 检查2kHz、200ms响/800ms停、NG重复、解除/重触发与复位；`tb_motor_resume` 增加报警和静音联动，原三档PWM与自动恢复断言保留。

```powershell
& ./sim/run_industrial_regression.ps1 -BuildName batch_buzzer_core_r1_20261103_validation -Tops tb_batch_buzzer,tb_motor_resume,tb_industrial_counter,tb_industrial_menu,tb_industrial_tracker,tb_frame_rate,tb_fps_display,tb_ae_boot_keys
python tools/verification/verify_batch_buzzer.py --build-record <本轮构建JSON>
```

8/8通过；完整CSI/视频本轮未重跑。功能、最终TD时序和上板声响是不同验证层次。详情见 `../docs/BATCH_BUZZER_20261103.md`。

## 2026-11-02 整机视觉升级回归

唯一目标是 `(4)/fpgashare` 整机。操作与验证边界见 `../docs/VISUAL_ENHANCE_20261102.md`；不要烧录根目录工程的视觉 bit。

```powershell
& ./sim/run_industrial_regression.ps1 -BuildName visual_core_final_20261102_validation -Tops tb_industrial_tone,tb_industrial_enhance,tb_industrial_counter,tb_industrial_tracker,tb_industrial_menu,tb_ae_target,tb_ae_once,tb_ae_once_single,tb_ae_boot_keys,tb_industrial_ui,tb_industrial_ui_rd2
& ./sim/run_video_modes_regression.ps1 -BuildName visual_video_final_20261102_validation -Tops tb_video_modes,tb_video_modes_onebeat,tb_video_modes_720p,tb_isp_video_modes,tb_video_mode_osd,tb_target_overlay,tb_parts_overlay,tb_video_tail_isp,tb_video_tail_isp_sobel,tb_video_tail_isp_enhance,tb_video_tail_isp_compare
& ./sim/run_ae_raw_isp.ps1 -BuildName visual_csi_20261102_validation -Tops tb_ae_csi_enhance
python tools/verification/visual_photo.py --prepare
& ./sim/run_industrial_regression.ps1 -BuildName visual_photo_20261102_validation -Tops tb_industrial_photo
python tools/verification/visual_photo.py
python tools/verification/verify_visual.py --build-record <本轮最终构建JSON>
```

亮度级新增82,704次灰阶/色彩/限幅/旁路检查，完整增强36,864个彩色像素、24组帧锁存参数和分屏。`tb_video_tail_isp_compare` 检查完整720p彩色三帧、紧消隐、DDR末行背压，左半严格原图，右半增强。真实照片RTL测试875,520个独立模型比对；导出图不是上板照片。UI两种读延迟各五帧并检查SPLIT菜单标签。

下面 industrial 记录为本轮之前的基线证据，其参数/像素数不代表新增强覆盖数。

## 2026-11-02 工业升级验收入口

当前 `(4)/fpgashare` 使用 AE152±8/16有效观测锁定、模式7 ENHN、统一16×16 UI和身份方向越线计数。
完整合同、按键及现场限制见 `../docs/INDUSTRIAL_UPGRADE_20261102.md`。

```powershell
& ./sim/run_industrial_regression.ps1 -BuildName industrial_core_r9_20261102_validation -Tops tb_industrial_enhance,tb_industrial_counter,tb_industrial_tracker,tb_industrial_menu,tb_ae_target,tb_ae_once,tb_ae_once_single,tb_ae_boot_keys,tb_industrial_ui,tb_industrial_ui_rd2
& ./sim/run_ae_chain_regression.ps1 -BuildName industrial_ae_r3_20261102_validation -Tops tb_ae_meter,tb_ae_chain,tb_ae_chain_dark,tb_ae_chain_midlight,tb_ae_chain_extreme,tb_ae_chain_gain_low,tb_ae_chain_gain_high,tb_ae_chain_motor,tb_ae_chain_nack,tb_ae_chain_boot_nack,tb_ae_chain_target_low,tb_ae_chain_target_high,tb_ae_chain_retarget
& ./sim/run_video_modes_regression.ps1 -BuildName industrial_video_r8_20261102_validation -Tops tb_video_modes,tb_video_modes_onebeat,tb_video_modes_720p,tb_isp_video_modes,tb_video_mode_osd,tb_target_overlay,tb_parts_overlay,tb_video_tail_isp,tb_video_tail_isp_sobel,tb_video_tail_isp_enhance
& ./sim/run_parts_regression.ps1 -BuildName industrial_parts_r7_20261102_validation -Tops tb_parts_multi_backlit,tb_parts_multi_backlit_latency,tb_parts_solid_rejection,tb_box_tracking,tb_recognition_latency
& ./sim/run_ae_raw_isp.ps1 -BuildName industrial_csi_r4_20261102_validation -Tops tb_ae_csi_system
# 使用实际 build JSON 路径核验全部51顶层、ROM资产、源清单、原SDC下最终时序和bit身份：
python tools/verification/verify_industrial.py --build-record <最终industrial构建JSON路径>
```

- 新增强测试独立检查12组强度/门限、18432彩色像素、色差保持、边界/有效间隙/尾行和帧首锁存。另用 `tb_video_tail_isp_enhance` 验证连续3帧完整720p ENHN在紧消隐、DDR末行背压下的独立像素、地址和帧边界。
- 新计数/跟踪测试检查同类替换、换槽、反复跨线、两次漏检、20/40/120ms间隔、160px预测关联、360ms漏检恢复、启动静物、DONE后惯性通过和显式ACK。
- 新菜单覆盖15项、参数上下界、单次ACK、故障停止后不自动重启；新UI对两种读延迟各渲染4帧完整720p，核验528个菜单字和未覆盖相机像素。
- 新参数下AE链继续断言EXP优先，仅在EXP≤8且控制器检测到整数档方向翻转时允许GAIN单档微调。历史“除上下限外GAIN绝不变化”合同已由此明确例外替代。
- `tb_target_overlay` / `tb_parts_overlay` 更新为新字体，控制面板保留区域由 `tb_industrial_ui` 单独逐像素/字形验证，其余目标框、标签、候选隐藏和帧内原子发布继续精确检查。
- 第5个目标导致容量不足时保留两次漏检保护，不强行抢占ID；旧身份过期后，新身份仍须三次真实确认。
- 短漏检后保留已确认形状和匹配颜色，`tb_parts_multi` 的单次消失后回归期望已更新；不把正确的保留行为当作重新确认失败。
- 旧 `tb_parts` 的 kind10/孔洞场景在修改前后同处失败，日志分别在 `industrial_prior_parts_20261102_validation` 和 `industrial_parts_r1_20261102_validation`。旧普通照明宽阴影测试仍未解决。
- 旧 `tb_batch_counter`（按占线数量）和旧UI固定坐标测试为历史合同，不用其通过结果冒充本次新计数/UI验证。


2026-11-01 AE4曝光优先见`docs/AE_EXPOSURE_20261101.md`。`run_ae_chain_regression.ps1 -Tops tb_ae_chain,tb_ae_chain_dark,tb_ae_chain_gain_low,tb_ae_chain_gain_high`独立解码实际曝光寄存器，要求普通场景EXP确实改变，并断言EXP=3才降GAIN、EXP=2244才升GAIN；`-AeSource`支持原GAIN优先控制器负对照。完整CSI用LIGHT=32裁剪亮场验证真实EXP写入，长路径由快速闭环覆盖；生产参数不改。35/35项回归、原SDC下TD最终时序和默认bit核验已通过，尚未上板。回归及默认bit身份核验入口为`tools/verification/verify_ae_exp.py`。

历史AE3目标菜单测试（当前AE4保留该合同）见`docs/AE_TARGET_20261101.md`。`run_ae_once_regression.ps1 -Tops tb_ae_target,tb_ae_target_status,tb_ae_target_status_rd2`覆盖默认128/范围64～192、16次有效观测锁定、17个目标的双读延迟OSD、锁后重调与I2C忙时改目标。`run_ae_chain_regression.ps1 -Tops tb_ae_chain_target_low,tb_ae_chain_target_high,tb_ae_chain_retarget`验证实际I2C/N+2闭环。`tb_ae_once`显式指定历史176～216/8次参数，仅用于保留参数化回归，不代表当前生产默认值。

现场MAN反馈后的原生CSI/校正/开机按键测试见`docs/AE_FIELD_BOOT_20261101.md`：新增`run_image_correction_regression.ps1`，`run_ae_raw_isp.ps1 -Tops tb_ae_csi_system`不再绕过CSI/RAW10解包、uial2axis与image_correction；`tb_ae_boot_keys`及`tb_ae_live_status`覆盖启动与AE2可见诊断。旧校正器/按键负对照日志保留。

2026-11-01 用户反馈前一版仍需手调，新增 `run_ae_chain_regression.ps1`：8个顶层覆盖独立测光、开机AUTO、实际I2C解码、异步配置时钟、N+2生效、暗/亮/短曝光、最小增益下的中等照明振荡反例、运行电机与NACK重试、锁定后停止写入。`run_ae_raw_isp.ps1` 使用真实生产RAW10/去马赛克/720p ISP，验证测光接线与视频完整性。`run_ae_once_regression.ps1` 补测控制器、菜单MAN/AUTO/LOCK和显式手动接管，不再沿用错误的默认MAN/运动HOLD/小于16无效合同。详情见 [AE_CHAIN_BOOT_20261101.md](../docs/AE_CHAIN_BOOT_20261101.md)。64/65像素速度边界测试仅复现现有算法限制，不能视为真实输送带提速通过。

2026-10-31 将显示模式7（SW1~SW3全开）从重复BIN改为低资源 `CART`：8级RGB量化叠加较高门限的黑色Sobel轮廓，复用原行延迟与帧尾处理，识别通路不变。`tb_isp_video_modes` 已加入模式7像素参考和DDR帧边界检查。Vivado 2022.2 `xvlog` 静态分析与 `xelab` 静态展开完成；本机仍在生成C文件阶段报既有 `XSIM 43-3409`，因此没有行为仿真通过结论。

2026-10-31 批次计数新增 `tb_batch_counter`：覆盖同一结果包内两个目标同时进入计数线、目标槽换序不重复计数、计数线清空后再次双目标计数、KEY1/KEY2分别设定SCR/WAS/HEX/SQU配额、KEY3短按统一清零与长按切换当前配额，以及四个非零配额全部满足后才锁存完成。为缓解整机拥塞，生产计数器已改为按类别比较相邻结果包的计数线占用数，只累计正增量，目标范围为0~99；同类别零件需在计数线保持基本间距。Vivado 2022.2 `xvlog` 静态分析通过；本机 XSim 仍在生成C文件阶段报既有 `XSIM 43-3409`，因此没有行为仿真通过结论。

2026-10-28 传送带动态框新增 `tb_box_tracking`：验证同一目标按显示帧平滑前进、新目标/形状变化/大位移直接吸附以及目标消失撤框。已加入 `run_parts_regression.ps1` 默认列表。当前 Vivado 2022.2 可完成 `xvlog` 静态分析，但本机 XSim 在生成 C 文件编译阶段失败，因此尚无行为仿真通过结论；上板前仍需重新完成 TD 资源与时序检查。

2026-10-25 正常照明/白纸背景新增 `tb_parts_ambient_shadows`：在渐变、纹理和四个宽软投影下同时验证银色垫圈、红色六角螺母、黑色方螺母及黄铜螺钉；`tb_parts_solid_rejection` 独立验证实心银色圆不会因掩膜空洞被误报为垫圈。两项已加入 `run_parts_regression.ps1` 默认列表，说明见 [NORMAL_LIGHT_SHADOW_SEGMENTATION_20261025.md](../docs/NORMAL_LIGHT_SHADOW_SEGMENTATION_20261025.md)。

2026-10-22 延迟可视化新增 `tb_recognition_latency`、`tb_parts_multi_latency`、`tb_latency_overlay`，已加入零件回归默认列表；实际尺寸 `tb_auto_wb_isp` 同时打开并核验延迟接口。计时定义、独立运行命令与验证边界见 [LATENCY_OSD_20261022.md](../docs/LATENCY_OSD_20261022.md)。

2026-10-19 颜色优化新增 `tb_parts_color_hsv`（独立HSV色相扫描）、完整零件反光黑色/暖黄铜用例和 `tb_parts_clean_overlay`（仅EXP/GAIN与目标标签/图标逐像素检查），已加入 `run_parts_regression.ps1` 默认列表；说明见 [COLOR_HSV_20261019.md](../docs/COLOR_HSV_20261019.md)。

2026-10-19 自动白平衡新增 `tb_awb_auto_reference`（真实AWB对比旧中心/固定1倍，含失去样本和重获）、`tb_bayer_neutral`（真实BGGR插值）、`tb_auto_wb_isp`（实际1280×720 ISP接线与逐拍校验）、`tb_auto_wb_overlay`（WAIT/AUTO/HOLD及四目标标签）和 `tb_parts_multi_no_calibration`（无锁定/参考门控的目标确认）。已加入对应脚本默认列表，说明见 [AUTO_WB_20261019.md](../docs/AUTO_WB_20261019.md)。历史手动校准模块回归保留，但不代表当前生产版要求放白纸。

从原工程迁入当前维护所需的三组测试及其直接源码依赖，未复制仿真数据库、旧源码备份或构建缓存。均使用当前仓库的 `user_source`，不需要原 `D:/FPGA_competition` 目录。

运行环境：Windows PowerShell、Vivado XSim。默认工具路径是 `D:/AMDDesignTools/2025.2/Vivado`；安装位置不同时使用参数覆盖。脚本中的运行库路径按该版本组织，其他版本需要核对。

在仓库根目录执行：

```powershell
# 颜色比例、白平衡校准与失效回退、诊断、实际尺寸ISP、多目标OSD
& ./sim/run_colour_stability_regression.ps1 -VivadoRoot 'D:/AMDDesignTools/2025.2/Vivado'

# RGB/GRAY/SOBEL/EDGE等模式及帧尾、DDR连续性
& ./sim/run_video_modes_regression.ps1 -VivadoBin 'D:/AMDDesignTools/2025.2/Vivado/bin'

# 零件形状与颜色基础回归
& ./sim/run_parts_regression.ps1 -VivadoRoot 'D:/AMDDesignTools/2025.2/Vivado'
```

可用 `-Tops` 选择测试，`-BuildName` 指定 sim 下的单层输出目录。建议目录名带 `validation`，会被已有 .gitignore 排除：

```powershell
& ./sim/run_colour_stability_regression.ps1 -BuildName migration_validation -Tops tb_wb_probe,tb_wb_probe_isp
```

摄像头/厂商 RAM 等在部分测试中使用仿真替身，不能据此判断真实 Bayer 输入、现场光谱或物理时序。测试通过不表示 bit 已生成或上板通过。迁移后重跑结果见 `docs/migration_validation.txt`；历史证据另见 `docs/evidence/`。
