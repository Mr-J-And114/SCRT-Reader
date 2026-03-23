# ============================================================
# radio_data_manager.gd - 本地无线电数据管理器
# 负责：管理 data/radio/ 文件夹下的信号定义 JSON 和资源文件
# ============================================================
class_name RadioDataManager
extends RefCounted

var main = null
var _radio_dir: String = ""

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main) -> void:
	main = p_main
	_radio_dir = _get_radio_data_path()
	_ensure_radio_dir()

## 获取 data/radio/ 的绝对路径
func _get_radio_data_path() -> String:
	var root: String = ""
	if OS.has_feature("editor"):
		root = ProjectSettings.globalize_path("res://")
	else:
		root = OS.get_executable_path().get_base_dir() + "/"
	return root + "data/radio/"

## 确保目录存在
func _ensure_radio_dir() -> void:
	if not DirAccess.dir_exists_absolute(_radio_dir):
		var err := DirAccess.make_dir_recursive_absolute(_radio_dir)
		if err != OK:
			push_warning("[RadioDataManager] 无法创建 radio 目录: " + _radio_dir)

## 获取 radio 目录路径
func get_radio_dir() -> String:
	return _radio_dir

# ══════════════════════════════════════════
#  扫描与加载
# ══════════════════════════════════════════

## 扫描 data/radio/ 下所有 .json 文件，返回可见信号的解析结果
func scan_signals() -> Array:
	var signals: Array = []
	var dir := DirAccess.open(_radio_dir)
	if dir == null:
		return signals

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "json":
			var sig := _load_signal_from_file(_radio_dir + file_name)
			if sig != null:
				signals.append(sig)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("[RadioDataManager] 扫描完成，共 %d 个可见信号" % signals.size())
	return signals

## 从单个 JSON 文件加载信号定义
func _load_signal_from_file(path: String) -> RadioConfigParser.RadioSignal:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		push_warning("[RadioDataManager] 无法读取: " + path)
		return null

	var text: String = fa.get_as_text()
	fa.close()

	var json := JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		push_warning("[RadioDataManager] JSON 解析失败: " + path + " - " + json.get_error_message())
		return null

	var data: Dictionary = json.data as Dictionary
	if data == null:
		return null

	# 检查 visible 字段（默认为 true）
	var visible: bool = bool(data.get("visible", true))
	if not visible:
		return null

	var sig := RadioConfigParser.RadioSignal.new()
	sig.id = str(data.get("id", path.get_file().get_basename()))
	RadioConfigParser._apply_manifest_entry(sig, data)

	# 从本地文件系统加载资源内容
	if not sig.content_file.is_empty():
		_load_content_from_local(sig)

	return sig

## 从本地文件系统加载信号资源（音频/图片/文本）
func _load_content_from_local(sig: RadioConfigParser.RadioSignal) -> void:
	var content_path: String = sig.content_file
	# 相对路径：相对于 data/radio/
	if not content_path.is_absolute_path():
		content_path = _radio_dir + content_path

	if not FileAccess.file_exists(content_path):
		push_warning("[RadioDataManager] 资源文件不存在: " + content_path)
		return

	match sig.type:
		"morse":
			var fa := FileAccess.open(content_path, FileAccess.READ)
			if fa != null:
				sig.content_text = fa.get_as_text()
				fa.close()
		"sstv":
			var fa := FileAccess.open(content_path, FileAccess.READ)
			if fa != null:
				sig.content_image = fa.get_buffer(fa.get_length())
				fa.close()
		"audio":
			var fa := FileAccess.open(content_path, FileAccess.READ)
			if fa != null:
				sig.content_audio = fa.get_buffer(fa.get_length())
				fa.close()

# ══════════════════════════════════════════
#  写入与修改
# ══════════════════════════════════════════

## 读取信号 JSON 原始数据（不过滤 visible）
func _read_signal_json(signal_id: String) -> Dictionary:
	var path: String = _radio_dir + signal_id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return {}
	var text: String = fa.get_as_text()
	fa.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	if json.data is Dictionary:
		return json.data as Dictionary
	return {}

## 写入信号 JSON 数据
func _write_signal_json(signal_id: String, data: Dictionary) -> bool:
	var path: String = _radio_dir + signal_id + ".json"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		push_warning("[RadioDataManager] 无法写入: " + path)
		return false
	fa.store_string(JSON.stringify(data, "\t"))
	fa.close()
	return true

## 设置信号的 visible 字段
func set_signal_visible(signal_id: String, visible: bool) -> bool:
	var data: Dictionary = _read_signal_json(signal_id)
	if data.is_empty():
		push_warning("[RadioDataManager] 信号不存在: " + signal_id)
		return false
	data["visible"] = visible
	return _write_signal_json(signal_id, data)

