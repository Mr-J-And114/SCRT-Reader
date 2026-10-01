# radio/ — 无线电系统 (Radio Receiver System)

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 数据格式：[/docs/data-formats.md](/docs/data-formats.md)
> 修改无线电系统后请同步更新本文件。

完整的无线电调谐界面，支持摩斯码解码、SSTV 图像接收和音频广播电台。
玩家通过 `radio` 命令进入无线电界面（仅桌面模式可用）。

## 重要提示

`radio_receiver.gd` 有 1735 行——是最大的查看器脚本。内含 `_RadioCanvas` 内部类用于所有自定义绘制。

## 调试入口（无线电演示模式）

游戏内输入 `debug 114514 radio test` 可一键进入无线电全功能测试（需桌面模式）：

```
debug 114514 radio test     # 注入 9 个测试信号 + 打开界面（幂等，可反复执行）
debug 114514 radio clean    # 移除测试信号（内存级，不写盘）
debug 114514 radio list     # 列出当前所有信号（类型/频段/标签/特殊标记）
```

实现位置：`scripts/command_handler.gd` 的 `_debug_radio_test()` / `_debug_radio_clean()` / `_debug_radio_list()`；
`_test_radio_ids` 成员变量记录注入的 ID 供清理。

**测试信号清单**（id 前缀 `_test_`，覆盖 3 类型 / 4 频段）：

| ID | 类型 | 频段/频率 | 测试点 | 素材 |
|---|---|---|---|---|
| `_test_morse_std` | morse | HF 7.100 | 标准摩斯解码、锁定 | 内嵌文本 |
| `_test_morse_num` | morse | HF 5.200 | 数字电台模式 | 内嵌数字 |
| `_test_beacon` | morse | HF 14.100 | 信标日志（L 键） | beacon_id |
| `_test_hidden` | morse | HF 9.800 | 隐藏信号发现 | hidden=true |
| `_test_cipher` | morse | HF 10.500 | 加密标记显示 | cipher_type=caesar |
| `_test_lf` | morse | LF 0.300 | 低频段覆盖 | 内嵌文本 |
| `_test_uhf` | morse | UHF 450.000 | 超高频段覆盖 | 内嵌文本 |
| `_test_sstv` | sstv | VHF 145.800 | SSTV 接收/存图 | `res://data/main/cameras/camera_test_main.jpg` |
| `_test_audio` | audio | VHF 162.550 | 音频电台自动播放 | `res://audio/startup.mp3` |

**关键行为**：
- 信号为**内存注入**（`signal_mgr.add_signal()`），不写入 `data/radio/`
- 注入前先 `load_local_signals()` 保留真实信号（S-00 等）
- 退出后用普通 `radio` 命令进入会**重置为真实信号**（`_cmd_radio` 会调用 `load_local_signals()`）
- 注入时用 `RadioConfigParser.RadioSignal.new()` 构造，audio 类型的 `content_file` 需设文件名（如 `"startup.mp3"`）用于扩展名检测

## 文件列表

| 文件 | 行数 | 用途 |
|---|---|---|
| radio_receiver.gd | 1735 | 完整无线电 UI + _RadioCanvas（调谐/频段/瀑布图/解码/SSTV） |
| radio_data_manager.gd | 289 | 本地 data/radio/ 文件夹管理，信号导入/读写 JSON |
| radio_config_parser.gd | 301 | 解析信号定义（从配置文件/manifest），RadioSignal 数据类 |
| radio_signal_manager.gd | 324 | 信号数据库，质量计算（渐进接近），发现跟踪，书签，扫描 |
| radio_audio_generator.gd | 304 | 程序化噪声/音调/SSTV 音频生成 |
| morse_engine.gd* | 327 | 摩斯码编解码，播放事件，数字站模式（位于 scripts/） |
| sstv_decoder.gd* | 294 | SSTV 图像接收模拟，带扫描线噪声（位于 scripts/） |

