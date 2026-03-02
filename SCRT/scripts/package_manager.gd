# ============================================================
# package_manager.gd - 模组管理器
# 负责：.scp 模组包的加载/编译/安装/卸载/生命周期管理
# ============================================================
class_name PackageManager
extends RefCounted

# ══════════════════════════════════════════
#  模块引用
# ══════════════════════════════════════════
var main = null
var fs: FileSystem = null
var T = null
var tw = null
var user_mgr = null
var disc_mgr = null
var cmd_handler = null
var story_loader = null
var audio_mgr = null

# ══════════════════════════════════════════
#  数据
# ══════════════════════════════════════════

## 已安装的模组元数据 { "mod_id": { manifest_package字段 + "_source_filename" + "_installed_at" } }
var installed_mods: Dictionary = {}

## 活跃的模组实例 { "mod_id": ModBase实例 }
var active_mods: Dictionary = {}

## 模组注册的命令 { "cmd_name": { "mod_id", "description", "handler": Callable, "mode" } }
var mod_commands: Dictionary = {}

## 模组包内文件缓存 { "mod_id": { "relative_path": PackedByteArray } }
var mod_pack_files: Dictionary = {}

## 隐藏的包文件名（已安装的内部包不再显示在 scan 中）
var hidden_package_files: Array[String] = []

## 模组持久化数据 { "mod_id": { "key": value } }
var mod_data_store: Dictionary = {}

## 当前输入捕获 { "mod_id": String, "handler": Callable } 或空
var _input_capture: Dictionary = {}

## ★ NEW: 事件订阅表 { "event_name": { "mod_id": Callable } }
var _event_subscribers: Dictionary = {}
## ★ NEW: 模组 UI 容器节点 { "mod_id": Control }
var _mod_containers: Dictionary = {}

## 需要每帧更新的模组 ID 列表
var _process_mods: Array[String] = []

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main, p_fs, p_theme, p_tw, p_user_mgr, p_disc_mgr, p_cmd_handler, p_story_loader) -> void:
	main = p_main
	fs = p_fs
	T = p_theme
	tw = p_tw
	user_mgr = p_user_mgr
	disc_mgr = p_disc_mgr
	cmd_handler = p_cmd_handler
	story_loader = p_story_loader
	if main:
		audio_mgr = main.audio_manager

# ══════════════════════════════════════════
#  每帧更新（由 main._process 调用）
# ══════════════════════════════════════════
func process(delta: float) -> void:
	for mod_id in _process_mods:
		if active_mods.has(mod_id):
			var mod_instance: ModBase = active_mods[mod_id] as ModBase
			mod_instance._process(delta)

# ══════════════════════════════════════════
#  输入捕获处理（由 main._input 调用）
# ══════════════════════════════════════════
func handle_input(event: InputEvent) -> bool:
	if _input_capture.is_empty():
		return false
	if not event is InputEventKey or not event.pressed:
		return false
	var handler: Callable = _input_capture.get("handler", Callable()) as Callable
	if handler.is_valid():
		return handler.call(event)
	return false

# ══════════════════════════════════════════
#  包类型判断（静态）
# ══════════════════════════════════════════
static func is_package_manifest(manifest: Dictionary) -> bool:
	return manifest.has("package") and manifest["package"] is Dictionary

static func get_package_type(manifest: Dictionary) -> String:
	if not is_package_manifest(manifest):
		return ""
	var pkg: Dictionary = manifest["package"] as Dictionary
	return str(pkg.get("type", "external")).to_lower()

static func get_package_info(manifest: Dictionary) -> Dictionary:
	if not is_package_manifest(manifest):
		return {}
	return manifest["package"] as Dictionary

