# CRT Reader 开发阶段分析与规划

## 一、当前进度分析

根据 `CRT READER软件规划-V1.0.1.docx` 中的九阶段开发计划，对照现有代码逐项核对：

---

### 阶段一：基础框架（MVP）—— ✅ 已完成

| 规划项 | 状态 | 对应代码 |
|--------|------|----------|
| Godot项目基础搭建、场景树结构 | ✅ | `project.godot`, `scenes/main.tscn` |
| 基础CRT Shader实现与渲染管线 | ✅ | `shaders/crt_effect.gdshader`, `shaders/background_vignette.gdshader`, `crt_shader.gd` |
| 命令行输入框与基础命令解析 | ✅ | `main.gd` — ls/cd/open/back/clear/help/exit 全部实现 |
| ZIP文件读取与虚拟文件系统 | ✅ | `story_loader.gd` (ZIP解析), `file_system.gd` (虚拟FS) |
| 基础TXT文件显示（纯文本） | ✅ | `main.gd:_cmd_open()` — 直接显示原始文本 |
| 打字机效果 | ✅ | `typewriter.gd` — 逐字输出、速度控制、[speed=]/[pause=]标签 |
| 状态栏 | ✅ | `main.gd:_update_status_bar()` — 路径 + 权限等级 + 邮件图标 |

**额外完成（超出阶段一范围）：**
- 桌面/终端双模式切换（`_desktop_mode`）
- 多磁盘扫描与管理（`scan`, `load`, `eject`, `vdisc`）
- 命令历史记录（↑↓键）
- Tab自动补全
- 模拟加载进度条
- 4套颜色主题（phosphor_green, amber, cool_blue, white）
- 自定义CRT风格鼠标光标
- 文件权限系统（clearance level）
- 全局密码认证（`unlock`）
- 文件独立密码系统
- 存档/读档自动化（JSON格式）
- 右键复制、鼠标滚轮、超链接点击

---

### 阶段二：核心功能 —— ⚠️ 部分完成（约65%）

| 规划项 | 状态 | 说明 |
|--------|------|------|
| CRT-ML解析器（标题/粗体/分割线/分页） | ❌ 未实现 | 当前文件以纯文本显示，无任何Markdown解析 |
| 用户注册/登录系统 | ❌ 未实现 | `_cmd_whoami()` 显示"将在后续版本中实现" |
| 存档与数据持久化 | ✅ 已完成 | `save_manager.gd` — auto_save/load_save |
| 头文件解析（.meta.cfg / 权限/密码） | ⚠️ 部分完成 | 权限和密码通过 `manifest.json` 集中配置，但**未实现**规划中的每层文件夹独立 `.meta.cfg` 头文件解析 |
| 清单文件解析（manifest） | ✅ 已完成 | `story_loader.gd` — 支持 manifest.json 和 manifest.cfg |
| 文件滚动与翻页 | ✅ 已完成 | PageUp/PageDown/鼠标滚轮/Home/End |
| 命令自动补全与历史记录 | ✅ 已完成 | Tab补全 + ↑↓历史 |
| 模拟加载动画 | ✅ 已完成 | `typewriter.gd:show_progress_bar()` |

---

### 阶段三~九 —— ❌ 均未开始

以下功能目前代码中完全没有涉及：

- **阶段三** — 图片/音频/视频播放器、CRT-ML多媒体标记、document/email/chat/report模板
- **阶段四** — 触发器系统、邮件系统（`_cmd_mail()` 返回"后续版本实现"）
- **阶段五** — Jumpscare、Glitch故障效果、CRT开关机动画、音效体系
- **阶段六** — CRT Shader全面优化、设置系统（`settings`命令不存在）
- **阶段七** — 开发者模式、全面错误处理
- **阶段八** — 条件触发器、自定义模板、鼠标交互完善、彩蛋指令
- **阶段九** — 主题包/插件系统、多语言支持等远期规划

---

## 二、当前代码架构（已拆分模块）

```
main.gd (1150行)          — 主控制器：命令分发、状态管理、磁盘加载
├── story_loader.gd (186行)  — ZIP解析、manifest读取
├── file_system.gd (333行)   — 虚拟文件系统、路径操作、权限检查、文本框构建
├── ui_manager.gd (371行)    — UI初始化、样式设置、自定义光标
├── typewriter.gd (218行)    — 打字机效果引擎
├── save_manager.gd (98行)   — 存档管理
├── theme_manager.gd (202行) — 颜色主题管理
└── crt_shader.gd (14行)     — CRT Shader尺寸控制
```

**总代码量：约2,572行GDScript**

---

## 三、阶段二剩余任务规划

### 2.1 CRT-ML 解析器（核心优先级）

这是阶段二中最大的缺失，也是整个阅读器的核心功能。建议新建 `scripts/crtml_parser.gd`。

**基本格式支持（阶段二目标）：**
```
# / ## / ###    → 标题（不同大小/高亮）
**粗体**        → BBCode [b] 或颜色高亮
__下划线__      → BBCode [u]
~~删除线~~      → [已编辑] 样式
> 引用块        → 缩进 + 竖线前缀
- 无序列表      → 缩进 + 符号前缀
1. 有序列表     → 缩进 + 编号
---             → 水平分割线
---PAGE---      → 分页符（等待用户按键继续）
```

**文档头部解析：**
```
---HEADER---
template: document
password: XXXXX
style: green_terminal
typewriter_speed: 50
---END_HEADER---
```

**实现建议：**
- 创建 `CRTMLParser` 类，输入原始文本，输出 BBCode 格式文本
- 在 `_cmd_open()` 中调用解析器，替代当前的直接文本输出
- 分页符触发等待用户输入

### 2.2 用户注册/登录系统

