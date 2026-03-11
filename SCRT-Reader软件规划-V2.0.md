# SCRT-Reader 软件规划 V2.0

**文档版本：** 2.0
**编制日期：** 2026-03-10
**前序文档：** CRT READER软件规划-V1.0.1.docx
**关联文档：** design-doc.txt（游戏设计文档 v0.1）、architecture.md、data-formats.md

---

## 〇、文档说明

### 0.1 编制目的

V1.0.1 规划文档中提出的 **9个开发阶段、13章功能需求** 已全部完成，且在开发过程中额外实现了 **12个规划外系统**（通讯/拨号/无线电/环境监测/摄像头/Mod等）。SCRT-Reader 已从一个"CRT风格阅读器"演进为一个**功能完备的互动叙事平台**。

本文档的目标是：
1. 系统回顾 V1.0.1 的完成情况，明确已有能力边界
2. 梳理现有技术债务和已知问题
3. 基于《游戏设计文档 v0.1》的愿景，规划从"平台"到"完整游戏体验"的升级路线
4. 为社区生态和平台扩展制定中长期方向

### 0.2 项目定位演进

```
V1.0.1 定位：CRT风格互动阅读器（阅读 .scp 故事包的通用平台）
         ↓
V2.0 定位：CRT终端模拟器 + OB-7K观测站互动叙事游戏 + 开放式故事包平台
```

---

## 一、V1.0.1 规划完成回顾

### 1.1 九阶段完成对照

| 阶段 | V1.0.1 规划内容 | 完成状态 | 备注 |
|------|----------------|---------|------|
| 阶段一：基础框架(MVP) | 场景树、CRT Shader、基础命令、ZIP读取、虚拟文件系统、打字机效果、状态栏 | ✅ 全部完成 | |
| 阶段二：核心功能 | CRTML解析、用户系统、存档、头文件解析、清单文件、滚动翻页、命令补全/历史、模拟加载 | ✅ 全部完成 | CRTML解析器扩展至~40种语法规则，远超原规划 |
| 阶段三：多媒体与模板 | 图片/音频/视频播放器、环境音系统、CRTML多媒体/超链接标记、document/email/chat/report模板 | ✅ 全部完成 | 额外实现：频谱可视化器(Oscilloscope)、ffmpeg视频回退 |
| 阶段四：触发器与邮件 | 触发器系统(条件检测+动作执行+触发链)、邮件系统(触发/延迟/收件箱) | ✅ 全部完成 | 触发器支持10种条件 × 20+种动作，远超原规划 |
| 阶段五：特殊效果 | Jumpscare系统、Glitch效果、内联效果标记、SCP标记、开关机动画、操作音效、载入画面、效果分级 | ✅ 全部完成 | 效果系统升级为时间线驱动的多步骤序列引擎 |
| 阶段六：CRT效果优化与设置 | CRT Shader全面优化、设置系统(4分类)、配色方案、设置持久化 | ✅ 全部完成 | 设置系统重构为注册表架构(904行)，支持import/export |
| 阶段七：调试工具与错误处理 | 开发者模式、日志面板、全面错误处理 | ✅ 全部完成 | |
| 阶段八：扩展与打磨 | 条件触发器、自定义模板机制、文件关联、鼠标交互、彩蛋指令、性能优化 | ⚠️ 大部分完成 | 自定义模板机制、.scp文件关联尚未实现 |
| 阶段九：远期规划 | 主题包、插件/Mod系统、多语言、创作工具、macOS/Web导出 | ⚠️ Mod系统已完成 | 主题包/多语言/创作工具/macOS/Web未实现 |

### 1.2 超出V1.0.1规划的额外实现

以下系统在V1.0.1文档中**完全未规划**，是开发过程中根据游戏设计需要新增的：

