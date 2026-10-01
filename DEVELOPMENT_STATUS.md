# SCRT-Reader 开发进度总结

> 2026-09-30 修复：移除 Vdisc 下载提示框的默认焦点描边；显式关闭控件边框和阴影，保留终端字符框作为唯一外框。待玩家目视确认。

> 2026-09-30 再补充：统一全屏界面下终端输出与焦点隔离，普通提示退出覆盖界面后回放；Vdisc 弹窗改为系统字符框与字符进度条。新增个人任务盘扫描标记、后台提示 debug 探针和完整手动测试方案 docs/upgrade-plans/vdisc-manual-test-plan.md。待玩家验收。

> 2026-09-30 修复：Vdisc 下载弹窗改为 CRT 后处理前渲染，统一终端字体与主题。已存在个人磁盘时需确认重新下载；成功后重置该盘进度，下载/校验失败保留旧盘。待玩家测试。

> 2026-09-30 补充：Vdisc 邮件附件支持点击下载，命令/邮件共用进度窗口；新增实际 HTTP 接收进度、本地模拟传输、失败提示和防重复领取。vdisc 显示任务缺口与上交命令。仅检查源文件，等待玩家通过 debug 验收。

> 2026-09-29 补充：会议立绘新增随对话栏上沿变化的裁剪区域，Rei 显示比例从 0.95 提至 1.20，直接渲染原始 PNG 图层；等待玩家在 Godot 中确认视觉大小与位置。

> 2026-09-29 补充：神田玲（`kanda`）已接入 Rei 的 22 张分层 PNG，按 PSD 顺序配置渲染层，并将 `-0` 眼睛、嘴型设为无活动时的默认状态。等待玩家在 Godot 中查看实际立绘；本次未运行游戏内测试。

> 2026-09-29 补充：Vdisc 任务系统已接入代码，含玩家专属磁盘副本、任务判定、文件修改、上交/没收、三种领取入口和联调样例 `demo_site19`。等待玩家在 Godot 中按 `docs/debug-mode-guide.md` 验收；本次没有执行游戏内测试。Day0 限时选项按当前安排暂缓。

> 最后更新：2026-09-12
> 基于代码实际审计结果，非文档描述。
> 本次更新：Day0 教程日剧情修复、来电系统改造、隐藏调试系统、全项目审查。

---

## 一、项目总览

**SCRT-Reader** 是一款 SCP 主题的复古 CRT 终端模拟器 / 互动小说阅读器，基于 Godot 4.7.1（GL Compatibility）开发。玩家扮演海岛观测站操作员，通过终端界面阅读故事、与角色通讯、监测环境数据、收听无线电信号。

**设计目标**：28 天完整剧情体验，5 幕结构（序章 + 3 章 + 终章），4 种结局，5 条叙事通道并行推进。

---

## 二、系统实现状态总览

