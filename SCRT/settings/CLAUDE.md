# settings/ — Settings System

> 上级文档：[/CLAUDE.md](/CLAUDE.md)
> 新增设置类别或修改 API 后请同步更新本文件。

Registry-based settings with automatic TUI rendering.

## Files

| File | Lines | Purpose |
|---|---|---|
| settings_manager.gd | 904 | Core: register, read, write, notify, TUI render |
| settings_registry.gd | ~200 | Built-in setting definitions (categories + defaults) |
| settings_storage.gd | ~200 | JSON persistence: global + per-user, version migration |

## Architecture

```
SettingsRegistry (static defaults) → SettingsManager (runtime) → SettingsStorage (disk)
```

1. `settings_registry.gd` defines categories and defaults via static methods
2. `settings_manager.gd` loads them at startup, provides runtime get/set + UI
3. `settings_storage.gd` handles JSON serialization to `user://` paths

## Built-in Categories

| ID | Display Name | Order |
|---|---|---|
| display | 显示 | 10 |
| audio | 音频 | 20 |
| effect | 效果 | 30 |
| terminal | 终端 | 40 |

## Key API

- `register_category(cat_def: Dictionary)` — `{id, display_name, icon, order}`
- `register_setting(def)` — setting definition dict
- Signal: `setting_changed(key: String, old_value: Variant, new_value: Variant)`
- Internal access: `_values["category.key"]`, `_apply_callbacks["category.key"]`

## Gotchas

- Setting keys are `"category.key"` format (dot-separated)
- `settings_registry` defines ALL built-in defaults; story packs cannot add settings
- Storage files: `_settings_global.json` (shared) + per-user `settings.json`
- Legacy migration: auto-converts old `theme.cfg`, `audio.cfg`, `effect_settings.cfg`
