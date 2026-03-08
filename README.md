# SCRT-Reader

**SCP CRT Terminal Reader** — 一款基于 Godot 4.6 引擎构建的复古 CRT 终端风格阅读器。玩家以操作员身份登录虚拟终端系统，通过命令行交互浏览"虚拟磁盘"（故事包）中的文档、音频、图像、视频等多媒体内容。内置环境监测站模拟、CCTV 监控摄像头、无线电接收器、通讯对话等多种交互系统。支持模组（Mod）扩展和自定义故事包制作。

---

## 目录

1. [项目概述](#项目概述)
2. [系统架构](#系统架构)
3. [功能介绍](#功能介绍)
4. [操作说明](#操作说明)
5. [故事包制作指南](#故事包制作指南)
6. [CRTML 标记语言](#crtml-标记语言)
7. [模组开发指南](#模组开发指南)
8. [目录结构](#目录结构)
9. [技术规格](#技术规格)

---

## 项目概述

SCRT-Reader 模拟了一台 20 世纪风格的 CRT 终端计算机。用户通过命令行操作虚拟文件系统，阅读文档、解密文件、收听无线电信号、查看 SSTV 图像、监控摄像头画面、管理环境监测站数据，以及与 AI 角色进行通讯对话。

### 核心特性

- **CRT 复古视觉效果**：扫描线、色差、屏幕弯曲、屏幕闪烁等可配置着色器效果
- **完整终端模拟**：命令行输入、文件系统浏览、密码保护、权限等级
- **故事包系统**：通过 `.scp` 格式的虚拟磁盘加载不同的故事内容
- **多媒体支持**：文档查看、图片查看器、音频播放器、视频播放器、示波器
- **无线电接收器**：模拟调频/调幅无线电，支持摩尔斯码解码和 SSTV 图像接收
- **通讯系统**：与虚拟角色进行对话交互，支持立绘和语音合成
- **拨号系统**：DTMF 拨号、语音通话路由、模拟调制解调器下载
- **邮件系统**：接收和阅读系统/故事邮件
- **环境监测站**：完整的气象/海洋/地球物理传感器模拟，每日任务系统
- **监控摄像头**：CCTV 画面查看，支持深度透视、多种照明模式、异常事件
- **触发器系统**：基于玩家行为自动触发事件（音效、特效、邮件、路径跳转等）
- **模组系统**：支持第三方模组扩展命令、UI、音频等功能
- **多用户系统**：用户注册/登录、个人资料、存档管理
- **设置系统**：注册式设置管理，分类持久化，TUI 交互界面
- **效果安全模式**：三级效果强度 + 光敏安全模式，防止闪烁触发不适
- **主题切换**：多种终端配色方案可选（磷光绿、琥珀色、冷蓝、白色）
- **自动存档**：自动保存阅读进度和系统状态

---

## 系统架构

```
┌──────────────────────────────────────────────────────────────┐
│                      Main (Control)                          │
│         主控制器 - 管理所有子系统的初始化与交互                 │
├──────────┬───────────┬───────────┬───────────────────────────┤
│  UI 层   │  逻辑层    │  数据层   │  扩展层                    │
├──────────┼───────────┼───────────┼───────────────────────────┤
│UIManager │CmdHandler │FileSystem │PackageManager             │
│Typewriter│DiscMgr    │StoryLoader│ModAPI / ModBase           │
│CRTShader │MailSys    │SaveManager│TriggerSystem              │
│EffectSys │CommMgr    │UserManager│SettingsManager            │
│AudioMgr  │DialMgr    │ThemeMgr   │                           │
│BootSeq   │CrtmlParser│           │                           │
├──────────┼───────────┼───────────┤                           │
│ 查看器层  │ 模拟层    │           │                           │
├──────────┼───────────┤           │                           │
│DocViewer │EnvMonitor │           │                           │
│ImgViewer │EnvTaskMgr │           │                           │
│RadioRecv │CameraMgr  │           │                           │
│DecodeView│CameraView │           │                           │
│Oscillosc │DailyDlgMgr│           │                           │
│VideoPlyr │           │           │                           │
│EnvViewer │           │           │                           │
└──────────┴───────────┴───────────┴───────────────────────────┘
```

### 核心子系统

| 子系统 | 脚本文件 | 职责 |
|--------|----------|------|
| **主控制器** | `main.gd` | 系统入口，初始化所有子系统，处理全局输入和 UI 事件 |
| **命令处理器** | `command_handler.gd` | 解析和执行终端命令，管理命令历史和 Tab 补全 |
| **磁盘管理器** | `disc_manager.gd` | 扫描/加载/弹出虚拟磁盘，管理故事生命周期 |
| **故事加载器** | `story_loader.gd` | 解析 `.scp` 文件（ZIP 格式），构建虚拟文件系统 |
| **文件系统** | `file_system.gd` | 虚拟文件树管理，路径操作，权限/密码控制 |
| **CRTML 解析器** | `crtml_parser.gd` | 将 CRTML 标记语言解析为 BBCode 富文本 |
| **邮件系统** | `mail_system.gd` | 邮件发送/接收/阅读，支持定时投递和通知 |
| **触发器系统** | `trigger_system.gd` | 基于事件触发动作（进入目录、打开文件、命令执行等） |
| **通讯系统** | `comm_manager.gd` | 角色对话系统，支持立绘、语音、分支选择 |
| **拨号系统** | `dial_manager.gd` | DTMF 拨号、语音通话路由、模拟调制解调器下载 |
| **无线电接收器** | `radio_receiver.gd` | 全功能无线电模拟，频率调谐、信号接收、解码 |
| **环境监测器** | `env_monitor.gd` | 环境传感器模拟（气象/海洋/地球物理），每日数据生成 |
| **环境任务管理** | `env_task_manager.gd` | 每日巡检任务清单，任务依赖链，天数推进 |
| **摄像头管理器** | `camera_manager.gd` | CCTV 摄像头注册/解锁/异常触发/存档管理 |
| **摄像头查看器** | `camera_viewer.gd` | 全屏监控画面叠加层，Shader 渲染管线 |
| **每日剧情管理** | `daily_dialogue_manager.gd` | 主线剧情推进，每日对话触发，独立存档 |
| **效果系统** | `effect_system.gd` | 时间轴驱动的屏幕特效序列（故障、抖动、黑屏等） |
| **效果安全设置** | `effect_settings.gd` | 三级效果强度 + 光敏安全过滤 |
| **音频管理器** | `audio_manager.gd` | 环境音、音效、媒体播放、音频频谱分析 |
| **设置管理器** | `settings_manager.gd` | 注册式设置管理，分类存储，TUI 交互 |
| **主题管理器** | `theme_manager.gd` | 终端配色方案管理和切换 |
| **用户管理器** | `user_manager.gd` | 用户注册/登录、个人资料、统计数据 |
| **存档管理器** | `save_manager.gd` | 游戏进度存档和加载 |
| **包管理器** | `package_manager.gd` | 模组安装/卸载/生命周期管理 |
| **UI 管理器** | `ui_manager.gd` | 终端 UI 布局、样式、CRT 自定义光标 |

---

## 功能介绍

### 1. 开机引导序列

程序启动后会播放一段可配置的开机动画序列（定义在 `boot_config.json` 中），模拟 BIOS POST 自检、系统加载的全过程。支持以下关键帧动作：

- `screen_off` / `fade_in` — 屏幕开关和淡入
- `text` — 输出文本（支持颜色）
- `progress_bar` — 进度条动画
- `glitch` — 屏幕故障效果
- `scanlines` — 扫描线强度调整
- `beep` — 蜂鸣器音效
- `logo` / `background` — Logo 和背景控制
- `complete` / `quit` — 序列完成/退出

### 2. 用户系统

- **注册**：输入用户名（3-16 字符）和密码
- **登录**：支持自动记住上次登录的用户
- **角色等级**：`operator`（普通操作员）、`admin`（管理员）
- **个人资料**：昵称、生日、头衔、系统笔记
- **统计数据**：命令执行数、文件阅读数、游戏时长

### 3. 桌面模式

登录后默认进入桌面模式。桌面模式下可使用的命令包括：

| 命令 | 说明 |
|------|------|
| `scan` | 扫描可用的虚拟磁盘列表 |
| `load <编号>` | 加载指定编号的虚拟磁盘 |
| `vdisc` | 与 `scan` 功能相同，列出虚拟磁盘 |
| `explore` | 文件浏览器模式 |
| `install <编号>` | 安装指定的模组/故事包 |
| `deluser <用户名>` | 删除指定用户（需管理员权限） |

### 4. 磁盘模式

加载故事包后进入磁盘模式，通过命令行浏览虚拟文件系统：

| 命令 | 说明 |
|------|------|
| `ls` / `dir` | 列出当前目录的文件和子目录 |
| `cd <路径>` | 切换到指定目录 |
| `back` | 返回上级目录 |
| `open <文件名>` / `read` / `cat` | 打开/阅读文件 |
| `unlock <路径>` | 解锁密码保护的目录 |
| `eject` | 弹出当前磁盘 |
| `save` | 手动保存进度 |
| `clearsave` | 清除当前磁盘的存档 |
| `radio` | 打开无线电接收器（如果故事包支持） |
| `decode <文件>` | 对文件进行解码查看 |
| `explore` | 以文件浏览器视图查看文件系统 |

### 5. 全局命令

以下命令在桌面模式和磁盘模式下均可使用：

| 命令 | 说明 |
|------|------|
| `help` | 显示帮助信息 |
| `clear` / `cls` | 清屏 |
| `whoami` | 显示当前用户信息 |
| `status` | 显示系统状态 |
| `mail` | 打开邮件系统 |
| `comm` | 通讯系统 |
| `dial <号码>` | 拨号（语音通话或调制解调器连接） |
| `phonebook` / `pb` | 查看号码簿 |
| `env` | 环境监测系统（`env help` 查看子命令） |
| `camera` / `cam` / `cctv` | 监控摄像头系统（`camera help` 查看子命令） |
| `settings` / `set` | 打开设置界面 |
| `theme` | 切换终端主题 |
| `volume` / `vol` | 调整音量 |
| `fx_level` | 调整视觉效果等级（`full` / `mild` / `off`） |
| `fx_safe` | 光敏安全模式开关 |
| `sound` | 音效设置 |
| `profile` | 查看个人资料 |
| `packages` / `pkg` | 查看已安装的包 |
| `uninstall` | 卸载模组 |
| `logout` | 注销当前用户 |
| `passwd` | 修改密码 |
| `birthday` | 设置生日 |
| `users` | 列出所有用户 |
| `reboot` | 重启终端 |
| `exit` / `quit` | 退出程序 |

### 6. 无线电接收器

完整模拟的无线电接收器界面，支持：

- **波段切换**：AM / FM / SW 等多个波段
- **频率调谐**：手动微调和拖拽调频
- **方位调整**：天线方位角和仰角
- **信号检测**：信号质量指示、信号锁定
- **自动扫描**：自动搜索频段内的信号
- **摩尔斯码解码**：自动解码锁定的摩尔斯码信号
- **SSTV 接收**：接收 SSTV（慢扫描电视）图像信号
- **音频电台**：直接播放音频流广播
- **瀑布图**：实时频谱瀑布图显示
- **雷达视图**：信号源方位可视化
- **渐进感知**：未锁定信号也可部分听到音频，音量随信号质量变化
- **隐藏信号**：需通过特定条件解锁的秘密频率

### 7. 通讯系统

与虚拟角色进行交互式对话：

- **角色立绘**：支持多表情状态和动画
- **语音合成**：模拟的角色说话音效
- **分支对话**：支持选择式对话分支
- **条件触发**：对话可基于特定条件（执行命令、打开文件等）推进
- **教程引导**：内置 AVA 助手角色引导新用户

### 8. 拨号系统

模拟真实的电话/调制解调器体验：

- **DTMF 拨号**：逐位播放双音多频拨号音（真实频率合成）
- **语音通话**：拨打号码后自动路由到通讯对话
- **调制解调器**：模拟握手音序列（载波检测、训练序列）
- **文件下载**：模拟 1200bps 调制解调器下载进度
- **号码簿**：系统内置 + 故事包提供的号码目录
- **状态机**：IDLE → DTMF → RINGING → VOICE/MODEM → ENDED 完整流程

### 9. 环境监测系统

完整的观测站环境监测模拟：

- **21 项传感器**：覆盖气象、海洋、地球物理、大气成分四大类
  - 气象：气温、湿度、气压、风速、风向、降水、能见度、云量、光照、紫外线
  - 海洋：海温、潮位、浪高、盐度
  - 地球物理：磁场强度、磁偏角、辐射、地震、土壤温度
  - 大气成分：氧浓度、二氧化碳浓度
- **数据生成**：基于萨哈林岛气候基线，含昼夜曲线、季节过渡、天气模式
- **天气系统**：8 种天气模式，含季节限制和概率权重
- **特殊事件**：风暴、磁暴、SCP 异常事件（可叠加、有持续时间）
- **传感器故障**：退化/离线模拟，可通过 `env repair` 修复
- **异常检测**：基于阈值和偏差的自动检测引擎
- **每日任务**：巡检 → 记录 → 校准 → 报告的标准流程，完成后推进天数
- **监测面板**：6 页 CRT 风格叠加面板（总览/气象/海洋/地物/成分/事件）

#### 环境监测命令

| 命令 | 说明 |
|------|------|
| `env status` | 显示所有传感器当前读数 |
| `env view` | 打开监测面板叠加层 |
| `env tasks` | 查看每日任务清单 |
| `env check` | 设备状态巡检 |
| `env read <类别>` | 记录传感器数据（atmosphere/ocean/geophysics/composition） |
| `env calibrate` | 校准仪器 |
| `env anomaly` | 检查并确认异常 |
| `env report` | 提交每日报告 |
| `env repair <传感器>` | 修复离线传感器 |
| `env advance` | 推进到下一天（需完成所有任务） |
| `env sensor <ID>` | 查看单个传感器详情 |
| `env weather` | 查看天气状况 |
| `env events` | 查看活跃事件 |

### 10. 监控摄像头系统

CCTV 监控画面查看与异常事件系统：

- **多摄像头管理**：每个故事包可定义多个摄像头，独立解锁/上线状态
- **底图 + 深度图**：伪 3D 透视效果，镜头平移时近景快、远景慢
- **三种照明模式**：
  - `spotlight` — 聚光灯照明，circle mask 衰减
  - `nightvision` — 夜视仪效果，画面整体绿色
  - `infrared` — 红外热成像，伪彩色热力图（蓝→青→绿→黄→红）
- **Shader 渲染管线**：噪点/扫描线/暗角/信号干扰/雪花点/色彩压缩
- **异常事件**：随机或剧情触发，异常图平滑混合叠加，可附带 glitch/shake 效果
- **信号质量**：可动态调整，信号下降时噪点自动增加
- **安全模式兼容**：异常视觉效果受 `fx_level` 控制，剧情触发器不受影响

#### 摄像头命令

| 命令 | 说明 |
|------|------|
| `camera list` | 列出所有已解锁摄像头 |
| `camera view [编号/ID]` | 打开摄像头查看器 |
| `camera status` | 显示所有摄像头状态 |

### 11. 文档查看模板

支持多种文档呈现模板：

| 模板 | 说明 |
|------|------|
| `article_viewer` | 文章查看器 — 长文阅读 |
| `chat_viewer` | 聊天记录查看器 — 即时通讯风格 |
| `email_viewer` | 邮件查看器 — 邮件格式展示 |
| `two_page_reader` | 双页阅读器 — 翻页式文档 |

### 12. 视觉效果系统

丰富的 CRT 屏幕效果：

- **故障 (Glitch)**：屏幕画面错位/像素化
- **抖动 (Shake)**：屏幕抖动
- **撕裂 (Tear)**：画面撕裂
- **噪声 (Noise Burst)**：噪声爆发
- **黑屏 (Screen Off)**：屏幕关闭效果
- **色差 (Chromatic)**：色差偏移
- **亮度变化 (Brightness)**：亮度闪烁
- **预设效果**：`unease`（不安）、`disturb`（干扰）、`jumpscare`（惊吓）、`crash`（崩溃）

效果可通过故事包的 manifest 定义自定义时间轴序列。

#### 效果安全设置

系统内置三级效果强度和光敏安全模式：

| 等级 | 效果强度 | 说明 |
|------|---------|------|
| `full` | 100% | 完整效果（默认） |
| `mild` | 40% | 减弱效果强度和持续时间 |
| `off` | 0% | 完全关闭视觉效果 |

**光敏安全模式**（`fx_safe on`）独立于效果等级，会额外过滤可能引发光敏性不适的效果类型（如 `jumpscare`、`flicker`、`blackout`、`noise_burst` 等），但不影响剧情推进。

### 13. 设置系统

注册式的统一设置管理：

- **分类管理**：显示、音频、效果、终端等分类
- **类型支持**：布尔值、整数、浮点数、字符串、枚举
- **约束验证**：最小/最大值、步长限制
- **持久化存储**：用户级和全局级独立存储
- **TUI 交互**：终端内的设置浏览和修改界面

---

## 操作说明

### 键盘操作

| 按键 | 功能 |
|------|------|
| `Enter` | 提交命令 |
| `↑` / `↓` | 浏览命令历史 |
| `Tab` | 命令和路径自动补全 |
| `Ctrl+C` | 复制终端选中文本 |
| `Ctrl+L` | 清屏 |
| `Escape` | 关闭当前查看器/退出当前模式 |
| `Page Up` / `Page Down` | 滚动终端输出 |

### 无线电接收器操作

| 按键 | 功能 |
|------|------|
| `←` / `→` | 微调频率 |
| `Shift + ←/→` | 大幅调频 |
| `↑` / `↓` | 调整天线方位 |
| `B` | 切换波段 |
| `S` | 自动扫描 |
| `L` | 查看信标日志 |
| `+` / `-` | 调整音量 |
| `Q` / `Escape` | 关闭无线电 |

### 通讯系统操作

| 按键 | 功能 |
|------|------|
| `Space` / `Enter` | 推进对话 |
| `1-9` | 选择对话分支 |
| `Escape` | 关闭通讯 |

### 环境监测面板操作

| 按键 | 功能 |
|------|------|
| `←` / `→` | 切换页面 |
| `Tab` | 下一页 |
| `Q` / `Escape` | 关闭面板 |

### 监控摄像头操作

| 按键 | 功能 |
|------|------|
| `←` / `→` / `↑` / `↓` | 平移镜头 |
| `1-9` | 快速切换摄像头编号 |
| `Tab` | 切换下一个在线摄像头 |
| `Q` / `Escape` | 关闭查看器 |

---

## 故事包制作指南

### 故事包格式

故事包是一个 `.scp` 文件，实质上是一个 **ZIP 压缩包**（仅修改扩展名为 `.scp`）。将故事包放入 `vdisc/` 目录即可被系统扫描到。

### 配置文件格式

系统同时支持两种配置格式：

| 文件名 | 格式 | 说明 |
|--------|------|------|
| `manifest.json` | JSON | 推荐，支持嵌套结构，便于配置复杂系统 |
| `manifest.cfg` | INI | 兼容格式，适合简单故事包 |

两者可任选其一，同时存在时均会被解析。

### 目录结构

```
my_story.scp (ZIP)
├── manifest.json         # 推荐：JSON 格式故事配置
├── manifest.cfg          # 或者：INI 格式故事配置
├── data/                 # 虚拟文件系统根目录
│   ├── documents/
│   │   ├── readme.txt
│   │   └── report.crtml
│   ├── images/
│   │   └── photo.png
│   ├── audio/
│   │   └── ambient.ogg
│   ├── videos/
│   │   └── tape.ogv
│   └── cameras/          # 可选：摄像头素材
│       └── hallway_01/
│           ├── base.png
│           ├── depth.png
│           └── light.png
├── mail/                 # 可选：邮件定义
│   └── inbox.json
├── radio/                # 可选：无线电信号定义
│   └── signals.json
├── comm/                 # 可选：通讯对话定义
│   ├── characters.json
│   └── dialogues.json
└── effects/              # 可选：自定义视觉效果
    └── effects.json
```

### manifest.json 配置（推荐）

```json
{
  "story": {
    "id": "my_story_id",
    "title": "我的故事",
    "author": "作者名",
    "description": "故事描述",
    "version": "1.0.0"
  },
  "settings": {
    "initial_path": "/",
    "player_clearance": 1
  },
  "passwords": {
    "/secret": "mypassword123",
    "/classified/files": "topsecret"
  },
  "file_passwords": {
    "/documents/encrypted.txt": "decrypt_key"
  },
  "hidden_dirs": ["/hidden", "/system/.internal"],
  "ambient": {
    "/documents": "ambient_hum",
    "/": "base_static"
  },
  "headers": {
    "/": "[color=#88ff88]欢迎访问数据库[/color]",
    "/documents": "[color=#ffaa44]文档存储区[/color]"
  },
  "descriptions": {
    "/documents/readme.txt": "入门指南",
    "/images/photo.png": "现场照片"
  },
  "folder_descriptions": {
    "/documents": "包含所有文档文件"
  },
  "triggers": {
    "/secret": {
      "on_first_enter": "new_mail:warning_mail | sound:sfx/alert.ogg"
    },
    "/documents": {
      "on_open_file:classified.txt": "sound:alert.ogg",
      "on_read_complete:report.crtml": "level_up:2",
      "on_command:help": "comm:tutorial_help",
      "on_idle:30": "text:系统闲置中..."
    }
  },
  "effects": {
    "custom_scare": [
      {"time": 0, "type": "glitch", "intensity": 1.0, "duration": 0.5},
      {"time": 0.3, "type": "shake", "intensity": 0.02, "duration": 0.3}
    ]
  },
  "env_config": {
    "location": {"name": "OB-7K", "lat": 50.0, "lon": 143.0},
    "master_seed": 42
  },
  "camera_system": {
    "cameras": {
      "cam_hallway_01": {
        "name": "走廊监控 #1",
        "location": "东翼走廊 B2F",
        "unlocked": false,
        "online": true,
        "base_image": "cameras/hallway_01/base.png",
        "depth_map": "cameras/hallway_01/depth.png",
        "light_mode": "spotlight",
        "light_image": "cameras/hallway_01/light.png",
        "signal_quality": 0.85,
        "anomalies": [
          {
            "id": "shadow_figure",
            "image": "cameras/hallway_01/anomaly_shadow.png",
            "trigger": "random",
            "probability": 0.03,
            "duration": 3.0,
            "min_interval": 120.0,
            "effects": ["glitch:0.4"],
            "action": "sound:sfx/static.ogg"
          }
        ]
      }
    }
  }
}
```

### manifest.cfg 配置（兼容格式）

`manifest.cfg` 使用类 INI 格式，适合不需要复杂嵌套配置的简单故事包：

```ini
[story]
id = my_story_id
title = 我的故事
author = 作者名
description = 故事描述
version = 1.0.0

[settings]
initial_path = /
player_clearance = 1

[passwords]
/secret = mypassword123

[file_passwords]
/documents/encrypted.txt = decrypt_key

[hidden_dirs]
dirs = /hidden, /system/.internal

[ambient]
/documents = ambient_hum

[headers]
/ = [color=#88ff88]欢迎访问数据库[/color]

[triggers]
enter:/secret = action:new_mail:warning_mail
open:/documents/classified.txt = action:sound:alert.ogg
```

> **注意**：环境监测系统（`env_config`）和摄像头系统（`camera_system`）等复杂嵌套配置仅在 `manifest.json` 中支持。

### 触发器系统详解

触发器在 manifest.json 中按目录路径分组，每个目录可定义多个触发条件：

#### 事件类型

| 事件 | 说明 | 默认行为 |
|------|------|---------|
| `on_enter` | 进入目录时触发 | 可重复 |
| `on_first_enter` | 首次进入目录时触发 | 仅一次 |
| `on_open_file:<文件名>` | 打开指定文件时触发 | 仅一次 |
| `on_read_complete:<路径>` | 阅读完指定文件后触发 | 仅一次 |
| `on_command:<命令>` | 执行指定命令时触发 | 可重复 |
| `on_level_reach:<等级>` | 安全等级达到时触发 | 仅一次 |
| `on_idle:<秒数>` | 空闲指定秒数后触发 | 仅一次 |

事件可添加 `.once` 或 `.repeat` 修饰符覆盖默认行为（如 `on_enter.once` 强制只触发一次）。

#### 动作类型

多个动作可用 `|` 分隔，同时执行：

| 动作 | 说明 |
|------|------|
| `new_mail:<邮件ID>` | 投递邮件 |
| `level_up:<等级>` | 提升安全等级 |
| `sound:<文件路径>` | 播放音效 |
| `text:<文本>` | 输出文本 |
| `redirect:<路径>` | 跳转目录 |
| `glitch:<强度>` | 屏幕故障 |
| `shake:<强度>` | 屏幕抖动 |
| `tear:<强度>` | 画面撕裂 |
| `noise_burst:<强度>` | 噪声爆发 |
| `screen_off:<时长>` | 屏幕关闭 |
| `reboot` | 重启终端 |
| `play_effect:<效果ID>` | 播放自定义效果 |
| `preset_effect:<预设名>` | 播放预设效果 |
| `lock_folder:<路径>` | 锁定目录 |
| `unlock_folder:<路径>` | 解锁目录 |
| `color_scheme:<主题>` | 切换配色 |
| `comm:<对话ID>` | 触发通讯对话 |
| `camera_unlock:<摄像头ID>` | 解锁摄像头 |
| `camera_lock:<摄像头ID>` | 锁定摄像头 |
| `camera_online:<摄像头ID>` | 使摄像头上线 |
| `camera_offline:<摄像头ID>` | 使摄像头下线 |
| `camera_anomaly:<摄像头ID>[:<异常ID>]` | 触发摄像头异常 |
| `camera_signal:<摄像头ID>:<质量>` | 设置信号质量（0-1） |

### 文件格式支持

| 类型 | 支持的格式 |
|------|-----------|
| 文本 | `.txt`, `.md`, `.log`, `.cfg`, `.ini`, `.json`, `.xml`, `.html`, `.csv`, `.crtml` |
| 图片 | `.png`, `.jpg`, `.jpeg`, `.bmp`, `.webp`, `.svg` |
| 音频 | `.ogg`, `.wav`, `.mp3` |
| 视频 | `.ogv` |

### CRTML 文件特殊说明

`.crtml` 是项目专用的富文本标记格式（详见下一章节），支持在文本文件内嵌入格式化标记。

---

## CRTML 标记语言

CRTML（CRT Markup Language）是 SCRT-Reader 的专用标记语言，用于在终端中呈现富文本内容。它类似 Markdown，但做了终端适配优化。

### 基本语法

#### 标题
```
# 一级标题
## 二级标题
### 三级标题
#### 四级标题
```

#### 文本格式化
```
**粗体文本**
*斜体文本*
~~删除线文本~~
`行内代码`
||剧透文本||（点击揭示）
```

#### 引用
```
> 这是引用文本
```

#### 分隔线
```
---
***
___
```

#### 分页符
```
===
```
当文件中出现分页符时，将使用分页查看器呈现内容。

#### 代码块
````
```
这是代码块
代码块内的内容不会被解析
```
````

#### 表格
```
| 列1 | 列2 | 列3 |
|-----|-----|-----|
| A   | B   | C   |
```

#### SCP 标记
```
[SCP-173] → 自动高亮为 SCP 编号样式
```

#### 黑条遮挡
```
[BLACKOUT:被遮挡的文本]
[BLACK:█████████████]
```

### 内嵌媒体

CRTML 使用 `![类型|参数](路径)` 语法嵌入多媒体内容：

#### 图片
```
![image](images/photo.png)
![image|width=40](images/photo.png)
![image|width=30|height=10](images/photo.png)
```

#### 音频
```
![audio](audio/recording.ogg)
```
终端中将显示播放控件，点击可切换播放/暂停。

#### 视频
```
![video](videos/tape.ogv)
```

### 链接
```
{link:目标路径|显示文本}
```
点击链接可跳转到文件系统中的对应文件/目录。

### 颜色

#### 主题色名称引用
```
{color:primary}主色文本{/color}
{color:error}错误文本{/color}
```
可用名称：`primary`、`secondary`、`dim`、`success`、`warning`、`error`、`info`、`muted`

#### 格式标签
```
{b}粗体{/b}  {i}斜体{/i}  {u}下划线{/u}  {s}删除线{/s}
```

### 布局标签
```
{center}居中文本{/center}
{right}右对齐文本{/right}
```

### 特效标签

CRTML 支持在文本中嵌入特效标签，在打字机输出到对应位置时自动触发：

#### 打字机控制
```
{speed=2.0}加速输出的文本{/speed}
{delay=500}              （暂停 500 毫秒）
{pause=1000}             （暂停 1000 毫秒）
{clear}                  （清屏）
{noskip}不可跳过的文本{/noskip}
```

#### CRT 屏幕效果
```
{glitch}故障效果中的文本{/glitch}
{glitch=0.8}强故障{/glitch}
{screen_shake}抖动中的文本{/screen_shake}
{screen_shake=0.02}强抖动{/screen_shake}
{tear}撕裂效果{/tear}
{noise}噪声效果{/noise}
```

#### 触发效果
```
{effect=custom_scare}    （触发 manifest 中定义的命名效果）
{preset=unease}          （触发内置预设效果）
{sound=audio/alert.ogg}  （播放音效）
```

#### 富文本动画
```
{shake}抖动文字{/shake}
{wave}波浪文字{/wave}
{rainbow}彩虹文字{/rainbow}
{fade}渐隐文字{/fade}
```

---

## 模组开发指南

### 概述

SCRT-Reader 支持通过模组系统扩展功能。模组以 `.scp` 文件打包，在 manifest 中声明类型为 `package` 或 `mod`，通过 `install` 命令安装。

### 模组包结构

```
my_mod.scp (ZIP)
├── manifest.cfg
├── main.gd           # 模组主脚本，必须继承 ModBase
├── assets/           # 模组资源文件
│   ├── sounds/
│   └── images/
└── data/             # 模组数据文件
```

### manifest.cfg（模组类型）

```ini
[story]
id = my_mod_id
title = 我的模组
author = 模组作者
description = 模组描述
version = 1.0.0
type = mod

[mod]
main_script = main.gd
```

### 模组基类 (ModBase)

所有模组的主脚本必须继承 `ModBase`。以下是可重写的生命周期函数：

```gdscript
extends ModBase

## 首次安装时调用（只调用一次）
func _on_install() -> void:
    pass

## 卸载时调用
func _on_uninstall() -> void:
    pass

## 每次启用时调用（登录后恢复、或刚安装后）
func _on_enable() -> void:
    pass

## 禁用时调用（用户注销）
func _on_disable() -> void:
    pass

## 注册命令（在 _on_enable 之前自动调用）
func _register_commands() -> void:
    pass

## 每帧更新
func _process(delta: float) -> void:
    pass
```

### 事件钩子

模组可重写以下钩子函数来拦截或响应系统事件：

```gdscript
## 命令执行前（返回 true 阻止命令执行）
func _on_before_command(cmd: String, args: Array) -> bool:
    return false

## 命令执行后
func _on_after_command(cmd: String, args: Array) -> void:
    pass

## 目录切换
func _on_directory_changed(old_path: String, new_path: String) -> void:
    pass

## 文件打开前（返回 true 阻止默认打开行为）
func _on_before_file_open(file_path: String) -> bool:
    return false

## 文件打开后
func _on_after_file_open(file_path: String) -> void:
    pass

## 磁盘加载后
func _on_disc_loaded(story_id: String, manifest: Dictionary) -> void:
    pass

## 磁盘弹出后
func _on_disc_ejected() -> void:
    pass

## 模式切换（桌面 ↔ 磁盘）
func _on_mode_changed(is_desktop: bool) -> void:
    pass

## 跨模组消息
func _on_mod_message(from_mod_id: String, data: Dictionary) -> void:
    pass

## 用户登录后
func _on_user_login(username: String) -> void:
    pass

## 用户注销前
func _on_user_logout(username: String) -> void:
    pass
```

### ModAPI 接口

通过 `api` 属性访问模组 API，提供以下功能分类：

#### 一、输出系统
```gdscript
api.output(text)                    # 即时输出（支持 BBCode）
api.output_typed(text)              # 打字机效果输出
api.output_colored(text, color_key) # 带颜色的输出
api.output_silent(text)             # 输出不带 beep 音效
api.clear_screen()                  # 清屏
api.wait_for_typewriter()           # 等待打字机完成
api.build_box(lines, color_hex)     # 构建装饰框
api.get_theme_colors()              # 获取主题颜色字典
```

#### 二、命令注册
```gdscript
# 注册命令 mode: "global" / "desktop" / "disc"
api.register_command(name, description, handler, mode)
api.unregister_command(name)        # 注销命令
api.execute_command(raw_command)    # 执行命令（模拟用户输入）
```

#### 三、系统状态查询
```gdscript
api.get_current_path()              # 当前文件系统路径
api.get_username()                  # 当前用户名
api.get_user_role()                 # 当前用户角色
api.is_desktop_mode()               # 是否桌面模式
api.get_clearance()                 # 当前安全等级
api.get_story_id()                  # 当前故事 ID
api.get_story_manifest()            # 当前故事 manifest
api.get_read_files()                # 已读文件列表
api.get_visited_paths()             # 已访问路径列表
api.get_unlocked_passwords()        # 已解锁密码列表
api.is_command_running()            # 命令是否正在执行
```

#### 四、文件系统
```gdscript
api.get_fs_children(path)           # 获取子项列表
api.read_fs_file(path)              # 读取文件内容
api.get_fs_node(path)               # 获取节点信息
api.fs_path_exists(path)            # 检查路径是否存在
api.get_fs_binary(path)             # 获取二进制数据
api.normalize_path(path)            # 规范化路径
api.join_path(base, relative)       # 路径拼接
api.set_current_path(path)          # 修改当前路径（模拟 cd）
```

#### 五、模组包文件
```gdscript
api.read_mod_file(relative_path)    # 读取模组包内文本文件
api.read_mod_binary(relative_path)  # 读取模组包内二进制文件
api.list_mod_files()                # 列出模组包内所有文件
```

#### 六、持久化数据
```gdscript
api.save_data(key, value)           # 保存数据
api.load_data(key, default_value)   # 读取数据
api.delete_data(key)                # 删除数据
api.get_data_keys()                 # 获取所有数据 key
api.clear_all_data()                # 清除所有数据
```

#### 七、UI 工具
```gdscript
api.show_progress_bar(duration_ms)  # 显示进度条
api.play_beep()                     # 播放蜂鸣音效
```

#### 八、音频系统
```gdscript
api.play_mod_audio(path)            # 播放模组包内音频（短音效）
api.play_mod_media(path)            # 播放媒体音频（长音频）
api.stop_media()                    # 停止媒体
api.pause_media()                   # 暂停/恢复媒体
api.play_ambient(id, path, vol)     # 播放环境音
api.stop_ambient()                  # 停止环境音
api.get_media_position()            # 获取播放位置
api.get_media_length()              # 获取总时长
api.is_media_playing()              # 是否正在播放
```

#### 九、视觉效果
```gdscript
api.trigger_glitch(intensity, duration, preset)  # 故障效果
api.trigger_shake(intensity, duration)            # 抖动
api.trigger_tear(strength, duration)              # 撕裂
api.trigger_noise_burst(intensity, duration)      # 噪声
api.trigger_screen_off(duration)                  # 黑屏
api.trigger_reboot()                              # 重启
api.trigger_preset_effect(name, duration)         # 预设效果
api.trigger_named_effect(effect_id)               # 命名效果
api.set_crt_parameter(name, value)                # CRT 参数
api.get_crt_parameter(name, default)              # 获取 CRT 参数
```

#### 十、输入控制
```gdscript
api.request_input_capture(handler)  # 拦截键盘输入
api.release_input_capture()         # 释放输入拦截
api.set_input_editable(editable)    # 设置输入框可编辑性
api.set_input_secret(secret)        # 设置密码模式
api.get_input_text()                # 获取输入框文本
api.set_input_text(text)            # 设置输入框文本
api.focus_input()                   # 聚焦输入框
```

#### 十一、UI 容器
```gdscript
api.get_mod_container()             # 获取模组专属 UI 容器
api.add_ui_node(node)               # 添加 UI 节点
api.remove_ui_node(node)            # 移除 UI 节点
api.clear_ui_nodes()                # 清空 UI 节点
api.create_overlay(color)           # 创建全屏覆盖层
api.create_rich_text_label()        # 创建 RichTextLabel
```

#### 十二、定时器
```gdscript
api.create_timer(seconds, callback) # 一次性定时器
api.create_interval(seconds, cb)    # 循环定时器
api.cancel_timer(timer)             # 取消定时器
api.wait(seconds)                   # 等待指定秒数
api.wait_frame()                    # 等待一帧
```

#### 十三、事件系统
```gdscript
api.send_mod_message(target_id, data)   # 向指定模组发送消息
api.broadcast_message(data)              # 广播消息
api.subscribe_event(event_name, handler) # 订阅事件
api.unsubscribe_event(event_name)        # 取消订阅
api.emit_event(event_name, data)         # 发布事件
```

#### 十四、通讯系统
```gdscript
api.comm_trigger(dialogue_id)                    # 触发对话
api.comm_stop()                                  # 停止对话
api.comm_is_active()                             # 是否有对话在播放
api.comm_register_character(char_id, config)     # 注册角色
api.comm_register_dialogue(dialogue_id, data)    # 注册对话
api.comm_unregister_character(char_id)           # 注销角色
api.comm_unregister_dialogue(dialogue_id)        # 注销对话
```

#### 十五、环境监测系统
```gdscript
api.env_get_reading(sensor_id)       # 获取传感器读数
api.env_get_all_readings()           # 获取所有读数
api.env_get_weather()                # 获取当前天气
api.env_get_day()                    # 获取当前天数
api.env_get_hour()                   # 获取当前小时
api.env_get_sensor_status(sensor_id) # 获取传感器状态
api.env_get_active_events()          # 获取活跃事件
api.env_inject_event(id, config)     # 注入自定义事件
api.env_force_event(id)              # 强制触发事件
api.env_add_task(id, data)           # 添加特殊任务
api.env_get_progress()               # 获取任务进度
api.env_can_advance()                # 是否可推进天数
```

#### 十六、其他
```gdscript
api.set_status_text(text)           # 设置状态栏文字
api.restore_status_bar()            # 恢复默认状态栏
api.set_fullscreen_mode(enabled)    # 全屏模式（隐藏框架）
api.request_scroll()                # 滚动到底部
api.create_tween()                  # 创建 Tween 动画
api.get_viewport_size()             # 获取视口大小
api.get_scene_tree()                # 获取场景树引用
api.is_logged_in()                  # 是否已登录
api.get_user_profile()              # 获取用户资料（安全副本）
api.get_installed_mods()            # 获取已安装模组列表
api.is_mod_active(mod_id)           # 模组是否激活
api.get_available_discs()           # 获取可用磁盘列表
api.set_background_shader(name, val)        # 设置背景 shader
api.tween_background_shader(name, from, to, dur) # 渐变背景 shader
```

### 模组示例

```gdscript
extends ModBase

func _register_commands() -> void:
    api.register_command("hello", "打个招呼", _cmd_hello, "global")
    api.register_command("countdown", "倒计时", _cmd_countdown, "global")

func _on_enable() -> void:
    api.output_colored("模组已加载！\n", "success")

func _on_disable() -> void:
    api.output_colored("模组已卸载。\n", "muted")

func _cmd_hello(args: Array) -> void:
    var name: String = api.get_username()
    if name.is_empty():
        name = "操作员"
    api.output("\n你好, " + name + "！欢迎使用终端。\n\n")

func _cmd_countdown(args: Array) -> void:
    var count: int = 5
    if args.size() > 0 and args[0].is_valid_int():
        count = int(args[0])
    for i in range(count, 0, -1):
        api.output(str(i) + "...\n")
        await api.wait(1.0)
    api.trigger_glitch(0.5, 1.0)
    api.output_colored("发射！\n", "success")

func _on_directory_changed(old_path: String, new_path: String) -> void:
    if new_path == "/secret":
        api.trigger_glitch(0.3, 0.5)
        api.output_colored("\n[警告] 检测到异常信号...\n", "warning")
```

---

## 目录结构

```
res://
├── audio/                  # 音频资源（启动音效等）
├── camera_system/          # 监控摄像头系统
│   ├── camera_feed.gd      # 摄像头数据模型
│   ├── camera_manager.gd   # 摄像头管理器
│   ├── camera_viewer.gd    # 摄像头查看器
│   └── camera_effect.gdshader  # 监控画面着色器
├── comm_system/            # 通讯系统模块
│   ├── comm_character.gd   # 角色数据类
│   ├── comm_dialogue_player.gd  # 对话播放器
│   ├── comm_manager.gd     # 通讯管理器
│   ├── comm_sprite_renderer.gd  # 立绘渲染器
│   ├── comm_ui.gd          # 通讯 UI
│   ├── comm_voice.gd       # 语音合成
│   ├── dial_manager.gd     # 拨号管理器
│   └── dial_tone_generator.gd  # DTMF 音频合成
├── data/                   # 内置数据文件
│   ├── ava_dialogues.json  # AVA 助手对话数据
│   └── tutorial.json       # 教程对话数据
├── env_system/             # 环境监测系统
│   ├── env_monitor.gd      # 环境模拟核心
│   ├── env_task_manager.gd # 每日任务管理
│   └── env_viewer.gd       # 监测面板查看器
├── fonts/                  # 字体文件
├── images/                 # UI 图像资源
├── modder/                 # 模组系统
│   ├── mod_api.gd          # 模组 API 接口
│   └── mod_base.gd         # 模组基类
├── saves/                  # 存档目录
├── scenes/                 # 场景文件
│   └── main.tscn           # 主场景
├── scripts/                # 核心脚本
│   ├── main.gd             # 主控制器
│   ├── audio_manager.gd    # 音频管理
│   ├── boot_sequence.gd    # 开机序列
│   ├── cipher_decoder.gd   # 密码解码器
│   ├── command_handler.gd  # 命令处理
│   ├── crtml_parser.gd     # CRTML 解析
│   ├── crt_shader.gd       # CRT 着色器控制
│   ├── daily_dialogue_manager.gd  # 每日剧情管理
│   ├── decode_viewer.gd    # 解码查看器
│   ├── disc_manager.gd     # 磁盘管理
│   ├── document_viewer.gd  # 文档查看器
│   ├── effect_settings.gd  # 效果安全设置
│   ├── effect_system.gd    # 效果系统
│   ├── explore_viewer.gd   # 文件浏览器
│   ├── file_system.gd      # 虚拟文件系统
│   ├── header_parser.gd    # 页眉解析
│   ├── image_viewer.gd     # 图片查看器
│   ├── loading_screen.gd   # 加载画面
│   ├── mail_system.gd      # 邮件系统
│   ├── morse_engine.gd     # 摩尔斯码引擎
│   ├── oscilloscope.gd     # 示波器
│   ├── package_manager.gd  # 包管理器
│   ├── profile_builder.gd  # 个人资料构建
│   ├── radio_audio_generator.gd  # 无线电音频生成
│   ├── radio_config_parser.gd    # 无线电配置解析
│   ├── radio_receiver.gd   # 无线电接收器
│   ├── radio_signal_manager.gd   # 无线电信号管理
│   ├── save_manager.gd     # 存档管理
│   ├── sstv_decoder.gd     # SSTV 解码器
│   ├── story_loader.gd     # 故事加载器
│   ├── theme_manager.gd    # 主题管理
│   ├── trigger_system.gd   # 触发器系统
│   ├── typewriter.gd       # 打字机效果
│   ├── ui_manager.gd       # UI 管理
│   ├── ui_sound.gd         # UI 音效
│   ├── user_manager.gd     # 用户管理
│   └── video_player.gd     # 视频播放器
├── settings/               # 设置系统
│   ├── settings_manager.gd # 设置管理器
│   ├── settings_registry.gd# 设置注册表
│   └── settings_storage.gd # 设置持久化
├── shaders/                # 着色器文件
│   ├── background_logo.gdshader      # Logo 着色器
│   ├── background_vignette.gdshader  # 暗角着色器
│   └── crt_effect.gdshader           # CRT 效果着色器
├── templates/              # 文档查看模板
│   ├── article_viewer.gd   # 文章查看器
│   ├── chat_viewer.gd      # 聊天查看器
│   ├── email_viewer.gd     # 邮件查看器
│   └── two_page_reader.gd  # 双页阅读器
├── vdisc/                  # 虚拟磁盘存放目录
│   └── *.scp               # 故事包 / 模组包文件
├── boot_config.json        # 开机引导配置
├── project.godot           # Godot 项目配置
├── AI_HANDOFF.md           # AI 交接文档
├── CAMERA_ASSET_GUIDE.txt  # 监控摄像头素材制作指南
├── DESIGN_DOC.txt          # 游戏设计文档
├── STORY_AUTHORING_GUIDE.txt # 故事编写指南
└── README.md               # 本文档
```

---

## 技术规格

| 项目 | 说明 |
|------|------|
| **引擎** | Godot 4.6 |
| **渲染方式** | GL Compatibility |
| **默认分辨率** | 1152 × 648 |
| **拉伸模式** | canvas_items |
| **脚本语言** | GDScript |
| **故事包格式** | ZIP (扩展名 .scp)，支持 manifest.json 和 manifest.cfg |
| **文本标记** | CRTML (CRT Markup Language) |
| **物理引擎** | Jolt Physics 3D（未使用，项目为纯 2D UI） |

### 存档位置

存档文件存储在用户数据目录下：
- **Windows**: `%APPDATA%/Godot/app_userdata/SCRT-Reader/`
- **Linux**: `~/.local/share/godot/app_userdata/SCRT-Reader/`
- **macOS**: `~/Library/Application Support/Godot/app_userdata/SCRT-Reader/`

### 相关文档

| 文档 | 说明 |
|------|------|
| `AI_HANDOFF.md` | AI 交接文档，压缩格式的完整技术参考 |
| `DESIGN_DOC.txt` | 游戏设计文档，叙事结构和核心玩法设计 |
| `STORY_AUTHORING_GUIDE.txt` | 故事编写完整教程，面向新作者 |
| `CAMERA_ASSET_GUIDE.txt` | 监控摄像头素材制作指南（底图/深度图/照明图/异常图） |

---

## 许可

本项目为 SCRT-Reader 终端阅读器。故事包和模组由各自作者创作，遵循其各自的许可协议。