# ══════════════════════════════════════════
#  登录后恢复
# ══════════════════════════════════════════
func load_installed_mods() -> void:
	_shutdown_all_mods()

	if not user_mgr or not user_mgr.is_logged_in:
		return

	var profile: Dictionary = user_mgr.current_user
	var saved_mods: Dictionary = profile.get("installed_packages", {}) as Dictionary
	var saved_data: Dictionary = profile.get("mod_data_store", {}) as Dictionary
	mod_data_store = saved_data.duplicate(true) if not saved_data.is_empty() else {}

	if saved_mods.is_empty():
		print("[PackageManager] 无已安装模组")
		return

	for mod_id in saved_mods.keys():
		var mod_meta: Dictionary = saved_mods[mod_id] as Dictionary
		installed_mods[mod_id] = mod_meta

		var source_file: String = str(mod_meta.get("_source_filename", ""))
		if not source_file.is_empty():
			hidden_package_files.append(source_file)

		# 尝试从磁盘重新加载并编译模组
		var source_path: String = str(mod_meta.get("_source_path", ""))
		if source_path.is_empty() or not FileAccess.file_exists(source_path):
			# 尝试从 vdisc 目录查找
			source_path = _find_package_path(source_file)

		if source_path.is_empty():
			push_warning("[PackageManager] 模组 %s 的源文件不存在，跳过加载" % mod_id)
			continue

		var pack_files: Dictionary = _read_all_pack_files(source_path)
		if pack_files.is_empty():
			push_warning("[PackageManager] 模组 %s 包文件读取失败" % mod_id)
			continue

		mod_pack_files[mod_id] = pack_files

		# 编译并启用
		var entry_script: String = str(mod_meta.get("entry_script", "mod_main.gd"))
		var mod_instance: ModBase = _compile_and_instantiate(mod_id, pack_files, entry_script)
		if mod_instance == null:
			push_warning("[PackageManager] 模组 %s 编译失败" % mod_id)
			continue

		active_mods[mod_id] = mod_instance
		mod_instance._register_commands()
		mod_instance._on_enable()

		# 检查是否需要 process
		# 通过检查模组是否重写了 _process
		_process_mods.append(mod_id)

		print("[PackageManager] 已恢复模组: %s" % mod_id)

	print("[PackageManager] 共恢复 %d 个模组" % active_mods.size())

# ══════════════════════════════════════════
#  安装模组
# ══════════════════════════════════════════
func install_package(story_index: int) -> Dictionary:
	if not user_mgr or not user_mgr.is_logged_in:
		return { "success": false, "message": "请先登录后再安装模组。" }

	if story_index < 0 or story_index >= disc_mgr.available_stories.size():
		return { "success": false, "message": "无效的磁盘编号。" }

	var story_data: Dictionary = disc_mgr.available_stories[story_index]
	var path: String = str(story_data.get("path", ""))
	var filename: String = str(story_data.get("filename", ""))

	# 读取完整 manifest
	var manifest: Dictionary = _read_manifest_from_zip(path)
	if manifest.is_empty():
		return { "success": false, "message": "无法读取模组信息。" }

	if not is_package_manifest(manifest):
		return { "success": false, "message": "此磁盘不是模组包，请使用 load 命令加载。" }

	var pkg_info: Dictionary = get_package_info(manifest)
	var pkg_type: String = str(pkg_info.get("type", "external")).to_lower()

	if pkg_type != "internal":
		return { "success": false, "message": "此为外部软件包，无需安装。请使用 load 命令加载。" }

	var mod_id: String = str(pkg_info.get("id", ""))
	if mod_id.is_empty():
		return { "success": false, "message": "模组缺少 ID，无法安装。" }

	if installed_mods.has(mod_id):
		return { "success": false, "message": "模组 \"" + str(pkg_info.get("title", mod_id)) + "\" 已安装。" }

	# 读取包内所有文件
	var pack_files: Dictionary = _read_all_pack_files(path)
	if pack_files.is_empty():
		return { "success": false, "message": "模组包内无文件。" }

	# 查找入口脚本
	var entry_script: String = str(pkg_info.get("entry_script", "mod_main.gd"))
	if not pack_files.has(entry_script):
		return { "success": false, "message": "模组缺少入口脚本: " + entry_script }

	# 编译模组
	var mod_instance: ModBase = _compile_and_instantiate(mod_id, pack_files, entry_script)
	if mod_instance == null:
		return { "success": false, "message": "模组脚本编译失败。请检查脚本语法。" }

	# 保存元数据
	var install_data: Dictionary = pkg_info.duplicate(true)
	install_data["_source_filename"] = filename
	install_data["_source_path"] = path
	install_data["_installed_at"] = _get_current_datetime()
	install_data["entry_script"] = entry_script

	installed_mods[mod_id] = install_data
	mod_pack_files[mod_id] = pack_files
	active_mods[mod_id] = mod_instance
	hidden_package_files.append(filename)
	_process_mods.append(mod_id)

	# 调用生命周期
	mod_instance._register_commands()
	mod_instance._on_install()
	mod_instance._on_enable()

	# 持久化
	_save_to_profile()

	var title: String = str(pkg_info.get("title", mod_id))
	var result_msg: String = "模组 \"" + title + "\" 安装成功。"

	# 列出注册的命令
	var registered_cmds: Array[String] = []
	for cmd_name in mod_commands.keys():
		var cmd_info: Dictionary = mod_commands[cmd_name]
		if str(cmd_info.get("mod_id", "")) == mod_id:
			registered_cmds.append(str(cmd_name) + " — " + str(cmd_info.get("description", "")))

	if not registered_cmds.is_empty():
		result_msg += "\n\n已注册命令:"
		for cmd_desc in registered_cmds:
			result_msg += "\n  " + cmd_desc

	return { "success": true, "message": result_msg }

