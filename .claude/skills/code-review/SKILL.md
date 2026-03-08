# Skill: GDScript Code Review

You are reviewing GDScript code for the SCRT-Reader project.
Check the following project-specific conventions:

## Checklist

### Architecture
- [ ] No autoloads/singletons — uses constructor injection via `main.gd._ready()`
- [ ] RefCounted for non-process classes, Node only when `_process()` is needed
- [ ] Dependencies passed through constructor, not accessed globally

### Output & UI
- [ ] Theme colors via `T.c_primary()`, `T.c_error()` etc. — no hardcoded color values
- [ ] Output via `main.append_output(bbcode)` or `tw.append(text)` — not `print()`
- [ ] Viewer overlays follow Panel-on-OutputArea pattern (see ImageViewer/Oscilloscope)

### Effects & Safety
- [ ] CRT effects via `crt_shader.play_glitch()` etc. — not direct shader manipulation
- [ ] Effect safety checked via `effect_settings.is_effect_allowed()` before intense visuals
  <!-- 特别注意 jumpscare 类效果必须检查 -->
- [ ] Trigger actions always execute regardless of effect settings (only visuals are gated)

### Data & State
- [ ] Save data properly integrated with `save_manager.auto_save()` / `load_save()`
- [ ] Input handling respects mode priority chain in `main._input()`
- [ ] Dial system: `stop_dialogue(silent=true)` for transitions, `silent=false` for natural end
- [ ] New commands registered in `CommandHandler._register_commands()`

### Style
- [ ] Follows existing GDScript conventions in the codebase
- [ ] No unnecessary static typing annotations (match existing style)
- [ ] Signal connections use callable syntax (Godot 4.x)
