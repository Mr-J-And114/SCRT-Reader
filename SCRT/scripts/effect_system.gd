# ============================================================
# effect_system.gd - 效果编排系统
# 职责：将多个原子效果按时间轴编排为序列，支持 JSON 配置驱动
#
# ---- 效果序列 JSON 格式 ----
# {
#   "id": "jumpscare_01",
#   "steps": [
#     { "time": 0.0, "action": "glitch", "params": { "intensity": 0.8, "duration": 1.5, "preset": "heavy" } },
#     { "time": 0.0, "action": "shake", "params": { "intensity": 0.02, "duration": 1.0 } },
#     { "time": 0.3, "action": "sound", "params": { "path": "/sfx/scare.ogg", "volume": 0.0 } },
#     { "time": 0.5, "action": "noise_burst", "params": { "intensity": 0.9, "duration": 0.4 } },
#     { "time": 0.8, "action": "tear", "params": { "strength": 0.12, "duration": 0.5 } },
#     { "time": 1.5, "action": "text", "params": { "content": "[警告] 未知实体已突破收容", "color": "error" } },
#     { "time": 2.0, "action": "blackout", "params": { "duration": 1.0 } },
#     { "time": 3.5, "action": "reboot" }
#   ]
# }
#
# ---- 支持的原子动作 ----
# glitch      : intensity, duration, preset
# shake       : intensity, duration
# tear        : strength, duration
# noise_burst : intensity, duration
# sound       : path, volume
# text        : content, color(primary/error/warning/muted/success)
# blackout    : duration
# shutdown    : duration
# boot        : duration
# reboot      : shutdown_dur, blackout_dur, boot_dur
# brightness  : value, duration (渐变到目标亮度)
# chromatic   : value, duration (色差突变)
# flicker     : intensity, duration (闪烁强化)
# ============================================================
class_name EffectSystem
extends RefCounted

# ── 依赖引用 ──
var main: Control = null
var fs = null          # FileSystem
var T = null           # ThemeColors
var audio_mgr = null   # AudioManager
var crt_shader = null   # crt_shader.gd 实例

# ── 预定义效果库（从 manifest 加载） ──
var _effect_library: Dictionary = {}  # "effect_id" -> { "steps": [...] }

# ── 播放状态 ──
var _playing: bool = false
var _current_id: String = ""
var _timeline: Array[Dictionary] = []  # 待执行的步骤（按 time 排序）
var _elapsed: float = 0.0
var _next_index: int = 0

# ── 信号 ──
signal effect_started(effect_id: String)
signal effect_finished(effect_id: String)

# ============================================================
# 初始化
# ============================================================
func setup(p_main: Control, p_fs, p_theme, p_audio, p_crt_shader) -> void:
	main = p_main
	fs = p_fs
	T = p_theme
	audio_mgr = p_audio
	crt_shader = p_crt_shader

## 从 manifest 中加载效果定义
## manifest["effects"] = { "jumpscare_01": { "steps": [...] }, ... }
func load_from_manifest(manifest: Dictionary) -> void:
	_effect_library.clear()
	if not manifest.has("effects"):
		return
	var effects_raw = manifest["effects"]
	if not effects_raw is Dictionary:
		return
	for key in (effects_raw as Dictionary).keys():
		var effect_data = effects_raw[key]
		if effect_data is Dictionary and effect_data.has("steps"):
			_effect_library[str(key)] = effect_data
	if not _effect_library.is_empty():
		print("[EffectSystem] 已加载 ", _effect_library.size(), " 个效果定义")

## 运行时动态注册效果
func register_effect(effect_id: String, effect_data: Dictionary) -> void:
	_effect_library[effect_id] = effect_data

# ============================================================
# 播放控制
# ============================================================

## 播放指定效果序列
## effect_id: 效果库中的 ID
## override_data: 可选的直接传入效果数据（不从库中查找）
func play(effect_id: String, override_data: Dictionary = {}) -> void:
	# 如果正在播放，先停止
	if _playing:
		stop()

	var effect_data: Dictionary = {}
	if not override_data.is_empty():
		effect_data = override_data
	elif _effect_library.has(effect_id):
		effect_data = _effect_library[effect_id]
	else:
		push_warning("[EffectSystem] 未找到效果: " + effect_id)
		return

	var steps_raw = effect_data.get("steps", [])
	if not steps_raw is Array or (steps_raw as Array).is_empty():
		push_warning("[EffectSystem] 效果 " + effect_id + " 没有有效的 steps")
		return

	# 构建排序后的时间轴
	_timeline.clear()
	for step in steps_raw:
		if step is Dictionary:
			_timeline.append(step as Dictionary)

	# 按 time 字段排序
	_timeline.sort_custom(_sort_by_time)

	_current_id = effect_id
	_elapsed = 0.0
	_next_index = 0
	_playing = true
	effect_started.emit(effect_id)
	print("[EffectSystem] 开始播放效果: ", effect_id, " (", _timeline.size(), " 步)")

