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
- `[math]LaTeX[/math]` 行内公式（渲染为图片插入文本流）
- `[math block]LaTeX[/math]` 块级公式（独占一行居中）

**LaTeX 公式支持的命令：**
- 分数：`\frac{}{}`、`\binom{}{}`
- 根号：`\sqrt{}`、`\sqrt[n]{}`
- 上下标：`^{}`、`_{}`
- 大运算符：`\sum` `\int` `\prod` `\oint` `\lim`（含 `\limits`/`\nolimits`）
- 可缩放定界符：`\left( \right)`、`\left[ \right]`、`\left\{ \right\}`、`\left| \right|`
- 环境：`\begin{matrix}` `\begin{pmatrix}` `\begin{bmatrix}` `\begin{cases}` `\begin{aligned}`
- 希腊字母：`\alpha`~`\omega`、`\Alpha`~`\Omega`（含 `var` 变体）
- 运算符：`\times` `\div` `\pm` `\leq` `\geq` `\neq` `\approx` `\to` `\cdot` `\cdots` `\ldots`
- 集合论：`\in` `\notin` `\subset` `\supset` `\cup` `\cap` `\emptyset` `\setminus`
- 逻辑：`\forall` `\exists` `\nabla` `\partial` `\infty` `\neg`
- 装饰：`\overline{}` `\underline{}` `\hat{}` `\vec{}` `\dot{}` `\ddot{}` `\tilde{}` `\bar{}`
- 字体：`\mathbf{}` `\mathit{}` `\mathrm{}` `\text{}` `\mathbb{}` `\boldsymbol{}`
- 间距：`\,` `\:` `\;` `\quad` `\qquad` `\!`
- 箭头：`\rightarrow` `\leftarrow` `\Rightarrow` `\Leftarrow` `\leftrightarrow` `\mapsto`
- 函数名：`\sin` `\cos` `\tan` `\log` `\ln` `\exp` `\lim` `\max` `\min` 等
- 颜色：`\color{name/hex}`、`\textcolor{name/hex}{content}`

**LaTeX 技术细节：**
- 渲染器：`scripts/latex_renderer.gd`（`LatexRenderer` 类）
- 流程：Tokenizer → Parser(递归下降 AST) → Layout(测量+定位) → SubViewport 绘制 → ImageTexture
- 字体：Sarasa Mono SC 系列（Regular/SemiBold/Italic/SemiBoldItalic），通过 `main.gd._ready()` 注入
- 缓存：静态字典 `_cache`，key = `latex|font_size|color_hex`，无上限
- 行内公式字号 18px，块级公式字号 22px
- √ 根号符号为自绘 V 形（draw_line），高度随 radicand 自适应，避免字体字形裁剪
- `render_to_texture()` 是 async，故事加载时需预渲染；`get_cached_texture()` 是同步查询
- CRTML 集成：`crtml_parser.gd._process_inline()` 第 12 步 `_parse_math()`，复用 `_inline_image_cache` 占位符机制

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

## Vdisc 任务（`vdisc_tasks`）

主线 `res://data/main/manifest.json` 可在顶层声明 `vdisc_tasks`。每个任务需要唯一任务 ID、`title`、`story_id`、`giver_number` 和 `download.filename`。`story_id` 必须与下载的 `.scp` 包内 `manifest.json` 的 `story.id` 一致。

```json
"vdisc_tasks": {
  "sample_task": {
    "title": "调查盘任务",
    "story_id": "sample_story",
    "giver": "kanda",
    "giver_number": "1001-0002",
    "download": {
      "number": "9900-0002",
      "filename": "sample.scp",
      "url": "",
      "mail_attachment": "MAIL-01"
    },
    "requirements": {
      "min_read_percent": 20,
      "required_files": ["/reports/summary.txt"],
      "min_total_files": 5,
      "min_size_kb": 1
    },
    "on_success": {"score": "side:1", "flags": {"sample_done": 1}},
    "on_fail": {"message": "请继续调查。"},
    "wrong_recipient": {
      "default": {"action": "return"},
      "ava": {"action": "confiscate", "score": "main:1"}
    }
  }
}
```

