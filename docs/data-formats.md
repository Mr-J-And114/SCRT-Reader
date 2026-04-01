# 数据与内容格式 (Data & Content Formats)

> 最后更新：2026-04-01
<!-- Extracted from SCRT/AI_HANDOFF.md §5 -->

## 故事盘格式 (.scp)

ZIP 压缩包，包含：
- `manifest.json` 或 `manifest.cfg` — 故事元数据、文件系统定义、权限、触发器、效果、无线电信号、邮件、对话
- 文本文件（CRTML 格式）、图片（PNG/JPG）、音频（MP3/OGG/WAV）、视频（OGV/MP4）

编码检测：优先 UTF-8，回退 GBK（由 StoryLoader 处理）。

存放位置：编辑器模式 `res://vdisc/`，导出版 `./vdisc/`。
通过调制解调器拨号下载的 .scp 文件也保存到相同的 `vdisc/` 目录。

## 无线电信号配置 / Radio Signal Config（manifest 中的 `radio_signals`）

支持数组格式，每个信号可配置以下属性：
- `type`：`"morse"` | `"sstv"` | `"audio"` — 信号内容类型（摩斯码 / 慢扫描电视 / 音频电台）
- `hidden`：bool — 隐藏信号不会在雷达点、频率标尺标记、瀑布图标记上显示
- `proximity_range`：float (MHz) — 渐进感知范围（0 = 使用 `tolerance_freq`）
- `content_audio`：PackedByteArray — `"audio"` 类型信号的已加载音频数据
- 音频电台在调谐接近时自动播放，音量随信号质量缩放
- 所有信号类型都支持渐进感知（在完全锁定前就能听到声音）

## CRTML 标记语法 (CrtmlParser)

Markdown 风格语法 → BBCode 转换：

**文档结构：**
- `# H1`、`## H2`、`### H3` 标题
- `**bold**` 粗体、`*italic*` 斜体、`~~strike~~` 删除线、`` `code` `` 行内代码
- `||spoiler||` 剧透遮罩、`[CLASSIFIED]`/`[REDACTED]` SCP 风格涂黑标记
- `███` 黑色方块
- `---` 分隔线、`===` / `{pagebreak}` 分页符
- `> quote` 引用块
- `![alt](path)` 图片、`!audio[label](path)` 音频、`!video[label](path)` 视频
- `|col1|col2|` 表格语法

**打字机控制标签：**
- `{speed=N}` / `{/speed}` 打字速度
- `{delay=N}` / `{pause=N}` 暂停（毫秒）
- `{clear}` 清屏
- `{noskip}` / `{/noskip}` 强制不可跳过

**文本效果标签（BBCode）：**
- `{shake}` / `{wave}` / `{rainbow}` / `{fade}` / `{blackout}` 文本动画
- `{color:name/hex}` / `{/color}` 颜色
- `{b}` `{i}` `{u}` `{s}` 格式化
- `{center}` / `{right}` 对齐

**CRT 着色器效果标签（范围）：**
- `{glitch}` 或 `{glitch=intensity}` / `{/glitch}` 故障效果
- `{screen_shake}` 或 `{screen_shake=intensity}` / `{/screen_shake}` 屏幕抖动
- `{tear}` 或 `{tear=strength}` / `{/tear}` 画面撕裂
- `{noise}` 或 `{noise=intensity}` / `{/noise}` 噪声

**即时触发效果标签：**
- `{effect=id}` 触发命名效果序列
- `{preset=name}` 触发内置预设
- `{blackscreen=ms}` 黑屏
- `{reboot}` 重启效果
- `{sound=path}` 播放音效

## 自定义加载画面配置 / Loading Screen Config (`loading_screen.json` in vdisc root)

放置在 `.scp` 故事包根目录的可选 JSON 文件。若存在，则在加载故事盘时**完全替换**内置默认加载动画。
由 `disc_manager._extract_loading_screen()` 在填充虚拟文件系统之前提取（对玩家不可见）。
使用与 `boot_sequence.gd` 相同的关键帧时间轴引擎。

播放期间 `main._process()` 进入独占模式——仅加载画面处理，其他系统（打字机、触发器、邮件、效果）全部挂起。

