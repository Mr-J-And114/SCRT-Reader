# ============================================================
# settings_manager.gd - 统一设置系统核心管理器
# 负责：设置注册/读写/持久化/通知/命令接口
# 路径：res://scripts/settings/settings_manager.gd
# ============================================================
class_name SettingsManager
extends RefCounted

# ============================================================
# 信号
# ============================================================
## 设置值变更通知 (key, old_value, new_value)
signal setting_changed(key: String, old_value: Variant, new_value: Variant)

# ============================================================
# 引用
# ============================================================
var _main = null          # main.gd 实例
var _storage: SettingsStorage = null
var _fs: FileSystem = null
var T = null              # 当前主题

# ============================================================
# 数据
# ============================================================
## 分类注册表 { "display": { id, display_name, icon, order } }
var _categories: Dictionary = {}

## 设置项定义表 { "audio.master_volume": { ...SettingDef... } }
var _definitions: Dictionary = {}

## 当前值表 { "audio.master_volume": 0.8 }
var _values: Dictionary = {}

## apply 回调表 { "audio.master_volume": Callable }
var _apply_callbacks: Dictionary = {}

## 当前登录用户名（用于判断是否需要保存到用户文件）
var _current_username: String = ""

## 初始化完成标志（防止初始化期间的 apply 回调触发保存）
var _initialized: bool = false

# ============================================================
# 初始化
# ============================================================
func setup(main_ref, fs: FileSystem, theme, save_root: String) -> void:
	_main = main_ref
	_fs = fs
	T = theme

	# 初始化存储后端
	_storage = SettingsStorage.new()
	_storage.setup(save_root)

	# 注册内置分类
	for cat in SettingsRegistry.get_categories():
		register_category(cat)

	# 注册内置设置项
	for def in SettingsRegistry.get_settings():
		register_setting(def)

	# 加载全局设置
	_load_global_settings()

	_initialized = true
	print("[SettingsManager] 初始化完成，已注册 %d 个分类，%d 个设置项" % [_categories.size(), _definitions.size()])

# ============================================================
# 分类注册
# ============================================================
func register_category(cat_def: Dictionary) -> void:
	var id: String = str(cat_def.get("id", ""))
	if id.is_empty():
		push_warning("[SettingsManager] 分类注册失败：缺少 id")
		return
	_categories[id] = {
		"id": id,
		"display_name": str(cat_def.get("display_name", id)),
		"icon": str(cat_def.get("icon", "●")),
		"order": int(cat_def.get("order", 99)),
	}

# ============================================================
# 设置项注册
# ============================================================
func register_setting(def: Dictionary) -> void:
	var key: String = str(def.get("key", ""))
	if key.is_empty() or not key.contains("."):
		push_warning("[SettingsManager] 设置注册失败：key 格式错误: " + key)
		return

	var category_id: String = key.split(".")[0]
	if not _categories.has(category_id):
		push_warning("[SettingsManager] 设置注册失败：分类不存在: " + category_id)
		return

	_definitions[key] = def.duplicate()

	# 设置默认值（如果当前没有值）
	if not _values.has(key):
		_values[key] = def.get("default")

## 注册 apply 回调（由各模块在初始化后调用）
func register_apply(key: String, callback: Callable) -> void:
	_apply_callbacks[key] = callback

# ============================================================
# 值读取
# ============================================================
## 获取设置值
func get_value(key: String) -> Variant:
	if _values.has(key):
		return _values[key]
	if _definitions.has(key):
		return _definitions[key].get("default")
	return null

## 获取设置值（类型安全的快捷方法）
func get_bool(key: String) -> bool:
	var v = get_value(key)
	if v is bool:
		return v
	return bool(v) if v != null else false

func get_float(key: String) -> float:
	var v = get_value(key)
	if v is float or v is int:
		return float(v)
	return 0.0

func get_int(key: String) -> int:
	var v = get_value(key)
	if v is int:
		return v
	if v is float:
		return int(v)
	return 0

## 获取所有设置键名（供 Tab 补全使用）
func get_all_keys() -> Array[String]:
	var keys: Array[String] = []
	for key in _definitions.keys():
		keys.append(str(key))
	return keys

func get_string(key: String) -> String:
	var v = get_value(key)
	return str(v) if v != null else ""

