# 现场MAN反馈后的开机曝光修正

工程：`D:/fpgashare/fpgashare (4)/fpgashare`，入口`td_project/camera_to_dsi_display.al`。

## 现场反馈与三处缺口

用户反馈烧录后为 **MAN，EXP/GAIN不变化**。这表明板上当前没有进入AUTO；此前26项仿真和20:52独立构建不能替代该现场事实。

1. **此前默认入口未同步。** 检查时`.al`激活`syn_1/phy_1`，默认bit时间为2026-11-01 19:55:47，SHA256为`F3600698449176AB27E3ED4FE8F7072866A488D92A2B5306863D1F05C163E37A`，不是20:52交付版`CB1BB429...`。不能据此断定用户实际选择了哪个文件，但默认入口确实未更新。本轮已在全部验证通过后，于21:41:08保留旧目录并同步默认run，详见下方交付记录。
2. **上电按键误接管MAN。** 原菜单把初始化读到的KEY1/KEY2低电平也当成手动按下。旧源码负对照复现`auto=0 exp=2212`。现在先等待相机键消抖后的全部释放，再允许新按下接管MAN；顶层同时屏蔽未解锁的原始键。真正的新按键和菜单内显式EXP/GAIN编辑仍可手动接管。
3. **前端按空闲时钟计行导致截帧。** 生产`image_correction.v`的8位`cnt==10`在长消隐中每256拍重复计行。600拍行间隔下第241行开始丢失；完整CSI每帧原始230400拍，旧校正器仅输出57600拍。独立测光要求完整帧，因此AUTO也可能一直没有有效测量。现保持原一拍数据延迟，转发`uial2axis`的真实有效、帧头和行尾，不再猜测行号。

第2、3项为已复现的源码缺陷，不能无依据地认定为现场MAN的唯一原因。旧26项测试绕过了CSI、流转换和该校正模块，本轮补齐该测试缺口。

## 自动调节和收敛

上电直接AUTO，无需先手调。继续使用AWB前独立空间测光，黑帧/饱和帧可驱动调整，不完整帧无效。连续4个有效观测在目标区间同一侧才调整；实际I2C写完后丢弃2包有效测光，等待N+2生效。

**目标为测光亮度176～216，连续8个完整有效观测达标才LOCK。** 锁后停止自动写曝光/增益；数值不变、未完成配置和无效图像不能冒充收敛。重新适应光照时显式MAN→AUTO或复位。AWB保持自身运行规则，不随AE锁定冻结。

该区间用于当前空间测光统计，不是任意背景/照明下语义正确的保证；本轮不改识别、帧差、速度预测、AWB、电机及计数算法。

## 版本与板上可见状态

新增两行紧凑状态，保留图标、计数和已确认目标框/标签：

```text
AE2:AUTO Y:C8 V1
I:11 W:03 S:7/8
```

- `AE2`为本轮独有版本标识，不依赖有效测光才显示；AUTO/MAN/LOCK显示实际状态。
- `Y`为最近测光值（十六进制），176～216对应`B0～D8`；`V1/V0`表示最近测光完整有效/无效。
- `I:11`表示初始化和曝光配置均完成，不等于寄存器读回。
- `W`为已完成的运行时参数写入次数（十六进制），不包括初始化。
- `S`为当前连续达标数；LOCK时绿色显示`S:8/8`。

## 验证与交付记录

新闭环为真实`CSI解包→RAW10解包→uial2axis→image_correction→720p ISP→测光→AE→实际I2C→N+2合成图像反馈`。MIPI模拟接收器、真实光学响应和厂商RAM不属于实物验证覆盖范围。

- `run_image_correction_regression.ps1`：短/600/1024拍行间隔，三帧720p，逐拍检查数据与一拍标记延迟。
- `run_ae_raw_isp.ps1 -Tops tb_ae_csi_system`：每帧检查原始/校正230400拍，收敛后改变光照再检查12帧不写入。
- `run_ae_once_regression.ps1 -Tops tb_ae_boot_keys,tb_ae_live_status,tb_ae_live_status_rd2`：启动按键、手动接管、版本/诊断行及两种显示读延迟。
- 重跑实际I2C/NACK、暗亮边界、AWB、8种视频模式、Sobel/EDGE与DDR帧尾、多目标及延迟。
- 三个旧源码负对照必须出现功能断言失败，不以编译错误冒充反例。

28/28项定向功能顶层全部通过，三个旧源码功能负对照均按预期失败。完整CSI闭环共47帧：首个有效测光248，GAIN自动由112经96、80、64降至48；第28～35帧测光持续200，第35帧LOCK。随后合成光照降低，测光变为24，再检查12帧，EXP保持2244、GAIN保持48，无新增参数写入请求。总计5组曝光参数I2C序列（包括初始化后的首组），使用ACK解码的寄存器和N+2合成图像反馈，不能当作实物光学结果。

最终构建记录`td_project/camera_to_dsi_display_Runs/ae_field_r2_build_20261101_211446.json`，2026-11-01 21:14:46～21:38:58完成。r1为诊断显示修正前的已取消构建，不交付。

| 最终项目 | 结果 |
| --- | --- |
| Setup / Hold WNS | +0.106 / +0.020 ns |
| Setup / Hold TNS及违例端点 | 均0 |
| Slice / LUT6 | 19927 / 19519，容量均21216 |
| ERAM / DSP | 76/108、20/40 |
| STA覆盖率 | 94.76%，原SDC及既有例外保留 |
| Routing DRC | 完成，无实现ERROR/FATAL；无多驱动、无异常时序路径、边界检查通过 |
| 生产输入 | 62项哈希与构建时一致，实际源清单和SDC路径一致 |

现有局部时钟、非时钟负载、估算利用率等WARNING/CRITICAL-WARNING保留，分类计数见验证JSON；不能将上述结果描述成全覆盖、无告警的物理签核。

## 本轮固件及默认入口

- 归档：`release_archive/ae_field_boot_20261101/camera_to_dsi_display_ae_field_boot.bit`。
- 默认：`td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。
- 原始run：`td_project/camera_to_dsi_display_Runs/phy_ae_field_r2_20261101_211446/camera_to_dsi_display.bit`。
- 三处均为1,789,539字节，SHA256：`B9FD637836B9181146C22AA0193AB575DBAC9F990BD353170956EC6F684A0CBE`。
- `.al`继续激活`syn_1/phy_1`，其综合数据库、最终报告及bit已同步；默认物理设置的父run为`../syn_1`，不是仅替换一个bit。
- 旧默认目录保留为`syn_1_before_ae_field_20261101_214108`及`phy_1_before_ae_field_20261101_214108`，未删除旧结果。
- `sim/ae_field_20261101_validation/default_run_promotion.json`记录同步前后路径和哈希，归档中也有副本。
- 验证`sim/ae_field_20261101_validation/verification.json`状态为`verified_no_board_test`，`defaultRun.verified=true`、`issues=[]`；归档包含证据、报告、SHA256SUMS及上板检查README。

上板应先确认独有标识`AE2:AUTO`，然后观察有效测光、运行时写入及最终`AE2:LOCK / S:8/8`。若初始亮度已在目标区间，不要求为了演示而强制改变EXP/GAIN；仍须满足连续8次有效达标。无`AE2`时先核对固件和烧录过程。

**尚未上板。** 不用合成图像仿真或当前约束下TD结果声称现场已通过；未提交或推送Git。
