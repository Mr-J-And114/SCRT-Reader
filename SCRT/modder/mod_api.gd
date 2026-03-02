# ============================================================
# mod_api.gd - 模组安全 API（增强版）
# 提供给模组脚本的沙盒化系统接口
# ============================================================
class_name ModAPI
extends RefCounted

# ══════════════════════════════════════════
#  内部引用（模组不可直接访问）
# ══════════════════════════════════════════
var _main = null
var _fs: FileSystem = null
var _T = null
var _tw = null
var _user_mgr = null
var _disc_mgr = null
var _cmd_handler = null
var _pkg_mgr = null  # PackageManager
var _audio_mgr = null

## 当前模组 ID
var _mod_id: String = ""
## 模组包内文件缓存引用
var _pack_files: Dictionary = {}

func setup(p_main, p_fs, p_theme, p_tw, p_user_mgr, p_disc_mgr, p_cmd_handler, p_pkg_mgr, p_audio_mgr) -> void:
	_main = p_main
	_fs = p_fs
	_T = p_theme
	_tw = p_tw
	_user_mgr = p_user_mgr
	_disc_mgr = p_disc_mgr
	_cmd_handler = p_cmd_handler
	_pkg_mgr = p_pkg_mgr
	_audio_mgr = p_audio_mgr

# ══════════════════════════════════════════════════════════════
#  一、输出系统
# ══════════════════════════════════════════════════════════════

## 输出文本到终端（即时，支持 BBCode）
func output(text: String) -> void:
	if _main:
		_main.append_output(text, false)

## 打字机输出
func output_typed(text: String) -> void:
	if _main:
		_main.append_output(text, true)

## 获取主题颜色字典
func get_theme_colors() -> Dictionary:
	if _T == null:
		return {}
	return {
		"primary": str(_T.primary_hex),
		"muted": str(_T.muted_hex),
		"error": str(_T.error_hex),
		"warning": str(_T.warning_hex),
		"success": str(_T.success_hex),
	}

## 便捷：带颜色的输出
func output_colored(text: String, color_key: String = "primary") -> void:
	var colors: Dictionary = get_theme_colors()
	var hex: String = str(colors.get(color_key, colors.get("primary", "#ffffff")))
	output("[color=" + hex + "]" + text + "[/color]\n")

## 清屏
func clear_screen() -> void:
	if _main and _main.output_text:
		_main.output_text.text = ""

## ★ NEW: 输出不带 beep 音效
func output_silent(text: String) -> void:
	if _main:
		_main.append_output(text, false, false)

## ★ NEW: 等待打字机完成
func wait_for_typewriter() -> void:
	if _main and _tw:
		while _tw.is_typing:
			await _main.get_tree().process_frame

## ★ NEW: 构建装饰框
func build_box(lines_arr: Array[String], color_hex: String = "") -> String:
	if color_hex.is_empty():
		var colors: Dictionary = get_theme_colors()
		color_hex = str(colors.get("primary", "#ffffff"))
	if _fs:
		return _fs.build_box(lines_arr, color_hex)
	return "\n".join(lines_arr)

## ★ NEW: 获取终端宽度估算（字符数）
func get_terminal_width() -> int:
	return 60

# ══════════════════════════════════════════════════════════════
#  二、命令注册
# ══════════════════════════════════════════════════════════════

## 注册一个命令
## name: 命令名（小写）
## description: 命令描述（显示在 help 中）
## handler: Callable，签名为 func(args: Array) -> void
## mode: "global"(两种模式都可用) / "desktop"(仅桌面) / "disc"(仅磁盘)
func register_command(cmd_name: String, description: String, handler: Callable, mode: String = "global") -> bool:
	cmd_name = cmd_name.to_lower().strip_edges()
	if cmd_name.is_empty():
		return false
	if _pkg_mgr == null:
		return false
	return _pkg_mgr._api_register_command(_mod_id, cmd_name, description, handler, mode)

## 注销一个命令
func unregister_command(cmd_name: String) -> void:
	cmd_name = cmd_name.to_lower().strip_edges()
	if _pkg_mgr:
		_pkg_mgr._api_unregister_command(_mod_id, cmd_name)

