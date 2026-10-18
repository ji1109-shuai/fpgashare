# 两人 Git / GitHub 协作操作指南

适用仓库：<https://github.com/ji1109-shuai/fpgashare>。仓库为私有，队友接受邀请后才能访问。

## 1. 我们采用什么规则

**两个人都在各自的功能分支开发，通过 Pull Request（PR，合并请求）把改动合入 `main`。** 仓库拥有者也遵守同样流程。

```text
main：双方共享的开发基线
  ├─ codex/owner-wb-diagnosis      例如：完善白平衡诊断
  └─ codex/teammate-shape-filter   例如：调整形状识别
          ↓ 提交、推送自己的分支
          ↓ 在 GitHub 创建 PR，由另一人检查
         合入 main，双方同步
```

- 每人电脑上各克隆一份仓库，使用自己的 GitHub 账号；不要在同一个共享文件夹里同时运行 Git 或 TD。
- 一个任务一个分支。分支名用英文、数字和短横线，建议带成员或任务名，避免同名。
- `main` 用于接收经过检查的改动；是否已通过功能仿真、物理时序和上板验证，需要分别注明。合入 `main` 不等于已经上板成功。
- 开始新任务前，先同步 `main`，再从更新后的 `main` 创建分支。不要从上一个未合并的功能分支随手创建下一个分支。
- 分支能够隔离未完成的修改，但不会消除冲突。同一个文件尤其是同一段代码，仍需要提前协调。
- 不强制推送、不重写公共历史、不用 `reset --hard` 或 `clean` 清理自己不清楚的内容。

## 2. 仓库拥有者：邀请队友

1. 在 GitHub 打开仓库，进入 **Settings → Collaborators**。若设置页采用不同分组，查找 **Access / Collaborators and teams**。
2. 点击 **Add people**，输入队友的 GitHub 用户名并核对账号，发送邀请。
3. 队友登录自己的账号并接受邀请，再访问仓库地址确认能看到文件。

如果仓库套餐支持分支保护或规则集，建议保护 `main`：要求通过 PR 合并、要求另一人批准，并禁止强制推送和删除。若私有仓库当前套餐不提供这些功能，先按本文人工执行流程，不影响协作开始。

不共享密码、验证码、访问令牌或 SSH 私钥。每个人完成自己的登录授权。

## 3. 队友首次准备：GitHub Desktop 路线

建议两人先统一使用 GitHub Desktop，命令行可作为后面的备用方式。

1. 安装 GitHub Desktop，登录自己的 GitHub 账号，配置提交者姓名和邮箱。邮箱可以使用 GitHub 提供的隐私邮箱。
2. 接受仓库邀请后，选择 **File → Clone repository**。在列表中选择 `ji1109-shuai/fpgashare`，或者在 URL 页填入仓库地址。
3. 选择本机工作路径，例如 `D:\work\fpgashare`，点击 **Clone**。已有仓库的拥有者直接添加现有本地仓库，不必重复克隆。
4. 确认 **Current Repository** 是 `fpgashare`，**Current Branch** 是 `main`。
5. 阅读根目录 `README.md`、`AGENTS.md`、`HANDOFF.md` 和 `sim/README.md`。如果这些文件尚未出现在远程，需要先由拥有者把交接资料提交、推送，队友再同步。
6. 用 TD 打开 `td_project/camera_to_dsi_display.al`。确认实际源码路径指向这次克隆的仓库。

保持 `td_project` 和 `user_source` 的同级目录结构。换电脑后，`.al` 的工程根路径可能需要本地调整；不要只为了记录自己的盘符，把队友的路径反复改进仓库。若 TD 自动修改工程文件，应检查差异，确认哪些是必要配置修改，哪些只是本机状态。

当前硬件问题、白平衡状态与测试边界以 `HANDOFF.md` 为准，不能把历史文档里的旧结论直接当成当前结果。

## 4. 每次开发：两个人都照这个流程

### 第一步：先说清楚本次修改范围

例如：“我改 `awb.v` 的参考采样，你先做形状分类；顶层和 ISP 接口有变化时先沟通。”

以下文件经常被多个功能共同影响，修改前尤其需要协调：

- `user_source/hdl_source/design_top_wrapper.v`
- `user_source/hdl_source/isp/isp_top.v`
- `user_source/hdl_source/img_proj.v`
- `user_source/hdl_source/hdmi_mixer.v`
- `td_project/camera_to_dsi_display.al` 和约束文件

