# radio/ — Radio Receiver System

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

## Supporting Scripts

| File | Purpose |
|---|---|
| radio_receiver.gd | Full radio UI + _RadioCanvas (tuning, bands, waterfall, decode) |
| radio_config_parser.gd | Parse signal definitions from config/manifest |
| radio_signal_manager.gd | Signal database, quality calculation, discovery, bookmarks |
| radio_audio_generator.gd | Procedural noise/tone/SSTV audio generation |
| morse_engine.gd | Morse encode/decode, playback events, numbers station mode |
| sstv_decoder.gd | SSTV image receive simulation with scanline noise |
