# 功能仿真

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