## ★ NEW: 执行一个命令（模拟用户输入）
func execute_command(raw_command: String) -> void:
	if _main and _main.has_method("_run_command"):
		_main._run_command(raw_command)

# ══════════════════════════════════════════════════════════════
#  三、系统状态查询
# ══════════════════════════════════════════════════════════════

## 当前文件系统路径（磁盘模式）
func get_current_path() -> String:
	if _main:
		return _main.current_path
	return "/"

## 当前用户名
func get_username() -> String:
	if _user_mgr and _user_mgr.is_logged_in:
		return _user_mgr.get_username()
	return ""

## 当前用户角色
func get_user_role() -> String:
	if _user_mgr and _user_mgr.is_logged_in:
		return _user_mgr.get_role()
	return ""

## 是否桌面模式
func is_desktop_mode() -> bool:
	if _main:
		return _main._desktop_mode
	return true

## 当前安全等级（磁盘模式）
func get_clearance() -> int:
	if _fs:
		return _fs.player_clearance
	return 0

## ★ NEW: 获取当前加载的故事 ID
func get_story_id() -> String:
	if _main:
		return _main.story_id
	return ""

## ★ NEW: 获取当前故事 manifest
func get_story_manifest() -> Dictionary:
	if _main:
		return _main.story_manifest.duplicate(true)
	return {}

## ★ NEW: 获取已读文件列表
func get_read_files() -> Array[String]:
	if _main:
		return _main.read_files.duplicate()
	return []

## ★ NEW: 获取已访问路径列表
func get_visited_paths() -> Array[String]:
	if _main:
		return _main.visited_paths.duplicate()
	return []

## ★ NEW: 获取已解锁密码列表
func get_unlocked_passwords() -> Array[String]:
	if _main:
		return _main.unlocked_passwords.duplicate()
	return []

## ★ NEW: 获取命令是否正在执行
func is_command_running() -> bool:
	if _main:
		return _main._command_running
	return false

# ══════════════════════════════════════════════════════════════
#  四、文件系统
# ══════════════════════════════════════════════════════════════

## 获取当前目录的子项列表
func get_fs_children(path: String = "") -> Array[String]:
	if _fs == null:
		return []
	if path.is_empty():
		path = get_current_path()
	var node = _fs.get_node_at_path(path)
	if node == null:
		return []
	var result: Array[String] = []
	if node.has("children") and node.children is Dictionary:
		for key in node.children.keys():
			result.append(str(key))
	return result

## 读取文件系统中的文件内容（磁盘模式）
func read_fs_file(path: String) -> String:
	if _fs == null:
		return ""
	var node = _fs.get_node_at_path(_fs.normalize_path(path))
	if node == null:
		return ""
	if "content" in node:
		return str(node.content)
	return ""

## ★ NEW: 获取文件系统节点信息
func get_fs_node(path: String) -> Dictionary:
	if _fs == null:
		return {}
	var node = _fs.get_node_at_path(_fs.normalize_path(path))
	if node == null:
		return {}
	var result: Dictionary = {}
	if "name" in node:
		result["name"] = str(node.name)
	if "type" in node:
		result["type"] = str(node.type)
	if "clearance" in node:
		result["clearance"] = int(node.clearance)
	if "locked" in node:
		result["locked"] = bool(node.locked)
	if "content" in node:
		result["has_content"] = true
	return result

## ★ NEW: 检查路径是否存在
func fs_path_exists(path: String) -> bool:
	if _fs == null:
		return false
	return _fs.get_node_at_path(_fs.normalize_path(path)) != null

## ★ NEW: 获取文件的二进制数据
func get_fs_binary(path: String) -> PackedByteArray:
	if _fs == null:
		return PackedByteArray()
	return _fs.get_binary_data(_fs.normalize_path(path))

## ★ NEW: 规范化路径
func normalize_path(path: String) -> String:
	if _fs:
		return _fs.normalize_path(path)
	return path

## ★ NEW: 路径拼接
func join_path(base: String, relative: String) -> String:
	if _fs:
		return _fs.join_path(base, relative)
	return base + "/" + relative

