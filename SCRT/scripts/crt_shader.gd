# ============================================================
# crt_shader.gd - CRT Shader 效果控制器
# 挂载在 CRTEffect 下的 ColorRect 节点上
# 职责：尺寸适配 + 提供 glitch/shake/boot/shutdown 等效果的 Tween 驱动接口
# ============================================================
extends ColorRect

# ══════════════════════════════════════════
#  缓存 ShaderMaterial 引用
# ══════════════════════════════════════════
var _mat: ShaderMaterial = null

# ══════════════════════════════════════════
#  活跃 Tween 引用（用于取消/覆盖）
# ══════════════════════════════════════════
var _glitch_tween: Tween = null
var _shake_tween: Tween = null
var _boot_tween: Tween = null
var _brightness_tween: Tween = null
var _noise_burst_tween: Tween = null
var _tear_tween: Tween = null

# ══════════════════════════════════════════
#  震动状态
# ══════════════════════════════════════════
var _shake_active: bool = false
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _shake_duration: float = 0.0

# ══════════════════════════════════════════
#  信号
# ══════════════════════════════════════════
signal boot_completed()
signal shutdown_completed()
signal effect_finished(effect_name: String)

# ══════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════
func _ready() -> void:
	_update_size.call_deferred()
	get_tree().root.size_changed.connect(_update_size)
	# 缓存 ShaderMaterial
	if material is ShaderMaterial:
		_mat = material as ShaderMaterial
	else:
		push_warning("[CRTShader] ColorRect 没有 ShaderMaterial！")

func _update_size() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	set_deferred("position", Vector2.ZERO)
	set_deferred("size", viewport_size)

func _process(delta: float) -> void:
	# 屏幕震动：每帧随机偏移
	if _shake_active:
		# ★ 持续模式（duration >= 90）不计时
		if _shake_duration < 90.0:
			_shake_timer -= delta
			if _shake_timer <= 0.0:
				_shake_active = false
				_set_param("shake_offset", Vector2.ZERO)
				effect_finished.emit("shake")
				return
		# 随着时间衰减震动强度（持续模式不衰减）
		var decay: float = 1.0
		if _shake_duration < 90.0 and _shake_duration > 0.0:
			decay = _shake_timer / _shake_duration
		var current_intensity: float = _shake_intensity * decay
		var offset := Vector2(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity)
		)
		_set_param("shake_offset", offset)

# ══════════════════════════════════════════
#  Shader 参数安全访问
# ══════════════════════════════════════════
func _set_param(param_name: String, value: Variant) -> void:
	if _mat != null:
		_mat.set_shader_parameter(param_name, value)

func _get_param(param_name: String, default: Variant = 0.0) -> Variant:
	if _mat != null:
		return _mat.get_shader_parameter(param_name)
	return default

func get_shader_material() -> ShaderMaterial:
	return _mat

