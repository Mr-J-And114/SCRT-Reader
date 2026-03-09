# SCRT-Reader

## WHY
SCP-themed retro CRT terminal simulator / interactive fiction reader.
Built with Godot 4.6 (GL Compatibility renderer). Pure 2D UI, single scene.
Players operate a terminal to read story packs (.scp files), interact with
characters via dial/comm, monitor environmental sensors, view CCTV feeds,
tune radio signals, and decode ciphers.

## WHAT (Repo Map)
- `SCRT/` — Godot project root
  - `scripts/` — Core scripts (main.gd is the god object, ~1939 lines)
  - `comm_system/` — Dialogue/character/dial system (8 scripts)
  - `camera_system/` — CCTV surveillance (4 files incl. shader)
  - `env_system/` — Environmental monitoring (env_monitor, env_task_manager, env_viewer)
  - `radio/` — Radio receiver/signals (radio_receiver ~1700 lines + 5 support scripts)
  - `settings/` — Settings manager/registry/storage
  - `modder/` — Mod API (mod_api.gd ~997 lines) + ModBase
  - `templates/` — Document viewer templates (article/chat/email/two-page)
  - `shaders/` — CRT effect, background vignette, background logo
  - `scenes/main.tscn` — Single scene (all UI nodes)
  - `data/` — Config files (dial directory, env config, tutorial, dialogues)
  - `addons/agent/` — Godot in-editor AI agent plugin (NOT Claude Code — do not modify)
- `docs/` — Architecture, data formats, guides (Chinese design docs + English technical refs)
  - `design-doc.txt` — 软件规划设计文档
  - `story-authoring-guide.txt` — 故事包制作指南
  - `camera-asset-guide.txt` — 摄像头资源制作指南

## HOW (Key Conventions)
- **Architecture**: No autoloads/singletons. main.gd instantiates all managers
  in `_ready()` with constructor injection via `setup()` methods. Managers extend
  RefCounted (or Node if they need `_process`).
- **GDScript style (Godot 4.6)**: Fully typed (all vars/params/returns), `class_name`
  at top, `@onready` + `$`, typed signals, `.connect(callable)`, `JSON.new().parse()`,
  `FileAccess`/`DirAccess`, `%` formatting, `as` casting, `await create_timer()`.
  See code-review skill for full checklist.
- **Output**: Use `main.append_output(bbcode)` or `tw.append(text)` for typed output.
- **Theme colors**: `T.c_primary()`, `T.c_error()` etc. (return hex strings).
- **CRT effects**: `crt_shader.play_glitch()`, `crt_shader.play_shake()`, etc.
- **Viewers/Overlays**: Follow overlay pattern — Panel on OutputArea, hide
  input/prompt, restore on close. See ImageViewer/Oscilloscope as reference.
- **Adding commands**: Register in `CommandHandler._register_commands()`.
- **Adding manifest data**: Parse in `disc_manager.load_story()` or
  `trigger_system.load_from_manifest()`.
- **Save data**: Add to `save_manager.auto_save()`/`load_save()`.
- **Settings**: Register via `settings_manager.register_category()`/`register_setting()`.
- **Input priority**: boot_sequence > comm > viewers > password > login > normal.
- **CommDialoguePlayer**: `stop_dialogue(silent=true)` for transitions;
  `silent=false` for natural completion. Voice calls delay 1.0s before
  `dial_mgr` callback.
- **Inline effects**: `{fx:glitch}`, `{fx:shake}`, `{fx:sound=path}` in CRTML text.

## IMPORTANT GOTCHAS
- main.gd is a ~1939-line god object. All `_process` and `_input` routing lives there.
- `dial_mgr` runs in background (non-blocking). State machine:
  IDLE → DTMF → RINGING → VOICE/MODEM → ENDED → IDLE.
- Story content loaded from .scp ZIP files. Encoding detection: UTF-8 with GBK fallback.
- `res://vdisc/` in editor, `./vdisc/` in exported build for disc storage.
- Effect safety: check `effect_settings.is_effect_allowed("jumpscare")` before visual scares.

## MODE FLAGS (main.gd input priority)

```
_booting > _shutting_down > _comm_active > _viewer_active > _camera_mode >
_radio_mode > _env_mode > _explore_mode > _decode_mode > _password_mode >
_login_mode > [normal terminal input]
```

Each flag gates a section in `main._input()`. If stuck `true`, lower-priority input blocked.

## SEE ALSO
- `docs/architecture.md` — Full dependency graph, scene tree, script reference
- `docs/data-formats.md` — .scp format, CRTML markup, boot config, save system
- `docs/extension-guide.md` — Step-by-step for adding new features
- `SCRT/scripts/CLAUDE.md` — Core scripts patterns + file index
- `SCRT/comm_system/CLAUDE.md` — Comm/dial system details
- `SCRT/camera_system/CLAUDE.md` — Camera shader pipeline
- `SCRT/radio/CLAUDE.md` — Radio system details
- `SCRT/env_system/CLAUDE.md` — Environmental monitoring sensors/tasks
- `SCRT/settings/CLAUDE.md` — Settings registry/storage
- `SCRT/modder/CLAUDE.md` — Mod API/lifecycle
- `SCRT/templates/CLAUDE.md` — Document viewer templates