# ══════════════════════════════════════════
#  卸载模组
# ══════════════════════════════════════════
func uninstall_package(id_or_name: String) -> Dictionary:
	if not user_mgr or not user_mgr.is_logged_in:
		return { "success": false, "message": "请先登录。" }

	var mod_id: String = _resolve_mod_id(id_or_name)
	if mod_id.is_empty():
		return { "success": false, "message": "未找到已安装的模组: \"" + id_or_name + "\"" }

	var mod_meta: Dictionary = installed_mods[mod_id]
	var title: String = str(mod_meta.get("title", mod_id))

	# 调用生命周期
	if active_mods.has(mod_id):
		var mod_instance: ModBase = active_mods[mod_id] as ModBase
		mod_instance._on_disable()
		mod_instance._on_uninstall()

	# 注销所有命令
	_unregister_all_commands_for_mod(mod_id)

	# ★ NEW: 清除事件订阅
	_clear_event_subscriptions(mod_id)
	# ★ NEW: 销毁 UI 容器
	_destroy_mod_container(mod_id)


	# 释放输入捕获
	if not _input_capture.is_empty() and str(_input_capture.get("mod_id", "")) == mod_id:
		_input_capture.clear()
		if main and main.input_field:
			main.input_field.editable = true

	# 清理
	active_mods.erase(mod_id)
	mod_pack_files.erase(mod_id)
	_process_mods.erase(mod_id)

	var source_file: String = str(mod_meta.get("_source_filename", ""))
	if not source_file.is_empty():
		hidden_package_files.erase(source_file)

	installed_mods.erase(mod_id)
	mod_data_store.erase(mod_id)

	_save_to_profile()

	return { "success": true, "message": "模组 \"" + title + "\" 已卸载。" }

# ══════════════════════════════════════════
#  已安装列表
# ══════════════════════════════════════════
func get_installed_list_text() -> String:
	var p: String = T.primary_hex
	var m: String = T.muted_hex
	var s: String = T.success_hex
	var e: String = T.error_hex

	if installed_mods.is_empty():
		return "[color=" + m + "]未安装任何模组。[/color]\n[color=" + m + "]使用 scan 扫描可用模组，然后用 install <编号> 安装。[/color]\n"

	var lines: Array[String] = []
	lines.append("[color=" + p + "]═══════════ 已安装模组 ═══════════[/color]")
	lines.append("")

	for mod_id in installed_mods.keys():
		var meta: Dictionary = installed_mods[mod_id]
		var title: String = str(meta.get("title", mod_id))
		var version: String = str(meta.get("version", ""))
		var author: String = str(meta.get("author", "未知"))
		var desc: String = str(meta.get("description", ""))
		var installed_at: String = str(meta.get("_installed_at", ""))
		var is_active: bool = active_mods.has(mod_id)

		var status_icon: String = "[color=" + s + "]●[/color]" if is_active else "[color=" + e + "]○[/color]"
		var version_str: String = " v" + version if not version.is_empty() else ""

		lines.append("  " + status_icon + " [color=" + p + "]" + title + version_str + "[/color]")
		lines.append("      [color=" + m + "]ID: " + mod_id + "  |  作者: " + author + "[/color]")
		if not desc.is_empty():
			lines.append("      [color=" + m + "]" + desc + "[/color]")

		# 列出该模组注册的命令
		var cmds: Array[String] = []
		for cmd_name in mod_commands.keys():
			if str(mod_commands[cmd_name].get("mod_id", "")) == mod_id:
				cmds.append(str(cmd_name))
		if not cmds.is_empty():
			lines.append("      [color=" + m + "]命令: " + ", ".join(cmds) + "[/color]")

		if not installed_at.is_empty():
			lines.append("      [color=" + m + "]安装: " + installed_at + "[/color]")

		if not is_active:
			lines.append("      [color=" + e + "]状态: 未激活（可能源文件缺失）[/color]")
		lines.append("")

	lines.append("[color=" + p + "]════════════════════════════════════════════[/color]")
	lines.append("[color=" + m + "]共 " + str(installed_mods.size()) + " 个模组  |  卸载: uninstall <名称或ID>[/color]")

	return "\n".join(lines) + "\n"