## 停止当前效果
func stop() -> void:
	if not _playing:
		return
	var finished_id: String = _current_id
	_playing = false
	_current_id = ""
	_timeline.clear()
	_next_index = 0
	_elapsed = 0.0
	effect_finished.emit(finished_id)

## 是否正在播放
func is_playing() -> bool:
	return _playing

## 获取当前播放的效果ID
func get_current_id() -> String:
	return _current_id

# ============================================================
# 每帧驱动（由 main._process 调用）
# ============================================================
func process(delta: float) -> void:
	if not _playing:
		return

	_elapsed += delta

	# 执行所有到达时间点的步骤
	while _next_index < _timeline.size():
		var step: Dictionary = _timeline[_next_index]
		var step_time: float = float(step.get("time", 0.0))
		if _elapsed >= step_time:
			_execute_step(step)
			_next_index += 1
		else:
			break

	# 所有步骤都已执行，检查是否完成
	if _next_index >= _timeline.size():
		# 计算最后一个步骤的预估结束时间
		var last_end: float = _estimate_end_time()
		if _elapsed >= last_end:
			var finished_id: String = _current_id
			_playing = false
			_current_id = ""
			effect_finished.emit(finished_id)

# ============================================================
# 执行单个步骤
# ============================================================
func _execute_step(step: Dictionary) -> void:
	var action: String = str(step.get("action", "")).strip_edges().to_lower()
	var params: Dictionary = {}
	if step.has("params") and step["params"] is Dictionary:
		params = step["params"] as Dictionary

	match action:
		"glitch":
			_step_glitch(params)
		"shake":
			_step_shake(params)
		"tear":
			_step_tear(params)
		"noise_burst":
			_step_noise_burst(params)
		"sound":
			_step_sound(params)
		"text":
			_step_text(params)
		"blackout":
			_step_blackout(params)
		"shutdown":
			_step_shutdown(params)
		"boot":
			_step_boot(params)
		"reboot":
			_step_reboot(params)
		"brightness":
			_step_brightness(params)
		"chromatic":
			_step_chromatic(params)
		"flicker":
			_step_flicker(params)
		_:
			push_warning("[EffectSystem] 未知动作: " + action)

# ── 动作实现 ──

func _step_glitch(params: Dictionary) -> void:
	var intensity: float = float(params.get("intensity", 0.5))
	var duration: float = float(params.get("duration", 1.0))
	var preset: String = str(params.get("preset", "custom"))
	if main and main.has_method("trigger_glitch"):
		main.trigger_glitch(intensity, duration, preset)

func _step_shake(params: Dictionary) -> void:
	var intensity: float = float(params.get("intensity", 0.01))
	var duration: float = float(params.get("duration", 0.5))
	if main and main.has_method("trigger_shake"):
		main.trigger_shake(intensity, duration)

func _step_tear(params: Dictionary) -> void:
	var strength: float = float(params.get("strength", 0.08))
	var duration: float = float(params.get("duration", 0.5))
	if main and main.has_method("trigger_tear"):
		main.trigger_tear(strength, duration)

func _step_noise_burst(params: Dictionary) -> void:
	var intensity: float = float(params.get("intensity", 0.8))
	var duration: float = float(params.get("duration", 0.3))
	if main and main.has_method("trigger_noise_burst"):
		main.trigger_noise_burst(intensity, duration)

func _step_sound(params: Dictionary) -> void:
	var path: String = str(params.get("path", ""))
	var volume: float = float(params.get("volume", 0.0))
	if path.is_empty() or audio_mgr == null or fs == null:
		return
	var norm_path: String = fs.normalize_path("/" + path.lstrip("/"))
	var data: PackedByteArray = fs.get_binary_data(norm_path)
	var stream: AudioStream = null
	if not data.is_empty() and audio_mgr.has_method("load_audio_from_bytes"):
		stream = audio_mgr.load_audio_from_bytes(norm_path, data)
	# 备用：从工程资源加载
	if stream == null and ResourceLoader.exists("res://" + path):
		stream = load("res://" + path) as AudioStream
	if stream != null and audio_mgr.has_method("play_sfx"):
		audio_mgr.play_sfx(stream, volume)
	else:
		push_warning("[EffectSystem] 无法加载音效: " + path)