每人使用自己的功能分支；不要两个人同时往同一个功能分支推送。

### 第二步：同步主分支，再创建功能分支

1. 先检查 **Changes**，确保没有遗留的未保存工作。若有，先在原任务分支保存为提交；不要为了切分支而丢弃改动。
2. 切换 **Current Branch → main**。
3. 点击 **Fetch origin**；如果出现 **Pull origin**，再点击它，下载并更新本地 `main`。Fetch 只是获取远程信息，Pull 才更新当前分支。
4. 选择 **Branch → New branch**，例如 `codex/teammate-shape-filter`，确认基于更新后的 `main` 创建。
5. 确认顶部显示自己的功能分支后再编辑代码。

### 第三步：修改、检查和验证

1. 只修改本次任务需要的文件。
2. 在 Desktop 的 **Changes** 中逐个检查差异，尤其关注 TD 自动生成的工程路径、IP 配置和调试配置变化。
3. 运行与改动相关的功能仿真，方法见 `sim/README.md`。
4. 如果涉及实际硬件行为，由负责上板的人用对应提交进行 TD 综合、布局布线、时序检查、bit 生成和下载，并记录结果。Codex 不自行运行 TD 构建。

功能仿真通过、物理时序通过、上板通过是三个不同结果。没有做的项目写“未验证”，不要混写成“全部通过”。

### 第四步：提交到本地，再推送自己的分支

1. 在 **Changes** 中只勾选本次任务需要的文件。
2. 填写说明，例如 `fix: 修正无效白平衡参考的补偿回退`。不要只写“修改”或“更新”。
3. 点击 **Commit to 当前分支**。此时只是保存在自己电脑的 Git 历史里。
4. 首次上传该分支点击 **Publish branch**；以后点击 **Push origin**。推送后队友才能从 GitHub 获取。

一个分支可以包含多次提交。未完成的工作也可以推送到自己的分支，创建 Draft PR 并注明未完成事项。

### 第五步：创建 PR，另一人检查后合并

1. 在 GitHub 创建 Pull Request，确认 **base: main**、**compare: 自己的功能分支**。
2. 写清楚：解决什么问题、改动范围、验证结果，以及还需要谁做什么。
3. 请另一人在 **Files changed** 中查看差异。Review 的 **Approve** 表示批准，尚未合并；点击合并按钮才会更新 `main`。
4. 有修改意见时，继续在原功能分支修改、提交、推送，PR 会自动更新，不用重新创建 PR。
5. 无冲突且检查完成后合并。两人初期可统一使用 **Squash and merge**，把一个任务整理为 `main` 上的一个提交，方便追溯。

PR 描述可使用：

```text
问题与改动：
调整了什么，预期看到什么行为。

验证：
- 功能仿真：测试名称及结果 / 未运行及原因
- TD 时序：具体结果 / 尚未验证
- 上板：现象、条件 / 尚未验证

待确认：
需要进一步采集的数据或已知限制。
```

### 第六步：合并后双方同步

1. 确认工作区没有未保存的修改，切回 `main`。
2. **Fetch origin → Pull origin**，获取合并结果。
3. 下一个任务从最新 `main` 新建分支。Squash 合并后不要继续使用原分支承接新任务。
4. 确认 PR 已合并、原分支没有独有的未提交或未推送工作后，可以删除该任务分支。

如果另一个功能分支仍在开发，需要把最新 `main` 合入该分支。Desktop 中切到自己的功能分支，再使用 **Branch → Merge into current branch** 并选择 `origin/main`；不同版本入口可能略有差异，也可以使用下面的命令行方式。

## 5. 命令行备用流程（PowerShell）

下面的路径和分支名是示例，按自己的实际情况替换。逐步执行；某一步报错时先处理，不要继续整段粘贴。

首次克隆，先进入已经存在的父目录：

```powershell
Set-Location D:\work
git clone https://github.com/ji1109-shuai/fpgashare.git
Set-Location .\fpgashare
```

每次新任务：先确认 `git status` 没有未保存改动，再同步和开分支。

```powershell
git status
git switch main
git pull --ff-only origin main
git switch -c codex/teammate-shape-filter
```

修改、验证后，查看差异，只暂存本次需要的文件。下面假设本次只改了 `img_proj.v`；实际有其他必要文件时逐个加入。