# ============================================================
# 值写入
# ============================================================
## 设置值，返回是否成功
## 会自动：验证 → 应用 → 持久化 → 发信号
func set_value(key: String, value: Variant) -> Dictionary:
	if not _definitions.has(key):
		return {"success": false, "message": "未知的设置项: " + key}

	var def: Dictionary = _definitions[key]

	# 类型转换和验证
	var result: Dictionary = _validate_and_convert(def, value)
	if not result["success"]:
		return result

	var converted_value: Variant = result["value"]
	var old_value: Variant = _values.get(key)

	# 值未变化则跳过
	if old_value != null and _values_equal(old_value, converted_value):
		return {"success": true, "message": "值未变化", "unchanged": true}

	# 写入
	_values[key] = converted_value

	# 触发 apply 回调
	if _apply_callbacks.has(key):
		_apply_callbacks[key].call(converted_value)

	# 持久化
	if _initialized:
		_save_current()

	# 发信号
	setting_changed.emit(key, old_value, converted_value)

	return {"success": true, "message": "已更新", "old_value": old_value, "new_value": converted_value}

# ============================================================
# 重置
# ============================================================
## 重置单个设置项为默认值
func reset_key(key: String) -> bool:
	if not _definitions.has(key):
		return false
	var def: Dictionary = _definitions[key]
	set_value(key, def.get("default"))
	return true

## 重置整个分类
func reset_category(category_id: String) -> int:
	var count: int = 0
	for key in _definitions.keys():
		if str(key).begins_with(category_id + "."):
			reset_key(key)
			count += 1
	return count

## 恢复出厂设置（重置所有）
func reset_all() -> int:
	var count: int = 0
	for key in _definitions.keys():
		reset_key(key)
		count += 1
	return count

# ============================================================
# 查询
# ============================================================
## 列出所有分类（按 order 排序）
func list_categories() -> Array[Dictionary]:
	var cats: Array[Dictionary] = []
	for cat in _categories.values():
		cats.append(cat as Dictionary)
	cats.sort_custom(func(a, b): return int(a.get("order", 99)) < int(b.get("order", 99)))
	return cats