| 系统 | 状态 | 说明 |
|---|---|---|
| 核心终端 | ✅ 完成 | 输入/输出/命令路由/模式切换 |
| 开关机动画 | ✅ 完成 | JSON 驱动关键帧动画 |
| CRT 着色器 | ✅ 完成 | glitch/shake/tear/noise/黑屏/重启 |
| 用户系统 | ✅ 完成 | 多用户/密码/资料/统计 |
| 存档系统 | ✅ 完成 | 自动存档/加载/清除 |
| 虚拟文件系统 | ✅ 完成 | 目录/文件/权限/密码解锁 |
| 故事加载器 | ✅ 完成 | .scp (ZIP) 解包/manifest 解析/编码检测 |
| CRTML 解析器 | ✅ 完成 | Markdown→BBCode + 内联效果标记 |
| 命令处理器 | ✅ 完成 | 53 条命令（全局 38 + 桌面 7 + 故事盘 11） |
| 绩效评分系统 | ✅ 完成 | 三类绩效/配额/加班缺口/4日报告/警告升级/perf 命令 |
| 触发器系统 | ✅ 完成 | 30 种动作类型 + 延迟执行 + 条件触发（含 score/perf_warning） |
| 通讯系统 | ✅ 完成 | 对话/选择/角色精灵/语音合成/来电模式 |
| 拨号系统 | ✅ 完成 | DTMF/号码簿/语音/调制解调器 |
| 邮件系统 | ✅ 完成 | 持久/临时收件箱/延迟投递/内联投递/去重 |
| 无线电系统 | ✅ 完成 | 摩斯码/SSTV/音频电台/频率扫描 |
| 摄像头系统 | ✅ 完成 | CCTV 多路切换/异常/信号质量/shader |
| 环境监测 | ✅ 完成 | 21 传感器 + 6 派生参数/系统时钟同步/物理关联/天气/异常/任务/仪表盘 |
| 每日对话管理 | ✅ 完成 | 7 种触发钩子 + 对话扩展加载 |
| 故事标记/选择 | ✅ 完成 | set_flag/get_flag/record_choice + 持久化 |
| 主题系统 | ✅ 完成 | 多主题/动态切换/故事包覆盖 |
| 效果安全 | ✅ 完成 | 分级效果控制 (fx_level/fx_safe) |
| 设置系统 | ✅ 完成 | 注册/存储/分类/应用回调 |
| Mod 系统 | ✅ 完成 | ModAPI/生命周期/热加载 |
| 文档查看器 | ✅ 完成 | article/chat/email/two_page 四模板 |
| 图片/视频查看器 | ✅ 完成 | 全屏覆盖/状态缓存/ESC 关闭 |
| 解码查看器 | ✅ 完成 | 示波器/解码工具 |
| LaTeX 公式渲染 | ✅ 完成 | Tokenizer→Parser(AST)→Layout→Image，支持分数/根号/矩阵/cases 等，集成 CRTML [math] 标记 |
| 每日内容配置 (DayConfig) | ❌ 未实现 | 文件解锁/环境覆盖/传感器偏移/强制事件 |
| 剧情变量系统 (StoryVariables) | ⚠️ 部分 | 仅有字符串标记，无数值变量追踪 |
| 结局判定系统 (EndingResolver) | ❌ 未实现 | 无任何结局条件判定代码 |
| 角色关系系统 | ❌ 未实现 | 无信任度/关系值追踪 |
| 每日拨号轮换 | ❌ 未实现 | 拨号系统无天数感知 |
| 来电系统 | ✅ 完成 | 2026-09-12 改造：铃声统一 1 次、FORCED 强制接听提示、ANSWERABLE 玩家选择、错过来电回拨补救 |
| 拒接后果触发 | ✅ 完成 | reject_consequence 已修复（此前永不执行），comm: 前缀走 handle_trigger_action |
| 调试系统 | ✅ 完成 | 隐藏调试命令（debug 114514 激活），覆盖全子系统 |

---

## 三、已实现功能详细清单

### 3.1 命令系统（53 条命令）

**全局命令**（桌面 + 故事盘均可用，38 条）：
`help` `clear`/`cls` `whoami` `status` `mail` `theme` `volume`/`vol` `reboot` `exit`/`quit` `profile` `logout` `passwd` `birthday` `nickname` `gender` `users` `decode` `fx_level` `fx_safe` `sound` `packages`/`pkg` `uninstall` `comm` `dial` `phonebook`/`pb` `settings`/`set` `env` `monitor` `camera`/`cam`/`cctv` `save` `perf`/`performance`

**隐藏调试命令**（2026-09-12 新增）：输入 `debug 114514` 激活，不在 `help` 显示、不在命令表注册。9 大类 40+ 子命令（登录/剧情/变量/环境/邮件/绩效/摄像头/特效/系统），操作文档见 `docs/debug-mode-guide.md`。

**桌面专用命令**（7 条）：
`scan` `load` `vdisc` `deluser` `explore` `install` `radio`

**故事盘专用命令**（11 条）：
`ls`/`dir` `cd` `back` `open`/`read`/`cat` `unlock` `eject` `clearsave` `explore`

### 3.2 触发器动作（30 种）

