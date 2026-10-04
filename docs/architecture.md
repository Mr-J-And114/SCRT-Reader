# 架构参考文档 (Architecture Reference)

> 最后更新：2026-04-01 | 行数通过 `wc -l` 核实
<!-- Extracted from SCRT/AI_HANDOFF.md §2-4, §7, §10, §13-15 -->

## 核心依赖图 (Core Dependency Graph)

```
main.gd (extends Control) — the god object
├─ fs: FileSystem — virtual filesystem tree
├─ save_mgr: SaveManager — per-user per-story save/load
├─ tw: Typewriter (extends Node) — queued typewriter output + inline FX
├─ T: ThemeManager — 4 color themes (green/amber/blue/white)
├─ story_loader: StoryLoader — parse .scp ZIP → populate fs
├─ cmd_handler: CommandHandler — CLI command registry + dispatch
├─ disc_mgr: DiscManager — scan/load/eject story discs
├─ user_mgr: UserManager — multi-user accounts, profiles, stats
├─ crtml: CrtmlParser — Markdown-like markup → BBCode for RichTextLabel
├─ pkg_mgr: PackageManager — mod .scp install/uninstall/runtime
├─ settings_mgr: SettingsManager — registry-based settings with TUI
├─ comm_mgr: CommManager — dialogue/comm system (characters, calls, presentation)
│  ├─ call_handler: CallHandler — SILENT/FORCED/ANSWERABLE incoming call flow
│  ├─ comm_ui: CommUI — dialogue bar, card/meeting/presentation modes, history
│  │  └─ presentation: PresentationOverlay — slide display with fit/align/transitions
│  ├─ character_registry: CharacterRegistry — character lifecycle (builtin/disc/mod)
│  │  └─ asset_library: CharacterAssetLibrary — asset profiles, texture loading
│  ├─ dial_mgr: DialManager — DTMF dialing, voice call routing, modem download state machine
│  ├─ tone_gen: DialToneGenerator — procedural DTMF/ringback/busy/modem/hangup audio synthesis (owned by dial_mgr)
├─ trigger_sys: TriggerSystem — event-driven triggers (enter dir, open file, etc.)
├─ mail_sys: MailSystem — in-game mail inbox with delayed delivery
├─ effect_sys: EffectSystem — timeline-based multi-step effect sequences
├─ effect_settings: EffectSettings — photosensitive/intensity levels
├─ boot_sequence: BootSequence — keyframe-driven boot/shutdown animations
├─ loading_screen: LoadingScreen — disc loading animation (custom or default, exclusive mode)
├─ doc_viewer: DocumentViewer — paginated document overlay
├─ profile_builder: ProfileBuilder — user profile card pages
├─ explore_viewer: ExploreViewer — file tree explorer panel
├─ image_viewer: ImageViewer — zoomable image viewer with scanline
├─ oscilloscope: Oscilloscope — audio spectrum/lissajous visualizer
├─ video_player_viewer: VideoPlayerViewer — video playback overlay
├─ radio_receiver: RadioReceiver — radio tuning/morse/SSTV/audio station/hidden signals decoder
├─ decode_viewer: DecodeViewer — cipher decode visualization
├─ ui_sound: UiSound — procedural keystroke/click SFX
├─ camera_mgr: CameraManager — CCTV camera management (register/unlock/anomaly/save)
├─ camera_viewer: CameraViewer — fullscreen camera overlay with shader rendering
├─ perf_mgr: PerformanceManager — scoring (main/daily/side), quotas, overtime, warnings
├─ ui_manager(static calls): UIManager — theme-aware style builder
├─ audio_manager: AudioManager (extends Node) — ambient/sfx/media players, load from bytes (MP3/OGG/WAV)
└─ crt_shader: CRTShader (extends ColorRect) — CRT post-process on CanvasLayer(10)
```

## 场景树 (Scene Tree - main.tscn)

