# 批次错误蜂鸣提示（2026-11-03）

唯一工程：`D:/fpgashare/fpgashare (4)/fpgashare`，入口 `td_project/camera_to_dsi_display.al`。

## 操作规则

- 计数器进入 NG 时，原有停车与屏幕 `BATCH: NG STOP` 保持，同时开始蜂鸣。
- 声音为 2 kHz，响 200 ms、停 800 ms，每秒重复一次，直到 NG 解除。
- 普通错件、非需求类别及超量件：移走错误类别，经原有连续三次新的完整目标发布确认后，NG 解除，声音停止；若操作员没有主动选择 STOP，则恢复之前选择的速度。
- 身份歧义、检测故障等原来需要 ACK 的错误：仍需按原规则处理并 ACK。蜂鸣器本身没有清故障、改计数或重启电机的权限。
- 操作员在 NG 中选择 STOP，只取消电机自动重启；尚未解决的 NG 继续蜂鸣。
- 正常 STOP、正确批次 DONE、NEW BATCH 等待清场、开机和复位均不触发错误提示音。开机时如果随后检测到实际 NG，仍会报警。
- 报警持续期间再次出现错误，沿用当前提示节奏；NG 已解除后再次出现错误，则从新的短鸣开始。

## 接入位置与保留功能

只增加两处生产输入：

1. `user_source/hdl_source/design_top_wrapper.v`：新增顶层 `O_buzzer`、`u_batch_error_buzzer` 观察支路和同文件 `batch_error_buzzer` 模块。使用 50 MHz 系统时钟，与计数器同域，直接观察 `S_batch_overrun`，没有反向控制连线。
2. `user_source/constraints_source/pin.adc`：新增 `O_buzzer=C12`，LVCMOS33、8 mA、上拉。依据工程保存的开发板原理图及前序蜂鸣控制资料，C12 经 PNP 支路低有效，因此空闲输出高电平，报警时输出方波。

原有计数器、菜单、电机 PWM 和帧率模块逐字保留；顶层除新增端口/实例/模块外也与修改前一致。AE152±8、曝光优先、AWB、工业增强及分屏、透明统一字号 UI、安路图标、STOP/65%/80%/100% 和帧率显示保留。百分比仍表示 PWM 占空比。

## 验证与交付

证据目录：`sim/batch_buzzer_20261103_validation`。独立验收入口：

```powershell
& ./sim/run_industrial_regression.ps1 -BuildName batch_buzzer_core_r1_20261103_validation -Tops tb_batch_buzzer,tb_motor_resume,tb_industrial_counter,tb_industrial_menu,tb_industrial_tracker,tb_frame_rate,tb_fps_display,tb_ae_boot_keys
python tools/verification/verify_batch_buzzer.py --build-record <本轮构建记录JSON>
```

- 8/8 定向功能顶层通过，使用 `--O0 --debug typical`。蜂鸣器检查 720,518 个周期采样，覆盖重复 NG、2 kHz/200 ms/800 ms 节奏、响声中/间隙中解除、再次触发、活动报警时复位，以及默认 50 MHz 参数下的分频。
- 联动测试 62 项断言，检查真实三档 PWM、错件暂停、三次新的完整发布后恢复、短漏检/重新出现、手动 STOP、硬故障 ACK、批次 DONE 和超额审计；加入 NG 发声以及自动恢复/ACK 后静音、正常 STOP/DONE/清场静音检查。
- 计数器、菜单、跟踪器、FPS 计量/显示和启动按键/AE 另行回归通过。生产输入 216 项及根工程 65 项保护哈希核对；除所列两份生产文件外未变。
- 完整 CSI/视频/照片/像素增强回归本轮未重跑，保留上轮已记录证据及未变源码校验，不把历史测试称为本轮重跑。

以下为最终交付记录。功能仿真不代表实际蜂鸣声或上板通过。

<!-- FINAL_DELIVERY_BEGIN -->
- 独立构建记录：`batch_buzzer_r1_build_20261103_085821.json`，2026-11-03T08:58:21.3677092+08:00 开始，2026-11-03T09:43:58.7817378+08:00 完成，继承前一版官方 TimingMedium 实现设置；原 SDC 未修改。
- 最终 Setup +0.102 ns、Hold +0.020 ns，TNS 与违例端点均为 0，Routing DRC 通过，无实现 ERROR/FATAL。
- STA覆盖 94.68%；Slice 20255/21216、LUT6 19780/21216、ERAM80/108、DSP22/40。时序余量小、资源占用高和既有约束/接口告警仍是限制，不称为零告警或现场验证。
- 无新增 critical warning。六条普通告警文本差异已审查：五条仅源行号移动，一条为布局前资源估计；详细记录在 `warning_comparison.json`。
- 只读加载本轮路由数据库核验：`O_buzzer_syn_4` 是已放置/固定的 LVCMOS33 输出PAD，LOCATION=C12、MODE=OUT、PULLMODE=PULLUP，doq[0]接 `O_buzzer_dup_3`，opad接顶层 `O_buzzer`。日志 `buzzer_physical_connection.log` 保留；检查未回写路由数据库。
- 归档：`release_archive/batch_buzzer_20261103/camera_to_dsi_display_batch_buzzer.bit`，1789539 字节，SHA256 `D3AF844DBED3F82F84FC64D927FD7EA594D2E5E762605F56ABC2794FDEB7BDBA`。
- 2026-11-03T09:49:21.7662881+08:00 已同步默认 `syn_1/phy_1`；覆盖前默认 bit SHA256为 `07D459B95457A11C4EA6422F9A455E2A283EF494A9B09699B2580D6910A35E7E`，完整保留于 `syn_1_before_batch_buzzer_20261103_094921` / `phy_1_before_batch_buzzer_20261103_094921`。
- 独立核验入口同时检查构建源清单、ROM、216项生产输入、65项根工程保护、测试/日志哈希、实现报告、引脚及默认Runs身份。归档/独立run/默认bit一致性以最终 `verification.json` 为准。
- 未烧录或上板试听，未提交推送。功能仿真和TD通过不能代替实际声响、音量及高速计数实测。
<!-- FINAL_DELIVERY_END -->
