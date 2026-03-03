# ============================================================
# daily_dialogue_manager.gd
# 每日剧情对话管理器 —— 根据当前天数自动触发通讯对话
#
# 数据来源：
#   1. res://data/main/manifest.json（内置主线剧情）
#   2. .scp 故事包 manifest 中的 daily_dialogues 段（覆盖/追加）
#
# 触发时机：
#   - on_start:        每天加载时自动触发
#   - on_scan_complete: env scan 完成后触发
#   - on_anomaly:       检测到异常时触发
# ============================================================
class_name DailyDialogueManager
extends RefCounted

var main = null
var _daily_config: Dictionary = {}  # day_number(str) -> {on_start, on_scan_complete, on_anomaly}
var _dialogues: Dictionary = {}     # dialogue_id -> dialogue_data
var _characters: Dictionary = {}    # character_id -> character_config
var _triggered_today: Dictionary = {} # 记录今天已触发的事件类型，防止重复

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main) -> void:
	main = p_main
	_load_main_storyline()

func _load_main_storyline() -> void:
	var path: String = "res://data/main/manifest.json"
	if not FileAccess.file_exists(path):
		print("[DailyDialogue] 主线剧情文件不存在: " + path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or not (json.data is Dictionary):
		push_warning("[DailyDialogue] 主线剧情 JSON 解析失败")
		return
	f.close()
	var data: Dictionary = json.data
	# 加载每日对话配置
	_daily_config = data.get("daily_dialogues", {})
	# 加载对话定义
	var dlgs: Dictionary = data.get("comm_dialogues", {})
	for dlg_id in dlgs.keys():
		_dialogues[dlg_id] = dlgs[dlg_id]
	# 加载角色定义
	_characters = data.get("comm_characters", {})
	# 扫描 dialogues 子目录加载扩展对话文件
	_load_dialogue_extensions("res://data/main/dialogues/")
	print("[DailyDialogue] 主线剧情加载完成: %d 天配置, %d 对话" % [_daily_config.size(), _dialogues.size()])

func _load_dialogue_extensions(dir_path: String) -> void:
	## 扫描目录下的所有 .json 文件，追加对话和天配置
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path: String = dir_path + file_name
			var f := FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var json := JSON.new()
				if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
					var ext_data: Dictionary = json.data
					# 追加每日对话配置
					var ext_daily: Dictionary = ext_data.get("daily_dialogues", {})
					for day_key in ext_daily.keys():
						if not _daily_config.has(day_key):
							_daily_config[day_key] = ext_daily[day_key]
					# 追加对话定义
					var ext_dlgs: Dictionary = ext_data.get("comm_dialogues", {})
					for dlg_id in ext_dlgs.keys():
						if not _dialogues.has(dlg_id):
							_dialogues[dlg_id] = ext_dlgs[dlg_id]
					# 追加角色定义
					var ext_chars: Dictionary = ext_data.get("comm_characters", {})
					for char_id in ext_chars.keys():
						if not _characters.has(char_id):
							_characters[char_id] = ext_chars[char_id]
				f.close()
		file_name = dir.get_next()
	dir.list_dir_end()

# ══════════════════════════════════════════
#  故事包覆盖
# ══════════════════════════════════════════
func load_from_manifest(manifest: Dictionary) -> void:
	# 故事包可以追加/覆盖每日对话配置
	var story_daily: Dictionary = manifest.get("daily_dialogues", {})
	for day_key in story_daily.keys():
		_daily_config[day_key] = story_daily[day_key]
	# 故事包的 comm_dialogues 也可以包含每日对话
	var story_dlgs: Dictionary = manifest.get("comm_dialogues", {})
	for dlg_id in story_dlgs.keys():
		_dialogues[dlg_id] = story_dlgs[dlg_id]
	var story_chars: Dictionary = manifest.get("comm_characters", {})
	for char_id in story_chars.keys():
		_characters[char_id] = story_chars[char_id]

# ══════════════════════════════════════════
#  注册对话到 CommManager
# ══════════════════════════════════════════
func register_dialogues_to_comm() -> void:
	if main == null or main.comm_mgr == null:
		return
	# 注册角色
	for char_id in _characters.keys():
		if not main.comm_mgr._characters.has(char_id):
			var char_config: Dictionary = _characters[char_id].duplicate()
			char_config["id"] = char_id
			var character = CommCharacter.new()
			character.load_from_config(char_config, null)
			main.comm_mgr._characters[char_id] = character
	# 注册对话
	for dlg_id in _dialogues.keys():
		main.comm_mgr._dialogues[dlg_id] = _dialogues[dlg_id]

# ══════════════════════════════════════════
#  触发接口
# ══════════════════════════════════════════
func trigger_day_start(day: int) -> void:
	## 每天开始时调用
	_triggered_today.clear()
	register_dialogues_to_comm()
	var dlg_ids: Array = _get_trigger_list(day, "on_start")
	if dlg_ids.size() > 0 and not _triggered_today.has("on_start"):
		_triggered_today["on_start"] = true
		_trigger_dialogues(dlg_ids)

func trigger_scan_complete(day: int) -> void:
	## env scan 完成后调用
	var dlg_ids: Array = _get_trigger_list(day, "on_scan_complete")
	if dlg_ids.size() > 0 and not _triggered_today.has("on_scan_complete"):
		_triggered_today["on_scan_complete"] = true
		_trigger_dialogues(dlg_ids)

func trigger_anomaly(day: int) -> void:
	## 检测到异常时调用
	var dlg_ids: Array = _get_trigger_list(day, "on_anomaly")
	if dlg_ids.size() > 0 and not _triggered_today.has("on_anomaly"):
		_triggered_today["on_anomaly"] = true
		_trigger_dialogues(dlg_ids)

# ══════════════════════════════════════════
#  存档
# ══════════════════════════════════════════
func get_save_data() -> Dictionary:
	return {
		"triggered_today": _triggered_today.duplicate(),
	}

func load_save_data(data: Dictionary) -> void:
	if data.has("triggered_today"):
		_triggered_today = data["triggered_today"]

# ══════════════════════════════════════════
#  内部
# ══════════════════════════════════════════
func _get_trigger_list(day: int, event_type: String) -> Array:
	var day_key: String = str(day)
	var config: Dictionary = {}
	if _daily_config.has(day_key):
		config = _daily_config[day_key]
	elif _daily_config.has("default"):
		config = _daily_config["default"]
	return config.get(event_type, [])

func _trigger_dialogues(dlg_ids: Array) -> void:
	if main == null or main.comm_mgr == null:
		return
	if dlg_ids.size() == 0:
		return
	# 过滤掉已完成且不可重复的对话
	var valid_ids: Array = []
	for dlg_id in dlg_ids:
		var sid: String = str(dlg_id)
		if main.comm_mgr._dialogues.has(sid):
			var dlg_data: Dictionary = main.comm_mgr._dialogues[sid]
			var repeatable: bool = dlg_data.get("repeatable", false)
			if repeatable or not main.comm_mgr._completed_dialogues.has(sid):
				valid_ids.append(sid)
	if valid_ids.size() == 0:
		return
	if valid_ids.size() == 1:
		# 延迟触发，确保 UI 已就绪
		main.get_tree().create_timer(1.5).timeout.connect(func():
			main.comm_mgr.trigger_dialogue(valid_ids[0])
		)
	else:
		main.get_tree().create_timer(1.5).timeout.connect(func():
			main.comm_mgr.trigger_dialogue_sequence(valid_ids)
		)
