# ============================================================
# loading_screen.gd — 自定义磁盘载入画面系统
#
# 与 boot_sequence.gd 采用相同的关键帧时间轴引擎，
# 专用于故事包加载时的过渡动画。
#
# ── 配置来源（优先级从高到低）──
#   1. manifest.json 的 "loading_screen" 字段（故事包作者定义）
#   2. 内置默认载入画面
#
# ── manifest.json 配置示例 ──
# {
#   "loading_screen": {
#     "skippable": true,
#     "audio": "/audio/loading_theme.ogg",
#     "audio_volume": 0.6,
#     "total_duration": 8.0,
#     "keyframes": [
#       { "time": 0.0, "action": "clear" },
#       { "time": 0.0, "action": "text", "params": {
#           "content": "INSERTING VIRTUAL DISC...", "color": "muted" } },
#       { "time": 0.5, "action": "glitch", "params": {
#           "intensity": 0.2, "duration": 0.3 } },
#       { "time": 1.0, "action": "disc_title" },
#       { "time": 1.5, "action": "disc_info" },
#       { "time": 2.0, "action": "separator" },
#       { "time": 2.5, "action": "text", "params": {
#           "content": "LOADING FILE SYSTEM...", "color": "muted" } },
#       { "time": 3.0, "action": "progress_bar", "params": {
#           "duration": 4.0 } },
#       { "time": 7.0, "action": "text", "params": {
#           "content": "READY.", "color": "success" } },
#       { "time": 7.5, "action": "clear" },
#       { "time": 8.0, "action": "complete" }
#     ]
#   }
# }
#
# ── 支持的关键帧动作 ──
#
#   === 文字输出 ===
#   text          终端输出文字     params: content, color(主题色名)
#   text_center   居中文字         params: content, color
#   disc_title    显示磁盘标题     params: color(可选)
#   disc_info     显示作者/版本    params: color(可选)
#   separator     输出分隔线       params: char(可选,默认"═"), width(可选), color
#   ascii_art     输出 ASCII 艺术  params: content, color
#
#   === 视觉效果 ===
#   glitch        故障效果         params: intensity, duration
#   scanlines     扫描线           params: intensity
#   screen_flash  屏幕闪白         params: duration
#
#   === 音频 ===
#   beep          蜂鸣音
#   sound         播放音效         params: path(虚拟FS路径)
#   audio_play    播放载入音乐     (使用顶层 audio 字段)
#
#   === 流程控制 ===
#   clear         清屏
#   wait          纯等待(占位)
#   progress_bar  进度条           params: duration, label
#   complete      结束载入画面
# ============================================================
class_name LoadingScreen
extends RefCounted

# ── 引用 ──
var main = null
var fs: FileSystem = null
var T = null
var audio_manager = null
var crt_shader = null
var effect_settings = null

# ── 状态 ──
var _active: bool = false
var _elapsed: float = 0.0
var _total_duration: float = 8.0
var _keyframes: Array[Dictionary] = []
var _next_kf_index: int = 0
var _completed: bool = false
var _skippable: bool = true

# ── 音频 ──
var _audio_player: AudioStreamPlayer = null
var _audio_started: bool = false
var _audio_base_volume_db: float = -6.0
var _audio_path: String = ""  # 顶层 audio 字段路径

# ── 进度条 ──
var _progress_bar_active: bool = false
var _progress_bar_start: float = 0.0
var _progress_bar_duration: float = 4.0
var _progress_bar_last_percent: int = -1
var _progress_bar_line_added: bool = false          # 是否已输出过进度条行
var _progress_bar_expected_para_count: int = 0      # 上次写入后的段落数（用于安全替换）

# ── 磁盘信息（由 disc_manager 在播放前注入） ──
var _disc_title: String = ""
var _disc_author: String = ""
var _disc_version: String = ""
var _disc_description: String = ""
var _disc_id: String = ""

# ── 信号 ──
signal loading_completed

# ============================================================
# 初始化
# ============================================================
func setup(p_main, p_fs: FileSystem, p_theme, p_audio_manager = null, p_crt_shader = null) -> void:
	main = p_main
	fs = p_fs
	T = p_theme
	audio_manager = p_audio_manager
	crt_shader = p_crt_shader
	effect_settings = main.effect_settings if main and "effect_settings" in main else null
	# 创建音频播放器
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	main.add_child.call_deferred(_audio_player)

# ============================================================
# 注入磁盘信息（由 disc_manager 调用）
# ============================================================
func set_disc_info(info: Dictionary) -> void:
	_disc_title = str(info.get("title", "Unknown Disc"))
	_disc_author = str(info.get("author", "Unknown"))
	_disc_version = str(info.get("version", ""))
	_disc_description = str(info.get("description", ""))
	_disc_id = str(info.get("id", ""))