```
Main (Control, fullrect) [main.gd]
├─ Background (ColorRect, black)
│  ├─ Backgrund (TextureRect, background_vignette shader)
│  └─ CenterContainer
│     └─ BackgroundLogo (TextureRect, background_logo shader, 600×600)
├─ MainContent (VBoxContainer, fullrect)
│  ├─ StatusFrame (PanelContainer)
│  │  └─ StatusBar (HBoxContainer, h=30)
│  │     ├─ PathLabel (Label) — shows "[/root]" etc.
│  │     └─ MailIcon (Label, right-aligned) — "[Mail]"
│  ├─ OutputArea (ScrollContainer, expand)
│  │  └─ OutputText (RichTextLabel, bbcode=true, fit_content=true)
│  └─ InputFrame (PanelContainer)
│     └─ InputArea (HBoxContainer, h=30)
│        ├─ Prompt (Label) — ">"
│        └─ InputField (LineEdit, expand)
├─ AudioManager (Node) [audio_manager.gd]
└─ CRTEffect (CanvasLayer, layer=10)
   └─ CRTShader (ColorRect) [crt_shader.gd] — crt_effect.gdshader
```

## 脚本参考 (Script Reference)

### 核心脚本 (`res://scripts/`)

| File | Class | Lines | Purpose |
|---|---|---|---|
| main.gd | — | 2381 | 中央控制器：初始化、输入路由、模式管理、Vdisc 任务集成及其他子系统 |
| file_system.gd | FileSystem | 535 | 虚拟文件系统树、权限、路径工具、任务副本文件操作 |
| command_handler.gd | CommandHandler | 3397 | CLI 命令注册、Vdisc 下载/编辑/上交、隐藏调试系统 |
| latex_renderer.gd | LatexRenderer | 1720 | LaTeX 公式渲染器：Tokenizer→Parser(AST)→Layout→Image，支持分数/根号(自绘)/矩阵/上下标/定界符/cases |
| story_loader.gd | StoryLoader | 708 | 解析 .scp ZIP 文件、编码检测（UTF-8/GBK）、构建 manifest + 文件系统 |
| disc_manager.gd | DiscManager | 751 | 扫描共用原盘和玩家任务副本、加载/弹出故事、工作副本恢复 |
| vdisc_task_manager.gd | VdiscTaskManager | 640 | 任务定义、下载登记、工作副本、判定、玩家专属归档和存档 |
| crtml_parser.gd | CrtmlParser | 1325 | Markdown→BBCode：标题、粗体、斜体、剧透、表格、媒体标签、效果标签、分页、LaTeX [math] 公式 |
| typewriter.gd | Typewriter | 540 | 排队式文本输出，逐字打字、内联效果触发、进度条 |
| save_manager.gd | SaveManager | 228 | 每用户每故事 JSON 存档/读档、自动存档 |
| user_manager.gd | UserManager | 853 | 多用户账户、登录/注册/改密、个人资料、统计、故事进度 |
| audio_manager.gd | AudioManager | 586 | 环境音（交叉淡化）/音效/媒体播放器、ducking、频谱分析、字节加载 |
| crt_shader.gd | — | 416 | CRT 后处理：glitch/shake/tear/开关机/noise burst/blackout |
| theme_manager.gd | ThemeManager | 517 | 4 种主题配色（ThemeColors）、CRT/背景/logo 着色器参数刷新 |
| boot_sequence.gd | BootSequence | 809 | JSON 关键帧驱动开机/关机动画：黑屏/亮屏/文本/故障/进度条/音频 |
| loading_screen.gd | LoadingScreen | 543 | 磁盘加载关键帧动画（支持 loading_screen.json 自定义或内置默认） |
| trigger_system.gd | TriggerSystem | 754 | 事件触发器：进目录/开文件/命令/空闲/等级变化 → 30 种动作（含 score/perf_warning） |
| performance_manager.gd | PerformanceManager | 413 | 绩效评分：三类绩效(main/daily/side)、配额、加班缺口、4日报告、警告升级、剧情版本门控 |
| mail_system.gd | MailSystem | 958 | 邮件收件箱、延迟投递、Vdisc 附件领取、邮件阅读对话延迟触发 |
| effect_system.gd | EffectSystem | 451 | 时间轴效果序列（glitch/shake/sound/text/reboot/brightness 等） |
| effect_settings.gd | EffectSettings | 175 | 效果强度等级（full/mild/off）、光敏模式 |
| settings/settings_manager.gd | SettingsManager | 903 | 注册式设置系统：分类、TUI 界面、导入/导出 |
| settings/settings_registry.gd | — | 225 | 内置设置定义注册（所有默认分类和设置项） |
| settings/settings_storage.gd | — | 165 | JSON 存储后端：全局 + 用户级、版本迁移 |
| header_parser.gd | HeaderParser | 247 | 文件头部解析（标记块中的元数据） |
| cipher_decoder.gd | CipherDecoder | 584 | 凯撒、维吉尼亚、替换、Base64、摩斯、ROT13、Atbash、反转 |
| morse_engine.gd | MorseEngine | 327 | 摩斯码编解码、播放事件、数字站模式 |
| radio_audio_generator.gd | RadioAudioGenerator | 304 | 程序化噪声/音调/SSTV 音频生成 |
| radio_config_parser.gd | RadioConfigParser | 301 | 解析无线电信号定义（配置/manifest）；RadioSignal 数据类 |
| radio_signal_manager.gd | RadioSignalManager | 324 | 信号数据库、质量计算（渐进接近）、发现跟踪、书签、扫描 |
| sstv_decoder.gd | SSTVDecoder | 294 | SSTV 图像接收模拟，带扫描线噪声 |
| package_manager.gd | PackageManager | 817 | Mod 系统：安装/卸载 .scp Mod、钩子分发、Mod 生命周期 |
| ui_manager.gd | UIManager | 466 | 程序化 UI 样式：光标、滚动条、面板主题、字体设置 |
| ui_sound.gd | UiSound | 200 | 程序化音效：按键/回车/退格/硬盘读取/点击 |
| profile_builder.gd | ProfileBuilder | 253 | 构建 3 页用户资料卡片 |
| video_player.gd | VideoPlayerViewer | 750 | 视频播放覆盖层，含控件，ffmpeg 回退支持 |
| daily_dialogue_manager.gd | DailyDialogueManager | 556 | 每日对话/邮件触发管理、主线剧情加载、场景邮件投递、requires_tasks 条件、requires_flag 数值兼容、故事标记/选择持久化、剧情版本门控、绩效配额配置 |
| env_monitor.gd | EnvMonitor | 1522 | 环境模拟：21 传感器 + 6 派生参数、系统时钟同步、传感器间物理关联、天气模式、异常检测、Day0 起始天数、剧情版本门控 |
| env_task_manager.gd | EnvTaskManager | 841 | 旧任务兼容、观测快照／历史、首次日报计分（Day0 剧情计分） |
| camera_feed.gd | CameraFeed | 320 | 单摄像头数据模型：底图/深度图/照明/异常图像、镜头参数 |
| camera_manager.gd | CameraManager | 435 | 摄像头注册中心、解锁/锁定、异常触发、存档/读档、图像加载 |