# ══════════════════════════════════════════
#  效果1：Glitch 故障效果
# ══════════════════════════════════════════
## 播放 glitch 效果
## intensity: 0.0~1.0 强度
## duration: 持续时间（秒），>= 90.0 表示持续模式（不自动恢复）
## preset: 预设名（"subtle"/"moderate"/"heavy"/"chaos"/"custom"）
func play_glitch(intensity: float = 0.5, duration: float = 1.0, preset: String = "custom") -> void:
	_kill_tween("_glitch_tween")

	# ★ 强度接近零时直接重置
	if intensity <= 0.001:
		_reset_glitch_params()
		return

	# 根据预设调整参数
	var color_drift: float = 0.0
	var line_speed: float = 8.0
	var line_density: float = 10.0
	var noise_burst_val: float = 0.0

	match preset:
		"subtle":
			intensity = clampf(intensity, 0.0, 0.3)
			color_drift = intensity * 0.005
			line_speed = 4.0
			noise_burst_val = 0.0
		"moderate":
			intensity = clampf(intensity, 0.2, 0.6)
			color_drift = intensity * 0.015
			line_speed = 8.0
			noise_burst_val = intensity * 0.1
		"heavy":
			intensity = clampf(intensity, 0.5, 0.9)
			color_drift = intensity * 0.03
			line_speed = 14.0
			line_density = 20.0
			noise_burst_val = intensity * 0.3
		"chaos":
			intensity = clampf(intensity, 0.7, 1.0)
			color_drift = 0.04
			line_speed = 20.0
			line_density = 30.0
			noise_burst_val = 0.6
		"custom", _:
			# 自定义：按 intensity 线性插值
			color_drift = intensity * 0.025
			line_speed = lerpf(4.0, 18.0, intensity)
			line_density = lerpf(8.0, 25.0, intensity)
			noise_burst_val = intensity * 0.2

	# 立即设置参数
	_set_param("glitch_intensity", intensity)
	_set_param("glitch_color_drift", color_drift)
	_set_param("glitch_line_speed", line_speed)
	_set_param("glitch_line_density", line_density)
	_set_param("noise_burst", noise_burst_val)

	# ★ 持续模式：不创建淡出 Tween
	if duration >= 90.0:
		return

	# 持续 duration 后淡出恢复 — 捕获初始值用于线性淡出
	var fade_base_intensity: float = intensity
	var fade_base_color_drift: float = color_drift
	var fade_base_noise_burst: float = noise_burst_val
	_glitch_tween = _create_tween()
	_glitch_tween.tween_interval(duration * 0.7)
	# 后 30% 时间淡出
	_glitch_tween.tween_method(
		func(t: float) -> void:
			_set_param("glitch_intensity", fade_base_intensity * t)
			_set_param("glitch_color_drift", fade_base_color_drift * t)
			_set_param("noise_burst", fade_base_noise_burst * t),
		1.0, 0.0, duration * 0.3)
	_glitch_tween.tween_callback(_on_glitch_finished)

func _on_glitch_finished() -> void:
	_reset_glitch_params()
	effect_finished.emit("glitch")

func _reset_glitch_params() -> void:
	_set_param("glitch_intensity", 0.0)
	_set_param("glitch_color_drift", 0.0)
	_set_param("glitch_line_speed", 8.0)
	_set_param("glitch_line_density", 10.0)
	_set_param("noise_burst", 0.0)
	_set_param("tear_strength", 0.0)

## 立即停止 glitch
func stop_glitch() -> void:
	_kill_tween("_glitch_tween")
	_reset_glitch_params()

# ══════════════════════════════════════════
#  效果2：屏幕撕裂
# ══════════════════════════════════════════
## ★ 完全重写：使用新的 tear_strength / tear_speed / tear_count 参数
## 产生多条随机水平撕裂线，效果远比旧版明显
##
## strength: 撕裂水平位移量（0.03~0.2 为合理范围）
## y_pos: 保留参数（兼容旧调用签名），不再使用
## duration: 持续时间（秒），>= 90.0 表示持续模式
func play_tear(strength: float = 0.08, y_pos: float = -1.0, duration: float = 0.5) -> void:
	_kill_tween("_tear_tween")

	# ★ 强度接近零时直接重置
	if strength <= 0.001:
		_set_param("tear_strength", 0.0)
		_set_param("tear_speed", 3.0)
		_set_param("tear_count", 3.0)
		return

	# ★ 增强撕裂参数：强度越高，撕裂线越多、移动越快
	var clamped_strength: float = clampf(strength, 0.02, 0.2)
	var speed: float = 3.0 + clamped_strength * 25.0       # 强度0.08→5.0, 0.2→8.0
	var count: float = 3.0 + clamped_strength * 20.0        # 强度0.08→4.6, 0.2→7.0

	_set_param("tear_strength", clamped_strength)
	_set_param("tear_speed", speed)
	_set_param("tear_count", count)

	# ★ 持续模式：不创建淡出 Tween
	if duration >= 90.0:
		return

	_tear_tween = _create_tween()
	# 前60%保持全强度，后40%淡出
	_tear_tween.tween_interval(duration * 0.6)
	_tear_tween.tween_property(_mat, "shader_parameter/tear_strength", 0.0, duration * 0.4)\
		.set_ease(Tween.EASE_OUT)
	_tear_tween.tween_callback(func():
		_set_param("tear_speed", 3.0)
		_set_param("tear_count", 3.0)
		effect_finished.emit("tear")
	)