# ============================================================
# 启动载入画面
# ============================================================
func play(config: Dictionary) -> void:
	if _active:
		return
	T = ThemeManager.current
	_active = true
	_elapsed = 0.0
	_completed = false
	_next_kf_index = 0
	_audio_started = false
	_progress_bar_active = false
	_progress_bar_last_percent = -1
	_progress_bar_line_added = false
	_progress_bar_expected_para_count = 0

	# 解析配置
	_skippable = bool(config.get("skippable", true))
	_total_duration = float(config.get("total_duration", 8.0))
	_audio_path = str(config.get("audio", ""))
	var audio_volume: float = float(config.get("audio_volume", 0.6))
	_audio_base_volume_db = linear_to_db(maxf(audio_volume, 0.01))

	# 解析关键帧
	_keyframes.clear()
	var kf_data: Array = config.get("keyframes", []) as Array
	for kf in kf_data:
		if kf is Dictionary:
			_keyframes.append(kf as Dictionary)
	_keyframes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)

	# 准备画面
	if main and main.output_text:
		main.output_text.text = ""
	if main and main.input_field:
		main.input_field.editable = false
		main.input_field.visible = false
	if main and main.prompt_label:
		main.prompt_label.visible = false

	print("[LoadingScreen] 载入画面启动, 时长: ", _total_duration, "s, 关键帧: ", _keyframes.size())

# ============================================================
# 使用内置默认配置启动
# ============================================================
func play_default() -> void:
	play(_get_builtin_default())

# ============================================================
# 每帧处理（由 main._process 或 disc_manager 调用）
# ============================================================
func process(delta: float) -> void:
	if not _active or _completed:
		return
	_elapsed += delta

	# 更新进度条（在关键帧之前，确保不会误删关键帧输出的内容）
	if _progress_bar_active:
		_update_progress_bar()

	# 执行到时间的关键帧
	while _next_kf_index < _keyframes.size():
		var kf: Dictionary = _keyframes[_next_kf_index]
		var kf_time: float = float(kf.get("time", 0.0))
		if _elapsed >= kf_time:
			_execute_keyframe(kf)
			_next_kf_index += 1
		else:
			break

	# 超时强制完成
	if _elapsed >= _total_duration + 1.0 and not _completed:
		_finish()

# ============================================================
# 跳过
# ============================================================
func skip() -> void:
	if not _active or not _skippable:
		return
	if _audio_player and _audio_player.playing:
		_audio_player.stop()
	_finish()

func is_active() -> bool:
	return _active

# ============================================================
# 关键帧动作执行
# ============================================================
func _execute_keyframe(kf: Dictionary) -> void:
	var action: String = str(kf.get("action", ""))
	var params: Dictionary = kf.get("params", {}) as Dictionary

	match action:
		# ── 文字输出 ──
		"text":
			var content: String = str(params.get("content", ""))
			var color_name: String = str(params.get("color", "primary"))
			_action_text(content, color_name)
		"text_center":
			var content: String = str(params.get("content", ""))
			var color_name: String = str(params.get("color", "primary"))
			_action_text_center(content, color_name)
		"disc_title":
			var color_name: String = str(params.get("color", "primary"))
			_action_disc_title(color_name)
		"disc_info":
			var color_name: String = str(params.get("color", "muted"))
			_action_disc_info(color_name)
		"separator":
			var ch: String = str(params.get("char", "═"))
			var width: int = int(params.get("width", 50))
			var color_name: String = str(params.get("color", "primary"))
			_action_separator(ch, width, color_name)
		"ascii_art":
			var content: String = str(params.get("content", ""))
			var color_name: String = str(params.get("color", "primary"))
			_action_text(content, color_name)

		# ── 视觉效果 ──
		"glitch":
			var intensity: float = float(params.get("intensity", 0.3))
			var duration: float = float(params.get("duration", 0.5))
			_action_glitch(intensity, duration)
		"scanlines":
			var intensity: float = float(params.get("intensity", 1.0))
			_action_scanlines(intensity)
		"screen_flash":
			var duration: float = float(params.get("duration", 0.15))
			_action_screen_flash(duration)

		# ── 音频 ──
		"beep":
			_action_beep()
		"sound":
			var path: String = str(params.get("path", ""))
			_action_sound(path)
		"audio_play":
			_action_audio_play(kf)

		# ── 流程控制 ──
		"clear":
			_action_clear()
		"wait":
			pass  # 纯占位
		"progress_bar":
			var duration: float = float(params.get("duration", 4.0))
			var label: String = str(params.get("label", "LOADING"))
			_action_start_progress_bar(duration, label)
		"complete":
			_finish()
		_:
			push_warning("[LoadingScreen] Unknown action: " + action)

# ============================================================
# 动作实现
# ============================================================

