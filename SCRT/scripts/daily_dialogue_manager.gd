# ============================================================
# daily_dialogue_manager.gd
# 每日剧情对话管理器 —— 根据当前天数自动触发通讯对话
#
# 数据来源：
#   1. res://data/main/manifest.json（内置主线剧情）
#   2. .scp 故事包 manifest 中的 daily_dialogues 段（覆盖/追加）
#
# 触发时机：
#   - on_start:        每天登录后自动触发
#   - on_scan_complete: env scan 完成后触发
#   - on_anomaly:       检测到异常时触发
#   - on_mail_read:     阅读特定邮件后触发
#   - on_command:       执行特定命令后触发
#
# 存档位置：
#   saves/{username}/story_progress.json（独立于磁盘存档）
# ============================================================
class_name DailyDialogueManager
extends RefCounted

var main = null
var _daily_config: Dictionary = {}  # day_number(str) -> {on_start, on_scan_complete, on_anomaly, ...}
var _dialogues: Dictionary = {}     # dialogue_id -> dialogue_data
var _characters: Dictionary = {}    # character_id -> character_config
var _triggered_today: Dictionary = {} # 记录今天已触发的事件类型，防止重复

# ★ 主线剧情进度（独立存档，不绑定磁盘）
var _story_day: int = 1             # 当前主线天数
var _completed_dialogues: Array[String] = []  # 已完成的对话 ID 列表
var _story_choices: Dictionary = {} # 关键剧情选项记录 {choice_id: selected_option}
var _story_flags: Dictionary = {}   # 剧情标记 {flag_name: value}

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════
func setup(p_main) -> void:
	main = p_main
	# ★ 不在初始化时加载主线剧情，改为登录后加载

func load_main_storyline() -> void:
	## 由 main.gd 在登录后调用，加载主线剧情配置
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
	# 注册角色（通过 registry API）
	var registry: CharacterRegistry = main.comm_mgr.get_registry()
	for char_id in _characters.keys():
		if registry and not registry.has_character(char_id):
			var char_config: Dictionary = _characters[char_id].duplicate()
			registry.register_character(char_id, char_config, CharacterRegistry.CharacterSource.BUILTIN)
	# 注册对话（通过公共 API）
	for dlg_id in _dialogues.keys():
		if not main.comm_mgr.get_dialogue_ids().has(dlg_id):
			main.comm_mgr.register_mod_dialogue(dlg_id, _dialogues[dlg_id])

# ══════════════════════════════════════════
#  触发接口
# ══════════════════════════════════════════
func trigger_day_start(day: int) -> void:
	## 每天登录时调用（与磁盘加载无关）
	_story_day = day
	_triggered_today.clear()
	register_dialogues_to_comm()
	# ★ 处理当日邮件投递
	_deliver_day_mails(day)
	# ★ 执行当日触发器动作（radio_update 等）
	_execute_day_actions(day)
	var dlg_ids: Array = _get_trigger_list(day, "on_start")
	if dlg_ids.size() > 0 and not _triggered_today.has("on_start"):
		_triggered_today["on_start"] = true
		_trigger_dialogues(dlg_ids)

## ★ 执行每日触发器动作（如 radio_update、radio_visible 等）
func _execute_day_actions(day: int) -> void:
	var day_key: String = str(day)
	var config: Dictionary = _daily_config.get(day_key, _daily_config.get("default", {})) as Dictionary
	var actions: Array = []
	var raw = config.get("on_start_actions", [])
	if raw is Array:
		actions = raw
	if actions.is_empty():
		return
	if main.trigger_sys == null:
		return
	for action in actions:
		main.trigger_sys._execute(str(action), {})

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

func trigger_mail_read(day: int, mail_id: String) -> void:
	## 阅读特定邮件后调用
	var dlg_ids: Array = _get_trigger_list(day, "on_mail_read")
	# 过滤出 mail_id 匹配的对话
	var matched: Array = []
	for dlg_id in dlg_ids:
		var dlg_data: Dictionary = _dialogues.get(str(dlg_id), {})
		var req_mail: String = str(dlg_data.get("requires_mail", ""))
		if req_mail.is_empty() or req_mail == mail_id:
			matched.append(dlg_id)
	var trigger_key: String = "on_mail_read:" + mail_id
	if matched.size() > 0 and not _triggered_today.has(trigger_key):
		_triggered_today[trigger_key] = true
		_trigger_dialogues(matched)

func trigger_command(day: int, cmd_name: String) -> void:
	## 执行特定命令后调用
	var dlg_ids: Array = _get_trigger_list(day, "on_command")
	var matched: Array = []
	for dlg_id in dlg_ids:
		var dlg_data: Dictionary = _dialogues.get(str(dlg_id), {})
		var req_cmd: String = str(dlg_data.get("requires_command", ""))
		if req_cmd.is_empty() or req_cmd == cmd_name:
			matched.append(dlg_id)
	var trigger_key: String = "on_command:" + cmd_name
	if matched.size() > 0 and not _triggered_today.has(trigger_key):
		_triggered_today[trigger_key] = true
		_trigger_dialogues(matched)

# ══════════════════════════════════════════
#  剧情选项记录
# ══════════════════════════════════════════
func record_choice(choice_id: String, selected_option: String) -> void:
	## 记录玩家的关键剧情选择
	_story_choices[choice_id] = selected_option
	save_story_save()

func get_choice(choice_id: String, default: String = "") -> String:
	## 查询某个剧情选择
	return str(_story_choices.get(choice_id, default))

func has_choice(choice_id: String) -> bool:
	return _story_choices.has(choice_id)

