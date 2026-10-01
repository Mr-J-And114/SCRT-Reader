# comm_system/ — 通讯系统 (Dialogue, Dial & Character System)

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 数据格式：[/docs/data-formats.md](/docs/data-formats.md)
> 修改通讯/角色/拨号逻辑后请同步更新本文件。

通讯子系统，处理角色对话、语音通话、调制解调器下载和模块化角色管理（含分层精灵系统）。
包含 14 个脚本文件，是系统数量最多的子目录。

## 重要陷阱

### silent stop（最常见的坑）
`CommDialoguePlayer.stop_dialogue(silent=true)` 用于对话段落之间的转场。
`silent=false`（默认）用于自然结束——触发 UI 隐藏和挂断。
**用错会导致多段对话中 UI 提前关闭。**

### 语音通话时序
`CommManager._on_dialogue_finished()` 在调用 `dial_mgr.on_voice_call_ended()` 前延迟 **1.0 秒**。
这让 UI 关闭动画有时间完成。不要缩短此延迟，否则挂断音会与对话重叠。

### next 链与 call_mode（2026-08-19 新增行为）
`next` 续播链 0.3s 后触发目标对话时，**若目标对话声明了 `call_mode`（forced/answerable）则走来电流程（响铃），否则静默续播**。
例：`d0_04` 的 next `["d0_05"]`，`d0_05` 声明 `call_mode: "answerable"` → 播完 d0_04 后响铃，玩家 `comm answer` 接听。

### meeting 模式延续（2026-08-19 新增行为）
`CommDialoguePlayer._play_current_line()` 中，行级 `display_mode` 为空但**当前 UI 已在 meeting/presentation 模式**时，仍会按该行 `meeting_slot` 设置角色位置。
即会议对话只需首行写 `display_mode: "meeting"`，后续行写 `meeting_slot` 即可（无需每行重复声明）。

## 文件列表

| 文件 | 行数 | 用途 |
|---|---|---|
| comm_manager.gd | 1466 | 对话编排、通话路由、教程入口（Day0 由 DailyDialogue 驱动）、对话链续播（next，目标声明 call_mode 时响铃）、场景邮件投递、flags_add、拨号条件选择、错过来电回拨补救、拒接后果触发，委托给 registry |
| comm_ui.gd | 1353 | 通讯覆盖层 UI（对话条、卡片/会议/演示模式、历史记录） |
| dial_manager.gd | 839 | DTMF 拨号状态机、通话路由、调制解调器握手/下载、Vdisc 任务副本登记、电话簿 |
| comm_character.gd | 446 | 轻量角色数据模型（身份信息 + 语音配置，委托给 animator） |
| character_asset_library.gd | 560 | 素材配置库、模块化纹理加载（res:// + 虚拟文件系统） |
| character_animator.gd | 387 | 动画引擎（口型同步、眨眼、动作帧、图层覆盖、服装切换） |
| comm_dialogue_player.gd | 400 | 对话播放引擎（逐行播放、选项分支、条件判断、幻灯片、静默停止、行级 story_action、meeting 模式延续） |
| call_handler.gd | 328 | 呼叫模式处理器：SILENT/FORCED/ANSWERABLE 来电生命周期、铃声控制、错过来电记录、拒接后果传递 |
| dial_tone_generator.gd | 376 | 程序化音频生成：DTMF 按键音/回铃/忙音/调制解调器握手/数据噪声/挂断/来电铃声 |
| character_registry.gd | 318 | 角色生命周期管理、注册（内置/故事盘/Mod 三种来源） |
| presentation_overlay.gd | 295 | 演示模式幻灯片覆盖层（图片显示、适配/对齐/区域配置 + 过渡效果） |
| comm_voice.gd | 106 | 逐字符合成短音、混合谐波、音量包络、中英文标点静音 |
| voice_tuner.gd | 229 | 编辑器实时调音面板：滑块、中文循环试听、保存/恢复/复制配置 |
| comm_sprite_renderer.gd | 181 | 角色精灵渲染（卡片模式下的头像显示） |

## 角色系统架构

`debug 114514 voice_meeting [角色ID...]` 读取 `meeting_voice_demo.json` 自动演示多人会议：全部参与者同时入场，开场留白，再逐人介绍与朗读统一对比句。`CommManager.start_voice_meeting_demo(scene)` 接受 `participants`（id/slot/intro）、`comparison_text`、`gap_seconds`、`lead_in_seconds`，仅使用已注册角色，可扩展多于三人。测试使用独立调试 ID，跳过通讯历史、完成状态和剧情信号；正常剧情在测试播放期间不覆盖它。

角色声音集中在 `voice_presets.json`，由 `CommManager` 在教程角色加载后应用。Ava / kanda / nanami 的初始基频分别为 345 / 480 / 390 Hz，音色为 warm / sharp / clear。`debug 114514 voice` 在编辑器内打开 `VoiceTuner`；滑块即时修改角色，试听独立播放，保存三人配置写回项目 JSON。面板打开时通讯暂停、终端输入路由让行；Esc 关闭。详见 `docs/debug-mode-guide.md`。旧故事盘的 `base_pitch` 仍兼容。