*标注 `*` 的文件物理位置在 `scripts/` 目录，但逻辑上属于无线电子系统。

## 信号类型

| 类型 | 说明 | 需要锁定 | 渐进音频 |
|---|---|---|---|
| morse | 摩斯码文本（标准/数字站） | 是（用于解码） | 锁定前可听到音调，音量 ∝ 信号质量 |
| sstv | 慢扫描电视图像 | 是（空格键接收） | 锁定前可听到 SSTV 音调 |
| audio | 音频广播（MP3/OGG/WAV） | 否 | 自动播放，音量 ∝ 信号质量 |

## 渐进感知机制（核心设计）

这是无线电系统最独特的特性——信号并非"锁定/未锁定"二元状态，而是渐进式体验：

- 所有信号：进入 `proximity_range` 范围后开始音频反馈
- 信号质量 = f(频率差, 方位角差, 仰角差) → 0.0~1.0
- 噪声音量与最大信号质量成反比
- 摩斯码音调音量随质量缩放（质量 > 0.02 时可听）
- 音频电台：音量 = 质量 × 主音量 × 0.8
- 完全锁定（质量 ≥ 阈值且持续 ≥ 3 秒）才能解码摩斯/接收 SSTV

## 隐藏信号

- 配置中 `hidden: true` → 不显示在雷达点、频率标尺标记、瀑布图标记中
- 仍可通过手动调谐发现，通过渐进感知听到
- 当质量达到锁定阈值时被标记为"已发现"

### ⚠️ `visible` vs `hidden`（重要陷阱）

- `visible: false` → `scan_signals()` **完全跳过该文件**，信号不存在于系统中，永远无法发现（radio_data_manager.gd `_load_signal_from_file`）
- `hidden: true` → 信号正常加载，仅不在界面标注（雷达/标尺/瀑布图），可手动调谐发现
- **彩蛋/隐藏信号必须用 `visible: true` + `hidden: true`**，`visible: false` 只用于"暂不启用"的开关
- 当前内置信号：`data/radio/s00_unknown_whisper.json`（Day0 彩蛋，morse 数字电台 5.473MHz）

## 本地信号管理 (data/radio/)

无线电信号现在独立于 vdisc 管理，存放在 `data/radio/` 文件夹：

- 每个信号定义在独立 JSON 文件中（如 `data/radio/weather.json`）
- `visible` 字段（默认 `true`）：设为 `false` 可隐藏信号而不删除
- 资源文件（音频/图像/文本）与 JSON 文件存放在同一目录
- `RadioDataManager` 负责扫描、读取、写入和导入
- radio 命令**仅桌面模式可用**——加载故事盘期间不可用

## 触发器动作

| 触发器 | 格式 | 说明 |
|---|---|---|
| `radio_import` | `radio_import:signal_id` 或 `radio_import:*` | 从当前 vdisc 导入信号到 data/radio/ |
| `radio_visible` | `radio_visible:signal_id:true/false` | 切换信号可见性 |
| `radio_update` | `radio_update:signal_id:field=value` | 修改信号字段（如 content_file） |
| `radio_reload` | `radio_reload` | 热重载 data/radio/ 中的信号列表 |

## JSON 信号定义示例

```json
{
  "id": "weather_broadcast",
  "type": "audio",
  "frequency": 162.55,
  "band": "VHF",
  "azimuth": 180,
  "elevation": 10,
  "tolerance_freq": 0.1,
  "tolerance_dir": 30,
  "content_file": "weather_day1.ogg",
  "label": "Weather Broadcast",
  "visible": true,
  "loop": true
}
```

## 音频加载

`AudioManager.load_audio_from_bytes(file_path, data)` 从原始字节加载音频：
- 第一个参数为路径（用于检测扩展名），第二个为字节数据
- MP3: `AudioStreamMP3.new()` + `.data = bytes`
- OGG: `AudioStreamOggVorbis.load_from_buffer(bytes)`
- WAV: 手动 PCM 解析（RIFF chunk 遍历）