| # | 系统 | 核心脚本 | 代码量 | 功能说明 |
|---|------|---------|-------|---------|
| 1 | **通讯系统** | comm_manager.gd, comm_dialogue_player.gd, comm_character.gd, comm_sprite_renderer.gd, comm_ui.gd, comm_voice.gd | ~1600行 (6个脚本) | 完整的角色对话编排引擎：角色管理、表情系统、语音合成、选择分支、教学流程、静默过渡 |
| 2 | **拨号系统** | dial_manager.gd, dial_tone_generator.gd | ~1100行 | DTMF拨号状态机(IDLE→DTMF→RINGING→VOICE/MODEM→ENDED)、语音通话路由、Modem握手+HTTP下载、号码簿(预设+故事) |
| 3 | **无线电系统** | radio_receiver.gd, radio_signal_manager.gd, radio_config_parser.gd, radio_audio_generator.gd, morse_engine.gd, sstv_decoder.gd | ~4600行 (6个脚本) | 完整无线电调谐UI、AM/FM频段、摩斯码解码、SSTV图像接收、音频电台、隐藏信号、瀑布图、渐进感知 |
| 4 | **环境监测系统** | env_monitor.gd, env_task_manager.gd, env_viewer.gd | ~1350行 (3个脚本) | 21个传感器(萨哈林基线)、天气模式(8种)、特殊事件、异常检测、昼夜/潮汐模型、每日任务检查清单(8项)、6页CRT覆盖面板 |
| 5 | **CCTV摄像头系统** | camera_feed.gd, camera_manager.gd, camera_viewer.gd, camera_effect.gdshader | ~1250行 (3个脚本+1着色器) | 监控画面管理(基础/深度/光照/异常图层)、3种光照模式(聚光灯/夜视/红外)、着色器管线(视差+噪点+信号干扰)、异常系统 |
| 6 | **Mod/模组系统** | mod_api.gd, mod_base.gd, package_manager.gd | ~1900行 (3个脚本) | 完整的模组API(997行/16功能类别)、模组生命周期管理(安装/启用/禁用/卸载)、ModBase基类(安装/启用/处理/事件回调) |
| 7 | **密码破译系统** | cipher_decoder.gd, decode_viewer.gd | ~2000行 (2个脚本) | 8种密码算法(Caesar/Vigenere/替换/Base64/Morse/ROT13/Atbash/反转)、动画化破译过程UI |
| 8 | **文件探索器** | explore_viewer.gd | ~478行 | 文件树面板、故事进度显示 |
| 9 | **视频播放器增强** | video_player.gd | ~737行 | 视频覆盖层+控制UI、ffmpeg回退支持 |
| 10 | **频谱可视化器** | oscilloscope.gd | ~820行 | 音频频谱分析+利萨如图形、CRT风格画布渲染 |
| 11 | **用户档案构建器** | profile_builder.gd | ~219行 | 3页式用户档案卡生成 |
| 12 | **效果序列引擎** | effect_system.gd | ~452行 | 基于时间线的多步骤效果序列(替代原V1.0.1简单的单次触发) |

### 1.3 当前技术指标

```
核心脚本数量：      ~40个 (scripts/ + comm_system/ + camera_system/ + env_system/ + radio/ + settings/ + modder/ + templates/)
总代码行数：        ~25,000+ 行 GDScript
管理器/系统数量：    40+ 个（全部通过构造注入初始化）
着色器：            4个 (CRT后处理 / 背景暗角 / 背景Logo / 摄像头效果)
文档模板：          4个 (article / chat / email / two_page_reader)
终端命令：          ~40个 (全局/桌面/磁盘三类)
支持的传感器类型：   21个 (大气/海洋/地球物理/成分组成)
密码算法：          8种
CRT主题：           4种 (绿色/琥珀/蓝色/白色)
```

---

## 二、已知问题与技术债务

### 2.1 路径迁移遗留

以下3处仍使用 `user://` 路径，需迁移到统一的 `saves/` 目录体系：

| 文件 | 行号 | 问题 | 建议修复方案 |
|------|------|------|-------------|
| `video_player.gd` | ~280 | 临时视频目录使用 `user://` | 改为 `res://saves/_temp/` 或系统临时目录 |
| `package_manager.gd` | ~792 | vdisc搜索路径使用 `user://` | 统一使用 `disc_manager` 的路径常量 |
| `story_loader.gd` | ~455 | GBK编码表路径使用 `user://` | 改为 `res://data/` 下的固定资源路径 |

### 2.2 代码质量——大文件拆分

| 文件 | 当前行数 | 问题 | 建议拆分方案 |
|------|---------|------|-------------|
| `main.gd` | ~1939行 | 上帝对象：集中了所有 `_process`、`_input`、模式管理、UI更新、媒体控制、效果调用 | 提取 `InputRouter`（输入分发+模式标志）、`ModeManager`（模式切换逻辑）、`UIController`（状态栏/输出区/输入框管理） |
| `radio_receiver.gd` | ~1700行 | 包含完整的无线电UI + 交互逻辑 + 画布渲染 | 提取 `RadioUI`（面板布局+按键处理）、保留 `RadioReceiver`（核心调谐逻辑），`_RadioCanvas` 内部类已存在 |
| `command_handler.gd` | ~1638行 | 所有命令处理器集中在一个文件 | 可按领域拆分为 `FileCommands`、`UserCommands`、`MediaCommands`、`SystemCommands` 等子处理器，CommandHandler仅做路由分发 |
| `crtml_parser.gd` | ~1266行 | 解析规则众多，但逻辑自洽 | 优先级较低，可暂不拆分 |