| 类别 | 动作 |
|---|---|
| 邮件 | `new_mail` (支持 `:persistent`) |
| 权限 | `level_up`, `lock_folder`, `unlock_folder` |
| 音效 | `sound` |
| 终端 | `text`, `redirect` |
| CRT 效果 | `glitch`, `shake`, `tear`, `noise_burst`, `play_effect`, `preset_effect`, `screen_off`, `reboot` |
| 主题 | `color_scheme` |
| 通讯 | `comm` |
| 摄像头 | `camera_unlock`, `camera_lock`, `camera_online`, `camera_offline`, `camera_anomaly`, `camera_signal` |
| 无线电 | `radio_import`, `radio_visible`, `radio_update`, `radio_reload` |
| 绩效 | `score`, `perf_warning` |
| 时序 | `delay` (可嵌套任意动作) |

### 3.3 CRTML 内联效果标记

| 类别 | 标记 |
|---|---|
| 打字机控制 | `{speed=N}` `{delay=N}` `{pause=N}` `{clear}` `{noskip}` |
| 文本效果 | `{shake}` `{wave}` `{rainbow}` `{fade}` `{blackout}` |
| 格式化 | `{b}` `{i}` `{u}` `{s}` `{color:X}` `{center}` `{right}` |
| CRT 着色器 | `{glitch}` `{screen_shake}` `{tear}` `{noise}` |
| 即时触发 | `{effect=id}` `{preset=name}` `{blackscreen=ms}` `{reboot}` `{sound=path}` |
| 文档结构 | `#` 标题、`---` 分割线、表格、代码块、链接、`[redacted]`、`{pagebreak}` |

### 3.4 每日对话管理器（7 种钩子）

| 钩子 | 触发时机 | 过滤条件 |
|---|---|---|
| `on_start` | 每天开始 | 无 |
| `on_scan_complete` | 环境扫描完成 | 无 |
| `on_anomaly` | 检测到异常 | 无 |
| `on_mail_read` | 阅读邮件 | `requires_mail` 字段匹配 |
| `on_command` | 执行命令 | `requires_command` 字段匹配 |
| `on_start_actions` | 每天开始时执行 | 触发器系统动作字符串 |
| `mail_deliveries` | 每天开始时投递 | 内联邮件定义 |

### 3.5 环境监测 manifest 覆盖键

通过 `env_config` 支持：`location` `sensors` `baselines` `weather_patterns` `anomaly_types` `events` `tasks` `master_seed`

### 3.7 绩效评分系统

- 三类绩效：`main`（主线）、`daily`（日常）、`side`（支线）+ `bonus`（额外奖励）
- 每日配额系统，DayConfig 可覆盖
- 加班缺口机制：不达标产生缺口，次日优先填补
- 4 日报告周期（自动邮件投递）
- 警告升级：邮件→AVA来电→termination 标记
- `perf` / `perf status` / `perf detail` / `perf history` 命令
- 触发器动作：`score:N[:category]`、`perf_warning:level:msg`
- 存档：`saves/{username}/performance.json`

### 3.6 故事标记系统（已实现部分）

- `set_flag(name, value)` / `get_flag(name)` / `has_flag(name)` — 字符串标记
- `record_choice(id, option)` / `get_choice(id)` / `has_choice(id)` — 选择记录
- `requires_flag` / `requires_choice` — 对话级条件门控
- 持久化至 `saves/{user}/story_progress.json`
- **缺失**：数值型变量（如 `trust_ava: 0-100`）、对话播放器自动调用 `set_flag`/`record_choice`

---

## 四、剧情内容进度

### 4.1 设计规划 vs 实际内容

| 章节 | 天数 | 对话内容 | 文件内容 | 邮件内容 | 无线电 | 环境数据 |
|---|---|---|---|---|---|---|
| **教程日** | Day 0 | ✅ 完整（D0-01~D0-10 全入引擎） | — | ✅ 2 封场景邮件（M00-01/M00-02） | ✅ S-00 彩蛋信号 | ✅ 默认配置 |
| **序章**（适应期） | Day 1-3 | ✅ 已有 | ⚠️ 有测试文件 | ✅ 3 封 | ✅ 4 信号 | ✅ 默认配置 |
| **第一章**（初兆） | Day 4-7 | ✅ 已有 | ⚠️ 有测试文件 | ❌ 无 | 同上 | 同上 |
| **第二章**（暗涌） | Day 8-14 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |
| **第三章**（真相） | Day 15-21 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |
| **终章**（结局） | Day 22-28 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |

