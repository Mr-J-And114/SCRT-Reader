# SCRT-Reader

**SCP CRT Terminal Reader** — 一款基于 Godot 4.6 引擎构建的复古 CRT 终端风格阅读器。玩家以操作员身份登录虚拟终端系统，通过命令行交互浏览"虚拟磁盘"（故事包）中的文档、音频、图像、视频等多媒体内容。支持模组（Mod）扩展和自定义故事包制作。

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

SCRT-Reader 模拟了一台 20 世纪风格的 CRT 终端计算机。用户通过命令行操作虚拟文件系统，阅读文档、解密文件、收听无线电信号、查看 SSTV 图像，以及与 AI 角色进行通讯对话。

### 核心特性

- **CRT 复古视觉效果**：扫描线、色差、屏幕弯曲、屏幕闪烁等可配置着色器效果
- **完整终端模拟**：命令行输入、文件系统浏览、密码保护、权限等级
- **故事包系统**：通过 `.scp` 格式的虚拟磁盘加载不同的故事内容
- **多媒体支持**：文档查看、图片查看器、音频播放器、视频播放器、示波器
- **无线电接收器**：模拟调频/调幅无线电，支持摩尔斯码解码和 SSTV 图像接收
- **通讯系统**：与虚拟角色进行对话交互，支持立绘和语音合成
- **邮件系统**：接收和阅读系统/故事邮件
- **触发器系统**：基于玩家行为自动触发事件（音效、特效、邮件、路径跳转等）
- **模组系统**：支持第三方模组扩展命令、UI、音频等功能
- **多用户系统**：用户注册/登录、个人资料、存档管理
- **主题切换**：多种终端配色方案可选（磷光绿、琥珀色、冷蓝、白色）
- **自动存档**：自动保存阅读进度和系统状态

---

## 系统架构

```
┌─────────────────────────────────────────────────┐
│                    Main (Control)                │
│  主控制器 - 管理所有子系统的初始化与交互         │
├─────────┬─────────┬──────────┬─���────────────────┤
│ UI 层   │ 逻辑层  │ 数据层   │ 扩展层           │
├─────────┼─────────┼──────────┼──────────────────┤
│UIManager│CmdHdlr  │FileSystem│PackageManager    │
│Typewriter│DiscMgr  │StoryLoader│ModAPI / ModBase │
│CRTShader│MailSys  │SaveManager│TriggerSystem    │
│EffectSys│CommMgr  │UserManager│                  │
│AudioMgr │CrtmlPsr │ThemeMgr  │                  │
│RadioRecv│         │          │                  │
└─────────┴─────────┴──────────┴──────────────────┘
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
| **无线电接收器** | `radio_receiver.gd` | 全功能无线电模拟，频率调谐、信号接收、解码 |
| **效果系统** | `effect_system.gd` | 时间轴驱动的屏幕特效序列（故障、抖动、黑屏等） |
| **音频管理器** | `audio_manager.gd` | 环境音、音效、媒体播放、音频频谱分析 |
| **主题管理器** | `theme_manager.gd` | 终端配色方案管理和切换 |
| **用户管理器** | `user_manager.gd` | 用户注册/登录、个人资料、统计数据 |
| **存档管理器** | `save_manager.gd` | 游戏进度存档和加载 |
| **包管理器** | `package_manager.gd` | 模组安装/卸载/生命周期管理 |
| **UI 管理器** | `ui_manager.gd` | 终端 UI 布局、���式、CRT 自定义光标 |

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
| `deluser <用户名>` | 删除指���用户（需管理员权限） |

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
| `theme` | 切换终端主题 |
| `volume` / `vol` | 调整音量 |
| `reboot` | 重启终端 |
| `exit` / `quit` | 退出程序 |
| `profile` | 查看个人资料 |
| `logout` | 注销当前用户 |
| `passwd` | 修改密码 |
| `birthday` | 设置生日 |
| `users` | 列出所有用户 |
| `decode` | 解码查看器 |
| `fx_level` | 调整视觉效果等级 |
| `fx_safe` | 安全模式（降低闪烁等） |
| `sound` | 音效设置 |
| `packages` / `pkg` | 查看已安装的包 |
| `uninstall` | 卸载模组 |
| `comm` | 通讯系统 |

### 6. 无线电接收器

完整模拟的无线电接收器界面，支持：

- **波段切换**：AM / FM / SW 等多个波段
- **频率调谐**：手动微调和拖拽调频
- **方位调整**：天线方位角和仰角
- **信号检测**：信号质量指示、信号锁定
- **自动扫描**：自动搜索频段内的信号
- **摩尔斯码解码**：自动解码锁定的摩尔斯码信号
- **SSTV 接收**：接收 SSTV（慢扫描电视）图像信号
- **瀑布图**：实时频谱瀑布图显示
- **雷达视图**：信号源方位可视化

### 7. 通讯系统

与虚拟角色进行交互式对话：

- **角色立绘**：支持多表情状态和动画
- **语音合成**：模拟的角色说话音效
- **分支对话**：支持选择式对话分支
- **条件触发**：对话可基于特定条件（执行命令、打开文件等）推进
- **教程引导**：内置 AVA 助手角色引导新用户

### 8. 文档查看模板

支持多种文档呈现模板：

| 模板 | 说明 |
|------|------|
| `article_viewer` | 文章查看器 — 长文阅读 |
| `chat_viewer` | 聊天记录查看器 — 即时通讯风格 |
| `email_viewer` | 邮件查看器 — 邮件格式展示 |
| `two_page_reader` | 双页阅读器 — 翻页式文档 |

### 9. 视觉效果系统

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
| `Escape` / `Q` | 关闭无线电 |

### 通讯系统操作

| 按键 | 功能 |
|------|------|
| `Space` / `Enter` | 推进对话 |
| `1-9` | 选择对话分支 |
| `Escape` | 关闭通讯 |

---

## 故事包制作指南

### 故事包格式

故事包是一个 `.scp` 文件，实质上是一个 **ZIP 压缩包**（仅修改扩展名为 `.scp`）。将故事包放入 `vdisc/` 目录即可被系统扫描到。

### 目录结构

```
my_story.scp (ZIP)
├── manifest.cfg          # 必须：故事配置清单
├── files/                # 虚拟文件系统根目录
│   ├── documents/
│   │   ├── readme.txt
│   │   └── report.crtml
│   ├── images/
│   │   └── photo.png
│   ├── audio/
│   │   └── ambient.ogg
│   └── videos/
│       └── tape.ogv
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