**实现建议：**
- 新建 `scripts/user_manager.gd`
- 用户数据存储在 `saves/user_profile.json`
- 首次启动进入注册流程（终端交互风格）
- 登录后显示"欢迎，Dr.XXX"
- 邮件中 `{username}` 变量替换基础

### 2.3 头文件系统（.meta.cfg）

**实现建议：**
- 修改 `story_loader.gd`，在加载ZIP时解析每层文件夹的 `.meta.cfg`
- 将权限、文件夹密码、文件描述、加载时间等配置读取到 `file_system.gd` 中
- `.meta.cfg` 在 `ls` 列表中隐藏
- 逐步替代目前 `manifest.json` 中集中式的 permissions/file_passwords 配置

---

## 四、后续阶段细化规划

### 阶段三：多媒体与模板

**建议拆分为3个子阶段：**

**3A — CRT-ML 高级语法 + document 模板**
- SCP特殊标记：`[REDACTED]`, `[DATA EXPUNGED]`, `||遮蔽文本||`
- 内联效果标记：`{typewriter speed=30}`, `{delay time=2000}`, `{clear}`
- 超链接解析：`[文本](link:路径)`, `[文本](url:https://...)`
- document 模板完善（标准文档排版）

**3B — email + chat 模板**
- email 模板：发件人/收件人/日期/主题 格式化显示
- chat 模板：`@用户名 [时间]: 消息` 解析，多说话人颜色区分
- `{typing delay=3000}` 打字指示器动画
- 聊天回放模式（实时/手动两种）

**3C — 多媒体播放器**
- 图片查看器（CRT效果覆盖、缩放）
- 音频播放器（播放控制、进度条、简介显示）
- 视频播放器（基础播放、CRT效果覆盖）
- 环境音系统（循环播放、跨目录持续）
- CRT-ML 多媒体标记解析：`![image]`, `![audio]`, `![video]`

### 阶段四：触发器与邮件系统

**建议拆分为2个子阶段：**

**4A — 邮件系统**
- 邮件文件存储于 `mail/` 目录（隐藏）
- 邮件触发机制（条件满足 → 延迟 → 投递）
- 收件箱列表（`mail` 命令）
- 邮件阅读（`mail read <id>`）
- 状态栏邮件图标提示
- `{username}` 动态变量替换

**4B — 触发器系统**
- 触发器核心引擎：条件检测 + 动作执行
- 基础条件：`on_enter`, `on_first_enter`, `on_open_file`
- 基础动作：`new_mail`, `level_up`, `sound`, `text`, `redirect`
- 高级条件：`on_level_reach`, `on_read_complete`, `on_idle`
- 高级动作：`glitch`, `screen_off`, `reboot`, `color_scheme`
- 复合触发器（分号分隔多动作）
- 一次性/可重复触发器
- 触发链深度限制与循环检测

### 阶段五：特殊效果与沉浸感

- Jumpscare效果系统
- Glitch故障效果系统（屏幕撕裂、色偏、噪点）
- CRT开机/关机动画
- 操作音效体系（键盘敲击、硬盘读取、电流底噪）
- 自定义载入画面（`loading.cfg` 解析）
- 效果强度分级设置（完整/温和/关闭）

### 阶段六：CRT效果优化与设置系统

- CRT Shader全面优化（参考 cool-retro-term）
- `settings` 命令 → 终端风格设置面板
- 显示/音频/文本/效果四大分类设置
- 配色方案运行时切换
- 设置即时预览与持久化

### 阶段七：调试工具与错误处理

- 开发者模式（`debug on/off`）
- 开发者命令集（`debug show_hidden`, `debug set_level`, `debug trigger`）
- 实时日志面板
- 全面错误处理（文件系统、解析、触发器等）

### 阶段八：扩展与打磨

- 条件触发器（`if_level>=`, `if_read:`）
- 自定义模板机制
- `.scp` 文件关联
- 彩蛋指令（`ping`, `sudo` 等）
- 性能优化、全面测试

### 阶段九：远期规划

- 主题包系统
- 插件/Mod系统
- 多语言支持
- 创作工具
- Web导出

---

## 五、建议的下一步行动

**当前应集中完成阶段二的剩余任务，按优先级排序：**

1. **CRT-ML 解析器** — 创建 `crtml_parser.gd`，实现基本格式解析
2. **头文件系统** — 修改 `story_loader.gd` 支持 `.meta.cfg` 解析
3. **用户注册/登录** — 创建 `user_manager.gd`

完成这三项后，阶段二即告完成，可以进入阶段三。

---

## 六、需要拆分的 main.gd 职责

当前 `main.gd`（1150行）仍然承担过多职责，后续阶段建议进一步拆分：

| 建议新增模块 | 职责 | 从 main.gd 抽出的内容 |
|-------------|------|----------------------|
| `crtml_parser.gd` | CRT-ML标记语言解析器 | `_cmd_open()` 中的文本处理逻辑 |
| `user_manager.gd` | 用户注册/登录/会话管理 | `_cmd_whoami()`, 用户相关状态变量 |
| `command_handler.gd` | 命令解析与分发 | `_execute_command()`, 所有 `_cmd_*()` 方法 |
| `disc_manager.gd` | 磁盘扫描/加载/卸载 | `_scan_available_stories()`, `_load_story_*()`, `_cmd_eject()` |
| `mail_manager.gd` | 邮件系统（阶段四） | `_cmd_mail()`, 邮件相关状态 |
| `trigger_engine.gd` | 触发器系统（阶段四） | 新建 |
| `audio_manager.gd` | 音频/音效管理（阶段三/五） | 新建 |
| `effect_manager.gd` | 特殊效果管理（阶段五） | 新建 |
| `settings_manager.gd` | 设置系统（阶段六） | 新建 |