### 查看器/覆盖层脚本 (Viewer/Overlay Scripts)

| 文件 | 类名 | 行数 | 用途 |
|---|---|---|---|
| document_viewer.gd | DocumentViewer | 668 | 双页覆盖层（左/右 RTL），分页，打字动画 |
| explore_viewer.gd | ExploreViewer | 481 | 文件树面板，任务磁盘进度显示 |
| image_viewer.gd | ImageViewer | 634 | 可缩放图像查看器，平移，扫描效果，_ImageCanvas 内部类 |
| oscilloscope.gd | Oscilloscope | 820 | 频谱分析器 + 李萨如图形，_ScopeCanvas 内部类 |
| radio_receiver.gd | RadioReceiver | 1735 | 完整无线电 UI：调谐/频段/摩斯解码/SSTV/音频电台/隐藏信号/瀑布图，_RadioCanvas 内部类 |
| decode_viewer.gd | DecodeViewer | 1461 | 密码解码动画查看器，_DecodeCanvas 内部类 |
| env_viewer.gd | EnvViewer | 821 | 环境命令观测台，地图简报、实时详情、采集证据与日报历史 |
| camera_viewer.gd | CameraViewer | 656 | CCTV 全屏覆盖层，shader 渲染监控画面，平移/切换控制 |

