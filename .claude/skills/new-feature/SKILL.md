# Skill: Add New Feature (Godot 4.6)

You are extending the SCRT-Reader terminal with a new feature/system.
Follow the 7-step process below with Godot 4.6 GDScript conventions.
<!-- 详细步骤参考 docs/extension-guide.md -->

## Step 1: Create Class

Create a new `.gd` file in `SCRT/scripts/` following this template:

```gdscript
class_name MyNewSystem
extends RefCounted

# 依赖引用（通过 setup() 注入）
var main = null
var T = null  # ThemeManager

# 状态
var is_active: bool = false

# 信号（需要时声明）
signal status_changed(id: String, value: float)

func setup(p_main) -> void:
    main = p_main
    T = ThemeManager.current
```

**Rules:**
- Use `RefCounted` unless you need `_process()` (then use `Node`)
- Always declare `class_name` at top
- All vars/params/returns must have type annotations
- Accept dependencies via `setup()` method (no autoloads)

## Step 2: Instantiate in main.gd

In `main.gd._ready()`, add:
```gdscript
# 在变量声明区
var my_system: MyNewSystem = null

# 在 _ready() 中
my_system = MyNewSystem.new()
my_system.setup(self)
```

If it needs per-frame updates, call from `main._process()`:
```gdscript
if my_system:
    my_system.process(delta)
```

## Step 3: Register Commands (if needed)

In `command_handler.gd`:

```gdscript
# 在 _register_commands() 的对应字典中添加
desktop_commands["mycmd"] = _cmd_mycmd    # 桌面模式命令
# 或
disc_commands["mycmd"] = _cmd_mycmd       # 故事模式命令

# 命令处理方法
func _cmd_mycmd(args: Array = []) -> void:
    var p: String = T.primary_hex
    var m: String = T.muted_hex
    if args.is_empty():
        main.append_output("[color=%s]用法: mycmd <参数>[/color]\n" % m, false)
        return
    # ... 实现逻辑
    main.append_output("[color=%s]结果: %s[/color]\n" % [p, result], false)
```

**Three command dictionaries** (choose one):
- `global_commands` — available in both desktop and disc modes
- `desktop_commands` — only in desktop mode (no story loaded)
- `disc_commands` — only when a story disc is loaded

## Step 4: Create Overlay (if needed)

Follow the ImageViewer/Oscilloscope pattern:

```gdscript
class_name MyViewer
extends RefCounted

var main = null
var T = null
var is_active: bool = false
var overlay: Panel = null

func setup(p_main) -> void:
    main = p_main
    T = ThemeManager.current

func _ensure_overlay() -> void:
    if overlay != null and is_instance_valid(overlay):
        return
    overlay = Panel.new()
    overlay.name = "MyViewerOverlay"
    overlay.visible = false
    var bg := StyleBoxFlat.new()
    bg.bg_color = Color(0, 0, 0, 0)
    overlay.add_theme_stylebox_override("panel", bg)
    var root: Control = main as Control
    root.add_child(overlay)
    # 添加自定义 Canvas（用于 _draw 渲染）
    # var canvas := _MyCanvas.new()
    # overlay.add_child(canvas)

func show() -> void:
    _ensure_overlay()
    is_active = true
    overlay.visible = true
    main.input_field.editable = false  # 禁用终端输入

func hide() -> void:
    is_active = false
    if overlay:
        overlay.visible = false
    main.input_field.editable = true   # 恢复终端输入

func handle_input(event: InputEvent) -> bool:
    if not is_active:
        return false
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_ESCAPE, KEY_Q:
                hide()
                return true
    return false
```

**In main.gd**, add input priority handling:
```gdscript
# 在 _input() 中，按优先级链插入
if _my_viewer_mode and my_viewer and my_viewer.is_active:
    if my_viewer.handle_input(event):
        get_viewport().set_input_as_handled()
        return
```

## Step 5: Parse Manifest Data (if needed)

In `disc_manager.gd` `load_story()`, add parsing for your manifest key:
```gdscript
if manifest.has("my_system"):
    main.my_system.load_from_manifest(manifest["my_system"])
```

## Step 6: Add Save Data (if needed)

Use `extra` dict in save file:
```gdscript
# 保存 (in auto_save or where save_mgr is called)
extra["my_data"] = { "state": current_state, "values": values_dict }

# 加载
var save: Dictionary = save_mgr.load_save(story_id)
if save and save.has("my_data"):
    _restore_state(save["my_data"])
```

## Step 7: Register Settings (if needed)

```gdscript
settings_mgr.register_category("my_feature", "我的功能")
settings_mgr.register_setting("my_feature", "enabled", true, "启用", "toggle")
settings_mgr.register_setting("my_feature", "intensity", 0.8, "强度", "slider", {"min": 0.0, "max": 1.0})
```

## Key Godot 4.6 API Reminders

| Task | Pattern |
|---|---|
| JSON read | `var json := JSON.new(); json.parse(text); json.data` |
| JSON write | `JSON.stringify(data, "\t")` |
| File read | `var f := FileAccess.open(path, FileAccess.READ)` |
| File write | `var f := FileAccess.open(path, FileAccess.WRITE)` |
| Dir check | `DirAccess.dir_exists_absolute(path)` |
| Delay | `await get_tree().create_timer(0.5).timeout` |
| Tween | `var tw: Tween = create_tween()` |
| Type cast | `var d: Dictionary = data as Dictionary` |
| String fmt | `"值: %d, 名: %s" % [count, name]` |