### 顶层字段 / Top-level Fields

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `skippable` | bool | `true` | 允许玩家按任意键跳过 |
| `total_duration` | float | `8.0` | 动画总时长（秒） |
| `audio` | string | `""` | 背景音乐的虚拟文件系统路径 |
| `audio_volume` | float | `0.6` | 音乐音量（线性 0.0~1.0） |
| `keyframes` | array | `[]` | `{time, action, params}` 关键帧对象数组 |

### 关键帧动作 / Keyframe Actions

**文本输出：**
| 动作 | 参数 | 说明 |
|---|---|---|
| `text` | `content`, `color` | 终端文本行 |
| `text_center` | `content`, `color` | 居中文本行 |
| `disc_title` | `color`（可选） | 显示故事盘标题框（使用 `fs.build_box`） |
| `disc_info` | `color`（可选） | 显示作者/版本/ID 信息 |
| `separator` | `char`（默认 `═`）, `width`（默认 50）, `color` | 分隔线 |
| `ascii_art` | `content`, `color` | ASCII 艺术字块 |

**视觉效果：**
| 动作 | 参数 | 说明 |
|---|---|---|
| `glitch` | `intensity`, `duration` | CRT 故障效果 |
| `scanlines` | `intensity` | 扫描线强度 |
| `screen_flash` | `duration` | 屏幕闪烁 |

**音频：**
| 动作 | 参数 | 说明 |
|---|---|---|
| `beep` | — | 终端蜂鸣音 |
| `sound` | `path` | 从虚拟文件系统播放音效 |
| `audio_play` | `path`（可选，回退到顶层 `audio`） | 开始播放背景音乐 |

**流程控制：**
| 动作 | 参数 | 说明 |
|---|---|---|
| `clear` | — | 清屏 |
| `wait` | — | 空操作占位符 |
| `progress_bar` | `duration`, `label` | 动画进度条（就地更新） |
| `complete` | — | 结束加载画面 |

### 变量替换 / Variable Substitution（`text`/`text_center` 的 content 字段中可用）

| 变量 | 替换为 |
|---|---|
| `{disc_title}` | manifest 中的故事标题 |
| `{disc_author}` | 作者名 |
| `{disc_version}` | 版本号 |
| `{disc_id}` | 故事 ID |
| `{username}` | 当前登录用户名 |

### 颜色名称 / Color Names

`primary`、`success`、`warning`、`error`、`muted` — 通过 ThemeManager 解析为实际颜色值。

### Example

```json
{
  "skippable": true,
  "total_duration": 8.0,
  "keyframes": [
    { "time": 0.0, "action": "clear" },
    { "time": 0.0, "action": "text", "params": {
        "content": "INSERTING VIRTUAL DISC...", "color": "muted" } },
    { "time": 0.5, "action": "glitch", "params": {
        "intensity": 0.2, "duration": 0.3 } },
    { "time": 1.0, "action": "disc_title" },
    { "time": 1.5, "action": "disc_info" },
    { "time": 2.0, "action": "separator" },
    { "time": 2.5, "action": "progress_bar", "params": {
        "duration": 4.0 } },
    { "time": 7.0, "action": "text", "params": {
        "content": "READY.", "color": "success" } },
    { "time": 8.0, "action": "complete" }
  ]
}
```

## 开机/关机配置 / Boot/Shutdown Config (`res://boot_config.json`)

JSON 关键帧时间轴格式：`{time, action, params}`。
由 `boot_sequence.gd` 解析和播放，控制终端的开机动画和关机动画。

可用动作：`screen_off`（黑屏）、`screen_on`（亮屏）、`audio_play`（播放音频）、`text`（文本输出）、`beep`（蜂鸣）、`glitch`（故障效果）、`scanlines`（扫描线）、`progress_bar`（进度条）、`clear`（清屏）、`fade_in`（淡入）、`background`（背景色）、`logo`（显示 Logo）、`screen_collapse`（屏幕坍缩效果）、`shutdown_sound`（关机音效）、`quit`（退出程序）。

## 存档系统 / Save System

| 路径 | 用途 |
|---|---|
| `res://saves/{username}/save_{story_id}.json` | 每个故事的存档数据 |
| `res://saves/{username}/profile.json` | 用户个人资料 |
| `res://saves/{username}/settings.json` | 用户个人设置 |
| `res://saves/_settings_global.json` | 全局设置（跨用户共享） |
| `res://saves/{username}/mail/` | 邮件存储目录 |