# ══════════════════════════════════════════
#  API 回调（由 ModAPI 调用）
# ══════════════════════════════════════════

## 注册命令
func _api_register_command(mod_id: String, cmd_name: String, description: String, handler: Callable, mode: String) -> bool:
	# 检查冲突
	if _check_builtin_command_conflict(cmd_name):
		push_warning("[PackageManager] 命令 '%s' 与内置命令冲突，注册失败" % cmd_name)
		return false

	# 如果已被其他模组注册
	if mod_commands.has(cmd_name):
		var existing_mod: String = str(mod_commands[cmd_name].get("mod_id", ""))
		if existing_mod != mod_id:
			push_warning("[PackageManager] 命令 '%s' 已被模组 '%s' 注册" % [cmd_name, existing_mod])
			return false

	mod_commands[cmd_name] = {
		"mod_id": mod_id,
		"description": description,
		"handler": handler,
		"mode": mode,
	}

	# 注册到 command_handler
	var cmd_callable: Callable = func(args: Array = []) -> void:
		if handler.is_valid():
			await handler.call(args)
	
	if cmd_handler:
		match mode:
			"desktop":
				cmd_handler.desktop_commands[cmd_name] = cmd_callable
			"disc":
				cmd_handler.disc_commands[cmd_name] = cmd_callable
			_:  # "global"
				cmd_handler.global_commands[cmd_name] = cmd_callable

	print("[PackageManager] 命令已注册: %s (模组: %s, 模式: %s)" % [cmd_name, mod_id, mode])
	return true

## 注销命令
func _api_unregister_command(mod_id: String, cmd_name: String) -> void:
	if not mod_commands.has(cmd_name):
		return
	if str(mod_commands[cmd_name].get("mod_id", "")) != mod_id:
		return  # 不能注销其他模组的命令

	var mode: String = str(mod_commands[cmd_name].get("mode", "global"))
	mod_commands.erase(cmd_name)

	if cmd_handler:
		match mode:
			"desktop":
				cmd_handler.desktop_commands.erase(cmd_name)
			"disc":
				cmd_handler.disc_commands.erase(cmd_name)
			_:
				cmd_handler.global_commands.erase(cmd_name)

## 保存模组数据
func _api_save_mod_data(mod_id: String, key: String, value: Variant) -> void:
	if not mod_data_store.has(mod_id):
		mod_data_store[mod_id] = {}
	mod_data_store[mod_id][key] = value
	_save_to_profile()

## 读取模组数据
func _api_load_mod_data(mod_id: String, key: String, default_value: Variant) -> Variant:
	if not mod_data_store.has(mod_id):
		return default_value
	return mod_data_store[mod_id].get(key, default_value)

## 设置输入捕获
func _api_set_input_capture(mod_id: String, handler: Callable) -> void:
	_input_capture = { "mod_id": mod_id, "handler": handler }

## 释放输入捕获
func _api_release_input_capture(mod_id: String) -> void:
	if str(_input_capture.get("mod_id", "")) == mod_id:
		_input_capture.clear()



# ══════════════════════════════════════════
#  ★ NEW: 钩子分发系统
# ══════════════════════════════════════════