### 通讯系统 (`res://comm_system/`)

| 文件 | 类名 | 行数 | 用途 |
|---|---|---|---|
| comm_manager.gd | CommManager | 1466 | 对话编排、通话路由、教程入口（Day0 由 DailyDialogue 驱动）、对话链续播（目标声明 call_mode 时响铃）、场景邮件投递、拨号条件选择、`comm` 命令处理 |
| comm_ui.gd | CommUI | 1353 | 通讯覆盖层 UI（对话条、卡片/会议/演示模式、历史记录） |
| dial_manager.gd | DialManager | 839 | DTMF 拨号状态机、语音通话路由、调制解调器下载与任务登记、电话簿 |
| comm_character.gd | CommCharacter | 446 | 轻量角色数据模型（身份/语音/状态，委托给 animator） |
| character_asset_library.gd | CharacterAssetLibrary | 560 | 素材配置库、模块化纹理加载（res:// + 虚拟 FS） |
| character_animator.gd | CharacterAnimator | 387 | 动画引擎（口型/眨眼/动作帧/图层覆盖/服装） |
| comm_dialogue_player.gd | CommDialoguePlayer | 400 | 对话播放引擎（逐行/选项/条件/幻灯片/静默停止/行级 story_action/meeting 模式延续） |
| dial_tone_generator.gd | DialToneGenerator | 376 | 程序化音频：DTMF 按键/回铃/忙音/调制解调器/挂断/来电铃声 |
| character_registry.gd | CharacterRegistry | 318 | 角色生命周期、注册（内置/故事盘/Mod 来源） |
| presentation_overlay.gd | PresentationOverlay | 295 | 演示模式幻灯片覆盖层（图片显示/适配/对齐/过渡） |
| comm_voice.gd | CommVoice | 106 | 逐字符短音：谐波混合、包络、角色配置、中英文标点静音 |
| voice_tuner.gd | VoiceTuner | 229 | 编辑器调音覆盖层、实时滑块、循环试听、保存角色预设 |
| comm_sprite_renderer.gd | — | 181 | 角色精灵渲染（卡片模式） |

### Mod 系统 (`res://modder/`)

| 文件 | 类名 | 行数 | 用途 |
|---|---|---|---|
| mod_api.gd | ModAPI | 1075 | 沙盒 API：16 类功能（输出/文件/命令/音频/效果/通讯/环境等） |
| mod_base.gd | ModBase | 92 | Mod 基类：生命周期钩子 + 事件回调 |

### 文档模板 (`res://templates/`)

| 文件 | 行数 | 用途 |
|---|---|---|
| article_viewer.gd | 466 | 文章样式文档模板（单页滚动） |
| chat_viewer.gd | 823 | 聊天记录模板（多角色对话） |
| email_viewer.gd | 788 | 邮件模板（含发件人信息栏） |
| two_page_reader.gd | 571 | 双页书籍模板（左/右翻页） |

## 着色器 (Shaders)

| 文件 | 用途 |
|---|---|
| shaders/crt_effect.gdshader | CRT 后处理（扫描线/弯曲/色差/噪声/亮度/抖动偏移） |
| shaders/background_vignette.gdshader | 背景暗角效果 |
| shaders/background_logo.gdshader | SCP logo 背景效果 |
| camera_system/camera_effect.gdshader | CCTV 监控着色器：深度视差(POM)/3 种照明/噪声/扫描线/信号干扰/异常混合 |

## 环境监测系统 (Environment Monitoring System)

