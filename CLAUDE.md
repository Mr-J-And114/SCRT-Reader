# SCRT-Reader — AI 引导文档

> **给 AI 助手的第一条指令**：本文件是项目入口文档。每次接手任务前，先通读本文件。
> 修改代码后，**必须**同步更新相关的 CLAUDE.md 和 docs/ 文档（行数、API、命令列表等）。
> 本文件最后更新：2026-03-28。

---

## 〇、文档导航地图

```
CLAUDE.md  ← 你在这里（项目总览 + AI 工作规范）
│
├─ docs/                          ← 人类可读的详细文档
│  ├─ architecture.md             ← 依赖图、场景树、全脚本索引（含行数）
│  ├─ data-formats.md             ← .scp 格式、CRTML、加载画面、存档、拨号
│  ├─ extension-guide.md          ← 添加新功能的 7 步流程 + 完整命令列表
│  ├─ design-doc.txt              ← 游戏设计文档（28 天剧情规划、角色、结局）
│  ├─ story-authoring-guide.txt   ← 故事包制作指南（面向非程序员）
│  ├─ character-system-guide.md   ← 角色精灵/动画系统
│  ├─ bgm-descriptions.md         ← 背景音乐设计说明
│  ├─ loading-screen-guide.md     ← 自定义加载画面制作
│  └─ camera-asset-guide.txt      ← 摄像头/CCTV 素材制作
│
├─ SCRT/scripts/CLAUDE.md         ← 核心脚本索引（行数、模式标志、架构模式）
├─ SCRT/comm_system/CLAUDE.md     ← 通讯/对话/角色/拨号系统
├─ SCRT/camera_system/CLAUDE.md   ← CCTV 摄像头 + shader 管线
├─ SCRT/radio/CLAUDE.md           ← 无线电接收/摩斯/SSTV/音频电台
├─ SCRT/env_system/CLAUDE.md      ← 环境监测（21 传感器、任务、天气）
├─ SCRT/settings/CLAUDE.md        ← 设置注册/存储系统
├─ SCRT/modder/CLAUDE.md          ← Mod API/生命周期
└─ SCRT/templates/CLAUDE.md       ← 文档查看器模板（article/chat/email/two_page）
```

**阅读策略**：根据任务类型选择性阅读：
- 修 bug → 本文件 + 相关子系统 CLAUDE.md
- 加功能 → 本文件 + `docs/extension-guide.md` + 相关子系统 CLAUDE.md
- 写剧情 → `docs/story-authoring-guide.txt` + `docs/design-doc.txt`
- 改 UI/效果 → 本文件 + `SCRT/scripts/CLAUDE.md`
- 全局了解 → 本文件 + `docs/architecture.md`

---

## 一、项目概述

**SCRT-Reader** — SCP 主题复古 CRT 终端模拟器 / 互动小说阅读器。
- 引擎：Godot 4.6（GL Compatibility 渲染器）
- 架构：纯 2D UI，单场景 (`main.tscn`)，无 Autoload
- 语言：GDScript，全类型标注
- 玩家角色：海岛观测站操作员，通过终端阅读故事包、与角色通讯、监测环境、收听无线电

**核心玩法循环**：开机 → 登录 → 加载故事盘 → 环境扫描 → 自由探索（文件/邮件/通讯/无线电）→ 关机存档

---

## 二、代码架构速览

### 目录结构
```
SCRT/                        Godot 项目根目录
├─ scripts/                  核心脚本（main.gd ~2209 行，command_handler.gd ~2346 行…）
├─ comm_system/              通讯系统（13 脚本：对话/角色/拨号/语音/演示）
├─ camera_system/            CCTV 监控（3 脚本 + 1 shader）
├─ env_system/               环境监测（3 脚本：监测/任务/查看器）
├─ radio/                    无线电（radio_receiver ~1804 行 + 5 支持脚本）
├─ settings/                 设置系统（3 脚本：管理器/注册表/存储）
├─ modder/                   Mod 系统（mod_api ~1075 行 + mod_base）
├─ templates/                文档模板（article/chat/email/two_page）
├─ shaders/                  着色器（CRT 效果/背景/logo）
├─ scenes/main.tscn          唯一场景
├─ data/                     配置与剧情数据
├─ addons/agent/             编辑器内 AI 插件（⚠️ 不要修改）
└─ vdisc/                    故事盘 (.scp) 存放目录
```

### 核心依赖注入模式
```gdscript
# main.gd._ready() 中实例化所有管理器，通过 setup() 注入依赖
var comm_mgr := CommManager.new()
comm_mgr.setup(self, fs, T)  # self=main, fs=FileSystem, T=ThemeColors
```
- 管理器 extends RefCounted（需要 `_process` 的 extends Node）
- **无 Autoload/Singleton**，所有引用通过构造注入

### 输入优先级链（main.gd 中 _input 路由）
```
_booting > _shutting_down > _comm_active > _viewer_active > _camera_mode >
_radio_mode > _env_mode > _explore_mode > _decode_mode > _password_mode >
_login_mode > [normal terminal input]
```

---

## 三、开发约定（必须遵守）

### GDScript 风格
- 全类型标注（变量/参数/返回值），`class_name` 在文件顶部
- `@onready` + `$` 引用节点，typed signals，`.connect(callable)`
- `JSON.new().parse()`，`FileAccess`/`DirAccess`，`await create_timer()`

