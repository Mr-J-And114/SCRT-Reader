# 调试模式操作指南

## Vdisc 任务联调（待在 Godot 中验收）

完整的逐项方案、命令总览及反馈模板见 [Vdisc 手动测试方案](upgrade-plans/vdisc-manual-test-plan.md)。新增 debug 114514 vdisc notice 可检查全屏界面是否被后台提示穿透。下载窗口现使用系统字符边框与 30 格字符进度条；完成后 Enter/Esc 返回，重下载确认 Y 同意、N/Esc/Enter 保留。

项目内置 `demo_site19` 联调任务，源包是 `vdisc/test_story_V0.3.2_1.scp`，不参与 Day0 正式剧情。登录后可走以下路径：

```text
debug 114514 vdisc list
debug 114514 vdisc mail
mail
# 打开“Vdisc 联调附件”，点击正文底部“下载 Vdisc 附件”
# 等待下载窗口显示完成，关闭窗口，再退出邮件
scan
load <显示的编号>
vdisc
debug 114514 vdisc check
```

也可用 `download demo_site19` 直接领取，或 `dial 9900-0002` 走模拟 modem。磁盘模式可用 `cp <源> <目标>`、`mv <源> <目标>`、`rm <文件>`、`mkfile <路径> [内容]` 修改个人副本。达到 20% 已读比例、保留 `/reports/summary.txt` 等条件后，用 `submit 1001-0002` 上交。`submit 1001-0001` 会走 Ava 没收分支，再次下载可重新开始。`debug 114514 vdisc check` 显示当前判定缺口。各账号的副本和任务状态相互独立；本流程尚需玩家在编辑器中实测。

邮件中的链接会直接弹出下载窗口，邮件保持打开。也可用 `mail download MTEST-VDISC` 领取同一附件。本地联调盘显示约 1.2 秒的模拟传输；联网盘显示实际接收进度，未知大小时显示等待提示。校验与保存成功后才显示完成；结束后可点“关闭”或按 Esc。重复领取时弹窗询问是否重新下载：选择保留或按 Esc 保留现有磁盘；选择重新下载则在新包校验成功后替换个人副本，重置该盘探索进度、文件修改和任务状态。已加载的同故事磁盘会自动弹出，需重新 load。下载失败保留旧数据。弹窗与终端一起经过 CRT shader，并跟随当前颜色主题。`vdisc` 会显示任务缺口和接收方的 `submit` 命令。

> **激活方式**：在终端输入 `debug 114514` 进入调试模式。
> **隐藏性**：`debug` 命令不在 `help` 列表中显示，输入 `debug` 而非 `debug 114514` 会提示"未知命令"。
> **格式**：所有调试命令格式为 `debug 114514 <子命令> [参数...]`，下文为简洁省略 `debug 114514` 前缀。
> **代码位置**：`scripts/command_handler.gd` 中 `_cmd_debug()`（约第 2464 行起）。

---

## 一、快速测试流程

### A. 从零开始测 Day0 全流程

```
debug 114514 skip_login          # 自动创建 test/test 用户并进桌面
debug 114514 jump_day0           # 触发 Day0 教程
debug 114514 status              # 查看系统总览
# → 正常玩到 d0_qte 选择处，选择后 d0_04 → d0_05 来电响铃
```

### B. 直接测试某个对话

```
debug 114514 skip_login
debug 114514 jump_day0
debug 114514 list_dialogues          # 列出所有对话 ID 及完成状态
debug 114514 trigger d0_meeting_1    # 静默触发会议对话
# 或用来电方式：
debug 114514 trigger_call d0_05:answerable   # 响铃，comm answer 接听
```

### C. 测试拨号分支（ava_report_ok / ava_report_fail）

```
debug 114514 skip_login
debug 114514 jump_day0
debug 114514 complete_env           # 所有环境任务完成 + 提交日报
debug 114514 set_flag d0_welcome_read 1   # 确保欢迎邮件已读标记
# 测成功分支：
debug 114514 trigger_call ava_report_ok   # 或正常 dial 1001-0001
# 测失败分支（任务未完成）：
debug 114514 reset_dlg ava_report_ok       # 清除完成标记
# （此时任务全完成，需手动取消部分任务来测 fail 分支）
```

### D. 重置进度重新测试