### 架构
```
env_monitor.gd (EnvMonitor) — Core simulation + data generation
├─ 21 sensors with Sakhalin baselines (monthly averages)
├─ 6 derived parameters: dew_point, wind_chill, heat_index, feels_like, beaufort, pressure_tendency
├─ Inter-sensor physical correlations (pressure→wind→precipitation→visibility→wave height)
├─ System clock sync (real time drives diurnal cycles, fictional dates displayed)
├─ Weather pattern system (8 patterns, pressure-tendency-driven transitions)
├─ Special event system (storms, magnetic anomalies, SCP events)
├─ Anomaly detection engine (threshold + deviation checks)
├─ Tidal model (real-time phase calculation), wind direction simulation
└─ Story pack overrides via manifest "env_config" section

env_task_manager.gd (EnvTaskManager) — Daily task checklist
├─ Legacy task IDs + observation snapshots / 30 reports
├─ Task dependency system (report requires all readings)
├─ Dynamic special tasks (injected by events/mods)
├─ Formatted output generators for each task type
├─ First daily report +1 daily, Day0 story scoring, no per-step bonus
└─ Day advancement gating (all tasks + report required)

env_viewer.gd (EnvViewer) — CRT overlay panel
├─ 2 maps + 6 detailed sensor pages + report history
├─ Derived parameters display (feels_like, dew_point, beaufort, pressure_tendency)
├─ Real-time sensor readings with trend indicators
├─ Mini sparkline graphs from reading history
├─ Anomaly blink indicators
└─ Keyboard: ←/→ pages, TAB next, Q/ESC close
```

### 传感器（21 个参数）

| 类别 | 传感器 ID |
|---|---|
| 大气 (atmosphere, 10) | air_temp, humidity, pressure, wind_speed, wind_dir, precipitation, visibility, cloud_cover, light_level, uv_index |
| 海洋 (ocean, 4) | sea_temp, tide_level, wave_height, salinity |
| 地球物理 (geophysics, 5) | mag_field, mag_declination, radiation, seismic, soil_temp |
| 大气成分 (composition, 2) | o2_concentration, co2_concentration |

### 派生参数（6 个，由传感器读数交叉计算）

| 参数 | 公式 | 依赖传感器 |
|---|---|---|
| 露点温度 (dew_point) | Magnus 公式 | air_temp, humidity |
| 风寒指数 (wind_chill) | 加拿大标准 (T<10°C, V>4.8km/h) | air_temp, wind_speed |
| 热指数 (heat_index) | Rothfusz 回归 (T>27°C, RH>40%) | air_temp, humidity |
| 体感温度 (feels_like) | 低温=风寒，高温=热指数，中间=实际 | air_temp, humidity, wind_speed |
| 蒲福风级 (beaufort) | 标准 0-12 级分级 | wind_speed |
| 气压趋势 (pressure_tendency) | 3h 滑动窗口: ±3.5hPa=急变 | pressure (历史) |

### 传感器间物理关联
- 气压下降 → 风速增大 (+10%~30%)
- 高湿度 + 低温 → 能见度降低（雾效应）
- 降水增加 → 能见度进一步降低
- 强风 (>10m/s) → 浪高增加

### 时间系统
- **系统时钟同步**：`current_hour` 每帧从 `Time.get_time_dict_from_system()` 读取
- **虚构日期**：`fictional_year/start_month/start_day` 配置起始日期，`current_day` 递增偏移
- **天数推进**：仅在所有每日任务完成 + 游戏重启/重新登录时推进
- **潮汐相位**：由当前真实小时直接计算 `fmod(hour / 12.42, 1.0) * TAU`
- **天气切换**：真实秒数计时（默认 45 分钟切换一次），由气压趋势影响方向

### 数据生成机制
- 主种子 + 天数 → 确定性每日数据
- 月均基准线按季节过渡插值
- 昼夜曲线（sin/cos 插值，温度 14:00 峰值，湿度反向），由系统时钟驱动
- 天气修正（8 种模式，气压趋势驱动切换）
- 事件修正（可叠加，有持续时间）
- 传感器校准漂移模拟 + 故障率
- 半日潮汐模型（12.42 小时周期），由真实时间驱动
- 基于太阳角度的光照/UV 计算
- 交叉关联：读数生成后应用物理约束

### 故事包集成
Manifest 键名：`"env_config"` — 支持覆盖：`location`、`sensors`、`baselines`、`weather_patterns`、`anomaly_types`、`events`、`tasks`、`master_seed`。