存档文件中的扩展数据键：
- `extra["env_data"]` / `extra["env_task_data"]` — 环境监测系统状态（传感器读数、任务进度）
- `extra["camera_data"]` — 摄像头系统状态（每个摄像头：解锁状态、在线状态、信号质量、视口位置、异常冷却）

绩效数据独立存储：
- `res://saves/{username}/performance.json` — 绩效评分系统存档

### 绩效存档格式 / Performance Save Format (`performance.json`)

```json
{
  "current_day": 5,
  "daily_quota": 3,
  "overtime_gap": 0,
  "warning_level": 0,
  "career_main": 12,
  "career_daily": 8,
  "career_side": 5,
  "career_bonus": 3,
  "career_overtime": 2,
  "career_warnings": 1,
  "day_history": [
    {"day": 1, "main": 3, "daily": 2, "side": 1, "bonus": 1, "total": 7, "quota": 3, "gap": 0},
    {"day": 2, "main": 2, "daily": 1, "side": 0, "bonus": 0, "total": 3, "quota": 3, "gap": 0}
  ]
}
```

## 环境监测时间配置 / Environment Time Config (`env_config.json` time section)

系统时钟同步配置（替代了旧的虚拟加速时间方案）：

```json
{
  "time": {
    "use_system_clock": true,
    "update_interval_seconds": 5.0,
    "weather_shift_interval_minutes": 45.0,
    "fictional_year": 2024,
    "fictional_start_month": 10,
    "fictional_start_day": 15,
    "timezone_display": "UTC+11"
  }
}
```

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `use_system_clock` | bool | `true` | 使用系统时钟驱动昼夜节律 |
| `update_interval_seconds` | float | `5.0` | 传感器读数刷新间隔（真实秒） |
| `weather_shift_interval_minutes` | float | `45.0` | 天气模式切换间隔（真实分钟） |
| `fictional_year` | int | `2024` | 虚构年份（仅用于显示） |
| `fictional_start_month` | int | `10` | 虚构起始月（1-12） |
| `fictional_start_day` | int | `15` | 虚构起始日（1-31） |
| `timezone_display` | string | `"UTC+11"` | 时区显示文本 |

## DayConfig 绩效配额覆盖 / DayConfig Performance Override

在 `daily_dialogues` 的天数配置中，可添加 `"performance"` 节覆盖当日绩效配额：

```json
{
  "daily_dialogues": {
    "5": {
      "on_start": ["day5_morning"],
      "performance": {
        "min_quota": 5
      }
    }
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `min_quota` | int | 当日最低绩效配额（覆盖 PerformanceManager 默认值） |

## 电话簿配置 / Dial Directory Config

电话号码从多个来源加载（优先级：故事盘 > 系统注册 > 预设）：
- **预设**：`res://data/dial_directory.json` — 内置号码，启动时加载
- **故事盘**：`manifest.json` → `dial_directory` 节，由 DiscManager 加载时注入
- **系统注册**：通过 `register_system_voice()` / `register_system_modem()` 编程注册

Format:
```json
{
  "voice": {
    "1001-0001": { "character": "ava", "label": "AVA - Liaison Officer" }
  },
  "modem": {
    "9900-0001": {
      "label": "SCP Archive Server",
      "speed_display": "9600 bps",
      "filename": "story.scp",
      "url": "https://example.com/story.scp"
    }
  }
}
```

### 通话类型 / Call Types

| 类型 | 流程 | 结果 |
|---|---|---|
| VOICE（语音） | DTMF 按键音 → 1 秒 → 回铃音 → 接通 → CommManager 对话 | 对话结束后播放挂断音 |
| MODEM（调制解调器） | DTMF → 1 秒 → 回铃音 → AT 命令 → 载波检测 → 握手音频 → 带进度条下载 | 文件保存到 vdisc/ |
| INVALID（无效） | DTMF → 1 秒 → 忙音 | 显示"号码不存在" |

## 通讯对话格式 / Comm Dialogue Format（manifest 中的 `dialogues` 或独立 JSON）

`dialogues` 数组/字典中的每个对话对象支持以下字段：