## 关键实现数值（避免重复查代码）

| 项 | 值 | 位置 |
|---|---|---|
| 锁定阈值 | 质量 ≥ **0.5** | radio_receiver.gd `SIGNAL_LOCK_THRESHOLD` |
| 锁定持续 | **3.0 秒** | radio_receiver.gd `SIGNAL_LOCK_TIME` |
| 频段范围 | LF 0.1-0.5 / HF 1.8-30 / VHF 30-300 / UHF 300-3000（MHz） | radio_config_parser.gd `BAND_RANGES` |
| 频段步进 | LF 0.001 / HF 0.005 / VHF 0.025 / UHF 0.1 | 同上 `step` |
| 质量公式 | `pow(freq_factor × azim_factor × elev_factor, 1.2)` | radio_signal_manager.gd `calculate_signal_quality()` |
| 基础方位容差 | `tolerance_dir`；SSTV/audio ×2；仰角容差 = `tolerance_dir × 0.8` | 同上 |
| 渐进范围 | `proximity_range`（>0 时生效，否则用 `tolerance_freq`） | 同上 |
| SSTV 图像格式 | PNG / JPG / BMP / WebP（`sstv_decoder.start_receive()` 按序尝试解析） | sstv_decoder.gd:90-95 |
| 音频电台音量 | 质量 × 主音量 × 0.8，质量 ≥ 0.5 才播放 | radio_receiver.gd `_update_audio_station()` |
| 默认调谐状态 | azimuth=0，elevation=15，volume=0.4，mode=MORSE，band=HF | radio_receiver.gd:31-38 |

**操作按键**（radio_receiver.gd `handle_input()`）：
`←→` 调频（Shift×10）| `↑↓` 方位（Shift×10）| `< >` 仰角 | `+ -` 音量 | `1-4` 频段（LF/HF/VHF/UHF）
`Tab` 模式切换（MORSE→SSTV→WATERFALL）| `S` 自动扫描 | `B` 书签 | `L` 信标日志
`空格` SSTV 接收 | `P` 保存 SSTV 图 | `R` 重置 | `Q/Esc` 退出 | 鼠标拖动频率刻度条可调频

## RadioSignal 字段速查（radio_config_parser.gd 内部类）

| 字段 | 类型 | 说明 |
|---|---|---|
| id / type / band / frequency | String/String/String/float | 基础标识；type: morse/sstv/audio |
| azimuth / elevation | float | 目标方向（0-359° / 0-90°） |
| tolerance_freq / tolerance_dir | float/int | 容差（MHz / 度） |
| proximity_range | float | 渐进感知范围（MHz），0=用 tolerance_freq |
| content_text / content_file / content_image / content_audio | String/String/PackedByteArray/PackedByteArray | 各类内容（file 为相对 `data/radio/` 的路径） |
| label / hint | String | 显示名 / 调谐提示 |
| loop / speed_wpm / character_set | bool/int/String | 循环 / 摩斯速度 / "numbers"=数字台 |
| group_size / group_pause_ms / repeat_count | int/float/int | 数字台分组控制 |
| beacon_id | String | 信标呼号（非空视为信标） |
| cipher_type / cipher_key_file | String | 加密类型（""/caesar/vigenere/otp）/ 密钥文件 |
| hidden | bool | 隐藏（不在雷达/标尺/瀑布图标注） |
| ephemeral / reappear_interval | bool/float | 短暂信号 / 重现间隔 |
| discovered_flag | String | 发现后设置的剧情标记（**注意：当前无消费代码**） |
| sstv_mode / transmit_duration | String/float | SSTV 模式（Martin M1 等）/ 传输时长（秒） |
| visible（JSON 字段，非类字段） | bool | false = `scan_signals()` 完全跳过（不可发现） |