### 4.1b Day0 教程日（2026-08-19 重写 / 2026-09-12 修复）

**剧情链**：on_start→d0_01（投递 M00-01）→ 读邮件 → d0_02（forced 来电，flags_add d0_welcome_read=1，QTE 暂用普通选项）→ choice:d0_qte → d0_qte_1/d0_qte_2 → next [d0_04, d0_05] → d0_04 投递 M00-02 → **d0_05 来电接入**（answerable，玩家选 d0_meeting_1 会议/d0_meeting_2 拒绝/d0_05_reject 拒接）→ env 上报 → d0_06（首测来电 answerable）→ 拨 1001-0001 → ava_report_ok（requires_tasks=all）/ava_report_fail → next [d0_08, d0_09]。

**2026-09-12 修复**：
- 拨号"当前不可用"根因：`requires_flag` 的 JSON float vs int 比较失败 → 数值兼容
- D0-05 会议接入：next 链检测 call_mode 响铃 + meeting 延续逻辑
- 错过来电可回拨，reject_consequence 已修复

**对话清单**（14 个）：d0_01, d0_02, d0_qte_1, d0_qte_2, d0_04, d0_05, d0_meeting_1, d0_meeting_2, d0_05_reject, d0_06, ava_report_ok, ava_report_fail, d0_08, d0_09


**manifest.json 内定义**（Day 1-3 + default）：

| 天 | on_start | on_scan_complete | on_anomaly | on_start_actions | mail_deliveries |
|---|---|---|---|---|---|
| 1 | `day1_briefing` | `day1_scan_done` | — | 2 条 radio 动作 | `welcome_mail` |
| 2 | `day2_morning` | — | `day2_anomaly_reaction` | 3 条 radio 动作 | `day2_report` |
| 3 | `day3_morning` | — | — | 5 条 radio 动作 | `day3_notice` |
| default | `daily_routine_greeting` | — | — | 2 条 radio 动作 | — |

**day_04_07.json 扩展**（Day 4-7）：

| 天 | on_start | on_scan_complete | on_anomaly | on_start_actions | mail_deliveries |
|---|---|---|---|---|---|
| 4 | `day4_morning` | — | `day4_anomaly` | — | — |
| 5 | `day5_morning` | `day5_discovery` | — | — | — |
| 6 | `day6_tension` | — | `day6_warning` | — | — |
| 7 | `day7_calm` | `day7_report` | — | — | — |

### 4.3 角色素材

| 角色 | 精灵素材 | 对话内容 | 设计文档定位 |
|---|---|---|---|
| AVA（AI 联络员） | ✅ 完整（分层/口型/眨眼） | ⚠️ 仅占位 | 导师/同伴/潜在威胁 |
| HQ（总部管控） | ❌ 无精灵 | ✅ Day 1-3 对话 | 权威/信息源/谎言 |
| 前任操作员 | ❌ 无（文件形式出现） | ❌ 无日志文件 | 幽灵角色/过去的声音 |
| 研究员 | ⚠️ 临时占位 | ❌ 无 | 知情者/Day 8+ 出场 |
| ??? 未知信号源 | ❌ 无 | ❌ 无 | 超自然/无线电出现 |

---

## 五、对照设计文档的未实现系统

### 5.1 每日内容配置扩展 (DayConfig) — 优先级 ★★★★★

**设计文档 §3.3 / §8.1** 定义了完整的 `day_config` 结构：

```
day_config = {
  "day": N,
  "act": "actN",
  "env_overrides": { "force_weather", "sensor_bias", "force_events" },
  "unlocks": { "files", "mail", "radio_signals", "passwords" },
  "triggers": { "on_read_complete:path": "action", ... }
}
```

**代码现状**：`daily_dialogues` 仅支持对话触发 + `on_start_actions` + `mail_deliveries`。以下设计功能无对应代码：
- 按天解锁文件（`unlocks.files`）
- 按天投递邮件定义（与 `mail_deliveries` 不同，这是基于 FS 的邮件模板）
- 按天激活/停用无线电信号（`unlocks.radio_signals`）
- 环境参数按天覆盖（`env_overrides.force_weather`）
- 传感器偏移（`env_overrides.sensor_bias`）
- 强制事件（`env_overrides.force_events`）
- 按天密码发放（`unlocks.passwords`）
- 行为触发器（`triggers` — 读文件/进目录后触发动作）

