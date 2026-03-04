# ============================================================
# effect_settings.gd - 效果强度与安全设置
# 职责：全局控制所有视觉效果的强度等级，提供光敏安全选项
#
# 三级效果强度：
#   FULL    = 完整效果（默认）
#   MILD    = 温和效果（强度减半，禁用最剧烈的闪烁）
#   OFF     = 关闭所有动态效果
#
# 光敏安全模式（独立于强度等级）：
#   开启后禁用：快速闪烁、高强度 glitch、jumpscare 闪屏
# ============================================================
class_name EffectSettings
extends RefCounted

enum Level { FULL, MILD, OFF }

# ── 当前设置 ──
var effect_level: Level = Level.FULL
var photosensitive_mode: bool = false  # 光敏安全模式

# ── 设置变更信号 ──
signal settings_changed

# ── 持久化路径 ──
const SETTINGS_KEY_LEVEL: String = "effect_level"
const SETTINGS_KEY_PHOTO: String = "photosensitive_mode"
var _save_root: String = ""

# ============================================================
# 初始化与持久化
# ============================================================

func setup_save_root(save_root: String) -> void:
	_save_root = save_root
	if not _save_root.ends_with("/"):
		_save_root += "/"

func _get_config_path() -> String:
	if not _save_root.is_empty():
		return _save_root + "effect_settings.cfg"
	# 兜底：游戏根目录 saves/
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://") + "saves/effect_settings.cfg"
	return OS.get_executable_path().get_base_dir() + "/saves/effect_settings.cfg"

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var path: String = _get_config_path()
	if cfg.load(path) == OK:
		effect_level = cfg.get_value("effects", SETTINGS_KEY_LEVEL, Level.FULL) as Level
		photosensitive_mode = cfg.get_value("effects", SETTINGS_KEY_PHOTO, false)
	else:
		# 兼容迁移：尝试从旧 user:// 路径读取
		var legacy_path: String = "user://effect_settings.cfg"
		if cfg.load(legacy_path) == OK:
			effect_level = cfg.get_value("effects", SETTINGS_KEY_LEVEL, Level.FULL) as Level
			photosensitive_mode = cfg.get_value("effects", SETTINGS_KEY_PHOTO, false)
			# 迁移到新路径
			save_settings()
			print("[EffectSettings] 已从 user:// 迁移到 saves/ 目录")
	print("[EffectSettings] 已加载: level=", Level.keys()[effect_level], " photosensitive=", photosensitive_mode)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("effects", SETTINGS_KEY_LEVEL, effect_level)
	cfg.set_value("effects", SETTINGS_KEY_PHOTO, photosensitive_mode)
	cfg.save(_get_config_path())

# ============================================================
# 设置接口
# ============================================================

func set_level(level: Level) -> void:
	if effect_level != level:
		effect_level = level
		save_settings()
		settings_changed.emit()
		print("[EffectSettings] 效果等级已变更: ", Level.keys()[level])

func set_photosensitive(enabled: bool) -> void:
	if photosensitive_mode != enabled:
		photosensitive_mode = enabled
		save_settings()
		settings_changed.emit()
		print("[EffectSettings] 光敏安全模式: ", "开启" if enabled else "关闭")

func get_level_name() -> String:
	return Level.keys()[effect_level]

func is_full() -> bool:
	return effect_level == Level.FULL

func is_mild() -> bool:
	return effect_level == Level.MILD

func is_off() -> bool:
	return effect_level == Level.OFF

# ============================================================
# 强度衰减计算（供各效果系统调用）
# ============================================================

## 对标量强度值应用等级衰减
## 返回经过等级调整后的值
func apply_intensity(raw_intensity: float) -> float:
	match effect_level:
		Level.FULL:
			return raw_intensity
		Level.MILD:
			return raw_intensity * 0.4
		Level.OFF:
			return 0.0
	return raw_intensity

## 对持续时间应用等级调整（温和模式缩短持续时间）
func apply_duration(raw_duration: float) -> float:
	match effect_level:
		Level.FULL:
			return raw_duration
		Level.MILD:
			return raw_duration * 0.6
		Level.OFF:
			return 0.0
	return raw_duration

## 检查某个效果类型是否被允许
## 光敏模式会额外禁用某些危险效果
func is_effect_allowed(effect_type: String) -> bool:
	if effect_level == Level.OFF:
		return false
	if photosensitive_mode:
		# 光敏模式禁用的效果类型
		var blocked: Array[String] = [
			"jumpscare", "chaos", "heavy",  # 剧烈预设
			"flicker",                       # 快速闪烁
			"blackout",                      # 突然黑屏
			"noise_burst",                   # 高强度噪点爆发
		]
		if effect_type.to_lower() in blocked:
			return false
	return true

## 对 glitch 预设名进行降级
## 光敏/温和模式下，剧烈预设会被降级为较温和的版本
func downgrade_preset(preset: String) -> String:
	var p: String = preset.to_lower()
	if effect_level == Level.OFF:
		return "off"
	if effect_level == Level.MILD or photosensitive_mode:
		match p:
			"chaos":
				return "moderate"
			"heavy":
				return "subtle"
			"moderate":
				return "subtle" if photosensitive_mode else "moderate"
	return p

## 对屏幕震动强度应用安全限制
func apply_shake_intensity(raw: float) -> float:
	if effect_level == Level.OFF:
		return 0.0
	var result: float = apply_intensity(raw)
	if photosensitive_mode:
		result = minf(result, 0.008)  # 光敏模式限制最大震动
	return result

## 对闪烁强度应用安全限制
func apply_flicker_intensity(raw: float) -> float:
	if effect_level == Level.OFF:
		return 0.0
	if photosensitive_mode:
		return 0.0  # 光敏模式完全禁用闪烁
	return apply_intensity(raw)