```
debug 114514 reset_progress         # 清空对话/选择/标记
debug 114514 reset_flags            # 仅清空标记（恢复初始值）
debug 114514 reset_dlg <id>         # 清除单个对话的完成标记
```

---

## 二、完整命令参考

### 【登录/用户】

| 命令 | 参数 | 说明 |
|---|---|---|
| `skip_login` | — | 自动创建/登录 `test`/`test` 用户并进入桌面（跳过注册流程） |
| `logout` | — | 登出当前用户 |
| `users` | — | 列出所有已注册用户 |
| `deluser` | `<name>` | 删除指定用户 |

### 【剧情/对话】

| 命令 | 参数 | 说明 |
|---|---|---|
| `jump_day0` | — | 触发 Day0 教程流程（需先登录） |
| `reset_progress` | — | 清空所有剧情进度（对话完成记录 + 选择 + 标记） |
| `list_dialogues` | — | 列出所有对话 ID、标题、完成状态（✓/○）、来电模式 |
| `dlg_status` | `<id>` | 查看指定对话的详细状态（标题/完成/可拨号/来电模式/requires_*/next） |
| `trigger` | `<id>` | 静默触发对话（跳过 call_mode，直接播放） |
| `trigger_call` | `<id>[:mode]` | 以来电方式触发对话。mode 默认 `forced`，可指定 `answerable`。例：`trigger_call d0_05:answerable` |
| `complete_dlg` | `<id>` | 标记对话为已完成（不实际播放） |
| `reset_dlg` | `<id>` | 清除对话的完成标记（允许再次触发） |

### 【剧情变量】

| 命令 | 参数 | 说明 |
|---|---|---|
| `set_flag` | `<name> <value>` | 设置剧情标记。value 自动识别类型（int/float/bool/string） |
| `get_flag` | `<name>` | 查看单个标记的值 |
| `list_flags` | — | 列出所有标记及其当前值 |
| `reset_flags` | — | 清空所有标记并恢复为 initial_flags 初始值 |
| `set_choice` | `<id> <value>` | 设置剧情选择（模拟玩家选择） |
| `get_choice` | `<id>` | 查看某个选择的值 |

### 【环境/任务】

| 命令 | 参数 | 说明 |
|---|---|---|
| `complete_env` | — | 标记所有环境任务完成 + 提交日报（一键满足 requires_tasks=all） |
| `complete_task` | `<task_id>` | 标记指定任务完成 |
| `advance_day` | — | 推进一天（env_monitor.advance_day + 任务重置） |
| `set_reading` | `<sensor_id> <value>` | 设置传感器读数值（float） |
| `force_event` | `<event_id>` | 强制启动环境事件 |
| `set_anomaly` | `<anomaly_id> <level>` | 设置异常等级（0-4） |
| `env_status` | — | 环境系统状态总览（天数/时间/天气/任务进度/日报） |

### 【邮件】

| 命令 | 参数 | 说明 |
|---|---|---|
| `deliver` | `<mail_id>` | 投递指定邮件 |
| `clear_mail` | — | 清空收件箱（含已投递记录） |
| `list_mail` | — | 列出当前收件箱邮件（标记 [T]/[G]、是否已读） |

### 【绩效】

| 命令 | 参数 | 说明 |
|---|---|---|
| `perf_add` | `<type> <amount>` | 增加绩效分数。type: `main`/`daily`/`side` |
| `perf_status` | — | 绩效状态总览（生涯总分/分类/配额/警告/当日得分） |
| `perf_settle` | — | 结算当日绩效（调用 settle_day） |

### 【摄像头】

| 命令 | 参数 | 说明 |
|---|---|---|
| `unlock_cam` | `<cam_id>` | 解锁指定摄像头 |
| `lock_cam` | `<cam_id>` | 锁定指定摄像头 |
| `list_cameras` | — | 列出所有摄像头（在线状态/名称/位置/锁定状态） |
| `cam_anomaly` | `<cam_id> <anomaly_id>` | 触发摄像头异常 |

### 【特效】