## 列出指定分类下所有设置项定义
func list_settings(category_id: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for key in _definitions.keys():
		if str(key).begins_with(category_id + "."):
			items.append(_definitions[key] as Dictionary)
	return items

## 获取设置项定义
func get_definition(key: String) -> Dictionary:
	return _definitions.get(key, {}) as Dictionary

## 检查分类是否存在
func has_category(category_id: String) -> bool:
	return _categories.has(category_id)

## 检查设置项是否存在
func has_setting(key: String) -> bool:
	return _definitions.has(key)

# ============================================================
# 用户切换
# ============================================================
## 用户登录时调用：加载用户设置并覆盖 user_bound 项
func on_user_login(username: String) -> void:
	_current_username = username
	var user_data: Dictionary = _storage.load_user(username)
	if user_data.is_empty():
		# 新用户：用当前全局值初始化用户设置文件
		_save_user_settings()
		print("[SettingsManager] 新用户 %s，已创建默认设置" % username)
		return

	# 覆盖 user_bound 设置项
	var applied_count: int = 0
	for key in user_data.keys():
		if not _definitions.has(key):
			continue
		var def: Dictionary = _definitions[key]
		if not def.get("user_bound", true):
			continue
		var old_val = _values.get(key)
		_values[key] = user_data[key]
		# 触发 apply
		if _apply_callbacks.has(key) and old_val != user_data[key]:
			_apply_callbacks[key].call(user_data[key])
		applied_count += 1

	print("[SettingsManager] 已加载用户 %s 的设置 (%d 项)" % [username, applied_count])

## 用户注销时调用：回退 user_bound 项到全局默认
func on_user_logout() -> void:
	# 注销前先保存当前用户设置
	if not _current_username.is_empty():
		_save_user_settings()

	_current_username = ""

	# 回退到全局设置
	var global_data: Dictionary = _storage.load_global()
	for key in _definitions.keys():
		var def: Dictionary = _definitions[key]
		if not def.get("user_bound", true):
			continue
		var fallback_value = global_data.get(key, def.get("default"))
		var old_val = _values.get(key)
		_values[key] = fallback_value
		if _apply_callbacks.has(key) and old_val != fallback_value:
			_apply_callbacks[key].call(fallback_value)

	print("[SettingsManager] 用户已注销，设置已回退到全局默认")

# ============================================================
# 旧配置检测
# ============================================================
## 检测并返回旧配置警告文本，无旧文件则返回空字符串
func check_legacy_files() -> String:
	if _storage == null:
		return ""
	var legacy: Array[String] = _storage.detect_legacy_files()
	if legacy.is_empty():
		return ""
	return _storage.get_legacy_warning(legacy, T)

# ============================================================
# 命令处理
# ============================================================
## 处理 settings 命令，返回 true 表示已处理
func handle_command(args: Array) -> bool:
	if _main == null:
		return false

	# settings（无参数）→ 显示分类概览
	if args.is_empty():
		_show_overview()
		return true

	var first: String = str(args[0]).strip_edges()

	# settings reset ...
	if first == "reset":
		_handle_reset(args.slice(1))
		return true

	# settings export
	if first == "export":
		_handle_export()
		return true

	# settings import
	if first == "import":
		_handle_import()
		return true

	# settings <分类名> → 显示分类详情
	if has_category(first):
		_show_category(first)
		return true

	# settings <key> → 显示单项详情 或 settings <key> <value> → 修改
	if args.size() == 1:
		# 可能是 key 查询
		if has_setting(first):
			_show_setting_detail(first)
			return true
		# 也可能是分类的简称（取 . 前面的部分）
		_output_error("未知的设置项或分类: " + first)
		_output_hint("输入 settings 查看所有分类")
		return true

	# settings <key> <value>
	if args.size() >= 2:
		var key: String = first
		# 支持省略分类前缀的模糊查找
		if not has_setting(key):
			key = _fuzzy_find_key(first)
		if key.is_empty():
			_output_error("未知的设置项: " + first)
			_output_hint("输入 settings <分类> 查看可用设置项")
			return true

		var value_str: String = str(args[1]).strip_edges()
		var def: Dictionary = get_definition(key)

		# 需要确认的设置（如主题切换）
		if def.get("requires_confirm", false):
			_handle_confirm_setting(key, value_str)
			return true

		var result: Dictionary = set_value(key, value_str)
		if result["success"]:
			if result.get("unchanged", false):
				_output_muted("值未变化: " + key + " = " + _format_display_value(key))
			else:
				_output_success(key + " 已更新为 " + _format_display_value(key))
		else:
			_output_error(str(result.get("message", "设置失败")))
		return true

	return true

# ============================================================
# Tab 补全
# ============================================================
## 返回补全候选项
func get_completions(current_text: String) -> Array[String]:
	var completions: Array[String] = []
	var parts: PackedStringArray = current_text.strip_edges().split(" ", false)

	# settings [Tab] → 分类列表 + reset/export/import
	if parts.size() <= 1:
		var prefix: String = parts[0] if parts.size() == 1 else ""
		# 分类
		for cat in list_categories():
			var cid: String = str(cat["id"])
			if prefix.is_empty() or cid.begins_with(prefix):
				completions.append(cid)
		# 所有 key
		for key in _definitions.keys():
			if prefix.is_empty() or str(key).begins_with(prefix):
				completions.append(str(key))
		# 子命令
		for sub in ["reset", "export", "import"]:
			if prefix.is_empty() or sub.begins_with(prefix):
				completions.append(sub)
		return completions

	var first: String = str(parts[0])

	# settings <分类> [Tab] → 该分类下的 key
	if has_category(first):
		var prefix: String = str(parts[1]) if parts.size() > 1 else ""
		for def in list_settings(first):
			var key: String = str(def["key"])
			# 补全完整 key 或省略分类前缀的短名
			var short_name: String = key.substr(first.length() + 1)
			if prefix.is_empty() or key.begins_with(prefix) or short_name.begins_with(prefix):
				completions.append(key)
		return completions

	# settings <key> [Tab] → 枚举值候选
	if has_setting(first) and parts.size() == 1:
		var def: Dictionary = get_definition(first)
		if def.get("type", "") == "enum":
			var vals: Array = def.get("enum_values", [])
			for v in vals:
				completions.append(str(v))
		elif def.get("type", "") == "bool":
			completions.append("true")
			completions.append("false")
		return completions

	# settings reset [Tab] → 分类 + all
	if first == "reset":
		var prefix: String = str(parts[1]) if parts.size() > 1 else ""
		for cat in list_categories():
			var cid: String = str(cat["id"])
			if prefix.is_empty() or cid.begins_with(prefix):
				completions.append(cid)
		if prefix.is_empty() or "all".begins_with(prefix):
			completions.append("all")
		return completions

	return completions

# ============================================================
# 显示 - 概览
# ============================================================
func _show_overview() -> void:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex

	var title_lines: Array[String] = ["TERMINAL SETTINGS", "终端设置"]
	var box: String = _fs.build_box(title_lines, p)
	_output_raw(box + "\n\n")

	for cat in list_categories():
		var settings: Array[Dictionary] = list_settings(str(cat["id"]))
		var icon: String = str(cat.get("icon", "●"))
		var name: String = str(cat.get("display_name", cat["id"]))
		var count: int = settings.size()
		_output_raw("  [color=" + w + "]" + icon + "[/color] [color=" + p + "]" + str(cat["id"]) + "[/color]")
		_output_raw("    [color=" + m + "]" + name + " (" + str(count) + "项)[/color]\n")

	_output_raw("\n")
	_output_raw("[color=" + m + "]用法:[/color]\n")
	_output_raw("  [color=" + p + "]settings <分类>[/color]         [color=" + m + "]查看分类下所有设置[/color]\n")
	_output_raw("  [color=" + p + "]settings <key>[/color]          [color=" + m + "]查看设置详情[/color]\n")
	_output_raw("  [color=" + p + "]settings <key> <value>[/color]  [color=" + m + "]修改设置值[/color]\n")
	_output_raw("  [color=" + p + "]settings reset <分类|all>[/color] [color=" + m + "]重置设置[/color]\n")
	_output_raw("  [color=" + p + "]settings export[/color]         [color=" + m + "]导出设置到剪贴板[/color]\n")
	_output_raw("  [color=" + p + "]settings import[/color]         [color=" + m + "]从剪贴板导入设置[/color]\n")

# ============================================================
# 显示 - 分类详情
# ============================================================
func _show_category(category_id: String) -> void:
	var cat: Dictionary = _categories.get(category_id, {})
	if cat.is_empty():
		return

	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex
	var s: String = T.success_hex

	var icon: String = str(cat.get("icon", "●"))
	var cat_name: String = str(cat.get("display_name", category_id))

	var title_lines: Array[String] = [icon + " " + cat_name]
	var box: String = _fs.build_box(title_lines, p)
	_output_raw(box + "\n\n")

	var settings: Array[Dictionary] = list_settings(category_id)
	for def in settings:
		var key: String = str(def["key"])
		var name: String = str(def.get("display_name", key))
		var desc: String = str(def.get("description", ""))
		var current_display: String = _format_display_value(key)
		var default_display: String = _format_value_with_def(def, def.get("default"))

		_output_raw("  [color=" + p + "]" + key + "[/color]\n")
		_output_raw("    [color=" + m + "]" + name + "[/color]\n")
		_output_raw("    [color=" + s + "]当前: " + current_display + "[/color]")
		_output_raw("  [color=" + m + "]默认: " + default_display + "[/color]\n")

		# 显示旧命令快捷方式
		var shortcut: String = str(def.get("shortcut_cmd", ""))
		if not shortcut.is_empty():
			_output_raw("    [color=" + w + "]快捷命令: " + shortcut + "[/color]\n")

		if not desc.is_empty():
			_output_raw("    [color=" + m + "]" + desc + "[/color]\n")
		_output_raw("\n")

# ============================================================
# 显示 - 单项详情
# ============================================================
func _show_setting_detail(key: String) -> void:
	var def: Dictionary = get_definition(key)
	if def.is_empty():
		return

	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var w: String = T.warning_hex
	var s: String = T.success_hex

	var name: String = str(def.get("display_name", key))
	var desc: String = str(def.get("description", ""))
	var type_str: String = str(def.get("type", "unknown"))
	var current_display: String = _format_display_value(key)
	var default_display: String = _format_value_with_def(def, def.get("default"))

	_output_raw("\n[color=" + p + "]" + key + "[/color]  [color=" + m + "](" + name + ")[/color]\n")
	_output_raw("[color=" + m + "]" + "─".repeat(40) + "[/color]\n")

	if not desc.is_empty():
		_output_raw("[color=" + m + "]" + desc + "[/color]\n\n")

	_output_raw("[color=" + m + "]类型:  [/color][color=" + p + "]" + type_str + "[/color]\n")
	_output_raw("[color=" + m + "]当前:  [/color][color=" + s + "]" + current_display + "[/color]\n")
	_output_raw("[color=" + m + "]默认:  [/color][color=" + p + "]" + default_display + "[/color]\n")

	# 范围信息
	if def.has("min") and def.has("max"):
		var range_str: String = str(def["min"]) + " ~ " + str(def["max"])
		if def.has("step"):
			range_str += " (步进: " + str(def["step"]) + ")"
		_output_raw("[color=" + m + "]范围:  [/color][color=" + p + "]" + range_str + "[/color]\n")

	# 枚举值
	if type_str == "enum":
		var vals: Array = def.get("enum_values", [])
		var labels: Array = def.get("enum_labels", [])
		_output_raw("[color=" + m + "]可选:  [/color]")
		for i in range(vals.size()):
			var v: String = str(vals[i])
			var label: String = str(labels[i]) if i < labels.size() else v
			var marker: String = " ◄" if v == str(get_value(key)) else ""
			_output_raw("[color=" + p + "]" + v + "[/color][color=" + m + "](" + label + ")" + marker + "  [/color]")
		_output_raw("\n")

	# 快捷命令
	var shortcut: String = str(def.get("shortcut_cmd", ""))
	if not shortcut.is_empty():
		_output_raw("\n[color=" + w + "]快捷命令: " + shortcut + "[/color]\n")

	_output_raw("\n[color=" + m + "]修改: settings " + key + " <新值>[/color]\n")
	_output_raw("[color=" + m + "]重置: settings reset " + key + "[/color]\n")

# ============================================================
# 需要确认的设置（主题切换）
# ============================================================
func _handle_confirm_setting(key: String, value_str: String) -> void:
	var def: Dictionary = get_definition(key)

	# 验证值是否合法
	var result: Dictionary = _validate_and_convert(def, value_str)
	if not result["success"]:
		_output_error(str(result.get("message", "值无效")))
		return

	var new_value = result["value"]
	var old_value = get_value(key)

	if _values_equal(old_value, new_value):
		_output_muted("值未变化: " + key + " = " + _format_display_value(key))
		return

	# 特殊处理：主题切换
	if key == "display.theme":
		_handle_theme_change(str(new_value))
		return

	# 通用确认（预留，目前只有主题需要确认）
	set_value(key, new_value)
	_output_success(key + " 已更新为 " + _format_display_value(key))

## 主题切换专用处理
## 主题切换专用处理
func _handle_theme_change(theme_name: String) -> void:
	# 使用 ThemeManager 的可用主题列表验证
	var available: Array[String] = ThemeManager.get_available_themes()
	if theme_name not in available:
		var valid: String = " / ".join(available)
		_output_error("未知主题: " + theme_name)
		_output_hint("可用主题: " + valid)
		return

	var current_theme: String = get_string("display.theme")
	if theme_name == current_theme:
		_output_muted("当前已经是 " + theme_name + " 主题")
		return

	# 调用 ThemeManager 的确认流程
	# request_theme_change 会设置 main._theme_confirm_mode = true
	ThemeManager.request_theme_change(theme_name, _main)


# ============================================================
# 重置处理
# ============================================================
func _handle_reset(args: Array) -> void:
	if args.is_empty():
		_output_muted("用法: settings reset <分类|key|all>")
		return

	var target: String = str(args[0]).strip_edges()

	if target == "all":
		var count: int = reset_all()
		_output_success("已重置所有设置 (" + str(count) + " 项)")
		return

	if has_category(target):
		var count: int = reset_category(target)
		_output_success("已重置 " + target + " 分类 (" + str(count) + " 项)")
		return

	if has_setting(target):
		reset_key(target)
		_output_success("已重置 " + target + " 为默认值: " + _format_display_value(target))
		return

	_output_error("未知的分类或设置项: " + target)

# ============================================================
# 导出/导入
# ============================================================
func _handle_export() -> void:
	var export_data: Dictionary = {}
	for key in _values.keys():
		export_data[key] = _values[key]
	var json_str: String = JSON.stringify(export_data, "\t")
	DisplayServer.clipboard_set(json_str)
	_output_success("当前设置已导出到剪贴板 (" + str(export_data.size()) + " 项)")

func _handle_import() -> void:
	var clipboard: String = DisplayServer.clipboard_get()
	if clipboard.strip_edges().is_empty():
		_output_error("剪贴板为空")
		return

	var json := JSON.new()
	if json.parse(clipboard) != OK:
		_output_error("剪贴板内容不是有效的 JSON")
		return

	if not (json.data is Dictionary):
		_output_error("JSON 格式不正确，需要一个对象")
		return

	var import_data: Dictionary = json.data
	var applied: int = 0
	var skipped: int = 0

	for key in import_data.keys():
		if has_setting(str(key)):
			var result: Dictionary = set_value(str(key), import_data[key])
			if result["success"]:
				applied += 1
			else:
				skipped += 1
		else:
			skipped += 1

	_output_success("导入完成: 已应用 " + str(applied) + " 项，跳过 " + str(skipped) + " 项")

# ============================================================
# 验证和类型转换
# ============================================================
func _validate_and_convert(def: Dictionary, value: Variant) -> Dictionary:
	var type_str: String = str(def.get("type", "string"))
	var value_str: String = str(value).strip_edges()

	match type_str:
		"bool":
			match value_str.to_lower():
				"true", "on", "1", "yes":
					return {"success": true, "value": true}
				"false", "off", "0", "no":
					return {"success": true, "value": false}
				_:
					if value is bool:
						return {"success": true, "value": value}
					return {"success": false, "message": "布尔值应为 true/false/on/off"}

		"int":
			if not value_str.is_valid_int():
				return {"success": false, "message": "需要整数值"}
			var int_val: int = int(value_str)
			if def.has("min") and int_val < int(def["min"]):
				return {"success": false, "message": "值不能小于 " + str(def["min"])}
			if def.has("max") and int_val > int(def["max"]):
				return {"success": false, "message": "值不能大于 " + str(def["max"])}
			return {"success": true, "value": int_val}

		"float":
			if not value_str.is_valid_float():
				# 尝试百分比格式：如 "80" 对于 0~1 范围的值 → 0.8
				if value_str.is_valid_int() and def.has("max") and float(def["max"]) <= 1.0:
					var percentage: float = float(value_str) / 100.0
					if def.has("min") and percentage < float(def["min"]):
						return {"success": false, "message": "值不能小于 " + str(def["min"])}
					if percentage > float(def["max"]):
						return {"success": false, "message": "值不能大于 " + str(float(def["max"]) * 100.0) + "%"}
					return {"success": true, "value": percentage}
				return {"success": false, "message": "需要数值"}
			var float_val: float = float(value_str)
			if def.has("min") and float_val < float(def["min"]):
				return {"success": false, "message": "值不能小于 " + str(def["min"])}
			if def.has("max") and float_val > float(def["max"]):
				return {"success": false, "message": "值不能大于 " + str(def["max"])}
			return {"success": true, "value": float_val}

		"enum":
			var enum_values: Array = def.get("enum_values", [])
			# 精确匹配
			for ev in enum_values:
				if value_str.to_lower() == str(ev).to_lower():
					return {"success": true, "value": str(ev)}
			# 前缀匹配
			var matches: Array[String] = []
			for ev in enum_values:
				if str(ev).to_lower().begins_with(value_str.to_lower()):
					matches.append(str(ev))
			if matches.size() == 1:
				return {"success": true, "value": matches[0]}
			var valid: String = " / ".join(enum_values.map(func(v): return str(v)))
			return {"success": false, "message": "无效选项。可选: " + valid}

		"string":
			return {"success": true, "value": value_str}

	return {"success": false, "message": "未知类型: " + type_str}

# ============================================================
# 值比较
# ============================================================
func _values_equal(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return absf(float(a) - float(b)) < 0.0001
	return a == b

# ============================================================
# 格式化显示值
# ============================================================
func _format_display_value(key: String) -> String:
	var def: Dictionary = get_definition(key)
	var value = get_value(key)
	return _format_value_with_def(def, value)

func _format_value_with_def(def: Dictionary, value: Variant) -> String:
	var type_str: String = str(def.get("type", "string"))
	var unit: String = str(def.get("unit", ""))

	match type_str:
		"bool":
			return "开启" if value else "关闭"
		"float":
			# 0~1 范围且单位为 % → 显示为百分比
			if unit == "%" and def.has("max") and float(def["max"]) <= 1.0:
				return str(int(float(value) * 100)) + "%"
			# 保留合理精度
			if float(value) == int(float(value)):
				return str(int(float(value))) + (" " + unit if not unit.is_empty() else "")
			return ("%.3f" % float(value)).rstrip("0").rstrip(".") + (" " + unit if not unit.is_empty() else "")
		"int":
			return str(value) + (" " + unit if not unit.is_empty() else "")
		"enum":
			var enum_values: Array = def.get("enum_values", [])
			var enum_labels: Array = def.get("enum_labels", [])
			var idx: int = enum_values.find(value)
			if idx >= 0 and idx < enum_labels.size():
				return str(value) + " (" + str(enum_labels[idx]) + ")"
			return str(value)
		"string":
			return str(value)

	return str(value)

# ============================================================
# 模糊查找 key（支持省略分类前缀）
# ============================================================
func _fuzzy_find_key(input: String) -> String:
	# 精确匹配
	if _definitions.has(input):
		return input

	# 尝试在每个分类中查找短名
	var input_lower: String = input.to_lower()
	var candidates: Array[String] = []
	for key in _definitions.keys():
		var key_str: String = str(key)
		# 完整 key 匹配
		if key_str.to_lower() == input_lower:
			return key_str
		# 短名匹配（去掉分类前缀）
		var dot_pos: int = key_str.find(".")
		if dot_pos >= 0:
			var short_name: String = key_str.substr(dot_pos + 1)
			if short_name.to_lower() == input_lower:
				candidates.append(key_str)

	if candidates.size() == 1:
		return candidates[0]

	return ""

# ============================================================
# 持久化
# ============================================================
func _load_global_settings() -> void:
	var data: Dictionary = _storage.load_global()
	for key in data.keys():
		if _definitions.has(str(key)):
			_values[str(key)] = data[key]

func _save_current() -> void:
	# 保存全局设置（非 user_bound 项 + 所有项的默认副本）
	_save_global_settings()
	# 如果有登录用户，同时保存用户设置
	if not _current_username.is_empty():
		_save_user_settings()

func _save_global_settings() -> void:
	var data: Dictionary = {}
	for key in _values.keys():
		data[key] = _values[key]
	_storage.save_global(data)

func _save_user_settings() -> void:
	if _current_username.is_empty():
		return
	var data: Dictionary = {}
	for key in _values.keys():
		var def: Dictionary = _definitions.get(key, {}) as Dictionary
		if def.get("user_bound", true):
			data[key] = _values[key]
	_storage.save_user(_current_username, data)

# ============================================================
# 输出辅助（统一通过 main.append_output）
# ============================================================
func _output_raw(text: String) -> void:
	if _main and _main.has_method("append_output"):
		_main.append_output(text, false, false)

func _output_success(text: String) -> void:
	_output_raw("[color=" + T.success_hex + "]" + text + "[/color]\n")

func _output_error(text: String) -> void:
	_output_raw("[color=" + T.error_hex + "]" + text + "[/color]\n")

func _output_muted(text: String) -> void:
	_output_raw("[color=" + T.muted_hex + "]" + text + "[/color]\n")

func _output_hint(text: String) -> void:
	_output_raw("[color=" + T.muted_hex + "]" + text + "[/color]\n")

# ============================================================
# 主题确认完成后的回调（由 main.gd 在确认流程结束后调用）
# ============================================================
func on_theme_confirmed(theme_name: String) -> void:
	_values["display.theme"] = theme_name
	if _initialized:
		_save_current()
	print("[SettingsManager] 主题已确认更新: " + theme_name)

func on_theme_cancelled() -> void:
	# 主题取消，无需操作（值未变）
	pass
