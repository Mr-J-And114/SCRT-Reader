# scripts/ — Core Scripts

This directory contains all core logic scripts. `main.gd` is the central
god object (~2211 lines) that owns all manager instances.

## Key Files by Size (largest = most complex)

| File | Lines | Role |
|---|---|---|
| main.gd | ~2211 | Init, input routing, mode management, UI, effects |
| typewriter.gd | ~1939 | Character-by-character output, queue, progress bar |
| command_handler.gd | ~1638 | CLI command registry, all `_cmd_*` handlers |
| crtml_parser.gd | ~1266 | Markdown-like markup → BBCode conversion |
| mail_system.gd | ~831 | Inbox, delayed delivery, global+per-story mail |
| package_manager.gd | ~818 | Mod install/uninstall/runtime |
| boot_sequence.gd | ~807 | JSON keyframe boot/shutdown animations |
| video_player.gd | ~737 | Video playback overlay |
| user_manager.gd | ~725 | Multi-user accounts, profiles, stats |
| disc_manager.gd | ~698 | Virtual disc: load/mount .scp, loading screen, desktop welcome |
| trigger_system.gd | ~600 | Event triggers: conditions → actions |
| loading_screen.gd | ~543 | Keyframe-driven disc loading animation (custom + default) |
| file_system.gd | ~400 | Virtual filesystem: paths, permissions, passwords |
| daily_dialogue_manager.gd | ~300 | Per-day dialogue/mail triggers |
| theme_manager.gd | ~250 | Color schemes, shader parameters |
| effect_system.gd | ~250 | Timeline-driven effect orchestration |
| story_loader.gd | ~200 | ZIP parser, UTF-8/GBK encoding detection |
| effect_settings.gd | ~176 | Effect intensity (FULL/MILD/OFF) + photosensitive |
| save_manager.gd | ~229 | Save/load paths, directory management |
| image_viewer.gd | ~200 | Full-screen CRT image viewer |
| oscilloscope.gd | ~200 | Audio visualizer (spectrum/Lissajous) |
| decode_viewer.gd | ~200 | Cipher decoder UI overlay |
| explore_viewer.gd | ~200 | Exploration progress tracker |
| document_viewer.gd | ~150 | Dispatches to templates/ viewers |
| header_parser.gd | ~150 | Parse file headers (template, title, password) |
| cipher_decoder.gd | ~150 | Caesar, Vigenere, Base64, Morse, ROT13, Atbash |
| morse_engine.gd | ~200 | Morse encode/decode, playback events |
| sstv_decoder.gd | ~200 | SSTV image receive simulation |
| ui_manager.gd | ~150 | UI init: background, fonts, cursor |
| ui_sound.gd | ~100 | Terminal SFX: keystroke, error, HDD read |
| profile_builder.gd | ~100 | User profile display |

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
