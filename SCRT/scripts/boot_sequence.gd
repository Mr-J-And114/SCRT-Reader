# ============================================================
# boot_sequence.gd - 开关机动画编排系统
# 职责：
#   - 解析开/关机动画配置（JSON 关键帧格式）
#   - 按时间轴驱动 CRT shader 效果、音频、文字输出
#   - 支持三级覆盖：磁盘包 > 用户自定义 > 内置默认
#
# 配置文件位置：
#   内置默认:  res://boot_config.json
#   用户覆盖:  saves/<username>/boot_config.json
#   磁盘包:    (由 manifest 的 boot_sequence 字段指定)
#
# 关键帧格式示例：
# {
#   "boot": {
#     "audio": "res://audio/start.mp3",
#     "audio_start_offset": 0.5,
#     "total_duration": 20.0,
#     "audio_fade_out_start": 15.0,
#     "audio_fade_out_end": 25.0,
#     "keyframes": [
#       { "time": 0.0, "action": "screen_off" },
#       { "time": 0.3, "action": "screen_on", "params": { "speed": 0.8 } },
#       { "time": 0.5, "action": "scanlines", "params": { "intensity": 1.5 } },
#       { "time": 1.0, "action": "text", "params": { "content": "BIOS v2.14", "color": "primary" } },
#       { "time": 5.8, "action": "beep" },
#       { "time": 5.8, "action": "text", "params": { "content": "POST CHECK... OK", "color": "success" } },
#       { "time": 6.0, "action": "glitch", "params": { "intensity": 0.3, "duration": 0.5 } },
#       { "time": 8.0, "action": "text", "params": { "content": "LOADING SYSTEM...", "color": "muted" } },
#       { "time": 10.0, "action": "progress_bar", "params": { "duration": 6.0 } },
#       { "time": 16.0, "action": "scanlines", "params": { "intensity": 1.0 } },
#       { "time": 18.0, "action": "clear" },
#       { "time": 20.0, "action": "complete" }
#     ]
#   },
#   "shutdown": {
#     "total_duration": 4.0,
#     "keyframes": [
#       { "time": 0.0, "action": "text", "params": { "content": "SHUTTING DOWN...", "color": "muted" } },
#       { "time": 0.8, "action": "clear" },
#       { "time": 1.0, "action": "shutdown_sound" },
#       { "time": 1.0, "action": "screen_collapse" },
#       { "time": 2.5, "action": "screen_off" },
#       { "time": 4.0, "action": "quit" }
#     ]
#   }
# }
# ============================================================
class_name BootSequence
extends RefCounted

# ── 引用 ──
var main = null
var T = null
var audio_manager = null
var crt_shader = null
var effect_settings = null

# ── 状态 ──
var _active: bool = false
var _is_boot: bool = true  # true=开机, false=关机
var _elapsed: float = 0.0
var _total_duration: float = 20.0
var _keyframes: Array[Dictionary] = []
var _next_kf_index: int = 0
var _completed: bool = false

# ── 音频控制 ──
var _boot_audio_player: AudioStreamPlayer = null
var _audio_start_offset: float = 0.5
var _audio_fade_out_start: float = 15.0
var _audio_fade_out_end: float = 25.0
var _audio_started: bool = false
var _audio_base_volume_db: float = 0.0

# ── 进度条 ──
var _progress_bar_active: bool = false
var _progress_bar_start: float = 0.0
var _progress_bar_duration: float = 6.0
var _progress_bar_last_percent: int = -1

# ── 关机音效 ──
var _shutdown_sound_player: AudioStreamPlayer = null

# ── 黑屏遮罩 ──
var _black_overlay: ColorRect = null

var skippable: bool = false  # 是否允许用户跳过

# ── 配置 ──
var _boot_config: Dictionary = {}
var _shutdown_config: Dictionary = {}

# ── 信号 ──
signal boot_completed
signal shutdown_completed