### 5.2 剧情变量系统 (StoryVariables) — 优先级 ★★★★☆

**设计文档 §8.2** 定义了数值型变量追踪：

```
"trust_ava": 0-100        // 对 AVA 的信任度
"truth_discovered": 0-5    // 发现了多少层真相
"hq_suspicion": 0-100      // 总部对你的怀疑度
"chose_to_report": bool    // 是否选择上报异常
"found_prev_log": bool     // 是否找到前任日志
```

**代码现状**：仅有 `_story_flags`（字符串等值比较）和 `_story_choices`（选择记录）。缺少：
- 数值型变量存储和运算（加减/比较/范围判断）
- 对话播放器自动写入标记/变量
- 变量变化时的回调通知
- 在触发器条件中使用变量

### 5.3 结局判定系统 (EndingResolver) — 优先级 ★★★☆☆

**设计文档 §6.3 / §8.3** 定义了 4 种结局：

| 结局 | 条件 |
|---|---|
| A "服从者" | `truth_discovered < 2` |
| B "发现者" | `truth_discovered >= 2 AND chose_to_report == false` |
| C "揭露者" | `truth_discovered >= 4 AND chose_to_report == true` |
| D "理解者" | `truth_discovered == 5 AND trust_ava >= 80` |

**代码现状**：零实现。无 EndingResolver 类，无结局条件判定逻辑。

### 5.4 角色关系系统 — 优先级 ★★★☆☆

**设计文档 §8.4** 定义了：
- 对话选择影响关系值
- 关系值影响角色后续对话内容
- 高关系值角色透露更多信息

**代码现状**：零实现。无任何关系追踪代码。

### 5.5 每日拨号对话轮换 — 优先级 ★★★★☆

**设计文档 §4.3 / §8.5** 定义了：
- 每天拨号同一角色获得不同对话
- `Day N → ava_call_dayN`，无配置则 `ava_call_default`

**代码现状**：`dial_manager.gd` 的 `resolve_number()` 为静态字典查找，无天数感知。

---

## 六、开发路线图状态

对照设计文档 §9.1 定义的四阶段路线图：

### Phase 1: 核心完善 — 进行中

| 任务 | 状态 | 说明 |
|---|---|---|
| 修复现有 bug | ✅ 完成 | 本次审计修复 10 个 bug；2026-09-12 修复 5 个（reject_consequence、debug list_mail、超时提示、slide_hide、requires_flag） |
| Day0 教程日 | ✅ 完成 | D0-01~D0-10 全入引擎，会议接入/拨号/错过来电回拨完善 |
| 完善 DayConfig 系统 | ❌ 未开始 | 需将 daily_dialogues 扩展为完整日配置 |
| 编写 7 天完整内容 | ⚠️ 部分 | Day 1-7 有对话框架，缺文件/邮件/环境细节 |
| 验证完整单日循环 | ⚠️ 部分 | Day0 已完整验证，Day 1+ 缺内容驱动验证 |

### Phase 2: 叙事深化 — 未开始

| 任务 | 状态 |
|---|---|
| 实现 StoryVariables 系统 | ❌ 仅有基础 flag |
| 对话选择影响变量 | ❌ |
| 按变量条件加载内容 | ❌ |
| 编写第二章 (Day 8-14) | ❌ |

### Phase 3: 结局与打磨 — 未开始

| 任务 | 状态 |
|---|---|
| 实现 EndingResolver | ❌ |
| 编写第三章+终章 (Day 15-28) | ❌ |
| 多结局分支内容 | ❌ |
| 整体体验打磨 | ❌ |

### Phase 4: 模组化 — 部分完成

| 任务 | 状态 | 说明 |
|---|---|---|
| Mod API | ✅ 完成 | mod_api.gd + mod_base.gd |
| 模组制作文档 | ✅ 完成 | story-authoring-guide.txt (1622 行) |
| .scp 覆盖/扩展验证 | ⚠️ 部分 | 基础功能可用，缺 day_configs |
| 模组模板 | ❌ 未提供 | |

