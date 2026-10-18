# 2026-10-17 ChipWatcher 时序违例定位

## 结论

本次布局布线报告的负裕量为 -0.027 ns，来自 ChipWatcher 自动插入的调试 hub 复位 recovery 路径。

- 起点：`debug_hub_top/U_tap/rst_reg_syn_3.clk`
- 终点：`debug_hub_top/slave_0_rst_sync2_reg_syn_3.asr`
- 约束：`set_max_delay ... -datapath_only 1`
- 预算：1.000 ns；实际：1.027 ns。
- 单元延迟 0.126 ns，布线延迟 0.901 ns，最大扇出 359，逻辑级数 0。
- 原始证据：`before/camera_to_dsi_display_exception.timing` 第 1847-1919 行附近。

同次普通时序报告：摄像头域 setup +0.111 ns，HDMI 域 setup +0.123 ns，DDR 用户域 setup +2.073 ns；普通域内时序未报告违例。裕量较小，重新布局布线后仍须检查全部时序。

## TD 操作：暂时禁用旧调试核

不改识别算法；不放宽约束。保存的两个实例均为 `ipgen="false"`，来自 Mark Debug。

1. 在 TD 打开当前工程，双击 Hierarchy 下的 ChipWatcher，进入配置界面（不是 Watch 波形采集界面）。若不可打开，先完成 Read Design / Optimize Gate。
2. 进入 **Instance View**，在左侧实例列表分别选中 `auto_created_cwc1` 和 `auto_created_cwc2`，右键 **Disable**。两个实例都应置灰。
3. 点击保存并关闭配置窗口。保留信号列表和参数，不执行 Clear Up ChipWatcher。
4. 为避免旧网表残留，从综合阶段重新运行完整流程（包括 Read Design、Optimize Gate、Opt Phy / 布局布线）。若工具重置流程后自动重新启用实例，在 Optimize Gate 完成后暂停，再确认两项仍为 Disable，保存后继续。
5. 查看新的最终时序报告：全局 SWNS / HWNS 均应不小于 0，违例端点为 0；本次 debug_hub 复位违例应消失。不要只检查普通时钟汇总，也要检查 exception timing。
6. 时序通过后由用户生成 bit、下载并测试颜色校准及识别效果。

注意：说明书明确指出，全局 **Disable ChipWatcher** 对源码 Mark Debug 插入的实例存在资源释放例外，因此不能仅凭全局菜单变灰判断调试核已移除。请禁用 Instance View 中的两个具体实例，并检查新报告/网表。

需要恢复抓波形时：Instance View 对两个实例选择 Enable，保存并重新编译相应流程；恢复插入调试核后须重新检查时序。

## 参考与备份

- TD 调试指南：`D:/AN_LU/doc/SWUG/SWUG111_Debug_Tools_User_Guide.pdf`，印刷页 28-30（Instance View、Disable、保存）、32-33（全局开关及其例外）。
- `before/` 保存当前 user.cfg 与时序/资源报告；`manifest.json` 记录 SHA256。
- 本次未修改生产 RTL、调试配置或约束，未运行 TD 编译或生成 bit。上述禁用动作需在 TD 中执行，尚未验证禁用后的布局布线结果。
