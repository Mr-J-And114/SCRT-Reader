# scripts/ — Core Scripts

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 详细索引：[/docs/architecture.md](/docs/architecture.md)
> 修改脚本后请同步更新本文件中的行数和文件列表。

This directory contains all core logic scripts. `main.gd` is the central
god object (~2209 lines) that owns all manager instances.

## Key Files by Size (largest = most complex)

| File | Lines | Role |
|---|---|---|
| command_handler.gd | 2346 | CLI command registry, all `_cmd_*` handlers |
| main.gd | 2209 | Init, input routing, mode management, UI, effects |
| decode_viewer.gd | 1456 | Cipher decoder UI overlay, _DecodeCanvas inner class |
| crtml_parser.gd | 1263 | Markdown-like markup → BBCode conversion |
| env_monitor.gd* | 919 | Environmental simulation (in env_system/) |
| mail_system.gd | 891 | Inbox, delayed delivery, global+per-story mail |
| user_manager.gd | 856 | Multi-user accounts, profiles, stats |
| oscilloscope.gd | 820 | Audio visualizer (spectrum/Lissajous), _ScopeCanvas |
| package_manager.gd | 817 | Mod install/uninstall/runtime |
| boot_sequence.gd | 813 | JSON keyframe boot/shutdown animations |
| video_player.gd | 748 | Video playback overlay with ffmpeg fallback |
| trigger_system.gd | 726 | Event triggers: conditions → actions |
| story_loader.gd | 708 | ZIP parser, UTF-8/GBK encoding detection |
| disc_manager.gd | 698 | Virtual disc: load/mount .scp, loading screen, desktop welcome |
| document_viewer.gd | 668 | 2-page overlay, pagination, typing animation |
| image_viewer.gd | 634 | Full-screen CRT image viewer, _ImageCanvas |
| audio_manager.gd | 586 | Ambient/SFX/Media players, ducking, spectrum |
| cipher_decoder.gd | 584 | Caesar, Vigenere, Base64, Morse, ROT13, Atbash |
| loading_screen.gd | 543 | Keyframe-driven disc loading animation (custom + default) |
| typewriter.gd | 520 | Character-by-character output, queue, progress bar |
| theme_manager.gd | 518 | Color schemes, shader parameters |
| explore_viewer.gd | 477 | File tree panel, story progress display |
| file_system.gd | 472 | Virtual filesystem: paths, permissions, passwords |
| ui_manager.gd | 466 | UI init: background, fonts, cursor |
| effect_system.gd | 451 | Timeline-driven effect orchestration |
| crt_shader.gd | 416 | CRT post-process effects controller |
| daily_dialogue_manager.gd | 414 | Per-day dialogue/mail triggers |
| morse_engine.gd | 347 | Morse encode/decode, playback events |
| sstv_decoder.gd | 310 | SSTV image receive simulation |
| header_parser.gd | 247 | Parse file headers (template, title, password) |
| profile_builder.gd | 242 | User profile display (3 pages) |
| save_manager.gd | 228 | Save/load paths, directory management |
| ui_sound.gd | 200 | Terminal SFX: keystroke, error, HDD read |
| effect_settings.gd | 175 | Effect intensity (FULL/MILD/OFF) + photosensitive |

## Mode Flags (main.gd input priority order)

```
_booting > _shutting_down > _comm_active > _viewer_active > _camera_mode >
_radio_mode > _env_mode > _explore_mode > _decode_mode > _password_mode >
_login_mode > [normal terminal input]
```

Each flag gates a section in `main._input()`. If stuck `true`, lower-priority input blocked.

## Patterns

- **Managers** extend RefCounted unless they need `_process` (then extend Node)
- **Viewers** use overlay pattern: Panel on OutputArea, hide input/prompt, restore on close
  - See `image_viewer.gd`, `oscilloscope.gd` as canonical examples
  - Custom rendering via `_draw()` in inner `_*Canvas` class
- **Commands** defined as `_cmd_<name>` methods in `command_handler.gd`
  - Three dicts: `global_commands`, `desktop_commands`, `disc_commands`
- **Inline effects** in CRTML text: `{fx:glitch}`, `{fx:shake}`, `{fx:sound=path}`
- **No autoloads** — all managers created in `main.gd._ready()` with constructor injection
- **Loading screen** uses BBCode buffer (`_bbcode_buffer`) for reliable in-place rendering.
  All output goes through the buffer, rendered via `output_text.text = _bbcode_buffer`.
  Progress bar saves a snapshot of the buffer, then overwrites the last line each frame.
  During playback, `main._process()` enters exclusive mode (early return) to prevent
  typewriter/trigger/mail/effect systems from writing to `output_text`.

## Adding a New Script

1. Create class extending RefCounted in this directory
2. Instantiate in `main.gd._ready()`, pass dependencies via constructor
3. If it needs per-frame updates, call its `process()` from `main._process()`
4. If it needs input, add handler in `main._input()` respecting mode priority chain
5. Register commands in `CommandHandler._register_commands()` if needed