## 更新信号的任意字段
func update_signal_field(signal_id: String, field: String, value: String) -> bool:
	var data: Dictionary = _read_signal_json(signal_id)
	if data.is_empty():
		push_warning("[RadioDataManager] 信号不存在: " + signal_id)
		return false

	# 尝试解析为合适的类型
	data[field] = _parse_value(value)
	return _write_signal_json(signal_id, data)

## 删除信号定义文件
func delete_signal(signal_id: String) -> bool:
	var path: String = _radio_dir + signal_id + ".json"
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	return err == OK

# ══════════════════════════════════════════
#  从 vdisc 导入
# ══════════════════════════════════════════

## 从 vdisc 的 manifest/fs 导入信号定义和资源到 data/radio/
## signal_ids: 要导入的信号 ID 列表，传空数组则导入全部
func import_from_vdisc(manifest: Dictionary, fs, signal_ids: Array = []) -> int:
	var imported: int = 0

	# 解析 vdisc 中的信号（不过滤，全部解析）
	var vdisc_signals: Array = RadioConfigParser.parse_signals_from_manifest(manifest, fs)
	if vdisc_signals.is_empty():
		vdisc_signals = RadioConfigParser.parse_signals(fs)

	for sig_item in vdisc_signals:
		var sig: RadioConfigParser.RadioSignal = sig_item as RadioConfigParser.RadioSignal
		if sig == null:
			continue

		# 如果指定了 ID 列表，只导入列表中的
		if not signal_ids.is_empty() and sig.id not in signal_ids:
			continue

		# 构建 JSON 数据
		var data: Dictionary = _signal_to_dict(sig)
		data["visible"] = true

		# 导出资源文件
		if not sig.content_file.is_empty():
			var res_name: String = sig.content_file.get_file()
			# 复制资源到 data/radio/
			var copied: bool = false
			match sig.type:
				"morse":
					if not sig.content_text.is_empty():
						var fa := FileAccess.open(_radio_dir + res_name, FileAccess.WRITE)
						if fa != null:
							fa.store_string(sig.content_text)
							fa.close()
							copied = true
				"sstv":
					if not sig.content_image.is_empty():
						var fa := FileAccess.open(_radio_dir + res_name, FileAccess.WRITE)
						if fa != null:
							fa.store_buffer(sig.content_image)
							fa.close()
							copied = true
				"audio":
					if not sig.content_audio.is_empty():
						var fa := FileAccess.open(_radio_dir + res_name, FileAccess.WRITE)
						if fa != null:
							fa.store_buffer(sig.content_audio)
							fa.close()
							copied = true

			if copied:
				data["content_file"] = res_name

		# 写入 JSON 定义
		if _write_signal_json(sig.id, data):
			imported += 1

	print("[RadioDataManager] 从 vdisc 导入了 %d 个信号" % imported)
	return imported

## 将 RadioSignal 转换为 Dictionary（用于 JSON 序列化）
func _signal_to_dict(sig: RadioConfigParser.RadioSignal) -> Dictionary:
	var d: Dictionary = {}
	d["id"] = sig.id
	d["type"] = sig.type
	d["frequency"] = sig.frequency
	d["band"] = sig.band
	d["azimuth"] = sig.azimuth
	d["elevation"] = sig.elevation
	d["tolerance_freq"] = sig.tolerance_freq
	d["tolerance_dir"] = sig.tolerance_dir
	d["content_file"] = sig.content_file
	d["loop"] = sig.loop
	d["speed_wpm"] = sig.speed_wpm
	d["label"] = sig.label
	d["hint"] = sig.hint
	d["sstv_mode"] = sig.sstv_mode
	d["transmit_duration"] = sig.transmit_duration
	d["character_set"] = sig.character_set
	d["ephemeral"] = sig.ephemeral
	d["reappear_interval"] = sig.reappear_interval
	d["discovered_flag"] = sig.discovered_flag
	d["beacon_id"] = sig.beacon_id
	d["cipher_type"] = sig.cipher_type
	d["cipher_key_file"] = sig.cipher_key_file
	d["group_size"] = sig.group_size
	d["group_pause_ms"] = sig.group_pause_ms
	d["repeat_count"] = sig.repeat_count
	d["hidden"] = sig.hidden
	d["proximity_range"] = sig.proximity_range
	return d

## 自动类型解析（字符串 → 合适的类型）
func _parse_value(value: String) -> Variant:
	# bool
	if value.to_lower() == "true":
		return true
	if value.to_lower() == "false":
		return false
	# int（纯数字无小数点）
	if value.is_valid_int():
		return value.to_int()
	# float
	if value.is_valid_float():
		return value.to_float()
	# 字符串
	return value
