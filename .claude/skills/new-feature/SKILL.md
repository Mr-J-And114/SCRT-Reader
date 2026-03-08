# Skill: Add New Feature

You are extending the SCRT-Reader terminal with a new feature/system.
Follow the 7-step process below.
<!-- 详细步骤参考 docs/extension-guide.md -->

## Steps

1. **Create class** in `SCRT/scripts/` extending `RefCounted`
   - Use `Node` only if you need `_process()` per-frame updates
   - Accept dependencies via constructor (no autoloads/singletons)

2. **Instantiate in `main.gd._ready()`**
   - Pass required manager references via constructor injection
   - Follow the ordering in the existing dependency graph (see `docs/architecture.md`)

3. **Register commands** (if needed)
   - Add `_cmd_<name>(args)` method in `CommandHandler`
   - Register in `CommandHandler._register_commands()` with help text

4. **Create overlay** (if needed)
   - Follow the overlay pattern from `image_viewer.gd` or `oscilloscope.gd`
   - Panel on OutputArea, hide input/prompt, restore on close
   - Custom rendering via inner `_*Canvas` class with `_draw()`

5. **Parse manifest data** (if needed)
   - Add parsing in `disc_manager.load_story()` or `trigger_system.load_from_manifest()`

6. **Add save data** (if needed)
   - Integrate with `save_manager.auto_save()` / `load_save()`
   - Use `extra` dict in save file for custom data

7. **Register settings** (if needed)
   - Use `settings_manager.register_category()` / `register_setting()`

## Key Conventions
- Theme colors: `T.c_primary()`, `T.c_error()` etc. (return hex strings)
- Output: `main.append_output(bbcode)` or `tw.append(text)`
- CRT effects: `crt_shader.play_glitch()`, `crt_shader.play_shake()`
- Input priority: boot_sequence > comm > viewers > password > login > normal
- Effect safety: check `effect_settings.is_effect_allowed()` before intense visuals