func _step_text(params: Dictionary) -> void:
	var content: String = str(params.get("content", ""))
	if content.is_empty():
		return
	var color_name: String = str(params.get("color", "primary")).strip_edges().to_lower()
	var hex: String = _resolve_color_hex(color_name)
	if main and main.has_method("append_output"):
		main.append_output("\n[color=" + hex + "]" + content + "[/color]\n", false)

func _step_blackout(params: Dictionary) -> void:
	var duration: float = float(params.get("duration", 2.0))
	if main and main.has_method("trigger_screen_off"):
		main.trigger_screen_off(duration)

func _step_shutdown(params: Dictionary) -> void:
	var duration: float = float(params.get("duration", 0.8))
	if crt_shader and crt_shader.has_method("play_shutdown"):
		crt_shader.play_shutdown(duration)

func _step_boot(params: Dictionary) -> void:
	var duration: float = float(params.get("duration", 1.2))
	if crt_shader and crt_shader.has_method("play_boot"):
		crt_shader.play_boot(duration)

func _step_reboot(params: Dictionary) -> void:
	var shutdown_dur: float = float(params.get("shutdown_dur", 0.6))
	var blackout_dur: float = float(params.get("blackout_dur", 0.8))
	var boot_dur: float = float(params.get("boot_dur", 1.0))
	if crt_shader and crt_shader.has_method("play_reboot"):
		crt_shader.play_reboot(shutdown_dur, blackout_dur, boot_dur)

func _step_brightness(params: Dictionary) -> void:
	var value: float = float(params.get("value", 1.2))
	var duration: float = float(params.get("duration", 0.5))
	if crt_shader == null:
		return
	var mat: ShaderMaterial = crt_shader.get_shader_material() if crt_shader.has_method("get_shader_material") else null
	if mat == null:
		return
	if duration <= 0.05:
		mat.set_shader_parameter("brightness", value)
	else:
		var tw: Tween = main.get_tree().create_tween()
		tw.tween_property(mat, "shader_parameter/brightness", value, duration)

func _step_chromatic(params: Dictionary) -> void:
	var value: float = float(params.get("value", 2.0))
	var duration: float = float(params.get("duration", 0.5))
	if crt_shader == null:
		return
	var mat: ShaderMaterial = crt_shader.get_shader_material() if crt_shader.has_method("get_shader_material") else null
	if mat == null:
		return
	var original: float = float(mat.get_shader_parameter("chromatic_aberration"))
	mat.set_shader_parameter("chromatic_aberration", value)
	if duration > 0.05:
		var tw: Tween = main.get_tree().create_tween()
		tw.tween_property(mat, "shader_parameter/chromatic_aberration", original, duration)\
			.set_ease(Tween.EASE_OUT)

func _step_flicker(params: Dictionary) -> void:
	var intensity: float = float(params.get("intensity", 0.15))
	var duration: float = float(params.get("duration", 1.0))
	if crt_shader == null:
		return
	var mat: ShaderMaterial = crt_shader.get_shader_material() if crt_shader.has_method("get_shader_material") else null
	if mat == null:
		return
	var original: float = float(mat.get_shader_parameter("flicker_intensity"))
	mat.set_shader_parameter("flicker_intensity", intensity)
	if duration > 0.05:
		var tw: Tween = main.get_tree().create_tween()
		tw.tween_interval(duration * 0.7)
		tw.tween_property(mat, "shader_parameter/flicker_intensity", original, duration * 0.3)\
			.set_ease(Tween.EASE_OUT)

# ============================================================
# 内置预设效果（代码定义，不需要 JSON）
# ============================================================

## 轻微不安感：微弱 glitch + 轻微色差偏移
func play_unease(duration: float = 2.0) -> void:
	play("_builtin_unease", {
		"steps": [
			{"time": 0.0, "action": "glitch", "params": {"intensity": 0.15, "duration": duration, "preset": "subtle"}},
			{"time": 0.0, "action": "chromatic", "params": {"value": 1.5, "duration": duration}},
			{"time": duration * 0.5, "action": "flicker", "params": {"intensity": 0.08, "duration": duration * 0.5}},
		]
	})

## 中等恐惧：故障 + 震动 + 噪点
func play_disturb(duration: float = 2.5) -> void:
	play("_builtin_disturb", {
		"steps": [
			{"time": 0.0, "action": "glitch", "params": {"intensity": 0.5, "duration": duration * 0.8, "preset": "moderate"}},
			{"time": 0.1, "action": "shake", "params": {"intensity": 0.012, "duration": duration * 0.6}},
			{"time": 0.3, "action": "noise_burst", "params": {"intensity": 0.4, "duration": 0.3}},
			{"time": 0.5, "action": "chromatic", "params": {"value": 3.0, "duration": 1.0}},
			{"time": duration * 0.6, "action": "tear", "params": {"strength": 0.06, "duration": 0.4}},
		]
	})

