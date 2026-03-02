# ============================================================
# settings_storage.gd - 设置持久化后端
# 负责：全局/用户设置的读写、旧配置检测
# 路径：res://scripts/settings/settings_storage.gd
# ============================================================
class_name SettingsStorage
extends RefCounted

# ============================================================
# 常量
# ============================================================
const SETTINGS_VERSION: int = 1
const GLOBAL_FILENAME: String = "_settings_global.json"
const USER_FILENAME: String = "settings.json"

# 旧配置文件列表（用于检测不兼容）
const LEGACY_FILES: Array[String] = [
	"theme.cfg",
	"audio.cfg",
	"effect_settings.cfg",
]

# ============================================================
# 状态
# ============================================================
var _save_root: String = ""

# ============================================================
# 初始化
# ============================================================
func setup(save_root: String) -> void:
	_save_root = save_root
	if not _save_root.ends_with("/"):
		_save_root += "/"
	if not DirAccess.dir_exists_absolute(_save_root):
		DirAccess.make_dir_recursive_absolute(_save_root)

# ============================================================
# 全局设置读写
# ============================================================
func save_global(data: Dictionary) -> bool:
	var path: String = _save_root + GLOBAL_FILENAME
	var payload: Dictionary = {
		"version": SETTINGS_VERSION,
		"timestamp": _get_timestamp(),
		"settings": data,
	}
	return _write_json(path, payload)

func load_global() -> Dictionary:
	var path: String = _save_root + GLOBAL_FILENAME
	var payload: Dictionary = _read_json(path)
	if payload.is_empty():
		return {}
	# 版本检查
	var ver: int = int(payload.get("version", 0))
	if ver != SETTINGS_VERSION:
		push_warning("[SettingsStorage] 全局设置版本不匹配: 期望 %d, 实际 %d" % [SETTINGS_VERSION, ver])
		# 未来可在此做版本迁移；当前直接返回空让系统用默认值
		return {}
	return payload.get("settings", {}) as Dictionary

# ============================================================
# 用户设置读写
# ============================================================
func save_user(username: String, data: Dictionary) -> bool:
	if username.is_empty():
		return false
	var dir_path: String = _save_root + username + "/"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var path: String = dir_path + USER_FILENAME
	var payload: Dictionary = {
		"version": SETTINGS_VERSION,
		"timestamp": _get_timestamp(),
		"settings": data,
	}
	return _write_json(path, payload)

func load_user(username: String) -> Dictionary:
	if username.is_empty():
		return {}
	var path: String = _save_root + username + "/" + USER_FILENAME
	var payload: Dictionary = _read_json(path)
	if payload.is_empty():
		return {}
	var ver: int = int(payload.get("version", 0))
	if ver != SETTINGS_VERSION:
		push_warning("[SettingsStorage] 用户设置版本不匹配 (%s): 期望 %d, 实际 %d" % [username, SETTINGS_VERSION, ver])
		return {}
	return payload.get("settings", {}) as Dictionary

func user_settings_exist(username: String) -> bool:
	if username.is_empty():
		return false
	return FileAccess.file_exists(_save_root + username + "/" + USER_FILENAME)

# ============================================================
# 旧配置检测
# ============================================================
## 检测是否存在旧版配置文件
## 返回找到的旧文件路径列表
func detect_legacy_files() -> Array[String]:
	var found: Array[String] = []
	# 检查 user:// 目录下的旧文件
	for filename in LEGACY_FILES:
		var user_path: String = "user://" + filename
		if FileAccess.file_exists(user_path):
			found.append(user_path)
	# 也检查 saves 目录下
	for filename in LEGACY_FILES:
		var save_path: String = _save_root + filename
		if FileAccess.file_exists(save_path):
			found.append(save_path)
	return found

## 生成旧配置不兼容的提示文本（BBCode）
func get_legacy_warning(legacy_files: Array[String], theme) -> String:
	if legacy_files.is_empty():
		return ""
	var w: String = str(theme.warning_hex) if theme else "#FFFF00"
	var m: String = str(theme.muted_hex) if theme else "#888888"
	var e: String = str(theme.error_hex) if theme else "#FF4444"
	var text: String = ""
	text += "[color=" + w + "]⚠ 检测到旧版配置文件：[/color]\n"
	for f in legacy_files:
		text += "  [color=" + m + "]" + f + "[/color]\n"
	text += "[color=" + w + "]旧版配置与新设置系统不兼容。[/color]\n"
	text += "[color=" + m + "]请通过 [/color][color=" + e + "]settings[/color][color=" + m + "] 命令重新配置，或手动删除上述旧文件。[/color]\n"
	return text

# ============================================================
# 内部工具
# ============================================================
func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[SettingsStorage] 无法写入: " + path + " 错误: " + str(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[SettingsStorage] JSON 解析失败: " + path)
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

func _get_timestamp() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]