## ★ NEW: 修改当前路径（模拟 cd 命令）
func set_current_path(path: String) -> bool:
	if _main == null or _fs == null:
		return false
	var normalized: String = _fs.normalize_path(path)
	var node = _fs.get_node_at_path(normalized)
	if node == null:
		return false
	var old_path: String = _main.current_path
	_main.current_path = normalized
	_main._update_status_bar()
	_main.update_ambient_sound()
	# 触发钩子
	if _pkg_mgr:
		_pkg_mgr._dispatch_hook("_on_directory_changed", [old_path, normalized])
	return true

# ══════════════════════════════════════════════════════════════
#  五、模组包内文件读取
# ══════════════════════════════════════════════════════════════

## 读取模组包内的文本文件
func read_mod_file(relative_path: String) -> String:
	if _pack_files.has(relative_path):
		var data: PackedByteArray = _pack_files[relative_path]
		return data.get_string_from_utf8()
	return ""

## 读取模组包内的二进制文件
func read_mod_binary(relative_path: String) -> PackedByteArray:
	if _pack_files.has(relative_path):
		return _pack_files[relative_path]
	return PackedByteArray()

## 列出模组包内的所有文件
func list_mod_files() -> Array[String]:
	var result: Array[String] = []
	for key in _pack_files.keys():
		result.append(str(key))
	return result

# ══════════════════════════════════════════════════════════════
#  六、模组持久化数据（跨会话存储）
# ══════════════════════════════════════════════════════════════

## 保存模组自定义数据
func save_data(key: String, value: Variant) -> void:
	if _pkg_mgr:
		_pkg_mgr._api_save_mod_data(_mod_id, key, value)

## 读取模组自定义数据
func load_data(key: String, default_value: Variant = null) -> Variant:
	if _pkg_mgr:
		return _pkg_mgr._api_load_mod_data(_mod_id, key, default_value)
	return default_value

## ★ NEW: 删除模组数据中的某个 key
func delete_data(key: String) -> void:
	if _pkg_mgr and _pkg_mgr.mod_data_store.has(_mod_id):
		_pkg_mgr.mod_data_store[_mod_id].erase(key)
		_pkg_mgr._save_to_profile()

## ★ NEW: 获取模组所有数据的 key 列表
func get_data_keys() -> Array[String]:
	var result: Array[String] = []
	if _pkg_mgr and _pkg_mgr.mod_data_store.has(_mod_id):
		for key in _pkg_mgr.mod_data_store[_mod_id].keys():
			result.append(str(key))
	return result

## ★ NEW: 清除模组所有持久化数据
func clear_all_data() -> void:
	if _pkg_mgr:
		_pkg_mgr.mod_data_store.erase(_mod_id)
		_pkg_mgr._save_to_profile()

# ══════════════════════════════════════════════════════════════
#  七、UI 工具
# ══════════════════════════════════════════════════════════════

## 显示进度条动画
func show_progress_bar(duration_ms: int = 500) -> void:
	if _tw:
		await _tw.show_progress_bar(duration_ms)

## 播放 beep 音效
func play_beep() -> void:
	if _audio_mgr and _audio_mgr.has_method("play_beep"):
		_audio_mgr.play_beep()

# ══════════════════════════════════════════════════════════════
#  八、音频系统
# ══════════════════════════════════════════════════════════════

## 从模组包内加载并播放音频
func play_mod_audio(relative_path: String) -> void:
	var data: PackedByteArray = read_mod_binary(relative_path)
	if data.is_empty():
		return
	if _audio_mgr and _audio_mgr.has_method("load_audio_from_bytes"):
		var stream: AudioStream = _audio_mgr.load_audio_from_bytes(relative_path, data)
		if stream and _audio_mgr.has_method("play_sfx"):
			_audio_mgr.play_sfx(stream)

## ★ NEW: 播放媒体音频（带进度条的长音频）
func play_mod_media(relative_path: String) -> void:
	var data: PackedByteArray = read_mod_binary(relative_path)
	if data.is_empty():
		return
	if _audio_mgr and _audio_mgr.has_method("load_audio_from_bytes"):
		var stream: AudioStream = _audio_mgr.load_audio_from_bytes(relative_path, data)
		if stream and _audio_mgr.has_method("play_media"):
			_audio_mgr.play_media(stream)