# ── 文字 ──
func _action_text(content: String, color_name: String) -> void:
	if main == null or main.output_text == null:
		return
	content = _replace_vars(content)
	var color_hex: String = _resolve_color(color_name)
	if content.is_empty():
		main.output_text.append_text("\n")
	else:
		main.output_text.append_text("[color=" + color_hex + "]" + content + "[/color]\n")
	main._request_scroll()

func _action_text_center(content: String, color_name: String) -> void:
	if main == null or main.output_text == null:
		return
	content = _replace_vars(content)
	var color_hex: String = _resolve_color(color_name)
	main.output_text.append_text("[center][color=" + color_hex + "]" + content + "[/color][/center]\n")
	main._request_scroll()

func _action_disc_title(color_name: String) -> void:
	if main == null or main.output_text == null:
		return
	var color_hex: String = _resolve_color(color_name)
	var m: String = _resolve_color("muted")
	# 用 build_box 构建标题框
	if fs and fs.has_method("build_box"):
		var box_lines: Array[String] = []
		box_lines.append(_disc_title)
		if not _disc_description.is_empty():
			box_lines.append(_disc_description)
		var box: String = fs.build_box(box_lines, color_hex)
		main.output_text.append_text(box + "\n")
	else:
		main.output_text.append_text("[color=" + color_hex + "][b]" + _disc_title + "[/b][/color]\n")
		if not _disc_description.is_empty():
			main.output_text.append_text("[color=" + m + "]" + _disc_description + "[/color]\n")
	main._request_scroll()

func _action_disc_info(color_name: String) -> void:
	if main == null or main.output_text == null:
		return
	var c: String = _resolve_color(color_name)
	var p: String = _resolve_color("primary")
	var lines: Array[String] = []
	if not _disc_author.is_empty():
		lines.append("  [color=" + c + "]Author:[/color]  [color=" + p + "]" + _disc_author + "[/color]")
	if not _disc_version.is_empty():
		lines.append("  [color=" + c + "]Version:[/color] [color=" + p + "]" + _disc_version + "[/color]")
	if not _disc_id.is_empty():
		lines.append("  [color=" + c + "]ID:[/color]      [color=" + p + "]" + _disc_id + "[/color]")
	for line in lines:
		main.output_text.append_text(line + "\n")
	main._request_scroll()

func _action_separator(ch: String, width: int, color_name: String) -> void:
	if main == null or main.output_text == null:
		return
	var color_hex: String = _resolve_color(color_name)
	var line: String = ch.repeat(clampi(width, 1, 80))
	main.output_text.append_text("[color=" + color_hex + "]" + line + "[/color]\n")
	main._request_scroll()

# ── 视觉效果 ──
func _action_glitch(intensity: float, duration: float) -> void:
	if effect_settings:
		if effect_settings.is_off():
			return
		intensity = effect_settings.apply_intensity(intensity)
		duration = effect_settings.apply_duration(duration)
	if crt_shader and crt_shader.has_method("play_glitch"):
		crt_shader.play_glitch(intensity, duration)

func _action_scanlines(intensity: float) -> void:
	if crt_shader and crt_shader.has_method("set_scanline_intensity"):
		crt_shader.set_scanline_intensity(intensity)

func _action_screen_flash(duration: float) -> void:
	if main == null:
		return
	if effect_settings and effect_settings.is_off():
		return
	# 利用 main 的 overlay 或 CRT shader
	if crt_shader and crt_shader.has_method("play_flash"):
		crt_shader.play_flash(duration)

# ── 音频 ──
func _action_beep() -> void:
	if audio_manager and audio_manager.has_method("play_beep"):
		audio_manager.play_beep()

func _action_sound(path: String) -> void:
	if audio_manager == null or fs == null or path.is_empty():
		return
	var norm_path: String = fs.normalize_path("/" + path.lstrip("/"))
	var stream: AudioStream = null
	var data: PackedByteArray = fs.get_binary_data(norm_path)
	if not data.is_empty() and audio_manager.has_method("load_audio_from_bytes"):
		stream = audio_manager.load_audio_from_bytes(norm_path, data)
	if stream != null and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx(stream)

func _action_audio_play(kf: Dictionary) -> void:
	if _audio_started or _audio_player == null:
		return
	# 优先从 kf params 获取路径，回退到顶层 audio 字段
	var audio_path: String = str(kf.get("params", {}).get("path", ""))
	if audio_path.is_empty():
		audio_path = _audio_path
	if audio_path.is_empty():
		return
	var stream: AudioStream = null
	# 尝试从虚拟文件系统加载
	if fs != null:
		var norm_path: String = fs.normalize_path("/" + audio_path.lstrip("/"))
		var data: PackedByteArray = fs.get_binary_data(norm_path)
		if not data.is_empty() and audio_manager and audio_manager.has_method("load_audio_from_bytes"):
			stream = audio_manager.load_audio_from_bytes(norm_path, data)
	# 回退到 res:// 加载
	if stream == null and ResourceLoader.exists(audio_path):
		stream = load(audio_path) as AudioStream
	if stream == null:
		return
	_audio_player.stream = stream
	_audio_player.volume_db = _audio_base_volume_db
	_audio_player.play()
	_audio_started = true