---

## 七、下一步优先事项

按依赖关系和优先级排序（2026-09-12 更新）：

1. **QTE 限时选项**（★★★★★，建议最先做）
   - D0-02 现为普通选项，需限时 + 超时默认选项（开发需求#1）
   - 纯前端引擎改动，不依赖新剧情源稿，能立即验证

2. **扩展 DayConfig 系统**（Phase 1 核心阻塞项）
   - 在 `daily_dialogue_manager.gd` 或新脚本中实现 `day_configs` 解析
   - 支持文件解锁、环境覆盖、传感器偏移、强制事件、密码发放
   - 支持行为触发器（读文件→动作）

3. **实现每日拨号轮换**（Phase 1）
   - `dial_manager.gd` 增加天数感知路由
   - 按天数查找 `{character}_call_day{N}`，回退到 `_call_default`

4. **完善 Day 1-7 内容**（Phase 1）
   - 补充 Day 4-7 的 `on_start_actions` 和 `mail_deliveries`
   - 添加前任操作员日志文件
   - 添加加密目录和密码线索

5. **扩展 StoryVariables 为数值系统**（Phase 2）
   - 在现有 flag 基础上增加数值变量
   - 支持加减运算和范围比较
   - 对话播放器自动写入标记

6. **实现 EndingResolver**（Phase 3）
   - 基于 StoryVariables 的条件表达式求值
   - 4 种结局分支判定

7. **编写 Day 8-28 剧情内容**（Phase 2-3）
   - 第二章：暗涌（Day 8-14）
   - 第三章：真相（Day 15-21）
   - 终章：结局（Day 22-28）

---

## 八、代码规模参考（2026-09-12 实际值）

| 脚本 | 行数 | 说明 |
|---|---|---|
| command_handler.gd | 3142 | 命令注册与执行（含隐藏 debug 调试系统 40+ 子命令） |
| main.gd | 2284 | 核心路由/模式管理/绩效集成/LaTeX 渲染器初始化/mail 按钮守卫 |
| latex_renderer.gd | 1720 | LaTeX 公式渲染器（Tokenizer→Parser→Layout→Image） |
| radio_receiver.gd | 1804 | 无线电接收器 |
| crtml_parser.gd | 1325 | CRTML→BBCode（含 LaTeX [math] 公式） |
| comm_manager.gd | 1344 | 通讯系统管理（含来电路由、错过来电回拨、拒接后果） |
| mail_system.gd | 937 | 邮件系统（含邮件阅读对话延迟触发、收件箱防重开） |
| env_monitor.gd | 1522 | 环境监测（21传感器+6派生参数+系统时钟） |
| modder/mod_api.gd | 1075 | Mod API |
| user_manager.gd | 853 | 用户账户 |
| boot_sequence.gd | 809 | 开关机动画 |
| trigger_system.gd | 754 | 触发器系统（含 score/perf_warning） |
| video_player.gd | 750 | 视频播放器 |
| env_task_manager.gd | 828 | 环境任务管理 |
| disc_manager.gd | 700 | 故事盘管理 |
| env_viewer.gd | 578 | 环境仪表盘（含派生参数） |
| daily_dialogue_manager.gd | 534 | 每日对话管理（含 requires_flag 数值兼容、绩效配额） |
| performance_manager.gd | 413 | 绩效评分系统 |
| comm_system/call_handler.gd | 328 | 呼叫模式处理器（SILENT/FORCED/ANSWERABLE、错过来电记录） |
| comm_system/comm_dialogue_player.gd | 394 | 对话播放引擎（含 meeting 模式延续） |

总代码量：约 44,000 行 GDScript


## 2026-10-01 ENV 观测台升级（待人工验收）

接入圆形近海／海域监视盘、正方形地图占位、短采集、固定快照、复测／关注／设备校准、手动日报与历史、profile 绩效概览、隔离 debug。基础任务改为首次日报 +1（Day0 仍由剧情计分），防重复奖励；日常通讯改为覆盖界面结束后排队播放。地图等待用户手绘，无无人机或 3D 拍照。未运行 Godot，验收见 docs/upgrade-plans/environment-manual-test-plan.md。