# ══════════════════════════════════════════
#  剧情标记（通用 flag 系统）
# ══════════════════════════════════════════
func set_flag(flag_name: String, value: Variant = true) -> void:
	_story_flags[flag_name] = value
	save_story_save()

func get_flag(flag_name: String, default: Variant = null) -> Variant:
	return _story_flags.get(flag_name, default)

func has_flag(flag_name: String) -> bool:
	return _story_flags.has(flag_name)

# ══════════════════════════════════════════
#  独立存档（保存到 saves/{username}/story_progress.json）
# ══════════════════════════════════════════
func _get_save_path() -> String:
	if main == null or main.user_mgr == null or not main.user_mgr.is_logged_in:
		return ""
	if main.save_mgr == null:
		return ""
	var user_dir: String = main.save_mgr.get_game_root_dir() + "saves/" + main.user_mgr.get_username() + "/"
	return user_dir + "story_progress.json"

func save_story_save() -> void:
	## 保存主线剧情进度到独立文件
	var path: String = _get_save_path()
	if path.is_empty():
		return
	# 确保目录存在
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var save_data: Dictionary = {
		"story_day": _story_day,
		"triggered_today": _triggered_today.duplicate(),
		"completed_dialogues": _completed_dialogues.duplicate(),
		"story_choices": _story_choices.duplicate(),
		"story_flags": _story_flags.duplicate(),
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()

func load_story_save() -> void:
	## 从独立文件加载主线剧情进度
	var path: String = _get_save_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		file.close()
		return
	file.close()
	var data: Dictionary = json.data
	_story_day = int(data.get("story_day", 1))
	if data.has("triggered_today"):
		_triggered_today = data["triggered_today"]
	if data.has("completed_dialogues"):
		_completed_dialogues.clear()
		for d in data["completed_dialogues"]:
			_completed_dialogues.append(str(d))
	if data.has("story_choices"):
		_story_choices = data["story_choices"]
	if data.has("story_flags"):
		_story_flags = data["story_flags"]
	print("[DailyDialogue] 主线存档已加载: day=%d, choices=%d, flags=%d" % [_story_day, _story_choices.size(), _story_flags.size()])

# ══════════════════════════════════════════
#  兼容旧存档（disc_manager 调用的接口保留）
# ══════════════════════════════════════════
func get_save_data() -> Dictionary:
	return {
		"triggered_today": _triggered_today.duplicate(),
		"story_day": _story_day,
		"completed_dialogues": _completed_dialogues.duplicate(),
		"story_choices": _story_choices.duplicate(),
		"story_flags": _story_flags.duplicate(),
	}

func load_save_data(data: Dictionary) -> void:
	if data.has("triggered_today"):
		_triggered_today = data["triggered_today"]
	if data.has("story_day"):
		_story_day = int(data["story_day"])
	if data.has("completed_dialogues"):
		_completed_dialogues.clear()
		for d in data["completed_dialogues"]:
			_completed_dialogues.append(str(d))
	if data.has("story_choices"):
		_story_choices = data["story_choices"]
	if data.has("story_flags"):
		_story_flags = data["story_flags"]

# ══════════════════════════════════════════
#  内部
# ══════════════════════════════════════════
func _deliver_day_mails(day: int) -> void:
	## 投递当日配置中的邮件（mail_deliveries 字段）
	if main.mail_sys == null:
		return
	var day_key: String = str(day)
	var config: Dictionary = {}
	if _daily_config.has(day_key):
		config = _daily_config[day_key]
	elif _daily_config.has("default"):
		config = _daily_config["default"]
	var mails: Array = config.get("mail_deliveries", [])
	for mail_def in mails:
		if not (mail_def is Dictionary):
			continue
		var mail_id: String = str(mail_def.get("id", ""))
		if mail_id.is_empty():
			continue
		var title: String = str(mail_def.get("title", mail_id))
		var from: String = str(mail_def.get("from", "SYSTEM"))
		var body: String = str(mail_def.get("body", ""))
		var persistent: bool = bool(mail_def.get("persistent", true))
		main.mail_sys.deliver_inline_mail(mail_id, title, from, body, persistent)

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
	# 过滤掉已完成且不可重复的对话，以及条件不满足的对话
	var valid_ids: Array = []
	for dlg_id in dlg_ids:
		var sid: String = str(dlg_id)
		if main.comm_mgr.has_dialogue(sid):
			var dlg_data: Dictionary = main.comm_mgr.get_dialogue_data(sid)
			var repeatable: bool = dlg_data.get("repeatable", false)
			if not repeatable and sid in _completed_dialogues:
				continue
			if not repeatable and main.comm_mgr.is_dialogue_completed(sid):
				continue
			# ★ 检查前置条件（需要某个选项或标记）
			if not _check_conditions(dlg_data):
				continue
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

func _check_conditions(dlg_data: Dictionary) -> bool:
	## 检查对话的前置条件是否满足
	# requires_choice: {"choice_id": "expected_value"}
	var req_choice: Dictionary = dlg_data.get("requires_choice", {})
	for choice_id in req_choice.keys():
		if get_choice(choice_id) != str(req_choice[choice_id]):
			return false
	# requires_flag: {"flag_name": expected_value}
	var req_flag: Dictionary = dlg_data.get("requires_flag", {})
	for flag_name in req_flag.keys():
		if not has_flag(flag_name):
			return false
		# 简单值比较
		var expected = req_flag[flag_name]
		var actual = get_flag(flag_name)
		if str(actual) != str(expected):
			return false
	return true

func mark_dialogue_completed(dlg_id: String) -> void:
	if dlg_id not in _completed_dialogues:
		_completed_dialogues.append(dlg_id)
		save_story_save()