# ══════════════════════════════════════════
#  效果3：屏幕震动
# ══════════════════════════════════════════
## 播放屏幕震动
## intensity: 最大偏移量（UV 空间，0.005~0.05 为合理范围）
## duration: 持续时间（秒），>= 90.0 表示持续模式
func play_shake(intensity: float = 0.01, duration: float = 0.5) -> void:
	# ★ 强度接近零时直接停止
	if intensity <= 0.001:
		stop_shake()
		return
	_shake_active = true
	_shake_intensity = clampf(intensity, 0.001, 0.1)
	_shake_duration = duration
	_shake_timer = duration

## 立即停止震动
func stop_shake() -> void:
	_shake_active = false
	_shake_intensity = 0.0
	_set_param("shake_offset", Vector2.ZERO)

# ══════════════════════════════════════════
#  效果4：屏幕关闭动画
# ══════════════════════════════════════════
## CRT 关机效果：画面收缩为中心水平亮线，然后消失
## duration: 总时长（秒）
func play_shutdown(duration: float = 0.8) -> void:
	_kill_tween("_boot_tween")

	# 保存当前亮度以便之后恢复
	var original_brightness: float = float(_get_param("brightness", 1.2))

	_boot_tween = _create_tween()

	# 阶段1：画面快速收缩到一条线（占总时长 60%）
	_boot_tween.tween_property(_mat, "shader_parameter/screen_height_ratio", 0.0, duration * 0.6)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# 阶段2：亮线停留一小会，带辉光
	_boot_tween.tween_property(_mat, "shader_parameter/boot_glow", 1.5, duration * 0.1)

	# 阶段3：亮线淡出消失
	_boot_tween.tween_property(_mat, "shader_parameter/boot_glow", 0.0, duration * 0.3)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	_boot_tween.tween_callback(func():
		_set_param("brightness", original_brightness)
		shutdown_completed.emit()
		effect_finished.emit("shutdown")
	)

# ══════════════════════════════════════════
#  效果5：屏幕开机动画
# ══════════════════════════════════════════
## CRT 开机效果：从中心亮线展开为完整画面
## duration: 总时长（秒）
func play_boot(duration: float = 1.2) -> void:
	_kill_tween("_boot_tween")

	# 从关闭状态开始
	_set_param("screen_height_ratio", 0.0)
	_set_param("boot_glow", 0.0)

	_boot_tween = _create_tween()

	# 阶段1：中心出现亮线（快速）
	_boot_tween.tween_property(_mat, "shader_parameter/boot_glow", 2.0, duration * 0.15)

	# 阶段2：画面从亮线展开（主要过程）
	_boot_tween.tween_property(_mat, "shader_parameter/screen_height_ratio", 1.0, duration * 0.55)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 同时辉光逐渐消退（并行 tween）
	var glow_tween: Tween = _create_tween()
	glow_tween.tween_interval(duration * 0.15)  # 等亮线出现后
	glow_tween.tween_property(_mat, "shader_parameter/boot_glow", 0.0, duration * 0.7)\
		.set_ease(Tween.EASE_OUT)

	# 阶段3：稍微过曝后恢复正常
	_boot_tween.tween_property(_mat, "shader_parameter/brightness", 1.5, duration * 0.1)
	_boot_tween.tween_property(_mat, "shader_parameter/brightness", 1.2, duration * 0.2)\
		.set_ease(Tween.EASE_OUT)

	_boot_tween.tween_callback(func():
		_set_param("screen_height_ratio", 1.0)
		_set_param("boot_glow", 0.0)
		boot_completed.emit()
		effect_finished.emit("boot")
	)

