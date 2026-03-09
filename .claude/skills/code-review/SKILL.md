# Skill: GDScript Code Review (Godot 4.6)

You are reviewing GDScript code for the SCRT-Reader project (Godot 4.6, GL Compatibility renderer).
Check the following project-specific conventions:

## Checklist

### GDScript Style (Godot 4.6)
- [ ] **Fully typed** — all variables, parameters, and return types have annotations
  ```gdscript
  var count: int = 0
  var items: Array[String] = []
  var data: Dictionary = {}
  func do_thing(name: String, value: float) -> bool:
  ```
- [ ] `class_name` declared at top of every non-main script
- [ ] `@onready` with `$` notation for node references:
  ```gdscript
  @onready var output_text: RichTextLabel = $MainContent/OutputArea/OutputText
  ```
- [ ] No `@export` — config injected via `setup()` or loaded from JSON manifests
- [ ] Typed signals with parameter names:
  ```gdscript
  signal status_changed(id: String, online: bool)
  ```
- [ ] Signal connection via callable syntax (never old string syntax):
  ```gdscript
  player.finished.connect(_on_finished)
  player.finished.connect(_on_finished, CONNECT_ONE_SHOT)  # 一次性连接
  ```
- [ ] Signal emission via `.emit()`:
  ```gdscript
  status_changed.emit(camera_id, true)
  ```

### Type Safety
- [ ] Type casting with `as` operator: `var m: Dictionary = json.data as Dictionary`
- [ ] Type checks with `is` operator: `if json.data is Dictionary:`
- [ ] Typed arrays where possible: `Array[String]`, `Array[Dictionary]`
- [ ] Null checks before member access: `if f != null:`, `if obj and obj.is_active:`

### Godot 4.6 API (one-line checks)
- [ ] JSON: `JSON.new()` + `.parse()` (NOT static `JSON.parse_string()`)
- [ ] File I/O: `FileAccess` / `DirAccess` (NOT old `File` / `Directory`)
- [ ] Tweens: `create_tween()` (NOT `Tween.new()`)
- [ ] Delays: `await get_tree().create_timer(sec).timeout`
- [ ] Settings persistence: `ConfigFile` (NOT custom JSON)

### Architecture
- [ ] No autoloads/singletons — uses constructor injection via `setup()` in `main.gd._ready()`
- [ ] RefCounted for non-process classes, Node only when `_process()` is needed
- [ ] Dependencies passed through `setup()` method, not accessed globally
- [ ] `match` statements for enum branching (NOT if-elif chains)

### Output & UI
- [ ] Theme colors via `T.c_primary()`, `T.c_error()` etc. — no hardcoded color values
- [ ] String formatting with `%` operator: `"值: %.1f°C" % temp`
- [ ] Output via `main.append_output(bbcode)` or `tw.append(text)` — not `print()`
  <!-- print() 仅用于调试日志，格式: print("[ModuleName] 消息") -->
- [ ] Debug logs follow format: `print("[ClassName] 描述: %s" % value)`
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