## 强烈冲击（jumpscare 基础）：剧烈故障 + 强震 + 噪点爆发
func play_jumpscare_base(duration: float = 3.0) -> void:
	play("_builtin_jumpscare", {
		"steps": [
			{"time": 0.0, "action": "glitch", "params": {"intensity": 0.9, "duration": duration * 0.5, "preset": "chaos"}},
			{"time": 0.0, "action": "shake", "params": {"intensity": 0.035, "duration": duration * 0.4}},
			{"time": 0.0, "action": "noise_burst", "params": {"intensity": 0.95, "duration": 0.5}},
			{"time": 0.0, "action": "chromatic", "params": {"value": 4.5, "duration": 0.8}},
			{"time": 0.05, "action": "flicker", "params": {"intensity": 0.18, "duration": 1.0}},
			{"time": 0.2, "action": "tear", "params": {"strength": 0.13, "duration": 0.6}},
			{"time": 0.8, "action": "noise_burst", "params": {"intensity": 0.6, "duration": 0.3}},
			{"time": 1.5, "action": "blackout", "params": {"duration": 1.0}},
		]
	})

## 系统崩溃：故障逐渐加剧 → 关机 → 重启
func play_system_crash(total_duration: float = 5.0) -> void:
	play("_builtin_crash", {
		"steps": [
			{"time": 0.0, "action": "glitch", "params": {"intensity": 0.3, "duration": 1.5, "preset": "moderate"}},
			{"time": 0.0, "action": "flicker", "params": {"intensity": 0.12, "duration": 2.0}},
			{"time": 0.5, "action": "text", "params": {"content": "[CRITICAL] 系统完整性校验失败", "color": "error"}},
			{"time": 1.0, "action": "shake", "params": {"intensity": 0.008, "duration": 1.5}},
			{"time": 1.5, "action": "glitch", "params": {"intensity": 0.7, "duration": 1.0, "preset": "heavy"}},
			{"time": 1.5, "action": "noise_burst", "params": {"intensity": 0.5, "duration": 0.4}},
			{"time": 2.0, "action": "chromatic", "params": {"value": 4.0, "duration": 0.5}},
			{"time": 2.0, "action": "text", "params": {"content": "[FATAL] 核心进程无响应，正在执行紧急重启...", "color": "error"}},
			{"time": 2.5, "action": "shake", "params": {"intensity": 0.025, "duration": 0.5}},
			{"time": 3.0, "action": "reboot", "params": {"shutdown_dur": 0.5, "blackout_dur": 0.8, "boot_dur": 1.0}},
		]
	})

# ============================================================
# 辅助
# ============================================================

func _sort_by_time(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("time", 0.0)) < float(b.get("time", 0.0))

func _resolve_color_hex(color_name: String) -> String:
	if T == null:
		return "#FFFFFF"
	match color_name:
		"primary":  return T.primary_hex
		"error":    return T.error_hex
		"warning":  return T.warning_hex
		"muted":    return T.muted_hex
		"success":  return T.success_hex
		"info":     return T.info_hex
		"secondary": return T.secondary_hex
		"dim":      return T.dim_hex
		_:
			# 如果直接传了 hex 值
			if color_name.begins_with("#"):
				return color_name
			return T.primary_hex

## 估算效果序列的总持续时间
func _estimate_end_time() -> float:
	var max_end: float = 0.0
	for step in _timeline:
		var t: float = float(step.get("time", 0.0))
		var params = step.get("params", {})
		var dur: float = 0.0
		if params is Dictionary:
			dur = float((params as Dictionary).get("duration", 0.0))
			# reboot 特殊处理
			if str(step.get("action", "")) == "reboot":
				dur = float((params as Dictionary).get("shutdown_dur", 0.6)) \
					+ float((params as Dictionary).get("blackout_dur", 0.8)) \
					+ float((params as Dictionary).get("boot_dur", 1.0))
		var end: float = t + maxf(dur, 0.5)  # 最少 0.5s 缓冲
		if end > max_end:
			max_end = end
	return max_end

## 获取效果库中所有已注册的效果 ID
func get_registered_effects() -> Array[String]:
	var ids: Array[String] = []
	for key in _effect_library.keys():
		ids.append(str(key))
	return ids

## 检查效果是否存在
func has_effect(effect_id: String) -> bool:
	return _effect_library.has(effect_id)