## 绩效评分系统 (Performance Scoring System)

### 架构
```
performance_manager.gd (PerformanceManager)
├─ Three score categories: main (主线), daily (日常), side (支线)
├─ Daily quota system with overtime gap carry-over
├─ 4-day period reporting cycle (auto-mail)
├─ Warning escalation: email → AVA call → termination
├─ Career statistics tracking (total scores, overtime, warnings)
└─ Save/load to saves/{username}/performance.json
```

### 评分机制
- `add_score(amount, category)`: 有加班缺口时先填补缺口（记入加班绩效），剩余计入正常类别
- `settle_day(day)`: 结算日绩效，不达标产生缺口，触发警告升级
- 每 4 天自动投递绩效报告邮件
- DayConfig 可通过 `"performance": {"min_quota": N}` 覆盖当日配额

### 警告升级
| 级别 | 触发条件 | 动作 |
|---|---|---|
| low | 首次不达标 | 自动邮件（总部温和提醒） |
| serious | 连续不达标 | 自动邮件 + AVA 来电警告 |
| termination | 严重持续不达标 | 故事标记 `performance_termination` + 终端警告 |

### 集成点
- `env_task_manager`: 首次日报／特殊任务 → `add_score(1, "daily")`，基础采集不逐项计分（Day 0 教程日屏蔽自动计分，分数由对话 `story_action` 提供）
- `trigger_system`: `score:N` / `score:N:category` / `perf_warning:level:msg` 动作
- `daily_dialogue_manager`: DayConfig `"performance"` 节覆盖配额；剧情版本门控（`story.version` 不匹配重置存档）
- `comm_system`: 对话 `story_action`（行级加分）、`deliver_mail`（场景邮件）、`next`（对话链）
- `main.gd`: 登录时加载、结算、保存绩效数据

### ModAPI 环境扩展接口
```gdscript
api.env_get_reading(sensor_id)       # Float reading
api.env_get_all_readings()           # Dict of all readings
api.env_get_weather()                # Weather name
api.env_get_day()                    # Current day number
api.env_get_hour()                   # Current game hour
api.env_get_sensor_status(sensor_id) # "online"/"degraded"/"offline"
api.env_get_active_events()          # Active events dict
api.env_inject_event(id, config)     # Add event definition
api.env_force_event(id)              # Force-start event
api.env_add_task(id, data)           # Add special task
api.env_get_progress()               # Task progress dict
api.env_can_advance()                # Can advance day?
api.env_get_anomalies()              # Pending anomalies
```

## 文件索引（按行数排序）

```
scripts/command_handler.gd|3397  scripts/main.gd|2371  scripts/latex_renderer.gd|1734
radio/radio_receiver.gd|1804  scripts/decode_viewer.gd|1461
env_system/env_monitor.gd|1522
comm_system/comm_ui.gd|1353  scripts/crtml_parser.gd|1325  comm_system/comm_manager.gd|1466
modder/mod_api.gd|1075  settings/settings_manager.gd|903
scripts/mail_system.gd|958  scripts/user_manager.gd|852  comm_system/dial_manager.gd|839
templates/chat_viewer.gd|823  scripts/oscilloscope.gd|820
scripts/package_manager.gd|817  scripts/boot_sequence.gd|809
templates/email_viewer.gd|788  scripts/video_player.gd|750
scripts/trigger_system.gd|754  scripts/story_loader.gd|708
scripts/disc_manager.gd|751  env_system/env_task_manager.gd|841
scripts/document_viewer.gd|668  camera_system/camera_viewer.gd|689
scripts/image_viewer.gd|634  scripts/audio_manager.gd|586
scripts/cipher_decoder.gd|584  templates/two_page_reader.gd|571
env_system/env_viewer.gd|821  scripts/loading_screen.gd|543
scripts/typewriter.gd|540  scripts/theme_manager.gd|517
scripts/explore_viewer.gd|481  scripts/file_system.gd|535
scripts/vdisc_task_manager.gd|640
scripts/ui_manager.gd|466  templates/article_viewer.gd|466
scripts/effect_system.gd|451  camera_system/camera_manager.gd|444
comm_system/comm_character.gd|446  comm_system/character_asset_library.gd|560
scripts/crt_shader.gd|416  scripts/daily_dialogue_manager.gd|556
comm_system/character_animator.gd|387  comm_system/comm_dialogue_player.gd|400
comm_system/dial_tone_generator.gd|376  scripts/morse_engine.gd|347
radio/radio_signal_manager.gd|344  camera_system/camera_feed.gd|927
radio/radio_config_parser.gd|319  radio/radio_audio_generator.gd|311
scripts/sstv_decoder.gd|310  radio/radio_data_manager.gd|302
comm_system/character_registry.gd|318  comm_system/presentation_overlay.gd|295
comm_system/call_handler.gd|328  scripts/header_parser.gd|247
scripts/profile_builder.gd|253  scripts/save_manager.gd|228
settings/settings_registry.gd|225  scripts/ui_sound.gd|200
comm_system/comm_voice.gd|106  comm_system/comm_sprite_renderer.gd|181
comm_system/voice_tuner.gd|229
scripts/effect_settings.gd|175  settings/settings_storage.gd|165
modder/mod_base.gd|92
总计: ~41,225 行
```