### manifest.cfg 配置

`manifest.cfg` 是故事包的核心配置文件，使用类 INI 格式：

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
/classified/files = topsecret

[file_passwords]
/documents/encrypted.txt = decrypt_key

[hidden_dirs]
dirs = /hidden, /system/.internal

[ambient]
/documents = ambient_hum
/ = base_static

[headers]
/ = [color=#88ff88]欢迎访问数据库[/color]
/documents = [color=#ffaa44]文档存储区[/color]

[descriptions]
/documents/readme.txt = 入门指南
/images/photo.png = 现场照片

[folder_descriptions]
/documents = 包含所有文档文件
/images = 图像存储区

[triggers]
enter:/secret = action:new_mail:warning_mail
open:/documents/classified.txt = action:sound:alert.ogg
read_complete:/documents/report.crtml = action:level_up:2
idle:30 = action:text:系统闲置中...
command:help = action:comm:tutorial_help

[effects]
custom_scare = [{"time":0,"type":"glitch","intensity":1.0,"duration":0.5},{"time":0.3,"type":"shake","intensity":0.02,"duration":0.3}]

[mail]
warning_mail = {"from":"SYSTEM","subject":"安全警告","body":"检测到未授权访问","priority":"high"}

[comm]
characters = comm/characters.json
dialogues = comm/dialogues.json
```

### manifest.cfg 配置项详解

#### [story] 基本信息
- `id`：故���唯一标识（英文，用于存档识别）
- `title`：故事标题（显示在磁盘列表中）
- `author`：作者名
- `description`：故事简介
- `version`：版本号

#### [settings] 全局设置
- `initial_path`：加载故事后的初始目录路径（默认 `/`）
- `player_clearance`：玩家初始安全等级（整数，默认 1）

#### [passwords] 目录密码
- 格式：`路径 = 密码`
- 访问被锁定的目录时需要输入 `unlock <路径>` 并提供正确密码

#### [file_passwords] 文件密码
- 格式：`路径 = 密码`
- 打开被锁定的文件时需要输入密码

#### [hidden_dirs] 隐藏目录
- `dirs`：逗号分隔的隐藏目录列表（`ls` 不可见但可直接 `cd` 进入）

#### [ambient] 环境音
- 格式：`路径 = 音频文件名`
- 进入该目录时自动播放对应的环境音

#### [headers] 路径页眉
- 格式：`路径 = BBCode文本`
- 在 `ls` 列出目录内容时，顶部会显示此文本

#### [triggers] 事件触发器
触发器格式：`事件类型:参数 = 动作类型:参数`

**事件类型：**
- `enter:<路径>` — 进入指定目录时触发
- `open:<路径>` — 打开指定文件时触发
- `read_complete:<路径>` — 阅读完指定文件后触发
- `command:<命令>` — 执行指定命令时触发
- `level:<等级>` — 安全等级变化时触发
- `idle:<秒数>` — 空闲指定秒数后触发

**动作类型：**
- `action:new_mail:<邮件ID>` — 发送邮件
- `action:level_up:<等级>` — 提升安全等级
- `action:sound:<文件>` — 播放音效
- `action:text:<文本>` — 输出文本
- `action:redirect:<路径>` — 跳转到指定目录
- `action:glitch:<强度>:<时长>` — 屏幕故障效果
- `action:shake:<强度>:<时长>` — 屏幕抖动
- `action:tear:<强度>:<时长>` — 画面撕裂
- `action:noise_burst:<强度>:<时长>` — 噪声爆发
- `action:screen_off:<时长>` — 屏幕关闭
- `action:reboot` — 重启终端
- `action:play_effect:<效果ID>` — 播放自定义效果
- `action:preset_effect:<预设名>:<时长>` — 播放预设效果
- `action:lock_folder:<路径>:<密码>` — 锁定目录
- `action:unlock_folder:<路径>` — 解锁目录
- `action:color_scheme:<主题>` — 切换配色
- `action:comm:<对话ID>` — 触发通讯对话

#### [effects] 自定义效果
- JSON 格式的时间轴效果序列，每个步骤包含 `time`、`type`、及类型特定参数

#### [mail] 邮件定义
- JSON 格式的邮件数据，包含 `from`、`subject`、`body`、`priority` 字段

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

#### 图片
```
{img:images/photo.png}
{img:images/photo.png|width=40}
{img:images/photo.png|width=30|height=10}
```

#### 音频
```
{audio:audio/recording.ogg}
```
终端中将显示播放控件，点击可切换播放/暂停。

#### 视频
```
{video:videos/tape.ogv}
```

### 链接
```
{link:目标路径|显示文本}
```
点击链接可跳转到文件系统中的对应文件/目录。

### 颜色
文本颜色通过以下名称引用主题色：
- `primary` — 主色
- `secondary` — 次要色
- `dim` — 暗色
- `success` — 成功色
- `warning` — 警告色
- `error` — 错误色
- `info` — 信息色
- `muted` — 静音色

### 特效标签

CRTML 支持在文本中嵌入特效标签，在打字机输出到对应位置时自动触发效果：

```
{fx:glitch|intensity=0.5|duration=1.0}
{fx:shake|intensity=0.01|duration=0.5}
{fx:sound|file=audio/alert.ogg}
{fx:delay|ms=500}
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

#### 十五、其他
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
├── comm_system/            # 通讯系统模块
│   ├── comm_character.gd   # 角色数据类
│   ├── comm_dialogue_player.gd  # 对话播放器
│   ├── comm_manager.gd     # 通讯管理器
│   ├── comm_sprite_renderer.gd  # 立绘渲染器
│   ├── comm_ui.gd          # 通讯 UI
│   └── comm_voice.gd       # 语音合成
├── data/                   # 内置数据文件
│   ├── ava_dialogues.json  # AVA 助手对话数据
│   └── tutorial.json       # 教程对话数据
├── fonts/                  # 字体文件
���── images/                 # UI 图像资源
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
│   ├── decode_viewer.gd    # 解码查看器
│   ├── disc_manager.gd     # 磁盘管理
│   ├── document_viewer.gd  # 文档查看器
│   ├── effect_settings.gd  # 效果设置
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
├── shaders/                # 着色器文件
│   ├── background_logo.gdshader      # Logo 着色器
│   ├── background_vignette.gdshader  # 暗角着色器
│   └── crt_effect.gdshader           # CRT 效果着色器
├── templates/              # 文档查看模板
│   ├── article_viewer.gd   # 文章查看器
│   ├── chat_viewer.gd      # 聊天查看器
│   ├── email_viewer.gd     # 邮件查看���
│   └── two_page_reader.gd  # 双页阅读器
├── vdisc/                  # 虚拟磁盘存放目录
│   ├── *.scp               # 故事包 / 模组包文件
│   └── scp_toolkit.scp     # 工具包
├── boot_config.json        # 开机引导配置
├── project.godot           # Godot 项目配置
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
| **故事包格式** | ZIP (扩展名 .scp) |
| **文本标记** | CRTML (CRT Markup Language) |
| **物理引擎** | Jolt Physics (3D) |

### 存档位置

存档文件存储在用户数据目录下：
- **Windows**: `%APPDATA%/Godot/app_userdata/SCRT-Reader/`
- **Linux**: `~/.local/share/godot/app_userdata/SCRT-Reader/`
- **macOS**: `~/Library/Application Support/Godot/app_userdata/SCRT-Reader/`

---

## 许可

本项目为 SCRT-Reader 终端阅读器。故事包和模组由各自作者创作，遵循其各自的许可协议。