### 2.3 功能完善项（V1.0.1阶段八/九未完成部分）

| 项目 | 原规划位置 | 当前状态 | 优先级 |
|------|-----------|---------|--------|
| 自定义模板机制 | 阶段八 / 十二章 | 未实现。当前仅4个内置模板，不支持 .scp 内自定义模板 | ★★☆☆☆ |
| .scp 文件关联 | 阶段八 | 未实现。无法双击 .scp 文件直接打开阅读器 | ★★☆☆☆ |
| 多语言支持(i18n) | 阶段九 | 未实现。界面文本硬编码为中文 | ★★★☆☆ |
| macOS 平台适配 | 阶段九 | 未测试/适配 | ★★☆☆☆ |
| Web 导出版本 | 阶段九 | 未评估可行性 | ★☆☆☆☆ |
| 主题包系统 | 阶段九 / 十二章 | 未实现。当前主题硬编码在 ThemeManager 中 | ★☆☆☆☆ |
| CRT-ML语法高亮编辑器 | 阶段九 / 十二章 | 未实现 | ★☆☆☆☆ |
| 内容包验证/打包工具 | 阶段九 / 十二章 | 未实现 | ★★☆☆☆ |

### 2.4 其他已知问题

| 问题 | 严重程度 | 说明 |
|------|---------|------|
| `_desktop_mode` 状态管理 | 中 | 桌面模式/磁盘模式的切换依赖 main.gd 中多个散布的标志位，关系不够清晰 |
| 大文档性能 | 低 | RichTextLabel 在超大BBCode内容时可能出现渲染延迟，尚无分段加载机制 |
| 编码表加载 | 低 | GBK 编码表从外部文件加载，首次运行时需要额外I/O |
| 模组安全 | 中 | ModAPI 暴露了大量系统能力，恶意模组可能滥用（但当前为单机应用，风险可控） |

---

## 三、从"阅读器平台"到"完整游戏体验"

> 本章基于《游戏设计文档 v0.1》（design-doc.txt）的愿景，规划将 SCRT-Reader 从通用平台升级为完整的"OB-7K观测站"互动叙事游戏所需的系统和内容。

### 3.1 核心差距分析

```
当前状态（平台层 ✅）              需要新增（游戏层 ○）
─────────────────────────        ─────────────────────────
✅ 虚拟文件系统                   ○ 每日内容配置系统 (DayConfig)
✅ 通讯对话系统                   ○ 剧情变量系统 (StoryVariables)
✅ 拨号/号码簿                    ○ 每日拨号对话轮换
✅ 邮件系统                       ○ 条件化对话加载
✅ 无线电信号系统                 ○ 结局判定系统 (EndingResolver)
✅ 环境监测(传感器/天气/事件)     ○ 角色关系系统 (CharacterRelationship)
✅ CCTV摄像头系统                 ○ 28天主线故事内容
✅ 触发器系统                     ○ 5幕剧情脚本
✅ 效果序列系统                   ○ 4种结局分支
✅ Mod/模组API                    ○ 故事包创作工具链
```

### 3.2 每日内容配置系统 (DayConfig)

**优先级：** ★★★★★（核心系统，其他叙事功能的基础）
**当前状态：** `daily_dialogues` 已实现基础对话触发，需扩展为完整日配置
**目标：** 每天控制内容解锁、邮件投递、信号激活、环境覆盖、触发器等全部叙事通道

**数据结构设计：**

```json
{
  "day": 5,
  "act": "act1",
  "title": "第五天 — 安静的早晨",

  "env_overrides": {
    "force_weather": "fog",
    "sensor_bias": { "mag_field": 15.0, "radiation": 0.02 },
    "force_events": ["magnetic_pulse"]
  },

  "dialogues": {
    "on_start": ["day5_morning"],
    "on_scan_complete": ["day5_discovery"],
    "on_anomaly": [],
    "on_idle_300": ["day5_idle_hint"]
  },

  "unlocks": {
    "files": ["/logs/prev_operator_03.txt"],
    "mail": ["hq_weekly_update_2"],
    "radio_signals": ["signal_unknown_03"],
    "passwords": { "deep_archive": "LIGHTHOUSE" },
    "cameras": ["cam_03"]
  },

  "triggers": {
    "on_read_complete:/classified/report_07.txt": "comm:ava_react_report07",
    "on_open_file:prev_operator_03.txt": "delay:3000:new_mail:hq_warning"
  }
}
```