## 分发钩子到所有活跃模组
## hook_name: ModBase 中的虚函数名，如 "_on_before_command"
## args: 参数数组
## 返回: 如果任一模组返回 true（用于 before 系列钩子），返回 true
func _dispatch_hook(hook_name: String, args: Array = []) -> bool:
	var blocked: bool = false
	for mod_id in active_mods.keys():
		var mod_instance: ModBase = active_mods[mod_id] as ModBase
		if mod_instance and mod_instance.has_method(hook_name):
			var result = mod_instance.callv(hook_name, args)
			if result is bool and result == true:
				blocked = true
	return blocked

## 分发命令执行前钩子
func dispatch_before_command(cmd: String, args: Array) -> bool:
	return _dispatch_hook("_on_before_command", [cmd, args])

## 分发命令执行后钩子
func dispatch_after_command(cmd: String, args: Array) -> void:
	_dispatch_hook("_on_after_command", [cmd, args])

## 分发目录切换钩子
func dispatch_directory_changed(old_path: String, new_path: String) -> void:
	_dispatch_hook("_on_directory_changed", [old_path, new_path])

## 分发文件打开前钩子
func dispatch_before_file_open(file_path: String) -> bool:
	return _dispatch_hook("_on_before_file_open", [file_path])

## 分发文件打开后钩子
func dispatch_after_file_open(file_path: String) -> void:
	_dispatch_hook("_on_after_file_open", [file_path])

## 分发磁盘加载钩子
func dispatch_disc_loaded(story_id: String, manifest: Dictionary) -> void:
	_dispatch_hook("_on_disc_loaded", [story_id, manifest])

## 分发磁盘弹出钩子
func dispatch_disc_ejected() -> void:
	_dispatch_hook("_on_disc_ejected", [])

## 分发模式切换钩子
func dispatch_mode_changed(is_desktop: bool) -> void:
	_dispatch_hook("_on_mode_changed", [is_desktop])

## 分发用户登录钩子
func dispatch_user_login(username: String) -> void:
	_dispatch_hook("_on_user_login", [username])

## 分发用户注销钩子
func dispatch_user_logout(username: String) -> void:
	_dispatch_hook("_on_user_logout", [username])

# ══════════════════════════════════════════
#  ★ NEW: 跨模组通信
# ══════════════════════════════════════════

## 向指定模组发送消息
func _dispatch_mod_message(from_mod_id: String, target_mod_id: String, data: Dictionary) -> bool:
	if not active_mods.has(target_mod_id):
		return false
	var target: ModBase = active_mods[target_mod_id] as ModBase
	if target and target.has_method("_on_mod_message"):
		target._on_mod_message(from_mod_id, data)
	return true

## 广播消息给所有活跃模组（除发送者自身）
func _broadcast_mod_message(from_mod_id: String, data: Dictionary) -> void:
	for mod_id in active_mods.keys():
		if mod_id == from_mod_id:
			continue
		var mod_instance: ModBase = active_mods[mod_id] as ModBase
		if mod_instance and mod_instance.has_method("_on_mod_message"):
			mod_instance._on_mod_message(from_mod_id, data)

# ══════════════════════════════════════════
#  ★ NEW: 事件总线
# ══════════════════════════════════════════

## 订阅事件
func _subscribe_event(mod_id: String, event_name: String, handler: Callable) -> void:
	if not _event_subscribers.has(event_name):
		_event_subscribers[event_name] = {}
	_event_subscribers[event_name][mod_id] = handler

## 取消订阅
func _unsubscribe_event(mod_id: String, event_name: String) -> void:
	if _event_subscribers.has(event_name):
		_event_subscribers[event_name].erase(mod_id)

## 发布事件
func _emit_event(event_name: String, data: Dictionary = {}) -> void:
	if not _event_subscribers.has(event_name):
		return
	var subscribers: Dictionary = _event_subscribers[event_name]
	for mod_id in subscribers.keys():
		var handler: Callable = subscribers[mod_id] as Callable
		if handler.is_valid():
			handler.call(data)

## 清除某模组的所有事件订阅
func _clear_event_subscriptions(mod_id: String) -> void:
	for event_name in _event_subscribers.keys():
		_event_subscribers[event_name].erase(mod_id)

