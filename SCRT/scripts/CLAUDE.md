# scripts/ — Core Scripts

This directory contains all core logic scripts. `main.gd` is the central
god object (~1939 lines) that owns all manager instances.

## Key Files by Size (largest = most complex)

| File | Lines | Role |
|---|---|---|
| main.gd | 1939 | Init, input routing, mode management, UI, effects |
| command_handler.gd | 1638 | CLI command registry, all `_cmd_*` handlers |
| crtml_parser.gd | 1266 | Markdown-like markup → BBCode conversion |
| settings_manager.gd | 904 | Registry-based settings with TUI |
| mail_system.gd | 831 | Inbox, delayed delivery, global+per-story mail |
| boot_sequence.gd | 807 | JSON keyframe boot/shutdown animations |
| package_manager.gd | 818 | Mod install/uninstall/runtime |
| video_player.gd | 737 | Video playback overlay |
| user_manager.gd | 725 | Multi-user accounts, profiles, stats |

## Patterns

- **Managers** extend RefCounted unless they need `_process` (then extend Node)
- **Viewers** use overlay pattern: Panel on OutputArea, hide input/prompt, restore on close
  - See `image_viewer.gd`, `oscilloscope.gd` as canonical examples
  - Custom rendering via `_draw()` in inner `_*Canvas` class
- **Commands** defined as `_cmd_<name>` methods in `command_handler.gd`
- **Inline effects** in CRTML text: `{fx:glitch}`, `{fx:shake}`, `{fx:sound=path}`
- **No autoloads** — all managers created in `main.gd._ready()` with constructor injection

## Adding a New Script

1. Create class extending RefCounted in this directory
2. Instantiate in `main.gd._ready()`, pass dependencies via constructor
3. If it needs per-frame updates, call its `process()` from `main._process()`
4. If it needs input, add handler in `main._input()` respecting mode priority chain
5. Register commands in `CommandHandler._register_commands()` if needed