**实现要点：**
- 新建 `day_config_manager.gd`（RefCounted），由 main.gd 实例化
- 数据来源：manifest.json 中的 `"days"` 字段，或 `days/day_XX.json` 独立文件
- 每天启动时（boot_sequence完成后）自动应用当天配置
- 与 disc_manager、trigger_system、mail_system、radio_signal_manager、env_monitor、camera_manager 联动
- 天数推进逻辑：env_task_manager 的每日任务全部完成 → 允许结束当天 → 自动存档 → 下次启动进入下一天

### 3.3 剧情变量系统 (StoryVariables)

**优先级：** ★★★★☆
**当前状态：** save_manager 中有 `story_choices` 和 `story_flags` 基础字段
**目标：** 完整的数值/布尔型变量追踪，支持条件表达式，驱动对话分支和内容解锁

**核心变量示例：**

| 变量名 | 类型 | 范围 | 说明 |
|--------|------|------|------|
| `trust_ava` | int | 0-100 | 对AVA的信任度 |
| `truth_discovered` | int | 0-5 | 发现了多少层真相 |
| `hq_suspicion` | int | 0-100 | 总部对玩家的怀疑度 |
| `chose_to_report` | bool | — | 是否选择向总部上报异常 |
| `found_prev_log` | bool | — | 是否找到前任操作员的日志 |
| `researcher_contact` | bool | — | 是否与研究员建立联系 |

**实现要点：**
- 新建 `story_variables.gd`（RefCounted）
- 变量定义来自 manifest.json 中的 `"story_variables"` 字段
- 提供 `get_var(name)` / `set_var(name, value)` / `modify_var(name, delta)` 接口
- 条件表达式引擎：解析 `"trust_ava >= 50 AND found_prev_log"` 格式的条件字符串
- 与 save_manager 集成：变量随存档自动持久化
- 对话系统支持 `"condition"` 字段引用变量条件
- ModAPI 扩展：`api.story_get_var()` / `api.story_set_var()` / `api.story_check_condition()`

### 3.4 结局判定系统 (EndingResolver)

**优先级：** ★★★☆☆（依赖 StoryVariables 完成后实现）
**目标：** 根据剧情变量在终章(Day 22-28)判定结局走向

**四种结局设计：**

| 结局 | 条件 | 体验 |
|------|------|------|
| A "服从者" | `truth_discovered < 2` | 从不质疑，被调离，永不知真相 |
| B "发现者" | `truth_discovered >= 2 AND chose_to_report == false` | 发现部分真相但沉默，带着秘密离开 |
| C "揭露者" | `truth_discovered >= 4 AND chose_to_report == true` | 发现全部真相并对外传播，高风险结局 |
| D "理解者" | `truth_discovered == 5 AND trust_ava >= 80` | 最完整体验，理解事物全貌 |

**实现要点：**
- 新建 `ending_resolver.gd`（RefCounted）
- 结局条件定义在 manifest.json 的 `"endings"` 字段
- 每个结局关联独立的内容（对话、邮件、文件、效果序列）
- 在终章开始时评估条件，确定结局走向并加载对应内容

### 3.5 角色关系系统 (CharacterRelationship)

**优先级：** ★★★☆☆（依赖 StoryVariables）
**目标：** 追踪玩家与每个角色的关系值，关系值影响对话内容

**实现要点：**
- 可作为 StoryVariables 的特殊子集实现（如 `rel_ava`, `rel_hq` 变量）
- 对话选择通过 `modify_var("rel_ava", +10)` 调整关系
- 拨号对话加载时检查关系值，选择不同的对话分支
- 高关系值角色透露更多信息，低关系值角色变得疏远或敌对

### 3.6 每日拨号对话轮换

**优先级：** ★★★★☆
**当前状态：** 角色拨号对话ID固定
**目标：** 同一角色每天返回不同的对话内容

**实现方案：**
- 在 DayConfig 中定义每日拨号对话映射：`"dial_dialogues": { "ava": "ava_call_day5" }`
- DialManager 查询当天 DayConfig 获取对话ID
- 无特定配置时回退到角色的 `default_call` 对话
- 已拨打过的对话标记为 `repeatable: false`，当天不再重复

---

## 四、28天主线故事内容规划

> 基于《游戏设计文档》的5幕剧情结构，以下为主线故事的章节概要。

### 4.1 故事概要

**设定：** 玩家扮演OB-7K前哨观测站的新任操作员。表面上这是一座偏远的气象/环境监测站，实际上是SCP基金会的外围监控节点。通过28天的工作循环，玩家逐步发现数据异常、前任失踪的真相、以及这座岛屿隐藏的秘密。

