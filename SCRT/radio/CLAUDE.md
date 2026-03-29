# radio/ — 无线电系统 (Radio Receiver System)

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 数据格式：[/docs/data-formats.md](/docs/data-formats.md)
> 修改无线电系统后请同步更新本文件。

完整的无线电调谐界面，支持摩斯码解码、SSTV 图像接收和音频广播电台。
玩家通过 `radio` 命令进入无线电界面（仅桌面模式可用）。

## 重要提示

`radio_receiver.gd` 有 1804 行——是最大的查看器脚本。内含 `_RadioCanvas` 内部类用于所有自定义绘制。

## 文件列表

| 文件 | 行数 | 用途 |
|---|---|---|
| radio_receiver.gd | 1804 | 完整无线电 UI + _RadioCanvas（调谐/频段/瀑布图/解码/SSTV） |
| radio_data_manager.gd | 302 | 本地 data/radio/ 文件夹管理，信号导入/读写 JSON |
| radio_config_parser.gd | 319 | 解析信号定义（从配置文件/manifest），RadioSignal 数据类 |
| radio_signal_manager.gd | 344 | 信号数据库，质量计算（渐进接近），发现跟踪，书签，扫描 |
| radio_audio_generator.gd | 311 | 程序化噪声/音调/SSTV 音频生成 |
| morse_engine.gd* | 347 | 摩斯码编解码，播放事件，数字站模式（位于 scripts/） |
| sstv_decoder.gd* | 310 | SSTV 图像接收模拟，带扫描线噪声（位于 scripts/） |

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
