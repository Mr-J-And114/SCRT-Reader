# radio/ — Radio Receiver System

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 数据格式：[/docs/data-formats.md](/docs/data-formats.md)
> 修改无线电系统后请同步更新本文件。

Full radio tuning interface with morse code, SSTV image reception, and audio broadcast stations.

## Key Warning

`radio_receiver.gd` is ~1700 lines — the largest viewer script. Contains `_RadioCanvas` inner class for all custom rendering.

## Signal Types

| Type | Description | Lock Required | Progressive Audio |
|---|---|---|---|
| morse | Morse code text (standard/numbers station) | Yes (for decode) | Tone audible before lock, volume ∝ quality |
| sstv | Slow-scan TV image | Yes (Space to receive) | SSTV tone audible before lock |
| audio | Audio broadcast (MP3/OGG/WAV) | No | Auto-play, volume ∝ quality |

## Progressive Perception (核心机制)

- All signals: entering `proximity_range` begins audio feedback
- Signal quality = f(freq_diff, azimuth_diff, elevation_diff) → 0.0~1.0
- Noise volume inversely proportional to max signal quality
- Morse tone volume scales with quality (audible at quality > 0.02)
- Audio stations: volume = quality × master_volume × 0.8
- Full lock (quality ≥ threshold for ≥ 3s) required for morse decode / SSTV receive

## Hidden Signals

- `hidden: true` in config → omitted from radar dots, frequency ruler markers, waterfall markers
- Still discoverable via manual tuning, audible via progressive perception
- Discovered when quality reaches lock threshold

## Audio Loading

`AudioManager.load_audio_from_bytes(file_path, data)` — loads MP3/OGG/WAV from raw bytes.
- First arg is path (for extension detection), second is byte data
- MP3: `AudioStreamMP3.new()` with `.data = bytes`
- OGG: `AudioStreamOggVorbis.load_from_buffer(bytes)`
- WAV: manual PCM parsing (RIFF chunk traversal)

## Local Signal Management (data/radio/)

Radio signals are now managed independently from vdisc via `data/radio/` folder.

- Each signal defined in its own JSON file (e.g. `data/radio/weather.json`)
- `visible` field (default `true`): set to `false` to hide a signal without deleting
- Resources (audio/images/text) stored alongside JSON files in `data/radio/`
- `RadioDataManager` handles scanning, reading, writing, and importing
- Radio command is **desktop-mode only** — unavailable during vdisc sessions

### Trigger Actions

| Trigger | Format | Description |
|---|---|---|
| `radio_import` | `radio_import:signal_id` or `radio_import:*` | Import signal from current vdisc to data/radio/ |
| `radio_visible` | `radio_visible:signal_id:true/false` | Toggle signal visibility |
| `radio_update` | `radio_update:signal_id:field=value` | Modify signal field (e.g. content_file) |
| `radio_reload` | `radio_reload` | Hot-reload signal list from data/radio/ |

### JSON Signal Definition Example

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

## Supporting Scripts

| File | Purpose |
|---|---|
| radio_receiver.gd | Full radio UI + _RadioCanvas (tuning, bands, waterfall, decode) |
| radio_data_manager.gd | Local data/radio/ folder management, import, read/write JSON |
| radio_config_parser.gd | Parse signal definitions from config/manifest |
| radio_signal_manager.gd | Signal database, quality calculation, discovery, bookmarks |
| radio_audio_generator.gd | Procedural noise/tone/SSTV audio generation |
| morse_engine.gd | Morse encode/decode, playback events, numbers station mode |
| sstv_decoder.gd | SSTV image receive simulation with scanline noise |