**三层叙事结构：**
- **表层：** 我是前哨站操作员，负责记录环境数据
- **中层：** 数据不对劲，总部的回复很奇怪
- **深层：** 这座岛上藏着SCP基金会的秘密

### 4.2 章节结构

| 章节 | 天数 | 基调 | 核心目标 |
|------|------|------|---------|
| **序章：适应期** | Day 1-3 | 平静、教学 | 熟悉系统、建立日常感、铺设基准线 |
| **第一章：初兆** | Day 4-7 | 微妙不安 | 种下疑问种子——数据偏移/总部敷衍/未知信号 |
| **第二章：暗涌** | Day 8-14 | 紧张、发现 | 第二叙事层全面展开——异常频率上升/误发邮件/前任日志 |
| **第三章：真相** | Day 15-21 | 揭示、抉择 | 第三叙事层揭开——SCP真相/总部矛盾指令/关键选择 |
| **终章：结局** | Day 22-28 | 取决于选择 | 收束叙事线——4种结局分支 |

### 4.3 角色阵容

| 代号 | 身份 | 叙事功能 | 出场时间 |
|------|------|---------|---------|
| **AVA** | AI联络员 | 导师/同伴/可能的威胁，始终在线 | Day 1 起 |
| **HQ** | 总部管控 | 权威/信息源/可能的谎言，通过邮件和偶尔通讯 | Day 4 起 |
| **前任** | 前操作员 | "幽灵"角色，通过日志和录音出现 | Day 4 起(文件) |
| **研究员** | Site科学家 | 知情者/盟友，拥有关键信息 | Day 8 起 |
| **???** | 未知信号源 | 悬念/恐惧/超自然要素，无线电中偶尔出现 | Day 6 起 |

### 4.4 多通道叙事协同

SCRT-Reader 的独特优势在于多种叙事通道的协同运用：

| 通道 | 适合的叙事类型 | 对应系统 |
|------|---------------|---------|
| **通讯对话** | 即时、情感化、角色关系导向 | CommManager / DialManager |
| **邮件** | 正式、延迟、有层次的信息传递 | MailSystem |
| **文件系统** | 深度、需主动发掘的线索 | FileSystem / DocumentViewer |
| **环境数据** | 渐进、非文字、需要观察力 | EnvMonitor / EnvViewer |
| **无线电信号** | 神秘、碎片化、需要破译 | RadioReceiver |
| **摄像头** | 视觉、直觉、恐惧氛围 | CameraManager / CameraViewer |

### 4.5 内容制作需求估算

| 内容类型 | 28天总量估算 | 说明 |
|---------|-------------|------|
| 对话脚本 | ~150段 | 主线+拨号+反应+空闲，5个角色 × 28天 |
| 邮件 | ~40封 | 总部指令/角色通讯/系统通知 |
| 文件文档 | ~60份 | 报告/日志/SCP档案/加密文件 |
| 无线电信号 | ~20个 | 摩斯码/SSTV图像/音频电台/隐藏信号 |
| 环境事件配置 | ~15个 | 自定义天气/传感器偏移/异常触发 |
| 摄像头场景 | ~8组 | 基础/深度/光照/异常图层 |
| 效果序列 | ~25个 | 故障/震动/黑屏/重启/综合效果 |
| 音效素材 | ~30个 | 环境音/提示音/角色语音音色 |

---

## 五、实施路线图

### Phase A：代码质量与技术债务清理

**周期：** 1-2周
**优先级：** ★★★★★
**目标：** 在新功能开发前消除技术债务，提高代码可维护性

| 任务 | 涉及文件 | 预期效果 |
|------|---------|---------|
| 修复3处 `user://` 路径残留 | video_player.gd, package_manager.gd, story_loader.gd | 路径体系统一 |
| main.gd 拆分 | main.gd → main.gd + input_router.gd + mode_manager.gd | 主文件从1939行降至~800行 |
| command_handler.gd 模块化 | command_handler.gd → 路由器 + 子处理器 | 命令系统可插拔 |
| 大文档分段加载 | crtml_parser.gd / typewriter.gd | 解决超长文档渲染延迟 |

### Phase B：叙事核心系统开发

**周期：** 2-3周
**优先级：** ★★★★★
**前置：** Phase A（建议在代码清理后开始）
**目标：** 实现"完整游戏体验"所需的4个核心叙事系统