| 命令 | 参数 | 说明 |
|---|---|---|
| `glitch` | `[intensity] [duration]` | 故障特效（默认 0.5, 1.0） |
| `shake` | `[intensity] [duration]` | 抖屏（默认 0.01, 0.5） |
| `tear` | `[strength] [duration]` | 撕裂（默认 0.08, 0.5） |
| `noise` | `[intensity] [duration]` | 噪点爆发（默认 0.8, 0.3） |
| `blackout` | `[duration]` | 黑屏（默认 2.0） |
| `reboot_fx` | — | 播放重启 CRT 动画 |
| `reset_fx` | — | 清除所有正在播放的特效 |

### 【无线电】

| 命令 | 参数 | 说明 |
|---|---|---|
| `radio test` | — | **进入无线电演示模式**：注入全套测试信号并打开界面（幂等，可反复执行） |
| `radio clean` | — | 移除所有测试信号（重新打开 radio 会恢复真实信号） |
| `radio list` | — | 列出当前所有信号（含类型/频段/标签/特殊标记） |

**`radio test` 注入的 9 个测试信号**（覆盖 3 种类型 / 4 个频段）：

| ID | 类型 | 频段/频率 | 测试功能 | 素材 |
|---|---|---|---|---|
| `_test_morse_std` | morse | HF 7.100 | 标准摩斯解码、锁定 | 内嵌文本 |
| `_test_morse_num` | morse | HF 5.200 | 数字电台模式（五码一组） | 内嵌数字 |
| `_test_beacon` | morse | HF 14.100 | 信标日志（按 L 查看） | beacon_id |
| `_test_hidden` | morse | HF 9.800 | 隐藏信号发现（不标注） | 内嵌文本 |
| `_test_cipher` | morse | HF 10.500 | 加密标记显示（KEY 标记） | cipher_type |
| `_test_lf` | morse | LF 0.300 | 低频段覆盖 | 内嵌文本 |
| `_test_uhf` | morse | UHF 450.000 | 超高频段覆盖 | 内嵌文本 |
| `_test_sstv` | sstv | VHF 145.800 | SSTV 图像接收/保存 | `data/main/cameras/camera_test_main.jpg` |
| `_test_audio` | audio | VHF 162.550 | 音频电台自动播放 | `audio/startup.mp3` |

> 真实信号（如 S-00）会保留；测试信号 id 以 `_test_` 开头，便于识别和清理。
> 完全锁定需质量 ≥ 0.5 且持续 3 秒；锁定后才能解码摩斯/接收 SSTV。

### 【系统】

`debug 114514 voice` 打开角色实时调音面板（仅 Godot 编辑器运行时可用，先结束当前对话）。选择 Ava、神田玲或七海，点击“试听”；勾选“循环试听”后拖动滑块，下一字立即使用新参数。可编辑试听台词，滑块右侧也能输入精确数值。

可调音高 Hz、音色波形、明亮度、音高波动、单音时长、起音/尾音、音量、标点停顿和发声密度。“保存三人配置”写入 `SCRT/comm_system/voice_presets.json`，下次启动生效；未保存的变化只在当前运行中保留。“恢复当前角色”回到本次打开或最近保存的设置；“复制当前 JSON”便于分享数值。Esc 关闭面板。调音面板打开时通讯播放暂停。

在 Godot 编辑器中运行游戏时，开机动画播放期间按 **F12** 可强制跳过，包括首次开机；此快捷键在导出版本中不启用。普通跳过方式仍遵循首次开机限制。

| 命令 | 参数 | 说明 |
|---|---|---|
| `skip_boot` | — | 跳过开机动画（仅在动画播放时有效） |
| `voice` | — | 打开三位角色的实时调音与循环试听面板（编辑器） |
| `voice_meeting` | `[角色ID...]` | 自动播放多人会议音色演示，默认 Ava、七海、Rei |
| `status` | — | 调试状态总览（用户/天数/任务/对话/标记/绩效/邮件/摄像头 一览） |
| `saves` | — | 列出各用户的存档文件 |
| `delssave` | `<story_id>` | 删除指定故事存档 |
| `set` | `<key> <value>` | 设置终端设置项 |
| `get` | `<key>` | 读取终端设置项 |

录制演示：结束当前通讯后输入 `debug 114514 voice_meeting`。三人从开始同时站在左/中/右位置，先留 3 秒准备时间，再依次自我介绍，然后各读同一段文字；每句结束后间隔 1.2 秒，最后自动退出。Esc 可提前结束，再次输入命令即可重播。演示使用当前已调整的角色音色，不产生剧情完成记录、剧情信号或通讯历史。