# ══════════════════════════════════════════
#  ★ NEW: 模组 UI 容器管理
# ══════════════════════════════════════════

## 获取或创建模组专属 UI 容器
func _get_or_create_mod_container(mod_id: String) -> Control:
	# 检查已有的是否仍有效
	if _mod_containers.has(mod_id):
		var existing: Control = _mod_containers[mod_id] as Control
		if is_instance_valid(existing):
			return existing
		else:
			_mod_containers.erase(mod_id)
	# 创建新容器
	if main == null:
		return null
	var container := Control.new()
	container.name = "ModContainer_" + mod_id
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(container)
	_mod_containers[mod_id] = container
	print("[PackageManager] 已创建 UI 容器: %s" % mod_id)
	return container

## 销毁模组 UI 容器及所有子节点
func _destroy_mod_container(mod_id: String) -> void:
	if _mod_containers.has(mod_id):
		var container: Control = _mod_containers[mod_id] as Control
		if is_instance_valid(container):
			container.queue_free()
		_mod_containers.erase(mod_id)



# ══════════════════════════════════════════
#  GDScript 运行时编译
# ══════════════════════════════════════════

func _compile_and_instantiate(mod_id: String, pack_files: Dictionary, entry_script: String) -> ModBase:
	if not pack_files.has(entry_script):
		push_error("[PackageManager] 入口脚本不存在: %s" % entry_script)
		return null

	var source_code: String = (pack_files[entry_script] as PackedByteArray).get_string_from_utf8()
	if source_code.strip_edges().is_empty():
		push_error("[PackageManager] 入口脚本为空: %s" % entry_script)
		return null

	# 编译 GDScript
	var script := GDScript.new()
	script.source_code = source_code
	var err := script.reload()
	if err != OK:
		push_error("[PackageManager] 模组 %s 脚本编译失败 (错误码: %d)" % [mod_id, err])
		return null

	# 实例化
	var instance = script.new()
	if not (instance is ModBase):
		push_error("[PackageManager] 模组 %s 入口脚本必须继承 ModBase" % mod_id)
		return null

	var mod_instance: ModBase = instance as ModBase
	mod_instance.mod_id = mod_id
	mod_instance._pack_files = pack_files

	# 创建 API
	var api := ModAPI.new()
	api.setup(main, fs, T, tw, user_mgr, disc_mgr, cmd_handler, self, audio_mgr)
	api._mod_id = mod_id
	api._pack_files = pack_files
	mod_instance.api = api

	print("[PackageManager] 模组 %s 编译成功" % mod_id)
	return mod_instance

# ══════════════════════════════════════════
#  内部工具
# ══════════════════════════════════════════

func _shutdown_all_mods() -> void:
	for mod_id in active_mods.keys():
		var mod_instance: ModBase = active_mods[mod_id] as ModBase
		mod_instance._on_disable()
		_unregister_all_commands_for_mod(mod_id)
		_clear_event_subscriptions(mod_id)	  # ★ NEW
		_destroy_mod_container(mod_id)		   # ★ NEW
	active_mods.clear()
	mod_commands.clear()
	mod_pack_files.clear()
	hidden_package_files.clear()
	_process_mods.clear()
	_input_capture.clear()
	installed_mods.clear()
	mod_data_store.clear()
	_event_subscribers.clear()				   # ★ NEW


func _unregister_all_commands_for_mod(mod_id: String) -> void:
	var to_remove: Array[String] = []
	for cmd_name in mod_commands.keys():
		if str(mod_commands[cmd_name].get("mod_id", "")) == mod_id:
			to_remove.append(cmd_name)

	for cmd_name in to_remove:
		var mode: String = str(mod_commands[cmd_name].get("mode", "global"))
		mod_commands.erase(cmd_name)
		if cmd_handler:
			match mode:
				"desktop":
					cmd_handler.desktop_commands.erase(cmd_name)
				"disc":
					cmd_handler.disc_commands.erase(cmd_name)
				_:
					cmd_handler.global_commands.erase(cmd_name)