内置 `kanda` 角色使用 `images/character/rei/` 的 Rei 分层素材。渲染顺序从底到顶为 braid、body、head、mouth、nose、eye_L、eye_R、eyehair；无对话或动作时使用 `-0` 眼睛和嘴型。

卡片头像裁剪到卡片矩形内；会议立绘由 `MeetingPortraitClip` 裁剪到对话栏上沿。角色仍使用原始图层纹理；Rei 的大小由 `create_rei_profile()` 中的 `display_scale`（当前 `1.20`）控制，`display_offset` 同时影响卡片与 meeting 模式，`meeting_offset` 只额外影响 meeting 模式。偏移量 X 正数向右、Y 正数向下；Rei 当前 `meeting_offset = Vector2(0, -50)`，用于修正大图下沉，不影响卡片位置。角色宽度按素材画布比例计算，横向中心会限制在屏幕范围内。

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

## 对话级字段（2026-08-19 Day0 剧情新增）

| 字段 | 位置 | 说明 |
|---|---|---|
| `next` | 对话级 | Array[String]，对话自然结束后自动续播的对话 ID 队列（0.3s 间隔，skip_call_mode） |
| `deliver_mail` | 对话级 | String/Array，结束时投递当日配置中 `deliver_on: "scene"` 的邮件 |
| `flags_add` | 对话级 | Dictionary，对话开始时对剧情标记做增量累加（如 `{"anger_ava": 1}`） |
| `story_action` | 行级 | String/Array，行开始播放时执行触发器动作（如 `"score:1:daily"`） |
| `requires_tasks` | 对话级 | `"all"`（当日 env 任务+日报全部完成）/ `"incomplete"`（未全部完成），供拨号条件选择 |
| `reject_consequence` | 对话级 | String，answerable 来电被拒后执行的触发器动作（如 `"comm:d0_05_reject:silent"`） |
| `skippable: false` | 对话级 | 禁止 ESC 跳过（主线剧情对话） |

拨号触发的对话选择（`start_dialogue_from_dial`）：
1. 角色名模式匹配（`{char}_chat` / `{char}_greeting` / `{char}_main` / `comm_{char}`）
2. 兜底：首个说话角色匹配 + 可呼叫 + `_is_dial_available()`（未完成或可重复，且剧情条件通过）
3. 全部失败 → "联络员 XXX 当前不可用"

## 来电模式 (CallHandler)

CallHandler 管理三种来电模式，从 CommManager 中分离出来：

| 模式 | 行为 |
|---|---|
| SILENT | 直接开始对话，无铃声。`comm:dialogue_id` 触发器的默认模式 |
| FORCED | 响铃 **1 次** → 自动接听 → 提示"本次通讯为强制接听，无法拒绝"。玩家无法拒绝 |
| ANSWERABLE | 响铃 **1 次** → 提示。玩家需输入 `comm answer` 或 `comm reject` |

状态机：`IDLE → RINGING → WAITING_ANSWER → IDLE`

**铃声次数**：所有模式统一只响 **1 次**铃声（`FORCED_RING_COUNT=1`、`ANSWERABLE_RING_COUNT=1`）。

### 触发器动作格式
`comm:dialogue_id:forced` 或 `comm:dialogue_id:answerable`

### 拒接后果（reject_consequence）
对话级字段 `reject_consequence` 为触发器动作字符串（如 `"comm:d0_05_reject:silent"`）。
玩家拒接 ANSWERABLE 来电后，CommManager 执行该动作：
- 若以 `comm:` 开头 → 走 `handle_trigger_action` 路由
- 否则 → 走 `trigger_sys._execute` 通用触发器

### 错过来电回拨（补救措施）
玩家拒接或超时未接 ANSWERABLE 来电后：
1. CallHandler 在 `_missed_calls` 字典中记录该对话 ID
2. 玩家拨号时，`start_dialogue_from_dial` 检查该角色是否有错过的来电，有则允许回拨
3. 接听/回拨成功后自动清除记录
4. `comm` 命令状态显示"错过的来电"列表

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

## 玩家交互模式

对话系统支持两种玩家交互模式：

### 单选项模式（继续对话）

行结束后 `_click_to_continue = true` → UI 显示 `"> 继续对话"` 提示

- 玩家按空格/回车/点击继续 → `advance()` 推进下一行
- 无编号，仅 `>` 箭头提示

### 多分支选项模式（选择分支）

行包含 `wait_for: "choice:<base>_q<N>"` → UI 显示编号选项 `[1]` `[2]` `[3]`…

- 玩家按数字键 1-9 → `_handle_choice_selection()` → `_handle_generic_choice()`
- 分支查找顺序：`base_a1` → `base_1` → `choice_id_1` → `base_ready_1`
- 找到匹配的对话 ID → `trigger_dialogue(branch_id, true)` 开始分支对话

### 未使用代码路径

`choice: []` 数组字段和 `choice_presented` 信号已在 `CommDialoguePlayer` 中定义，
但未在 `CommManager.setup()` 中连接。当前所有选项均通过 `wait_for: "choice:xxx"` 实现。

## 电话号码来源（优先级顺序）

1. **故事盘**：`manifest.json` → `dial_directory` 节（DiscManager 加载时注入）
2. **系统注册**：通过 `register_system_voice()` / `register_system_modem()` 编程注册
3. **预设**：`res://data/dial_directory.json`（内置，启动时加载）