### 基础字段 / Basic Fields

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | string | 是 | 对话唯一标识符 |
| `character` | string | 是 | 角色 ID（必须匹配已定义的角色） |
| `trigger` | string | 否 | 自动触发条件（如 `"incoming_call"`、`"story_start"`） |
| `lines` | array | 是 | 对话行对象数组 |

### 来电模式字段 / Call Mode Fields

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `call_mode` | string | `"silent"` | `"silent"` 直接开始，无铃声；`"forced"` 响铃后自动接听；`"answerable"` 响铃，玩家需 `comm answer` 或 `comm reject` |
| `reject_consequence` | string | `""` | 玩家拒接时显示的文本 |
| `caller_name` | string | 角色标签 | 响铃时显示的来电者名称 |

触发器格式：`comm:dialogue_id:forced` 或 `comm:dialogue_id:answerable`。

### 视频/会议模式字段 / Video / Meeting Mode Fields

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `video_call` | bool | `false` | 标记为视频通话（出现在 `comm video` 频道列表中） |
| `video_number` | string | `""` | 此视频频道的拨号号码（如 `"1002-0001"`） |
| `display_mode` | string | `"normal"` | `"normal"` 纯文本、`"video"` 单角色视频、`"meeting"` 多角色会议、`"presentation"` 会议+幻灯片 |

### 会议模式角色设置 / Meeting Mode Character Setup（逐行配置）

| 字段 | 类型 | 说明 |
|---|---|---|
| `meeting_slot` | string | `"left"` 或 `"right"` — 角色在会议布局中的位置 |
| `char_anim` | string | 角色动画：`"talk"`（说话）、`"idle"`（待机）、`"think"`（思考）等 |

多角色共享屏幕，带 40px 重叠偏移。当前说话者置于前景并全亮度显示；非活跃角色亮度降至 70%。

### 演示模式 / Presentation Mode（逐行配置）

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `slide_image` | string | — | 幻灯片图片路径（相对于故事包或 `res://`） |
| `slide_position` | array | `[0.55, 0.1]` | `[x, y]` 归一化位置 (0.0~1.0) |
| `slide_size` | array | `[0.4, 0.5]` | `[w, h]` 归一化尺寸 (0.0~1.0) |
| `slide_area` | array | — | `[x, y, w, h]` 显示区域（覆盖 position+size） |
| `slide_fit` | string | `"contain"` | 图片适配模式：`"contain"` 包含 / `"cover"` 覆盖 / `"stretch"` 拉伸 / `"actual"` 原始尺寸 |
| `slide_align` | string | `"center"` | 区域内对齐：`"center"` / `"top_left"` / `"top_center"` / `"top_right"` / `"center_left"` / `"center_right"` / `"bottom_left"` / `"bottom_center"` / `"bottom_right"` |
| `slide_transition` | string | `"fade"` | 过渡效果：`"fade"` 淡入 / `"instant"` 即时 / `"slide_left"` 左滑 / `"slide_right"` 右滑 |
| `slide_hide` | bool/string | — | 隐藏当前幻灯片（`true` 或指定过渡效果如 `"slide_left"`） |

### 对话前清屏设置 / Clear-Before-Dialogue Setting

在设置系统中注册为 `comm.clear_before_dialogue`（布尔值，默认 `false`）。启用后，每次新对话开始前清空终端输出。

### 示例：可接听来电 + 视频会议 / Example: Answerable Call with Video Meeting

```json
{
  "id": "team_briefing",
  "character": "ava",
  "call_mode": "answerable",
  "reject_consequence": "未接来电已记录。",
  "video_call": true,
  "video_number": "1000-9999",
  "display_mode": "meeting",
  "lines": [
    {
      "character": "ava",
      "meeting_slot": "left",
      "text": "各位，会议开始。"
    },
    {
      "character": "researcher",
      "meeting_slot": "right",
      "char_anim": "talk",
      "text": "收到，请继续。"
    },
    {
      "character": "ava",
      "meeting_slot": "left",
      "slide_image": "slides/plan.png",
      "slide_area": [0.5, 0.05, 0.45, 0.6],
      "slide_fit": "contain",
      "slide_align": "center",
      "slide_transition": "fade",
      "text": "请看这份计划。"
    }
  ]
}
```
