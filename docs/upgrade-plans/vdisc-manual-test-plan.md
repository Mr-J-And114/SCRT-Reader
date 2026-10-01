# Vdisc 完整手动测试方案

日期：2026-09-30。依据当前代码与联调包编写；未运行 Godot，以下“预期”不代表已通过。

## 1. 测试准备

- 用两个专门的测试账号 A、B，避免改动日常试玩进度。可从登录界面注册；不要删除原有存档。
- 开机时可按 F12 跳过。若出现教程通讯，先结束当前通讯，再在普通终端执行本方案。
- 每条命令单独输入；带 `<编号>` 的位置用 scan 实际显示的数字替换。若个人盘已经加载，跳过重复的 load；需要换盘时先 eject。
- 查看器打开后，先按 Q/Esc 返回再输入下一条命令。邮件正文退出后会回到收件箱，需再退出一次才回到终端。
- 领取的盘必须在 scan 中标有 `[个人任务盘]`。同名的共用源盘仍会保留，不能用它上交任务或编辑任务副本。
- 任务 ID 是 `demo_site19`；邮件 ID 是 `MTEST-VDISC`；磁盘故事 ID 是 `site19_incident_0117_2`。这三种 ID 不可互换。

## 2. 当前功能与命令总览

| 场景 | 操作 | 当前作用 |
|---|---|---|
| 查看任务 | `vdisc` | 桌面显示任务列表、状态及归档数量；盘内显示进度、缺口与上交号码 |
| 查看磁盘 | `scan` | 列出可加载磁盘，个人任务副本有专门标记 |
| 加载个人副本 | `load <编号>` | 加载所选盘，恢复该玩家的进度和文件修改 |
| 命令领取 | `download demo_site19` | 弹出字符下载窗口；已有文件时询问是否重下载 |
| 邮件领取 | 邮件正文点击附件链接 | 保持邮件打开，在其上方显示下载窗口 |
| 邮件领取备用 | `mail download MTEST-VDISC` | 与点击附件共用同一领取流程，也支持邮件编号 |
| modem 领取 | `dial 9900-0002` | 通过现有 modem 下载流程领取，保留其原有界面 |
| 文件探索 | `ls`、`cd <目录>`、`open <文件>`、`explore` | 已读可见且有权限的文件计入任务探索度 |
| 复制文件 | `cp <源文件> <目标路径>` | 仅修改个人任务盘；目标不能已存在 |
| 移动文件 | `mv <源文件> <目标路径>` | 同上，已读标记随移动更新 |
| 删除文件 | `rm <文件>` | 从工作副本删除；不删除共用源包 |
| 创建文件 | `mkfile <路径> [内容]` | 目标需不存在，父目录需可写；不支持覆盖编辑 |
| 存盘/弹出 | `save`、`eject` | 保存玩家进度；弹出也会自动保存 |
| 上交 | `submit 1001-0002` | 交给任务发布方，先检查要求；成功后归档并退出该盘 |
| 错误接收方 | `submit 1001-0001` | 联调任务中 Ava 会没收磁盘，不受达标要求限制 |
| 查号码 | `phonebook` | 查看当前注册的联系人；联调上交以 vdisc 显示的号码为准 |
| 联调列表 | `debug 114514 vdisc list` | 查看原始任务状态 |
| 投递测试邮件 | `debug 114514 vdisc mail` | 投递/刷新测试邮件 |
| 直接联调领取 | `debug 114514 vdisc give demo_site19` | 与普通 download 共用流程 |
| 检查达标 | `debug 114514 vdisc check` | 显示当前盘是否达标及具体缺口 |
| 测试后台提示 | `debug 114514 vdisc notice` | 5 秒后产生普通终端提示，检查全屏隔离 |
| 查看结算标记 | `debug 114514 get_flag demo_site19_done` | 成功上交后应为 1 |
| 查看修改上交标记 | `debug 114514 get_flag demo_site19_fake_pass` | 有文件修改的成功上交应为 1 |
| 查看绩效 | `perf` | 对照上交/没收前后的分数变化 |

### 下载窗口操作

- 下载中：阻止底层终端输入，等待传输与校验结束。
- 重下载确认：点击“重新下载”或按 Y 确认；点击“保留”或按 N/Esc 取消。Enter 默认保留。
- 完成/失败/取消：点击“返回”或按 Enter/Esc 返回原界面。
- 外框复用 `FileSystem.build_box()` 的 `╔═╗ / ║ / ╚═╝` 字符；进度使用 Typewriter 的 30 格 `█` 规则，仍经过 CRT shader。
- 普通终端输出在全屏界面活动时暂存，退出所有覆盖界面后显示；音视频自身状态继续由其现有界面显示。

### 任务条件与状态

