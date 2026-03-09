# Skill: Bug Fix (Godot 4.6 / SCRT-Reader)

You are diagnosing and fixing a bug in the SCRT-Reader terminal.
Follow this systematic workflow.

## Step 1: Reproduce

- Understand the symptom: what's wrong, when it happens, which system is affected
- Identify the relevant subsystem (check `CLAUDE.md` in that directory first)
- Note the input mode when the bug occurs (see mode flags below)

## Step 2: Locate

Search strategy by symptom type:

| Symptom | Search In |
|---|---|
| Command not working | `command_handler.gd` → `_cmd_<name>` method |
| UI not responding | `main.gd._input()` → mode priority chain |
| Overlay stuck/broken | Viewer's `handle_input()` + `is_active` flag |
| Dial/comm issue | `dial_manager.gd` state machine + `comm_manager.gd` |
| Save data lost | `save_manager.gd` + `auto_save()` call site |
| Effect not playing | `effect_settings.gd` safety check + `crt_shader.gd` |
| Trigger not firing | `trigger_system.gd` condition matching + `disc_manager.gd` load |
| File not loading | `story_loader.gd` ZIP extraction + encoding detection |
| Signal chain broken | Check `setup()` method → `.connect()` calls |

## Step 3: Diagnose

Trace the execution path:
- For state machines: verify all transitions have matching exit conditions
- For signals: verify `.connect()` in `setup()`, `.emit()` at call site
- For mode flags: verify both set AND clear paths exist in `main.gd`
- For overlays: verify `is_active` toggled correctly on open/close

## Step 4: Fix

- Minimal change — preserve existing patterns
- Match surrounding code style (fully typed, `class_name`, etc.)
- Don't refactor adjacent code or add unrelated improvements

## Step 5: Verify

- Check that the fix doesn't break the mode priority chain
- Check that save/load round-trips correctly if save data was changed
- Check signal connection count (no duplicate `.connect()` calls)

## Common Bug Patterns

| Pattern | Root Cause | Fix Location |
|---|---|---|
| Signal not firing | Missing `.connect()` in `setup()` | The manager's `setup()` method |
| Mode flag stuck | Missing clear on exit path | `main.gd._input()` or viewer's `hide()`/`close()` |
| Dial state stuck | Missing state transition | `dial_manager.gd` — check IDLE→DTMF→RINGING→VOICE/MODEM→ENDED→IDLE |
| Overlay not closing | `handle_input()` not returning `true` | Viewer's `handle_input()` for ESC/Q |
| Save data lost | Field not in `extra` dict | `auto_save()` call — add field to extra |
| Encoding garbled | Non-UTF-8 content | `story_loader.gd` — check GBK fallback path |
| Effect blocked | Safety check | `effect_settings.is_effect_allowed()` — verify level |
| Typewriter stuck | Queue not advancing | `typewriter.gd` — check `_on_typing_completed` |

## Mode Flags in main.gd (input priority order)

```
_booting > _shutting_down > _comm_active > _viewer_active > _camera_mode >
_radio_mode > _env_mode > _explore_mode > _decode_mode > _password_mode >
_login_mode > [normal terminal input]
```

Each flag gates a section in `main._input()`. If a flag is stuck `true`, all lower-priority input is blocked.

## Debug Logging Convention

```gdscript
print("[ClassName] 描述: %s" % value)
push_warning("[ClassName] 警告描述")
```
