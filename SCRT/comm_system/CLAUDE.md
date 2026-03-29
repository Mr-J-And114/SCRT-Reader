# comm_system/ — 通讯系统 (Dialogue, Dial & Character System)

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 数据格式：[/docs/data-formats.md](/docs/data-formats.md)
> 修改通讯/角色/拨号逻辑后请同步更新本文件。

通讯子系统，处理角色对话、语音通话、调制解调器下载和模块化角色管理（含分层精灵系统）。
包含 13 个脚本文件，是系统数量最多的子目录。

## 重要陷阱

### silent stop（最常见的坑）
`CommDialoguePlayer.stop_dialogue(silent=true)` 用于对话段落之间的转场。
`silent=false`（默认）用于自然结束——触发 UI 隐藏和挂断。
**用错会导致多段对话中 UI 提前关闭。**

### 语音通话时序
`CommManager._on_dialogue_finished()` 在调用 `dial_mgr.on_voice_call_ended()` 前延迟 **1.0 秒**。
这让 UI 关闭动画有时间完成。不要缩短此延迟，否则挂断音会与对话重叠。

## 文件列表

| 文件 | 行数 | 用途 |
|---|---|---|
| comm_manager.gd | 1259 | 对话编排、通话路由、教程流程、`comm` 命令处理，委托给 registry |
| comm_ui.gd | 1289 | 通讯覆盖层 UI（对话条、卡片/会议/演示模式、历史记录） |
| dial_manager.gd | 831 | DTMF 拨号状态机、通话路由、调制解调器握手/下载、电话簿 |
| comm_character.gd | 426 | 轻量角色数据模型（身份信息 + 语音配置，委托给 animator） |
| character_asset_library.gd | 420 | 素材配置库、模块化纹理加载（res:// + 虚拟文件系统） |
| character_animator.gd | 387 | 动画引擎（口型同步、眨眼、动作帧、图层覆盖、服装切换） |
| comm_dialogue_player.gd | 377 | 对话播放引擎（逐行播放、选项分支、条件判断、幻灯片、静默停止） |
| dial_tone_generator.gd | 376 | 程序化音频生成：DTMF 按键音/回铃/忙音/调制解调器握手/数据噪声/挂断/来电铃声 |
| character_registry.gd | 297 | 角色生命周期管理、注册（内置/故事盘/Mod 三种来源） |
| presentation_overlay.gd | 295 | 演示模式幻灯片覆盖层（图片显示、适配/对齐/区域配置 + 过渡效果） |
| comm_voice.gd | 188 | 程序化语音合成（正弦/方波/锯齿波音调） |
| comm_sprite_renderer.gd | 181 | 角色精灵渲染（卡片模式下的头像显示） |

## 角色系统架构

```
CharacterRegistry（角色注册中心）
├─ CharacterAssetLibrary（素材库）
│  ├─ AssetProfile（每个角色的素材定义：图层/眼睛/嘴型/服装/动作）
│  └─ CharacterTextures（已加载的纹理缓存）
├─ CommCharacter（角色数据模型：身份 + 语音 + 状态）
│  └─ CharacterAnimator（动画控制器：口型/眨眼/动作帧/图层覆盖）
└─ 来源标识：BUILTIN（内置）/ DISC（故事盘）/ MOD（Mod）
```

### 添加新角色
1. 创建 `AssetProfile`（参考 `CharacterAssetLibrary.create_ava_profile()`）
2. 注册素材配置：`asset_library.register_profile("char_id", profile)`
3. 注册角色配置：`registry.register_character("char_id", config)`
4. 角色通过 `init_from_asset_library()` 自动加载素材

### 对话 JSON 角色控制标记
```json
{
  "character": "ava",
  "text": "你好！",
  "expression": "neutral",
  "action": "nod",
  "costume": "lab_coat",
  "layer_override": { "eye_L": "eye_L_close", "eye_R": "eye_R_open" },
  "layer_override_duration": 5.0,
  "clear_overrides": true,
  "anim_effect": "wink_left:2.0"
}
```

可用 `anim_effect` 值：`wink_left`、`wink_right`、`eyes_closed`、`surprised`
（均接受可选 `:duration` 后缀，默认 2.0 秒）