### 常用 API
| 操作 | 方式 |
|---|---|
| 终端输出 | `main.append_output(bbcode)` 或 `tw.append(text)` |
| 主题颜色 | `T.primary_hex`, `T.error_hex` 等（返回 hex 字符串） |
| CRT 效果 | `crt_shader.play_glitch()`, `play_shake()`, `play_tear()` |
| 效果安全检查 | `effect_settings.is_effect_allowed("jumpscare")` |
| 注册命令 | `CommandHandler._register_commands()` 中添加 `_cmd_<name>` |
| 注册设置 | `settings_manager.register_category()` / `register_setting()` |
| 存档数据 | `save_manager.auto_save()` / `load_save()` |

### Viewer/Overlay 模式
创建全屏覆盖层的标准模式：
1. 创建 Panel 覆盖在 OutputArea 上
2. 缓存并隐藏 input/prompt/status
3. ESC/Q 关闭时恢复原始可见性状态
4. 参考 `ImageViewer` / `Oscilloscope` 实现

### 来电模式
`CallHandler` 管理 SILENT/FORCED/ANSWERABLE 来电。
- 对话 JSON 中设 `"call_mode"`，触发器格式 `comm:id:forced`
- 显示模式：`"card"` / `"meeting"` / `"presentation"`

---

## 四、重要陷阱（GOTCHAS）

1. **main.gd 是上帝对象**（~2209 行）——所有 `_process` 和 `_input` 路由都在此
2. **dial_mgr 后台运行**，状态机：IDLE → DTMF → RINGING → VOICE/MODEM → ENDED → IDLE
3. **.scp 文件是 ZIP**，编码检测：UTF-8 优先，GBK 回退
4. **vdisc 路径差异**：编辑器用 `res://vdisc/`，导出版用 `./vdisc/`
5. **CommDialoguePlayer**：转场用 `stop_dialogue(silent=true)`，自然结束用 `silent=false`
6. **加载画面独占模式**：播放期间 `main._process()` 只处理加载画面，其他系统挂起

---

## 五、当前开发进度

### 已完成模块（✅ 全部可用）
核心终端 | 文件系统 | 故事加载 | 用户系统 | 存档系统 | 通讯系统 |
邮件系统 | 无线电系统 | Mod 系统 | 设置系统 | 触发器系统 | 效果系统 |
所有查看器 | CRTML 解析 | 拨号系统 | 环境监测 | 摄像头系统 | 每日对话管理器

### 已有剧情内容
- 序章（Day 1-3）+ 第一章（Day 4-7）的每日对话配置
- AVA 角色完整精灵素材（分层/口型/眨眼）
- 4 个无线电信号 + 5 个摄像头测试素材

### 未完成事项（按优先级排序）

| 优先级 | 项目 | 说明 |
|---|---|---|
| ★★★★★ | **DayConfig 系统扩展** | daily_dialogues 缺少：文件解锁、环境参数覆盖、传感器偏移、强制事件 |
| ★★★★★ | **Day 8-28 剧情内容** | 第二章至终章的对话/文件/邮件/无线电内容 |
| ★★★★☆ | **剧情变量系统** | trust_ava、truth_discovered 等变量追踪，用于条件判断 |
| ★★★★☆ | **每日拨号对话轮换** | 同角色不同天数返回不同对话 |
| ★★★☆☆ | **结局判定系统** | 4 种结局条件判定（见 design-doc.txt §6.3） |
| ★★★☆☆ | **角色关系系统** | 对话选择影响关系值，关系值影响对话内容 |
| ★★☆☆☆ | **BGM 音乐** | 已有 20 首设计说明（bgm-descriptions.md），缺音频文件 |
| ★★☆☆☆ | **更多角色素材** | 只有 AVA 有完整精灵，researcher 仅临时占位 |

> 详见 `docs/design-doc.txt` 第八节"待实现的关键系统"

---

## 六、AI 文档维护规范

### 何时更新文档
**每次代码修改后**，检查以下文档是否需要同步更新：

| 修改类型 | 需要更新的文档 |
|---|---|
| 新增/删除/重命名脚本 | `docs/architecture.md` 脚本表 + 相关子系统 CLAUDE.md |
| 脚本行数显著变化（±50行） | `docs/architecture.md` 行数 + `SCRT/scripts/CLAUDE.md` |
| 新增/修改命令 | `docs/extension-guide.md` 命令列表 |
| 新增/修改 manifest 字段 | `docs/data-formats.md` + 相关子系统 CLAUDE.md |
| 新增系统模块 | 本文件(CLAUDE.md)架构图 + `docs/architecture.md` |
| 完成设计文档中的待办项 | 本文件第五节"当前开发进度" |
| 新增/修改 CRTML 标记 | `docs/data-formats.md` CRTML 节 + `docs/story-authoring-guide.txt` |
| 修改触发器动作 | `docs/story-authoring-guide.txt` 触发器章节 |
| 修改 Mod API | `SCRT/modder/CLAUDE.md` |

### 文档格式约定
- **CLAUDE.md**（各级）：面向 AI，简洁精确，用表格和代码块
- **docs/*.md**：面向 AI + 人类开发者，可更详细
- **docs/*.txt**：面向故事作者（非程序员），用中文，避免术语
- 行数使用**实际值**，不用约数（定期用 `wc -l` 核实）
- 所有 CLAUDE.md 文件顶部应有一行描述用途

### 自检清单（完成任务前执行）
1. ☐ 修改的代码是否引入了新的公共 API？→ 更新对应 CLAUDE.md
2. ☐ 命令列表是否有变化？→ 更新 `docs/extension-guide.md`
3. ☐ 大文件行数是否有显著变化？→ 更新 `docs/architecture.md`
4. ☐ 是否完成了"未完成事项"中的某项？→ 更新本文件第五节
5. ☐ 新增的子系统是否有 CLAUDE.md？→ 如无则创建