## ★ NEW: 停止媒体播放
func stop_media() -> void:
	if _audio_mgr and _audio_mgr.has_method("stop_media"):
		_audio_mgr.stop_media()

## ★ NEW: 暂停/恢复媒体
func pause_media() -> void:
	if _audio_mgr and _audio_mgr.has_method("pause_media"):
		_audio_mgr.pause_media()

## ★ NEW: 播放环境音（带循环）
func play_ambient(stream_id: String, relative_path: String, volume_db: float = -10.0) -> void:
	var data: PackedByteArray = read_mod_binary(relative_path)
	if data.is_empty():
		return
	if _audio_mgr and _audio_mgr.has_method("load_audio_from_bytes"):
		var stream: AudioStream = _audio_mgr.load_audio_from_bytes(relative_path, data)
		if stream and _audio_mgr.has_method("play_ambient"):
			_audio_mgr.play_ambient(stream_id, stream, volume_db)

## ★ NEW: 停止环境音
func stop_ambient() -> void:
	if _audio_mgr and _audio_mgr.has_method("stop_ambient"):
		_audio_mgr.stop_ambient()

## ★ NEW: 获取媒体播放位置
func get_media_position() -> float:
	if _audio_mgr and _audio_mgr.has_method("get_media_playback_position"):
		return _audio_mgr.get_media_playback_position()
	return 0.0

## ★ NEW: 获取媒体总时长
func get_media_length() -> float:
	if _audio_mgr and _audio_mgr.has_method("get_media_length"):
		return _audio_mgr.get_media_length()
	return 0.0

## ★ NEW: 媒体是否正在播放
func is_media_playing() -> bool:
	if _audio_mgr and _audio_mgr.has_method("is_media_playing"):
		return _audio_mgr.is_media_playing()
	return false

# ══════════════════════════════════════════════════════════════
#  九、视觉效果系统
# ══════════════════════════════════════════════════════════════

## 触发故障效果
func trigger_glitch(intensity: float = 0.5, duration: float = 1.0, preset: String = "custom") -> void:
	if _main and _main.has_method("trigger_glitch"):
		_main.trigger_glitch(intensity, duration, preset)

## 触发屏幕抖动
func trigger_shake(intensity: float = 0.01, duration: float = 0.5) -> void:
	if _main and _main.has_method("trigger_shake"):
		_main.trigger_shake(intensity, duration)

## ★ NEW: 触发撕裂效果
func trigger_tear(strength: float = 0.08, duration: float = 0.5) -> void:
	if _main and _main.has_method("trigger_tear"):
		_main.trigger_tear(strength, duration)

## ★ NEW: 触发噪声爆发
func trigger_noise_burst(intensity: float = 0.8, duration: float = 0.3) -> void:
	if _main and _main.has_method("trigger_noise_burst"):
		_main.trigger_noise_burst(intensity, duration)

## ★ NEW: 触发黑屏效果
func trigger_screen_off(duration: float = 2.0) -> void:
	if _main and _main.has_method("trigger_screen_off"):
		_main.trigger_screen_off(duration)

## ★ NEW: 触发重启效果
func trigger_reboot() -> void:
	if _main and _main.has_method("trigger_reboot"):
		_main.trigger_reboot()

## ★ NEW: 触发预设效果（unease/disturb/jumpscare/crash）
func trigger_preset_effect(preset_name: String, duration: float = 2.0) -> void:
	if _main and _main.has_method("trigger_preset_effect"):
		_main.trigger_preset_effect(preset_name, duration)

## ★ NEW: 触发命名效果（effect_sys 中定义的）
func trigger_named_effect(effect_id: String) -> void:
	if _main and _main.has_method("trigger_effect"):
		_main.trigger_effect(effect_id)

## ★ NEW: 直接控制 CRT shader 参数
func set_crt_parameter(param_name: String, value: Variant) -> void:
	if _main and _main.crt_shader:
		if _main.crt_shader.has_method("set_parameter"):
			_main.crt_shader.set_parameter(param_name, value)
		elif _main.crt_shader.has_method("set"):
			_main.crt_shader.set(param_name, value)