## 模块状态 (Module Status)

| 模块 | 状态 | 说明 |
|---|---|---|
| 核心终端 | ✅ 完成 | CLI 输入/输出、主题、CRT 效果 |
| 虚拟文件系统 | ✅ 完成 | 目录树、权限、安全等级 |
| 故事加载 | ✅ 完成 | ZIP 解析、GBK 编码支持 |
| 用户系统 | ✅ 完成 | 多用户、个人资料、统计 |
| 存档系统 | ✅ 完成 | 每用户每故事独立存档 |
| 通讯系统 | ✅ 完成 | 对话/角色/来电模式(SILENT/FORCED/ANSWERABLE)/卡片/会议/演示/分层精灵/历史/视频 |
| 邮件系统 | ✅ 完成 | 收件箱、延迟投递、持久/临时、内联投递 |
| 无线电系统 | ✅ 完成 | 调谐/摩斯码/SSTV/音频电台/隐藏信号/瀑布图/渐进感知 |
| Mod 系统 | ✅ 完成 | 安装/卸载、生命周期、16 类 API |
| 设置系统 | ✅ 完成 | 注册式、TUI 界面、导入/导出 |
| 触发器系统 | ✅ 完成 | 28 种事件驱动动作 |
| 效果系统 | ✅ 完成 | 时间轴效果序列、预设 |
| 查看器 | ✅ 完成 | 图片/音频/视频/密码解码/文件探索 |
| CRTML 解析 | ✅ 完成 | 完整标记解析器（结构/格式/效果/媒体） |
| 拨号系统 | ✅ 完成 | DTMF/语音路由/调制解调器握手下载/电话簿 |
| 环境监测 | ✅ 完成 | 21 传感器/天气/事件/异常/每日任务/仪表盘 |
| 摄像头系统 | ✅ 完成 | CCTV 监控：底图/深度/照明/异常/shader 管线/3 种照明/POM 视差/触发器集成 |
| 每日对话 | ✅ 完成 | 7 种触发钩子/故事标记/选择持久化/对话扩展加载 |


## ENV 观测台新增组件（2026-10-01，待人工验收）

| 文件 | 类 | 行数 | 职责 |
|---|---|---|---|
| env_system/env_observation.gd | EnvObservation | 295 | 短采集、复测、日报、旧存档迁移、隔离预览 |
| env_system/env_map_canvas.gd | EnvMapCanvas | 227 | 两种监视盘、SVG 底图入口与方形占位、简报、来源与历史绘制 |

main → EnvObservation → EnvMonitor / EnvTaskManager；EnvViewer → EnvMapCanvas。采集数据存入任务进度；DailyDialogueManager.process_pending 串行播放等待覆盖界面结束的通讯。配置和验收见 docs/upgrade-plans/environment-manual-test-plan.md。