## 来电模式 (CallHandler)

CallHandler 管理三种来电模式，从 CommManager 中分离出来：

| 模式 | 行为 |
|---|---|
| SILENT | 直接开始对话，无铃声。`comm:dialogue_id` 触发器的默认模式 |
| FORCED | 铃声响起 → N 次铃声后自动接听。玩家无法拒绝 |
| ANSWERABLE | 铃声响起 → 提示。玩家需输入 `comm answer` 或 `comm reject` |

状态机：`IDLE → RINGING → WAITING_ANSWER → IDLE`

### 触发器动作格式
`comm:dialogue_id:forced` 或 `comm:dialogue_id:answerable`

## 显示模式 (CommUI)

| 模式 | 说明 |
|---|---|
| `"card"` | 小头像卡片在对话条旁（默认模式） |
| `"meeting"` | Galgame 风格的大角色立绘，按插槽 z 排序 |
| `"presentation"` | 会议模式 + 幻灯片覆盖层（支持适配/对齐/区域配置） |

通过对话行 JSON 的 `"display_mode"` 字段设置。

### 演示模式幻灯片字段

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| slide_image | String | — | 幻灯片图片路径 |
| slide_position | [x, y] | [0.55, 0.1] | 归一化位置 (0.0~1.0) |
| slide_size | [w, h] | [0.4, 0.5] | 归一化尺寸 (0.0~1.0) |
| slide_area | [x, y, w, h] | — | 显示区域（覆盖 position+size） |
| slide_fit | String | "contain" | 图片适配：contain/cover/stretch/actual |
| slide_align | String | "center" | 区域内对齐方式（9 种位置） |
| slide_transition | String | "fade" | 过渡效果：fade/instant/slide_left/slide_right |

隐藏幻灯片：`"slide_hide": true` 或 `"slide_hide": "slide_left"`

## Comm 命令

| 命令 | 说明 |
|---|---|
| `comm` | 显示通讯状态 |
| `comm answer` | 接听来电 |
| `comm reject` | 拒接来电 |
| `comm video` | 列出视频频道 |
| `comm video <num>` | 拨打视频频道 |
| `comm phonebook` | 显示电话簿 |
| `comm history` / `comm log` | 查看通讯历史 |

## 拨号状态机

```
IDLE → DTMF_PLAYING → RINGING → BUSY（无效号码）
                              → VOICE_CONNECTING → VOICE_ACTIVE → CALL_ENDED → IDLE
                              → MODEM_INIT → MODEM_CARRIER → MODEM_TRAINING
                                → MODEM_NEGOTIATION → MODEM_DOWNLOADING → MODEM_COMPLETE → CALL_ENDED → IDLE
```

**DialState 枚举**（完整状态列表）：
`IDLE` `DTMF_PLAYING` `RINGING` `BUSY` `VOICE_CONNECTING` `VOICE_ACTIVE`
`MODEM_INIT` `MODEM_CARRIER` `MODEM_TRAINING` `MODEM_NEGOTIATION` `MODEM_DOWNLOADING` `MODEM_COMPLETE` `CALL_ENDED`

**CallType 枚举**：`NONE` / `VOICE` / `MODEM` / `INVALID`
- 拨号系统通过 `dial_mgr.process(delta)` 在 `main._process()` 中后台运行
- **不阻塞**终端输入

## 通话类型

| 类型 | 流程 | 结果 |
|---|---|---|
| VOICE | DTMF → 1 秒 → 回铃 → 接通 → CommManager 对话 | 挂断音 |
| MODEM | DTMF → 1 秒 → 回铃 → AT 命令 → 载波检测 → 握手 → 下载 | 文件保存到 vdisc/ |
| INVALID | DTMF → 1 秒 → 忙音 | "号码不存在" |

## 电话号码来源（优先级顺序）

1. **故事盘**：`manifest.json` → `dial_directory` 节（DiscManager 加载时注入）
2. **系统注册**：通过 `register_system_voice()` / `register_system_modem()` 编程注册
3. **预设**：`res://data/dial_directory.json`（内置，启动时加载）