## ★ NEW: 获取 CRT shader 参数
func get_crt_parameter(param_name: String, default_value: Variant = null) -> Variant:
	if _main and _main.crt_shader:
		if _main.crt_shader.has_method("get_parameter"):
			return _main.crt_shader.get_parameter(param_name)
		elif param_name in _main.crt_shader:
			return _main.crt_shader.get(param_name)
	return default_value

# ══════════════════════════════════════════════════════════════
#  十、状态栏控制
# ══════════════════════════════════════════════════════════════

## 更新状态栏文字（临时覆盖）
func set_status_text(text: String) -> void:
	if _main and _main.path_label:
		_main.path_label.text = text

## 恢复默认状态栏
func restore_status_bar() -> void:
	if _main and _main.has_method("_update_status_bar"):
		_main._update_status_bar()

## ★ NEW: 设置邮件图标文字
func set_mail_icon_text(text: String) -> void:
	if _main and _main.mail_icon:
		_main.mail_icon.text = text

# ══════════════════════════════════════════════════════════════
#  十一、输入拦截
# ══════════════════════════════════════════════════════════════

## 请求拦截所有键盘输入（进入交互模式）
func request_input_capture(handler: Callable) -> void:
	if _pkg_mgr:
		_pkg_mgr._api_set_input_capture(_mod_id, handler)

## 释放输入拦截
func release_input_capture() -> void:
	if _pkg_mgr:
		_pkg_mgr._api_release_input_capture(_mod_id)

## 设置输入框是否可编辑
func set_input_editable(editable: bool) -> void:
	if _main and _main.input_field:
		_main.input_field.editable = editable

## 获取输入框引用（谨慎使用）
func get_input_field() -> LineEdit:
	if _main:
		return _main.input_field
	return null

## 获取输出区域引用（谨慎使用）
func get_output_text() -> RichTextLabel:
	if _main:
		return _main.output_text
	return null

## ★ NEW: 设置输入框密码模式
func set_input_secret(secret: bool) -> void:
	if _main and _main.input_field:
		_main.input_field.secret = secret

## ★ NEW: 获取输入框当前文本
func get_input_text() -> String:
	if _main and _main.input_field:
		return _main.input_field.text
	return ""

## ★ NEW: 设置输入框文本
func set_input_text(text: String) -> void:
	if _main and _main.input_field:
		_main.input_field.text = text
		_main.input_field.caret_column = text.length()

## ★ NEW: 聚焦输入框
func focus_input() -> void:
	if _main and _main.input_field:
		_main.input_field.grab_focus()

# ══════════════════════════════════════════════════════════════
#  十二、★ NEW: 定时器系统
# ══════════════════════════════════════════════════════════════

## 创建一个一次性定时器，到时后调用 callback
## 返回 Timer 节点引用（可用于 cancel_timer）
func create_timer(seconds: float, callback: Callable) -> Timer:
	if _main == null:
		return null
	var timer := Timer.new()
	timer.wait_time = seconds
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func():
		if callback.is_valid():
			callback.call()
		timer.queue_free()
	)
	_main.add_child(timer)
	return timer

## 创建一个循环定时器
func create_interval(seconds: float, callback: Callable) -> Timer:
	if _main == null:
		return null
	var timer := Timer.new()
	timer.wait_time = seconds
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(func():
		if callback.is_valid():
			callback.call()
	)
	_main.add_child(timer)
	return timer

## 取消定时器
func cancel_timer(timer: Timer) -> void:
	if timer and is_instance_valid(timer):
		timer.stop()
		timer.queue_free()

## ★ NEW: 等待指定秒数
func wait(seconds: float) -> void:
	if _main:
		await _main.get_tree().create_timer(seconds).timeout

## ★ NEW: 等待一帧
func wait_frame() -> void:
	if _main:
		await _main.get_tree().process_frame

# ══════════════════════════════════════════════════════════════
#  十三、★ NEW: 场景树安全访问（模组 UI 容器）
# ══════════════════════════════════════════════════════════════

## 获取模组专属的 UI 容器节点
## 首次调用时自动创建，模组卸载时自动销毁
func get_mod_container() -> Control:
	if _pkg_mgr == null or _main == null:
		return null
	return _pkg_mgr._get_or_create_mod_container(_mod_id)