玩家用 `download <任务ID>`、`dial <download.number>` 或 `mail download <邮件ID/编号>` 获取磁盘；邮件附件须先投递对应邮件。空 `download.url` 从游戏 `vdisc/` 中复制同名源包，非空 URL 由 HTTP 请求获取。副本位于 `saves/<用户名>/vdisc/inbox/`；上交或没收后移动到该玩家的 `submitted/` 或 `confiscated/`，共用原包保留。任务状态、归档记录及文件修改记录写入玩家 `profile.json` 的 `vdisc_task_data`。

磁盘模式中可用 `cp`、`mv`、`rm`、`mkfile` 修改任务副本，`submit <接收方号码>` 上交。已读百分比按当前可访问、未隐藏文件计算；文件大小按文本 UTF-8 字节和二进制字节计算。满足数量、必需文件和体积即可过关；有文件修改时写入 `<任务ID>_fake_pass` 标记，供后续剧情判断。新任务字段对旧故事包没有要求。

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
- **预设**：main.gd `_ready()` 中编程注册（`dial_mgr.register_system_voice()`），2026-08-19 起不再使用 `res://data/dial_directory.json`（旧文件已归档）
- **故事盘**：`manifest.json` → `dial_directory` 节，由 DiscManager 加载时注入
- **系统注册**：通过 `register_system_voice()` / `register_system_modem()` 编程注册

当前内置号码（main.gd:200-202）：

| 号码 | 角色 | 标签 |
|---|---|---|
| 1001-0001 | ava | Ava Lacant（O5 秘书长） |
| 1001-0002 | kanda | 神田玲（操作指导员） |
| 1003-0001 | nanami | 初级研究员（七海灯子） |

Format:
```json
{
  "voice": {
    "1001-0001": { "character": "ava", "label": "Ava Lacant（O5 秘书长）" }
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

### 剧情驱动字段 / Story-Driven Fields（2026-08-19 新增，Day0 剧情使用）

| 字段 | 类型 | 说明 |
|---|---|---|
| `skippable` | bool | 默认 `true`；设为 `false` 时禁止 ESC 跳过（主线剧情对话） |
| `next` | array | 对话自然结束后自动续播的对话 ID 队列（0.3s 间隔） |
| `deliver_mail` | string/array | 对话结束时投递当日配置中 `deliver_on: "scene"` 的邮件 ID |
| `flags_add` | object | 对话开始时对剧情标记（story_flags）增量累加，如 `{"anger_ava": 1}` |
| `requires_tasks` | string | `"all"`（当日 env 任务+日报全部完成）/ `"incomplete"`（未全部完成），用于拨号触发对话的条件过滤 |
| `story_action` | 行级 | string/array，行开始播放时执行触发器动作（如 `"score:1:daily"` 给当日绩效加分） |

拨号触发对话选择顺序（`comm_manager.start_dialogue_from_dial`）：
1. 角色名模式匹配（`{char}_chat` / `{char}_greeting` / `{char}_main` / `comm_{char}`）
2. 兜底：首个说话角色匹配 + 可呼叫 + 条件通过（未完成或可重复 + `_is_dial_available` 剧情条件）
3. 全部失败 → "联络员 XXX 当前不可用"

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

## 2026-10-01 ENV 观测台配置与进度

独立配置 SCRT/data/env_observation.json：capture_seconds、map_texture（空字符串时方形占位）、nearshore_radius_m/nearshore_grid_m、sea_radius_nm/sea_grid_nm、regions（id/name/position/source/sensors/view/kind）、contacts（id/kind/position/track/source；默认空）。位置相对圆盘半径归一化，右下为正，view=nearshore/sea。配置不包含无人机。

map_texture 可填写 SVG 的 res:// 路径，用于用户绘制的冷战风格矢量地形。建议正方形 viewBox、本站居中；当前显示区域为逻辑尺寸 410×410。Godot 导入 SVG 为纹理，按显示需求调整导入分辨率。底图先绘制，网格和动态标记随后叠加，保持独立配置。

EnvTaskManager 存档新增 observation_data（day/hour/weather/readings/collected/issues/submitted/score_note/notify_pending）及 observation_history（最近30份日报）。readings 无有效值用null。issue 包含首次值、复测值与时间、标记、可选校准记录。老存档缺字段可加载，已提交日报补归档不重复奖励。DailyDialogueManager 新增 pending_dialogues（ids/day/delay），等终端无遮挡且无通讯拨号后串行触发。