# ── 流程 ──
func _action_clear() -> void:
	if main and main.output_text:
		main.output_text.text = ""

func _action_start_progress_bar(duration: float, _label: String) -> void:
	_progress_bar_active = true
	_progress_bar_start = _elapsed
	_progress_bar_duration = duration
	_progress_bar_last_percent = -1
	_progress_bar_line_added = false
	_progress_bar_expected_para_count = 0

func _update_progress_bar() -> void:
	if main == null or main.output_text == null:
		return
	var progress_elapsed: float = _elapsed - _progress_bar_start
	var progress: float = clampf(progress_elapsed / _progress_bar_duration, 0.0, 1.0)
	var percent: int = int(progress * 100.0)
	if percent == _progress_bar_last_percent:
		return
	_progress_bar_last_percent = percent
	var bar_width: int = 40
	var filled: int = int(progress * bar_width)
	var empty_count: int = bar_width - filled
	var bar: String = "█".repeat(filled) + "░".repeat(empty_count)
	var p: String = _resolve_color("primary")
	var m: String = _resolve_color("muted")
	var line: String = "[color=" + m + "][" + bar + "] [/color][color=" + p + "]" + str(percent) + "%[/color]\n"
	# 原地更新：仅当上次写入后没有其他内容追加时，才安全替换上一行
	if _progress_bar_line_added:
		var current_para: int = main.output_text.get_paragraph_count()
		if current_para == _progress_bar_expected_para_count:
			# 没有新段落插入，可以安全替换
			main.output_text.remove_paragraph(current_para - 1)
		# 否则有其他内容被追加，直接追加新行（不删除旧行）
	main.output_text.append_text(line)
	_progress_bar_line_added = true
	_progress_bar_expected_para_count = main.output_text.get_paragraph_count()
	main._request_scroll()
	if progress >= 1.0:
		_progress_bar_active = false

# ============================================================
# 完成
# ============================================================
func _finish() -> void:
	_completed = true
	_active = false
	_progress_bar_active = false
	# 停止音频
	if _audio_player and _audio_player.playing:
		_audio_player.stop()
	# 恢复输入框
	if main and main.input_field:
		main.input_field.editable = true
		main.input_field.visible = true
		main.input_field.grab_focus()
	if main and main.prompt_label:
		main.prompt_label.visible = true
	print("[LoadingScreen] 载入画面完成")
	loading_completed.emit()

# ============================================================
# 内置默认配置
# ============================================================
func _get_builtin_default() -> Dictionary:
	return {
		"skippable": true,
		"total_duration": 6.0,
		"keyframes": [
			{"time": 0.0, "action": "clear"},
			{"time": 0.0, "action": "text", "params": {"content": "INSERTING VIRTUAL DISC...", "color": "muted"}},
			{"time": 0.3, "action": "beep"},
			{"time": 0.8, "action": "text", "params": {"content": "", "color": "primary"}},
			{"time": 1.0, "action": "disc_title"},
			{"time": 1.5, "action": "disc_info"},
			{"time": 2.0, "action": "separator"},
			{"time": 2.2, "action": "text", "params": {"content": "MOUNTING FILE SYSTEM...", "color": "muted"}},
			{"time": 2.5, "action": "progress_bar", "params": {"duration": 3.0}},
			{"time": 5.5, "action": "beep"},
			{"time": 5.5, "action": "text", "params": {"content": "DISC LOADED.", "color": "success"}},
			{"time": 6.0, "action": "complete"},
		]
	}

# ============================================================
# 工具函数
# ============================================================
func _resolve_color(color_name: String) -> String:
	if T == null:
		match color_name:
			"primary": return "#00ff00"
			"success": return "#00ff88"
			"warning": return "#ffaa00"
			"error": return "#ff4444"
			"muted": return "#888888"
			_: return "#00ff00"
	match color_name:
		"primary": return T.primary_hex
		"success": return T.success_hex
		"warning": return T.warning_hex
		"error": return T.error_hex
		"muted": return T.muted_hex
		_: return T.primary_hex

func _replace_vars(text: String) -> String:
	text = text.replace("{disc_title}", _disc_title)
	text = text.replace("{disc_author}", _disc_author)
	text = text.replace("{disc_version}", _disc_version)
	text = text.replace("{disc_id}", _disc_id)
	if main and "user_mgr" in main and main.user_mgr != null and main.user_mgr.is_logged_in:
		text = text.replace("{username}", main.user_mgr.get_username())
	return text