## 向模组容器添加子节点
func add_ui_node(node: Control) -> void:
	var container: Control = get_mod_container()
	if container:
		container.add_child(node)

## 移除模组容器中的子节点
func remove_ui_node(node: Control) -> void:
	if node and is_instance_valid(node) and node.get_parent():
		node.get_parent().remove_child(node)
		node.queue_free()

## 清空模组容器中的所有子节点
func clear_ui_nodes() -> void:
	var container: Control = get_mod_container()
	if container:
		for child in container.get_children():
			child.queue_free()

## ★ NEW: 创建一个全屏覆盖层（模态弹窗用）
func create_overlay(color: Color = Color(0, 0, 0, 0.8)) -> Panel:
	var overlay := Panel.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	overlay.add_theme_stylebox_override("panel", style)
	add_ui_node(overlay)
	return overlay

## ★ NEW: 创建 RichTextLabel
func create_rich_text_label() -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.scroll_following = true
	rtl.selection_enabled = true
	return rtl

## ★ NEW: 获取主场景树引用
func get_scene_tree() -> SceneTree:
	if _main:
		return _main.get_tree()
	return null

## ★ NEW: 获取视口大小
func get_viewport_size() -> Vector2:
	if _main:
		return _main.get_viewport_rect().size
	return Vector2(1280, 720)

# ══════════════════════════════════════════════════════════════
#  十四、★ NEW: 事件系统（跨模组通信 + 全局事件）
# ══════════════════════════════════════════════════════════════

## 向指定模组发送消息
func send_mod_message(target_mod_id: String, data: Dictionary) -> bool:
	if _pkg_mgr == null:
		return false
	return _pkg_mgr._dispatch_mod_message(_mod_id, target_mod_id, data)

## 广播消息给所有模组
func broadcast_message(data: Dictionary) -> void:
	if _pkg_mgr:
		_pkg_mgr._broadcast_mod_message(_mod_id, data)

## 订阅全局事件（由 PackageManager 内部事件总线分发）
func subscribe_event(event_name: String, handler: Callable) -> void:
	if _pkg_mgr:
		_pkg_mgr._subscribe_event(_mod_id, event_name, handler)

## 取消订阅
func unsubscribe_event(event_name: String) -> void:
	if _pkg_mgr:
		_pkg_mgr._unsubscribe_event(_mod_id, event_name)

## 发布全局事件
func emit_event(event_name: String, data: Dictionary = {}) -> void:
	if _pkg_mgr:
		_pkg_mgr._emit_event(event_name, data)

# ══════════════════════════════════════════════════════════════
#  十五、★ NEW: 主题系统
# ══════════════════════════════════════════════════════════════

## 获取当前主题名称
func get_current_theme_name() -> String:
	if _T and "name" in _T:
		return str(_T.name)
	return ""

## 获取主题的 Color 对象（非 hex 字符串）
func get_theme_color(key: String) -> Color:
	if _T == null:
		return Color.WHITE
	match key:
		"primary":
			return _T.primary if "primary" in _T else Color.WHITE
		"muted":
			return _T.muted if "muted" in _T else Color.GRAY
		"error":
			return _T.error if "error" in _T else Color.RED
		"warning":
			return _T.warning if "warning" in _T else Color.YELLOW
		"success":
			return _T.success if "success" in _T else Color.GREEN
		"background":
			return _T.background if "background" in _T else Color.BLACK
	return Color.WHITE

# ══════════════════════════════════════════════════════════════
#  十六、★ NEW: 磁盘系统
# ══════════════════════════════════════════════════════════════

## 获取可用磁盘列表
func get_available_discs() -> Array[Dictionary]:
	if _disc_mgr == null:
		return []
	var result: Array[Dictionary] = []
	for story in _disc_mgr.available_stories:
		result.append({
			"title": str(story.get("title", "")),
			"filename": str(story.get("filename", "")),
			"author": str(story.get("author", "")),
			"description": str(story.get("description", "")),
			"is_package": story.get("is_package", false),
		})
	return result

## 获取当前加载的磁盘索引
func get_current_disc_index() -> int:
	if _main:
		return _main.current_story_index
	return -1

## 是否有磁盘已加载
func is_disc_loaded() -> bool:
	if _main:
		return _main.current_story_index >= 0 and not _main._desktop_mode
	return false