# ============================================================
# 初始化
# ============================================================
func setup(p_main, p_audio_manager, p_crt_shader) -> void:
	main = p_main
	T = ThemeManager.current
	audio_manager = p_audio_manager
	crt_shader = p_crt_shader
	effect_settings = main.effect_settings if main else null
	# 创建音频播放器
	_boot_audio_player = AudioStreamPlayer.new()
	_boot_audio_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	main.add_child.call_deferred(_boot_audio_player)
	_shutdown_sound_player = AudioStreamPlayer.new()
	_shutdown_sound_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	main.add_child.call_deferred(_shutdown_sound_player)

	# 创建全屏黑色遮罩（用于隐藏 CRT shader 初始化时的短暂画面）
	_black_overlay = ColorRect.new()
	_black_overlay.color = Color.BLACK
	_black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black_overlay.visible = false
	# 使用 CanvasLayer 确保在最顶层
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "BootOverlay"
	overlay_layer.layer = 100  # 在 CRT 效果之上
	main.add_child.call_deferred(overlay_layer)
	# 延迟添加 ColorRect 到 CanvasLayer
	_setup_overlay_deferred.call_deferred(overlay_layer)

func _setup_overlay_deferred(layer: CanvasLayer) -> void:
	_black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_black_overlay)


	# 加载默认配置
	_load_default_config()

# ============================================================
# 配置加载（三级覆盖）
# ============================================================
func _load_default_config() -> void:
	var config: Dictionary = _get_builtin_default()
	# 尝试加载 res://boot_config.json
	if FileAccess.file_exists("res://boot_config.json"):
		var loaded: Dictionary = _load_json_file("res://boot_config.json")
		if not loaded.is_empty():
			config = _merge_config(config, loaded)
	_boot_config = config.get("boot", {}) as Dictionary
	_shutdown_config = config.get("shutdown", {}) as Dictionary

func load_user_override(username: String) -> void:
	var user_path: String = "user://saves/" + username + "/boot_config.json"
	if FileAccess.file_exists(user_path):
		var loaded: Dictionary = _load_json_file(user_path)
		if not loaded.is_empty():
			var base: Dictionary = _get_current_full_config()
			var merged: Dictionary = _merge_config(base, loaded)
			_boot_config = merged.get("boot", _boot_config) as Dictionary
			_shutdown_config = merged.get("shutdown", _shutdown_config) as Dictionary
			print("[BootSequence] 已加载用户自定义开机配置: " + username)

func load_disc_override(manifest: Dictionary) -> void:
	if manifest.has("boot_sequence"):
		var disc_boot: Dictionary = manifest.get("boot_sequence", {}) as Dictionary
		if not disc_boot.is_empty():
			var base: Dictionary = _get_current_full_config()
			var merged: Dictionary = _merge_config(base, disc_boot)
			_boot_config = merged.get("boot", _boot_config) as Dictionary
			_shutdown_config = merged.get("shutdown", _shutdown_config) as Dictionary
			print("[BootSequence] 已加载磁盘包自定义开机配置")

func _get_current_full_config() -> Dictionary:
	return {"boot": _boot_config, "shutdown": _shutdown_config}