本联调任务要求：探索比例至少 20%，存在 `/reports/summary.txt` 文件，可见且有权限的文件至少 8 个，总数据量至少 1 KB。满足探索比例不等于满足全部条件，请以 vdisc/check 提示为准。

| 原始状态 | 含义 | 下一步 |
|---|---|---|
| `not_started` | 未领取 | 点击附件或 download |
| `downloaded` | 已领取、尚未结算 | scan → load → 探索 → submit |
| `submitted` | 已上交 | 查看归档；禁止再次领取，避免重复奖励 |
| `confiscated` | 已没收 | 可重新领取，以新副本开始 |

## 3. 按顺序测试

每项记录“通过 / 问题 / 未测”，有问题时标明测试编号并截图。

### T01 · 新账号的入口与提示（账号 A）

依次输入：

```text
vdisc
help
debug 114514 vdisc list
debug 114514 vdisc mail
mail
```

点击“Vdisc 联调附件”。预期：看得到下载链接、备用命令；任务初始未领取。重点反馈是否能理解任务 ID、邮件 ID 和磁盘编号。

### T02 · 邮件下载与字符窗口（账号 A）

点击下载链接，等待完成，按 Enter 返回。

预期：字符外框对齐、进度条与系统相同，中文、百分比清楚；CRT 扫描线/颜色作用于窗口；返回后仍在原邮件，邮件没有被普通下载提示或命令覆盖。按键不会写入后台终端。

再退出邮件和收件箱，输入 scan。预期：仅新增一张 `[个人任务盘]`；终端可能显示暂存的下载结果，这是退出后的正常记录。

### T03 · 全屏后台输出隔离（先测邮件，再测其他界面）

普通终端输入：

```text
debug 114514 vdisc notice
mail
```

保持收件箱或正文打开超过 5 秒。预期：全屏界面不出现普通提示，滚动和点击正常；退出正文回到收件箱时仍不显示后台提示，退出收件箱后才在终端显示一次。

加载个人盘后，分别重复 notice 测试，紧接着打开：

```text
open /notice.txt
explore
open /city-sun.jpg
env view
```

每次只打开一种界面，等待提示到达后关闭。已有 article/chat/two-page 文档也按同一方法检查。重点记录：文本是否穿透、关闭后是否缺失/重复、鼠标是否误操作底层终端、退出后焦点是否恢复。

### T04 · 已有副本时取消重下载（账号 A）

```text
load <个人任务盘编号>
open /notice.txt
```

退出文件查看器，记下 vdisc 的已读进度。然后打开测试邮件，再次点击附件。

先选“保留”，再重复一次按 Esc 取消。预期：不会开始传输；原文件、任务状态、已读进度保留。取消不显示 100% 下载成功。

### T05 · 确认重下载（账号 A）

在同一邮件再次点击附件，选择“重新下载”，等待完成。退出邮件后：

```text
scan
load <个人任务盘编号>
vdisc
debug 114514 vdisc check
```

预期：个人副本只保留一份；原盘若正在使用会弹出；重新加载后探索进度从零开始。状态为 downloaded，旧文件修改被清除。任务总进度提示与扫描列表及时刷新。

### T06 · 达标与正常上交（账号 A）

先输入 `submit 1001-0002`，预期：未达标时列出缺口，个人盘仍可继续使用。

逐个打开以下文件，每次退出查看器后再开下一份：

```text
open /notice.txt
open /maintenance_notes.txt
open /reports/summary.txt
open /reports/scp_173.txt
open /reports/final_report.txt
vdisc
debug 114514 vdisc check
```

若仍不到 20%，用 ls/explore 找到更多有权限文件，继续阅读，直到 check 通过。

然后：

```text
perf
submit 1001-0002
vdisc
scan
debug 114514 get_flag demo_site19_done
perf
download demo_site19
```

预期：成功上交，个人盘退出并归档；个人任务副本不再可加载，共用源盘仍在；done=1；本次 side 分增加 1；再次领取被拒绝，不重复奖励。

### T07 · 账号隔离与 modem 入口（账号 B）

注销 A，从登录界面注册/登录 B；输入 vdisc。

预期：B 的任务仍未领取，不继承 A 的上交状态。然后：

```text
dial 9900-0002
scan
load <个人任务盘编号>
vdisc
```

预期：modem 下载正常；新副本属于 B，状态 downloaded。A 的归档和分数不变。

说明：modem 保留自身下载界面，本轮“重复领取确认”覆盖的是普通 download 和邮件入口；重复拨号遇到已存在盘仍会提示已有副本，此处请记录体验，暂不视为确认窗口缺失故障。

### T08 · 未知号码与没收（账号 B）

```text
submit 0000-0000
perf
submit 1001-0001
vdisc
scan
perf
```