# ══════════════════════════════════════════════════════════════
#  十七、★ NEW: 用户系统（安全的只读+有限写入）
# ══════════════════════════════════════════════════════════════

## 是否已登录
func is_logged_in() -> bool:
	if _user_mgr:
		return _user_mgr.is_logged_in
	return false

## 获取当前用户 profile（只读副本）
func get_user_profile() -> Dictionary:
	if _user_mgr and _user_mgr.is_logged_in and _user_mgr.current_user is Dictionary:
		# 返回安全副本，排除密码等敏感字段
		var profile: Dictionary = _user_mgr.current_user.duplicate(true)
		profile.erase("password_hash")
		profile.erase("salt")
		return profile
	return {}

## 获取用户命令统计数
func get_command_count() -> int:
	if _user_mgr and _user_mgr.is_logged_in:
		return int(_user_mgr.current_user.get("command_count", 0))
	return 0

## 获取所有用户名列表
func get_all_usernames() -> Array[String]:
	if _user_mgr and _user_mgr.has_method("get_all_users"):
		return _user_mgr.get_all_users()
	return []

# ══════════════════════════════════════════════════════════════
#  十八、★ NEW: 邮件系统
# ══════════════════════════════════════════════════════════════

## 发送一封邮件到当前用户收件箱
func send_mail(from_name: String, subject: String, body: String, priority: String = "normal") -> bool:
	if _main == null or _main.mail_sys == null:
		return false
	if not _main.mail_sys.has_method("add_mail_from_mod"):
		# 降级：直接操作收件箱数组
		return _send_mail_fallback(from_name, subject, body, priority)
	return _main.mail_sys.add_mail_from_mod(_mod_id, from_name, subject, body, priority)

func _send_mail_fallback(from_name: String, subject: String, body: String, priority: String) -> bool:
	if _main == null or _main.mail_sys == null:
		return false
	var mail_entry: Dictionary = {
		"from": from_name,
		"subject": subject,
		"body": body,
		"priority": priority,
		"timestamp": Time.get_datetime_string_from_system(),
		"read": false,
		"source_mod": _mod_id,
	}
	if "inbox" in _main.mail_sys:
		_main.mail_sys.inbox.append(mail_entry)
		if "has_new_mail" in _main:
			_main.has_new_mail = true
		return true
	return false

## 获取当前收件箱邮件数量
func get_mail_count() -> int:
	if _main and _main.mail_sys and "inbox" in _main.mail_sys:
		return _main.mail_sys.inbox.size()
	return 0

# ══════════════════════════════════════════════════════════════
#  十九、★ NEW: 背景与 Shader 控制
# ══════════════════════════════════════════════════════════════

## 设置背景 shader uniform
func set_background_shader(uniform_name: String, value: float) -> void:
	if _main and _main.has_method("_set_background_shader_value"):
		_main._set_background_shader_value(uniform_name, value)

## 设置 logo shader uniform
func set_logo_shader(uniform_name: String, value: float) -> void:
	if _main and _main.has_method("_set_logo_shader_value"):
		_main._set_logo_shader_value(uniform_name, value)

## Tween 渐变背景 shader
func tween_background_shader(uniform_name: String, from: float, to: float, duration: float) -> void:
	if _main and _main.has_method("_tween_background_shader"):
		_main._tween_background_shader(uniform_name, from, to, duration)

## Tween 渐变 logo shader
func tween_logo_shader(uniform_name: String, from: float, to: float, duration: float) -> void:
	if _main and _main.has_method("_tween_logo_shader"):
		_main._tween_logo_shader(uniform_name, from, to, duration)

# ══════════════════════════════════════════════════════════════
#  二十、★ NEW: UI 框架样式
# ══════════════════════════════════════════════════════════════

## 隐藏/显示状态栏
func set_status_bar_visible(visible: bool) -> void:
	if _main and _main.status_frame:
		_main.status_frame.visible = visible

## 隐藏/显示输入框
func set_input_frame_visible(visible: bool) -> void:
	if _main and _main.input_frame:
		_main.input_frame.visible = visible

