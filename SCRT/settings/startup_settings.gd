extends RefCounted
## 封面与主游戏共用的只读启动设置；不创建账号、不写设置、不增加封面设置页。

const Registry := preload("res://settings/settings_registry.gd")
const Storage := preload("res://settings/settings_storage.gd")
const KEYS := ["audio.master_volume", "audio.ambient_volume", "effect.level", "effect.photosensitive"]

static func load_values(save_root: String) -> Dictionary:
	var values: Dictionary = {}
	for definition in Registry.get_settings():
		if definition["key"] in KEYS:
			values[definition["key"]] = definition["default"]
	var saved: Dictionary = {}
	var path: String = save_root.path_join(Storage.GLOBAL_FILENAME)
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and int(parsed.get("version", 0)) == Storage.SETTINGS_VERSION and parsed.get("settings") is Dictionary:
			saved = parsed["settings"]
	# 旧版 fx_level/fx_safe 的配置在没有新版键时仍有效，迁移只读取。
	var legacy := ConfigFile.new()
	if legacy.load(save_root.path_join("effect_settings.cfg")) == OK:
		if not saved.has("effect.level"):
			var level: int = clampi(int(legacy.get_value("effects", "effect_level", 0)), 0, 2)
			values["effect.level"] = ["full", "mild", "off"][level]
		if not saved.has("effect.photosensitive"):
			values["effect.photosensitive"] = bool(legacy.get_value("effects", "photosensitive_mode", false))
	for key in KEYS:
		var value: Variant = saved.get(key)
		if key.begins_with("audio.") and (value is float or value is int):
			values[key] = clampf(float(value), 0.0, 1.0)
		elif key == "effect.level" and value is String and value in ["full", "mild", "off"]:
			values[key] = value
		elif key == "effect.photosensitive" and value is bool:
			values[key] = value
	return values

static func apply_master(volume: float) -> void:
	var bus: int = AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.0001, clampf(volume, 0.0, 1.0))))
		AudioServer.set_bus_mute(bus, volume <= 0.0)