# ══════════════════════════════════════════
#  效果6：屏幕黑屏（简单版，用于 trigger_screen_off）
# ══════════════════════════════════════════
## 屏幕黑屏指定时长后恢复
func play_blackout(duration: float = 2.0) -> void:
	_kill_tween("_brightness_tween")

	var original_brightness: float = float(_get_param("brightness", 1.2))
	_set_param("brightness", 0.0)

	_brightness_tween = _create_tween()
	_brightness_tween.tween_interval(duration)
	_brightness_tween.tween_property(_mat, "shader_parameter/brightness", original_brightness, 0.3)\
		.set_ease(Tween.EASE_OUT)
	_brightness_tween.tween_callback(func(): effect_finished.emit("blackout"))

# ══════════════════════════════════════════
#  效果7：噪点爆发（独立使用）
# ══════════════════════════════════════════
## ★ 支持持续模式（duration >= 90.0）
func play_noise_burst(intensity: float = 0.8, duration: float = 0.3) -> void:
	_kill_tween("_noise_burst_tween")

	# ★ 强度接近零时直接重置
	if intensity <= 0.001:
		_set_param("noise_burst", 0.0)
		return

	_set_param("noise_burst", intensity)

	# ★ 持续模式：不创建淡出 Tween
	if duration >= 90.0:
		return

	_noise_burst_tween = _create_tween()
	_noise_burst_tween.tween_interval(duration * 0.6)
	_noise_burst_tween.tween_property(_mat, "shader_parameter/noise_burst", 0.0, duration * 0.4)
	_noise_burst_tween.tween_callback(func(): effect_finished.emit("noise_burst"))

# ══════════════════════════════════════════
#  组合效果：模拟重启
# ══════════════════════════════════════════
## 模拟 CRT 重启：关机 → 短暂黑屏 → 开机
## 返回一个信号，可以在关机完成时执行清屏等操作
func play_reboot(shutdown_dur: float = 0.6, blackout_dur: float = 0.8, boot_dur: float = 1.0) -> void:
	_kill_tween("_boot_tween")
	_kill_tween("_brightness_tween")

	# 先关机
	play_shutdown(shutdown_dur)

	# 关机完成后等待黑屏，然后开机
	await shutdown_completed

	# 黑屏等待
	_set_param("screen_height_ratio", 0.0)
	_set_param("boot_glow", 0.0)
	await get_tree().create_timer(blackout_dur).timeout

	# 开机
	play_boot(boot_dur)

# ══════════════════════════════════════════
#  复位：将所有效果参数恢复默认
# ══════════════════════════════════════════
func reset_all_effects() -> void:
	_kill_tween("_glitch_tween")
	_kill_tween("_shake_tween")
	_kill_tween("_boot_tween")
	_kill_tween("_brightness_tween")
	_kill_tween("_noise_burst_tween")
	_kill_tween("_tear_tween")

	_shake_active = false
	_shake_intensity = 0.0

	_reset_glitch_params()
	_set_param("shake_offset", Vector2.ZERO)
	_set_param("screen_height_ratio", 1.0)
	_set_param("boot_glow", 0.0)
	_set_param("brightness", 1.2)
	# ★ 重置撕裂参数
	_set_param("tear_strength", 0.0)
	_set_param("tear_speed", 3.0)
	_set_param("tear_count", 3.0)

# ══════════════════════════════════════════
#  Tween 工具
# ══════════════════════════════════════════
func _create_tween() -> Tween:
	return get_tree().create_tween().bind_node(self)

func _kill_tween(tween_name: String) -> void:
	var tw: Tween = get(tween_name)
	if tw != null and tw.is_valid():
		tw.kill()
	set(tween_name, null)