| 任务 | 新增文件 | 集成点 |
|------|---------|--------|
| DayConfig系统 | `day_config_manager.gd` | main.gd, disc_manager.gd, trigger_system.gd, mail_system.gd, radio_signal_manager.gd, env_monitor.gd, camera_manager.gd |
| StoryVariables系统 | `story_variables.gd` | save_manager.gd, comm_dialogue_player.gd, mod_api.gd |
| 条件表达式引擎 | (嵌入 story_variables.gd) | comm_dialogue_player.gd, day_config_manager.gd |
| 每日拨号对话轮换 | (修改 dial_manager.gd) | day_config_manager.gd |

### Phase C：主线内容·序章与第一章

**周期：** 2-3周
**优先级：** ★★★★☆
**前置：** Phase B
**目标：** 完成Day 1-7的全部游戏内容，验证完整的单日循环流程

| 任务 | 交付物 |
|------|--------|
| Day 1-3 序章内容 | 对话脚本(~20段)、邮件(~5封)、文件(~8份)、环境配置(~3天)、教学流程 |
| Day 4-7 第一章内容 | 对话脚本(~25段)、邮件(~8封)、文件(~10份)、无线电信号(~5个)、环境事件(~4个) |
| 角色素材 | AVA/HQ角色配置、语音音色定义 |
| 通关测试 | 完整7天循环流程验证，无卡死/状态异常 |

### Phase D：结局与关系系统 + 第二章

**周期：** 2-3周
**优先级：** ★★★☆☆
**前置：** Phase C
**目标：** 实现角色关系和结局判定系统，完成第二章内容

| 任务 | 新增文件 | 说明 |
|------|---------|------|
| EndingResolver | `ending_resolver.gd` | 4结局条件评估+内容加载 |
| CharacterRelationship | (融入 story_variables.gd) | 关系值变量+对话分支 |
| Day 8-14 内容 | 对话/邮件/文件/信号/事件 | 第二叙事层全面展开 |

### Phase E：主线内容完成

**周期：** 3-4周
**优先级：** ★★★☆☆
**前置：** Phase D
**目标：** 完成Day 15-28的全部游戏内容及4种结局分支

| 任务 | 说明 |
|------|------|
| Day 15-21 第三章 | 真相揭示、关键抉择、SCP内容 |
| Day 22-28 终章 | 4种结局分支内容(各约15段对话+专属文件+效果序列) |
| 完整通关测试 | 28天全流程 × 4结局分支验证 |

### Phase F：社区生态与平台扩展

**周期：** 2-3周（可并行）
**优先级：** ★★☆☆☆
**目标：** 支持社区创作和平台覆盖

| 任务 | 说明 |
|------|------|
| 故事包创作指南更新 | 更新 story-authoring-guide.txt 覆盖新系统(DayConfig/StoryVariables等) |
| 示例故事包 | 提供带DayConfig的完整示例 .scp |
| 内容包验证工具 | CLI脚本验证manifest结构、资源引用完整性 |
| 多语言支持(i18n) | 界面文本外置为翻译文件 |
| macOS适配测试 | Godot 4.6 macOS导出 + 测试 |
| Web导出评估 | GL Compatibility渲染器的Web可行性测试 |

---

## 六、关键文件索引

### 6.1 需修改的现有文件

| 文件 | 修改内容 | 所属阶段 |
|------|---------|---------|
| `main.gd` | 拆分InputRouter/ModeManager、集成DayConfig/StoryVariables | Phase A, B |
| `video_player.gd` | 修复user://路径 | Phase A |
| `package_manager.gd` | 修复user://路径 | Phase A |
| `story_loader.gd` | 修复user://路径 | Phase A |
| `command_handler.gd` | 模块化拆分 | Phase A |
| `dial_manager.gd` | 集成每日对话轮换 | Phase B |
| `comm_dialogue_player.gd` | 支持变量条件分支 | Phase B |
| `disc_manager.gd` | 加载DayConfig数据 | Phase B |
| `save_manager.gd` | 持久化StoryVariables和关系值 | Phase B |
| `mod_api.gd` | 新增story/day相关API | Phase B |

### 6.2 需新建的文件

| 文件 | 类名 | 功能 | 所属阶段 |
|------|------|------|---------|
| `day_config_manager.gd` | DayConfigManager | 每日内容配置加载/应用 | Phase B |
| `story_variables.gd` | StoryVariables | 剧情变量追踪/条件评估 | Phase B |
| `ending_resolver.gd` | EndingResolver | 结局条件判定/内容加载 | Phase D |
| `input_router.gd` | InputRouter | 输入分发+模式标志管理 | Phase A |
| `mode_manager.gd` | ModeManager | 模式切换逻辑 | Phase A |

### 6.3 需创建的内容文件

