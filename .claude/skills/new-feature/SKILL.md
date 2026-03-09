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

Follow the `image_viewer.gd` / `oscilloscope.gd` pattern. Key elements:

- Class extends RefCounted with `is_active: bool` and `overlay: Panel`
- `_ensure_overlay()` → creates Panel, adds to main as child, sets transparent bg
- `show()` → set `is_active = true`, show overlay, disable `main.input_field`
- `hide()` → set `is_active = false`, hide overlay, re-enable input
- `handle_input(event: InputEvent) -> bool` → return `true` if handled (ESC/Q to close)
- Custom rendering via inner `_*Canvas` class with `_draw()` override

**In main.gd**, add input priority handling in `_input()`:
```gdscript
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

## GDScript Style Reminder

See root `CLAUDE.md` for full GDScript 4.6 conventions and code-review skill for checklist.