预期：未知号码不收走磁盘；Ava 没收后个人盘退出，状态 confiscated，归档数量增加。联调配置当前将该分支设为 main 加 1，这只是当前配置，不代表最终剧情奖惩已经定稿，请记录是否合理。

重新输入：

```text
download demo_site19
scan
load <个人任务盘编号>
vdisc
```

预期：可以领取新盘；探索进度归零，没收归档仍保留。

### T09 · 文件操作与错误提示（账号 B）

```text
mkfile /vdisc_note.txt 第一次测试记录
open /vdisc_note.txt
cp /notice.txt /vdisc_copy.txt
mv /vdisc_copy.txt /vdisc_moved.txt
open /vdisc_moved.txt
rm /vdisc_moved.txt
ls /
```

预期：创建/复制/移动/删除生效，已读标记随移动/删除更新；内容正确，共用源盘不改变。

再测试：

```text
cp /notice.txt /vdisc_note.txt
rm /not_exists.txt
mkfile /not_exists_dir/new.txt 记录
open /classified/overseer_memo.txt
```

预期：已有目标、无效路径、无权限操作被拒绝；不覆盖原有文件。记录当前错误提示是否能告诉你具体原因。

### T10 · 保存与重新启动（账号 B）

```text
save
eject
scan
load <个人任务盘编号>
open /vdisc_note.txt
vdisc
```

预期：新增文本和已读进度可恢复。再正常关闭游戏、重新启动、登录 B、加载个人副本重复检查。随后登录 A，预期 A 的 submitted 状态和归档仍存在。

### T11 · 缺失必需文件（回到账号 B）

重新登录 B 后，先 scan 并 load 个人任务盘；再正常阅读至 check 通过，随后执行：

```text
cp /reports/summary.txt /summary_backup.txt
rm /reports/summary.txt
vdisc
submit 1001-0002
```

预期：即使探索比例达标，也因缺少必需文件被拒绝；任务盘仍保留。然后：

```text
cp /summary_backup.txt /reports/summary.txt
rm /summary_backup.txt
vdisc
debug 114514 vdisc check
```

预期：缺少必需文件的提示消失。恢复文件可能未读，按 vdisc 提示补足探索即可。

### T12 · 修改后的上交与结算（账号 B，最后执行）

check 达标后：

```text
perf
submit 1001-0002
vdisc
debug 114514 get_flag demo_site19_done
debug 114514 get_flag demo_site19_fake_pass
perf
```

预期：成功归档，done=1，fake_pass=1，side 加 1。当前 fake_pass 采用“只要有文件修改即标记”的简易规则；请评价是否需要只将关键文件修改视为蒙混。

### T13 · 无效参数与非任务盘

在桌面或共用源盘内测试，注意只加载无 `[个人任务盘]` 标记的原盘：

```text
download not_exists_task
mail download not_exists_mail
submit
cp
mkfile
submit 1001-0002
mkfile /source_should_not_change.txt 测试
```

预期：未知 ID/缺参数有提示；未加载个人任务盘时不能上交；共用源盘不能使用任务编辑命令。共用源包实际文件不应改变。

### T14 · 下载失败（需要开发者配合准备失效源）

当前联调任务走本地源，不用改玩家文件来制造失败。若需测试：由开发者临时添加失效 URL、缺失源包、损坏 ZIP 或 story.id 不符的专用测试任务；不要直接破坏现有源包。

分别检查：失败信息可读、不会显示 100%、窗口可返回、旧副本及旧进度不丢失，错误任务不出现在 scan。HTTP 未知总大小不应伪造百分比；请求约 30 秒后超时返回。

本项没有专用坏包配置，当前可标“待准备”。

## 4. 建议反馈格式

```text
测试编号：T02
结果：问题 / 通过 / 未测
所在界面与账号：邮件正文，账号 A
操作：点击附件 → 下载完成 → 按 Enter
实际：……
期望：……
截图或录像：……
```

## 5. 测完后优先讨论的命令和提示

1. 桌面 vdisc 的任务状态目前仍有英文原始值，是否统一改中文，并直接展示领取命令？
2. 盘内 vdisc 已有缺口和 submit 号码，是否还需要普通 `vdisc check`，让玩家不用 debug 查看判定？
3. cp/mv/rm/mkfile 的错误提示目前偏笼统，是否逐项区分权限不足、源不存在、目标已存在、父目录不存在？
4. 成功上交目前主要给归档数量，是否需要展示标题、接收方、日期、正常/修改上交、结算分数？
5. 邮件、download、modem 三个入口要不要统一重复领取确认与提示？
6. 重下载的探索/文件修改重置方式，以及 fake_pass 与没收奖惩，是否符合试玩期望？

本轮保留现有命令语法，只补足界面隔离、字符下载窗口、扫描中个人任务副本标记和后台提示测试入口。上述命令扩展与剧情奖惩待体验反馈后再定。