| 目录/文件 | 说明 | 所属阶段 |
|----------|------|---------|
| `data/main/days/day_01.json` ~ `day_28.json` | 每日配置文件 | Phase C-E |
| `data/main/dialogues/ava/*.json` | AVA角色对话脚本 | Phase C-E |
| `data/main/dialogues/hq/*.json` | HQ角色对话脚本 | Phase C-E |
| `data/main/dialogues/researcher/*.json` | 研究员角色对话脚本 | Phase D-E |
| `data/main/mail/*.txt` | 邮件模板文件 | Phase C-E |
| `data/main/files/**/*.txt` | 故事文件内容(CRTML) | Phase C-E |
| `data/main/signals/*.json` | 无线电信号定义 | Phase C-E |

---

## 七、验证方案

### 7.1 单日循环验证清单

每完成一天的内容，需验证以下完整流程：

- [ ] 开机启动 → 日期显示正确 → 晨间通讯正常触发
- [ ] env scan → 扫描报告显示正确 → 异常标记（如有）正确
- [ ] 新内容解锁 → 文件可见/邮件到达/信号可收 → 与DayConfig一致
- [ ] 拨号对话 → 当天对话正确加载 → 选择影响变量正确记录
- [ ] 空闲触发 → 指定时间后角色主动联络
- [ ] 任务完成 → 环境监测任务全部完成 → 允许结束当天
- [ ] 自动存档 → 变量/进度正确保存 → 重启后恢复到正确状态

### 7.2 结局验证矩阵

| 测试场景 | 变量状态 | 预期结局 |
|---------|---------|---------|
| 从不质疑，按部就班 | truth < 2 | A "服从者" |
| 发现部分，选择沉默 | truth >= 2, report = false | B "发现者" |
| 发现全部，选择揭露 | truth >= 4, report = true | C "揭露者" |
| 发现全部，理解接受 | truth = 5, trust_ava >= 80 | D "理解者" |

### 7.3 回归测试要点

- 现有 .scp 故事包（无DayConfig）仍能正常加载运行
- 新系统（DayConfig/StoryVariables）对不使用这些功能的故事包无影响
- Mod API新增接口向后兼容
- 设置系统、存档系统在新增数据字段后仍能加载旧存档

---

## 八、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| main.gd拆分引入回归bug | 高 | 拆分后全面功能回归测试；保持拆分粒度适中，避免过度拆分 |
| DayConfig数据格式频繁变更 | 中 | 先实现序章(3天)，验证格式后再批量编写 |
| 28天内容创作量过大 | 高 | 采用分章节交付策略；序章可作为独立Demo发布 |
| 条件表达式引擎复杂度 | 中 | 初期仅支持简单的 AND/OR + 比较运算符，不做完整脚本语言 |
| 多结局分支内容倍增 | 中 | 结局分歧点集中在终章最后3-5天，前期内容大部分共享 |
| 旧存档兼容性 | 低 | 新增字段使用默认值回退，不破坏现有存档结构 |

---

## 九、长远规划

以下为Phase F之后的远景方向，视项目发展和社区反馈决定优先级：

| 方向 | 说明 | 前置条件 |
|------|------|---------|
| **Steam/itch.io 发布** | 将OB-7K主线打包为独立游戏发布 | Phase E 完成 |
| **社区故事包平台** | 在线浏览/下载/评分社区创作的 .scp 故事包 | Modem下载功能已具备基础 |
| **自定义模板机制** | 允许 .scp 内定义新文档模板（V1.0.1阶段八规划） | 优先级随社区需求调整 |
| **可视化故事编辑器** | 基于Web或Electron的故事包可视化创作工具 | 需求明确后启动 |
| **移动端适配** | Android/iOS触屏交互适配 | 需重新设计输入交互 |
| **多人/在线元素** | 共享观测站日志、异步消息等社交机制 | 需服务端架构 |

---

## 附录A：当前全部终端命令清单

### 全局命令（桌面+磁盘模式均可用）

| 命令 | 别名 | 功能 |
|------|------|------|
| `help` | — | 查看命令帮助 |
| `clear` | `cls` | 清屏 |
| `whoami` | — | 显示当前用户身份 |
| `status` | — | 显示系统状态 |
| `mail` | — | 查看/阅读邮件 |
| `theme` | — | 切换颜色主题 |
| `volume` | `vol` | 音量控制 |
| `reboot` | — | 模拟终端重启 |
| `exit` | `quit` | 退出/关机 |
| `profile` | — | 查看用户档案 |
| `logout` | — | 注销当前用户 |
| `passwd` | — | 修改密码 |
| `birthday` | — | 设置生日 |
| `nickname` | — | 设置昵称 |
| `gender` | — | 设置性别 |
| `users` | — | 查看用户列表 |
| `decode` | — | 密码破译工具 |
| `fx_level` | — | 效果强度设置 |
| `fx_safe` | — | 光敏安全模式 |
| `sound` | — | 音效开关 |
| `packages` | `pkg` | 模组管理 |
| `uninstall` | — | 卸载模组 |
| `comm` | — | 通讯系统 |
| `dial` | — | 拨号 |
| `phonebook` | `pb` | 号码簿 |
| `settings` | `set` | 设置面板 |
| `env` | `monitor` | 环境监测系统 |
| `camera` | `cam`, `cctv` | 监控摄像头 |
| `save` | — | 手动保存 |