## 隐藏/显示输入框 + 状态栏（全屏模式）
func set_fullscreen_mode(enabled: bool) -> void:
	set_status_bar_visible(not enabled)
	set_input_frame_visible(not enabled)

## 获取 ScrollContainer（滚动控制）
func get_scroll_container() -> ScrollContainer:
	if _main:
		return _main.scroll_container
	return null

## 请求滚动到底部
func request_scroll() -> void:
	if _main and _main.has_method("_request_scroll"):
		_main._request_scroll()

# ══════════════════════════════════════════════════════════════
#  二十一、★ NEW: 其他模组查询
# ══════════════════════════════════════════════════════════════

## 获取所有已安装模组列表
func get_installed_mods() -> Array[Dictionary]:
	if _pkg_mgr == null:
		return []
	var result: Array[Dictionary] = []
	for mod_id in _pkg_mgr.installed_mods.keys():
		var meta: Dictionary = _pkg_mgr.installed_mods[mod_id].duplicate()
		meta.erase("_source_path")  # 安全：不暴露文件路径
		meta["is_active"] = _pkg_mgr.active_mods.has(mod_id)
		result.append(meta)
	return result

## 检查某个模组是否已安装且激活
func is_mod_active(mod_id: String) -> bool:
	if _pkg_mgr:
		return _pkg_mgr.active_mods.has(mod_id)
	return false

# ══════════════════════════════════════════════════════════════
#  二十二、★ NEW: 操作音效
# ══════════════════════════════════════════════════════════════

## 播放按键音
func play_keystroke() -> void:
	if _main and _main.ui_sound:
		_main.ui_sound.play_keystroke()

## 播放点击音
func play_click() -> void:
	if _main and _main.ui_sound:
		_main.ui_sound.play_click()

## 播放退格音
func play_backspace() -> void:
	if _main and _main.ui_sound:
		_main.ui_sound.play_backspace()

# ══════════════════════════════════════════════════════════════
#  二十三、★ NEW: Tween 动画辅助
# ══════════════════════════════════════════════════════════════

## 创建一个 Tween 实例
func create_tween() -> Tween:
	if _main:
		return _main.create_tween()
	return null


# ══════════════════════════════════════════════════════════════
#  二十四、★ NEW: 通讯系统
# ══════════════════════════════════════════════════════════════

## 触发一段对话
func comm_trigger(dialogue_id: String) -> bool:
	if _main and _main.comm_mgr:
		return _main.comm_mgr.trigger_dialogue(dialogue_id)
	return false

## 停止当前对话
func comm_stop() -> void:
	if _main and _main.comm_mgr:
		_main.comm_mgr.stop_dialogue()

## 是否有对话在播放
func comm_is_active() -> bool:
	if _main and _main.comm_mgr:
		return _main.comm_mgr.is_dialogue_active()
	return false

## 注册自定义角色
func comm_register_character(char_id: String, config: Dictionary) -> bool:
	if _main and _main.comm_mgr:
		return _main.comm_mgr.register_mod_character(char_id, config)
	return false

## 注册自定义对话
func comm_register_dialogue(dialogue_id: String, dialogue_data: Dictionary) -> bool:
	if _main and _main.comm_mgr:
		return _main.comm_mgr.register_mod_dialogue(dialogue_id, dialogue_data)
	return false

## 注销角色
func comm_unregister_character(char_id: String) -> void:
	if _main and _main.comm_mgr:
		_main.comm_mgr.unregister_mod_character(char_id)

## 注销对话
func comm_unregister_dialogue(dialogue_id: String) -> void:
	if _main and _main.comm_mgr:
		_main.comm_mgr.unregister_mod_dialogue(dialogue_id)

## 获取已注册角色列表
func comm_get_characters() -> Array[String]:
	if _main and _main.comm_mgr:
		return _main.comm_mgr.get_character_ids()
	return []

## 获取已注册对话列表
func comm_get_dialogues() -> Array[String]:
	if _main and _main.comm_mgr:
		return _main.comm_mgr.get_dialogue_ids()
	return []

## 设置默认角色头像（单张纹理）
func comm_set_default_portrait(texture: ImageTexture) -> void:
	if _main and _main.comm_mgr:
		_main.comm_mgr.set_default_portrait(texture)