```powershell
git diff
git add -- user_source/hdl_source/img_proj.v
git diff --cached
git commit -m "fix: 改善零件形状判断"
git push -u origin codex/teammate-shape-filter
```

随后去 GitHub 创建 PR。以后在同一分支继续提交后，使用 `git push`。

正在开发的功能分支需要获取队友已经合入 `main` 的修改时，先保存自己的工作，确认当前分支是自己的功能分支：

```powershell
git status
git branch --show-current
git fetch origin
git merge origin/main
```

有冲突先按下一节处理；合并完成并验证后再 `git push`。两人初期统一使用 merge 更新功能分支，避免 rebase 后需要强制推送。

PR 合并后，工作区干净时同步本地 `main`：

```powershell
git switch main
git pull --ff-only origin main
```

若 `--ff-only` 失败，通常表示本地 `main` 有额外提交或历史出现分叉；保留现场，先检查，不要改成强制覆盖。

## 6. 冲突和常见问题

### 出现合并冲突

1. 用 `git status` 查看冲突文件，或在 Desktop 中查看冲突提示。
2. 打开文件，检查 `<<<<<<<`、`=======`、`>>>>>>>` 两侧的修改，结合双方意图整理最终内容，删除冲突标记。不要一律选择“保留我的”或“保留对方的”。
3. `.al`、约束或 IP 配置发生冲突时，由熟悉该配置的人处理，必要时在 TD 中重新打开核对。不要直接拼接配置。
4. 处理后检查差异、暂存已解决文件、完成合并提交，再做相关验证并推送。Desktop 可按冲突解决提示完成这些操作。
5. 不确定时保留现场，把冲突文件和报错交给另一人或 Codex 分析。若决定取消尚未完成的 merge，可在确认没有需要保留的合并期间新增修改后使用 `git merge --abort`。

### Push 被拒绝

先确认当前分支和报错原因。身份验证失败、没有权限、远程分支有更新是不同问题。若远程同名功能分支有新提交，先 `git fetch origin`，检查提交记录并协商后合并；不要直接强制推送。

### 切分支时提示有未提交文件

回到原任务分支保存成提交，或用 Desktop 的临时保存功能妥善保存，再切分支。不要点击丢弃全部更改来消除提示。切换后核对修改归属，避免把任务 A 的改动带进任务 B。

### 不小心在 main 上写了代码

先保留工作。如果尚未提交，通常可以直接新建功能分支，把改动带过去；若已在本地 `main` 提交、或已经推送，需要先查看历史再处理。不要自行重置或覆盖远程 `main`。

## 7. 本 FPGA 工程哪些文件要提交

| 文件 | 处理方式 |
| --- | --- |
| RTL、仿真测试与运行脚本 | 提交与任务相关的修改 |
| `.al` 工程配置、`.sdc` 时序约束、`.adc` 引脚约束 | 必要修改应提交；核对路径、文件列表和配置差异 |
| IP 配置及工程依赖的生成 HDL | 属于工程资产；改变 IP 时一起核对并提交必要文件 |
| `logo_idx.hex`、`logo_pal.hex` | 保留，是安路图标资源 |
| ChipWatcher 配置 | 需要共享的探针/实例调整应说明；不要把个人实验配置无意覆盖给所有人 |
| 文档和精选调试证据 | 提交有解释、能追溯版本的必要资料 |
| TD Runs、仿真缓存、bit、完整波形、临时日志、锁文件 | 不提交源码仓库；遵循 `.gitignore` |

`.gitignore` 只帮助排除文件，不会自动取消对已被 Git 跟踪文件的跟踪。看到不确定的文件，先检查用途；不要按“工具生成”一概删除，更不要用 `git add -f` 绕过忽略规则上传缓存。

保存上板记录时，注明实际用于构建的提交号、工作区是否还有未提交修改、TD 版本、时序结果、EXP/GAIN、开关状态及现场现象。需要传递 bit 时另行共享，并关联这些记录，不放进源码提交。

## 8. 每次开发前后的简短检查

- 开始：仓库正确、工作区状态清楚、`main` 已同步、已创建自己的功能分支、双方修改范围已协调。
- 提交：差异已检查、没有混入缓存或个人盘符、必要文件齐全、验证结果写清楚。
- 合并：PR 方向正确、另一人已检查、冲突已解决、未完成验证已明确标注。
- 结束：代码已推送、PR 状态清楚、下一步及待测事项已记录。