### 桌面模式专用

| 命令 | 功能 |
|------|------|
| `scan` | 扫描可用磁盘 |
| `load` | 加载故事磁盘 |
| `vdisc` | 磁盘管理 |
| `deluser` | 删除用户 |
| `explore` | 文件探索器 |
| `install` | 安装模组 |

### 磁盘模式专用

| 命令 | 别名 | 功能 |
|------|------|------|
| `ls` | `dir` | 列出文件 |
| `cd` | — | 切换目录 |
| `back` | — | 返回上级 |
| `open` | `read`, `cat` | 打开/阅读文件 |
| `unlock` | — | 解锁加密内容 |
| `eject` | — | 弹出磁盘 |
| `clearsave` | — | 清除存档 |
| `radio` | — | 无线电接收器 |
| `explore` | — | 文件探索器 |

---

## 附录B：系统架构依赖图（当前）

```
main.gd (Control) — 上帝对象
├─ fs: FileSystem — 虚拟文件系统
├─ save_mgr: SaveManager — 存档管理
├─ tw: Typewriter (Node) — 打字机输出 + 内联效果
├─ T: ThemeManager — 主题管理(4主题)
├─ story_loader: StoryLoader — .scp ZIP解析
├─ cmd_handler: CommandHandler — 命令注册/分发
├─ disc_mgr: DiscManager — 磁盘扫描/加载/弹出
├─ user_mgr: UserManager — 多用户账户系统
├─ crtml: CrtmlParser — CRTML → BBCode解析
├─ pkg_mgr: PackageManager — 模组安装/卸载/生命周期
├─ settings_mgr: SettingsManager — 注册表设置系统
├─ comm_mgr: CommManager — 对话编排
│  ├─ dial_mgr: DialManager — DTMF拨号状态机
│  └─ tone_gen: DialToneGenerator — 程序化音频合成
├─ trigger_sys: TriggerSystem — 事件触发器
├─ mail_sys: MailSystem — 邮件系统
├─ effect_sys: EffectSystem — 效果序列引擎
├─ effect_settings: EffectSettings — 效果强度/安全设置
├─ boot_sequence: BootSequence — 开机/关机动画
├─ loading_screen: LoadingScreen — 加载动画
├─ doc_viewer: DocumentViewer — 文档查看器
├─ profile_builder: ProfileBuilder — 用户档案构建
├─ explore_viewer: ExploreViewer — 文件探索面板
├─ image_viewer: ImageViewer — 图片查看器
├─ oscilloscope: Oscilloscope — 频谱可视化
├─ video_player_viewer: VideoPlayerViewer — 视频播放器
├─ radio_receiver: RadioReceiver — 无线电接收器
├─ decode_viewer: DecodeViewer — 密码破译查看器
├─ ui_sound: UiSound — 程序化UI音效
├─ camera_mgr: CameraManager — 摄像头管理
├─ camera_viewer: CameraViewer — 摄像头查看器
├─ env_monitor: EnvMonitor — 环境监测模拟
├─ env_task_mgr: EnvTaskManager — 每日任务管理
├─ env_viewer: EnvViewer — 环境数据面板
├─ audio_manager: AudioManager (Node) — 音频管理(环境/音效/媒体)
└─ crt_shader: CRTShader (ColorRect) — CRT后处理着色器
```

### V2.0 新增系统（规划）

```
main.gd
├─ ... (现有系统)
├─ day_config_mgr: DayConfigManager — ★ 每日内容配置 (Phase B)
├─ story_vars: StoryVariables — ★ 剧情变量系统 (Phase B)
└─ ending_resolver: EndingResolver — ★ 结局判定系统 (Phase D)

main.gd 拆分后 (Phase A):
├─ input_router: InputRouter — ★ 输入分发+模式标志
└─ mode_mgr: ModeManager — ★ 模式切换逻辑
```

---

*文档结束。本规划将根据开发进度和社区反馈持续更新。*
