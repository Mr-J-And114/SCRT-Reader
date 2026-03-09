# modder/ — Mod System

Sandboxed mod API with lifecycle hooks and cross-mod messaging.

## Files

| File | Lines | Purpose |
|---|---|---|
| mod_api.gd | 997 | Sandboxed API: 16 functional categories for mod access |
| mod_base.gd | ~100 | Base class: lifecycle hooks + event hooks for mods to override |

## ModBase Lifecycle (mods override these)

```
_on_install() → _on_enable() → _register_commands() → [runtime] → _on_disable() → _on_uninstall()
```

## ModBase Event Hooks

| Hook | Return | Purpose |
|---|---|---|
| `_on_before_command(cmd, args)` | `bool` | Intercept command (return true to block) |
| `_on_after_command(cmd, args)` | void | React after command |
| `_on_directory_changed(old, new)` | void | Directory navigation |
| `_on_before_file_open(path)` | `bool` | Intercept file open |
| `_on_after_file_open(path)` | void | React after file open |
| `_on_disc_loaded(story_id, manifest)` | void | Story loaded |
| `_on_disc_ejected()` | void | Story ejected |
| `_on_mode_changed(is_desktop)` | void | Desktop ↔ disc mode |
| `_on_mod_message(from_id, data)` | void | Cross-mod messaging |
| `_on_user_login/logout(username)` | void | User session events |

## ModAPI Categories (16)

output, commands, fs, ui, effects, comm, env, camera, radio, mail, triggers, settings, audio, save, theme, utils

## Gotchas

- ModAPI restricts file access to mod's own directory + vdisc/
- Package format: `.zip` with `mod_manifest.json` at root
- mod_api.gd is 997 lines — changes affect ALL installed mods
- Managed by `package_manager.gd` (818L) in scripts/ — install/uninstall/lifecycle
- See `docs/README.md` mod development section for full ModAPI function list