扩展接口：编辑 `SCRT/comm_system/meeting_voice_demo.json` 的 `participants` 数组，添加 `{"id": "已注册角色ID", "slot": "left|center|right", "intro": "试听文字"}`；`comparison_text` 是所有人都读的对比句，`gap_seconds` 是句间留白，`lead_in_seconds` 是开场留白。每次命令重新读取配置。也可临时指定名单，如 `debug 114514 voice_meeting ava kanda nanami op7`；命令按左/中/右循环分配位置，超过三人时沿用现有同位置叠放。角色必须先在注册中心存在，测试接口不会自动创建角色。
---

## 三、Day0 测试速查表

| 测试目标 | 命令序列 |
|---|---|
| 完整 Day0 流程 | `skip_login` → `jump_day0` → 正常游玩 |
| D0-02 来电（forced） | 读 M00-01 邮件后自动触发 |
| D0-05 会议接入 | `trigger_call d0_05:answerable` → `comm answer` → 选 `[1]` |
| D0-05 拒绝接入 | `trigger_call d0_05:answerable` → `comm answer` → 选 `[2]` |
| D0-05 拒接来电 | `trigger_call d0_05:answerable` → `comm reject` |
| D0-06 首测来电 | `complete_env` → `trigger_call d0_06:answerable` |
| 拨号成功分支 | `complete_env` → `set_flag d0_welcome_read 1` → `trigger_call ava_report_ok` |
| 拨号失败分支 | （任务未全完成时）`trigger_call ava_report_fail` |
| D0-08/09 主动汇报后续 | `complete_env` → `trigger ava_report_ok` → 自动 next 到 d0_08/d0_09 |
| 会议视觉 | `trigger d0_meeting_1`（kanda 右侧滑入 + Ava 左侧） |
| 特效测试 | `glitch 0.8 1.5` / `shake 0.02 1.0` / `reset_fx` |
| **无线电全功能** | `radio test` → 界面内测试 → `radio clean` |
| 无线电信号列表 | `radio list` |

---

## 四、注意事项

1. **调试命令不触发 on_command 钩子**：`debug` 命令在 `execute()` 中提前拦截，不经过 `trigger_sys.on_command`，不会误触发剧情触发器。
2. **会话状态**：`skip_login` 后的会话与正常登录完全一致（走 `_enter_desktop_after_login`），所有系统正常初始化。
3. **存档影响**：`complete_env`、`set_flag`、`perf_add` 等命令会修改内存状态，但**不自动存档**。退出前若需保留，手动 `save`；若需丢弃，直接退出。
4. **重置后需重新 jump**：`reset_progress` 清空进度后，需重新 `jump_day0` 才能再次触发 Day0 事件。
5. **`trigger` vs `trigger_call`**：
   - `trigger`：跳过 call_mode 直接播放（无声无响铃）
   - `trigger_call`：走 CallHandler 流程（forced 自动接听、answerable 需手动 comm answer）
6. **对话完成标记**：`trigger` 播放的对话结束后会正常标记完成。`trigger_call` 同理。若需重复测试，先 `reset_dlg <id>`。
7. **错过来电回拨**：ANSWERABLE 来电被拒接/超时后，玩家拨打对方号码即可回拨。`comm` 命令会显示"错过的来电"列表。
8. **强制接听提示**：FORCED 来电响铃 1 次后自动接听，并显示"（本次通讯为强制接听，无法拒绝）"。
9. **无线电演示模式**：`radio test` 注入的测试信号**只在内存中**，不写入 `data/radio/`。退出 radio 后用普通 `radio` 命令进入会恢复真实信号；测试期间请始终用 `radio test` 重新进入（或先 `radio clean` 再正常进入）。

## 新 environment 隔离预览（2026-10-01）

输入 debug 114514 env normal / device / mystery / sea / clear（每次一种）。分别预览普通日、设备疑点、未解变化、海域示意；clear 恢复玩家进度。关闭观测台不会退出预览。预览不保存不计分不触发剧情。正式体验 env 后 S采集、Enter提交；详见 [environment 人工测试](upgrade-plans/environment-manual-test-plan.md)。