func _merge_config(base: Dictionary, override: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key in override.keys():
		result[key] = override[key]
	return result

func _load_json_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("[BootSequence] JSON 解析失败: " + path)
		return {}
	if json.data is Dictionary:
		return json.data as Dictionary
	return {}

# ============================================================
# 内置默认配置（基于 start.mp3 参数）
# ============================================================
func _get_builtin_default() -> Dictionary:
	return {
		"boot": {
			"audio": "res://audio/startup.mp3",
			"audio_start_offset": 0.5,
			"audio_volume": 0.8,
			"total_duration": 20.0,
			"audio_fade_out_start": 15.0,
			"audio_fade_out_end": 20.0,
			"keyframes": [
				{"time": 0.0, "action": "screen_off"},
				{"time": 0.1, "action": "audio_play"},
				{"time": 0.3, "action": "fade_in", "params": {"duration": 1.5, "from": "#000000"}},
				{"time": 0.5, "action": "background", "params": {"action": "fade_in", "duration": 2.5}},
				{"time": 0.8, "action": "logo", "params": {"action": "blink", "blink_count": 4, "duration": 1.5}},
				{"time": 3.5, "action": "scanlines", "params": {"intensity": 2.0}},
				{"time": 4.0, "action": "text", "params": {"content": "BIOS POST v2.14.7", "color": "muted"}},
				{"time": 4.5, "action": "text", "params": {"content": "MEM CHECK: 640K OK", "color": "muted"}},
				{"time": 5.0, "action": "text", "params": {"content": "FDD 0: 3.5\" 1.44MB", "color": "muted"}},
				{"time": 5.3, "action": "text", "params": {"content": "HDD 0: SCP-VDISC CONTROLLER", "color": "muted"}},
				{"time": 5.5, "action": "text", "params": {"content": "", "color": "primary"}},
				{"time": 5.8, "action": "beep"},
				{"time": 5.8, "action": "text", "params": {"content": "POST CHECK COMPLETE - ALL SYSTEMS OK", "color": "success"}},
				{"time": 6.0, "action": "glitch", "params": {"intensity": 0.2, "duration": 0.3}},
				{"time": 6.5, "action": "text", "params": {"content": "", "color": "primary"}},
				{"time": 7.0, "action": "text", "params": {"content": "LOADING SCP TERMINAL OS v4.6.1 ...", "color": "primary"}},
				{"time": 7.5, "action": "scanlines", "params": {"intensity": 1.2}},
				{"time": 8.0, "action": "progress_bar", "params": {"duration": 8.0, "label": "SYSTEM LOAD"}},
				{"time": 16.5, "action": "text", "params": {"content": "INITIALIZATION COMPLETE", "color": "success"}},
				{"time": 17.0, "action": "scanlines", "params": {"intensity": 1.0}},
				{"time": 17.5, "action": "glitch", "params": {"intensity": 0.15, "duration": 0.2}},
				{"time": 18.5, "action": "clear"},
				{"time": 19.0, "action": "text", "params": {"content": "TERMINAL READY.", "color": "primary"}},
				{"time": 20.0, "action": "complete"}
			]
		},
		"shutdown": {
			"total_duration": 5.0,
			"keyframes": [
				{"time": 0.0, "action": "text", "params": {"content": "\nSHUTTING DOWN TERMINAL...", "color": "muted"}},
				{"time": 0.3, "action": "glitch", "params": {"intensity": 0.3, "duration": 0.3}},
				{"time": 0.8, "action": "clear"},
				{"time": 0.8, "action": "shutdown_sound"},
				{"time": 1.0, "action": "logo", "params": {"action": "hide", "duration": 0.3}},
				{"time": 1.0, "action": "background", "params": {"action": "hide", "duration": 0.5}},
				{"time": 1.3, "action": "screen_collapse"},
				{"time": 3.0, "action": "screen_off"},
				{"time": 5.0, "action": "quit"}
			]
		}
	}



# ============================================================
# 启动开机序列
# ============================================================
func play_boot() -> void:
	if _active:
		return
	# 确保遮罩已就绪
	if _black_overlay and not _black_overlay.is_inside_tree():
		await main.get_tree().process_frame
	T = ThemeManager.current
	_active = true
	_is_boot = true
	_elapsed = 0.0
	_completed = false
	_next_kf_index = 0
	_audio_started = false
	_progress_bar_active = false
	_progress_bar_last_percent = -1
	# 解析配置
	_total_duration = float(_boot_config.get("total_duration", 20.0))
	_audio_start_offset = float(_boot_config.get("audio_start_offset", 0.5))
	_audio_fade_out_start = float(_boot_config.get("audio_fade_out_start", 15.0))
	_audio_fade_out_end = float(_boot_config.get("audio_fade_out_end", 25.0))
	var audio_volume: float = float(_boot_config.get("audio_volume", 0.8))
	_audio_base_volume_db = linear_to_db(audio_volume)
	# 解析关键帧
	_keyframes.clear()
	var kf_data: Array = _boot_config.get("keyframes", []) as Array
	for kf in kf_data:
		if kf is Dictionary:
			_keyframes.append(kf as Dictionary)
	# 按时间排序
	_keyframes.sort_custom(_sort_by_time)
	# 清屏准备
	if main and main.output_text:
		main.output_text.text = ""
	# 隐藏输入框
	if main and main.input_field:
		main.input_field.editable = false
		main.input_field.visible = false
	print("[BootSequence] 开机序列启动，时长: " + str(_total_duration) + "s, 关键帧: " + str(_keyframes.size()))

# ============================================================
# 启动关机序列
# ============================================================
func play_shutdown() -> void:
	if _active:
		return
	T = ThemeManager.current
	_active = true
	_is_boot = false
	_elapsed = 0.0
	_completed = false
	_next_kf_index = 0
	_progress_bar_active = false
	# 解析配置
	_total_duration = float(_shutdown_config.get("total_duration", 4.5))
	# 解析关键帧
	_keyframes.clear()
	var kf_data: Array = _shutdown_config.get("keyframes", []) as Array
	for kf in kf_data:
		if kf is Dictionary:
			_keyframes.append(kf as Dictionary)
	_keyframes.sort_custom(_sort_by_time)
	# 隐藏输入框
	if main and main.input_field:
		main.input_field.editable = false
		main.input_field.visible = false
	print("[BootSequence] 关机序列启动，时长: " + str(_total_duration) + "s")

func _sort_by_time(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("time", 0.0)) < float(b.get("time", 0.0))

# ============================================================
# 每帧处理
# ============================================================
func process(delta: float) -> void:
	if not _active or _completed:
		return
	_elapsed += delta
	# 执行到时间的关键帧
	while _next_kf_index < _keyframes.size():
		var kf: Dictionary = _keyframes[_next_kf_index]
		var kf_time: float = float(kf.get("time", 0.0))
		if _elapsed >= kf_time:
			_execute_keyframe(kf)
			_next_kf_index += 1
		else:
			break
	# 更新音频淡出
	if _is_boot and _audio_started:
		_update_audio_fade()
	# 更新进度条
	if _progress_bar_active:
		_update_progress_bar()
	# 超时强制完成
	if _elapsed >= _total_duration + 2.0 and not _completed:
		_finish()

# ============================================================
# 关键帧动作执行
# ============================================================
func _execute_keyframe(kf: Dictionary) -> void:
	var action: String = str(kf.get("action", ""))
	var params: Dictionary = kf.get("params", {}) as Dictionary
	match action:
		"screen_off":
			_action_screen_off()
		"screen_on":
			var speed: float = float(params.get("speed", 0.8))
			_action_screen_on(speed)
		"audio_play":
			_action_audio_play()
		"text":
			var content: String = str(params.get("content", ""))
			var color_name: String = str(params.get("color", "primary"))
			_action_text(content, color_name)
		"beep":
			_action_beep()
		"glitch":
			var intensity: float = float(params.get("intensity", 0.3))
			var duration: float = float(params.get("duration", 0.5))
			_action_glitch(intensity, duration)
		"scanlines":
			var intensity: float = float(params.get("intensity", 1.0))
			_action_scanlines(intensity)
		"progress_bar":
			var duration: float = float(params.get("duration", 6.0))
			var label: String = str(params.get("label", "LOADING"))
			_action_start_progress_bar(duration, label)
		"clear":
			_action_clear()
		"screen_collapse":
			_action_screen_collapse()
		"shutdown_sound":
			_action_shutdown_sound()
		"fade_in":
			var duration: float = float(params.get("duration", 1.0))
			var from_color: String = str(params.get("from", "#000000"))
			_action_fade_in(duration, from_color)
		"background":
			var bg_action: String = str(params.get("action", "fade_in"))
			var bg_path: String = str(params.get("path", ""))
			var bg_duration: float = float(params.get("duration", 1.0))
			_action_background(bg_action, bg_path, bg_duration)
		"logo":
			var logo_action: String = str(params.get("action", "show"))
			var logo_text: String = str(params.get("text", ""))
			var logo_ascii: String = str(params.get("ascii", ""))
			var logo_blink_count: int = int(params.get("blink_count", 2))
			var logo_duration: float = float(params.get("duration", 2.0))
			_action_logo(logo_action, logo_text, logo_ascii, logo_blink_count, logo_duration)
		"complete":
			_finish()
		"quit":
			_action_quit()
		_:
			push_warning("[BootSequence] 未知动作: " + action)

# ── 具体动作实现 ──
func _action_screen_off() -> void:
	if _black_overlay:
		_black_overlay.color = Color.BLACK
		_black_overlay.visible = true

func _action_screen_on(speed: float) -> void:
	if crt_shader and crt_shader.has_method("set_brightness"):
		crt_shader.set_brightness(1.0)
	# 遮罩淡出（模拟屏幕渐亮）
	if _black_overlay and main:
		var fade_duration: float = 1.0 / maxf(speed, 0.1)
		var tween: Tween = main.create_tween()
		tween.tween_property(_black_overlay, "color", Color(0, 0, 0, 0), fade_duration)
		tween.tween_callback(func(): _black_overlay.visible = false)

func _action_audio_play() -> void:
	if _audio_started:
		return
	var audio_path: String = str(_boot_config.get("audio", "res://audio/start.mp3"))
	var stream: AudioStream = null
	# 从 res:// 加载
	if ResourceLoader.exists(audio_path):
		stream = load(audio_path) as AudioStream
	if stream == null:
		push_warning("[BootSequence] 无法加载开机音频: " + audio_path)
		return
	_boot_audio_player.stream = stream
	_boot_audio_player.volume_db = _audio_base_volume_db
	# 从指定偏移开始播放
	_boot_audio_player.play(_audio_start_offset)
	_audio_started = true
	print("[BootSequence] 开机音频开始播放，偏移: " + str(_audio_start_offset) + "s")

func _action_text(content: String, color_name: String) -> void:
	if main == null or main.output_text == null:
		return
	var color_hex: String = _resolve_color(color_name)
	if content.is_empty():
		main.output_text.append_text("\n")
	else:
		main.output_text.append_text("[color=" + color_hex + "]" + content + "[/color]\n")
	main._request_scroll()


func _action_beep() -> void:
	if audio_manager and audio_manager.has_method("play_beep"):
		audio_manager.play_beep()

func _action_glitch(intensity: float, duration: float) -> void:
	# 经过效果设置衰减
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

func _action_start_progress_bar(duration: float, _label: String) -> void:
	_progress_bar_active = true
	_progress_bar_start = _elapsed
	_progress_bar_duration = duration
	_progress_bar_last_percent = -1

func _action_clear() -> void:
	if main and main.output_text:
		main.output_text.text = ""


func _action_screen_collapse() -> void:
	# 通过 shader 隐藏背景和 logo（已在 shutdown keyframes 中用 hide 动作处理）
	# 使用 CRT shader 的关机效果
	if crt_shader and crt_shader.has_method("play_shutdown"):
		crt_shader.play_shutdown()


func _action_shutdown_sound() -> void:
	var audio_path: String = "res://audio/shutdown.mp3"
	if ResourceLoader.exists(audio_path):
		var stream: AudioStream = load(audio_path) as AudioStream
		if stream:
			_shutdown_sound_player.stream = stream
			_shutdown_sound_player.volume_db = -3.0
			_shutdown_sound_player.play()
			return
	# 回退：如果文件不存在则用程序化生成
	_generate_fallback_shutdown_sound()

func _generate_fallback_shutdown_sound() -> void:
	var duration: float = 1.2
	var sample_rate: float = 22050.0
	var count: int = int(sample_rate * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t: float = float(i) / sample_rate
		var progress: float = t / duration
		var freq: float = 1200.0 * exp(-progress * 4.0) + 80.0
		var env: float = 1.0
		if t < 0.02:
			env = t / 0.02
		elif t > duration * 0.6:
			env = (duration - t) / (duration * 0.4)
		env = maxf(env, 0.0)
		var tone: float = sin(t * TAU * freq) * 0.5
		tone += sin(t * TAU * freq * 2.0) * 0.15
		tone += randf_range(-1.0, 1.0) * 0.05 * env
		samples[i] = clampf(tone * env * 0.6, -1.0, 1.0)
	var stream := AudioStreamWAV.new()
	stream.mix_rate = int(sample_rate)
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var val: float = clampf(samples[i], -1.0, 1.0)
		var int16_val: int = int(val * 32767.0)
		data[i * 2] = int16_val & 0xFF
		data[i * 2 + 1] = (int16_val >> 8) & 0xFF
	stream.data = data
	_shutdown_sound_player.stream = stream
	_shutdown_sound_player.volume_db = -6.0
	_shutdown_sound_player.play()


func _action_quit() -> void:
	_completed = true
	shutdown_completed.emit()
	# 延迟一帧后退出，确保信号处理完
	if main:
		main.get_tree().quit.call_deferred()


func _action_fade_in(duration: float, from_color_hex: String) -> void:
	if _black_overlay == null or main == null:
		return
	var from_color: Color = Color(from_color_hex)
	from_color.a = 1.0
	_black_overlay.color = from_color
	_black_overlay.visible = true
	var tween: Tween = main.create_tween()
	tween.tween_property(_black_overlay, "color:a", 0.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func(): _black_overlay.visible = false)


func _action_background(bg_action: String, bg_path: String, duration: float) -> void:
	if main == null or main.background == null:
		return
	var bg_tex: TextureRect = main.background
	var mat: ShaderMaterial = bg_tex.material as ShaderMaterial
	match bg_action:
		"fade_in":
			if mat:
				# 通过 shader uniform 淡入
				var target_brightness: float = 0.688
				var target_alpha: float = 0.5
				mat.set_shader_parameter("brightness", 0.0)
				mat.set_shader_parameter("alpha", 0.0)
				var tween: Tween = main.create_tween().set_parallel(true)
				tween.tween_method(func(v: float): mat.set_shader_parameter("brightness", v), 0.0, target_brightness, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				tween.tween_method(func(v: float): mat.set_shader_parameter("alpha", v), 0.0, target_alpha, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			else:
				bg_tex.modulate = Color(1, 1, 1, 0)
				var tween: Tween = main.create_tween()
				tween.tween_property(bg_tex, "modulate:a", 1.0, duration)
		"change":
			if not bg_path.is_empty() and ResourceLoader.exists(bg_path):
				var tex: Texture2D = load(bg_path) as Texture2D
				if tex:
					bg_tex.texture = tex
			# 换完后淡入
			_action_background("fade_in", "", duration)
		"hide":
			if mat:
				var tween: Tween = main.create_tween().set_parallel(true)
				tween.tween_method(func(v: float): mat.set_shader_parameter("brightness", v), mat.get_shader_parameter("brightness"), 0.0, duration)
				tween.tween_method(func(v: float): mat.set_shader_parameter("alpha", v), mat.get_shader_parameter("alpha"), 0.0, duration)
			else:
				var tween: Tween = main.create_tween()
				tween.tween_property(bg_tex, "modulate:a", 0.0, duration)
		"show":
			if mat:
				mat.set_shader_parameter("brightness", 0.688)
				mat.set_shader_parameter("alpha", 0.5)
			else:
				bg_tex.modulate = Color(1, 1, 1, 1)


func _action_logo(logo_action: String, logo_text: String, logo_ascii: String, blink_count: int, duration: float) -> void:
	if main == null:
		return
	var logo_node: TextureRect = main.background_logo
	if logo_node == null:
		# 没有 logo 节点则回退到文字
		if not logo_text.is_empty() or not logo_ascii.is_empty():
			var p: String = _resolve_color("primary")
			var content: String = logo_ascii if not logo_ascii.is_empty() else logo_text
			main.output_text.append_text("[color=" + p + "]" + content + "[/color]\n")
			main._request_scroll()
		return
	var mat: ShaderMaterial = logo_node.material as ShaderMaterial
	match logo_action:
		"show":
			if mat:
				mat.set_shader_parameter("brightness", 0.0)
				mat.set_shader_parameter("alpha", 0.4)
			else:
				logo_node.modulate = Color(1, 1, 1, 1)
		"blink":
			_blink_logo_node(logo_node, blink_count, duration)
		"fade_in":
			if mat:
				mat.set_shader_parameter("brightness", 0.0)
				mat.set_shader_parameter("alpha", 0.0)
				var tween: Tween = main.create_tween().set_parallel(true)
				tween.tween_method(func(v: float): mat.set_shader_parameter("brightness", v), 0.0, 0.0, duration)
				tween.tween_method(func(v: float): mat.set_shader_parameter("alpha", v), 0.0, 0.4, duration).set_ease(Tween.EASE_OUT)
			else:
				logo_node.modulate = Color(1, 1, 1, 0)
				var tween: Tween = main.create_tween()
				tween.tween_property(logo_node, "modulate:a", 1.0, duration)
		"hide":
			if mat:
				var tween: Tween = main.create_tween().set_parallel(true)
				tween.tween_method(func(v: float): mat.set_shader_parameter("brightness", v), mat.get_shader_parameter("brightness"), 0.0, duration)
				tween.tween_method(func(v: float): mat.set_shader_parameter("alpha", v), mat.get_shader_parameter("alpha"), 0.0, duration)
			else:
				var tween: Tween = main.create_tween()
				tween.tween_property(logo_node, "modulate:a", 0.0, duration)


func _blink_logo_node(logo_node: TextureRect, blink_count: int, total_duration: float) -> void:
	if main == null or logo_node == null:
		return
	var mat: ShaderMaterial = logo_node.material as ShaderMaterial
	if mat == null:
		# 没有 shader，用 modulate 回退
		_blink_logo_modulate(logo_node, blink_count, total_duration)
		return
	# 通过 shader brightness + alpha 快速闪烁
	var target_brightness: float = 0.0  # logo shader 默认 brightness
	var target_alpha: float = 0.4	   # logo shader 默认 alpha
	var flash_brightness: float = 1.5   # 闪烁时的高亮
	var flash_alpha: float = 0.8		# 闪烁时的高透明度
	# 开始前确保不可见
	mat.set_shader_parameter("brightness", 0.0)
	mat.set_shader_parameter("alpha", 0.0)
	var tween: Tween = main.create_tween()
	# 快速闪烁（每次闪烁约 0.15s）
	for i in range(blink_count):
		# 闪亮
		tween.tween_method(func(v: float): mat.set_shader_parameter("brightness", v), 0.0, flash_brightness, 0.04)
		tween.tween_method(func(v: float): mat.set_shader_parameter("alpha", v), 0.0, flash_alpha, 0.04)
		tween.tween_interval(0.08)
		# 熄灭
		tween.tween_method(func(v: float): mat.set_shader_parameter("brightness", v), flash_brightness, 0.0, 0.03)
		tween.tween_method(func(v: float): mat.set_shader_parameter("alpha", v), flash_alpha, 0.0, 0.03)
		tween.tween_interval(0.06)
	# 最后一次闪亮后稳定到正常值
	tween.tween_method(func(v: float): mat.set_shader_parameter("brightness", v), 0.0, flash_brightness, 0.04)
	tween.tween_method(func(v: float): mat.set_shader_parameter("alpha", v), 0.0, flash_alpha, 0.04)
	tween.tween_interval(0.1)
	# 平滑过渡到稳态
	tween.tween_method(func(v: float): mat.set_shader_parameter("brightness", v), flash_brightness, target_brightness, 0.5)
	tween.tween_method(func(v: float): mat.set_shader_parameter("alpha", v), flash_alpha, target_alpha, 0.5)

## modulate 回退方案
func _blink_logo_modulate(logo_node: TextureRect, blink_count: int, _total_duration: float) -> void:
	var tween: Tween = main.create_tween()
	logo_node.modulate = Color(1, 1, 1, 0)
	for i in range(blink_count):
		tween.tween_property(logo_node, "modulate:a", 1.0, 0.04)
		tween.tween_interval(0.08)
		tween.tween_property(logo_node, "modulate:a", 0.0, 0.03)
		tween.tween_interval(0.06)
	tween.tween_property(logo_node, "modulate:a", 1.0, 0.04)
	tween.tween_interval(0.1)
	tween.tween_property(logo_node, "modulate:a", 1.0, 0.3)


# ============================================================
# 音频淡出控制
# ============================================================
func _update_audio_fade() -> void:
	if not _boot_audio_player.playing:
		return
	# 计算实际音频播放时间（含偏移）
	var audio_time: float = _elapsed
	if audio_time < _audio_fade_out_start:
		# 还没到淡出时间，保持原音量
		_boot_audio_player.volume_db = _audio_base_volume_db
		return
	if audio_time >= _audio_fade_out_end:
		# 完全静音并停止
		_boot_audio_player.stop()
		return
	# 淡出区间：使用平滑的 ease-out 曲线
	var fade_progress: float = (audio_time - _audio_fade_out_start) / (_audio_fade_out_end - _audio_fade_out_start)
	fade_progress = clampf(fade_progress, 0.0, 1.0)
	# 使用二次 ease-out: 先快后慢
	var volume_linear: float = (1.0 - fade_progress) * (1.0 - fade_progress)
	var target_db: float = linear_to_db(maxf(volume_linear * db_to_linear(_audio_base_volume_db), 0.001))
	_boot_audio_player.volume_db = target_db

# ============================================================
# 进度条更新
# ============================================================
func _update_progress_bar() -> void:
	if main == null or main.output_text == null:
		return
	var progress_elapsed: float = _elapsed - _progress_bar_start
	var progress: float = clampf(progress_elapsed / _progress_bar_duration, 0.0, 1.0)
	var percent: int = int(progress * 100.0)
	# 只在百分比变化时更新，避免过度刷新
	if percent == _progress_bar_last_percent:
		return
	_progress_bar_last_percent = percent
	# 构建进度条
	var bar_width: int = 40
	var filled: int = int(progress * bar_width)
	var empty_count: int = bar_width - filled
	var bar: String = "█".repeat(filled) + "░".repeat(empty_count)
	var p: String = T.primary_hex if T else "#00ff00"
	var m: String = T.muted_hex if T else "#888888"
	# 用最后一行替换的方式（追加然后覆盖）
	# 简化实现：每5%输出一次
	if percent % 5 == 0 or percent == 100:
		main.output_text.append_text("[color=" + m + "][" + bar + "] [/color][color=" + p + "]" + str(percent) + "%[/color]\n")
		main._request_scroll()
	if progress >= 1.0:
		_progress_bar_active = false

# ============================================================
# 完成处理
# ============================================================
func _finish() -> void:
	_completed = true
	_active = false
	_progress_bar_active = false
	# 确保遮罩被隐藏（开机完成时）
	if _is_boot and _black_overlay:
		_black_overlay.visible = false
		_black_overlay.color = Color(0, 0, 0, 0)
	# 恢复输入框
	if main and main.input_field:
		main.input_field.editable = true
		main.input_field.visible = true
		main.input_field.grab_focus()
	if _is_boot:
		print("[BootSequence] 开机序列完成")
		boot_completed.emit()
	else:
		print("[BootSequence] 关机序列完成")
		shutdown_completed.emit()


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
		"info": return T.info_hex if T.get("info_hex") else T.primary_hex
		_: return T.primary_hex

func is_active() -> bool:
	return _active

func skip() -> void:
	if not _active:
		return
	# 跳过：立即停止音频，直接完成

	if not skippable:
		return  # 首次开机不可跳过

	if _boot_audio_player and _boot_audio_player.playing:
		_boot_audio_player.stop()
	if _black_overlay:
		_black_overlay.visible = false
	_finish()