func _check_builtin_command_conflict(cmd_name: String) -> bool:
	if cmd_handler == null:
		return false
	cmd_name = cmd_name.to_lower()
	# 检查内置命令（不含模组注册的动态命令）
	var builtin_global: Array[String] = [
		"help", "clear", "cls", "exit", "quit", "logout", "scan",
		"load", "theme", "themes", "sound", "packages", "pkg",
		"install", "uninstall"
	]
	if cmd_name in builtin_global:
		return true
	var builtin_desktop: Array[String] = [
		"whoami", "profile", "passwd", "users", "deluser", "mail",
        "explore"
	]
	if cmd_name in builtin_desktop:
		return true
	var builtin_disc: Array[String] = [
		"ls", "dir", "cd", "back", "open", "read", "cat", "tree",
		"find", "search", "eject", "save", "status", "radio", "decode"
	]
	if cmd_name in builtin_disc:
		return true
	return false

func is_hidden_package(filename: String) -> bool:
	return hidden_package_files.has(filename)

func _resolve_mod_id(id_or_name: String) -> String:
	if installed_mods.has(id_or_name):
		return id_or_name
	var lower_input: String = id_or_name.to_lower()
	for mod_id in installed_mods.keys():
		if str(mod_id).to_lower() == lower_input:
			return mod_id
	for mod_id in installed_mods.keys():
		var meta: Dictionary = installed_mods[mod_id]
		if str(meta.get("title", "")).to_lower() == lower_input:
			return mod_id
	return ""

func _read_manifest_from_zip(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {}
	var result: Dictionary = {}
	var zip_files: PackedStringArray = reader.get_files()
	for f in zip_files:
		# 兼容顶层文件夹包裹：匹配任意深度的 manifest.json
		if f.get_file() == "manifest.json":
			var data: PackedByteArray = reader.read_file(f)
			var json := JSON.new()
			if json.parse(data.get_string_from_utf8()) == OK:
				if json.data is Dictionary:
					result = json.data
			break
	reader.close()
	return result

func _read_all_pack_files(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {}
	var result: Dictionary = {}
	var zip_files: PackedStringArray = reader.get_files()

	# 检测是否所有文件都在同一个顶层文件夹下
	var common_prefix: String = ""
	var has_common_prefix: bool = true

	for f in zip_files:
		if f.ends_with("/") and f.count("/") == 1:
			# 可能是顶层文件夹本身，如 "scp_tetris/"
			if common_prefix.is_empty():
				common_prefix = f
			elif common_prefix != f:
				has_common_prefix = false
				break
		elif f.contains("/"):
			var first_part: String = f.substr(0, f.find("/") + 1)
			if common_prefix.is_empty():
				common_prefix = first_part
			elif common_prefix != first_part:
				has_common_prefix = false
				break
		else:
			# 根目录文件，没有前缀
			has_common_prefix = false
			break

	if common_prefix.is_empty():
		has_common_prefix = false

	for f in zip_files:
		if f.ends_with("/"):
			continue  # 跳过目录条目
		var data: PackedByteArray = reader.read_file(f)
		var relative: String = f
		# 如果有公共前缀，剥离它
		if has_common_prefix and relative.begins_with(common_prefix):
			relative = relative.substr(common_prefix.length())
		if relative.is_empty():
			continue
		result[relative] = data

	reader.close()

	print("[PackageManager] 读取包文件 %d 个 (前缀剥离: %s)" % [result.size(), common_prefix if has_common_prefix else "无"])
	return result


func _find_package_path(filename: String) -> String:
	if filename.is_empty():
		return ""
	# 在标准 vdisc 目录查找
	var search_dirs: Array[String] = [
		"res://vdisc/",
		"user://vdisc/",
	]
	# 也检查 disc_mgr 已知的路径
	if disc_mgr:
		for story in disc_mgr.available_stories:
			if str(story.get("filename", "")) == filename:
				return str(story.get("path", ""))
	for dir_path in search_dirs:
		var full: String = dir_path + filename
		if FileAccess.file_exists(full):
			return full
	return ""

func _save_to_profile() -> void:
	if not user_mgr or not user_mgr.is_logged_in:
		return
	user_mgr.current_user["installed_packages"] = installed_mods.duplicate(true)
	user_mgr.current_user["mod_data_store"] = mod_data_store.duplicate(true)
	user_mgr._save_current_profile()

func _get_current_datetime() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]
